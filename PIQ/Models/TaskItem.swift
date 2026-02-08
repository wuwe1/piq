import Foundation

struct TaskItem: Identifiable, Codable, Sendable {
    let id: UUID
    let taskID: String
    let name: String
    let description: String
    let status: ItemStatus
    let filePath: URL
    let created: Date
    let updated: Date

    init(
        id: UUID = UUID(),
        taskID: String,
        name: String,
        description: String = "",
        status: ItemStatus = .open,
        filePath: URL,
        created: Date = Date(),
        updated: Date = Date()
    ) {
        self.id = id
        self.taskID = taskID
        self.name = name
        self.description = description
        self.status = status
        self.filePath = filePath
        self.created = created
        self.updated = updated
    }
}
