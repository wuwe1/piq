#if DEBUG

import AppKit
import Charts
import SwiftUI

// MARK: - Screenshot Generator

/// Renders SwiftUI views to PNG files using `ImageRenderer`.
///
/// Usage from tests:
/// ```swift
/// let dir = FileManager.default.temporaryDirectory.appending(path: "screenshots")
/// let urls = ScreenshotGenerator.generateAll(to: dir)
/// ```
@MainActor
enum ScreenshotGenerator {

    /// Render a single SwiftUI view to a PNG file.
    @discardableResult
    static func render<V: View>(
        _ view: V,
        size: CGSize,
        scale: CGFloat = 2.0,
        to fileURL: URL
    ) -> Bool {
        let hosted = view.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: hosted)
        renderer.scale = scale

        guard let nsImage = renderer.nsImage,
              let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:])
        else {
            return false
        }

        do {
            try pngData.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Generate all product page screenshots into `directory`.
    /// Returns the file URLs of successfully written PNGs.
    static func generateAll(to directory: URL, scale: CGFloat = 2.0) -> [URL] {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let collapsedState = ScreenshotMockData.createAppState()
        let expandedState = ScreenshotMockData.createExpandedAppState()

        let scenes: [(view: AnyView, size: CGSize, name: String)] = [
            (
                AnyView(MenuBarShowcase(appState: collapsedState)),
                CGSize(width: 440, height: 580),
                "screenshot-menubar.png"
            ),
            (
                AnyView(MenuBarShowcase(appState: expandedState)),
                CGSize(width: 440, height: 820),
                "screenshot-detail.png"
            ),
            (
                AnyView(StatsShowcase(appState: collapsedState)),
                CGSize(width: 440, height: 780),
                "screenshot-stats.png"
            ),
        ]

        var results: [URL] = []
        for scene in scenes {
            let url = directory.appending(path: scene.name)
            if render(scene.view, size: scene.size, scale: scale, to: url) {
                results.append(url)
            }
        }
        return results
    }
}

// MARK: - Showcase Views

// NOTE: ImageRenderer cannot render ScrollView content, so all showcase
// views inline their content inside plain VStacks instead of delegating
// to the production views (MenuBarView / StatsView) which use ScrollView.

/// Menu bar panel rendered with a drop shadow for product page use.
@MainActor
struct MenuBarShowcase: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            showcaseHeader(icon: "chart.bar")
            Divider()

            // Inline project list (no ScrollView)
            VStack(spacing: 6) {
                ForEach(
                    Array(appState.projects.enumerated()),
                    id: \.element.id
                ) { index, project in
                    ProjectCardView(
                        project: project,
                        index: index,
                        total: appState.projects.count
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
            showcaseFooter
        }
        .environment(appState)
        .frame(width: 360)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        .padding(40)
    }
}

/// Stats dashboard rendered with the same chrome as the menu bar panel.
@MainActor
struct StatsShowcase: View {
    let appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            showcaseHeader(icon: "list.bullet")
            Divider()

            // Inline stats content (no ScrollView)
            ShowcaseStatsContent()

            Divider()
            showcaseFooter
        }
        .environment(appState)
        .frame(width: 360)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        .padding(40)
    }
}

