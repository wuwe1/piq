import SwiftUI
import Charts

struct StatsOverviewView: View {
    let stats: ClaudeStats
    let sessions: [SessionEntry]
    let statsCache: StatsCache?
    let projectGroups: [(name: String, path: String, count: Int, tokens: Int)]
    let recentHourly: [(date: Date, count: Int)]

    @State private var selectedDay: Date?
    @State private var selectedModelDay: Date?
    @State private var selectedHour: Date?

    init(stats: ClaudeStats, sessions: [SessionEntry], statsCache: StatsCache? = nil) {
        self.stats = stats
        self.sessions = sessions
        self.statsCache = statsCache

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
            let hour = calendar.dateInterval(of: .hour, for: s.lastActivityAt)?.start ?? s.lastActivityAt
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
                if statsCache != nil {
                    dailyModelTokensChart
                }
                activeHoursChart
                modelUsageChart
                projectsList
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Summary Cards

    private var avgTurnsPerSession: String {
        guard stats.totalSessions > 0 else { return "0" }
        let avg = Double(stats.totalMessages) / Double(stats.totalSessions) / 2.0
        if avg >= 100 { return "\(Int(avg))" }
        return String(format: "%.1f", avg)
    }

    private var summaryCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
            StatCard(
                icon: "bubble.left.and.bubble.right",
                value: "\(stats.totalSessions)",
                label: "Sessions",
                color: .blue
            )
            StatCard(
                icon: "folder",
                value: "\(projectGroups.count)",
                label: "Projects",
                color: .indigo
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
                icon: "book.pages",
                value: stats.totalCacheReadTokens.formattedCount,
                label: "Cache Read",
                color: .teal
            )
            if let cache = statsCache {
                StatCard(
                    icon: "wrench.and.screwdriver",
                    value: cache.totalToolCalls.formattedCount,
                    label: "Tool Calls",
                    color: .purple
                )
            }
            StatCard(
                icon: "arrow.triangle.turn.up.right.diamond",
                value: avgTurnsPerSession,
                label: "Avg Turns",
                color: .pink
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

            Chart {
                ForEach(stats.dailyActivity) { day in
                    BarMark(
                        x: .value("Date", parseDate(day.date) ?? Date(), unit: .day),
                        y: .value("Messages", day.messageCount)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(2)
                }

                if let selectedDay, let match = matchingDailyActivity(for: selectedDay) {
                    RuleMark(x: .value("Selected", parseDate(match.date) ?? selectedDay, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartTooltip(title: formatShortDate(match.date), value: "\(match.messageCount) msgs")
                        }
                }
            }
            .chartXSelection(value: $selectedDay)
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

    // MARK: - Daily Model Tokens

    /// Flattened entries for the stacked bar chart.
    private struct ModelTokenEntry: Identifiable {
        let id = UUID()
        let date: Date
        let model: String
        let tokens: Int
    }

    private var dailyModelTokensChart: some View {
        let entries: [ModelTokenEntry] = {
            guard let cache = statsCache else { return [] }
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            return cache.dailyModelTokens.flatMap { day -> [ModelTokenEntry] in
                guard let date = df.date(from: day.date) else { return [] }
                return day.tokensByModel.compactMap { model, tokens in
                    guard !model.hasPrefix("<") else { return nil }
                    return ModelTokenEntry(date: date, model: shortModel(model), tokens: tokens)
                }
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Text("Daily Output Tokens by Model")
                .font(.headline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(entries) { entry in
                    BarMark(
                        x: .value("Date", entry.date, unit: .day),
                        y: .value("Tokens", entry.tokens)
                    )
                    .foregroundStyle(by: .value("Model", entry.model))
                    .cornerRadius(2)
                }

                if let info = modelTokensTooltipInfo(entries: entries) {
                    RuleMark(x: .value("Selected", info.date, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartTooltip(title: formatDate(info.date), value: "\(info.total.formattedCount) tokens")
                        }
                }
            }
            .chartXSelection(value: $selectedModelDay)
            .chartForegroundStyleScale { (model: String) -> Color in
                colorForModel(model)
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

    private func shortModel(_ model: String) -> String {
        if model.contains("opus-4-6") { return "Opus 4.6" }
        if model.contains("opus-4-5") { return "Opus 4.5" }
        if model.contains("sonnet-4-5") { return "Sonnet 4.5" }
        if model.contains("haiku-4-5") { return "Haiku 4.5" }
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
        return model
    }

    // MARK: - Active Hours

    private var activeHoursChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Hours (24h)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(recentHourly, id: \.date) { item in
                    BarMark(
                        x: .value("Time", item.date, unit: .hour),
                        y: .value("Messages", item.count)
                    )
                    .foregroundStyle(.purple.gradient)
                    .cornerRadius(2)
                }

                if let selectedHour, let match = matchingHourly(for: selectedHour) {
                    RuleMark(x: .value("Selected", match.date, unit: .hour))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
                            chartTooltip(title: formatHour(match.date), value: "\(match.count) msgs")
                        }
                }
            }
            .chartXSelection(value: $selectedHour)
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

    private var totalEstimatedCost: Double {
        stats.modelBreakdown.reduce(0) { $0 + $1.estimatedCost }
    }

    private var modelUsageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model Usage")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Est. \(totalEstimatedCost, format: .currency(code: "USD"))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.orange)
            }

            // Table header
            HStack(spacing: 0) {
                Text("Model")
                    .frame(width: 80, alignment: .leading)
                Text("Input")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Output")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Cache Read")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Cache Write")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Cost")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            // Model rows
            ForEach(stats.modelBreakdown) { model in
                HStack(spacing: 0) {
                    Text(model.displayName)
                        .fontWeight(.medium)
                        .foregroundStyle(colorForModel(model.displayName))
                        .frame(width: 80, alignment: .leading)
                    Text(model.inputTokens.formattedCount)
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.outputTokens.formattedCount)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.cacheReadTokens.formattedCount)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.cacheCreationTokens.formattedCount)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text(model.estimatedCost, format: .currency(code: "USD"))
                        .foregroundStyle(.orange)
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.caption)
            }
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

    private func chartTooltip(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatShortDate(_ dateStr: String) -> String {
        guard let date = parseDate(dateStr) else { return dateStr }
        let df = DateFormatter()
        df.dateFormat = "M/d"
        return df.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "M/d"
        return df.string(from: date)
    }

    private func formatHour(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    private func matchingDailyActivity(for date: Date) -> DailyActivity? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        let key = df.string(from: date)
        return stats.dailyActivity.first { $0.date == key }
    }

    private func modelTokensTooltipInfo(entries: [ModelTokenEntry]) -> (date: Date, total: Int)? {
        guard let selected = selectedModelDay else { return nil }
        let cal = Calendar.current
        let total = entries.filter { cal.isDate($0.date, inSameDayAs: selected) }.reduce(0) { $0 + $1.tokens }
        guard total > 0 else { return nil }
        return (date: cal.startOfDay(for: selected), total: total)
    }

    private func matchingHourly(for date: Date) -> (date: Date, count: Int)? {
        guard let hour = Calendar.current.dateInterval(of: .hour, for: date)?.start else { return nil }
        return recentHourly.first { $0.date == hour }
    }

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
