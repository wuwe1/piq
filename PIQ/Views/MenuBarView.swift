import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
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
                $0.gitBranch.lowercased().contains(query)
            }
        }

        displaySessions = result
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .onChange(of: sessionStore?.sessions, initial: true) { _, _ in recomputeFilteredSessions() }
        .onChange(of: searchText) { _, _ in recomputeFilteredSessions() }
        .onChange(of: projectFilter) { _, _ in recomputeFilteredSessions() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "eyes")
                .foregroundStyle(.secondary)
            Text("PIQ")
                .font(.headline)
            Spacer()
            Text("\(sessionStore?.sessions.count ?? 0) sessions")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button {
                sessionStore?.rescan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Search & Filter

    private var selectedProjectName: String {
        if let filter = projectFilter,
           let project = uniqueProjects.first(where: { $0.path == filter }) {
            return project.name
        }
        return "All"
    }

    private var searchBar: some View {
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
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if sessionStore?.isLoading == true {
            VStack(spacing: 8) {
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
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displaySessions.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                Text(searchText.isEmpty ? "No sessions" : "No matches")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displaySessions) { session in
                        sessionRow(session)
                        if session.id != displaySessions.last?.id {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: SessionEntry) -> some View {
        Button {
            appState.pendingSessionId = session.id
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "sessions")
        } label: {
            SessionRowView(entry: session)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let stats = sessionStore?.stats {
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
            }

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "sessions")
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open window")

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.footnote)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
