import Foundation

// MARK: - SessionTurn

/// A logical turn: one user message + the assistant response chain
/// (including tool calls/results) + system events.
struct SessionTurn: Identifiable, Sendable {
    let id: String
    let userMessage: SessionMessage?
    let assistantMessages: [SessionMessage]
    var toolPairs: [ToolCallPair]
    let durationMs: Double?
    let totalUsage: TokenUsage?
}

// MARK: - ToolCallPair

/// A matched pair of tool_use (from assistant) and tool_result (from user).
struct ToolCallPair: Identifiable, Sendable {
    let id: String          // tool_use_id
    let name: String        // tool name (e.g. "Bash", "Read", "Edit")
    let serverName: String? // MCP server name if applicable
    let inputJSON: String   // pretty-printed JSON of tool input
    let output: String?     // tool result content
    let isError: Bool
    var agentTurns: [SessionTurn]? // Agent conversation for Task tool calls
}
