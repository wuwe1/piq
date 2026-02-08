import SwiftUI

struct ProjectCardView: View {
    let project: Project
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ProjectDetailView(project: project)
                .padding(.top, 4)
        } label: {
            cardLabel
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        }
    }

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
