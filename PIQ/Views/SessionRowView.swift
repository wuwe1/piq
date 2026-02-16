import SwiftUI

/// A single row in the session list sidebar.
struct SessionRowView: View {
    let entry: SessionEntry

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top line: project name + time
            HStack {
                Text(entry.projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(Self.relativeFormatter.localizedString(for: entry.lastActivityAt, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // First prompt
            Text(entry.firstPrompt.isEmpty ? "(no prompt)" : entry.firstPrompt)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.primary)

            // Bottom line: metadata badges
            HStack(spacing: 6) {
                if !entry.model.isEmpty {
                    metaBadge(text: entry.model.shortModelName, color: .purple)
                }
                if !entry.gitBranch.isEmpty {
                    metaBadge(
                        text: entry.gitBranch,
                        icon: "arrow.triangle.branch",
                        color: .orange
                    )
                }
                if entry.userTurnCount > 0 {
                    metaBadge(
                        text: "\(entry.userTurnCount)",
                        icon: "text.bubble",
                        color: .blue
                    )
                }
                if entry.outputTokens > 0 {
                    metaBadge(
                        text: (entry.inputTokens + entry.outputTokens).formattedCount,
                        icon: "sparkle",
                        color: .green
                    )
                }
                if entry.hasSubagents {
                    metaBadge(
                        text: "agents",
                        icon: "person.2",
                        color: .cyan
                    )
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func metaBadge(text: String, icon: String? = nil, color: Color) -> some View {
        HStack(spacing: 2) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(color)
        .lineLimit(1)
    }
}
