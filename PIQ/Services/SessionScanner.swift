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

    /// Deduplicate sessions by resolving continuation chains.
    ///
    /// Claude Code creates continuation files when resuming a session:
    /// the new file's sessionId references the previous file's UUID, forming a chain.
    /// We resolve the full chain and keep one entry per logical session.
    static func deduplicateSessions(_ allSessions: [SessionEntry]) -> [SessionEntry] {
        // Map each file's UUID (from filename) to the sessionId found in its content.
        var fileToSessionId: [String: String] = [:]
        for entry in allSessions {
            let fileUUID = entry.jsonlURL.deletingPathExtension().lastPathComponent
            fileToSessionId[fileUUID] = entry.id
        }

        // Follow the chain to find the root sessionId.
        func rootId(of sessionId: String, visited: Set<String> = []) -> String {
            guard !visited.contains(sessionId) else { return sessionId }
            if let parentId = fileToSessionId[sessionId], parentId != sessionId {
                return rootId(of: parentId, visited: visited.union([sessionId]))
            }
            return sessionId
        }

        // Group all entries by their root sessionId.
        var groups: [String: [SessionEntry]] = [:]
        for entry in allSessions {
            let root = rootId(of: entry.id)
            groups[root, default: []].append(entry)
        }

        // Pick the best representative per group:
        // - Prefer entries with a meaningful prompt (not "[Request interrupted...")
        // - Use the latest activity time from the group
        return groups.values.compactMap { group -> SessionEntry? in
            let sorted = group.sorted { $0.lastActivityAt > $1.lastActivityAt }
            guard let latest = sorted.first else { return nil }
            let best = sorted.first {
                !$0.firstPrompt.hasPrefix("[Request interrupted")
            } ?? latest

            if best.id != latest.id, latest.lastActivityAt > best.lastActivityAt {
                return SessionEntry(
                    id: best.id,
                    projectPath: best.projectPath,
                    projectName: best.projectName,
                    firstPrompt: best.firstPrompt,
                    lastPrompt: latest.lastPrompt.isEmpty ? best.lastPrompt : latest.lastPrompt,
                    lastOutput: latest.lastOutput.isEmpty ? best.lastOutput : latest.lastOutput,
                    userTurnCount: group.reduce(0) { $0 + $1.userTurnCount },
                    messageCount: group.reduce(0) { $0 + $1.messageCount },
                    model: latest.model.isEmpty ? best.model : latest.model,
                    gitBranch: latest.gitBranch.isEmpty ? best.gitBranch : latest.gitBranch,
                    slug: best.slug,
                    createdAt: best.createdAt,
                    lastActivityAt: latest.lastActivityAt,
                    jsonlURL: latest.jsonlURL,
                    hasSubagents: group.contains { $0.hasSubagents },
                    inputTokens: group.reduce(0) { $0 + $1.inputTokens },
                    outputTokens: group.reduce(0) { $0 + $1.outputTokens },
                    cacheReadTokens: group.reduce(0) { $0 + $1.cacheReadTokens },
                    cacheCreationTokens: group.reduce(0) { $0 + $1.cacheCreationTokens }
                )
            }
            return best
        }.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }}