/// Reusable header matching MenuBarView's chrome.
private func showcaseHeader(icon: String) -> some View {
    HStack {
        Image(systemName: "eyes")
            .foregroundStyle(.secondary)
        Text("PIQ")
            .font(.headline)
        Spacer()
        Text("3 projects")
            .font(.caption)
            .foregroundStyle(.tertiary)
        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}

/// Reusable footer matching MenuBarView's chrome.
private var showcaseFooter: some View {
    HStack {
        Label("Refresh", systemImage: "arrow.clockwise")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Spacer()
        Image(systemName: "gear")
            .font(.footnote)
            .foregroundStyle(.secondary)
        Text("Quit")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}

/// Inlines StatsView content without ScrollView for ImageRenderer.
private struct ShowcaseStatsContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            summarySection
            trendSection
            activitySection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Summary", systemImage: "chart.pie")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            globalTaskStats

            ForEach(appState.projects) { project in
                projectProgressRow(project)
            }

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
        let percent = taskCount > 0
            ? Int((Double(doneCount) / Double(taskCount) * 100).rounded()) : 0

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
                epicBadge(label: "Backlog", count: counts.backlog, color: .gray)
                epicBadge(label: "In Progress", count: counts.inProgress, color: .blue)
                epicBadge(label: "Done", count: counts.done, color: .green)
            }
        }
    }

    private func epicBadge(label: String, count: Int, color: Color) -> some View {
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

    // MARK: - Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("7-Day Trend", systemImage: "chart.bar")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let store = appState.activityStore {
                let data = store.tasksCompletedPerDay(lastDays: 7)
                if data.contains(where: { $0.count > 0 }) {
                    Charts.Chart {
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
                            AxisValueLabel(
                                format: .dateTime.weekday(.abbreviated),
                                centered: true
                            )
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine()
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 120)
                } else {
                    trendEmpty
                }
            } else {
                trendEmpty
            }
        }
    }

    private var trendEmpty: some View {
        Text("No task completions yet")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recent Activity", systemImage: "clock")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let store = appState.activityStore {
                let recent = store.recentEvents(limit: 5)
                if recent.isEmpty {
                    activityEmpty
                } else {
                    ForEach(recent) { event in
                        ActivityRowView(event: event)
                    }
                }
            } else {
                activityEmpty
            }
        }
    }

    private var activityEmpty: some View {
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

    // MARK: - Computed

    private var allEpics: [EpicItem] {
        appState.projects.flatMap(\.epics)
    }

    private var totalTaskCount: Int {
        appState.projects.reduce(0) { sum, p in
            sum + p.epics.reduce(0) { $0 + $1.tasks.count }
        }
    }

    private var doneTaskCount: Int {
        appState.projects.reduce(0) { sum, p in
            sum + p.epics.reduce(0) { s, e in
                s + e.tasks.filter { $0.status == .done }.count
            }
        }
    }

    private var epicStatusCounts: (backlog: Int, inProgress: Int, done: Int) {
        var backlog = 0, inProgress = 0, done = 0
        for epic in allEpics {
            switch epic.status {
            case .backlog, .open: backlog += 1
            case .inProgress: inProgress += 1
            case .done: done += 1
            }
        }
        return (backlog, inProgress, done)
    }
}

// MARK: - Mock Data

/// Creates realistic sample data for screenshot generation.
@MainActor
enum ScreenshotMockData {

    /// App state with all projects collapsed.
    static func createAppState() -> AppState {
        let state = AppState()
        state.projects = createMockProjects()
        setupMockActivity(for: state)
        return state
    }

    /// App state with the first project expanded to show detail.
    static func createExpandedAppState() -> AppState {
        let state = AppState()
        state.projects = createMockProjects()
        state.expandedProjectPaths.insert(
            state.projects[0].rootPath.path(percentEncoded: false)
        )
        setupMockActivity(for: state)
        return state
    }

    // MARK: Activity

    private static func setupMockActivity(for state: AppState) {
        let tmpDir = FileManager.default.temporaryDirectory
            .appending(path: "piq-screenshots")
        try? FileManager.default.createDirectory(
            at: tmpDir, withIntermediateDirectories: true
        )
        let activityFile = tmpDir.appending(path: "activity.json")

        let events = createMockEvents()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(events) {
            try? data.write(to: activityFile, options: .atomic)
        }

        let store = ActivityStore(storageURL: activityFile)
        store.loadHistory()
        state.activityStore = store
    }

    private static func createMockEvents() -> [ActivityEvent] {
        let calendar = Calendar.current
        let now = Date()
        let base = URL(filePath: "/tmp/piq-mock")
        let dailyCounts = [3, 1, 2, 0, 4, 2, 1]
        let projectNames = ["piq", "claude-code", "web-dashboard"]
        var events: [ActivityEvent] = []

        for dayOffset in 0..<7 {
            guard let day = calendar.date(
                byAdding: .day, value: -dayOffset, to: now
            ) else { continue }

            for i in 0..<dailyCounts[dayOffset] {
                events.append(ActivityEvent(
                    timestamp: day.addingTimeInterval(Double(i) * 3600),
                    itemType: .task,
                    itemName: "Task \(dayOffset)-\(i)",
                    oldStatus: .inProgress,
                    newStatus: .done,
                    filePath: base.appending(path: "mock-\(dayOffset)-\(i).md"),
                    projectName: projectNames[dayOffset % 3]
                ))
            }
        }

        events.append(ActivityEvent(
            timestamp: now.addingTimeInterval(-1800),
            itemType: .epic,
            itemName: "Core Dashboard",
            oldStatus: .backlog,
            newStatus: .inProgress,
            filePath: base.appending(path: "piq/epic-1.md"),
            projectName: "piq"
        ))

        events.append(ActivityEvent(
            timestamp: now.addingTimeInterval(-7200),
            itemType: .task,
            itemName: "pm:epic-sync command",
            oldStatus: .open,
            newStatus: .inProgress,
            filePath: base.appending(path: "claude-code/task-2.md"),
            projectName: "claude-code"
        ))

        return events
    }

