import SwiftUI

/// Column 2: displays the turn summary list for a selected root session.
struct SessionTurnListView: View {
    @Bindable var store: SessionStore
    let rootSession: RootSession

    @Environment(\.colorScheme) private var colorScheme
    @State private var userTurns: [UserTurnItem] = []
    @State private var displayTurns: [UserTurnItem] = []  // cached filtered + reversed
    @State private var searchText: String = ""

    struct UserTurnItem: Identifiable {
        let id: String          // turn.id
        let index: Int          // 1-based user turn number
        let globalIndex: Int    // index into store.loadedTurns (the turn with response)
        let turn: SessionTurn   // the main turn (with response)
        let allTurns: [SessionTurn]  // all merged turns (pending no-response + main)
        let text: String        // user message preview
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionHeader
            Divider()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Search turns...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()

            if store.isLoadingDetail {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.loadedTurns.isEmpty {
                ContentUnavailableView {
                    Label("Empty Session", systemImage: "text.bubble")
                } description: {
                    Text("This session has no conversation turns")
                }
            } else {
                turnList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.loadedTurnsVersion, initial: true) { _, _ in
            userTurns = Self.computeUserTurns(from: store.loadedTurns)
            recomputeDisplayTurns()
            // Sync selectedTurns for auto-selected turn (e.g. on initial load)
            if let idx = store.selectedTurnIndex,
               let item = userTurns.first(where: { $0.globalIndex == idx }) {
                store.selectedTurns = item.allTurns
            }
        }
        .onChange(of: searchText) { _, _ in recomputeDisplayTurns() }
    }

