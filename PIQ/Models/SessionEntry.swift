import Foundation

/// Lightweight model for session list display.
struct SessionEntry: Identifiable, Equatable, Sendable, Codable {
    let id: String              // sessionId
    let projectPath: String     // from cwd field
    let projectName: String     // last component of path
    let firstPrompt: String     // first user text (truncated)
    let userTurnCount: Int      // real user turns (text input, not tool_result-only)
    let messageCount: Int       // user + assistant lines
    let model: String           // e.g. "claude-opus-4-6"
    let gitBranch: String
    let slug: String            // human-readable slug
    let createdAt: Date
    let lastActivityAt: Date
    let jsonlURL: URL
    let hasSubagents: Bool
    let inputTokens: Int        // sum of input_tokens from all assistant messages
    let outputTokens: Int       // sum of output_tokens from all assistant messages
}

// MARK: - Shared Formatting

extension Int {
    /// Format large numbers with K/M/B suffixes.
    var formattedCount: String {
        if self >= 1_000_000_000 {
            return String(format: "%.1fB", Double(self) / 1_000_000_000)
        } else if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return "\(self)"
    }
}

extension String {
    /// Convert model ID to short display name.
    var shortModelName: String {
        if contains("opus") { return "Opus" }
        if contains("sonnet") { return "Sonnet" }
        if contains("haiku") { return "Haiku" }
        return self
    }
}
