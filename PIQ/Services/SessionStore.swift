import Foundation

// MARK: - ClaudeStats

struct DailyActivity: Identifiable, Sendable {
    var id: String { date }
    let date: String           // "2026-02-14"
    let messageCount: Int
}

struct ModelStats: Identifiable, Sendable {
    var id: String { model }
    let model: String          // "claude-opus-4-6"
    let displayName: String    // "Opus 4.6"
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    var totalTokens: Int { inputTokens + outputTokens }
}

struct ClaudeStats: Sendable {
    let totalSessions: Int
    let totalMessages: Int
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCacheReadTokens: Int
    let totalCacheCreationTokens: Int

    let firstSessionDate: Date?
    let longestSessionMessages: Int
    let longestSessionDuration: TimeInterval
    let hourCounts: [Int: Int]
    let dailyActivity: [DailyActivity]
    let modelBreakdown: [ModelStats]

    /// Actual API tokens (excluding cache)
    var totalTokens: Int { totalInputTokens + totalOutputTokens }
}

// MARK: - SessionIndex (Persistent Cache)

struct SessionIndex: Codable, Sendable {
    struct CachedEntry: Codable, Sendable {
        let mtime: Date
        let entry: SessionEntry
    }
    var entries: [String: CachedEntry] = [:]  // key = file path

    private static let indexURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/session-index.json")
    }()

    static func load() -> SessionIndex {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(SessionIndex.self, from: data) else {
            return SessionIndex()
        }
        return index
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }

    func cachedEntry(for path: String, mtime: Date) -> SessionEntry? {
        guard let cached = entries[path], cached.mtime == mtime else { return nil }
        return cached.entry
    }

    mutating func update(path: String, mtime: Date, entry: SessionEntry) {
        entries[path] = CachedEntry(mtime: mtime, entry: entry)
    }

    mutating func removeStaleEntries(keeping validPaths: Set<String>) {
        entries = entries.filter { validPaths.contains($0.key) }
    }
}

// MARK: - ScanProgress

struct ScanProgress: Equatable, Sendable {
    let message: String
    let completed: Int?
    let total: Int?
}

// MARK: - SessionStore

