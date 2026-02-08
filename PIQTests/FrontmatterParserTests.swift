import Testing
import Foundation
@testable import PIQ

// MARK: - FrontmatterParser Tests

@Suite("FrontmatterParser")
struct FrontmatterParserTests {

    // MARK: - Basic parsing

    @Test("parses simple frontmatter")
    func parseSimple() {
        let content = """
        ---
        name: test-project
        status: backlog
        ---
        # Body
        """
        let result = FrontmatterParser.parse(content)
        #expect(result != nil)
        #expect(result?["name"] == .string("test-project"))
        #expect(result?["status"] == .string("backlog"))
    }

    @Test("returns nil for empty string")
    func parseEmptyString() {
        #expect(FrontmatterParser.parse("") == nil)
    }

    @Test("returns nil for no frontmatter")
    func parseNoFrontmatter() {
        let content = "# Just a heading\nSome text."
        #expect(FrontmatterParser.parse(content) == nil)
    }

    @Test("returns nil for unclosed frontmatter")
    func parseUnclosedFrontmatter() {
        let content = """
        ---
        name: test
        status: open
        """
        #expect(FrontmatterParser.parse(content) == nil)
    }

    @Test("returns nil for empty frontmatter block")
    func parseEmptyFrontmatterBlock() {
        let content = """
        ---
        ---
        """
        #expect(FrontmatterParser.parse(content) == nil)
    }

    // MARK: - Value type inference

