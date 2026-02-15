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
    @State private var stats: ClaudeStats?

    private var sessionStore: SessionStore? { appState.sessionStore }

    private var filteredSessions: [SessionEntry] {
        guard let store = sessionStore else { return [] }
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

        return result
    }

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
                if let entry = filteredSessions.first(where: { $0.id == pending }) {
                    Task {
                        await sessionStore?.loadSessionDetail(entry: entry)
                    }
                }
            }
        }
        .task {
            stats = await Task.detached { [sessionStore] in
                sessionStore?.loadStats()
            }.value
        }
        .onChange(of: appState.pendingSessionId) { _, newValue in
            guard let pending = newValue else { return }
            selection = .session(pending)
            appState.pendingSessionId = nil
            if let entry = filteredSessions.first(where: { $0.id == pending }) {
                Task {
                    await sessionStore?.loadSessionDetail(entry: entry)
                }
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
            if filteredSessions.isEmpty && searchText.isEmpty {
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
                        if filteredSessions.isEmpty {
                            Text("No sessions match your search")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(filteredSessions) { session in
                                SessionRowView(entry: session)
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
                       let entry = filteredSessions.first(where: { $0.id == id }) {
                        Task {
                            await sessionStore?.loadSessionDetail(entry: entry)
                        }
                    } else {
                        sessionStore?.clearDetail()
                    }
                }
            }

            if let stats {
                Divider()
                sidebarFooter(stats: stats)
            }
        }
    }

    // MARK: - Sidebar Footer

    private func sidebarFooter(stats: ClaudeStats) -> some View {
        HStack(spacing: 8) {
            Text("\(formatCount(stats.totalMessages)) msgs")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.quaternary)
            Text("\(formatCount(stats.totalInputTokens)) in")
                .font(.caption2)
                .foregroundStyle(.blue.opacity(0.8))
            Text("\(formatCount(stats.totalOutputTokens)) out")
                .font(.caption2)
                .foregroundStyle(.green.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .session(let id):
            if let store = sessionStore,
               let entry = filteredSessions.first(where: { $0.id == id }) {
                SessionDetailView(entry: entry, store: store)
            }
        case .overview:
            if let stats, let store = sessionStore {
                StatsOverviewView(stats: stats, sessions: store.sessions)
            }
        case nil:
            if let stats, let store = sessionStore {
                StatsOverviewView(stats: stats, sessions: store.sessions)
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
