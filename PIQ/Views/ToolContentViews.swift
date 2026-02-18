import SwiftUI

// MARK: - Tool-Specific Content Views

extension SessionToolCallView {

    // MARK: - Edit Tool

    func editExpandedView(_ input: [String: Any]) -> some View {
        editDiffView(input)
    }

    func editDiffView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""
        let oldStr = input["old_string"] as? String ?? ""
        let newStr = input["new_string"] as? String ?? ""
        let lines = DiffEngine.cachedLineDiff(old: oldStr, new: newStr)

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

    func writeExpandedView(_ input: [String: Any]) -> some View {
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

    func bashExpandedView(_ input: [String: Any]) -> some View {
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

    func bashOutputView(_ output: String) -> some View {
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

    func readExpandedView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""
        let ext = (filePath as NSString).pathExtension

        return VStack(alignment: .leading, spacing: 0) {
            if !filePath.isEmpty { filePathHeader(filePath) }

            if let output = pair.output {
                readOutputView(output, ext: ext)
            }
        }
    }

    func readOutputView(_ output: String, ext: String = "") -> some View {
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

    func readLineRow(_ rawLine: String, ext: String = "") -> some View {
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

    static func parseReadLine(_ line: String) -> (lineNum: String, content: String) {
        // Format: "     1→content"
        guard let idx = line.firstIndex(of: "\u{2192}") else { // → character
            return ("", line)
        }
        let num = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
        let content = String(line[line.index(after: idx)...])
        return (num, content)
    }

    // MARK: - Grep Tool

    func grepExpandedView(_ input: [String: Any]) -> some View {
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

    func globExpandedView(_ input: [String: Any]) -> some View {
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

    struct SearchResult: Identifiable {
        let id = UUID()
        let title: String
        let url: String
    }

    static func parseSearchResults(_ output: String) -> [SearchResult] {
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

    func webSearchExpandedView(_ input: [String: Any]) -> some View {
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

    func webFetchExpandedView(_ input: [String: Any]) -> some View {
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

    func taskExpandedView(_ input: [String: Any]) -> some View {
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

    // MARK: - Shared: Search Results

    /// Shared view for file list / search results output.
    func searchResultsView(_ output: String, highlightPattern: String? = nil) -> some View {
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
                    Text("... \(lines.count - 500) more")
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
    static func highlightMatches(in text: String, regex: NSRegularExpression) -> AttributedString {
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

    // MARK: - Diff Line Row

    func diffLineRow(_ line: DiffDisplayLine) -> some View {
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
}
