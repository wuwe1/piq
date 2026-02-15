import SwiftUI

/// Root view for the Claude Sessions window.
/// Uses NavigationSplitView with sidebar list and detail pane.
struct SessionWindowView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSessionId: String?
    @State private var searchText = ""
    @State private var projectFilter: String?

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
                selectedSessionId = pending
                appState.pendingSessionId = nil
                if let entry = filteredSessions.first(where: { $0.id == pending }) {
                    Task {
                        await sessionStore?.loadSessionDetail(entry: entry)
                    }
                }
            }
        }
        .onChange(of: appState.pendingSessionId) { _, newValue in
            guard let pending = newValue else { return }
            selectedSessionId = pending
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
            if filteredSessions.isEmpty {
                ContentUnavailableView {
                    Label("No Sessions", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    if searchText.isEmpty {
                        Text("Claude Code sessions will appear here")
                    } else {
                        Text("No sessions match your search")
                    }
                }
            } else {
                List(filteredSessions, selection: $selectedSessionId) { session in
                    SessionRowView(entry: session)
                        .tag(session.id)
                }
                .listStyle(.sidebar)
                .onChange(of: selectedSessionId) { _, newValue in
                    if let id = newValue,
                       let entry = filteredSessions.first(where: { $0.id == id }) {
                        Task {
                            await sessionStore?.loadSessionDetail(entry: entry)
                        }
                    } else {
                        sessionStore?.clearDetail()
                    }
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let store = sessionStore,
           let sessionId = selectedSessionId,
           let entry = filteredSessions.first(where: { $0.id == sessionId }) {
            SessionDetailView(entry: entry, store: store)
        } else {
            ContentUnavailableView {
                Label("Select a Session", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Choose a session from the sidebar to view its conversation")
            }
        }
    }

}
