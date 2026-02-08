import Foundation

// MARK: - ItemStatus

enum ItemStatus: String, Codable, Sendable, CaseIterable {
    case backlog
    case open
    case inProgress = "in-progress"
    case done

    /// Tolerant initializer that accepts common aliases.
    init?(tolerant raw: String) {
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch normalized {
        case "backlog":
            self = .backlog
        case "open":
            self = .open
        case "in-progress", "in_progress", "inprogress":
            self = .inProgress
        case "done", "closed", "completed", "complete":
            self = .done
        default:
            return nil
        }
    }
}

// MARK: - ItemType

enum ItemType: String, Codable, Sendable {
    case prd
    case epic
    case task
}
