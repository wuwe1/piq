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

    /// Scan a single project directory for .jsonl session files.
    static func scanSessions(in projectDir: URL) -> [SessionEntry] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }

        return jsonlFiles.compactMap { url in
            SessionParser.extractMetadata(from: url)
        }
    }

    /// Scan all projects and return sessions sorted by last activity (newest first).
    /// Deduplicates by sessionId, keeping the entry with the latest activity.
    static func scanAll() -> [SessionEntry] {
        let projects = discoverProjects()
        let allSessions = projects.flatMap { scanSessions(in: $0) }

        // Deduplicate by sessionId — keep the most recently active entry
        var seen: [String: SessionEntry] = [:]
        for session in allSessions {
            if let existing = seen[session.id] {
                if session.lastActivityAt > existing.lastActivityAt {
                    seen[session.id] = session
                }
            } else {
                seen[session.id] = session
            }
        }

        return seen.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    /// Get modification date for a JSONL file.
    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
