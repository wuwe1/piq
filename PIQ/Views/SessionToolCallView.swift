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

    /// Parsed JSON input for structured display (cached).
    private nonisolated(unsafe) static let jsonCache = NSCache<NSString, JsonBox>()
    private final class JsonBox { let json: [String: Any]?; init(_ j: [String: Any]?) { json = j } }

    private var parsedInput: [String: Any]? {
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

    // MARK: - Expanded Content

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
        let lines = Self.cachedLineDiff(old: oldStr, new: newStr)

        return VStack(alignment: .leading, spacing: 0) {
            if !filePath.isEmpty { filePathHeader(filePath) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        diffLineRow(line)
                    }
                }
                .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
        }
    }

    // MARK: - Write Tool

    private func writeExpandedView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""
        let content = input["content"] as? String ?? ""
        let ext = (filePath as NSString).pathExtension

        return VStack(alignment: .leading, spacing: 0) {
            if !filePath.isEmpty { filePathHeader(filePath) }

            ScrollView {
                Text(Self.syntaxHighlight(String(content.prefix(8000)), ext: ext))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 300)
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
        HStack(spacing: 0) {
            if pair.isError {
                Rectangle()
                    .fill(.red.opacity(0.5))
                    .frame(width: 2)
            }
            ScrollView {
                Text(output.prefix(8000))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(pair.isError ? .red.opacity(0.8) : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 200)
        }
        .background(pair.isError ? .red.opacity(0.04) : .clear)
    }

    // MARK: - Read Tool

    private func readExpandedView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""
        let ext = (filePath as NSString).pathExtension

        return VStack(alignment: .leading, spacing: 0) {
            if !filePath.isEmpty { filePathHeader(filePath) }

            if let output = pair.output {
                readOutputView(output, ext: ext)
            }
        }
    }

    private func readOutputView(_ output: String, ext: String = "") -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(output.components(separatedBy: "\n").enumerated()), id: \.offset) { _, rawLine in
                    readLineRow(rawLine, ext: ext)
                }
            }
            .textSelection(.enabled)
        }
        .frame(maxHeight: 300)
    }

    private func readLineRow(_ rawLine: String, ext: String = "") -> some View {
        let parsed = Self.parseReadLine(rawLine)
        return HStack(alignment: .top, spacing: 0) {
            Text(parsed.lineNum)
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, 6)
            Text(Self.syntaxHighlight(parsed.content, ext: ext))
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
                searchResultsView(output, highlightPattern: pattern)
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

    // MARK: - WebSearch Tool

    private struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let url: String
    }

    private static func parseSearchResults(_ output: String) -> [SearchResult] {
        // Find JSON array in output: Links: [{"title":"...","url":"..."},...]
        guard let linksRange = output.range(of: "Links: "),
              let arrayStart = output[linksRange.upperBound...].firstIndex(of: "[") else { return [] }

        // Find matching closing bracket
        var depth = 0
        var arrayEnd: String.Index?
        for i in output[arrayStart...].indices {
            if output[i] == "[" { depth += 1 }
            else if output[i] == "]" {
                depth -= 1
                if depth == 0 { arrayEnd = output.index(after: i); break }
            }
        }
        guard let end = arrayEnd else { return [] }

        let jsonStr = String(output[arrayStart..<end])
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }
        return arr.compactMap { item in
            guard let title = item["title"], let url = item["url"] else { return nil }
            return SearchResult(title: title, url: url)
        }
    }

    private func webSearchExpandedView(_ input: [String: Any]) -> some View {
        let query = input["query"] as? String ?? ""
        let results = pair.output.map(Self.parseSearchResults) ?? []

        return VStack(alignment: .leading, spacing: 0) {
            // Query
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.purple)
                Text(query)
                    .fontWeight(.medium)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))

            // Results
            if !results.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(results) { result in
                            if let url = URL(string: result.url) {
                                Link(destination: url) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(result.url)
                                            .font(.caption2)
                                            .foregroundStyle(.purple.opacity(0.7))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if result.id != results.last?.id {
                                    Divider().padding(.leading, 10)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            } else if let output = pair.output, !output.isEmpty {
                // Fallback: raw output
                ScrollView {
                    Text(output.prefix(8000))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    // MARK: - WebFetch Tool

    private func webFetchExpandedView(_ input: [String: Any]) -> some View {
        let url = input["url"] as? String ?? ""
        let prompt = input["prompt"] as? String

        return VStack(alignment: .leading, spacing: 0) {
            // URL
            VStack(alignment: .leading, spacing: 3) {
                Text(url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.purple)
                    .textSelection(.enabled)
                    .lineLimit(2)
                if let prompt, !prompt.isEmpty {
                    Text(prompt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))

            // Output
            if let output = pair.output, !output.isEmpty {
                ScrollView {
                    Text(output.prefix(8000))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    // MARK: - Task Tool

    private func taskExpandedView(_ input: [String: Any]) -> some View {
        let description = input["description"] as? String ?? ""
        let agentType = input["subagent_type"] as? String
        let prompt = input["prompt"] as? String

        return VStack(alignment: .leading, spacing: 0) {
            // Task info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let agentType, !agentType.isEmpty {
                        Text(agentType)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.cyan.opacity(0.7), in: Capsule())
                    }
                    Text(description)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                if let prompt, !prompt.isEmpty {
                    Text(prompt.prefix(200))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.3))

            // Output
            if let output = pair.output, !output.isEmpty {
                ScrollView {
                    Text(output.prefix(5000))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 200)
            }
        }
    }

    /// Shared view for file list / search results output.
    private func searchResultsView(_ output: String, highlightPattern: String? = nil) -> some View {
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        let regex = highlightPattern.flatMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.prefix(500).enumerated()), id: \.offset) { _, line in
                    if let regex {
                        Text(Self.highlightMatches(in: line, regex: regex))
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 1.5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
        .frame(maxHeight: 200)
    }

    /// Highlight regex matches in a line with a colored background.
    private static func highlightMatches(in text: String, regex: NSRegularExpression) -> AttributedString {
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = AttributedString(text)
        result.foregroundColor = .secondary

        for match in matches.reversed() {
            guard let range = Range(match.range, in: text) else { continue }
            let attrRange = result.range(of: String(text[range]))
            guard let attrRange else { continue }
            result[attrRange].foregroundColor = .blue
            result[attrRange].backgroundColor = .blue.opacity(0.15)
        }
        return result
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

    private nonisolated(unsafe) static let diffCache = NSCache<NSNumber, DiffResultBox>()
    private final class DiffResultBox { let lines: [DiffDisplayLine]; init(_ l: [DiffDisplayLine]) { lines = l } }

    private static func cachedLineDiff(old: String, new: String) -> [DiffDisplayLine] {
        let key = NSNumber(value: "\(old)\n---\n\(new)".hashValue)
        if let cached = diffCache.object(forKey: key) { return cached.lines }
        let result = computeLineDiff(old: old, new: new)
        diffCache.setObject(DiffResultBox(result), forKey: key)
        return result
    }

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

    // MARK: - Syntax Highlighting

    private static let keywordsByExt: [String: (keywords: Set<String>, commentPrefix: String)] = {
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

    private static func syntaxHighlight(_ text: String, ext: String) -> AttributedString {
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
            var lastIndex = line.startIndex

            while !scanner.isAtEnd {
                // Skip non-word characters
                if let nonWord = scanner.scanUpToCharacters(from: .alphanumerics.union(CharacterSet(charactersIn: "@_"))) {
                    var seg = AttributedString(nonWord)
                    seg.foregroundColor = .primary.opacity(0.85)
                    result.append(seg)
                    lastIndex = line.index(line.startIndex, offsetBy: scanner.currentIndex.utf16Offset(in: line), limitedBy: line.endIndex) ?? line.endIndex
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
                    Text("… truncated (\(output.count) chars)")
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
