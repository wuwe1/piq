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

    /// Parsed JSON input for structured display.
    private var parsedInput: [String: Any]? {
        guard let data = pair.inputJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
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

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        if let input = parsedInput {
            switch pair.name {
            case "Edit":  editExpandedView(input)
            case "Write": writeExpandedView(input)
            case "Bash":  bashExpandedView(input)
            case "Read":  readExpandedView(input)
            case "Grep":  grepExpandedView(input)
            case "Glob":  globExpandedView(input)
            default:      genericExpandedView
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

    private func filePathHeader(_ path: String) -> some View {
        Text(path)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))
    }

    // MARK: - Edit Tool

    private func editExpandedView(_ input: [String: Any]) -> some View {
        editDiffView(input)
    }

    private func editDiffView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""
        let oldStr = input["old_string"] as? String ?? ""
        let newStr = input["new_string"] as? String ?? ""
        let lines = Self.computeLineDiff(old: oldStr, new: newStr)

        return VStack(alignment: .leading, spacing: 0) {
            if !filePath.isEmpty { filePathHeader(filePath) }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    diffLineRow(line)
                }
            }
            .textSelection(.enabled)
        }
    }

    // MARK: - Write Tool

    private func writeExpandedView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""
        let content = input["content"] as? String ?? ""

        return VStack(alignment: .leading, spacing: 0) {
            if !filePath.isEmpty { filePathHeader(filePath) }

            Text(content.prefix(8000))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }

    // MARK: - Bash Tool

    private func bashExpandedView(_ input: [String: Any]) -> some View {
        let command = input["command"] as? String ?? ""
        let description = input["description"] as? String

        return VStack(alignment: .leading, spacing: 0) {
            // Description
            if let desc = description, !desc.isEmpty {
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }

            // Command prompt
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    Text("$")
                        .foregroundStyle(.green.opacity(0.7))
                    Text(command)
                        .foregroundStyle(.primary.opacity(0.9))
                        .textSelection(.enabled)
                }
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .background(.black.opacity(0.15))

            // Output
            if let output = pair.output, !output.isEmpty {
                bashOutputView(output)
            }
        }
    }

    private func bashOutputView(_ output: String) -> some View {
        Text(output.prefix(8000))
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(pair.isError ? .red : .secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }

    // MARK: - Read Tool

    private func readExpandedView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""

        return VStack(alignment: .leading, spacing: 0) {
            if !filePath.isEmpty { filePathHeader(filePath) }

            if let output = pair.output {
                readOutputView(output)
            }
        }
    }

    private func readOutputView(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(output.components(separatedBy: "\n").enumerated()), id: \.offset) { _, rawLine in
                readLineRow(rawLine)
            }
        }
        .textSelection(.enabled)
    }

    private func readLineRow(_ rawLine: String) -> some View {
        let parsed = Self.parseReadLine(rawLine)
        return HStack(alignment: .top, spacing: 0) {
            Text(parsed.lineNum)
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)
            Text(parsed.content)
                .foregroundStyle(.primary.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 0.5)
    }

    private static func parseReadLine(_ line: String) -> (lineNum: String, content: String) {
        // Format: "     1→content"
        guard let idx = line.firstIndex(of: "\u{2192}") else { // → character
            return ("", line)
        }
        let num = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
        let content = String(line[line.index(after: idx)...])
        return (num, content)
    }

    // MARK: - Grep Tool

    private func grepExpandedView(_ input: [String: Any]) -> some View {
        let pattern = input["pattern"] as? String ?? ""
        let path = input["path"] as? String
        let mode = input["output_mode"] as? String ?? "files_with_matches"

        return VStack(alignment: .leading, spacing: 0) {
            // Pattern info
            HStack(spacing: 6) {
                Text("/\(pattern)/")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.blue)
                if let p = path {
                    Text("in")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text((p as NSString).lastPathComponent)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(mode.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))

            // Results
            if let output = pair.output, !output.isEmpty {
                searchResultsView(output)
            }
        }
    }

    // MARK: - Glob Tool

    private func globExpandedView(_ input: [String: Any]) -> some View {
        let pattern = input["pattern"] as? String ?? ""

        return VStack(alignment: .leading, spacing: 0) {
            // Pattern info
            Text(pattern)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3))

            // Results
            if let output = pair.output, !output.isEmpty {
                searchResultsView(output)
            }
        }
    }

    /// Shared view for file list / search results output.
    private func searchResultsView(_ output: String) -> some View {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.prefix(500).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if lines.count > 500 {
                Text("… \(lines.count - 500) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
        .textSelection(.enabled)
    }

    private func diffLineRow(_ line: DiffDisplayLine) -> some View {
        let prefixColor: Color = switch line.type {
        case .context: .secondary.opacity(0.3)
        case .removed: .red.opacity(0.6)
        case .added: .green.opacity(0.6)
        }
        let bgColor: Color = switch line.type {
        case .context: .clear
        case .removed: .red.opacity(0.08)
        case .added: .green.opacity(0.08)
        }

        return HStack(spacing: 0) {
            Text(line.prefix)
                .frame(width: 16)
                .foregroundStyle(prefixColor)
            Text(line.styledText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .background(bgColor)
    }

    // MARK: - Diff Types & Computation

    private enum DiffLineType { case context, removed, added }

    private struct DiffDisplayLine {
        let prefix: String
        let type: DiffLineType
        let styledText: AttributedString
    }

    private enum LineDiffOp {
        case equal(String)
        case remove(String)
        case insert(String)
    }

    /// LCS-based line diff with character-level highlights for modified pairs.
    private static func computeLineDiff(old: String, new: String) -> [DiffDisplayLine] {
        let oldLines = old.components(separatedBy: "\n")
        let newLines = new.components(separatedBy: "\n")
        let ops = lcsLineDiff(oldLines, newLines)

        var result: [DiffDisplayLine] = []
        var i = 0
        while i < ops.count {
            switch ops[i] {
            case .equal(let text):
                result.append(DiffDisplayLine(
                    prefix: " ", type: .context,
                    styledText: AttributedString(text)
                ))
                i += 1
            default:
                // Gather consecutive removes/inserts as a hunk
                var removes: [String] = []
                var inserts: [String] = []
                while i < ops.count {
                    if case .remove(let t) = ops[i] { removes.append(t); i += 1 }
                    else if case .insert(let t) = ops[i] { inserts.append(t); i += 1 }
                    else { break }
                }
                // Pair up for character-level diff, interleave remove/add
                let pairs = min(removes.count, inserts.count)
                for p in 0..<pairs {
                    let (oldHL, newHL) = charHighlights(old: removes[p], new: inserts[p])
                    result.append(DiffDisplayLine(
                        prefix: "−", type: .removed,
                        styledText: styledDiffText(removes[p], highlights: oldHL, color: .red)
                    ))
                    result.append(DiffDisplayLine(
                        prefix: "+", type: .added,
                        styledText: styledDiffText(inserts[p], highlights: newHL, color: .green)
                    ))
                }
                for p in pairs..<removes.count {
                    result.append(DiffDisplayLine(
                        prefix: "−", type: .removed,
                        styledText: AttributedString(removes[p])
                    ))
                }
                for p in pairs..<inserts.count {
                    result.append(DiffDisplayLine(
                        prefix: "+", type: .added,
                        styledText: AttributedString(inserts[p])
                    ))
                }
            }
        }
        return result
    }

    /// LCS-based diff producing edit operations.
    private static func lcsLineDiff(_ old: [String], _ new: [String]) -> [LineDiffOp] {
        let m = old.count, n = new.count
        if m == 0 { return new.map { .insert($0) } }
        if n == 0 { return old.map { .remove($0) } }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if old[i - 1] == new[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var ops: [LineDiffOp] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && old[i - 1] == new[j - 1] {
                ops.append(.equal(old[i - 1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                ops.append(.insert(new[j - 1]))
                j -= 1
            } else {
                ops.append(.remove(old[i - 1]))
                i -= 1
            }
        }
        return ops.reversed()
    }

    /// Character-level LCS to find which chars changed between two lines.
    private static func charHighlights(old: String, new: String) -> (IndexSet, IndexSet) {
        let oldChars = Array(old)
        let newChars = Array(new)
        let m = oldChars.count, n = newChars.count

        // Skip for very long lines
        if m > 500 || n > 500 { return (IndexSet(), IndexSet()) }
        if m == 0 { return (IndexSet(), n > 0 ? IndexSet(integersIn: 0..<n) : IndexSet()) }
        if n == 0 { return (m > 0 ? IndexSet(integersIn: 0..<m) : IndexSet(), IndexSet()) }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if oldChars[i - 1] == newChars[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find common characters
        var commonOld = Set<Int>()
        var commonNew = Set<Int>()
        var i = m, j = n
        while i > 0 && j > 0 {
            if oldChars[i - 1] == newChars[j - 1] {
                commonOld.insert(i - 1)
                commonNew.insert(j - 1)
                i -= 1; j -= 1
            } else if dp[i][j - 1] >= dp[i - 1][j] {
                j -= 1
            } else {
                i -= 1
            }
        }

        // Highlights = characters NOT in common
        var oldHL = IndexSet()
        for idx in 0..<m where !commonOld.contains(idx) { oldHL.insert(idx) }
        var newHL = IndexSet()
        for idx in 0..<n where !commonNew.contains(idx) { newHL.insert(idx) }
        return (oldHL, newHL)
    }

    /// Build AttributedString with highlighted character ranges.
    private static func styledDiffText(_ text: String, highlights: IndexSet, color: Color) -> AttributedString {
        if highlights.isEmpty { return AttributedString(text) }

        var result = AttributedString()
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let isHL = highlights.contains(i)
            var j = i + 1
            while j < chars.count && highlights.contains(j) == isHL { j += 1 }

            var segment = AttributedString(String(chars[i..<j]))
            if isHL {
                segment.backgroundColor = color.opacity(0.25)
            }
            result.append(segment)
            i = j
        }
        return result
    }

    // MARK: - Raw Input

    private var rawInputView: some View {
        Text(pair.inputJSON)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }

    // MARK: - Output Section

    private func outputSection(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(output.prefix(5000))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(pair.isError ? .red : .secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if output.count > 5000 {
                Text("… truncated (\(output.count) chars)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
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
