import Foundation

/// Lightweight model for session list display.
/// Only requires head/tail of JSONL file to construct.
struct SessionEntry: Identifiable, Sendable {
    let id: String              // sessionId
    let projectPath: String     // from cwd field
    let projectName: String     // last component of path
    let firstPrompt: String     // first user text (truncated)
    let messageCount: Int       // user + assistant lines
    let model: String           // e.g. "claude-opus-4-6"
    let gitBranch: String
    let slug: String            // human-readable slug
    let createdAt: Date
    let lastActivityAt: Date
    let jsonlURL: URL
    let hasSubagents: Bool
}
