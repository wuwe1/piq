import Foundation

enum ProjectStore {

    // MARK: - Config Persistence

    /// Load project configuration from a JSON file. Returns default config if file is missing or invalid.
    static func loadConfig(from url: URL) -> ProjectConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(ProjectConfig.self, from: data) else {
            return ProjectConfig()
        }
        return config
    }

    /// Save project configuration to a JSON file. Returns true on success.
    @discardableResult
    static func saveConfig(_ config: ProjectConfig, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return false }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Full Scan

    /// Load config, discover projects from scan roots, merge with manual projects,
    /// scan each project, save updated config, and return all projects.
    static func scanAll(configURL: URL) -> [Project] {
        var config = loadConfig(from: configURL)

        // Discover projects from scan roots
        var discovered: [ProjectEntry] = []
        for root in config.scanRoots {
            let projectURLs = ProjectScanner.discoverProjects(under: root)
            for url in projectURLs {
                let entry = ProjectEntry(rootPath: url, isManual: false)
                discovered.append(entry)
            }
        }

        // Preserve isHidden flags from previous discoveries
        let previousHidden = Set(
            config.discoveredProjects.filter(\.isHidden).map { canonicalPath($0.rootPath) }
        )
        discovered = discovered.map { entry in
            var e = entry
            if previousHidden.contains(canonicalPath(e.rootPath)) {
                e.isHidden = true
            }
            return e
        }
        config.discoveredProjects = discovered

        // Merge: manual projects + non-hidden discovered projects
        let manualPaths = Set(config.manualProjects.map { canonicalPath($0.rootPath) })
        let allEntries = config.manualProjects + discovered.filter { entry in
            !entry.isHidden && !manualPaths.contains(canonicalPath(entry.rootPath))
        }

        // Scan each project
        let projects = allEntries.map { entry in
            ProjectScanner.scanProject(at: entry.rootPath)
        }

        saveConfig(config, to: configURL)

        return projects
    }

    // MARK: - Manual Project Management

    /// Add a manual project entry. Returns false if already present.
    @discardableResult
    static func addManualProject(path: URL, to config: inout ProjectConfig) -> Bool {
        let allPaths = config.manualProjects.map { canonicalPath($0.rootPath) }
            + config.discoveredProjects.map { canonicalPath($0.rootPath) }
        guard !allPaths.contains(canonicalPath(path)) else { return false }
        config.manualProjects.append(ProjectEntry(rootPath: path, isManual: true))
        return true
    }

    // MARK: - Scan Root Management

    /// Add a scan root directory.
    static func addScanRoot(_ root: URL, to config: inout ProjectConfig) {
        guard !config.scanRoots.contains(root) else { return }
        config.scanRoots.append(root)
    }

    /// Remove a scan root directory.
    static func removeScanRoot(_ root: URL, from config: inout ProjectConfig) {
        config.scanRoots.removeAll { $0 == root }
    }

    // MARK: - Private

    /// Normalize a URL path to a canonical form for comparison.
    /// Resolves macOS symlinks (e.g. /private/var ↔ /var) and removes trailing slashes.
    private static func canonicalPath(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).standardizingPath
    }
}
