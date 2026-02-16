import Foundation

// MARK: - SessionParser

/// Parses Claude Code JSONL session files.
enum SessionParser {

    // MARK: - Metadata Extraction (Full Scan)

    /// Read entire JSONL file to extract accurate metadata.
    static func extractMetadata(from url: URL) -> SessionEntry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let allLines = linesFromData(data)

        var sessionId: String?
        var cwd: String?
        var gitBranch: String = ""
        var slug: String = ""
        var model: String = ""
        var firstPrompt: String = ""
        var lastPrompt: String = ""
        var lastOutput: String = ""
        var createdAt: Date?
        var lastActivityAt: Date?
        var hasSubagents = false

        var userCount = 0
        var assistantCount = 0
        var userTurnCount = 0
        var inputTokens = 0
        var outputTokens = 0
        var cacheReadTokens = 0
        var cacheCreationTokens = 0

        for lineData in allLines {
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

            // Use timestamp of the first real message as creation time
            if createdAt == nil, (lineType == "user" || lineType == "assistant"),
               let ts = json["timestamp"] as? String {
                createdAt = parseISO8601(ts)
            }

            // Track last activity from any line with a timestamp
            if let ts = json["timestamp"] as? String, let date = parseISO8601(ts) {
                lastActivityAt = date
            }

            if lineType == "user" {
                userCount += 1
                if let msg = json["message"] as? [String: Any] {
                    if isRealUserMessage(msg) {
                        userTurnCount += 1
                    }
                }
            }
            if lineType == "assistant" {
                assistantCount += 1
                if let msg = json["message"] as? [String: Any],
                   let usage = msg["usage"] as? [String: Any] {
                    inputTokens += usage["input_tokens"] as? Int ?? 0
                    outputTokens += usage["output_tokens"] as? Int ?? 0
                    cacheReadTokens += usage["cache_read_input_tokens"] as? Int ?? 0
                    cacheCreationTokens += usage["cache_creation_input_tokens"] as? Int ?? 0
                }
            }

            // Extract model from assistant message
            if model.isEmpty, lineType == "assistant",
               let msg = json["message"] as? [String: Any],
               let m = msg["model"] as? String {
                model = m
            }

            // Extract user prompts (skip tool_result-only and interruption marker messages)
            if lineType == "user",
               let msg = json["message"] as? [String: Any] {
                let text = extractUserText(from: msg)
                if !text.isEmpty && !text.hasPrefix("[Request interrupted") {
                    if firstPrompt.isEmpty {
                        firstPrompt = text
                    }
                    lastPrompt = text
                }
            }

            // Extract last assistant text output
            if lineType == "assistant",
               let msg = json["message"] as? [String: Any] {
                let text = extractAssistantText(from: msg)
                if !text.isEmpty {
                    lastOutput = text
                }
            }

            if let sidechain = json["isSidechain"] as? Bool, sidechain {
                hasSubagents = true
            }
        }

        guard let sid = sessionId else { return nil }

        let fileUUID = url.deletingPathExtension().lastPathComponent

        // Use file modification date as fallback for missing timestamps
        let fileMtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        let resolvedCreated = createdAt ?? fileMtime ?? Date()
        let resolvedLastActivity = lastActivityAt ?? createdAt ?? fileMtime ?? Date()

        // Skip empty sessions with no prompt and no messages
        if firstPrompt.isEmpty && (userCount + assistantCount) == 0 {
            return nil
        }

        // Skip warmup/prefill sessions (Claude Code internal)
        if firstPrompt == "Warmup" {
            return nil
        }

        let projectPath = cwd ?? ""
        let projectName = (projectPath as NSString).lastPathComponent

