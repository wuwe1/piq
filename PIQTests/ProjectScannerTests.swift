import Testing
import Foundation
@testable import PIQ

// MARK: - ProjectScanner Tests

@Suite("ProjectScanner")
struct ProjectScannerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "piq-test-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(at url: URL, content: String) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Project Discovery

    @Test("discovers projects with .claude/prds directory")
    func discoverWithPRDs() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let projectA = root.appending(path: "project-a")
        try FileManager.default.createDirectory(
            at: projectA.appending(path: ".claude/prds"),
            withIntermediateDirectories: true
        )

        let projectB = root.appending(path: "project-b")
        try FileManager.default.createDirectory(at: projectB, withIntermediateDirectories: true)

        let found = ProjectScanner.discoverProjects(under: root)
        #expect(found.count == 1)
        #expect(found.first?.lastPathComponent == "project-a")
    }

    @Test("discovers projects with .claude/epics directory")
    func discoverWithEpics() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = root.appending(path: "my-project")
        try FileManager.default.createDirectory(
            at: project.appending(path: ".claude/epics"),
            withIntermediateDirectories: true
        )

        let found = ProjectScanner.discoverProjects(under: root)
        #expect(found.count == 1)
    }

    @Test("ignores directories without .claude marker")
    func discoverIgnoresNonProjects() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }

        let plain = root.appending(path: "plain-dir")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        let found = ProjectScanner.discoverProjects(under: root)
        #expect(found.isEmpty)
    }

    @Test("returns empty for nonexistent root")
    func discoverNonexistentRoot() {
        let fake = URL(filePath: "/tmp/nonexistent-\(UUID())")
        let found = ProjectScanner.discoverProjects(under: fake)
        #expect(found.isEmpty)
    }

    // MARK: - PRD Scanning

    @Test("scans PRD files from .claude/prds")
    func scanPRDs() throws {
        let project = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: project) }

        let prd1 = """
        ---
        name: auth-system
        description: "User auth"
        status: in-progress
        created: 2024-01-15T14:30:45Z
        ---
        # Auth
        """
        let prd2 = """
        ---
        name: billing
        description: "Billing module"
        status: backlog
        created: 2024-02-01T10:00:00Z
        ---
        # Billing
        """
        try writeFile(at: project.appending(path: ".claude/prds/auth-system.md"), content: prd1)
        try writeFile(at: project.appending(path: ".claude/prds/billing.md"), content: prd2)

        let prds = ProjectScanner.scanPRDs(in: project)
        #expect(prds.count == 2)
        #expect(prds[0].name == "auth-system")
        #expect(prds[0].status == .inProgress)
        #expect(prds[1].name == "billing")
        #expect(prds[1].status == .backlog)
    }

    @Test("returns empty PRDs for project without .claude/prds")
    func scanPRDsEmpty() throws {
        let project = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: project) }

        let prds = ProjectScanner.scanPRDs(in: project)
        #expect(prds.isEmpty)
    }

    // MARK: - Epic Scanning

    @Test("scans epics with their tasks")
    func scanEpicsWithTasks() throws {
        let project = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: project) }

        let epicContent = """
        ---
        name: data-layer
        status: in-progress
        progress: 50
        created: 2024-01-15T14:30:45Z
        ---
        # Data Layer
        """
        let task1 = """
        ---
        name: "Create schema"
        status: done
        created: 2024-01-16T10:00:00Z
        ---
        # Schema
        """
        let task2 = """
        ---
        name: "Add migrations"
        status: open
        created: 2024-01-17T10:00:00Z
        ---
        # Migrations
        """

        let epicDir = project.appending(path: ".claude/epics/data-layer")
        try writeFile(at: epicDir.appending(path: "epic.md"), content: epicContent)
        try writeFile(at: epicDir.appending(path: "001.md"), content: task1)
        try writeFile(at: epicDir.appending(path: "002.md"), content: task2)

        let epics = ProjectScanner.scanEpics(in: project)
        #expect(epics.count == 1)
        #expect(epics[0].name == "data-layer")
        #expect(epics[0].tasks.count == 2)
        #expect(epics[0].actualTasksDone == 1)
    }

    // MARK: - Task Filtering

    @Test("excludes epic.md, analysis files, and github-mapping.md")
    func scanTasksFiltering() throws {
        let epicDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: epicDir) }

        let taskContent = """
        ---
        name: "Real task"
        status: open
        ---
        """
        let epicContent = """
        ---
        name: "Epic file"
        status: open
        ---
        """
        let analysisContent = """
        ---
        name: "Analysis"
        status: open
        ---
        """
        let mappingContent = """
        ---
        name: "Mapping"
        status: open
        ---
        """

        try writeFile(at: epicDir.appending(path: "001.md"), content: taskContent)
        try writeFile(at: epicDir.appending(path: "epic.md"), content: epicContent)
        try writeFile(at: epicDir.appending(path: "001-analysis.md"), content: analysisContent)
        try writeFile(at: epicDir.appending(path: "github-mapping.md"), content: mappingContent)

        let tasks = ProjectScanner.scanTasks(in: epicDir)
        #expect(tasks.count == 1)
        #expect(tasks[0].name == "Real task")
    }

    // MARK: - Worktree Parsing

    @Test("parses porcelain worktree output, skipping main worktree")
    func parseWorktreeOutput() {
        let output = """
        worktree /Users/dev/project
        HEAD abc123
        branch refs/heads/main

        worktree /Users/dev/epic-auth
        HEAD def456
        branch refs/heads/epic/auth

        worktree /Users/dev/epic-billing
        HEAD ghi789
        branch refs/heads/epic/billing

        """
        let base = URL(filePath: "/Users/dev/project")
        let worktrees = ProjectScanner.parseWorktreeOutput(output, relativeTo: base)
        #expect(worktrees.count == 2)
        #expect(worktrees[0].name == "epic-auth")
        #expect(worktrees[0].branch == "epic/auth")
        #expect(worktrees[1].name == "epic-billing")
        #expect(worktrees[1].branch == "epic/billing")
    }

    @Test("parses worktree output without trailing newline")
    func parseWorktreeNoTrailingNewline() {
        let output = """
        worktree /Users/dev/project
        HEAD abc123
        branch refs/heads/main

        worktree /Users/dev/epic-feature
        HEAD def456
        branch refs/heads/epic/feature
        """
        let base = URL(filePath: "/Users/dev/project")
        let worktrees = ProjectScanner.parseWorktreeOutput(output, relativeTo: base)
        #expect(worktrees.count == 1)
        #expect(worktrees[0].name == "epic-feature")
        #expect(worktrees[0].branch == "epic/feature")
    }

    @Test("returns empty for single worktree (main only)")
    func parseWorktreeMainOnly() {
        let output = """
        worktree /Users/dev/project
        HEAD abc123
        branch refs/heads/main

        """
        let base = URL(filePath: "/Users/dev/project")
        let worktrees = ProjectScanner.parseWorktreeOutput(output, relativeTo: base)
        #expect(worktrees.isEmpty)
    }

    @Test("returns empty for empty output")
    func parseWorktreeEmptyOutput() {
        let base = URL(filePath: "/tmp")
        let worktrees = ProjectScanner.parseWorktreeOutput("", relativeTo: base)
        #expect(worktrees.isEmpty)
    }

    // MARK: - Consistency Check

    @Test("verifyConsistency returns true when progress matches")
    func consistencyMatches() {
        let tasks = [
            TaskItem(taskID: "1", name: "t1", status: .done, filePath: URL(filePath: "/tmp/1.md")),
            TaskItem(taskID: "2", name: "t2", status: .open, filePath: URL(filePath: "/tmp/2.md")),
        ]
        let epic = EpicItem(
            name: "test",
            filePath: URL(filePath: "/tmp/test.md"),
            progress: 50,
            tasks: tasks
        )
        #expect(ProjectScanner.verifyConsistency(epic: epic) == true)
    }

    @Test("verifyConsistency returns false when progress mismatches")
    func consistencyMismatches() {
        let tasks = [
            TaskItem(taskID: "1", name: "t1", status: .done, filePath: URL(filePath: "/tmp/1.md")),
            TaskItem(taskID: "2", name: "t2", status: .open, filePath: URL(filePath: "/tmp/2.md")),
        ]
        let epic = EpicItem(
            name: "test",
            filePath: URL(filePath: "/tmp/test.md"),
            progress: 80,
            tasks: tasks
        )
        #expect(ProjectScanner.verifyConsistency(epic: epic) == false)
    }

    @Test("verifyConsistency returns true for epic with no tasks")
    func consistencyNoTasks() {
        let epic = EpicItem(
            name: "test",
            filePath: URL(filePath: "/tmp/test.md"),
            progress: 50
        )
        #expect(ProjectScanner.verifyConsistency(epic: epic) == true)
    }

    // MARK: - Full Project Scan

    @Test("scanProject assembles a complete Project")
    func scanProject() throws {
        let project = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: project) }

        let prd = """
        ---
        name: feature-x
        status: backlog
        created: 2024-01-15T14:30:45Z
        ---
        """
        let epic = """
        ---
        name: feature-x
        status: in-progress
        progress: 0
        created: 2024-01-15T14:30:45Z
        ---
        """
        let task = """
        ---
        name: "Setup DB"
        status: open
        created: 2024-01-16T10:00:00Z
        ---
        """

        try writeFile(at: project.appending(path: ".claude/prds/feature-x.md"), content: prd)
        let epicDir = project.appending(path: ".claude/epics/feature-x")
        try writeFile(at: epicDir.appending(path: "epic.md"), content: epic)
        try writeFile(at: epicDir.appending(path: "001.md"), content: task)

        let result = ProjectScanner.scanProject(at: project)
        #expect(result.name == project.lastPathComponent)
        #expect(result.prds.count == 1)
        #expect(result.epics.count == 1)
        #expect(result.tasks.count == 1)
        #expect(result.lastScanned != nil)
    }
}

