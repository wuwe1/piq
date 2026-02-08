import Foundation

@MainActor
@Observable
final class AppState {
    private let configDirectory: URL
    var projects: [Project] = []
    var projectConfig: ProjectConfig = ProjectConfig()
    private var fileWatcher: FileWatcher?

    private var configFileURL: URL {
        configDirectory.appending(path: "projects.json")
    }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = home.appending(path: ".piq", directoryHint: .isDirectory)
        createConfigDirectoryIfNeeded()
    }

    func loadProjects() {
        projectConfig = ProjectStore.loadConfig(from: configFileURL)
    }

    func rescanAll() {
        projects = ProjectStore.scanAll(configURL: configFileURL)
        projectConfig = ProjectStore.loadConfig(from: configFileURL)
        updateWatchedPaths()
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
}
