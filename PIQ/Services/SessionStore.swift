import Foundation

// MARK: - SessionStore

/// Central state manager for Claude Code sessions.
@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [SessionEntry] = []
    private(set) var isLoading = false
    private var fileWatcher: SessionFileWatcher?
    private var mtimeCache: [URL: Date] = [:]

    /// Currently loaded session detail (turns for the selected session).
    private(set) var loadedTurns: [SessionTurn] = []
    private(set) var loadedSessionId: String?
    private(set) var isLoadingDetail = false

    // MARK: - Scanning

    /// Full rescan of all session files.
    func rescan() {
        isLoading = true
        let scanned = SessionScanner.scanAll()
        sessions = scanned
        // Update mtime cache
        mtimeCache = [:]
        for entry in scanned {
            mtimeCache[entry.jsonlURL] = SessionScanner.modificationDate(of: entry.jsonlURL)
        }
        isLoading = false
    }

    /// Incremental update: only re-parse files whose mtime changed.
    func incrementalUpdate() {
        let projectDirs = SessionScanner.discoverProjects()
        var updated = false

        for projectDir in projectDirs {
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            let jsonlFiles = contents.filter { $0.pathExtension == "jsonl" }

            for file in jsonlFiles {
                let newMtime = SessionScanner.modificationDate(of: file)
                let oldMtime = mtimeCache[file]

                if oldMtime == nil || newMtime != oldMtime {
                    // File is new or changed
                    if let entry = SessionParser.extractMetadata(from: file) {
                        // Remove old entry with same URL
                        sessions.removeAll { $0.jsonlURL == file }
                        sessions.append(entry)
                        updated = true
                    }
                    mtimeCache[file] = newMtime
                }
            }
        }

        // Remove sessions whose files no longer exist
        let existingURLs = Set(mtimeCache.keys)
        let before = sessions.count
        sessions.removeAll { !existingURLs.contains($0.jsonlURL) }
        if sessions.count != before { updated = true }

        if updated {
            sessions.sort { $0.lastActivityAt > $1.lastActivityAt }
        }

        // If the currently loaded session was updated, refresh it
        if let loadedId = loadedSessionId,
           let entry = sessions.first(where: { $0.id == loadedId }) {
            let newMtime = SessionScanner.modificationDate(of: entry.jsonlURL)
            if newMtime != mtimeCache[entry.jsonlURL] {
                Task {
                    await loadSessionDetail(entry: entry)
                }
            }
        }
    }

    // MARK: - Detail Loading

    /// Load full session detail (turns) for display.
    func loadSessionDetail(entry: SessionEntry) async {
        loadedSessionId = entry.id
        isLoadingDetail = true
        loadedTurns = []

        let url = entry.jsonlURL
        let turns = await Task.detached(priority: .userInitiated) {
            let messages = SessionParser.parseFile(at: url)
            return SessionParser.groupIntoTurns(messages)
        }.value

        // Only update if we're still viewing this session
        if loadedSessionId == entry.id {
            loadedTurns = turns
            isLoadingDetail = false
        }
    }

    /// Clear loaded detail.
    func clearDetail() {
        loadedTurns = []
        loadedSessionId = nil
        isLoadingDetail = false
    }

    // MARK: - File Watching

    func startWatching() {
        let watcher = SessionFileWatcher { [weak self] in
            self?.incrementalUpdate()
        }
        fileWatcher = watcher
        watcher.startWatching()
    }

    func stopWatching() {
        fileWatcher?.stopWatching()
        fileWatcher = nil
    }
}
