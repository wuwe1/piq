import Charts
import SwiftUI

struct StatsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                trendSection
                activitySection
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Summary", systemImage: "chart.pie")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            // Global task stats
            globalTaskStats

            // Per-project progress
            if !appState.projects.isEmpty {
                ForEach(appState.projects) { project in
                    projectProgressRow(project)
                }
            }

            // Epic status distribution
            if !allEpics.isEmpty {
                epicStatusDistribution
            }
        }
    }

    private var globalTaskStats: some View {
        let total = totalTaskCount
        let done = doneTaskCount
        let rate = total > 0 ? Int((Double(done) / Double(total) * 100).rounded()) : 0

        return HStack(spacing: 16) {
            statBox(value: "\(total)", label: "Tasks")
            statBox(value: "\(done)", label: "Done")
            statBox(value: "\(rate)%", label: "Rate")
        }
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func projectProgressRow(_ project: Project) -> some View {
        let taskCount = project.epics.reduce(0) { $0 + $1.tasks.count }
        let doneCount = project.epics.reduce(0) { sum, epic in
            sum + epic.tasks.filter { $0.status == .done }.count
        }
        let percent = taskCount > 0 ? Int((Double(doneCount) / Double(taskCount) * 100).rounded()) : 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                Text("\(doneCount)/\(taskCount)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ProgressBarView(value: percent, total: 100)
        }
    }

    private var epicStatusDistribution: some View {
        let counts = epicStatusCounts

        return VStack(alignment: .leading, spacing: 4) {
            Text("Epic Status")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                epicCountBadge(label: "Backlog", count: counts.backlog, color: .gray)
                epicCountBadge(label: "In Progress", count: counts.inProgress, color: .blue)
                epicCountBadge(label: "Done", count: counts.done, color: .green)
            }
        }
    }

    private func epicCountBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(count)")
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Trend Section

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("7-Day Trend", systemImage: "chart.bar")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let store = appState.activityStore {
                let data = store.tasksCompletedPerDay(lastDays: 7)
                if data.contains(where: { $0.count > 0 }) {
                    trendChart(data: data)
                } else {
                    trendEmptyState
                }
            } else {
                trendEmptyState
            }

            // Average task duration
            if let store = appState.activityStore, let avg = store.averageTaskDuration() {
                averageDurationRow(avg)
            }
        }
    }

    private func trendChart(data: [(date: Date, count: Int)]) -> some View {
        Chart {
            ForEach(data, id: \.date) { entry in
                BarMark(
                    x: .value("Day", entry.date, unit: .day),
                    y: .value("Tasks", entry.count)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 120)
    }

    private var trendEmptyState: some View {
        Text("No task completions yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }

    private func averageDurationRow(_ duration: TimeInterval) -> some View {
        HStack {
            Text("Avg task duration")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(formattedDuration(duration))
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.medium)
        }
    }

    // MARK: - Activity Section

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Activity", systemImage: "clock")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let store = appState.activityStore {
                let recent = store.recentEvents(limit: 20)
                if recent.isEmpty {
                    activityEmptyState
                } else {
                    ForEach(recent.reversed()) { event in
                        ActivityRowView(event: event)
                    }
                }
            } else {
                activityEmptyState
            }
        }
    }

    private var activityEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No activity yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Computed Properties

    private var allEpics: [EpicItem] {
        appState.projects.flatMap(\.epics)
    }

    private var totalTaskCount: Int {
        appState.projects.reduce(0) { sum, project in
            sum + project.epics.reduce(0) { $0 + $1.tasks.count }
        }
    }

    private var doneTaskCount: Int {
        appState.projects.reduce(0) { sum, project in
            sum + project.epics.reduce(0) { epicSum, epic in
                epicSum + epic.tasks.filter { $0.status == .done }.count
            }
        }
    }

    private var epicStatusCounts: (backlog: Int, inProgress: Int, done: Int) {
        var backlog = 0
        var inProgress = 0
        var done = 0
        for epic in allEpics {
            switch epic.status {
            case .backlog, .open:
                backlog += 1
            case .inProgress:
                inProgress += 1
            case .done:
                done += 1
            }
        }
        return (backlog, inProgress, done)
    }

    // MARK: - Helpers

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
