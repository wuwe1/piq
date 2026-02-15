import SwiftUI

/// Detail view showing a full session conversation.
struct SessionDetailView: View {
    let entry: SessionEntry
    @Bindable var store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            Divider()

            if store.isLoadingDetail {
                ProgressView("Loading session...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.loadedTurns.isEmpty {
                ContentUnavailableView {
                    Label("Empty Session", systemImage: "text.bubble")
                } description: {
                    Text("This session has no conversation turns")
                }
            } else {
                turnsList
            }
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.projectName)
                    .font(.headline)
                HStack(spacing: 8) {
                    if !entry.gitBranch.isEmpty {
                        Label(entry.gitBranch, systemImage: "arrow.triangle.branch")
                    }
                    if !entry.model.isEmpty {
                        Label(shortModelName(entry.model), systemImage: "cpu")
                    }
                    if !entry.slug.isEmpty {
                        Text(entry.slug)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(entry.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Total tokens for the session
            if let totalUsage = totalSessionUsage {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(formatTokenCount(totalUsage.inputTokens)) in")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("\(formatTokenCount(totalUsage.outputTokens)) out")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                .padding(.leading, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Turns List

    private var turnsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(store.loadedTurns) { turn in
                        SessionTurnView(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Helpers

    private var totalSessionUsage: TokenUsage? {
        let usages = store.loadedTurns.compactMap(\.totalUsage)
        guard !usages.isEmpty else { return nil }
        return usages.reduce(TokenUsage.zero, +)
    }

    private func shortModelName(_ model: String) -> String {
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
