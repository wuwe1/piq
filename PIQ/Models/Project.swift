import Foundation

// MARK: - Worktree

struct Worktree: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let path: URL
    let branch: String

    init(id: UUID = UUID(), name: String, path: URL, branch: String) {
        self.id = id
        self.name = name
        self.path = path
        self.branch = branch
    }
}

// MARK: - Project

struct Project: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let rootPath: URL
    var prds: [PRDItem]
    var epics: [EpicItem]
    var tasks: [TaskItem]
    var worktrees: [Worktree]
    var lastScanned: Date?

    init(
        id: UUID = UUID(),
        name: String,
        rootPath: URL,
        prds: [PRDItem] = [],
        epics: [EpicItem] = [],
        tasks: [TaskItem] = [],
        worktrees: [Worktree] = [],
        lastScanned: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.rootPath = rootPath
        self.prds = prds
        self.epics = epics
        self.tasks = tasks
        self.worktrees = worktrees
        self.lastScanned = lastScanned
    }
}
