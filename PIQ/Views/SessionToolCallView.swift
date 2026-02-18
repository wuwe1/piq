import SwiftUI

/// Displays a tool call with its input and output.
/// Clicking the header row toggles expand/collapse of the combined content.
struct SessionToolCallView: View {
    let pair: ToolCallPair

    @Environment(ExpandState.self) private var expandState
    @State private var showAgent = false

    private var isExpanded: Bool { expandState.isExpanded(pair.id) }

    private var toolInfo: (color: Color, icon: String) {
        let name = pair.name.lowercased()
        switch name {
        case "read", "glob", "grep":
            return (.blue, name == "read" ? "doc.text" : "magnifyingglass")
        case "write", "edit", "notebookedit":
            return (.orange, "pencil")
        case "bash":
            return (.green, "terminal")
        case "websearch", "webfetch":
            return (.purple, "globe")
        case "task":
            return (.cyan, "person.2")
        case "todowrite", "todoread":
            return (.indigo, "checklist")
        default:
            return (.gray, "wrench")
        }
    }

    // MARK: - Caches

    /// Parsed JSON input for structured display (cached).
    nonisolated(unsafe) static let jsonCache = NSCache<NSString, JsonBox>()
    final class JsonBox { let json: [String: Any]?; init(_ j: [String: Any]?) { json = j } }

    /// Diff result cache (used by DiffEngine).
    nonisolated(unsafe) static let diffCache = NSCache<NSNumber, DiffResultBox>()

    var parsedInput: [String: Any]? {
        let key = pair.inputJSON as NSString
        if let cached = Self.jsonCache.object(forKey: key) { return cached.json }
        let json = pair.inputJSON.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        Self.jsonCache.setObject(JsonBox(json), forKey: key)
        return json
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                toolHeader

                if isExpanded {
                    Divider().padding(.horizontal, 10)
                    expandedContent
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) { expandState.toggle(pair.id) }
            }

