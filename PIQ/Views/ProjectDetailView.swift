import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !project.prds.isEmpty {
                prdSection
            }
            if !project.epics.isEmpty {
                epicSection
            }
            if !project.worktrees.isEmpty {
                worktreeSection
            }
        }
        .padding(.leading, 4)
    }

    // MARK: - PRDs

    private var prdSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("PRDs", systemImage: "doc.text")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(project.prds) { prd in
                HStack(spacing: 6) {
                    Text(prd.name)
                        .font(.caption)
                        .lineLimit(1)
                        .onTapGesture {
                            ActionService.openFile(prd.filePath)
                        }
                        .help("Click to open in editor")
                    Spacer()
                    StatusBadge(status: prd.status)
                }
                .contextMenu {
                    fileContextMenu(name: prd.name, filePath: prd.filePath)
                }
            }
        }
    }

    // MARK: - Epics

    private var epicSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Epics", systemImage: "list.bullet.rectangle")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(project.epics) { epic in
                epicRow(epic)
            }
        }
    }

    private func epicRow(_ epic: EpicItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(epic.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .onTapGesture {
                        ActionService.openFile(epic.filePath)
                    }
                    .help("Click to open in editor")
                if !epic.isConsistent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .help("Progress inconsistency detected")
                }
                if let github = epic.github {
                    linkButton(url: github)
                }
                Spacer()
                StatusBadge(status: epic.status)
            }

            ProgressBarView(
                value: epic.progressPercent,
                total: epic.tasks.count
            )

            if !epic.tasks.isEmpty {
                tasksUnderEpic(epic.tasks)
            }
        }
        .padding(.leading, 4)
        .contextMenu {
            fileContextMenu(name: epic.name, filePath: epic.filePath)
            if epic.github != nil {
                Divider()
                Button("Open on GitHub") {
                    if let url = epic.github { ActionService.openInBrowser(url) }
                }
            }
            Divider()
            Button("Copy /pm:epic-sync") {
                ActionService.copyToClipboard("/pm:epic-sync \(epic.name)")
                appState.showToast("Copied epic command")
            }
        }
    }

    private func tasksUnderEpic(_ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tasks) { task in
                HStack(spacing: 4) {
                    Text(task.taskID)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(task.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .onTapGesture {
                            ActionService.copyToClipboard("/pm:issue-start \(task.taskID)")
                            appState.showToast("Copied issue command")
                        }
                        .help("Click to copy command")
                    if let github = task.github {
                        linkButton(url: github)
                    }
                    Spacer()
                    StatusBadge(status: task.status)
                }
                .contextMenu {
                    fileContextMenu(name: task.name, filePath: task.filePath)
                    if task.github != nil {
                        Divider()
                        Button("Open on GitHub") {
                            if let url = task.github { ActionService.openInBrowser(url) }
                        }
                    }
                    Divider()
                    Button("Copy /pm:issue-start") {
                        ActionService.copyToClipboard("/pm:issue-start \(task.taskID)")
                        appState.showToast("Copied issue command")
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    // MARK: - Worktrees

    private var worktreeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Worktrees", systemImage: "arrow.triangle.branch")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ForEach(project.worktrees) { worktree in
                HStack(spacing: 4) {
                    Image(systemName: "arrow.branch")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(worktree.branch)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .onTapGesture {
                            ActionService.copyToClipboard("cd \(worktree.path.path(percentEncoded: false))")
                            appState.showToast("Copied cd command")
                        }
                        .help("Click to copy cd command")
                }
                .contextMenu {
                    Button("Open Terminal") {
                        ActionService.openTerminal(at: worktree.path)
                    }
                    Button("Show in Finder") {
                        ActionService.showInFinder(worktree.path)
                    }
                    Button("Copy Path") {
                        ActionService.copyToClipboard(worktree.path.path(percentEncoded: false))
                        appState.showToast("Copied path")
                    }
                }
            }
        }
    }

    // MARK: - Shared

    private func linkButton(url: URL) -> some View {
        Button {
            ActionService.openInBrowser(url)
        } label: {
            Image(systemName: "link")
                .font(.caption2)
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .help("Open on GitHub")
    }

    @ViewBuilder
    private func fileContextMenu(name: String, filePath: URL) -> some View {
        Button("Open in Editor") {
            ActionService.openFile(filePath)
        }
        Button("Show in Finder") {
            ActionService.showInFinder(filePath)
        }
        Button("Copy File Path") {
            ActionService.copyToClipboard(filePath.path(percentEncoded: false))
            appState.showToast("Copied path")
        }
    }
}
