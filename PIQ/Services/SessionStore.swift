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

struct ProjectGroup: Sendable {
    let name: String
    let path: String
    let count: Int
    let tokens: Int
}

struct HourlyBucket: Sendable {
    let date: Date
    let count: Int
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
    let projectGroups: [ProjectGroup]
    let recentHourly: [HourlyBucket]

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
    private var readState = ReadState.load()
    private(set) var unreadCounts: [String: Int] = [:]

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

                // First launch: mark all as read to avoid showing everything as unread
                if self.readState.lastReadCounts.isEmpty {
                    self.markAllAsRead()
                }
                self.readState.removeStaleEntries(keeping: Set(sorted.map(\.id)))
                self.recomputeUnreadCounts()
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
                self.recomputeUnreadCounts()

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

        // Mark session as read
        readState.markRead(sessionId: entry.id, readableMessageCount: entry.readableMessageCount)
        readState.save()
        recomputeUnreadCounts()

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

    // MARK: - Unread Tracking

    private func recomputeUnreadCounts() {
        var counts: [String: Int] = [:]
        for session in sessions {
            let count = readState.unreadCount(sessionId: session.id, readableMessageCount: session.readableMessageCount)
            if count > 0 {
                counts[session.id] = count
            }
        }
        unreadCounts = counts
    }

    private func markAllAsRead() {
        for session in sessions {
            readState.markRead(sessionId: session.id, readableMessageCount: session.readableMessageCount)
        }
        readState.save()
    }

    // MARK: - Aggregate Stats

    /// Compute aggregate stats from parsed session data in a single pass.
    private nonisolated static func computeStats(from sessions: [SessionEntry]) -> ClaudeStats {
        let calendar = Calendar.current
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")

        var totalMessages = 0
        var totalInput = 0
        var totalOutput = 0
        var totalCacheRead = 0
        var totalCacheCreate = 0
        var firstDate: Date?
        var longestMsgs = 0
        var longestDuration: TimeInterval = 0
        var hourCounts: [Int: Int] = [:]
        var daily: [String: Int] = [:]
        var models: [String: (inp: Int, out: Int, cacheRead: Int, cacheCreate: Int)] = [:]
        var projectMap: [String: (name: String, count: Int, tokens: Int)] = [:]

        // Recent hourly buckets (24h)
        let currentHour = calendar.dateInterval(of: .hour, for: Date())!.start
        let startHour = currentHour.addingTimeInterval(-23 * 3600)
        var hourlyBuckets: [Date: Int] = [:]
        for i in 0..<24 {
            hourlyBuckets[startHour.addingTimeInterval(Double(i) * 3600)] = 0
        }

        for s in sessions {
            // Basic aggregates
            totalMessages += s.messageCount
            totalInput += s.inputTokens
            totalOutput += s.outputTokens
            totalCacheRead += s.cacheReadTokens
            totalCacheCreate += s.cacheCreationTokens

            if firstDate == nil || s.createdAt < firstDate! {
                firstDate = s.createdAt
            }
            if s.messageCount > longestMsgs {
                longestMsgs = s.messageCount
            }
            let duration = s.lastActivityAt.timeIntervalSince(s.createdAt)
            if duration > longestDuration {
                longestDuration = duration
            }

            // Hour counts (last 24h)
            if s.lastActivityAt > cutoff {
                let sHour = calendar.component(.hour, from: max(s.createdAt, cutoff))
                let eHour = calendar.component(.hour, from: s.lastActivityAt)
                if sHour == eHour {
                    hourCounts[eHour, default: 0] += s.messageCount
                } else {
                    var hours: [Int] = []
                    var h = sHour
                    while true {
                        hours.append(h)
                        if h == eHour { break }
                        h = (h + 1) % 24
                    }
                    let perHour = s.messageCount / hours.count
                    let remainder = s.messageCount % hours.count
                    for (i, hour) in hours.enumerated() {
                        hourCounts[hour, default: 0] += perHour + (i < remainder ? 1 : 0)
                    }
                }
            }

            // Daily activity
            let startDay = calendar.startOfDay(for: s.createdAt)
            let endDay = calendar.startOfDay(for: s.lastActivityAt)
            if startDay == endDay {
                daily[df.string(from: startDay), default: 0] += s.messageCount
            } else {
                var days: [String] = []
                var d = startDay
                while d <= endDay {
                    days.append(df.string(from: d))
                    d = calendar.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86400)
                }
                let perDay = s.messageCount / days.count
                let remainder = s.messageCount % days.count
                for (i, day) in days.enumerated() {
                    daily[day, default: 0] += perDay + (i < remainder ? 1 : 0)
                }
            }

            // Model breakdown
            if !s.model.isEmpty {
                let e = models[s.model] ?? (0, 0, 0, 0)
                models[s.model] = (
                    inp: e.inp + s.inputTokens,
                    out: e.out + s.outputTokens,
                    cacheRead: e.cacheRead + s.cacheReadTokens,
                    cacheCreate: e.cacheCreate + s.cacheCreationTokens
                )
            }

            // Project groups
            let key = s.projectPath.isEmpty ? "(unknown)" : s.projectPath
            let name = s.projectPath.isEmpty ? "Unknown" : s.projectName
            let existing = projectMap[key] ?? (name: name, count: 0, tokens: 0)
            projectMap[key] = (
                name: existing.name,
                count: existing.count + 1,
                tokens: existing.tokens + s.inputTokens + s.outputTokens
            )

            // Recent hourly buckets
            let endBucket = calendar.dateInterval(of: .hour, for: s.lastActivityAt)?.start ?? s.lastActivityAt
            if endBucket >= startHour {
                let clippedStart = max(s.createdAt, startHour)
                let startBucket = calendar.dateInterval(of: .hour, for: clippedStart)?.start ?? clippedStart
                var validBuckets: [Date] = []
                var hb = startBucket
                while hb <= endBucket {
                    if hourlyBuckets[hb] != nil { validBuckets.append(hb) }
                    hb = hb.addingTimeInterval(3600)
                }
                if !validBuckets.isEmpty {
                    let perBucket = s.messageCount / validBuckets.count
                    let remainder = s.messageCount % validBuckets.count
                    for (i, bucket) in validBuckets.enumerated() {
                        hourlyBuckets[bucket, default: 0] += perBucket + (i < remainder ? 1 : 0)
                    }
                }
            }
        }

        let dailyActivity = daily.map { DailyActivity(date: $0.key, messageCount: $0.value) }
            .sorted { $0.date < $1.date }

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

        let projectGroups = projectMap.map {
            ProjectGroup(name: $0.value.name, path: $0.key, count: $0.value.count, tokens: $0.value.tokens)
        }.sorted { $0.count > $1.count }

        let recentHourly = hourlyBuckets.sorted { $0.key < $1.key }
            .map { HourlyBucket(date: $0.key, count: $0.value) }

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
            modelBreakdown: modelBreakdown,
            projectGroups: projectGroups,
            recentHourly: recentHourly
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
