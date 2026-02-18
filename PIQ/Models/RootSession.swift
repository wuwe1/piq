import Foundation

/// A logical session that merges a root session and all its continuations.
struct RootSession: Identifiable, Equatable {
    let id: String                    // root file's UUID (== sessionId)
    let entries: [SessionEntry]       // root + continuations, sorted by createdAt

    // Aggregated properties from all entries
    var projectPath: String { entries[0].projectPath }
    var projectName: String { entries[0].projectName }
    var firstPrompt: String { entries[0].firstPrompt }
    var lastPrompt: String { entries.last!.lastPrompt }
    var lastOutput: String { entries.last!.lastOutput }
    var model: String { entries.last!.model }
    var gitBranch: String { entries.first(where: { !$0.gitBranch.isEmpty })?.gitBranch ?? "" }
    var slug: String { entries[0].slug }
    var createdAt: Date { entries[0].createdAt }
    var lastActivityAt: Date { entries.last!.lastActivityAt }
    var messageCount: Int { entries.reduce(0) { $0 + $1.messageCount } }
    var userTurnCount: Int { entries.reduce(0) { $0 + $1.userTurnCount } }
    var inputTokens: Int { entries.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { entries.reduce(0) { $0 + $1.outputTokens } }
    var cacheReadTokens: Int { entries.reduce(0) { $0 + $1.cacheReadTokens } }
    var readableMessageCount: Int { entries.reduce(0) { $0 + $1.readableMessageCount } }
    var hasSubagents: Bool { entries.contains { $0.hasSubagents } }
    var continuationCount: Int { entries.count }
}