            // Agent conversation (outside tap area)
            if let agentTurns = pair.agentTurns, !agentTurns.isEmpty {
                agentSection(agentTurns)
            }
        }
        .background(toolInfo.color.opacity(0.04))
        .overlay(
            Rectangle()
                .strokeBorder(toolInfo.color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Tool Header

    private var toolHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 10)

            Image(systemName: toolInfo.icon)
                .font(.caption)
                .foregroundStyle(toolInfo.color)
                .frame(width: 16)

            Text(pair.name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(toolInfo.color)

            if let serverName = pair.serverName {
                Text("(\(serverName))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Inline summary
            Text(headerSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if pair.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Spacer()

            if pair.agentTurns != nil {
                togglePill("Agent", icon: "person.2", isOn: showAgent, tint: .cyan) {
                    withAnimation(.easeInOut(duration: 0.15)) { showAgent.toggle() }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Header Summary

    private var headerSummary: String {
        guard let input = parsedInput else { return "" }
        switch pair.name {
        case "Edit":
            return (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
        case "Read":
            return (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
        case "Write":
            return (input["file_path"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
        case "Bash":
            let cmd = input["command"] as? String ?? ""
            return String(cmd.prefix(80))
        case "Glob":
            return input["pattern"] as? String ?? ""
        case "Grep":
            return input["pattern"] as? String ?? ""
        case "WebSearch":
            return input["query"] as? String ?? ""
        case "WebFetch":
            return input["url"] as? String ?? ""
        case "Task":
            return input["description"] as? String ?? ""
        default:
            return ""
        }
    }

    // MARK: - Expanded Content (routes to ToolContentViews)

    @ViewBuilder
    private var expandedContent: some View {
        if let input = parsedInput {
            switch pair.name {
            case "Edit":  editExpandedView(input)
            case "Write": writeExpandedView(input)
            case "Bash":  bashExpandedView(input)
            case "Read":  readExpandedView(input)
            case "Grep":      grepExpandedView(input)
            case "Glob":      globExpandedView(input)
            case "WebSearch": webSearchExpandedView(input)
            case "WebFetch":  webFetchExpandedView(input)
            case "Task":      taskExpandedView(input)
            default:          genericExpandedView
            }
        } else {
            genericExpandedView
        }
    }

    private var genericExpandedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            rawInputView
            if let output = pair.output {
                Divider().padding(.horizontal, 10)
                outputSection(output)
            }
        }
    }

    // MARK: - Shared: File Path Header

    func filePathHeader(_ path: String) -> some View {
        Text(path)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
    }

    // MARK: - Syntax Highlighting

    static let keywordsByExt: [String: (keywords: Set<String>, commentPrefix: String)] = {
        let swift: Set<String> = ["import", "func", "var", "let", "class", "struct", "enum", "protocol",
                                   "return", "if", "else", "guard", "switch", "case", "for", "while",
                                   "private", "public", "internal", "static", "self", "Self", "nil",
                                   "true", "false", "async", "await", "throws", "try", "catch",
                                   "override", "init", "deinit", "extension", "where", "in", "some",
                                   "mutating", "typealias", "associatedtype", "weak", "lazy", "final",
                                   "@Observable", "@State", "@Binding", "@Environment", "@MainActor",
                                   "@ViewBuilder", "@Published", "@available", "@escaping", "@Sendable"]
        let py: Set<String> = ["import", "from", "def", "class", "return", "if", "elif", "else",
                                "for", "while", "with", "as", "try", "except", "finally", "raise",
                                "yield", "lambda", "pass", "break", "continue", "and", "or", "not",
                                "in", "is", "None", "True", "False", "self", "async", "await",
                                "global", "nonlocal", "assert", "del"]
        let js: Set<String> = ["import", "export", "from", "function", "const", "let", "var",
                                "return", "if", "else", "for", "while", "switch", "case", "break",
                                "class", "extends", "new", "this", "super", "async", "await",
                                "try", "catch", "finally", "throw", "typeof", "instanceof",
                                "true", "false", "null", "undefined", "default", "yield", "of"]
        return [
            "swift": (swift, "//"), "py": (py, "#"), "js": (js, "//"),
            "ts": (js, "//"), "tsx": (js, "//"), "jsx": (js, "//"),
            "json": ([], ""), "md": ([], ""), "yaml": ([], "#"), "yml": ([], "#"),
            "sh": (py, "#"), "zsh": (py, "#"), "bash": (py, "#"),
            "rb": (py, "#"), "rs": (swift, "//"), "go": (swift, "//"),
        ]
    }()

    static func syntaxHighlight(_ text: String, ext: String) -> AttributedString {
        guard !ext.isEmpty, let lang = keywordsByExt[ext.lowercased()] else {
            var result = AttributedString(text)
            result.foregroundColor = .primary.opacity(0.85)
            return result
        }

        var result = AttributedString()
        let lines = text.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            if i > 0 { result.append(AttributedString("\n")) }

            // Check for comment lines
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !lang.commentPrefix.isEmpty && trimmed.hasPrefix(lang.commentPrefix) {
                var seg = AttributedString(line)
                seg.foregroundColor = .gray
                result.append(seg)
                continue
            }

            // Check for string lines (starts with quote after trimming)
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("'") || trimmed.hasPrefix("`") {
                var seg = AttributedString(line)
                seg.foregroundColor = .orange.opacity(0.85)
                result.append(seg)
                continue
            }

            // Token-based keyword highlighting
            let scanner = Scanner(string: line)
            scanner.charactersToBeSkipped = nil

            while !scanner.isAtEnd {
                // Skip non-word characters
                if let nonWord = scanner.scanUpToCharacters(from: .alphanumerics.union(CharacterSet(charactersIn: "@_"))) {
                    var seg = AttributedString(nonWord)
                    seg.foregroundColor = .primary.opacity(0.85)
                    result.append(seg)
                }

                // Scan a word
                if let word = scanner.scanCharacters(from: .alphanumerics.union(CharacterSet(charactersIn: "@_"))) {
                    var seg = AttributedString(word)
                    if lang.keywords.contains(word) {
                        seg.foregroundColor = .pink.opacity(0.9)
                        seg.inlinePresentationIntent = .stronglyEmphasized
                    } else if word.first?.isUppercase == true {
                        seg.foregroundColor = .cyan.opacity(0.85)
                    } else if Int(word) != nil {
                        seg.foregroundColor = .orange.opacity(0.85)
                    } else {
                        seg.foregroundColor = .primary.opacity(0.85)
                    }
                    result.append(seg)
                }
            }
        }

        return result
    }

    // MARK: - Raw Input

    private var rawInputView: some View {
        ScrollView {
            Text(pair.inputJSON)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 150)
    }

    // MARK: - Output Section

    private func outputSection(_ output: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text(output.prefix(5000))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(pair.isError ? .red : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if output.count > 5000 {
                    Text("... truncated (\(output.count) chars)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 200)
    }

    // MARK: - Agent Section

    private func agentSection(_ turns: [SessionTurn]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showAgent {
                Divider().padding(.horizontal, 10)

                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.cyan.opacity(0.3))
                        .frame(width: 2)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(turns) { turn in
                            SessionTurnView(turn: turn)
                        }
                    }
                    .padding(10)
                }
                .background(.cyan.opacity(0.03))
            }
        }
    }

    // MARK: - Toggle Pill

    private func togglePill(
        _ label: String,
        icon: String,
        isOn: Bool,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let color = tint ?? toolInfo.color
        return Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(isOn ? .white : color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(isOn ? color.opacity(0.8) : color.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DiffResultBox

/// Box type for caching diff results in NSCache.
final class DiffResultBox {
    let lines: [DiffDisplayLine]
    init(_ l: [DiffDisplayLine]) { lines = l }
}
