import Foundation

// MARK: - SessionParser

/// Parses Claude Code JSONL session files.
enum SessionParser {

    // MARK: - Metadata Extraction (Head + Tail only)

    /// Read head 32KB + tail 32KB to extract list-level metadata.
    static func extractMetadata(from url: URL) -> SessionEntry? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let headSize = 32 * 1024
        let headData = handle.readData(ofLength: headSize)
        let headLines = linesFromData(headData)

        // Also read tail
        let fileSize = (try? handle.seekToEnd()) ?? 0
        var tailLines: [Data] = []
        if fileSize > headSize {
            let tailStart = max(0, fileSize - UInt64(headSize))
            handle.seek(toFileOffset: tailStart)
            let tailData = handle.readData(ofLength: headSize)
            tailLines = linesFromData(tailData)
            // If we started mid-line, drop the first partial line
            if tailStart > 0 && !tailLines.isEmpty {
                tailLines.removeFirst()
            }
        }

        // Parse head lines for first message metadata
        var sessionId: String?
        var cwd: String?
        var gitBranch: String = ""
        var slug: String = ""
        var model: String = ""
        var version: String?
        var firstPrompt: String = ""
        var createdAt: Date?
        var hasSubagents = false

        var userCount = 0
        var assistantCount = 0

        for lineData in headLines {
            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let lineType = json["type"] as? String ?? ""

            // Skip types that don't carry session metadata
            if lineType == "file-history-snapshot" { continue }

            if sessionId == nil, let sid = json["sessionId"] as? String, !sid.isEmpty {
                sessionId = sid
            }
            if cwd == nil, let c = json["cwd"] as? String, !c.isEmpty {
                cwd = c
            }
            if gitBranch.isEmpty, let b = json["gitBranch"] as? String, !b.isEmpty {
                gitBranch = b
            }
            if slug.isEmpty, let s = json["slug"] as? String, !s.isEmpty {
                slug = s
            }
            if version == nil, let v = json["version"] as? String, !v.isEmpty {
                version = v
            }

            // Use timestamp of the first real message as creation time
            if createdAt == nil, (lineType == "user" || lineType == "assistant"),
               let ts = json["timestamp"] as? String {
                createdAt = parseISO8601(ts)
            }

            if lineType == "user" || lineType == "assistant" {
                if lineType == "user" { userCount += 1 }
                if lineType == "assistant" { assistantCount += 1 }
            }

            // Extract model from assistant message
            if model.isEmpty, lineType == "assistant",
               let msg = json["message"] as? [String: Any],
               let m = msg["model"] as? String {
                model = m
            }

            // Extract first user prompt (skip tool_result-only user messages)
            if firstPrompt.isEmpty, lineType == "user",
               let msg = json["message"] as? [String: Any] {
                firstPrompt = extractUserText(from: msg)
            }

            if let sidechain = json["isSidechain"] as? Bool, sidechain {
                hasSubagents = true
            }
        }

        // Parse tail for last activity and additional counts
        var lastActivityAt: Date?
        for lineData in tailLines.reversed() {
            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            let lineType = json["type"] as? String ?? ""

            if lineType == "user" || lineType == "assistant" {
                if lineType == "user" { userCount += 1 }
                if lineType == "assistant" { assistantCount += 1 }
            }

            // Update metadata from tail if not found in head
            if slug.isEmpty, let s = json["slug"] as? String {
                slug = s
            }
            if model.isEmpty, lineType == "assistant",
               let msg = json["message"] as? [String: Any],
               let m = msg["model"] as? String {
                model = m
            }
            if let sidechain = json["isSidechain"] as? Bool, sidechain {
                hasSubagents = true
            }

            if lastActivityAt == nil, let ts = json["timestamp"] as? String {
                lastActivityAt = parseISO8601(ts)
            }
        }

        guard let sid = sessionId else { return nil }

        let projectPath = cwd ?? ""
        let projectName = (projectPath as NSString).lastPathComponent

