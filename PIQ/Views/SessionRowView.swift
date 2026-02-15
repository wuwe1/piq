import SwiftUI

/// A single row in the session list sidebar.
struct SessionRowView: View {
    let entry: SessionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top line: project name + time
            HStack {
                Text(entry.projectName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(relativeTime(entry.lastActivityAt))
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
                    metaBadge(text: shortModelName(entry.model), color: .purple)
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
                        text: formatTokens(entry.inputTokens + entry.outputTokens),
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

    private func shortModelName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
