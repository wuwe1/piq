import SwiftUI

/// Holds expand/collapse state for tool calls and thinking blocks.
/// Owned by SessionDetailView, shared via @Environment so child view
/// recreation (e.g. when new turns arrive) does not reset state.
@MainActor @Observable
final class ExpandState {
    var expandedIds: Set<String> = []

    func isExpanded(_ id: String) -> Bool { expandedIds.contains(id) }

    func toggle(_ id: String) {
        if expandedIds.contains(id) {
            expandedIds.remove(id)
        } else {
            expandedIds.insert(id)
        }
    }

    func expandAll(turns: [SessionTurn]) {
        for turn in turns {
            for pair in turn.toolPairs { expandedIds.insert(pair.id) }
            for msg in turn.assistantMessages {
                for block in msg.contentBlocks {
                    if case .thinking(let id, _) = block { expandedIds.insert(id) }
                }
            }
        }
    }

    func collapseAll() { expandedIds.removeAll() }
}

/// Detail view showing a full session conversation.
struct SessionDetailView: View {
    let entry: SessionEntry
    let sessions: [SessionEntry]
    @Bindable var store: SessionStore
    var onNavigate: ((String) -> Void)?
    @State private var isAllExpanded = false
    @State private var expandState = ExpandState()
    @State private var showInspector = true
    @State private var scrollTarget: String?

    /// The child continuation session (if any) that continues from this session.
    private var childSession: SessionEntry? {
        sessions.first { $0.parentFileId == entry.id }
    }

    /// Turns that have a real user message (for the inspector TOC).
    private var userTurns: [(index: Int, turn: SessionTurn, text: String)] {
        var result: [(index: Int, turn: SessionTurn, text: String)] = []
        var idx = 0
        for turn in store.loadedTurns {
            guard let userMsg = turn.userMessage else { continue }
            idx += 1
            let text = userMsg.contentBlocks.compactMap { block -> String? in
                if case .text(_, let t) = block { return t }
                return nil
            }.first ?? ""
            if !text.isEmpty {
                result.append((idx, turn, text))
            }
        }
        return result
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
        .environment(expandState)
        .onChange(of: entry.id) { _, _ in
            expandState.collapseAll()
            isAllExpanded = false
        }
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
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
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isAllExpanded {
                        expandState.collapseAll()
                    } else {
                        expandState.expandAll(turns: store.loadedTurns)
                    }
                    isAllExpanded.toggle()
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isAllExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    Text(isAllExpanded ? "Collapse" : "Expand")
                }
                .font(.caption2)
                .foregroundStyle(isAllExpanded ? .white : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isAllExpanded ? AnyShapeStyle(.secondary.opacity(0.6)) : AnyShapeStyle(.quaternary), in: Capsule())
            }
            .buttonStyle(.plain)

            // Inspector toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showInspector.toggle() }
            } label: {
                Image(systemName: "sidebar.trailing")
                    .font(.caption)
                    .foregroundStyle(showInspector ? .white : .secondary)
                    .padding(5)
                    .background(showInspector ? AnyShapeStyle(.secondary.opacity(0.6)) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 4))
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
                        SessionTurnView(turn: turn)
                            .id(turn.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(target, anchor: .top)
                }
                scrollTarget = nil
            }
        }
    }

    // MARK: - Inspector

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Turns", systemImage: "list.bullet")
                    .font(.headline)
                Spacer()
                Text("\(userTurns.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(userTurns, id: \.turn.id) { item in
                        inspectorRow(item)
                    }
                }
            }
        }
    }

    private func inspectorRow(_ item: (index: Int, turn: SessionTurn, text: String)) -> some View {
        Button {
            scrollTarget = item.turn.id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Text("\(item.index)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.text.prefix(120))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)

                    inspectorRowMeta(item.turn)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if scrollTarget == item.turn.id {
                Color.accentColor.opacity(0.1)
            }
        }
    }

    private func inspectorRowMeta(_ turn: SessionTurn) -> some View {
        HStack(spacing: 6) {
            if let ts = turn.userMessage?.timestamp {
                Text(ts, format: .dateTime.hour().minute().second())
            }
            let toolCount = turn.toolPairs.count
            if toolCount > 0 {
                Label("\(toolCount)", systemImage: "wrench")
            }
            if let usage = turn.totalUsage {
                Text("\(formatCompact(usage.outputTokens)) out")
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }

    private func formatCompact(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Helpers

    private var totalSessionUsage: TokenUsage? {
        let usages = store.loadedTurns.compactMap(\.totalUsage)
        guard !usages.isEmpty else { return nil }
        return usages.reduce(TokenUsage.zero, +)
    }

}
