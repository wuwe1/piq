import Foundation

/// Persists per-session "last read" counts to track unread messages.
/// Stored at `~/.claude/piq-read-state.json`.
struct ReadState: Codable, Sendable {
    var lastReadCounts: [String: Int] = [:]  // sessionId → last-seen readableMessageCount

    private static let fileURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/piq-read-state.json")
    }()

    static func load() -> ReadState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(ReadState.self, from: data) else {
            return ReadState()
        }
        return state
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    mutating func markRead(sessionId: String, readableMessageCount: Int) {
        lastReadCounts[sessionId] = readableMessageCount
    }

    func unreadCount(sessionId: String, readableMessageCount: Int) -> Int {
        let lastRead = lastReadCounts[sessionId] ?? 0
        return max(0, readableMessageCount - lastRead)
    }

    mutating func removeStaleEntries(keeping validIds: Set<String>) {
        lastReadCounts = lastReadCounts.filter { validIds.contains($0.key) }
    }
}
