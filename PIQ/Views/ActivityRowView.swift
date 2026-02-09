import SwiftUI

struct ActivityRowView: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: typeIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.itemName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let old = event.oldStatus {
                        StatusBadge(status: old)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    StatusBadge(status: event.newStatus)
                }
            }

            Spacer()

            HStack(spacing: 3) {
                Text(event.timestampSource == .created ? "+" : "~")
                    .font(.system(.caption2, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundStyle(event.timestampSource == .created ? .green : .orange)
                Text(formattedTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var typeIcon: String {
        switch event.itemType {
        case .prd:
            "doc.text"
        case .epic:
            "list.bullet.rectangle"
        case .task:
            "checklist"
        }
    }

    private var formattedTime: String {
        let now = Date()
        let interval = now.timeIntervalSince(event.timestamp)

        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            let mins = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return mins > 0 ? "\(hours)h \(mins)m ago" : "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            let hours = Int((interval.truncatingRemainder(dividingBy: 86400)) / 3600)
            return hours > 0 ? "\(days)d \(hours)h ago" : "\(days)d ago"
        }
    }
}
