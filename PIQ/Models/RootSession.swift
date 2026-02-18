import Foundation

/// A logical session that groups all Claude Code conversations under the same project directory.
/// Entries are sorted by createdAt; the most recently active entry drives display properties.
struct RootSession: Identifiable, Equatable {
    let id: String                    // project path (or sessionId for unknown projects)
    let entries: [SessionEntry]       // all sessions in this project, sorted by createdAt

    /// Custom Equatable: compare identity + entry count + latest activity timestamp.
    /// Avoids deep O(n) comparison of all entry fields on every SwiftUI diff.
    static func == (lhs: RootSession, rhs: RootSession) -> Bool {
        lhs.id == rhs.id
            && lhs.entries.count == rhs.entries.count
            && lhs.lastActivityAt == rhs.lastActivityAt
    }

    /// The entry with the most recent activity.
    private var latestEntry: SessionEntry { entries.max(by: { $0.lastActivityAt < $1.lastActivityAt }) ?? entries[0] }

    // Aggregated properties from all entries
    var projectPath: String { entries[0].projectPath }
    var projectName: String { entries[0].projectName }
    var firstPrompt: String { entries[0].firstPrompt }
    var lastPrompt: String { latestEntry.lastPrompt }
    var lastOutput: String { latestEntry.lastOutput }
    var model: String { latestEntry.model }
    var gitBranch: String { latestEntry.gitBranch.isEmpty ? (entries.last(where: { !$0.gitBranch.isEmpty })?.gitBranch ?? "") : latestEntry.gitBranch }
    var slug: String { latestEntry.slug }
    var createdAt: Date { entries[0].createdAt }
    var lastActivityAt: Date { latestEntry.lastActivityAt }
    var messageCount: Int { entries.reduce(0) { $0 + $1.messageCount } }
    var userTurnCount: Int { entries.reduce(0) { $0 + $1.userTurnCount } }
    var inputTokens: Int { entries.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { entries.reduce(0) { $0 + $1.outputTokens } }
    var cacheReadTokens: Int { entries.reduce(0) { $0 + $1.cacheReadTokens } }
    var readableMessageCount: Int { entries.reduce(0) { $0 + $1.readableMessageCount } }
    var hasSubagents: Bool { entries.contains { $0.hasSubagents } }
    var sessionCount: Int { Set(entries.map(\.sessionId)).count }
}