    private func recomputeDisplayTurns() {
        var filtered = userTurns
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = userTurns.filter { item in
                if item.text.lowercased().contains(query) { return true }
                if let preview = assistantPreview(item.turn),
                   preview.lowercased().contains(query) { return true }
                return false
            }
        }
        displayTurns = filtered.reversed()
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rootSession.projectName)
                    .font(.headline)
                HStack(spacing: 8) {
                    if !rootSession.gitBranch.isEmpty {
                        Label(rootSession.gitBranch, systemImage: "arrow.triangle.branch")
                    }
                    if !rootSession.model.isEmpty {
                        Label(rootSession.model.shortModelName, systemImage: "cpu")
                    }
                    if !rootSession.slug.isEmpty {
                        Text(rootSession.slug)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Duration")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(rootSession.inputTokens.formattedCount) in")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text("\(rootSession.outputTokens.formattedCount) out")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var formattedDuration: String {
        let interval = rootSession.lastActivityAt.timeIntervalSince(rootSession.createdAt)
        guard interval > 0 else { return "—" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    // MARK: - Turn List

    private var turnIndexBinding: Binding<Int?> {
        Binding(
            get: { store.selectedTurnIndex },
            set: { newValue in
                store.selectedTurnIndex = newValue
                if let idx = newValue,
                   let item = userTurns.first(where: { $0.globalIndex == idx }) {
                    store.selectedTurns = item.allTurns
                } else {
                    store.selectedTurns = []
                }
            }
        )
    }

    private var turnList: some View {
        List {
            ForEach(displayTurns) { item in
                let isSelected = store.selectedTurnIndex == item.globalIndex
                turnRow(item)
                    .listRowBackground(
                        isSelected
                            ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                            : nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        turnIndexBinding.wrappedValue = item.globalIndex
                    }
                    .environment(\.colorScheme, isSelected ? .dark : colorScheme)
            }
        }
        .listStyle(.inset)
        .onKeyPress(.upArrow) {
            navigateTurn(direction: .up, in: displayTurns)
        }
        .onKeyPress(.downArrow) {
            navigateTurn(direction: .down, in: displayTurns)
        }
    }

    private enum NavigationDirection {
        case up, down
    }

    private func navigateTurn(direction: NavigationDirection, in reversedTurns: [UserTurnItem]) -> KeyPress.Result {
        guard !reversedTurns.isEmpty else { return .ignored }

        guard let currentIndex = store.selectedTurnIndex,
              let currentPos = reversedTurns.firstIndex(where: { $0.globalIndex == currentIndex }) else {
            // Nothing selected: select the first item (most recent)
            turnIndexBinding.wrappedValue = reversedTurns.first?.globalIndex
            return .handled
        }

        let nextPos: Int
        switch direction {
        case .up:
            // Up moves toward older turns (higher index in reversedTurns)
            nextPos = currentPos + 1
        case .down:
            // Down moves toward newer turns (lower index in reversedTurns)
            nextPos = currentPos - 1
        }

        guard reversedTurns.indices.contains(nextPos) else { return .ignored }
        turnIndexBinding.wrappedValue = reversedTurns[nextPos].globalIndex
        return .handled
    }

    // MARK: - Turn Row

    @State private var hoveredTurnId: String?

    private var isSystemMessage: (String) -> Bool {{ text in
        text.hasPrefix("This session is being continued") ||
        text.hasPrefix("<task-notification>") ||
        text.hasPrefix("Base directory for this skill:")
    }}

    private func assistantPreview(_ turn: SessionTurn) -> String? {
        for msg in turn.assistantMessages.reversed() {
            for block in msg.contentBlocks.reversed() {
                if case .text(_, let t) = block {
                    let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return String(trimmed.prefix(120)) }
                }
            }
        }
        return nil
    }

    private func turnRow(_ item: UserTurnItem) -> some View {
        let isSystem = isSystemMessage(item.text)
        let isSelected = store.selectedTurnIndex == item.globalIndex

        return HStack(alignment: .top, spacing: 8) {
            Text("\(item.index)")
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    isSelected ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(.quaternary),
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                // Line 1: timestamp
                if let ts = item.turn.userMessage?.timestamp {
                    Text(ts, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Line 2: user message
                previewLine(
                    icon: "bubble.right",
                    text: item.text.isEmpty ? "(no prompt)" : String(item.text.prefix(120)),
                    style: isSystem ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary),
                    italic: isSystem
                )

                // Line 3: assistant response
                if let preview = assistantPreview(item.turn) {
                    previewLine(
                        icon: "sparkles",
                        text: preview,
                        style: AnyShapeStyle(.secondary),
                        italic: false
                    )
                }

                // Line 4: stats
                turnMeta(item.turn)
            }
        }
        .padding(.vertical, 4)
    }

    private func previewLine(icon: String, text: String, style: AnyShapeStyle, italic: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .frame(width: 10)
            Text(text)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(style)
                .italic(italic)
        }
    }

    private func turnMeta(_ turn: SessionTurn) -> some View {
        HStack(spacing: 6) {
            let toolCount = turn.toolPairs.count
            if toolCount > 0 {
                badge(text: "\(toolCount)", icon: "wrench", color: .blue)
            }
            if let usage = turn.totalUsage {
                badge(
                    text: "\(formatCompact(usage.inputTokens))/\(formatCompact(usage.outputTokens))",
                    icon: "sparkle",
                    color: .green
                )
            }
            Spacer()
        }
    }

    private func badge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(color)
        .lineLimit(1)
    }

    private func formatCompact(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    // MARK: - Compute User Turns

    static func computeUserTurns(from turns: [SessionTurn]) -> [UserTurnItem] {
        var result: [UserTurnItem] = []
        var userIdx = 0
        var pendingTexts: [String] = []
        var pendingTurns: [SessionTurn] = []

        for (globalIndex, turn) in turns.enumerated() {
            guard let userMsg = turn.userMessage else { continue }

            let text = userMsg.contentBlocks.compactMap { block -> String? in
                if case .text(_, let t) = block { return t }
                return nil
            }.first ?? ""

            let hasImage = userMsg.contentBlocks.contains { block in
                if case .toolResult = block { return true }
                return false
            }

            let hasResponse = !turn.assistantMessages.isEmpty || !turn.toolPairs.isEmpty

            if !hasResponse {
                if !text.isEmpty { pendingTexts.append(text) }
                pendingTurns.append(turn)
                continue
            }

            userIdx += 1
            if !text.isEmpty { pendingTexts.append(text) }
            let combined = pendingTexts.joined(separator: "\n")
            pendingTexts = []

            let displayText = combined.isEmpty && hasImage ? "(image)" : combined

            var allTurns = pendingTurns
            allTurns.append(turn)
            pendingTurns = []

            result.append(UserTurnItem(
                id: "\(turn.id)-\(turn.assistantMessages.count)-\(turn.toolPairs.count)",
                index: userIdx,
                globalIndex: globalIndex,
                turn: turn,
                allTurns: allTurns,
                text: displayText
            ))
        }
        return result
    }
}
