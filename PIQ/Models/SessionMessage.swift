import Foundation

// MARK: - SessionMessage

/// A single parsed line from a Claude Code JSONL session file.
struct SessionMessage: Identifiable, Sendable {
    let id: String                          // uuid
    let parentId: String?                   // parentUuid
    let type: SessionMessageType
    let timestamp: Date
    let sessionId: String
    let cwd: String?
    let gitBranch: String?
    let slug: String?
    let version: String?
    let model: String?
    let contentBlocks: [SessionContentBlock]
    let usage: TokenUsage?
    let isSidechain: Bool
    let systemSubtype: String?
    let durationMs: Double?
    let toolUseResult: ToolUseResultInfo?
}

// MARK: - SessionMessageType

enum SessionMessageType: String, Sendable {
    case user
    case assistant
    case system
    case progress
    case fileHistorySnapshot = "file-history-snapshot"
    case hookProgress = "hook_progress"
}

// MARK: - SessionContentBlock

enum SessionContentBlock: Identifiable, Sendable {
    case text(id: String, text: String)
    case thinking(id: String, text: String)
    case toolUse(id: String, toolId: String, name: String, serverName: String?, inputJSON: String)
    case toolResult(id: String, toolUseId: String, content: String, isError: Bool)

    var id: String {
        switch self {
        case .text(let id, _): id
        case .thinking(let id, _): id
        case .toolUse(let id, _, _, _, _): id
        case .toolResult(let id, _, _, _): id
        }
    }
}

// MARK: - TokenUsage

struct TokenUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int

    static let zero = TokenUsage(inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0)

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens
        )
    }
}

// MARK: - ToolUseResultInfo

/// Extra metadata attached to user messages that carry tool results.
struct ToolUseResultInfo: Sendable {
    let stdout: String?
    let stderr: String?
    let interrupted: Bool
    let isImage: Bool
    /// For file operations: create, edit, etc.
    let fileOperationType: String?
    let filePath: String?
}
