#if DEBUG

import AppKit
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
                CGSize(width: 440, height: 700),
                "screenshot-detail.png"
            ),
            (
                AnyView(StatsShowcase(appState: collapsedState)),
                CGSize(width: 440, height: 580),
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

/// Menu bar panel rendered with a drop shadow for product page use.
@MainActor
struct MenuBarShowcase: View {
    let appState: AppState

    var body: some View {
        MenuBarView()
            .environment(appState)
            .frame(width: 360, height: 500)
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
        StatsShowcaseContent()
            .environment(appState)
            .frame(width: 360, height: 500)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
            .padding(40)
    }
}

/// Reproduces the MenuBarView chrome but forces the stats panel visible.
private struct StatsShowcaseContent: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "eyes")
                    .foregroundStyle(.secondary)
                Text("PIQ")
                    .font(.headline)
                Spacer()
                Text("\(appState.projects.count) projects")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Image(systemName: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            StatsView()

            Divider()

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
