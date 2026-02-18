import AppKit
import SwiftUI

/// Top-level mode: sessions browser or stats overview.
enum WindowMode: String {
    case sessions = "Sessions"
    case overview = "Overview"
}

/// Date range filter for the session sidebar.
enum DateFilter: String, CaseIterable {
    case all = "All"
    case today = "Today"
    case thisWeek = "Week"
    case thisMonth = "Month"

    /// Returns the cutoff date for this filter, or nil for `.all`.
    func cutoffDate(calendar: Calendar = .current) -> Date? {
        let now = Date()
        switch self {
        case .all:
            return nil
        case .today:
            return calendar.startOfDay(for: now)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start
        }
    }
}

/// Root view for the Claude Sessions window.
/// Toolbar picker switches between Sessions (3-column NavigationSplitView) and Overview (full-width stats).
struct SessionWindowView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("selectedMode") private var mode: WindowMode = .sessions
    @State private var selectedSessionId: String?
    @State private var searchText = ""
    @AppStorage("selectedProjectFilter") private var projectFilterStorage: String = ""
    @State private var dateFilter: DateFilter = .all
    @State private var displayRootSessions: [RootSession] = []

    /// Bridge @AppStorage string to optional project filter.
    private var projectFilter: String? {
        get { projectFilterStorage.isEmpty ? nil : projectFilterStorage }
    }

    private func setProjectFilter(_ value: String?) {
        projectFilterStorage = value ?? ""
    }

    private var sessionStore: SessionStore? { appState.sessionStore }

    /// Whether the export action is currently available.
    private var canExport: Bool {
        guard let store = sessionStore,
              selectedSessionId != nil,
              !store.loadedTurns.isEmpty else { return false }
        return true
    }

    var body: some View {
        Group {
            switch mode {
            case .sessions:
                sessionsView
            case .overview:
                overviewView
            }
        }
        .onAppear {
            if appState.sessionStore == nil {
                appState.setupSessionStore()
            }
            if let pending = appState.pendingSessionId {
                navigateToSession(pending)
                appState.pendingSessionId = nil
            }
        }
        .onChange(of: sessionStore?.rootSessions, initial: true) { _, _ in recomputeFilteredSessions() }
        .onChange(of: searchText) { _, _ in recomputeFilteredSessions() }
        .onChange(of: projectFilterStorage) { _, _ in recomputeFilteredSessions() }
        .onChange(of: dateFilter) { _, _ in recomputeFilteredSessions() }
        .onChange(of: appState.pendingSessionId) { _, newValue in
            guard let pending = newValue else { return }
            navigateToSession(pending)
            appState.pendingSessionId = nil
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                .tag(WindowMode.sessions)
            Label("Overview", systemImage: "chart.bar.xaxis")
                .tag(WindowMode.overview)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    // MARK: - Sessions View (3-column)

    private var sessionsView: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } content: {
            turnListColumn
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 400)
        } detail: {
            turnDetailColumn
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                modePicker
            }
            ToolbarItem(placement: .primaryAction) {
                toolbarButtons
            }
        }
    }

    // MARK: - Overview View (full-width)

    private var overviewView: some View {
        NavigationStack {
            Group {
                if let stats = sessionStore?.stats, let store = sessionStore {
                    StatsOverviewView(stats: stats, sessions: store.sessions, statsCache: store.statsCache)
                } else {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    modePicker
                }
                ToolbarItem(placement: .primaryAction) {
                    toolbarButtons
                }
            }
        }
    }

    // MARK: - Toolbar Buttons (hidden shortcuts + export)

    private var toolbarButtons: some View {
        HStack(spacing: 4) {
            // Hidden buttons for keyboard shortcuts (Cmd+1 / Cmd+2)
            Button("Sessions") {
                mode = .sessions
            }
            .keyboardShortcut("1", modifiers: .command)
            .hidden()
            .frame(width: 0, height: 0)

            Button("Overview") {
                mode = .overview
            }
            .keyboardShortcut("2", modifiers: .command)
            .hidden()
            .frame(width: 0, height: 0)

            // Export button
            Button {
                exportCurrentSession()
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(!canExport)
            .help("Export session to Markdown")
        }
    }

    // MARK: - Export

    private func exportCurrentSession() {
        guard let store = sessionStore,
              let id = selectedSessionId,
              let rs = store.rootSessions.first(where: { $0.id == id }),
              !store.loadedTurns.isEmpty else { return }

        let markdown = SessionExporter.exportToMarkdown(rootSession: rs, turns: store.loadedTurns)
        let safeName = rs.projectName.replacingOccurrences(of: "/", with: "-")
        let suggestedName = "\(safeName)-session.md"
        SessionExporter.saveWithPanel(markdown: markdown, suggestedName: suggestedName)
    }

    // MARK: - Navigation

    private func navigateToSession(_ sessionId: String) {
        mode = .sessions
        selectedSessionId = sessionId
        if let rs = sessionStore?.rootSessions.first(where: { $0.id == sessionId }) {
            Task {
                await sessionStore?.loadSessionDetail(rootSession: rs)
            }
        }
    }

    // MARK: - Filtering

    private var uniqueProjects: [(path: String, name: String)] {
        guard let store = sessionStore else { return [] }
        var seen = Set<String>()
        var result: [(path: String, name: String)] = []
        for rs in store.rootSessions {
            if !rs.projectPath.isEmpty && seen.insert(rs.projectPath).inserted {
                result.append((rs.projectPath, rs.projectName))
            }
        }
        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func recomputeFilteredSessions() {
        guard let store = sessionStore else {
            displayRootSessions = []
            return
        }
        var result = store.rootSessions

        if let filter = projectFilter {
            result = result.filter { $0.projectPath == filter }
        }

        if let cutoff = dateFilter.cutoffDate() {
            result = result.filter { $0.lastActivityAt >= cutoff }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.firstPrompt.lowercased().contains(query) ||
                $0.projectName.lowercased().contains(query) ||
                $0.slug.lowercased().contains(query) ||
                $0.gitBranch.lowercased().contains(query)
            }
        }

        displayRootSessions = result
    }

    // MARK: - Sidebar

    private var selectedProjectName: String {
        if let filter = projectFilter,
           let project = uniqueProjects.first(where: { $0.path == filter }) {
            return project.name
        }
        return "All"
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Search + filter bar
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                    TextField("Search sessions...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    if uniqueProjects.count > 1 {
                        Menu {
                            Button {
                                setProjectFilter(nil)
                            } label: {
                                if projectFilter == nil {
                                    Label("All", systemImage: "checkmark")
                                } else {
                                    Text("All")
                                }
                            }
                            Divider()
                            ForEach(uniqueProjects, id: \.path) { project in
                                Button {
                                    setProjectFilter(project.path)
                                } label: {
                                    if projectFilter == project.path {
                                        Label(project.name, systemImage: "checkmark")
                                    } else {
                                        Text(project.name)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 2) {
                                Text(selectedProjectName)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .font(.caption2)
                            .foregroundStyle(projectFilter != nil ? .primary : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

                // Date filter picker
                Picker("Date", selection: $dateFilter) {
                    ForEach(DateFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if sessionStore?.isLoading == true && displayRootSessions.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    if let p = sessionStore?.scanProgress,
                       let completed = p.completed, let total = p.total, total > 0 {
                        ProgressView(value: Double(completed), total: Double(total))
                            .frame(width: 180)
                        Text(p.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        if let p = sessionStore?.scanProgress {
                            Text(p.message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Loading sessions...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if displayRootSessions.isEmpty && searchText.isEmpty && dateFilter == .all {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Claude Code sessions will appear here")
                }
            } else {
                List(selection: $selectedSessionId) {
                    if displayRootSessions.isEmpty {
                        Text("No sessions match your filters")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(displayRootSessions) { rs in
                            SessionRowView(rootSession: rs, unreadCount: sessionStore?.unreadCounts[rs.id] ?? 0, isSelected: selectedSessionId == rs.id)
                                .tag(rs.id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selectedSessionId) { _, newValue in
                    if let id = newValue,
                       let rs = displayRootSessions.first(where: { $0.id == id }) {
                        Task {
                            await sessionStore?.loadSessionDetail(rootSession: rs)
                        }
                    } else {
                        sessionStore?.clearDetail()
                    }
                }
            }

            if let stats = sessionStore?.stats {
                Divider()
                sidebarFooter(stats: stats)
            }
        }
    }

    // MARK: - Sidebar Footer

    private func sidebarFooter(stats: ClaudeStats) -> some View {
        HStack(spacing: 8) {
            Text("\(stats.totalMessages.formattedCount) msgs")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\u{00B7}")
                .foregroundStyle(.quaternary)
            Text("\(stats.totalInputTokens.formattedCount) in")
                .font(.caption2)
                .foregroundStyle(.blue.opacity(0.8))
            Text("\(stats.totalOutputTokens.formattedCount) out")
                .font(.caption2)
                .foregroundStyle(.green.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Turn List Column (Column 2)

    @ViewBuilder
    private var turnListColumn: some View {
        if let id = selectedSessionId,
           let store = sessionStore,
           let rs = displayRootSessions.first(where: { $0.id == id }) {
            SessionTurnListView(store: store, rootSession: rs)
        } else {
            ContentUnavailableView {
                Label("Select a Session", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Choose a session from the sidebar")
            }
        }
    }

    // MARK: - Turn Detail Column (Column 3)

    @ViewBuilder
    private var turnDetailColumn: some View {
        if let store = sessionStore,
           !store.selectedTurns.isEmpty {
            SessionTurnDetailView(turns: store.selectedTurns)
        } else if selectedSessionId != nil {
            ContentUnavailableView {
                Label("Select a Turn", systemImage: "text.bubble")
            } description: {
                Text("Choose a turn from the list to view its content")
            }
        } else {
            Color.clear
        }
    }
}

