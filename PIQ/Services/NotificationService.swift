import Foundation
import UserNotifications

enum NotificationService {

    // MARK: - Permission

    static func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // MARK: - Send Notification

    static func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Milestone Check

    /// Send a notification when an epic crosses 25%, 50%, 75%, or 100% completion.
    static func checkMilestone(epic: EpicItem, oldProgress: Int, settings: Settings) {
        guard settings.notificationsEnabled, settings.notifyOnMilestones else { return }
        guard !isQuietHours(settings: settings) else { return }

        let newProgress = epic.progressPercent
        let milestones = [25, 50, 75, 100]

        for milestone in milestones {
            if oldProgress < milestone && newProgress >= milestone {
                sendNotification(
                    title: "Epic Milestone: \(milestone)%",
                    body: "\(epic.name) reached \(milestone)% completion."
                )
                return
            }
        }
    }

    // MARK: - Task Change

    static func notifyTaskChange(
        task: TaskItem,
        oldStatus: ItemStatus?,
        newStatus: ItemStatus,
        settings: Settings
    ) {
        guard settings.notificationsEnabled, settings.notifyOnTaskChanges else { return }
        guard !isQuietHours(settings: settings) else { return }

        let oldLabel = oldStatus?.rawValue ?? "new"
        sendNotification(
            title: "Task Updated",
            body: "\(task.name): \(oldLabel) -> \(newStatus.rawValue)"
        )
    }

    // MARK: - New PRD

    static func notifyNewPRD(name: String, settings: Settings) {
        guard settings.notificationsEnabled, settings.notifyOnNewPRD else { return }
        guard !isQuietHours(settings: settings) else { return }

        sendNotification(
            title: "New PRD Detected",
            body: "\(name) has been added."
        )
    }

    // MARK: - Inconsistency

    static func notifyInconsistency(epic: EpicItem, settings: Settings) {
        guard settings.notificationsEnabled, settings.notifyOnInconsistency else { return }
        guard !isQuietHours(settings: settings) else { return }

        sendNotification(
            title: "Progress Inconsistency",
            body: "\(epic.name): frontmatter says \(epic.progress)% but tasks show \(epic.progressPercent)%."
        )
    }

    // MARK: - Quiet Hours

    static func isQuietHours(settings: Settings) -> Bool {
        guard settings.quietHoursEnabled else { return false }

        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        let start = settings.quietHoursStart
        let end = settings.quietHoursEnd

        if start < end {
            // Same-day range, e.g. 09:00-17:00
            return hour >= start && hour < end
        } else {
            // Overnight range, e.g. 22:00-08:00
            return hour >= start || hour < end
        }
    }
}
