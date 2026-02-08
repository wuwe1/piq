import Foundation

struct Settings: Codable, Sendable, Equatable {
    var launchAtLogin: Bool = false
    var notificationsEnabled: Bool = true
    var notifyOnMilestones: Bool = true
    var notifyOnTaskChanges: Bool = true
    var notifyOnNewPRD: Bool = true
    var notifyOnInconsistency: Bool = true
    var quietHoursEnabled: Bool = false
    var quietHoursStart: Int = 22
    var quietHoursEnd: Int = 8
    var historyRetentionDays: Int = 30
}