    @Test("infers integer values")
    func inferInteger() {
        let content = """
        ---
        progress: 75
        count: 0
        negative: -1
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["progress"] == .int(75))
        #expect(result["count"] == .int(0))
        #expect(result["negative"] == .int(-1))
    }

    @Test("infers boolean values")
    func inferBoolean() {
        let content = """
        ---
        enabled: true
        disabled: false
        upper: True
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["enabled"] == .bool(true))
        #expect(result["disabled"] == .bool(false))
        #expect(result["upper"] == .bool(true))
    }

    @Test("infers string values")
    func inferString() {
        let content = """
        ---
        name: hello-world
        description: A test project
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["name"] == .string("hello-world"))
        #expect(result["description"] == .string("A test project"))
    }

    @Test("handles quoted strings")
    func quotedStrings() {
        let content = """
        ---
        name: "quoted value"
        single: 'single quoted'
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["name"] == .string("quoted value"))
        #expect(result["single"] == .string("single quoted"))
    }

    @Test("handles inline array")
    func inlineArray() {
        let content = """
        ---
        tags: [feat, ui, api]
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["tags"] == .array(["feat", "ui", "api"]))
    }

    @Test("handles multi-line array")
    func multiLineArray() {
        let content = """
        ---
        labels:
          - bug
          - urgent
          - frontend
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["labels"] == .array(["bug", "urgent", "frontend"]))
    }

    // MARK: - Colon handling

    @Test("splits only at first colon — URLs preserved")
    func colonInURL() {
        let content = """
        ---
        url: https://github.com/user/repo
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["url"] == .string("https://github.com/user/repo"))
    }

    @Test("handles value with multiple colons")
    func multipleColons() {
        let content = """
        ---
        time: 12:30:45
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["time"] == .string("12:30:45"))
    }

    // MARK: - Date parsing

    @Test("parses ISO 8601 date")
    func parseISO8601() {
        let content = """
        ---
        name: test
        created: 2024-01-15T14:30:45Z
        ---
        """
        let result = FrontmatterParser.parse(content)!
        #expect(result["created"] == .string("2024-01-15T14:30:45Z"))
    }

    // MARK: - ItemStatus tolerant init

    @Test("tolerant init accepts standard values")
    func statusStandard() {
        #expect(ItemStatus(tolerant: "backlog") == .backlog)
        #expect(ItemStatus(tolerant: "open") == .open)
        #expect(ItemStatus(tolerant: "in-progress") == .inProgress)
        #expect(ItemStatus(tolerant: "done") == .done)
    }

    @Test("tolerant init accepts aliases for done")
    func statusAliases() {
        #expect(ItemStatus(tolerant: "closed") == .done)
        #expect(ItemStatus(tolerant: "completed") == .done)
        #expect(ItemStatus(tolerant: "complete") == .done)
    }

    @Test("tolerant init accepts in-progress variants")
    func statusInProgressVariants() {
        #expect(ItemStatus(tolerant: "in_progress") == .inProgress)
        #expect(ItemStatus(tolerant: "inprogress") == .inProgress)
    }

    @Test("tolerant init is case-insensitive")
    func statusCaseInsensitive() {
        #expect(ItemStatus(tolerant: "BACKLOG") == .backlog)
        #expect(ItemStatus(tolerant: "In-Progress") == .inProgress)
        #expect(ItemStatus(tolerant: "DONE") == .done)
    }

    @Test("tolerant init trims whitespace")
    func statusTrimsWhitespace() {
        #expect(ItemStatus(tolerant: "  open  ") == .open)
        #expect(ItemStatus(tolerant: "\tbacklog\t") == .backlog)
    }

    @Test("tolerant init returns nil for unknown")
    func statusUnknown() {
        #expect(ItemStatus(tolerant: "unknown") == nil)
        #expect(ItemStatus(tolerant: "") == nil)
        #expect(ItemStatus(tolerant: "cancelled") == nil)
    }

    // MARK: - EpicItem computed properties

    @Test("progressPercent with no tasks returns frontmatter progress")
    func epicNoTasks() {
        let epic = EpicItem(
            name: "test",
            filePath: URL(filePath: "/tmp/test.md"),
            progress: 50
        )
        #expect(epic.progressPercent == 50)
        #expect(epic.isConsistent == true)
    }

    @Test("progressPercent with tasks computes from task status")
    func epicWithTasks() {
        let tasks = [
            TaskItem(taskID: "1", name: "t1", status: .done, filePath: URL(filePath: "/tmp/1.md")),
            TaskItem(taskID: "2", name: "t2", status: .done, filePath: URL(filePath: "/tmp/2.md")),
            TaskItem(taskID: "3", name: "t3", status: .open, filePath: URL(filePath: "/tmp/3.md")),
            TaskItem(taskID: "4", name: "t4", status: .open, filePath: URL(filePath: "/tmp/4.md")),
        ]
        let epic = EpicItem(
            name: "test",
            filePath: URL(filePath: "/tmp/test.md"),
            progress: 50,
            tasks: tasks
        )
        #expect(epic.progressPercent == 50)
        #expect(epic.isConsistent == true)
    }

    @Test("isConsistent detects mismatch")
    func epicInconsistent() {
        let tasks = [
            TaskItem(taskID: "1", name: "t1", status: .done, filePath: URL(filePath: "/tmp/1.md")),
            TaskItem(taskID: "2", name: "t2", status: .open, filePath: URL(filePath: "/tmp/2.md")),
        ]
        let epic = EpicItem(
            name: "test",
            filePath: URL(filePath: "/tmp/test.md"),
            progress: 75,
            tasks: tasks
        )
        #expect(epic.progressPercent == 50)
        #expect(epic.isConsistent == false)
    }

    @Test("progressPercent rounds correctly")
    func epicRounding() {
        let tasks = [
            TaskItem(taskID: "1", name: "t1", status: .done, filePath: URL(filePath: "/tmp/1.md")),
            TaskItem(taskID: "2", name: "t2", status: .open, filePath: URL(filePath: "/tmp/2.md")),
            TaskItem(taskID: "3", name: "t3", status: .open, filePath: URL(filePath: "/tmp/3.md")),
        ]
        let epic = EpicItem(
            name: "test",
            filePath: URL(filePath: "/tmp/test.md"),
            progress: 33,
            tasks: tasks
        )
        // 1/3 = 33.33... rounds to 33
        #expect(epic.progressPercent == 33)
    }

    // MARK: - parseFile via temporary files

    @Test("parseFile parses PRD")
    func parseFilePRD() throws {
        let content = """
        ---
        name: auth-system
        description: User authentication
        status: in-progress
        created: 2024-01-15T14:30:45Z
        ---
        # Auth System
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "test-prd-\(UUID()).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = FrontmatterParser.parseFile(at: url, as: .prd)
        guard case .prd(let prd) = result else {
            Issue.record("Expected PRD item")
            return
        }
        #expect(prd.name == "auth-system")
        #expect(prd.description == "User authentication")
        #expect(prd.status == .inProgress)
    }

    @Test("parseFile parses Epic with progress")
    func parseFileEpic() throws {
        let content = """
        ---
        name: data-layer
        status: in-progress
        progress: 60
        created: 2024-01-15T14:30:45Z
        ---
        # Data Layer
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "test-epic-\(UUID()).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = FrontmatterParser.parseFile(at: url, as: .epic)
        guard case .epic(let epic) = result else {
            Issue.record("Expected Epic item")
            return
        }
        #expect(epic.name == "data-layer")
        #expect(epic.status == .inProgress)
        #expect(epic.progress == 60)
    }

    @Test("parseFile parses Task with ID from filename")
    func parseFileTask() throws {
        let content = """
        ---
        name: implement-login
        status: open
        ---
        # Task
        """
        let dir = FileManager.default.temporaryDirectory.appending(path: "piq-test-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "3.md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = FrontmatterParser.parseFile(at: url, as: .task)
        guard case .task(let task) = result else {
            Issue.record("Expected Task item")
            return
        }
        #expect(task.name == "implement-login")
        #expect(task.taskID == "3")
        #expect(task.status == .open)
    }

    @Test("parseFile returns nil for missing name")
    func parseFileMissingName() throws {
        let content = """
        ---
        status: open
        ---
        # No name
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "test-noname-\(UUID()).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FrontmatterParser.parseFile(at: url, as: .prd) == nil)
        #expect(FrontmatterParser.parseFile(at: url, as: .epic) == nil)
        #expect(FrontmatterParser.parseFile(at: url, as: .task) == nil)
    }

    @Test("parseFile returns nil for nonexistent file")
    func parseFileNonexistent() {
        let url = URL(filePath: "/tmp/nonexistent-\(UUID()).md")
        #expect(FrontmatterParser.parseFile(at: url, as: .prd) == nil)
    }

    @Test("parseFile handles status aliases")
    func parseFileStatusAliases() throws {
        let content = """
        ---
        name: completed-task
        status: completed
        ---
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "test-alias-\(UUID()).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = FrontmatterParser.parseFile(at: url, as: .task)
        guard case .task(let task) = result else {
            Issue.record("Expected Task item")
            return
        }
        #expect(task.status == .done)
    }

    @Test("parseFile defaults status to backlog for PRD")
    func parseFilePRDDefaultStatus() throws {
        let content = """
        ---
        name: no-status-prd
        ---
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "test-defstatus-\(UUID()).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = FrontmatterParser.parseFile(at: url, as: .prd)
        guard case .prd(let prd) = result else {
            Issue.record("Expected PRD item")
            return
        }
        #expect(prd.status == .backlog)
    }

    @Test("parseFile defaults status to open for Task")
    func parseFileTaskDefaultStatus() throws {
        let content = """
        ---
        name: no-status-task
        ---
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "test-deftask-\(UUID()).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = FrontmatterParser.parseFile(at: url, as: .task)
        guard case .task(let task) = result else {
            Issue.record("Expected Task item")
            return
        }
        #expect(task.status == .open)
    }

    @Test("parse handles progress with percent sign")
    func parseProgressPercent() throws {
        let content = """
        ---
        name: pct-epic
        progress: 75%
        ---
        """
        let url = FileManager.default.temporaryDirectory.appending(path: "test-pct-\(UUID()).md")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = FrontmatterParser.parseFile(at: url, as: .epic)
        guard case .epic(let epic) = result else {
            Issue.record("Expected Epic item")
            return
        }
        #expect(epic.progress == 75)
    }
}
