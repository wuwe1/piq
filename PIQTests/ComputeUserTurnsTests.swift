import XCTest
@testable import PIQ

final class ComputeUserTurnsTests: XCTestCase {

    // MARK: - Helpers

    private func makeMessage(
        id: String = UUID().uuidString,
        type: SessionMessageType,
        contentBlocks: [SessionContentBlock] = [],
        usage: TokenUsage? = nil
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
            systemSubtype: nil,
            durationMs: nil,
            toolUseResult: nil
        )
    }

    private func makeTurn(
        id: String = UUID().uuidString,
        userText: String? = nil,
        hasAssistant: Bool = true,
        toolPairs: [ToolCallPair] = []
    ) -> SessionTurn {
        let userMsg: SessionMessage? = userText.map { text in
            makeMessage(id: "\(id)-user", type: .user, contentBlocks: [
                .text(id: "\(id)-user-0", text: text),
            ])
        }

        let assistantMsgs: [SessionMessage] = hasAssistant ? [
            makeMessage(id: "\(id)-asst", type: .assistant, contentBlocks: [
                .text(id: "\(id)-asst-0", text: "Response"),
            ]),
        ] : []

        return SessionTurn(
            id: id,
            userMessage: userMsg,
            assistantMessages: assistantMsgs,
            toolPairs: toolPairs,
            durationMs: nil,
            totalUsage: nil
        )
    }

    // MARK: - Normal Cases

    func testComputeUserTurns_withNormalTurns() {
        let turns = [
            makeTurn(id: "t1", userText: "First question"),
            makeTurn(id: "t2", userText: "Second question"),
            makeTurn(id: "t3", userText: "Third question"),
        ]

        let result = SessionTurnListView.computeUserTurns(from: turns)

        XCTAssertEqual(result.count, 3)

        // Check 1-based user indices
        XCTAssertEqual(result[0].index, 1)
        XCTAssertEqual(result[1].index, 2)
        XCTAssertEqual(result[2].index, 3)

        // Check text extraction
        XCTAssertEqual(result[0].text, "First question")
        XCTAssertEqual(result[1].text, "Second question")
        XCTAssertEqual(result[2].text, "Third question")
    }

    func testComputeUserTurns_globalIndexMatchesTurnsArrayIndex() {
        let turns = [
            makeTurn(id: "t1", userText: "Question A"),
            makeTurn(id: "t2", userText: "Question B"),
        ]

        let result = SessionTurnListView.computeUserTurns(from: turns)

        XCTAssertEqual(result[0].globalIndex, 0)
        XCTAssertEqual(result[1].globalIndex, 1)
    }

    // MARK: - Pending (No-Response) Turns

    func testComputeUserTurns_pendingTurnMergedIntoNextResponsive() {
        // A turn with a user message but no assistant response should be merged
        // into the next turn that has a response.
        let pendingTurn = makeTurn(id: "pending", userText: "First part", hasAssistant: false)
        let responsiveTurn = makeTurn(id: "responsive", userText: "Second part", hasAssistant: true)

        let result = SessionTurnListView.computeUserTurns(from: [pendingTurn, responsiveTurn])

        XCTAssertEqual(result.count, 1, "Pending turn should merge into the responsive turn")
        XCTAssertEqual(result[0].index, 1)
        XCTAssertEqual(result[0].text, "First part\nSecond part", "Texts should be joined with newline")
        XCTAssertEqual(result[0].globalIndex, 1, "Global index should point to the responsive turn")
    }

    func testComputeUserTurns_multiplePendingTurnsMerged() {
        let p1 = makeTurn(id: "p1", userText: "Part 1", hasAssistant: false)
        let p2 = makeTurn(id: "p2", userText: "Part 2", hasAssistant: false)
        let responsive = makeTurn(id: "r1", userText: "Part 3", hasAssistant: true)

        let result = SessionTurnListView.computeUserTurns(from: [p1, p2, responsive])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Part 1\nPart 2\nPart 3")
        XCTAssertEqual(result[0].globalIndex, 2)
    }

    func testComputeUserTurns_pendingTurnAtEnd_isNotIncluded() {
        // A pending turn at the very end with no subsequent responsive turn
        // should not produce a user turn item.
        let responsive = makeTurn(id: "r1", userText: "Answered", hasAssistant: true)
        let pending = makeTurn(id: "p1", userText: "Unanswered", hasAssistant: false)

        let result = SessionTurnListView.computeUserTurns(from: [responsive, pending])

        XCTAssertEqual(result.count, 1, "Only the responsive turn should appear")
        XCTAssertEqual(result[0].text, "Answered")
    }

    func testComputeUserTurns_allTurnsContainsMergedTurns() {
        let p1 = makeTurn(id: "p1", userText: "Pending", hasAssistant: false)
        let r1 = makeTurn(id: "r1", userText: "Responsive", hasAssistant: true)

        let result = SessionTurnListView.computeUserTurns(from: [p1, r1])

        XCTAssertEqual(result[0].allTurns.count, 2, "allTurns should contain both pending and responsive turns")
        XCTAssertEqual(result[0].allTurns[0].id, "p1")
        XCTAssertEqual(result[0].allTurns[1].id, "r1")
    }

    // MARK: - Turns Without User Messages

    func testComputeUserTurns_turnsWithNoUserMessage_areSkipped() {
        // A turn with nil userMessage (e.g., assistant-only) should be skipped
        let turnNoUser = SessionTurn(
            id: "no-user",
            userMessage: nil,
            assistantMessages: [
                makeMessage(id: "a1", type: .assistant, contentBlocks: [
                    .text(id: "a1-0", text: "Unsolicited"),
                ]),
            ],
            toolPairs: [],
            durationMs: nil,
            totalUsage: nil
        )
        let normalTurn = makeTurn(id: "normal", userText: "Hello", hasAssistant: true)

        let result = SessionTurnListView.computeUserTurns(from: [turnNoUser, normalTurn])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "Hello")
        XCTAssertEqual(result[0].globalIndex, 1, "Should reference the second turn in the array")
    }

    // MARK: - Edge Cases

    func testComputeUserTurns_emptyInput() {
        let result = SessionTurnListView.computeUserTurns(from: [])

        XCTAssertTrue(result.isEmpty)
    }

    func testComputeUserTurns_singleTurn() {
        let turn = makeTurn(id: "only", userText: "Only question", hasAssistant: true)

        let result = SessionTurnListView.computeUserTurns(from: [turn])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].index, 1)
        XCTAssertEqual(result[0].globalIndex, 0)
        XCTAssertEqual(result[0].text, "Only question")
    }

    func testComputeUserTurns_turnWithEmptyText() {
        // User message with empty text content blocks
        let userMsg = makeMessage(id: "u-empty", type: .user, contentBlocks: [
            .text(id: "u-empty-0", text: ""),
        ])
        let assistantMsg = makeMessage(id: "a-empty", type: .assistant, contentBlocks: [
            .text(id: "a-empty-0", text: "I'll help"),
        ])
        let turn = SessionTurn(
            id: "empty-text",
            userMessage: userMsg,
            assistantMessages: [assistantMsg],
            toolPairs: [],
            durationMs: nil,
            totalUsage: nil
        )

        let result = SessionTurnListView.computeUserTurns(from: [turn])

        XCTAssertEqual(result.count, 1)
        // Empty text with no tool_result blocks yields empty string (not "(image)")
        XCTAssertEqual(result[0].text, "")
    }

    func testComputeUserTurns_turnWithToolPairsCountsAsResponse() {
        // A turn with no assistant messages but with tool pairs should still be
        // considered as having a response.
        let userMsg = makeMessage(id: "u-tool", type: .user, contentBlocks: [
            .text(id: "u-tool-0", text: "Use a tool"),
        ])
        let toolPair = ToolCallPair(
            id: "tp-1",
            name: "Bash",
            serverName: nil,
            inputJSON: "{}",
            output: "output",
            isError: false
        )
        let turn = SessionTurn(
            id: "tool-turn",
            userMessage: userMsg,
            assistantMessages: [],
            toolPairs: [toolPair],
            durationMs: nil,
            totalUsage: nil
        )

        let result = SessionTurnListView.computeUserTurns(from: [turn])

        XCTAssertEqual(result.count, 1, "Turn with tool pairs should be treated as having a response")
        XCTAssertEqual(result[0].text, "Use a tool")
    }

    // MARK: - ID Generation

    func testComputeUserTurns_idIncludesAssistantAndToolCounts() {
        let toolPair = ToolCallPair(
            id: "tp-id", name: "Read", serverName: nil,
            inputJSON: "{}", output: "data", isError: false
        )
        let turn = makeTurn(id: "t1", userText: "Test")
        // The default makeTurn gives 1 assistant message and 0 tool pairs.
        // id format: "\(turn.id)-\(turn.assistantMessages.count)-\(turn.toolPairs.count)"

        let result = SessionTurnListView.computeUserTurns(from: [turn])

        XCTAssertEqual(result[0].id, "t1-1-0", "ID should encode assistant count and tool pair count")
    }

    // MARK: - Mixed Pending and Normal

    func testComputeUserTurns_mixedPendingAndNormalTurns() {
        let turns = [
            makeTurn(id: "t1", userText: "Q1", hasAssistant: true),
            makeTurn(id: "t2", userText: "Pending Q2", hasAssistant: false),
            makeTurn(id: "t3", userText: "Q3 with response", hasAssistant: true),
            makeTurn(id: "t4", userText: "Q4", hasAssistant: true),
        ]

        let result = SessionTurnListView.computeUserTurns(from: turns)

        XCTAssertEqual(result.count, 3)

        // First item: standalone
        XCTAssertEqual(result[0].index, 1)
        XCTAssertEqual(result[0].globalIndex, 0)
        XCTAssertEqual(result[0].text, "Q1")

        // Second item: merged pending + responsive
        XCTAssertEqual(result[1].index, 2)
        XCTAssertEqual(result[1].globalIndex, 2)
        XCTAssertEqual(result[1].text, "Pending Q2\nQ3 with response")
        XCTAssertEqual(result[1].allTurns.count, 2)

        // Third item: standalone
        XCTAssertEqual(result[2].index, 3)
        XCTAssertEqual(result[2].globalIndex, 3)
        XCTAssertEqual(result[2].text, "Q4")
    }
}
