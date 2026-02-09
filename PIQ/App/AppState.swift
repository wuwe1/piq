import Foundation

@MainActor
@Observable
final class AppState {
    private let configDirectory: URL
    var projects: [Project] = []
    var projectConfig: ProjectConfig = ProjectConfig()
    var settings: Settings = Settings()
    var selectedProjectID: UUID?
    var expandedProjectPaths: Set<String> = []
    var toastMessage: String?
    var activityStore: ActivityStore?
    private var fileWatcher: FileWatcher?

    /// Snapshot of epic progress percentages from the previous scan, keyed by file path.
    private var epicProgressSnapshot: [String: Int] = [:]

    /// Snapshot of known PRD names from the previous scan.
    private var knownPRDNames: Set<String> = []

    /// Snapshot of known epic file paths for inconsistency tracking.
    private var knownInconsistentEpics: Set<String> = []

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    private var configFileURL: URL {
        configDirectory.appending(path: "projects.json")
    }

    private var activityFileURL: URL {
        configDirectory.appending(path: "activity.json")
    }

    var settingsFileURL: URL {
        configDirectory.appending(path: "settings.json")
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = home.appending(path: ".piq", directoryHint: .isDirectory)
        createConfigDirectoryIfNeeded()
    }

    func loadProjects() {
        projectConfig = ProjectStore.loadConfig(from: configFileURL)
    }

    func loadSettings() {
        settings = SettingsStore.load(from: settingsFileURL)
    }

    func saveSettings() {
        SettingsStore.save(settings, to: settingsFileURL)
    }

    func saveProjectConfig() {
        ProjectStore.saveConfig(projectConfig, to: configFileURL)
    }

    func rescanAll() {
        let oldProjects = projects
        projects = ProjectStore.scanAll(configURL: configFileURL)
        projectConfig = ProjectStore.loadConfig(from: configFileURL)
        reorderProjects()
        updateWatchedPaths()
        activityStore?.processChanges(projects: projects)
        checkNotifications(oldProjects: oldProjects)
    }

    /// Move a project by array index and persist the order.
    func moveProjectByIndex(from source: Int, to destination: Int) {
        guard source >= 0, source < projects.count,
              destination >= 0, destination < projects.count,
              source != destination else { return }
        let project = projects.remove(at: source)
        projects.insert(project, at: destination)
        projectConfig.projectOrder = projects.map { $0.rootPath.path(percentEncoded: false) }
        saveProjectConfig()
    }

    /// Reorder projects to match the persisted `projectOrder`.
    /// Projects not in the order are appended at the end.
    /// Stale entries (paths no longer present) are removed from the order.
    private func reorderProjects() {
        let order = projectConfig.projectOrder
        guard !order.isEmpty else { return }

        let pathToIndex: [String: Int] = {
            var map: [String: Int] = [:]
            for (i, path) in order.enumerated() {
                map[path] = i
            }
            return map
        }()

        let ordered = projects.filter { pathToIndex[$0.rootPath.path(percentEncoded: false)] != nil }
            .sorted { a, b in
                let ai = pathToIndex[a.rootPath.path(percentEncoded: false)] ?? Int.max
                let bi = pathToIndex[b.rootPath.path(percentEncoded: false)] ?? Int.max
                return ai < bi
            }
        let unordered = projects.filter { pathToIndex[$0.rootPath.path(percentEncoded: false)] == nil }

        projects = ordered + unordered

        // Clean up stale entries from projectOrder
        let currentPaths = Set(projects.map { $0.rootPath.path(percentEncoded: false) })
        let cleanedOrder = projectConfig.projectOrder.filter { currentPaths.contains($0) }
        if cleanedOrder.count != projectConfig.projectOrder.count {
            projectConfig.projectOrder = cleanedOrder
            saveProjectConfig()
        }
    }

    func setupActivityStore() {
        let store = ActivityStore(storageURL: activityFileURL)
        store.loadHistory()
        activityStore = store
    }

    func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            toastMessage = nil
        }
    }

    func addScanRoot(_ root: URL) {
        ProjectStore.addScanRoot(root, to: &projectConfig)
        ProjectStore.saveConfig(projectConfig, to: configFileURL)
    }

    func addManualProject(_ path: URL) {
        ProjectStore.addManualProject(path: path, to: &projectConfig)
        ProjectStore.saveConfig(projectConfig, to: configFileURL)
    }

    // MARK: - File Watching

    /// Create a FileWatcher, collect project paths, and start monitoring for changes.
    func startWatching() {
        let watcher = FileWatcher { [weak self] in
            self?.rescanAll()
        }
        fileWatcher = watcher

        let paths = projects.map(\.rootPath)
        watcher.startWatching(paths: paths)
    }

    /// Stop the FileWatcher and release resources.
    func stopWatching() {
        fileWatcher?.stopWatching()
        fileWatcher = nil
    }

    // MARK: - Private

    /// Update the FileWatcher's monitored paths based on the current project list.
    private func updateWatchedPaths() {
        let paths = projects.map(\.rootPath)
        fileWatcher?.updatePaths(paths)
    }

    private func createConfigDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path(percentEncoded: false)) {
            try? fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Notification Checks

    /// Compare current scan results against previous snapshots and send notifications.
    private func checkNotifications(oldProjects: [Project]) {
        let currentSettings = settings

        // Gather all epics and PRDs from the new scan
        let allEpics = projects.flatMap(\.epics)
        let allPRDs = projects.flatMap(\.prds)

        // Check epic milestones
        for epic in allEpics {
            let key = epic.filePath.path(percentEncoded: false)
            let oldProgress = epicProgressSnapshot[key] ?? 0
            NotificationService.checkMilestone(epic: epic, oldProgress: oldProgress, settings: currentSettings)
        }

        // Check for new PRDs
        let currentPRDNames = Set(allPRDs.map(\.name))
        let newPRDNames = currentPRDNames.subtracting(knownPRDNames)
        if !knownPRDNames.isEmpty {
            for name in newPRDNames {
                NotificationService.notifyNewPRD(name: name, settings: currentSettings)
            }
        }

        // Check for inconsistencies
        for epic in allEpics {
            let key = epic.filePath.path(percentEncoded: false)
            if !epic.isConsistent && !knownInconsistentEpics.contains(key) {
                NotificationService.notifyInconsistency(epic: epic, settings: currentSettings)
            }
        }

        // Update snapshots
        epicProgressSnapshot = [:]
        for epic in allEpics {
            let key = epic.filePath.path(percentEncoded: false)
            epicProgressSnapshot[key] = epic.progressPercent
        }
        knownPRDNames = currentPRDNames
        knownInconsistentEpics = Set(allEpics.filter { !$0.isConsistent }.map { $0.filePath.path(percentEncoded: false) })
    }
}
