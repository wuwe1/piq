import SwiftUI

/// Detail view showing a full session conversation.
struct SessionDetailView: View {
    let entry: SessionEntry
    let sessions: [SessionEntry]
    @Bindable var store: SessionStore
    var onNavigate: ((String) -> Void)?
    @State private var expandAll = false

    /// The child continuation session (if any) that continues from this session.
    private var childSession: SessionEntry? {
        sessions.first { $0.parentFileId == entry.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader

            if entry.isContinuation {
                continuationBanner(
                    label: "Continued from previous session",
                    systemImage: "arrow.left",
                    targetId: entry.parentFileId
                )
            }
            if let child = childSession {
                continuationBanner(
                    label: "Continued in next session",
                    systemImage: "arrow.right",
                    targetId: child.id
                )
            }

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

    // MARK: - Continuation Banner

    private func continuationBanner(label: String, systemImage: String, targetId: String?) -> some View {
        Button {
            if let targetId { onNavigate?(targetId) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(.blue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.blue.opacity(0.06))
        }
        .buttonStyle(.plain)
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

            // Expand all toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expandAll.toggle() }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: expandAll ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    Text(expandAll ? "Collapse" : "Expand")
                }
                .font(.caption2)
                .foregroundStyle(expandAll ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(expandAll ? AnyShapeStyle(.secondary.opacity(0.6)) : AnyShapeStyle(.quaternary), in: Capsule())
            }
            .buttonStyle(.plain)
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
                        SessionTurnView(turn: turn, expandAll: expandAll)
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