/// Central state manager for Claude Code sessions.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SessionEntry] = []
    private(set) var isLoading = false
    private(set) var scanProgress: ScanProgress?
    private(set) var stats: ClaudeStats?
    private var fileWatcher: SessionFileWatcher?
    private var sessionIndex = SessionIndex()

    /// Currently loaded session detail (turns for the selected session).
    private(set) var loadedTurns: [SessionTurn] = []
    private(set) var loadedSessionId: String?
    private(set) var isLoadingDetail = false

    // MARK: - Scan Types

    private struct ScanResult: Sendable {
        let allEntries: [SessionEntry]
        let updatedIndex: SessionIndex
        let changedDirs: Set<URL>
        let changedFiles: Set<URL>
        let hasChanges: Bool
    }

    private struct FileToParse: Sendable {
        let file: URL
        let path: String
        let mtime: Date?
        let projectDir: URL
    }

    private struct ParseResult: Sendable {
        let file: URL
        let path: String
        let mtime: Date?
        let projectDir: URL
        let entry: SessionEntry?
    }

    // MARK: - Scanning

    /// Full rescan of all session files (runs IO on background thread).
    func rescan() {
        isLoading = true
        scanProgress = nil
        var index = sessionIndex
        if index.entries.isEmpty {
            index = SessionIndex.load()
        }
        Task.detached(priority: .userInitiated) { [index] in
            let result = await Self.scanWithIndex(index) { progress in
                await MainActor.run {
                    self.scanProgress = progress
                }
            }
            let deduped = SessionScanner.deduplicateSessions(result.allEntries)
            let newStats = self.loadStats()
            result.updatedIndex.save()
            await MainActor.run {
                self.sessions = deduped
                self.sessionIndex = result.updatedIndex
                self.stats = newStats
                self.scanProgress = nil
                self.isLoading = false
            }
        }
    }

    /// Incremental update: only re-parse files whose mtime changed.
    /// All file I/O runs on a background thread; only final state assignment is on MainActor.
    func incrementalUpdate() {
        let index = sessionIndex
        let loadedId = loadedSessionId

        Task.detached(priority: .userInitiated) { [index] in
            let result = await Self.scanWithIndex(index)

            guard result.hasChanges else { return }

            let deduped = SessionScanner.incrementalDedup(
                allSessions: result.allEntries,
                changedDirs: result.changedDirs
            )
            let newStats = self.loadStats()
            result.updatedIndex.save()

            // Check if loaded session needs detail refresh
            var detailEntry: SessionEntry?
            if let loadedId,
               let entry = deduped.first(where: { $0.id == loadedId }),
               result.changedFiles.contains(entry.jsonlURL) {
                detailEntry = entry
            }

            await MainActor.run {
                self.sessions = deduped
                self.sessionIndex = result.updatedIndex
                self.stats = newStats

                if let entry = detailEntry {
                    Task {
                        await self.loadSessionDetail(entry: entry)
                    }
                }
            }
        }
    }

    // MARK: - Unified Scan Logic

    private nonisolated static func scanWithIndex(
        _ index: SessionIndex,
        onProgress: (@Sendable (ScanProgress) async -> Void)? = nil
    ) async -> ScanResult {
        let projectDirs = SessionScanner.discoverProjects()
        var updatedIndex = index
        var allEntries: [SessionEntry] = []
        var changedDirs = Set<URL>()
        var changedFiles = Set<URL>()
        var hasChanges = false
        var seenPaths = Set<String>()
        var filesToParse: [FileToParse] = []

        await onProgress?(ScanProgress(message: "Discovering sessions...", completed: nil, total: nil))

        for projectDir in projectDirs {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let jsonlFiles = contents.filter {
                $0.pathExtension == "jsonl" && !$0.lastPathComponent.hasPrefix("agent-")
            }

            for file in jsonlFiles {
                let path = file.path(percentEncoded: false)
                seenPaths.insert(path)

                let newMtime = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate

                // Try cache first
                if let mtime = newMtime, let cached = updatedIndex.cachedEntry(for: path, mtime: mtime) {
                    allEntries.append(cached)
                    continue
                }

                // Cache miss — queue for concurrent parse
                filesToParse.append(FileToParse(file: file, path: path, mtime: newMtime, projectDir: projectDir))
            }
        }

        // Parse cache-miss files concurrently
        if !filesToParse.isEmpty {
            let total = filesToParse.count
            await onProgress?(ScanProgress(message: "Parsing sessions 0/\(total)...", completed: 0, total: total))

            var parsed = 0
            await withTaskGroup(of: ParseResult.self) { group in
                for item in filesToParse {
                    group.addTask {
                        let entry = SessionParser.extractMetadata(from: item.file)
                        return ParseResult(file: item.file, path: item.path, mtime: item.mtime, projectDir: item.projectDir, entry: entry)
                    }
                }

                for await result in group {
                    parsed += 1
                    if parsed == 1 || parsed % 5 == 0 || parsed == total {
                        await onProgress?(ScanProgress(message: "Parsing sessions \(parsed)/\(total)...", completed: parsed, total: total))
                    }

                    if let entry = result.entry {
                        allEntries.append(entry)
                        if let mtime = result.mtime {
                            updatedIndex.update(path: result.path, mtime: mtime, entry: entry)
                        }
                        changedDirs.insert(result.projectDir)
                        changedFiles.insert(result.file)
                        hasChanges = true
                    } else if result.mtime != nil {
                        updatedIndex.entries.removeValue(forKey: result.path)
                    }
                }
            }
        }

        // Remove stale entries for files that no longer exist
        let stalePaths = Set(updatedIndex.entries.keys).subtracting(seenPaths)
        if !stalePaths.isEmpty {
            for path in stalePaths {
                changedDirs.insert(URL(fileURLWithPath: path).deletingLastPathComponent())
            }
            updatedIndex.removeStaleEntries(keeping: seenPaths)
            hasChanges = true
        }

        return ScanResult(
            allEntries: allEntries,
            updatedIndex: updatedIndex,
            changedDirs: changedDirs,
            changedFiles: changedFiles,
            hasChanges: hasChanges
        )
    }

    // MARK: - Detail Loading

    /// Load full session detail (turns) for display.
    func loadSessionDetail(entry: SessionEntry) async {
        loadedSessionId = entry.id
        isLoadingDetail = true
        loadedTurns = []

        let url = entry.jsonlURL
        let sessionId = entry.id
        let turns = await Task.detached(priority: .userInitiated) {
            let messages = SessionParser.parseFile(at: url)
            var turns = SessionParser.groupIntoTurns(messages)

            // Load agent conversations and attach to Task tool calls
            let agentMap = SessionParser.loadAgentTurns(
                sessionDir: url.deletingLastPathComponent(),
                sessionId: sessionId
            )
            if !agentMap.isEmpty {
                for i in turns.indices {
                    for j in turns[i].toolPairs.indices {
                        let pair = turns[i].toolPairs[j]
                        if pair.name == "Task",
                           let output = pair.output,
                           let agentId = SessionParser.extractAgentId(from: output),
                           let agentTurns = agentMap[agentId] {
                            turns[i].toolPairs[j].agentTurns = agentTurns
                        }
                    }
                }
            }

            return turns
        }.value

        // Only update if we're still viewing this session
        if loadedSessionId == entry.id {
            loadedTurns = turns
            isLoadingDetail = false
        }
    }

    /// Clear loaded detail.
    func clearDetail() {
        loadedTurns = []
        loadedSessionId = nil
        isLoadingDetail = false
    }

    // MARK: - Aggregate Stats

    /// Read aggregate stats from ~/.claude/stats-cache.json.
    nonisolated func loadStats() -> ClaudeStats? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/stats-cache.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let totalSessions = json["totalSessions"] as? Int ?? 0
        let totalMessages = json["totalMessages"] as? Int ?? 0

        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreation = 0
        var modelBreakdown: [ModelStats] = []
        if let modelUsage = json["modelUsage"] as? [String: [String: Any]] {
            for (model, usage) in modelUsage {
                let inp = usage["inputTokens"] as? Int ?? 0
                let out = usage["outputTokens"] as? Int ?? 0
                let cacheRead = usage["cacheReadInputTokens"] as? Int ?? 0
                let cacheCreate = usage["cacheCreationInputTokens"] as? Int ?? 0
                totalInput += inp
                totalOutput += out
                totalCacheRead += cacheRead
                totalCacheCreation += cacheCreate
                modelBreakdown.append(ModelStats(
                    model: model,
                    displayName: Self.modelDisplayName(model),
                    inputTokens: inp,
                    outputTokens: out,
                    cacheReadTokens: cacheRead,
                    cacheCreationTokens: cacheCreate
                ))
            }
        }
        modelBreakdown.sort { $0.totalTokens > $1.totalTokens }

        // firstSessionDate
        var firstDate: Date?
        if let dateStr = json["firstSessionDate"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            firstDate = formatter.date(from: dateStr)
        }

        // longestSession
        var longestMsgs = 0
        var longestDuration: TimeInterval = 0
        if let longest = json["longestSession"] as? [String: Any] {
            longestMsgs = longest["messageCount"] as? Int ?? 0
            longestDuration = longest["duration"] as? Double ?? 0
        }

        // hourCounts
        var hourCounts: [Int: Int] = [:]
        if let hours = json["hourCounts"] as? [String: Int] {
            for (key, value) in hours {
                if let hour = Int(key) {
                    hourCounts[hour] = value
                }
            }
        }

        // dailyActivity
        var dailyActivity: [DailyActivity] = []
        if let daily = json["dailyActivity"] as? [[String: Any]] {
            for entry in daily {
                if let date = entry["date"] as? String,
                   let count = entry["messageCount"] as? Int {
                    dailyActivity.append(DailyActivity(date: date, messageCount: count))
                }
            }
        }
        dailyActivity.sort { $0.date < $1.date }

        return ClaudeStats(
            totalSessions: totalSessions,
            totalMessages: totalMessages,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheCreationTokens: totalCacheCreation,
            firstSessionDate: firstDate,
            longestSessionMessages: longestMsgs,
            longestSessionDuration: longestDuration,
            hourCounts: hourCounts,
            dailyActivity: dailyActivity,
            modelBreakdown: modelBreakdown
        )
    }

    /// Convert model ID to a short display name.
    private nonisolated static func modelDisplayName(_ model: String) -> String {
        if model.contains("opus-4-6") { return "Opus 4.6" }
        if model.contains("opus-4-5") { return "Opus 4.5" }
        if model.contains("sonnet-4-5") { return "Sonnet 4.5" }
        if model.contains("haiku-4-5") { return "Haiku 4.5" }
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }

    // MARK: - File Watching

    func startWatching() {
        let watcher = SessionFileWatcher { [weak self] in
            self?.incrementalUpdate()
        }
        fileWatcher = watcher
        watcher.startWatching()
    }

    func stopWatching() {
        fileWatcher?.stopWatching()
        fileWatcher = nil
    }
}
