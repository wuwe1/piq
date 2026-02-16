import Foundation

// MARK: - SessionScanner

/// Discovers Claude Code session JSONL files under ~/.claude/projects/.
enum SessionScanner {
    private static let claudeProjectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects", directoryHint: .isDirectory)
    }()

    /// List all project directories under ~/.claude/projects/.
    static func discoverProjects() -> [URL] {
        let fm = FileManager.default
        let path = claudeProjectsDir.path(percentEncoded: false)
        guard fm.fileExists(atPath: path) else { return [] }

        guard let contents = try? fm.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

}
