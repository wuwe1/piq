import SwiftUI

struct StatusBadge: View {
    let status: ItemStatus

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .backlog:
            "Backlog"
        case .open:
            "Open"
        case .inProgress:
            "In Progress"
        case .done:
            "Done"
        }
    }

    private var color: Color {
        switch status {
        case .backlog:
            .gray
        case .open:
            .orange
        case .inProgress:
            .blue
        case .done:
            .green
        }
    }
}
