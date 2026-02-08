import Foundation

struct EpicItem: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let status: ItemStatus
    let filePath: URL
    let created: Date
    let updated: Date
    let progress: Int
    var actualTasksDone: Int
    var tasks: [TaskItem]

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        status: ItemStatus = .backlog,
        filePath: URL,
        created: Date = Date(),
        updated: Date = Date(),
        progress: Int = 0,
        actualTasksDone: Int = 0,
        tasks: [TaskItem] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.filePath = filePath
        self.created = created
        self.updated = updated
        self.progress = progress
        self.actualTasksDone = actualTasksDone
        self.tasks = tasks
    }

    /// Percentage of tasks completed, derived from actual child tasks.
    var progressPercent: Int {
        guard !tasks.isEmpty else { return progress }
        let done = tasks.filter { $0.status == .done }.count
        return Int((Double(done) / Double(tasks.count) * 100).rounded())
    }

    /// Whether the frontmatter progress matches the actual task completion ratio.
    var isConsistent: Bool {
        guard !tasks.isEmpty else { return true }
        return progress == progressPercent
    }
}