        return SessionEntry(
            id: fileUUID,
            sessionId: sid,
            projectPath: projectPath,
            projectName: projectName,
            firstPrompt: firstPrompt,
            lastPrompt: lastPrompt,
            lastOutput: lastOutput,
            userTurnCount: userTurnCount,
            messageCount: userCount + assistantCount,
            model: model,
            gitBranch: gitBranch,
            slug: slug,
            createdAt: resolvedCreated,
            lastActivityAt: resolvedLastActivity,
            jsonlURL: url,
            hasSubagents: hasSubagents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens
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
        // Collects assistant messages AND tool_result user messages for the current turn.
        var currentTurnMessages: [SessionMessage] = []
        var currentSystemEvents: [SessionMessage] = []

        func flushTurn() {
            guard currentUserMsg != nil || !currentTurnMessages.isEmpty else { return }

            // Collect tool_use blocks into pairs (initially without output)
            var toolPairs: [ToolCallPair] = []
            for msg in currentTurnMessages {
                for block in msg.contentBlocks {
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

            // Match tool_result blocks to their corresponding tool_use pairs
            for msg in currentTurnMessages where msg.type == .user {
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

            // Calculate total usage
            let usages = currentTurnMessages.compactMap(\.usage)
            let totalUsage = usages.isEmpty ? nil : usages.reduce(TokenUsage.zero, +)

            // Get duration from system events
            let duration = currentSystemEvents
                .first(where: { $0.systemSubtype == "turn_duration" })?.durationMs

            turns.append(SessionTurn(
                id: currentUserMsg?.id ?? currentTurnMessages.first?.id ?? UUID().uuidString,
                userMessage: currentUserMsg,
                assistantMessages: currentTurnMessages.filter { $0.type == .assistant },
                toolPairs: toolPairs,
                durationMs: duration,
                totalUsage: totalUsage
            ))

            currentUserMsg = nil
            currentTurnMessages = []
            currentSystemEvents = []
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
                    currentTurnMessages.append(message)
                } else {
                    // New human turn
                    flushTurn()
                    currentUserMsg = message
                }

            case .assistant:
                currentTurnMessages.append(message)

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

    // MARK: - Agent Loading

    /// Extract agentId from a Task tool_result text.
    /// Pattern: "agentId: XXXXXXX" near the end of the output.
    static func extractAgentId(from output: String) -> String? {
        guard let range = output.range(of: #"agentId:\s*(\S+)"#, options: .regularExpression) else {
            return nil
        }
        let match = output[range]
        let parts = match.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }

    /// Load and parse all agent JSONL files in a directory that share a sessionId.
    /// Returns a map of agentId → [SessionTurn].
    static func loadAgentTurns(sessionDir: URL, sessionId: String) -> [String: [SessionTurn]] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: sessionDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        let agentFiles = contents.filter {
            $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("agent-")
        }

        var result: [String: [SessionTurn]] = [:]
        for file in agentFiles {
            // Extract agentId from filename: "agent-XXXXXXX.jsonl"
            let name = file.deletingPathExtension().lastPathComponent
            let agentId = String(name.dropFirst("agent-".count))

            // Verify this agent belongs to the same session
            let messages = parseFile(at: file)
            guard let first = messages.first, first.sessionId == sessionId else { continue }

            // Skip the "Warmup" user message — show only real content
            let filtered = messages.filter { msg in
                if msg.type == .user {
                    let texts = msg.contentBlocks.compactMap { block -> String? in
                        if case .text(_, let text) = block { return text }
                        return nil
                    }
                    if texts.count == 1, texts.first == "Warmup" { return false }
                }
                return true
            }

            let turns = groupIntoTurns(filtered)
            if !turns.isEmpty {
                result[agentId] = turns
            }
        }

        return result
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

    /// Check if a user message contains real text input (not just tool_result blocks).
    private static func isRealUserMessage(_ message: [String: Any]) -> Bool {
        if let text = message["content"] as? String, !text.isEmpty {
            return true
        }
        if let blocks = message["content"] as? [[String: Any]] {
            return blocks.contains { ($0["type"] as? String) == "text" }
        }
        return false
    }

    /// Extract the last text block from an assistant message's content field.
    private static func extractAssistantText(from message: [String: Any]) -> String {
        guard let blocks = message["content"] as? [[String: Any]] else { return "" }
        // Find the last text block (skip thinking, tool_use)
        var lastText: String?
        for block in blocks {
            if (block["type"] as? String) == "text",
               let text = block["text"] as? String, !text.isEmpty {
                lastText = text
            }
        }
        guard let raw = lastText else { return "" }
        let cleaned = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(cleaned.prefix(200))
    }

    /// Extract human-readable text from a user message's content field.
    /// Handles both string content and array-of-blocks content.
    /// Returns empty string for tool_result-only messages.
    private static func extractUserText(from message: [String: Any]) -> String {
        var raw: String?

        // Case 1: content is a plain string
        if let text = message["content"] as? String {
            raw = text
        }

        // Case 2: content is an array of blocks
        if raw == nil, let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                let blockType = block["type"] as? String ?? ""
                if blockType == "text", let text = block["text"] as? String, !text.isEmpty {
                    raw = text
                    break
                }
            }
        }

        guard let raw else { return "" }

        // Collapse newlines into spaces for compact list display
        let cleaned = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(cleaned.prefix(200))
    }
}
