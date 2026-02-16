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

// MARK: - SessionStore

/// Central state manager for Claude Code sessions.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SessionEntry] = []
    private(set) var isLoading = false
    private(set) var stats: ClaudeStats?
    private var fileWatcher: SessionFileWatcher?
    private var mtimeCache: [URL: Date] = [:]

    /// Currently loaded session detail (turns for the selected session).
    private(set) var loadedTurns: [SessionTurn] = []
    private(set) var loadedSessionId: String?
    private(set) var isLoadingDetail = false

    // MARK: - Scanning

    /// Full rescan of all session files (runs IO on background thread).
    func rescan() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let scanned = SessionScanner.scanAll()
            var cache: [URL: Date] = [:]
            for entry in scanned {
                cache[entry.jsonlURL] = SessionScanner.modificationDate(of: entry.jsonlURL)
            }
            let newStats = self.loadStats()
            await MainActor.run { [scanned, cache, newStats] in
                self.sessions = scanned
                self.mtimeCache = cache
                self.stats = newStats
                self.isLoading = false
            }
        }
    }

    /// Incremental update: only re-parse files whose mtime changed.
    /// All file I/O runs on a background thread; only final state assignment is on MainActor.
    func incrementalUpdate() {
        let currentSessions = sessions
        let currentCache = mtimeCache
        let loadedId = loadedSessionId

        Task.detached(priority: .userInitiated) {
            let result = Self.performIncrementalScan(
                currentSessions: currentSessions,
                mtimeCache: currentCache
            )

            guard result.hasChanges else { return }

            let deduped = SessionScanner.incrementalDedup(
                allSessions: result.updatedSessions,
                changedDirs: result.changedDirs
            )
            let newStats = self.loadStats()

            // Check if loaded session needs detail refresh
            var detailEntry: SessionEntry?
            if let loadedId,
               let entry = deduped.first(where: { $0.id == loadedId }),
               result.changedFiles.contains(entry.jsonlURL) {
                detailEntry = entry
            }

            await MainActor.run {
                self.sessions = deduped
                self.mtimeCache = result.newCache
                self.stats = newStats

                if let entry = detailEntry {
                    Task {
                        await self.loadSessionDetail(entry: entry)
                    }
                }
            }
        }
    }

    // MARK: - Incremental Scan (background)

    private struct IncrementalResult: Sendable {
        let updatedSessions: [SessionEntry]
        let newCache: [URL: Date]
        let changedDirs: Set<URL>
        let changedFiles: Set<URL>
        let hasChanges: Bool
    }

    private nonisolated static func performIncrementalScan(
        currentSessions: [SessionEntry],
        mtimeCache: [URL: Date]
    ) -> IncrementalResult {
        let projectDirs = SessionScanner.discoverProjects()
        var sessions = currentSessions
        var cache = mtimeCache
        var changedDirs = Set<URL>()
        var changedFiles = Set<URL>()
        var updated = false
        var seenFiles = Set<URL>()

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
                seenFiles.insert(file)
                let newMtime = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate
                let oldMtime = cache[file]

                if oldMtime == nil || newMtime != oldMtime {
                    if let entry = SessionParser.extractMetadata(from: file) {
                        sessions.removeAll { $0.jsonlURL == file }
                        sessions.append(entry)
                        changedDirs.insert(projectDir)
                        changedFiles.insert(file)
                        updated = true
                    }
                    cache[file] = newMtime
                }
            }
        }

        // Remove sessions whose files no longer exist
        let staleFiles = Set(cache.keys).subtracting(seenFiles)
        if !staleFiles.isEmpty {
            for file in staleFiles {
                changedDirs.insert(file.deletingLastPathComponent())
                cache.removeValue(forKey: file)
            }
            let beforeCount = sessions.count
            sessions.removeAll { staleFiles.contains($0.jsonlURL) }
            if sessions.count != beforeCount { updated = true }
        }

        return IncrementalResult(
            updatedSessions: sessions,
            newCache: cache,
            changedDirs: changedDirs,
            changedFiles: changedFiles,
            hasChanges: updated
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
