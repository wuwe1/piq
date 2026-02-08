import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @State private var dropTargetPath: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .overlay(alignment: .bottom) {
            if let message = appState.toastMessage {
                ToastView(message: message)
                    .padding(.bottom, 40)
                    .animation(.easeInOut(duration: 0.2), value: appState.toastMessage)
            }
        }
        .task {
            appState.rescanAll()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.secondary)
            Text("PIQ")
                .font(.headline)
            Spacer()
            Text("\(appState.projects.count) projects")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.projects.isEmpty {
            emptyState
        } else {
            projectList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No projects")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Add a scan root via config")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(appState.projects) { project in
                    let path = project.rootPath.path(percentEncoded: false)
                    ProjectCardView(project: project)
                        .overlay(alignment: .top) {
                            if dropTargetPath == path {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentColor)
                                    .frame(height: 2)
                                    .offset(y: -5)
                            }
                        }
                        .draggable(path) {
                            Text(project.name)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            dropTargetPath = nil
                            guard let draggedPath = items.first, draggedPath != path else { return false }
                            appState.moveProject(from: draggedPath, to: path)
                            return true
                        } isTargeted: { targeted in
                            if targeted {
                                dropTargetPath = path
                            } else if dropTargetPath == path {
                                dropTargetPath = nil
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.15), value: dropTargetPath)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                appState.rescanAll()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
                Image(systemName: "gear")
                    .font(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")

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
