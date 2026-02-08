import Foundation

@MainActor
@Observable
final class AppState {
    private let configDirectory: URL
    var projects: [Project] = []
    var projectConfig: ProjectConfig = ProjectConfig()

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
    }

    func addScanRoot(_ root: URL) {
        ProjectStore.addScanRoot(root, to: &projectConfig)
        ProjectStore.saveConfig(projectConfig, to: configFileURL)
    }

    func addManualProject(_ path: URL) {
        ProjectStore.addManualProject(path: path, to: &projectConfig)
        ProjectStore.saveConfig(projectConfig, to: configFileURL)
    }

    private func createConfigDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDirectory.path(percentEncoded: false)) {
            try? fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }
    }
}
