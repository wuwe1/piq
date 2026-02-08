import Foundation

enum ProjectScanner {

    // MARK: - Project Discovery

    /// Discover projects under a root directory by scanning direct subdirectories
    /// for `.claude/prds/` or `.claude/epics/` markers.
    static func discoverProjects(under rootURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return children.filter { url in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir),
                  isDir.boolValue else {
                return false
            }
            let claudeDir = url.appending(path: ".claude", directoryHint: .isDirectory)
            let hasPRDs = fm.fileExists(atPath: claudeDir.appending(path: "prds").path(percentEncoded: false))
            let hasEpics = fm.fileExists(atPath: claudeDir.appending(path: "epics").path(percentEncoded: false))
            return hasPRDs || hasEpics
        }
    }

    // MARK: - Full Project Scan

    /// Scan a single project directory and assemble a Project model.
    static func scanProject(at projectURL: URL) -> Project {
        let prds = scanPRDs(in: projectURL)
        let epics = scanEpics(in: projectURL)
        let worktrees = discoverWorktrees(at: projectURL)
        let allTasks = epics.flatMap(\.tasks)

        return Project(
            name: projectURL.lastPathComponent,
            rootPath: projectURL,
            prds: prds,
            epics: epics,
            tasks: allTasks,
            worktrees: worktrees,
            lastScanned: Date()
        )
    }

    // MARK: - PRD Scanning

    /// Scan `.claude/prds/` for PRD markdown files.
    static func scanPRDs(in projectURL: URL) -> [PRDItem] {
        let prdsDir = projectURL
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "prds", directoryHint: .isDirectory)

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: prdsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> PRDItem? in
                guard case .prd(let item) = FrontmatterParser.parseFile(at: url, as: .prd) else {
                    return nil
                }
                return item
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Epic Scanning

    /// Scan `.claude/epics/*/epic.md` for Epic items, including their child tasks.
    static func scanEpics(in projectURL: URL) -> [EpicItem] {
        let epicsDir = projectURL
            .appending(path: ".claude", directoryHint: .isDirectory)
            .appending(path: "epics", directoryHint: .isDirectory)

        let fm = FileManager.default
        guard let epicDirs = try? fm.contentsOfDirectory(
            at: epicsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return epicDirs
            .filter { url in
                var isDir: ObjCBool = false
                return fm.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
            }
            .compactMap { epicDir -> EpicItem? in
                let epicFile = epicDir.appending(path: "epic.md")
                guard case .epic(var epic) = FrontmatterParser.parseFile(at: epicFile, as: .epic) else {
                    return nil
                }
                let tasks = scanTasks(in: epicDir)
                epic.tasks = tasks
                epic.actualTasksDone = tasks.filter { $0.status == .done }.count
                return epic
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Task Scanning

    /// Scan task markdown files in an epic directory, excluding non-task files.
    static func scanTasks(in epicDirectoryURL: URL) -> [TaskItem] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: epicDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let excludedNames: Set<String> = ["epic.md", "github-mapping.md"]

        return files
            .filter { url in
                guard url.pathExtension == "md" else { return false }
                let filename = url.lastPathComponent
                if excludedNames.contains(filename) { return false }
                if filename.hasSuffix("-analysis.md") { return false }
                return true
            }
            .compactMap { url -> TaskItem? in
                guard case .task(let item) = FrontmatterParser.parseFile(at: url, as: .task) else {
                    return nil
                }
                return item
            }
            .sorted { $0.taskID.localizedStandardCompare($1.taskID) == .orderedAscending }
    }

    // MARK: - Worktree Discovery

    /// Discover git worktrees by running `git worktree list --porcelain`.
    static func discoverWorktrees(at projectURL: URL) -> [Worktree] {
        guard let output = runProcess(
            executable: "/usr/bin/git",
            arguments: ["worktree", "list", "--porcelain"],
            currentDirectory: projectURL
        ) else {
            return []
        }
        return parseWorktreeOutput(output, relativeTo: projectURL)
    }

    /// Parse the porcelain output of `git worktree list` into Worktree models.
    /// Filters out the main worktree (the first entry).
    static func parseWorktreeOutput(_ output: String, relativeTo baseURL: URL) -> [Worktree] {
        let lines = output.components(separatedBy: .newlines)
        var worktrees: [Worktree] = []
        var currentPath: String?
        var currentBranch: String?
        var isFirst = true

        for line in lines {
            if line.hasPrefix("worktree ") {
                // Save previous entry (if any)
                if let path = currentPath, let branch = currentBranch, !isFirst {
                    let url = URL(filePath: path, directoryHint: .isDirectory)
                    let name = url.lastPathComponent
                    worktrees.append(Worktree(name: name, path: url, branch: branch))
                }
                if currentPath != nil { isFirst = false }
                currentPath = String(line.dropFirst("worktree ".count))
                currentBranch = nil
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                // Strip refs/heads/ prefix
                if ref.hasPrefix("refs/heads/") {
                    currentBranch = String(ref.dropFirst("refs/heads/".count))
                } else {
                    currentBranch = ref
                }
            } else if line.isEmpty {
                // Block separator — save previous if not first
                if let path = currentPath, let branch = currentBranch, !isFirst {
                    let url = URL(filePath: path, directoryHint: .isDirectory)
                    let name = url.lastPathComponent
                    worktrees.append(Worktree(name: name, path: url, branch: branch))
                }
                if currentPath != nil { isFirst = false }
                currentPath = nil
                currentBranch = nil
            }
        }

        // Handle trailing entry (no final blank line)
        if let path = currentPath, let branch = currentBranch, !isFirst {
            let url = URL(filePath: path, directoryHint: .isDirectory)
            let name = url.lastPathComponent
            worktrees.append(Worktree(name: name, path: url, branch: branch))
        }

        return worktrees
    }

    // MARK: - Consistency Check

    /// Verify that an epic's frontmatter progress matches its actual task completion.
    static func verifyConsistency(epic: EpicItem) -> Bool {
        epic.isConsistent
    }

    // MARK: - Process Execution

    /// Run an external process and return its standard output, or nil on failure.
    static func runProcess(executable: String, arguments: [String], currentDirectory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
