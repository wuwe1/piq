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

            // Three preview lines
            VStack(alignment: .leading, spacing: 2) {
                // First user prompt
                previewLine(
                    icon: "bubble.right",
                    text: entry.firstPrompt.isEmpty ? "(no prompt)" : entry.firstPrompt,
                    color: .primary
                )

                // Last user prompt (only if different from first)
                if !entry.lastPrompt.isEmpty && entry.lastPrompt != entry.firstPrompt {
                    previewLine(
                        icon: "bubble.right.fill",
                        text: entry.lastPrompt,
                        color: .primary.opacity(0.7)
                    )
                }

                // Last assistant output
                if !entry.lastOutput.isEmpty {
                    previewLine(
                        icon: "sparkles",
                        text: entry.lastOutput,
                        color: .secondary
                    )
                }
            }

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
                        text: "\(entry.inputTokens.formattedCount)/\(entry.outputTokens.formattedCount)",
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

    private func previewLine(icon: String, text: String, color: some ShapeStyle) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(color)
        }
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