        return SessionEntry(
            id: sid,
            projectPath: projectPath,
            projectName: projectName,
            firstPrompt: firstPrompt,
            messageCount: userCount + assistantCount,
            model: model,
            gitBranch: gitBranch,
            slug: slug,
            createdAt: createdAt ?? Date.distantPast,
            lastActivityAt: lastActivityAt ?? createdAt ?? Date.distantPast,
            jsonlURL: url,
            hasSubagents: hasSubagents
        )
    }

    // MARK: - Full Parse

    /// Parse all messages from a JSONL file, filtering out progress/file-history-snapshot.
    static func parseFile(at url: URL) -> [SessionMessage] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let lines = linesFromData(data)
        return lines.compactMap { parseLine($0) }
    }

    /// Parse a single JSONL line into a SessionMessage.
    static func parseLine(_ data: Data) -> SessionMessage? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let typeStr = json["type"] as? String ?? ""

        // Skip noise types
        guard let msgType = SessionMessageType(rawValue: typeStr),
              msgType != .progress,
              msgType != .fileHistorySnapshot,
              msgType != .hookProgress else { return nil }

        let uuid = json["uuid"] as? String ?? UUID().uuidString
        let parentUuid = json["parentUuid"] as? String
        let timestamp = (json["timestamp"] as? String).flatMap(parseISO8601) ?? Date()
        let sessionId = json["sessionId"] as? String ?? ""
        let cwd = json["cwd"] as? String
        let gitBranch = json["gitBranch"] as? String
        let slug = json["slug"] as? String
        let version = json["version"] as? String
        let isSidechain = json["isSidechain"] as? Bool ?? false

        var model: String?
        var contentBlocks: [SessionContentBlock] = []
        var usage: TokenUsage?
        var systemSubtype: String?
        var durationMs: Double?
        var toolUseResult: ToolUseResultInfo?

        if let message = json["message"] as? [String: Any] {
            model = message["model"] as? String

            // Parse content blocks
            if let contentArray = message["content"] as? [[String: Any]] {
                contentBlocks = contentArray.compactMap { parseContentBlock($0, messageType: msgType) }
            } else if let textContent = message["content"] as? String {
                contentBlocks = [.text(id: UUID().uuidString, text: textContent)]
            }

            // Parse usage
            if let usageDict = message["usage"] as? [String: Any] {
                usage = TokenUsage(
                    inputTokens: usageDict["input_tokens"] as? Int ?? 0,
                    outputTokens: usageDict["output_tokens"] as? Int ?? 0,
                    cacheReadTokens: usageDict["cache_read_input_tokens"] as? Int ?? 0,
                    cacheCreationTokens: usageDict["cache_creation_input_tokens"] as? Int ?? 0
                )
            }
        }

        // System message fields
        if msgType == .system {
            systemSubtype = json["subtype"] as? String
            durationMs = json["durationMs"] as? Double

            // Also check nested data
            if let data = json["data"] as? [String: Any] {
                if systemSubtype == nil {
                    systemSubtype = data["subtype"] as? String
                }
                if durationMs == nil {
                    durationMs = data["durationMs"] as? Double
                }
            }
        }

        // Tool use result
        if let tur = json["toolUseResult"] as? [String: Any] {
            toolUseResult = ToolUseResultInfo(
                stdout: tur["stdout"] as? String,
                stderr: tur["stderr"] as? String,
                interrupted: tur["interrupted"] as? Bool ?? false,
                isImage: tur["isImage"] as? Bool ?? false,
                fileOperationType: tur["type"] as? String,
                filePath: tur["filePath"] as? String
            )
        }

        return SessionMessage(
            id: uuid,
            parentId: parentUuid,
            type: msgType,
            timestamp: timestamp,
            sessionId: sessionId,
            cwd: cwd,
            gitBranch: gitBranch,
            slug: slug,
            version: version,
            model: model,
            contentBlocks: contentBlocks,
            usage: usage,
            isSidechain: isSidechain,
            systemSubtype: systemSubtype,
            durationMs: durationMs,
            toolUseResult: toolUseResult
        )
    }

    // MARK: - Turn Grouping

    /// Group sequential messages into logical turns.
    /// A turn starts with a user message and includes all subsequent assistant messages
    /// and tool interactions until the next user message.
    static func groupIntoTurns(_ messages: [SessionMessage]) -> [SessionTurn] {
        var turns: [SessionTurn] = []
        var currentUserMsg: SessionMessage?
        var currentAssistantMsgs: [SessionMessage] = []
        var currentSystemEvents: [SessionMessage] = []
        var toolUseMap: [String: (name: String, serverName: String?, inputJSON: String)] = [:]  // toolId -> info

        func flushTurn() {
            guard currentUserMsg != nil || !currentAssistantMsgs.isEmpty else { return }

            // Build tool pairs
            var toolPairs: [ToolCallPair] = []
            for assistantMsg in currentAssistantMsgs {
                for block in assistantMsg.contentBlocks {
                    if case .toolUse(_, let toolId, let name, let serverName, let inputJSON) = block {
                        toolUseMap[toolId] = (name, serverName, inputJSON)
                    }
                }
            }

            // Match tool results from user messages that follow
            // (tool results come as user messages with tool_result content blocks)
            for assistantMsg in currentAssistantMsgs {
                for block in assistantMsg.contentBlocks {
                    if case .toolUse(_, let toolId, let name, let serverName, let inputJSON) = block {
                        toolPairs.append(ToolCallPair(
                            id: toolId,
                            name: name,
                            serverName: serverName,
                            inputJSON: inputJSON,
                            output: nil,
                            isError: false
                        ))
                    }
                }
            }

            // Find tool results in interleaved user messages
            let allMsgs = currentAssistantMsgs
            for msg in allMsgs {
                if msg.type == .user {
                    for block in msg.contentBlocks {
                        if case .toolResult(_, let toolUseId, let content, let isError) = block {
                            if let idx = toolPairs.firstIndex(where: { $0.id == toolUseId }) {
                                toolPairs[idx] = ToolCallPair(
                                    id: toolUseId,
                                    name: toolPairs[idx].name,
                                    serverName: toolPairs[idx].serverName,
                                    inputJSON: toolPairs[idx].inputJSON,
                                    output: content,
                                    isError: isError
                                )
                            }
                        }
                    }
                }
            }

            // Calculate total usage
            let usages = currentAssistantMsgs.compactMap(\.usage)
            let totalUsage = usages.isEmpty ? nil : usages.reduce(TokenUsage.zero, +)

            // Get duration from system events
            let duration = currentSystemEvents
                .first(where: { $0.systemSubtype == "turn_duration" })?.durationMs

            turns.append(SessionTurn(
                id: currentUserMsg?.id ?? currentAssistantMsgs.first?.id ?? UUID().uuidString,
                userMessage: currentUserMsg,
                assistantMessages: currentAssistantMsgs.filter { $0.type == .assistant },
                toolPairs: toolPairs,
                durationMs: duration,
                totalUsage: totalUsage
            ))

            currentUserMsg = nil
            currentAssistantMsgs = []
            currentSystemEvents = []
            toolUseMap = [:]
        }

        for message in messages {
            switch message.type {
            case .user:
                // Check if this user message contains only tool_result blocks
                let hasOnlyToolResults = !message.contentBlocks.isEmpty &&
                    message.contentBlocks.allSatisfy {
                        if case .toolResult = $0 { return true }
                        return false
                    }

                if hasOnlyToolResults {
                    // This is a tool result response, attach to current turn
                    // Match results to pending tool calls
                    for block in message.contentBlocks {
                        if case .toolResult(_, let toolUseId, let content, let isError) = block {
                            if let idx = currentAssistantMsgs.lastIndex(where: { assistantMsg in
                                assistantMsg.contentBlocks.contains(where: {
                                    if case .toolUse(_, let tid, _, _, _) = $0 { return tid == toolUseId }
                                    return false
                                })
                            }) {
                                // Store the result - we'll pair it later in flushTurn
                            }
                        }
                    }
                    currentAssistantMsgs.append(message) // Keep for pairing
                } else {
                    // New human turn
                    flushTurn()
                    currentUserMsg = message
                }

            case .assistant:
                currentAssistantMsgs.append(message)

            case .system:
                currentSystemEvents.append(message)
                if message.systemSubtype == "turn_duration" {
                    // Turn duration marks the end of a turn
                    flushTurn()
                }

            case .progress, .fileHistorySnapshot, .hookProgress:
                break // Already filtered
            }
        }

        flushTurn()
        return turns
    }

    // MARK: - Private Helpers

    private static func linesFromData(_ data: Data) -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        for i in data.indices where data[i] == UInt8(ascii: "\n") {
            if i > start {
                lines.append(data[start..<i])
            }
            start = i + 1
        }
        if start < data.endIndex {
            lines.append(data[start..<data.endIndex])
        }
        return lines
    }

    private static func parseContentBlock(_ dict: [String: Any], messageType: SessionMessageType) -> SessionContentBlock? {
        let blockType = dict["type"] as? String ?? ""

        switch blockType {
        case "text":
            let text = dict["text"] as? String ?? ""
            return .text(id: UUID().uuidString, text: text)

        case "thinking":
            let text = dict["thinking"] as? String ?? ""
            guard !text.isEmpty else { return nil }
            return .thinking(id: UUID().uuidString, text: text)

        case "tool_use":
            let toolId = dict["id"] as? String ?? UUID().uuidString
            let name = dict["name"] as? String ?? "unknown"
            let serverName = dict["server_name"] as? String
            var inputJSON = "{}"
            if let input = dict["input"] {
                if let inputData = try? JSONSerialization.data(withJSONObject: input, options: [.prettyPrinted, .sortedKeys]),
                   let inputStr = String(data: inputData, encoding: .utf8) {
                    inputJSON = inputStr
                }
            }
            return .toolUse(id: UUID().uuidString, toolId: toolId, name: name, serverName: serverName, inputJSON: inputJSON)

        case "tool_result":
            let toolUseId = dict["tool_use_id"] as? String ?? ""
            let isError = dict["is_error"] as? Bool ?? false
            var content = ""
            if let c = dict["content"] as? String {
                content = c
            } else if let contentArray = dict["content"] as? [[String: Any]] {
                content = contentArray.compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            return .toolResult(id: UUID().uuidString, toolUseId: toolUseId, content: content, isError: isError)

        default:
            return nil
        }
    }

    private static nonisolated(unsafe) let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static nonisolated(unsafe) let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseISO8601(_ string: String) -> Date? {
        iso8601Formatter.date(from: string) ?? iso8601FallbackFormatter.date(from: string)
    }

    /// Extract human-readable text from a user message's content field.
    /// Handles both string content and array-of-blocks content.
    /// Returns empty string for tool_result-only messages.
    private static func extractUserText(from message: [String: Any]) -> String {
        // Case 1: content is a plain string
        if let text = message["content"] as? String {
            return String(text.prefix(200))
        }

        // Case 2: content is an array of blocks
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                let blockType = block["type"] as? String ?? ""
                if blockType == "text", let text = block["text"] as? String, !text.isEmpty {
                    return String(text.prefix(200))
                }
            }
        }

        return ""
    }
}
