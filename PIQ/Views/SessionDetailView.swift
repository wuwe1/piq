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
                        Label(entry.model.shortModelName, systemImage: "cpu")
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

            // Time info
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Started")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(entry.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Duration")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last Active")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(entry.lastActivityAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Total tokens for the session
            if let totalUsage = totalSessionUsage {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(totalUsage.inputTokens.formattedCount) in")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Text("\(totalUsage.outputTokens.formattedCount) out")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var formattedDuration: String {
        let interval = entry.lastActivityAt.timeIntervalSince(entry.createdAt)
        guard interval > 0 else { return "—" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
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

}
