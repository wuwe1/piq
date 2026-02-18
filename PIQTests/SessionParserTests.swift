import XCTest
@testable import PIQ

final class SessionParserTests: XCTestCase {

    // MARK: - Helpers

    /// Create a minimal SessionMessage for testing turn grouping.
    private func makeMessage(
        id: String = UUID().uuidString,
        type: SessionMessageType,
        contentBlocks: [SessionContentBlock] = [],
        usage: TokenUsage? = nil,
        systemSubtype: String? = nil,
        durationMs: Double? = nil
    ) -> SessionMessage {
        SessionMessage(
            id: id,
            parentId: nil,
            type: type,
            timestamp: Date(),
            sessionId: "test-session",
            cwd: nil,
            gitBranch: nil,
            slug: nil,
            version: nil,
            model: nil,
            contentBlocks: contentBlocks,
            usage: usage,
            isSidechain: false,
            systemSubtype: systemSubtype,
            durationMs: durationMs,
            toolUseResult: nil
        )
    }

    // MARK: - groupIntoTurns: Normal Sequences

    func testGroupIntoTurns_withSingleUserAssistantPair() {
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Hello"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "Hi there!"),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].userMessage?.id, "u1")
        XCTAssertEqual(turns[0].assistantMessages.count, 1)
        XCTAssertEqual(turns[0].assistantMessages[0].id, "a1")
    }

