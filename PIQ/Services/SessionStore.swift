import Foundation
import os

private let perfLog = Logger(subsystem: "com.piq.app", category: "perf")

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

    /// Per-MTok pricing in USD: (input, output, cacheRead, cacheWrite).
    /// Rates sourced from Anthropic's published API pricing.
    static let pricingTable: [String: (input: Double, output: Double, cacheRead: Double, cacheWrite: Double)] = [
        "opus":   (15,   75,  1.50,  18.75),
        "sonnet": ( 3,   15,  0.30,   3.75),
        "haiku":  ( 0.80, 4,  0.08,   1.0),
    ]

    /// Default rates when model family cannot be determined (uses opus pricing).
    private static let defaultRates: (input: Double, output: Double, cacheRead: Double, cacheWrite: Double) =
        (15, 75, 1.50, 18.75)

    /// Estimated API cost in USD based on published per-token pricing.
    var estimatedCost: Double {
        let rates = Self.pricingRates(for: model)
        return Double(inputTokens) * rates.input / 1_000_000
            + Double(outputTokens) * rates.output / 1_000_000
            + Double(cacheReadTokens) * rates.cacheRead / 1_000_000
            + Double(cacheCreationTokens) * rates.cacheWrite / 1_000_000
    }

    /// Look up per-MTok pricing rates for a model identifier.
    static func pricingRates(for model: String) -> (input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        let lowered = model.lowercased()
        for (key, rates) in pricingTable where lowered.contains(key) {
            return rates
        }
        return defaultRates
    }

    /// Compute the output-token cost in USD for a given model and token count.
    static func outputCost(model: String, tokens: Int) -> Double {
        let rates = pricingRates(for: model)
        return Double(tokens) * rates.output / 1_000_000
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
    private var readState = ReadState()
    private(set) var unreadCounts: [String: Int] = [:]

    /// Root sessions (grouped by sessionId, merging continuations).
    private(set) var rootSessions: [RootSession] = []

    /// Currently loaded session detail (turns for the selected session).
    private(set) var loadedTurns: [SessionTurn] = []
    private(set) var loadedSessionId: String?
    private(set) var isLoadingDetail = false

    /// Incremented every time `loadedTurns` is assigned, so views can detect
    /// content changes even when the turn count stays the same.
    private(set) var loadedTurnsVersion: Int = 0

    /// Per-entry turn cache: entry.id → parsed turns.
    /// Only changed entries need re-parsing; others are served from cache.
    private var entryTurnsCache: [String: [SessionTurn]] = [:]
    /// LRU tracking at session level for eviction.
    private var cachedSessionOrder: [String] = []  // oldest first
    private let sessionCacheLimit = 10

    /// Cache parsed turns for entries, tracking their parent session for LRU eviction.
    private func cacheEntryResults(_ results: [(String, [SessionTurn])], forSession sessionId: String) {
        for (entryId, turns) in results {
            entryTurnsCache[entryId] = turns
        }
        touchSessionLRU(sessionId)
    }

    /// Touch the LRU order and evict if over capacity.
    private func touchSessionLRU(_ sessionId: String) {
        cachedSessionOrder.removeAll { $0 == sessionId }
        cachedSessionOrder.append(sessionId)
        while cachedSessionOrder.count > sessionCacheLimit {
            let evicted = cachedSessionOrder.removeFirst()
            if let rs = rootSessions.first(where: { $0.id == evicted }) {
                for entry in rs.entries { entryTurnsCache.removeValue(forKey: entry.id) }
            }
        }
    }

    /// Assemble turns for a root session from the per-entry cache.
    /// Returns assembled turns (in entry order) and any entries not yet cached.
    private func assembleTurns(for rootSession: RootSession) -> (turns: [SessionTurn], uncached: [SessionEntry]) {
        var turns: [SessionTurn] = []
        var uncached: [SessionEntry] = []
        for entry in rootSession.entries {
            if let cached = entryTurnsCache[entry.id] {
                turns.append(contentsOf: cached)
            } else {
                uncached.append(entry)
            }
        }
        return (turns, uncached)
    }

    /// Active detail-loading task; cancelled when switching sessions.
    private var detailLoadTask: Task<Void, Never>?

    /// Currently selected turn index within loadedTurns.
    var selectedTurnIndex: Int? = nil

    /// The turns to display in Column 3 (may include preceding no-response turns merged with the selected turn).
    var selectedTurns: [SessionTurn] = []

    /// The currently selected turn (last of selectedTurns, for compatibility).
    var selectedTurn: SessionTurn? {
        selectedTurns.last
    }

    /// Recompute rootSessions from current sessions list, grouped by project path.
    private func recomputeRootSessions() {
        var groups: [String: [SessionEntry]] = [:]
        for s in sessions {
            let key = s.projectPath.isEmpty ? s.sessionId : s.projectPath
            groups[key, default: []].append(s)
        }
        rootSessions = groups.map { (key, entries) in
            RootSession(id: key, entries: entries.sorted { $0.createdAt < $1.createdAt })
        }.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

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
        let index = sessionIndex
        let isFirstLoad = readState.lastReadCounts.isEmpty && index.entries.isEmpty
        let rescanStart = ContinuousClock.now
        Task.detached(priority: .userInitiated) { [index] in
            // Load persistent caches off the main thread
            var loadedIndex = index
            if loadedIndex.entries.isEmpty {
                loadedIndex = SessionIndex.load()
            }
            let loadedReadState: ReadState? = isFirstLoad ? nil : ReadState.load()
            perfLog.info("[rescan] index+readState loaded: \(rescanStart.duration(to: .now))")

            let result = await Self.scanWithIndex(loadedIndex) { progress in
                await MainActor.run {
                    self.scanProgress = progress
                }
            }
            perfLog.info("[rescan] scanWithIndex done: \(rescanStart.duration(to: .now)), entries=\(result.allEntries.count), changed=\(result.changedFiles.count)")
            let sorted = result.allEntries.sorted { $0.lastActivityAt > $1.lastActivityAt }
            let newStats = Self.computeStats(from: sorted)
            let cache = StatsCache.load()
            result.updatedIndex.save()
            perfLog.info("[rescan] stats+save done: \(rescanStart.duration(to: .now))")
            await MainActor.run {
                self.sessions = sorted
                self.sessionIndex = result.updatedIndex
                self.stats = newStats
                self.statsCache = cache
                self.scanProgress = nil
                self.isLoading = false
                self.recomputeRootSessions()

                // Restore persisted read state from disk
                if let loadedReadState {
                    self.readState = loadedReadState
                }

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
        let updateStart = ContinuousClock.now

        Task.detached(priority: .userInitiated) { [index] in
            let result = await Self.scanWithIndex(index)

            guard result.hasChanges else {
                perfLog.debug("[incremental] no changes: \(updateStart.duration(to: .now))")
                return
            }
            perfLog.info("[incremental] scan done: \(updateStart.duration(to: .now)), changed=\(result.changedFiles.count)")

            let sorted = result.allEntries.sorted { $0.lastActivityAt > $1.lastActivityAt }
            let newStats = Self.computeStats(from: sorted)
            let cache = StatsCache.load()
            result.updatedIndex.save()

            // If the loaded session is affected, re-parse only the changed entries
            // on the background thread BEFORE switching to MainActor.
            let loadedId = await MainActor.run { self.loadedSessionId }
            var refreshedEntryTurns: [(String, [SessionTurn])]?
            if let loadedId {
                // Build the updated root session to find changed entries
                var groups: [String: [SessionEntry]] = [:]
                for s in sorted {
                    let key = s.projectPath.isEmpty ? s.sessionId : s.projectPath
                    groups[key, default: []].append(s)
                }
                if let entries = groups[loadedId] {
                    let changedEntries = entries.filter { result.changedFiles.contains($0.jsonlURL) }
                    if !changedEntries.isEmpty {
                        let parseStart = ContinuousClock.now
                        refreshedEntryTurns = await Self.parseEntriesParallel(changedEntries)
                        perfLog.info("[incremental] re-parsed \(changedEntries.count) entries: \(parseStart.duration(to: .now))")
                    }
                }
            }

            await MainActor.run {
                self.sessions = sorted
                self.sessionIndex = result.updatedIndex
                self.stats = newStats
                self.statsCache = cache
                self.recomputeRootSessions()
                self.recomputeUnreadCounts()

                // Invalidate entry cache for changed files
                for rs in self.rootSessions {
                    for entry in rs.entries where result.changedFiles.contains(entry.jsonlURL) {
                        self.entryTurnsCache.removeValue(forKey: entry.id)
                    }
                }

                // Apply pre-parsed results only if the same session is still loaded
                if let parsed = refreshedEntryTurns,
                   let loadedId,
                   loadedId == self.loadedSessionId,
                   let rs = self.rootSessions.first(where: { $0.id == loadedId }) {
                    self.cacheEntryResults(parsed, forSession: loadedId)
                    let (allTurns, _) = self.assembleTurns(for: rs)
                    self.loadedTurns = allTurns
                    self.loadedTurnsVersion += 1
                    // Mark read
                    for entry in rs.entries {
                        self.readState.markRead(sessionId: entry.id, readableMessageCount: entry.readableMessageCount)
                    }
                    self.readState.save()
                    self.recomputeUnreadCounts()
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

    /// Load full session detail (turns) for a RootSession (all entries merged).
    /// Uses per-entry cache: only uncached entries are parsed. Cached entries are assembled instantly.
    func loadSessionDetail(rootSession: RootSession, isRefresh: Bool = false) async {
        let detailStart = ContinuousClock.now
        loadedSessionId = rootSession.id
        markEntriesRead(rootSession.entries)

        let (cachedTurns, uncachedEntries) = assembleTurns(for: rootSession)

        if uncachedEntries.isEmpty {
            // Fully cached: show immediately, no parsing needed
            loadedTurns = cachedTurns
            loadedTurnsVersion += 1
            isLoadingDetail = false
            touchSessionLRU(rootSession.id)
            if !isRefresh {
                selectedTurnIndex = cachedTurns.isEmpty ? nil : cachedTurns.count - 1
                selectedTurns = []
            }
            perfLog.info("[detail] cache hit: \(cachedTurns.count) turns, \(detailStart.duration(to: .now))")
            return
        }

        // Show whatever is cached so far (partial or empty)
        if !isRefresh {
            loadedTurns = cachedTurns
            loadedTurnsVersion += 1
            isLoadingDetail = true
            selectedTurnIndex = cachedTurns.isEmpty ? nil : cachedTurns.count - 1
            selectedTurns = []
        }

        // Parse only uncached entries in parallel
        perfLog.info("[detail] parsing \(uncachedEntries.count) uncached entries (cached=\(rootSession.entries.count - uncachedEntries.count))...")
        let parsed = await Self.parseEntriesParallel(uncachedEntries)
        guard !Task.isCancelled, loadedSessionId == rootSession.id else { return }

        // Store results in per-entry cache and reassemble
        cacheEntryResults(parsed, forSession: rootSession.id)
        let (allTurns, _) = assembleTurns(for: rootSession)
        loadedTurns = allTurns
        loadedTurnsVersion += 1
        isLoadingDetail = false
        if selectedTurnIndex == nil && !allTurns.isEmpty {
            selectedTurnIndex = allTurns.count - 1
        }
        perfLog.info("[detail] loaded \(allTurns.count) turns total: \(detailStart.duration(to: .now))")
    }

    private func markEntriesRead(_ entries: [SessionEntry]) {
        for entry in entries {
            readState.markRead(sessionId: entry.id, readableMessageCount: entry.readableMessageCount)
        }
        readState.save()
        recomputeUnreadCounts()
    }

    /// Parse multiple entries in parallel, returning per-entry results in input order.
    private nonisolated static func parseEntriesParallel(_ entries: [SessionEntry]) async -> [(String, [SessionTurn])] {
        await withTaskGroup(of: (Int, String, [SessionTurn]).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    let messages = SessionParser.parseFile(at: entry.jsonlURL)
                    var turns = SessionParser.groupIntoTurns(messages)

                    let agentMap = SessionParser.loadAgentTurns(
                        sessionDir: entry.jsonlURL.deletingLastPathComponent(),
                        sessionId: entry.sessionId
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
                    return (index, entry.id, turns)
                }
            }

            var results = [(Int, String, [SessionTurn])]()
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
    }

    /// Fire-and-forget wrapper that cancels any in-flight detail load before starting a new one.
    func loadSessionDetailAsync(rootSession: RootSession) {
        detailLoadTask?.cancel()
        detailLoadTask = Task {
            await loadSessionDetail(rootSession: rootSession)
        }
    }

    /// Compat: load by single entry (used by MenuBar). Finds the RootSession and delegates.
    func loadSessionDetail(entry: SessionEntry, isRefresh: Bool = false) async {
        let key = entry.projectPath.isEmpty ? entry.sessionId : entry.projectPath
        if let rs = rootSessions.first(where: { $0.id == key }) {
            await loadSessionDetail(rootSession: rs, isRefresh: isRefresh)
        }
    }

    /// Clear loaded detail.
    func clearDetail() {
        loadedTurns = []
        loadedTurnsVersion += 1
        loadedSessionId = nil
        selectedTurnIndex = nil
        selectedTurns = []
        isLoadingDetail = false
    }

    // MARK: - Unread Tracking

    private func recomputeUnreadCounts() {
        var counts: [String: Int] = [:]
        for rs in rootSessions {
            let total = rs.entries.reduce(0) { sum, entry in
                sum + readState.unreadCount(sessionId: entry.id, readableMessageCount: entry.readableMessageCount)
            }
            if total > 0 { counts[rs.id] = total }
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
