import Foundation

enum TimestampSource: String, Codable, Sendable {
    case created
    case updated
}

struct ActivityEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let itemType: ItemType
    let itemName: String
    let oldStatus: ItemStatus?
    let newStatus: ItemStatus
    let filePath: URL
    let timestampSource: TimestampSource
    let projectName: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        itemType: ItemType,
        itemName: String,
        oldStatus: ItemStatus? = nil,
        newStatus: ItemStatus,
        filePath: URL,
        timestampSource: TimestampSource = .updated,
        projectName: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.itemType = itemType
        self.itemName = itemName
        self.oldStatus = oldStatus
        self.newStatus = newStatus
        self.filePath = filePath
        self.timestampSource = timestampSource
        self.projectName = projectName
    }

    enum CodingKeys: String, CodingKey {
        case id, timestamp, itemType, itemName, oldStatus, newStatus, filePath, timestampSource, projectName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        itemType = try c.decode(ItemType.self, forKey: .itemType)
        itemName = try c.decode(String.self, forKey: .itemName)
        oldStatus = try c.decodeIfPresent(ItemStatus.self, forKey: .oldStatus)
        newStatus = try c.decode(ItemStatus.self, forKey: .newStatus)
        filePath = try c.decode(URL.self, forKey: .filePath)
        timestampSource = try c.decodeIfPresent(TimestampSource.self, forKey: .timestampSource) ?? .updated
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName) ?? ""
    }
}
