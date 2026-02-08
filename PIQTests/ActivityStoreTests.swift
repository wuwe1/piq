import Testing
import Foundation
@testable import PIQ

// MARK: - ActivityStore Tests

@Suite("ActivityStore")
struct ActivityStoreTests {

    // MARK: - Helpers

    /// Create a temporary directory for test storage, returning the activity.json URL inside it.
    private func makeTempStorageURL() -> (directory: URL, storageURL: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "piq-activity-test-\(UUID())")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storageURL = dir.appending(path: "activity.json")
        return (dir, storageURL)
    }

    /// Build a minimal Project with the given PRDs, epics, and tasks.
    private func makeProject(
        prds: [PRDItem] = [],
        epics: [EpicItem] = [],
        tasks: [TaskItem] = []
    ) -> Project {
        Project(
            name: "test-project",
            rootPath: URL(filePath: "/tmp/test-project"),
            prds: prds,
            epics: epics,
            tasks: tasks
        )
    }

    // MARK: - Empty initial state

    @Test("empty initial state")
    @MainActor
    func emptyInitialState() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)
        #expect(store.events.isEmpty)
        #expect(store.recentEvents().isEmpty)
        #expect(store.averageTaskDuration() == nil)
        #expect(store.tasksCompleted(inLastDays: 7) == 0)
    }

    // MARK: - processChanges detects new items

    @Test("processChanges detects new items with nil oldStatus")
    @MainActor
    func detectNewItems() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)

        let task = TaskItem(
            taskID: "1",
            name: "new-task",
            status: .open,
            filePath: URL(filePath: "/tmp/test-project/.claude/epics/feat/1.md")
        )
        let project = makeProject(tasks: [task])

        store.processChanges(projects: [project])

        #expect(store.events.count == 1)
        #expect(store.events[0].itemType == .task)
        #expect(store.events[0].itemName == "new-task")
        #expect(store.events[0].oldStatus == nil)
        #expect(store.events[0].newStatus == .open)
    }

    // MARK: - processChanges detects status changes

    @Test("processChanges detects status change open to inProgress")
    @MainActor
    func detectStatusChange() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)

        let filePath = URL(filePath: "/tmp/test-project/.claude/epics/feat/1.md")

        // First scan: task is open
        let task1 = TaskItem(taskID: "1", name: "task-a", status: .open, filePath: filePath)
        store.processChanges(projects: [makeProject(tasks: [task1])])
        #expect(store.events.count == 1)

        // Second scan: task is now in-progress
        let task2 = TaskItem(taskID: "1", name: "task-a", status: .inProgress, filePath: filePath)
        store.processChanges(projects: [makeProject(tasks: [task2])])
        #expect(store.events.count == 2)

        let lastEvent = store.events[1]
        #expect(lastEvent.oldStatus == .open)
        #expect(lastEvent.newStatus == .inProgress)
    }

    // MARK: - processChanges ignores unchanged items

    @Test("processChanges ignores unchanged items")
    @MainActor
    func ignoreUnchanged() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)

        let filePath = URL(filePath: "/tmp/test-project/.claude/epics/feat/1.md")
        let task = TaskItem(taskID: "1", name: "task-a", status: .open, filePath: filePath)
        let project = makeProject(tasks: [task])

        store.processChanges(projects: [project])
        #expect(store.events.count == 1)

        // Same task, same status — no new event
        store.processChanges(projects: [project])
        #expect(store.events.count == 1)
    }

    // MARK: - loadHistory / save round-trip

    @Test("loadHistory and persistEvents round-trip")
    @MainActor
    func roundTrip() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create store, process changes, persist
        let store = ActivityStore(storageURL: storageURL)
        let task = TaskItem(
            taskID: "1",
            name: "round-trip-task",
            status: .open,
            filePath: URL(filePath: "/tmp/project/.claude/epics/feat/1.md")
        )
        store.processChanges(projects: [makeProject(tasks: [task])])
        store.persistEvents()

        // Create a new store, load from disk
        let store2 = ActivityStore(storageURL: storageURL)
        store2.loadHistory()

        #expect(store2.events.count == 1)
        #expect(store2.events[0].itemName == "round-trip-task")
        #expect(store2.events[0].newStatus == .open)
        #expect(store2.events[0].oldStatus == nil)
    }

    // MARK: - loadHistory handles corrupted file

    @Test("loadHistory handles corrupted file gracefully")
    @MainActor
    func corruptedFile() throws {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write garbage to the storage file
        try "not valid json at all {{{".write(to: storageURL, atomically: true, encoding: .utf8)

        let store = ActivityStore(storageURL: storageURL)
        store.loadHistory()

        #expect(store.events.isEmpty)
    }

    // MARK: - loadHistory with nonexistent file

    @Test("loadHistory with nonexistent file starts empty")
    @MainActor
    func nonexistentFile() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Don't create the file — just load
        let store = ActivityStore(storageURL: storageURL)
        store.loadHistory()

        #expect(store.events.isEmpty)
    }

    // MARK: - recentEvents returns limited results

    @Test("recentEvents returns limited results")
    @MainActor
    func recentEventsLimit() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)

        // Create 5 different tasks so we get 5 events in a single processChanges call
        var tasks: [TaskItem] = []
        for i in 1...5 {
            tasks.append(TaskItem(
                taskID: "\(i)",
                name: "task-\(i)",
                status: .open,
                filePath: URL(filePath: "/tmp/project/.claude/epics/feat/\(i).md")
            ))
        }
        store.processChanges(projects: [makeProject(tasks: tasks)])
        #expect(store.events.count == 5)

        let recent3 = store.recentEvents(limit: 3)
        #expect(recent3.count == 3)

        // Should be the last 3 events
        let allEvents = store.events
        #expect(recent3[0].id == allEvents[2].id)
        #expect(recent3[1].id == allEvents[3].id)
        #expect(recent3[2].id == allEvents[4].id)
    }

    // MARK: - averageTaskDuration

    @Test("averageTaskDuration calculates correctly")
    @MainActor
    func averageTaskDuration() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)

        let filePath1 = URL(filePath: "/tmp/project/.claude/epics/feat/1.md")
        let filePath2 = URL(filePath: "/tmp/project/.claude/epics/feat/2.md")

        // Task 1: open
        let task1Open = TaskItem(taskID: "1", name: "t1", status: .open, filePath: filePath1)
        store.processChanges(projects: [makeProject(tasks: [task1Open])])

        // Task 2: open
        let task2Open = TaskItem(taskID: "2", name: "t2", status: .open, filePath: filePath2)
        store.processChanges(projects: [makeProject(tasks: [task1Open, task2Open])])

        // Manually inject events with specific timestamps for deterministic duration testing
        // Clear events and add controlled ones
        let baseDate = Date(timeIntervalSince1970: 1000000)

        let event1 = ActivityEvent(
            timestamp: baseDate,
            itemType: .task,
            itemName: "t1",
            oldStatus: nil,
            newStatus: .open,
            filePath: filePath1
        )
        let event2 = ActivityEvent(
            timestamp: baseDate.addingTimeInterval(100),
            itemType: .task,
            itemName: "t1",
            oldStatus: .open,
            newStatus: .done,
            filePath: filePath1
        )
        let event3 = ActivityEvent(
            timestamp: baseDate,
            itemType: .task,
            itemName: "t2",
            oldStatus: nil,
            newStatus: .open,
            filePath: filePath2
        )
        let event4 = ActivityEvent(
            timestamp: baseDate.addingTimeInterval(200),
            itemType: .task,
            itemName: "t2",
            oldStatus: .open,
            newStatus: .done,
            filePath: filePath2
        )

        // Create a fresh store with controlled events
        let store2 = ActivityStore(storageURL: storageURL)
        // Write controlled events to disk and load them
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try! encoder.encode([event1, event2, event3, event4])
        try! data.write(to: storageURL, options: .atomic)
        store2.loadHistory()

        let avg = store2.averageTaskDuration()
        #expect(avg != nil)
        // t1: 100s, t2: 200s => average = 150s
        #expect(abs(avg! - 150.0) < 0.01)
    }

    @Test("averageTaskDuration returns nil when no completions")
    @MainActor
    func averageTaskDurationNoCompletions() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)
        let task = TaskItem(
            taskID: "1",
            name: "t1",
            status: .open,
            filePath: URL(filePath: "/tmp/project/.claude/epics/feat/1.md")
        )
        store.processChanges(projects: [makeProject(tasks: [task])])

        #expect(store.averageTaskDuration() == nil)
    }

    // MARK: - tasksCompleted counting

    @Test("tasksCompleted counts tasks done in time window")
    @MainActor
    func tasksCompletedCounting() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)
        let filePath = URL(filePath: "/tmp/project/.claude/epics/feat/1.md")

        // First scan: task open
        let taskOpen = TaskItem(taskID: "1", name: "t1", status: .open, filePath: filePath)
        store.processChanges(projects: [makeProject(tasks: [taskOpen])])

        // Second scan: task done
        let taskDone = TaskItem(taskID: "1", name: "t1", status: .done, filePath: filePath)
        store.processChanges(projects: [makeProject(tasks: [taskDone])])

        // The done event should be within last 7 days (it happened now)
        #expect(store.tasksCompleted(inLastDays: 7) == 1)
        // Also within last 1 day
        #expect(store.tasksCompleted(inLastDays: 1) == 1)
    }

    @Test("tasksCompleted excludes non-task events")
    @MainActor
    func tasksCompletedExcludesNonTasks() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)

        // PRD going to done should not count
        let prd = PRDItem(
            name: "prd-1",
            status: .done,
            filePath: URL(filePath: "/tmp/project/.claude/prds/prd-1.md")
        )
        store.processChanges(projects: [makeProject(prds: [prd])])

        #expect(store.tasksCompleted(inLastDays: 7) == 0)
    }

    // MARK: - Multiple item types

    @Test("processChanges tracks PRDs, epics, and tasks")
    @MainActor
    func multipleItemTypes() {
        let (dir, storageURL) = makeTempStorageURL()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ActivityStore(storageURL: storageURL)

        let prd = PRDItem(
            name: "prd-1",
            status: .inProgress,
            filePath: URL(filePath: "/tmp/project/.claude/prds/prd-1.md")
        )
        let epic = EpicItem(
            name: "epic-1",
            status: .backlog,
            filePath: URL(filePath: "/tmp/project/.claude/epics/feat/epic.md")
        )
        let task = TaskItem(
            taskID: "1",
            name: "task-1",
            status: .open,
            filePath: URL(filePath: "/tmp/project/.claude/epics/feat/1.md")
        )

        store.processChanges(projects: [makeProject(prds: [prd], epics: [epic], tasks: [task])])

        #expect(store.events.count == 3)

        let types = Set(store.events.map(\.itemType))
        #expect(types.contains(.prd))
        #expect(types.contains(.epic))
        #expect(types.contains(.task))
    }
}
