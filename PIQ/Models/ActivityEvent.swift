import Foundation

struct ActivityEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let itemType: ItemType
    let itemName: String
    let oldStatus: ItemStatus?
    let newStatus: ItemStatus
    let filePath: URL

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        itemType: ItemType,
        itemName: String,
        oldStatus: ItemStatus? = nil,
        newStatus: ItemStatus,
        filePath: URL
    ) {
        self.id = id
        self.timestamp = timestamp
        self.itemType = itemType
        self.itemName = itemName
        self.oldStatus = oldStatus
        self.newStatus = newStatus
        self.filePath = filePath
    }
}
