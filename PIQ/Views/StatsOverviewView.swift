import SwiftUI
import Charts

struct StatsOverviewView: View {
    let stats: ClaudeStats
    let sessions: [SessionEntry]
    let projectGroups: [(name: String, path: String, count: Int, tokens: Int)]
    let recentHourly: [(date: Date, count: Int)]

    init(stats: ClaudeStats, sessions: [SessionEntry]) {
        self.stats = stats
        self.sessions = sessions

        var groups: [String: (name: String, count: Int, tokens: Int)] = [:]
        for session in sessions {
            let key = session.projectPath.isEmpty ? "(unknown)" : session.projectPath
            let name = session.projectPath.isEmpty ? "Unknown" : session.projectName
            let existing = groups[key] ?? (name: name, count: 0, tokens: 0)
            groups[key] = (
                name: existing.name,
                count: existing.count + 1,
                tokens: existing.tokens + session.inputTokens + session.outputTokens
            )
        }
        self.projectGroups = groups.map {
            (name: $0.value.name, path: $0.key, count: $0.value.count, tokens: $0.value.tokens)
        }.sorted { $0.count > $1.count }

        // Build 24-hour timeline ending at the current hour
        let calendar = Calendar.current
        let currentHour = calendar.dateInterval(of: .hour, for: Date())!.start
        let startHour = currentHour.addingTimeInterval(-23 * 3600)

        var buckets: [Date: Int] = [:]
        for i in 0..<24 {
            buckets[startHour.addingTimeInterval(Double(i) * 3600)] = 0
        }
        for s in sessions {
            let hour = calendar.dateInterval(of: .hour, for: s.createdAt)?.start ?? s.createdAt
            if hour >= startHour, buckets[hour] != nil {
                buckets[hour, default: 0] += s.messageCount
            }
        }
        self.recentHourly = buckets.sorted { $0.key < $1.key }
            .map { (date: $0.key, count: $0.value) }
    }

    private var daysSinceFirst: Int {
        guard let first = stats.firstSessionDate else { return 0 }
        return max(1, Calendar.current.dateComponents([.day], from: first, to: Date()).day ?? 0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                summaryCards
                dailyActivityChart
                HStack(spacing: 16) {
                    activeHoursChart
                    modelUsageChart
                }
                projectsList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatCard(
                icon: "bubble.left.and.bubble.right",
                value: "\(stats.totalSessions)",
                label: "Sessions",
                color: .blue
            )
            StatCard(
                icon: "arrow.down.circle",
                value: stats.totalInputTokens.formattedCount,
                label: "Input Tokens",
                color: .cyan
            )
            StatCard(
                icon: "arrow.up.circle",
                value: stats.totalOutputTokens.formattedCount,
                label: "Output Tokens",
                color: .green
            )
            StatCard(
                icon: "calendar",
                value: "\(daysSinceFirst)",
                label: "Days Active",
                color: .orange
            )
        }
    }

    // MARK: - Daily Activity

    private var dailyActivityChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Activity")
                .font(.headline)
                .foregroundStyle(.secondary)

            Chart(stats.dailyActivity) { day in
                BarMark(
                    x: .value("Date", parseDate(day.date) ?? Date()),
                    y: .value("Messages", day.messageCount)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .chartXScale(range: .plotDimension(padding: 12))
            .frame(height: 160)
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Active Hours

    private var activeHoursChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Hours (24h)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Chart(recentHourly, id: \.date) { item in
                BarMark(
                    x: .value("Time", item.date),
                    y: .value("Messages", item.count)
                )
                .foregroundStyle(.purple.gradient)
                .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Model Usage

    private var modelUsageChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Usage")
                .font(.headline)
                .foregroundStyle(.secondary)

            Chart(stats.modelBreakdown) { model in
                BarMark(
                    x: .value("Tokens", model.totalTokens),
                    y: .value("Model", model.displayName)
                )
                .foregroundStyle(colorForModel(model.displayName).gradient)
                .cornerRadius(3)
                .annotation(position: .trailing, spacing: 4) {
                    Text(model.totalTokens.formattedCount)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Projects

    private var projectsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Projects")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(projectGroups, id: \.path) { project in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(project.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer()
                        Text("\(project.count) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(project.tokens.formattedCount + " tokens")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    if project.path != projectGroups.last?.path {
                        Divider().padding(.leading, 32)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Helpers

    private func parseDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    private func colorForModel(_ name: String) -> Color {
        if name.contains("Opus") { return .blue }
        if name.contains("Sonnet") { return .green }
        if name.contains("Haiku") { return .orange }
        return .gray
    }
}

// MARK: - StatCard

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(.rounded)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}
