import Foundation

@MainActor
@Observable
final class ActivityStore {
    private(set) var events: [ActivityEvent] = []
    private var statusSnapshot: [String: ItemStatus] = [:]
    private let storageURL: URL
    private var pendingEvents: [ActivityEvent] = []
    private var batchTimer: Timer?

    private static let batchFlushInterval: TimeInterval = 5.0
    private static let batchFlushThreshold = 10

    init(storageURL: URL) {
        self.storageURL = storageURL
    }

    // MARK: - Public API

    /// Compare current project state against snapshot, generate events for changes.
    func processChanges(projects: [Project]) {
        let newSnapshot = buildSnapshot(from: projects)
        let diff = diffSnapshots(old: statusSnapshot, new: newSnapshot, projects: projects)
        statusSnapshot = newSnapshot

        guard !diff.isEmpty else { return }

        events.append(contentsOf: diff)
        pendingEvents.append(contentsOf: diff)

        if pendingEvents.count >= Self.batchFlushThreshold {
            persistEvents()
        } else {
            startBatchTimer()
        }
    }

    /// Load events from disk and rebuild the status snapshot so the next
    /// processChanges only records actual changes (not duplicates).
    func loadHistory() {
        guard FileManager.default.fileExists(atPath: storageURL.path(percentEncoded: false)) else {
            events = []
            return
        }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            events = try decoder.decode([ActivityEvent].self, from: data)
        } catch {
            // Corrupted file — start fresh
            events = []
        }

        // Rebuild snapshot from loaded events so processChanges won't
        // treat every item as "new" on the next app launch.
        for event in events {
            let key = event.filePath.path(percentEncoded: false)
            statusSnapshot[key] = event.newStatus
        }
    }

    /// Most recent N events, sorted newest-first.
    func recentEvents(limit: Int = 20) -> [ActivityEvent] {
        events.sorted { $0.timestamp > $1.timestamp }.prefix(limit).map { $0 }
    }

    /// Calculate average time for tasks to go from open to done.
    func averageTaskDuration() -> TimeInterval? {
        // Find pairs: for each task that reached .done, find the earliest event
        // where it appeared (oldStatus == nil, newStatus == .open) and the event
        // where it became .done.
        var firstSeen: [String: Date] = [:]
        var completedAt: [String: Date] = [:]

        for event in events {
            guard event.itemType == .task else { continue }
            let key = event.filePath.path(percentEncoded: false)

            // Record earliest appearance
            if firstSeen[key] == nil {
                firstSeen[key] = event.timestamp
            }

            // Record completion
            if event.newStatus == .done {
                completedAt[key] = event.timestamp
            }
        }

        var durations: [TimeInterval] = []
        for (key, doneDate) in completedAt {
            if let startDate = firstSeen[key] {
                let duration = doneDate.timeIntervalSince(startDate)
                if duration > 0 {
                    durations.append(duration)
                }
            }
        }

        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }

    /// Per-day task completion counts for the last N days, including days with 0 completions.
    func tasksCompletedPerDay(lastDays: Int) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build a dictionary of day -> count for .done task events
        var countByDay: [Date: Int] = [:]
        for event in events where event.itemType == .task && event.newStatus == .done {
            let day = calendar.startOfDay(for: event.timestamp)
            countByDay[day, default: 0] += 1
        }

        // Return continuous range including days with 0
        return (0..<lastDays).compactMap { offset -> (date: Date, count: Int)? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date: day, count: countByDay[day] ?? 0)
        }.reversed()
    }

    /// Calculate how many tasks were completed in the last N days.
    func tasksCompleted(inLastDays days: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return events.filter { event in
            event.itemType == .task
                && event.newStatus == .done
                && event.timestamp >= cutoff
        }.count
    }

    // MARK: - Private helpers

    private func buildSnapshot(from projects: [Project]) -> [String: ItemStatus] {
        var snapshot: [String: ItemStatus] = [:]

        for project in projects {
            for prd in project.prds {
                snapshot[prd.filePath.path(percentEncoded: false)] = prd.status
            }
            for epic in project.epics {
                snapshot[epic.filePath.path(percentEncoded: false)] = epic.status
            }
            for task in project.tasks {
                snapshot[task.filePath.path(percentEncoded: false)] = task.status
            }
        }

        return snapshot
    }

    private func diffSnapshots(
        old: [String: ItemStatus],
        new: [String: ItemStatus],
        projects: [Project]
    ) -> [ActivityEvent] {
        let itemLookup = buildItemLookup(from: projects)
        var result: [ActivityEvent] = []

        for (path, newStatus) in new {
            let oldStatus = old[path]

            if oldStatus == newStatus { continue }

            guard let info = itemLookup[path] else { continue }

            let event = ActivityEvent(
                timestamp: info.updated,
                itemType: info.itemType,
                itemName: info.itemName,
                oldStatus: oldStatus,
                newStatus: newStatus,
                filePath: info.filePath
            )
            result.append(event)
        }

        return result
    }

    private struct ItemInfo {
        let itemType: ItemType
        let itemName: String
        let filePath: URL
        let updated: Date
    }

    private func buildItemLookup(from projects: [Project]) -> [String: ItemInfo] {
        var lookup: [String: ItemInfo] = [:]

        for project in projects {
            for prd in project.prds {
                let key = prd.filePath.path(percentEncoded: false)
                lookup[key] = ItemInfo(itemType: .prd, itemName: prd.name, filePath: prd.filePath, updated: prd.updated)
            }
            for epic in project.epics {
                let key = epic.filePath.path(percentEncoded: false)
                lookup[key] = ItemInfo(itemType: .epic, itemName: epic.name, filePath: epic.filePath, updated: epic.updated)
            }
            for task in project.tasks {
                let key = task.filePath.path(percentEncoded: false)
                lookup[key] = ItemInfo(itemType: .task, itemName: task.name, filePath: task.filePath, updated: task.updated)
            }
        }

        return lookup
    }

    /// Flush pending events to disk as JSON.
    func persistEvents() {
        batchTimer?.invalidate()
        batchTimer = nil
        pendingEvents.removeAll()

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(events)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            // Best-effort persistence — log and continue
        }
    }

    private func startBatchTimer() {
        guard batchTimer == nil else { return }
        batchTimer = Timer.scheduledTimer(
            withTimeInterval: Self.batchFlushInterval,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.persistEvents()
            }
        }
    }
}
