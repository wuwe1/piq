import Foundation

struct PRDItem: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let description: String
    let status: ItemStatus
    let filePath: URL
    let created: Date
    let updated: Date

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        status: ItemStatus = .backlog,
        filePath: URL,
        created: Date = Date(),
        updated: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.filePath = filePath
        self.created = created
        self.updated = updated
    }
}
