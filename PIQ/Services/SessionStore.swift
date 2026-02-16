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

    /// Estimated API cost in USD based on published per-token pricing.
    var estimatedCost: Double {
        let rates = Self.pricingRates(for: model)
        return Double(inputTokens) * rates.input / 1_000_000
            + Double(outputTokens) * rates.output / 1_000_000
            + Double(cacheReadTokens) * rates.cacheRead / 1_000_000
            + Double(cacheCreationTokens) * rates.cacheWrite / 1_000_000
    }

    private static func pricingRates(for model: String) -> (input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        if model.contains("opus") {
            return (15, 75, 1.50, 18.75)
        } else if model.contains("sonnet") {
            return (3, 15, 0.30, 3.75)
        } else if model.contains("haiku") {
            return (0.80, 4, 0.08, 1.0)
        }
        return (15, 75, 1.50, 18.75) // default to opus pricing
    }
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

// MARK: - StatsCache (Claude Code stats-cache.json)

/// Parsed representation of ~/.claude/stats-cache.json written by Claude Code.
struct StatsCache: Sendable {
    let dailyActivity: [DailyActivityCached]
    let dailyModelTokens: [DailyModelTokens]
    let totalToolCalls: Int

    struct DailyActivityCached: Identifiable, Sendable {
        var id: String { date }
        let date: String
        let sessionCount: Int
        let toolCallCount: Int
    }

    struct DailyModelTokens: Identifiable, Sendable {
        var id: String { date }
        let date: String
        let tokensByModel: [String: Int]   // model id → output tokens
    }

    static func load() -> StatsCache? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/stats-cache.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var daily: [DailyActivityCached] = []
        if let arr = json["dailyActivity"] as? [[String: Any]] {
            for item in arr {
                guard let date = item["date"] as? String else { continue }
                daily.append(DailyActivityCached(
                    date: date,
                    sessionCount: item["sessionCount"] as? Int ?? 0,
                    toolCallCount: item["toolCallCount"] as? Int ?? 0
                ))
            }
        }

        var modelTokens: [DailyModelTokens] = []
        if let arr = json["dailyModelTokens"] as? [[String: Any]] {
            for item in arr {
                guard let date = item["date"] as? String,
                      let byModel = item["tokensByModel"] as? [String: Int] else { continue }
                modelTokens.append(DailyModelTokens(date: date, tokensByModel: byModel))
            }
        }

        let totalTools = daily.reduce(0) { $0 + $1.toolCallCount }

        return StatsCache(
            dailyActivity: daily,
            dailyModelTokens: modelTokens,
            totalToolCalls: totalTools
        )
    }
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
    private(set) var statsCache: StatsCache?
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
        let changedFiles: Set<URL>
        let hasChanges: Bool
    }

    private struct FileToParse: Sendable {
        let file: URL
        let path: String
        let mtime: Date?
    }

    private struct ParseResult: Sendable {
        let file: URL
        let path: String
        let mtime: Date?
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
            let sorted = result.allEntries.sorted { $0.lastActivityAt > $1.lastActivityAt }
            let newStats = Self.computeStats(from: sorted)
            let cache = StatsCache.load()
            result.updatedIndex.save()
            await MainActor.run {
                self.sessions = sorted
                self.sessionIndex = result.updatedIndex
                self.stats = newStats
                self.statsCache = cache
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

            let sorted = result.allEntries.sorted { $0.lastActivityAt > $1.lastActivityAt }
            let newStats = Self.computeStats(from: sorted)
            let cache = StatsCache.load()
            result.updatedIndex.save()

            // Check if loaded session needs detail refresh
            var detailEntry: SessionEntry?
            if let loadedId,
               let entry = sorted.first(where: { $0.id == loadedId }),
               result.changedFiles.contains(entry.jsonlURL) {
                detailEntry = entry
            }

            await MainActor.run {
                self.sessions = sorted
                self.sessionIndex = result.updatedIndex
                self.stats = newStats
                self.statsCache = cache

                if let entry = detailEntry {
                    Task {
                        await self.loadSessionDetail(entry: entry, isRefresh: true)
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
                filesToParse.append(FileToParse(file: file, path: path, mtime: newMtime))
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
                        return ParseResult(file: item.file, path: item.path, mtime: item.mtime, entry: entry)
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
            updatedIndex.removeStaleEntries(keeping: seenPaths)
            hasChanges = true
        }

        return ScanResult(
            allEntries: allEntries,
            updatedIndex: updatedIndex,
            changedFiles: changedFiles,
            hasChanges: hasChanges
        )
    }

    // MARK: - Detail Loading

    /// Load full session detail (turns) for display.
    /// When `isRefresh` is true, keeps existing turns visible to preserve scroll position.
    func loadSessionDetail(entry: SessionEntry, isRefresh: Bool = false) async {
        loadedSessionId = entry.id
        if !isRefresh {
            isLoadingDetail = true
            loadedTurns = []
        }

        let url = entry.jsonlURL
        let sessionId = entry.sessionId
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

    /// Compute aggregate stats from parsed session data.
    private nonisolated static func computeStats(from sessions: [SessionEntry]) -> ClaudeStats {
        let totalMessages = sessions.reduce(0) { $0 + $1.messageCount }
        let totalInput = sessions.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = sessions.reduce(0) { $0 + $1.outputTokens }

        let firstDate = sessions.min(by: { $0.createdAt < $1.createdAt })?.createdAt
        let longestMsgs = sessions.max(by: { $0.messageCount < $1.messageCount })?.messageCount ?? 0
        let longestDuration = sessions.reduce(0.0) {
            max($0, $1.lastActivityAt.timeIntervalSince($1.createdAt))
        }

        // Hour counts — messages in the last 24 hours, by creation hour
        let calendar = Calendar.current
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var hourCounts: [Int: Int] = [:]
        for s in sessions where s.lastActivityAt > cutoff {
            let hour = calendar.component(.hour, from: s.createdAt)
            hourCounts[hour, default: 0] += s.messageCount
        }

        // Daily activity — messages grouped by session creation date
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        var daily: [String: Int] = [:]
        for s in sessions {
            daily[df.string(from: s.createdAt), default: 0] += s.messageCount
        }
        let dailyActivity = daily.map { DailyActivity(date: $0.key, messageCount: $0.value) }
            .sorted { $0.date < $1.date }

        // Model breakdown
        var models: [String: (inp: Int, out: Int, cacheRead: Int, cacheCreate: Int)] = [:]
        for s in sessions where !s.model.isEmpty {
            let e = models[s.model] ?? (0, 0, 0, 0)
            models[s.model] = (
                inp: e.inp + s.inputTokens,
                out: e.out + s.outputTokens,
                cacheRead: e.cacheRead + s.cacheReadTokens,
                cacheCreate: e.cacheCreate + s.cacheCreationTokens
            )
        }
        let modelBreakdown = models.map {
            ModelStats(
                model: $0.key,
                displayName: modelDisplayName($0.key),
                inputTokens: $0.value.inp,
                outputTokens: $0.value.out,
                cacheReadTokens: $0.value.cacheRead,
                cacheCreationTokens: $0.value.cacheCreate
            )
        }.sorted { $0.estimatedCost > $1.estimatedCost }

        let totalCacheRead = sessions.reduce(0) { $0 + $1.cacheReadTokens }
        let totalCacheCreate = sessions.reduce(0) { $0 + $1.cacheCreationTokens }

        return ClaudeStats(
            totalSessions: sessions.count,
            totalMessages: totalMessages,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalCacheCreationTokens: totalCacheCreate,
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
