import SwiftUI

struct ProjectDetailView: View {
    let project: Project

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
                    Spacer()
                    StatusBadge(status: prd.status)
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
                if !epic.isConsistent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .help("Progress inconsistency detected")
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
                    Spacer()
                    StatusBadge(status: task.status)
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
                }
            }
        }
    }
}