    // MARK: Projects

    private static func createMockProjects() -> [Project] {
        let base = URL(filePath: "/tmp/piq-mock")

        return [
            Project(
                name: "piq",
                rootPath: base.appending(path: "piq"),
                prds: [
                    PRDItem(
                        name: "Menubar Dashboard", status: .inProgress,
                        filePath: base.appending(path: "piq/prd-1.md")
                    ),
                    PRDItem(
                        name: "Notification System", status: .done,
                        filePath: base.appending(path: "piq/prd-2.md")
                    ),
                ],
                epics: [
                    EpicItem(
                        name: "Core Dashboard",
                        status: .inProgress,
                        filePath: base.appending(path: "piq/epic-1.md"),
                        progress: 75,
                        github: URL(string: "https://github.com/piq/piq/issues/1"),
                        tasks: [
                            TaskItem(
                                taskID: "TASK-001", name: "Project card layout",
                                status: .done,
                                filePath: base.appending(path: "piq/task-1.md")
                            ),
                            TaskItem(
                                taskID: "TASK-002", name: "Progress bar component",
                                status: .done,
                                filePath: base.appending(path: "piq/task-2.md")
                            ),
                            TaskItem(
                                taskID: "TASK-003", name: "Drag to reorder",
                                status: .done,
                                filePath: base.appending(path: "piq/task-3.md")
                            ),
                            TaskItem(
                                taskID: "TASK-004", name: "Detail view expansion",
                                status: .inProgress,
                                filePath: base.appending(path: "piq/task-4.md")
                            ),
                        ]
                    ),
                    EpicItem(
                        name: "File Watching",
                        status: .done,
                        filePath: base.appending(path: "piq/epic-2.md"),
                        progress: 100,
                        tasks: [
                            TaskItem(
                                taskID: "TASK-005", name: "FSEvents integration",
                                status: .done,
                                filePath: base.appending(path: "piq/task-5.md")
                            ),
                            TaskItem(
                                taskID: "TASK-006", name: "Debounced refresh",
                                status: .done,
                                filePath: base.appending(path: "piq/task-6.md")
                            ),
                        ]
                    ),
                    EpicItem(
                        name: "Activity Tracking",
                        status: .backlog,
                        filePath: base.appending(path: "piq/epic-3.md"),
                        progress: 0,
                        tasks: [
                            TaskItem(
                                taskID: "TASK-007", name: "Event persistence",
                                status: .open,
                                filePath: base.appending(path: "piq/task-7.md")
                            ),
                            TaskItem(
                                taskID: "TASK-008", name: "7-day trend chart",
                                status: .open,
                                filePath: base.appending(path: "piq/task-8.md")
                            ),
                        ]
                    ),
                ]
            ),
            Project(
                name: "claude-code",
                rootPath: base.appending(path: "claude-code"),
                prds: [
                    PRDItem(
                        name: "PM Workflow", status: .inProgress,
                        filePath: base.appending(path: "claude-code/prd-1.md")
                    ),
                ],
                epics: [
                    EpicItem(
                        name: "Slash Commands",
                        status: .inProgress,
                        filePath: base.appending(path: "claude-code/epic-1.md"),
                        progress: 50,
                        github: URL(string: "https://github.com/anthropics/claude-code/issues/42"),
                        tasks: [
                            TaskItem(
                                taskID: "CC-001", name: "pm:plan command",
                                status: .done,
                                filePath: base.appending(path: "claude-code/task-1.md")
                            ),
                            TaskItem(
                                taskID: "CC-002", name: "pm:epic-sync command",
                                status: .inProgress,
                                filePath: base.appending(path: "claude-code/task-2.md")
                            ),
                        ]
                    ),
                ]
            ),
            Project(
                name: "web-dashboard",
                rootPath: base.appending(path: "web-dashboard"),
                prds: [
                    PRDItem(
                        name: "Analytics Dashboard", status: .backlog,
                        filePath: base.appending(path: "web-dashboard/prd-1.md")
                    ),
                ],
                epics: [
                    EpicItem(
                        name: "Chart Components",
                        status: .backlog,
                        filePath: base.appending(path: "web-dashboard/epic-1.md"),
                        progress: 0,
                        tasks: [
                            TaskItem(
                                taskID: "WD-001", name: "Line chart",
                                status: .open,
                                filePath: base.appending(path: "web-dashboard/task-1.md")
                            ),
                            TaskItem(
                                taskID: "WD-002", name: "Bar chart",
                                status: .open,
                                filePath: base.appending(path: "web-dashboard/task-2.md")
                            ),
                        ]
                    ),
                ]
            ),
        ]
    }
}

#endif
