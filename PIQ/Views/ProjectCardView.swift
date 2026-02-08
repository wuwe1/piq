import SwiftUI

struct ProjectCardView: View {
    let project: Project
    @Environment(AppState.self) private var appState

    private var isExpanded: Binding<Bool> {
        let key = project.rootPath.path(percentEncoded: false)
        return Binding(
            get: { appState.expandedProjectPaths.contains(key) },
            set: { newValue in
                if newValue {
                    appState.expandedProjectPaths.insert(key)
                } else {
                    appState.expandedProjectPaths.remove(key)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isExpanded.wrappedValue)

                cardLabel
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isExpanded.wrappedValue.toggle()
            }

            if isExpanded.wrappedValue {
                ProjectDetailView(project: project)
                    .padding(.top, 8)
                    .padding(.leading, 16)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu { projectContextMenu }
    }

    private var cardLabel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .lineLimit(1)

            HStack(spacing: 12) {
                statLabel(count: project.prds.count, label: "PRDs", icon: "doc.text")
                statLabel(count: project.epics.count, label: "Epics", icon: "list.bullet.rectangle")
                statLabel(count: totalTaskCount, label: "Tasks", icon: "checklist")
            }

            if totalTaskCount > 0 {
                ProgressBarView(value: overallPercent, total: totalTaskCount)
            }

            actionBar
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            actionButton("terminal", icon: "terminal") {
                ActionService.openTerminal(at: project.rootPath)
                appState.showToast("Opened Terminal")
            }
            actionButton("claude", icon: "chevron.left.forwardslash.chevron.right") {
                ActionService.openClaudeCode(at: project.rootPath)
                appState.showToast("Opened Claude Code")
            }
            actionButton("copy", icon: "doc.on.doc") {
                let summary = ActionService.projectStatusSummary(project)
                ActionService.copyToClipboard(summary)
                appState.showToast("Copied status")
            }
            Spacer()
        }
    }

    private func actionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var projectContextMenu: some View {
        Button("Copy cd command") {
            ActionService.copyToClipboard("cd \(project.rootPath.path(percentEncoded: false))")
            appState.showToast("Copied cd command")
        }
        Button("Show in Finder") {
            ActionService.showInFinder(project.rootPath)
        }
        Button("Open Terminal") {
            ActionService.openTerminal(at: project.rootPath)
        }
        Button("Open Claude Code") {
            ActionService.openClaudeCode(at: project.rootPath)
        }
        Divider()
        Button("Copy Status") {
            let summary = ActionService.projectStatusSummary(project)
            ActionService.copyToClipboard(summary)
            appState.showToast("Copied status")
        }
    }

    // MARK: - Stats

    private func statLabel(count: Int, label: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var totalTaskCount: Int {
        project.epics.reduce(0) { $0 + $1.tasks.count }
    }

    private var doneTaskCount: Int {
        project.epics.reduce(0) { sum, epic in
            sum + epic.tasks.filter { $0.status == .done }.count
        }
    }

    private var overallPercent: Int {
        guard totalTaskCount > 0 else { return 0 }
        return Int((Double(doneTaskCount) / Double(totalTaskCount) * 100).rounded())
    }
}