// MARK: - ProjectStore Tests

@Suite("ProjectStore")
struct ProjectStoreTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "piq-store-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeFile(at url: URL, content: String) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Config Persistence

    @Test("saveConfig and loadConfig round-trip")
    func configRoundTrip() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let configURL = dir.appending(path: "config.json")
        let home = URL(filePath: "/Users/dev")
        let config = ProjectConfig(
            scanRoots: [home.appending(path: "projects")],
            manualProjects: [ProjectEntry(rootPath: home.appending(path: "special"), isManual: true)],
            discoveredProjects: []
        )

        let saved = ProjectStore.saveConfig(config, to: configURL)
        #expect(saved == true)

        let loaded = ProjectStore.loadConfig(from: configURL)
        #expect(loaded.scanRoots.count == 1)
        #expect(loaded.manualProjects.count == 1)
        #expect(loaded.manualProjects[0].isManual == true)
    }

    @Test("loadConfig returns default for missing file")
    func loadConfigMissing() {
        let url = URL(filePath: "/tmp/nonexistent-\(UUID()).json")
        let config = ProjectStore.loadConfig(from: url)
        #expect(config.scanRoots.isEmpty)
        #expect(config.manualProjects.isEmpty)
        #expect(config.discoveredProjects.isEmpty)
    }

    // MARK: - Manual Project Management

    @Test("addManualProject adds new entry")
    func addManualProject() {
        var config = ProjectConfig()
        let path = URL(filePath: "/Users/dev/my-project")
        let added = ProjectStore.addManualProject(path: path, to: &config)
        #expect(added == true)
        #expect(config.manualProjects.count == 1)
        #expect(config.manualProjects[0].isManual == true)
    }

    @Test("addManualProject rejects duplicate")
    func addManualProjectDuplicate() {
        var config = ProjectConfig()
        let path = URL(filePath: "/Users/dev/my-project")
        _ = ProjectStore.addManualProject(path: path, to: &config)
        let added = ProjectStore.addManualProject(path: path, to: &config)
        #expect(added == false)
        #expect(config.manualProjects.count == 1)
    }

    @Test("addManualProject rejects path already in discovered")
    func addManualProjectAlreadyDiscovered() {
        let path = URL(filePath: "/Users/dev/my-project")
        var config = ProjectConfig(
            discoveredProjects: [ProjectEntry(rootPath: path)]
        )
        let added = ProjectStore.addManualProject(path: path, to: &config)
        #expect(added == false)
    }

    // MARK: - Scan Root Management

    @Test("addScanRoot adds new root")
    func addScanRoot() {
        var config = ProjectConfig()
        let root = URL(filePath: "/Users/dev/projects")
        ProjectStore.addScanRoot(root, to: &config)
        #expect(config.scanRoots.count == 1)
    }

    @Test("addScanRoot ignores duplicate")
    func addScanRootDuplicate() {
        var config = ProjectConfig()
        let root = URL(filePath: "/Users/dev/projects")
        ProjectStore.addScanRoot(root, to: &config)
        ProjectStore.addScanRoot(root, to: &config)
        #expect(config.scanRoots.count == 1)
    }

    @Test("removeScanRoot removes existing root")
    func removeScanRoot() {
        let root = URL(filePath: "/Users/dev/projects")
        var config = ProjectConfig(scanRoots: [root])
        ProjectStore.removeScanRoot(root, from: &config)
        #expect(config.scanRoots.isEmpty)
    }

    // MARK: - Full Scan Integration

    @Test("scanAll discovers and scans projects")
    func scanAllIntegration() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Create a scan root with one project
        let scanRoot = dir.appending(path: "scan-root")
        let project = scanRoot.appending(path: "my-app")
        let prd = """
        ---
        name: feature-a
        status: backlog
        created: 2024-01-15T14:30:45Z
        ---
        """
        try writeFile(at: project.appending(path: ".claude/prds/feature-a.md"), content: prd)

        // Create config with scan root
        let configURL = dir.appending(path: "config.json")
        let config = ProjectConfig(scanRoots: [scanRoot])
        ProjectStore.saveConfig(config, to: configURL)

        let projects = ProjectStore.scanAll(configURL: configURL)
        #expect(projects.count == 1)
        #expect(projects[0].name == "my-app")
        #expect(projects[0].prds.count == 1)
    }

    @Test("scanAll preserves isHidden flags across rescans")
    func scanAllPreservesHidden() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let scanRoot = dir.appending(path: "scan-root")
        let project = scanRoot.appending(path: "hidden-app")
        try FileManager.default.createDirectory(
            at: project.appending(path: ".claude/prds"),
            withIntermediateDirectories: true
        )

        let configURL = dir.appending(path: "config.json")
        let config = ProjectConfig(
            scanRoots: [scanRoot],
            discoveredProjects: [
                ProjectEntry(rootPath: project, isManual: false, isHidden: true)
            ]
        )
        ProjectStore.saveConfig(config, to: configURL)

        // scanAll should discover the project but keep it hidden
        let projects = ProjectStore.scanAll(configURL: configURL)
        #expect(projects.isEmpty)

        // Verify config preserved the hidden flag
        let updatedConfig = ProjectStore.loadConfig(from: configURL)
        #expect(updatedConfig.discoveredProjects.count == 1)
        #expect(updatedConfig.discoveredProjects[0].isHidden == true)
    }

    @Test("scanAll includes manual projects")
    func scanAllWithManualProjects() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Manual project (no .claude dir needed for entry, but scanner will just return empty data)
        let manualProject = dir.appending(path: "manual-project")
        let prd = """
        ---
        name: manual-feature
        status: backlog
        created: 2024-01-15T14:30:45Z
        ---
        """
        try writeFile(at: manualProject.appending(path: ".claude/prds/manual-feature.md"), content: prd)

        let configURL = dir.appending(path: "config.json")
        let config = ProjectConfig(
            manualProjects: [ProjectEntry(rootPath: manualProject, isManual: true)]
        )
        ProjectStore.saveConfig(config, to: configURL)

        let projects = ProjectStore.scanAll(configURL: configURL)
        #expect(projects.count == 1)
        #expect(projects[0].prds.count == 1)
    }
}

// MARK: - ProjectConfig Tests

@Suite("ProjectConfig")
struct ProjectConfigTests {

    @Test("default config has empty collections")
    func defaultConfig() {
        let config = ProjectConfig()
        #expect(config.scanRoots.isEmpty)
        #expect(config.manualProjects.isEmpty)
        #expect(config.discoveredProjects.isEmpty)
    }

    @Test("ProjectEntry defaults")
    func entryDefaults() {
        let entry = ProjectEntry(rootPath: URL(filePath: "/tmp/test"))
        #expect(entry.isManual == false)
        #expect(entry.isHidden == false)
    }
}