    func testGroupIntoTurns_withMultipleTurns() {
        let u1 = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "First question"),
        ])
        let a1 = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "First answer"),
        ])
        let u2 = makeMessage(id: "u2", type: .user, contentBlocks: [
            .text(id: "u2-0", text: "Second question"),
        ])
        let a2 = makeMessage(id: "a2", type: .assistant, contentBlocks: [
            .text(id: "a2-0", text: "Second answer"),
        ])

        let turns = SessionParser.groupIntoTurns([u1, a1, u2, a2])

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].userMessage?.id, "u1")
        XCTAssertEqual(turns[0].assistantMessages.count, 1)
        XCTAssertEqual(turns[0].assistantMessages[0].id, "a1")
        XCTAssertEqual(turns[1].userMessage?.id, "u2")
        XCTAssertEqual(turns[1].assistantMessages.count, 1)
        XCTAssertEqual(turns[1].assistantMessages[0].id, "a2")
    }

    func testGroupIntoTurns_withMultipleAssistantMessages() {
        // A user message followed by multiple assistant messages (e.g., multi-step response)
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Do something complex"),
        ])
        let a1 = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "Step 1"),
        ])
        let a2 = makeMessage(id: "a2", type: .assistant, contentBlocks: [
            .text(id: "a2-0", text: "Step 2"),
        ])

        let turns = SessionParser.groupIntoTurns([user, a1, a2])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].assistantMessages.count, 2)
        XCTAssertEqual(turns[0].assistantMessages[0].id, "a1")
        XCTAssertEqual(turns[0].assistantMessages[1].id, "a2")
    }

    // MARK: - groupIntoTurns: Tool Calls

    func testGroupIntoTurns_withToolCallPairs() {
        let toolUseId = "tool-123"
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Read this file"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .toolUse(id: "a1-0", toolId: toolUseId, name: "Read", serverName: nil, inputJSON: "{\"file_path\":\"/tmp/test.txt\"}")
        ])
        let toolResult = makeMessage(id: "tr1", type: .user, contentBlocks: [
            .toolResult(id: "tr1-0", toolUseId: toolUseId, content: "file contents here", isError: false),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant, toolResult])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].toolPairs.count, 1)
        XCTAssertEqual(turns[0].toolPairs[0].id, toolUseId)
        XCTAssertEqual(turns[0].toolPairs[0].name, "Read")
        XCTAssertEqual(turns[0].toolPairs[0].output, "file contents here")
        XCTAssertFalse(turns[0].toolPairs[0].isError)
    }

    func testGroupIntoTurns_withToolCallError() {
        let toolUseId = "tool-err"
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Run command"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .toolUse(id: "a1-0", toolId: toolUseId, name: "Bash", serverName: nil, inputJSON: "{\"command\":\"exit 1\"}")
        ])
        let toolResult = makeMessage(id: "tr1", type: .user, contentBlocks: [
            .toolResult(id: "tr1-0", toolUseId: toolUseId, content: "command failed", isError: true),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant, toolResult])

        XCTAssertEqual(turns[0].toolPairs.count, 1)
        XCTAssertTrue(turns[0].toolPairs[0].isError)
        XCTAssertEqual(turns[0].toolPairs[0].output, "command failed")
    }

    func testGroupIntoTurns_withMultipleToolCalls() {
        let toolId1 = "tool-1"
        let toolId2 = "tool-2"
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Read two files"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .toolUse(id: "a1-0", toolId: toolId1, name: "Read", serverName: nil, inputJSON: "{\"file_path\":\"a.txt\"}"),
            .toolUse(id: "a1-1", toolId: toolId2, name: "Read", serverName: nil, inputJSON: "{\"file_path\":\"b.txt\"}"),
        ])
        let toolResults = makeMessage(id: "tr1", type: .user, contentBlocks: [
            .toolResult(id: "tr1-0", toolUseId: toolId1, content: "contents of a", isError: false),
            .toolResult(id: "tr1-1", toolUseId: toolId2, content: "contents of b", isError: false),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant, toolResults])

        XCTAssertEqual(turns[0].toolPairs.count, 2)
        XCTAssertEqual(turns[0].toolPairs[0].id, toolId1)
        XCTAssertEqual(turns[0].toolPairs[0].output, "contents of a")
        XCTAssertEqual(turns[0].toolPairs[1].id, toolId2)
        XCTAssertEqual(turns[0].toolPairs[1].output, "contents of b")
    }

    func testGroupIntoTurns_toolUseWithoutResult() {
        let toolUseId = "tool-no-result"
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Start something"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .toolUse(id: "a1-0", toolId: toolUseId, name: "Bash", serverName: nil, inputJSON: "{\"command\":\"sleep 10\"}")
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant])

        XCTAssertEqual(turns[0].toolPairs.count, 1)
        XCTAssertEqual(turns[0].toolPairs[0].id, toolUseId)
        XCTAssertNil(turns[0].toolPairs[0].output, "Tool pair should have nil output when no result is received")
    }

    func testGroupIntoTurns_toolResultOnlyUserMessageStaysInTurn() {
        // A user message that contains only tool_result blocks should NOT start a new turn.
        let toolUseId = "tool-abc"
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Do a thing"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .toolUse(id: "a1-0", toolId: toolUseId, name: "Edit", serverName: nil, inputJSON: "{}"),
        ])
        let toolResultUser = makeMessage(id: "tr1", type: .user, contentBlocks: [
            .toolResult(id: "tr1-0", toolUseId: toolUseId, content: "success", isError: false),
        ])
        let assistant2 = makeMessage(id: "a2", type: .assistant, contentBlocks: [
            .text(id: "a2-0", text: "Done!"),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant, toolResultUser, assistant2])

        XCTAssertEqual(turns.count, 1, "Tool result user message should not start a new turn")
        XCTAssertEqual(turns[0].assistantMessages.count, 2)
        XCTAssertEqual(turns[0].toolPairs.count, 1)
        XCTAssertEqual(turns[0].toolPairs[0].output, "success")
    }

    func testGroupIntoTurns_toolWithServerName() {
        let toolUseId = "mcp-tool-1"
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Use MCP tool"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .toolUse(id: "a1-0", toolId: toolUseId, name: "custom_tool", serverName: "my-server", inputJSON: "{}")
        ])
        let toolResult = makeMessage(id: "tr1", type: .user, contentBlocks: [
            .toolResult(id: "tr1-0", toolUseId: toolUseId, content: "result", isError: false),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant, toolResult])

        XCTAssertEqual(turns[0].toolPairs[0].serverName, "my-server")
    }

    // MARK: - groupIntoTurns: Edge Cases

    func testGroupIntoTurns_emptyInput() {
        let turns = SessionParser.groupIntoTurns([])

        XCTAssertTrue(turns.isEmpty)
    }

    func testGroupIntoTurns_userMessageWithNoResponse() {
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Unanswered question"),
        ])

        let turns = SessionParser.groupIntoTurns([user])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].userMessage?.id, "u1")
        XCTAssertTrue(turns[0].assistantMessages.isEmpty)
        XCTAssertTrue(turns[0].toolPairs.isEmpty)
    }

    func testGroupIntoTurns_consecutiveUserMessages() {
        // Each real user message (with text) starts a new turn, so consecutive user messages
        // create separate turns. The first turn has no assistant response.
        let u1 = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "First"),
        ])
        let u2 = makeMessage(id: "u2", type: .user, contentBlocks: [
            .text(id: "u2-0", text: "Second"),
        ])
        let a1 = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "Response to second"),
        ])

        let turns = SessionParser.groupIntoTurns([u1, u2, a1])

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].userMessage?.id, "u1")
        XCTAssertTrue(turns[0].assistantMessages.isEmpty, "First turn should have no assistant response")
        XCTAssertEqual(turns[1].userMessage?.id, "u2")
        XCTAssertEqual(turns[1].assistantMessages.count, 1)
    }

    func testGroupIntoTurns_assistantOnlyMessages() {
        // Edge case: assistant messages without a preceding user message
        let a1 = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "Unrequested response"),
        ])

        let turns = SessionParser.groupIntoTurns([a1])

        XCTAssertEqual(turns.count, 1)
        XCTAssertNil(turns[0].userMessage)
        XCTAssertEqual(turns[0].assistantMessages.count, 1)
    }

    // MARK: - groupIntoTurns: System Events

    func testGroupIntoTurns_systemTurnDurationFlushes() {
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Question"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "Answer"),
        ])
        let duration = makeMessage(
            id: "s1", type: .system,
            systemSubtype: "turn_duration",
            durationMs: 1500.0
        )

        let turns = SessionParser.groupIntoTurns([user, assistant, duration])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].durationMs, 1500.0)
    }

    // MARK: - groupIntoTurns: Token Usage

    func testGroupIntoTurns_accumulatesTokenUsage() {
        let usage1 = TokenUsage(inputTokens: 100, outputTokens: 50, cacheReadTokens: 10, cacheCreationTokens: 5)
        let usage2 = TokenUsage(inputTokens: 200, outputTokens: 80, cacheReadTokens: 20, cacheCreationTokens: 15)

        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Multi-step question"),
        ])
        let a1 = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "Part 1"),
        ], usage: usage1)
        let a2 = makeMessage(id: "a2", type: .assistant, contentBlocks: [
            .text(id: "a2-0", text: "Part 2"),
        ], usage: usage2)

        let turns = SessionParser.groupIntoTurns([user, a1, a2])

        XCTAssertEqual(turns.count, 1)
        let totalUsage = turns[0].totalUsage
        XCTAssertNotNil(totalUsage)
        XCTAssertEqual(totalUsage?.inputTokens, 300)
        XCTAssertEqual(totalUsage?.outputTokens, 130)
        XCTAssertEqual(totalUsage?.cacheReadTokens, 30)
        XCTAssertEqual(totalUsage?.cacheCreationTokens, 20)
    }

    func testGroupIntoTurns_noUsageReturnsNil() {
        let user = makeMessage(id: "u1", type: .user, contentBlocks: [
            .text(id: "u1-0", text: "Simple question"),
        ])
        let assistant = makeMessage(id: "a1", type: .assistant, contentBlocks: [
            .text(id: "a1-0", text: "Simple answer"),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant])

        XCTAssertNil(turns[0].totalUsage, "Should be nil when no usage data is present")
    }

    // MARK: - groupIntoTurns: Turn ID Assignment

    func testGroupIntoTurns_turnIdUsesUserMessageId() {
        let user = makeMessage(id: "user-id-123", type: .user, contentBlocks: [
            .text(id: "u-0", text: "Hello"),
        ])
        let assistant = makeMessage(id: "asst-id-456", type: .assistant, contentBlocks: [
            .text(id: "a-0", text: "Hi"),
        ])

        let turns = SessionParser.groupIntoTurns([user, assistant])

        XCTAssertEqual(turns[0].id, "user-id-123", "Turn ID should come from the user message")
    }

    func testGroupIntoTurns_turnIdFallsBackToFirstAssistantId() {
        let assistant = makeMessage(id: "asst-only-id", type: .assistant, contentBlocks: [
            .text(id: "a-0", text: "Just an assistant message"),
        ])

        let turns = SessionParser.groupIntoTurns([assistant])

        XCTAssertEqual(turns[0].id, "asst-only-id", "Turn ID should fall back to first message ID when no user message")
    }

    // MARK: - groupIntoTurns: Complex Sequence

    func testGroupIntoTurns_fullConversationWithToolCalls() {
        // Simulate: user -> assistant(tool_use) -> user(tool_result) -> assistant(text) -> system(turn_duration)
        //           -> user -> assistant
        let toolId = "tool-xyz"

        let messages: [SessionMessage] = [
            makeMessage(id: "u1", type: .user, contentBlocks: [
                .text(id: "u1-0", text: "Edit a file"),
            ]),
            makeMessage(id: "a1", type: .assistant, contentBlocks: [
                .text(id: "a1-0", text: "I will edit the file."),
                .toolUse(id: "a1-1", toolId: toolId, name: "Edit", serverName: nil, inputJSON: "{\"file_path\":\"test.swift\"}"),
            ]),
            makeMessage(id: "tr1", type: .user, contentBlocks: [
                .toolResult(id: "tr1-0", toolUseId: toolId, content: "File edited", isError: false),
            ]),
            makeMessage(id: "a2", type: .assistant, contentBlocks: [
                .text(id: "a2-0", text: "The file has been edited."),
            ]),
            makeMessage(id: "s1", type: .system, systemSubtype: "turn_duration", durationMs: 2500.0),
            makeMessage(id: "u2", type: .user, contentBlocks: [
                .text(id: "u2-0", text: "Thanks!"),
            ]),
            makeMessage(id: "a3", type: .assistant, contentBlocks: [
                .text(id: "a3-0", text: "You're welcome!"),
            ]),
        ]

        let turns = SessionParser.groupIntoTurns(messages)

        XCTAssertEqual(turns.count, 2)

        // First turn
        XCTAssertEqual(turns[0].userMessage?.id, "u1")
        XCTAssertEqual(turns[0].assistantMessages.count, 2)
        XCTAssertEqual(turns[0].toolPairs.count, 1)
        XCTAssertEqual(turns[0].toolPairs[0].name, "Edit")
        XCTAssertEqual(turns[0].toolPairs[0].output, "File edited")
        XCTAssertEqual(turns[0].durationMs, 2500.0)

        // Second turn
        XCTAssertEqual(turns[1].userMessage?.id, "u2")
        XCTAssertEqual(turns[1].assistantMessages.count, 1)
        XCTAssertTrue(turns[1].toolPairs.isEmpty)
    }

    // MARK: - extractAgentId

    func testExtractAgentId_validOutput() {
        let output = "Task completed successfully.\nagentId: abc123xyz"
        let result = SessionParser.extractAgentId(from: output)
        XCTAssertEqual(result, "abc123xyz")
    }

    func testExtractAgentId_noAgentId() {
        let output = "Just some output without an agent ID"
        let result = SessionParser.extractAgentId(from: output)
        XCTAssertNil(result)
    }

    func testExtractAgentId_extraWhitespace() {
        let output = "agentId:   spaced-id-456"
        let result = SessionParser.extractAgentId(from: output)
        XCTAssertEqual(result, "spaced-id-456")
    }
}
