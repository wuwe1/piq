import Combine
import SwiftUI

/// Shared timer that fires every 60s to refresh relative timestamps.
private nonisolated(unsafe) let relativeTimeTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

/// A single row in the session list sidebar.
struct SessionRowView: View {
    let entry: SessionEntry
    var unreadCount: Int = 0
    var isSelected: Bool = false

    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top line: project name + badge
            HStack {
                Text(entry.projectName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    .lineLimit(1)
                Spacer()
            }
            .overlay(alignment: .topTrailing) {
                if unreadCount > 0 {
                    unreadBadge
                }
            }

            // Three preview lines
            VStack(alignment: .leading, spacing: 2) {
                // First user prompt
                previewLine(
                    icon: "bubble.right",
                    text: entry.firstPrompt.isEmpty ? "(no prompt)" : entry.firstPrompt,
                    style: isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
                )

                // Last user prompt (only if different from first)
                if !entry.lastPrompt.isEmpty && entry.lastPrompt != entry.firstPrompt {
                    previewLine(
                        icon: "bubble.right.fill",
                        text: entry.lastPrompt,
                        style: isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.primary.opacity(0.7))
                    )
                }

                // Last assistant output
                if !entry.lastOutput.isEmpty {
                    previewLine(
                        icon: "sparkles",
                        text: entry.lastOutput,
                        style: isSelected ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.secondary)
                    )
                }
            }

            // Bottom line: metadata badges + time
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
                Text(Self.relativeTime(from: entry.lastActivityAt, to: now))
                    .font(.caption2)
                    .foregroundStyle(AnyShapeStyle(isSelected ? AnyShapeStyle(.white.opacity(0.5)) : AnyShapeStyle(.tertiary)))
            }
        }
        .padding(.vertical, 4)
        .onReceive(relativeTimeTimer) { now = $0 }
    }

    private func previewLine(icon: String, text: String, style: AnyShapeStyle) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(AnyShapeStyle(isSelected ? AnyShapeStyle(.white.opacity(0.5)) : AnyShapeStyle(.tertiary)))
                .frame(width: 10)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(style)
        }
    }

    private var unreadBadge: some View {
        let label = unreadCount > 99 ? "99+" : "\(unreadCount)"
        let size: CGFloat = 16
        return Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: size, idealHeight: size)
            .fixedSize()
            .padding(.horizontal, unreadCount > 9 ? 3 : 0)
            .background(.red.opacity(0.85), in: Capsule())
    }

    /// Friendly relative time without seconds-level precision.
    private static func relativeTime(from date: Date, to now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        return "\(months / 12)y ago"
    }

    private func metaBadge(text: String, icon: String? = nil, color: Color) -> some View {
        HStack(spacing: 2) {
            if let icon {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(isSelected ? .white.opacity(0.8) : color)
        .lineLimit(1)
    }
}
