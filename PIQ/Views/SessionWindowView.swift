import SwiftUI

/// Sidebar selection: either the stats overview or a specific session.
enum SidebarSelection: Hashable {
    case overview
    case session(String)
}

/// Root view for the Claude Sessions window.
/// Uses NavigationSplitView with sidebar list and detail pane.
struct SessionWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SidebarSelection? = .overview
    @State private var searchText = ""
    @State private var projectFilter: String?
    @State private var displaySessions: [SessionEntry] = []

    private var sessionStore: SessionStore? { appState.sessionStore }

    private var uniqueProjects: [(path: String, name: String)] {
        guard let store = sessionStore else { return [] }
        var seen = Set<String>()
        var result: [(path: String, name: String)] = []
        for session in store.sessions {
            if !session.projectPath.isEmpty && seen.insert(session.projectPath).inserted {
                result.append((session.projectPath, session.projectName))
            }
        }
        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func recomputeFilteredSessions() {
        guard let store = sessionStore else {
            displaySessions = []
            return
        }
        var result = store.sessions

        if let filter = projectFilter {
            result = result.filter { $0.projectPath == filter }
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

        displaySessions = result
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            detail
        }
        .onAppear {
            if appState.sessionStore == nil {
                appState.setupSessionStore()
            }
            // Pick up pending selection from menubar click
            if let pending = appState.pendingSessionId {
                selection = .session(pending)
                appState.pendingSessionId = nil
                if let entry = sessionStore?.sessions.first(where: { $0.id == pending }) {
                    Task {
                        await sessionStore?.loadSessionDetail(entry: entry)
                    }
                }
            }
        }
        .onChange(of: sessionStore?.sessions, initial: true) { _, _ in recomputeFilteredSessions() }
        .onChange(of: searchText) { _, _ in recomputeFilteredSessions() }
        .onChange(of: projectFilter) { _, _ in recomputeFilteredSessions() }
        .onChange(of: appState.pendingSessionId) { _, newValue in
            guard let pending = newValue else { return }
            selection = .session(pending)
            appState.pendingSessionId = nil
            if let entry = sessionStore?.sessions.first(where: { $0.id == pending }) {
                Task {
                    await sessionStore?.loadSessionDetail(entry: entry)
                }
            }
        }
    }

    // MARK: - Navigation

    private func navigateToSession(_ fileId: String) {
        selection = .session(fileId)
        if let entry = sessionStore?.sessions.first(where: { $0.id == fileId }) {
            Task {
                await sessionStore?.loadSessionDetail(entry: entry)
            }
        }
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
                            projectFilter = nil
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
                                projectFilter = project.path
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Session list
            if sessionStore?.isLoading == true && displaySessions.isEmpty {
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
            } else if displaySessions.isEmpty && searchText.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Claude Code sessions will appear here")
                }
            } else {
                List(selection: $selection) {
                    Label("Overview", systemImage: "chart.bar.xaxis")
                        .tag(SidebarSelection.overview)

                    Section {
                        if displaySessions.isEmpty {
                            Text("No sessions match your search")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(displaySessions) { session in
                                SessionRowView(entry: session, unreadCount: sessionStore?.unreadCounts[session.id] ?? 0, isSelected: selection == .session(session.id))
                                    .tag(SidebarSelection.session(session.id))
                            }
                        }
                    } header: {
                        Text("Sessions")
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selection) { _, newValue in
                    if case .session(let id) = newValue,
                       let entry = displaySessions.first(where: { $0.id == id }) {
                        Task {
                            await sessionStore?.loadSessionDetail(entry: entry)
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
            Text("·")
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

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .session(let id):
            if let store = sessionStore,
               let entry = displaySessions.first(where: { $0.id == id }) {
                SessionDetailView(
                    entry: entry,
                    sessions: store.sessions,
                    store: store,
                    onNavigate: { targetId in
                        navigateToSession(targetId)
                    }
                )
            }
        case .overview:
            if let stats = sessionStore?.stats, let store = sessionStore {
                StatsOverviewView(stats: stats, sessions: store.sessions, statsCache: store.statsCache)
            }
        case nil:
            if let stats = sessionStore?.stats, let store = sessionStore {
                StatsOverviewView(stats: stats, sessions: store.sessions, statsCache: store.statsCache)
            } else {
                ContentUnavailableView {
                    Label("Select a Session", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Choose a session from the sidebar to view its conversation")
                }
            }
        }
    }

}
