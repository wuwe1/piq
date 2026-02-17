import SwiftUI

/// Lightweight Markdown renderer for Claude assistant output.
/// Handles code blocks, tables, headers, lists, and inline formatting with styled highlights.
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let md):
                    inlineMarkdown(md)
                case .codeBlock(let lang, let code):
                    codeBlockView(language: lang, code: code)
                case .table(let table):
                    tableView(table)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Segment Parsing

    private enum Segment {
        case text(String)
        case codeBlock(language: String?, code: String)
        case table(ParsedTable)
    }

    private struct ParsedTable {
        let headers: [String]
        let alignments: [Alignment]
        let rows: [[String]]

        enum Alignment { case leading, center, trailing }
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var current = ""
        var inCode = false
        var codeLang: String?
        var codeLines: [String] = []
        var tableLines: [String] = []

        let lines = text.components(separatedBy: "\n")

        func flushText() {
            if !current.isEmpty {
                result.append(.text(current))
                current = ""
            }
        }

        func flushTable() {
            guard tableLines.count >= 2 else {
                // Not a real table, put back as text
                for tl in tableLines {
                    if !current.isEmpty { current += "\n" }
                    current += tl
                }
                tableLines = []
                return
            }
            if let table = parseTable(tableLines) {
                flushText()
                result.append(.table(table))
            } else {
                for tl in tableLines {
                    if !current.isEmpty { current += "\n" }
                    current += tl
                }
            }
            tableLines = []
        }

        for line in lines {
            if !inCode && line.hasPrefix("```") {
                flushTable()
                flushText()
                inCode = true
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLang = lang.isEmpty ? nil : lang
                codeLines = []
            } else if inCode && line.hasPrefix("```") {
                result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
                inCode = false
                codeLang = nil
                codeLines = []
            } else if inCode {
                codeLines.append(line)
            } else if isTableLine(line) {
                if tableLines.isEmpty { flushText() }
                tableLines.append(line)
            } else {
                if !tableLines.isEmpty { flushTable() }
                if !current.isEmpty { current += "\n" }
                current += line
            }
        }

        if inCode {
            result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
        } else {
            if !tableLines.isEmpty { flushTable() }
            flushText()
        }

        return result
    }

    private func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1
    }

    private func parseTable(_ lines: [String]) -> ParsedTable? {
        guard lines.count >= 2 else { return nil }

        func splitRow(_ line: String) -> [String] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let inner = trimmed.dropFirst().dropLast() // strip leading/trailing |
            return inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        let headerCells = splitRow(lines[0])

        // Find separator line (contains only -, :, |, spaces)
        var separatorIdx: Int?
        for i in 1..<min(lines.count, 3) {
            let stripped = lines[i].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "|", with: "")
                .replacingOccurrences(of: "-", with: "")
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: " ", with: "")
            if stripped.isEmpty {
                separatorIdx = i
                break
            }
        }

        guard let sepIdx = separatorIdx else { return nil }

        // Parse alignments from separator
        let sepCells = splitRow(lines[sepIdx])
        let alignments: [ParsedTable.Alignment] = sepCells.map { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            let left = t.hasPrefix(":")
            let right = t.hasSuffix(":")
            if left && right { return .center }
            if right { return .trailing }
            return .leading
        }

        // Parse data rows
        var rows: [[String]] = []
        for i in (sepIdx + 1)..<lines.count {
            rows.append(splitRow(lines[i]))
        }

        return ParsedTable(headers: headerCells, alignments: alignments, rows: rows)
    }

    // MARK: - Table View

    private func tableView(_ table: ParsedTable) -> some View {
        let colCount = table.headers.count
        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                // Header
                GridRow {
                    ForEach(0..<colCount, id: \.self) { col in
                        tableCell(table.headers[col], bold: true, alignment: tableAlignment(col, table))
                    }
                }

                Divider().gridCellUnsizedAxes(.horizontal)

                // Body
                ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIdx, row in
                    GridRow {
                        ForEach(0..<colCount, id: \.self) { col in
                            let cell: String = col < row.count ? row[col] : ""
                            tableCell(cell, bold: false, alignment: tableAlignment(col, table))
                        }
                    }
                    .background(rowIdx.isMultiple(of: 2) ? AnyShapeStyle(.clear) : AnyShapeStyle(.quaternary.opacity(0.2)))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .background(.quaternary.opacity(0.15))
            .overlay(Rectangle().strokeBorder(.quaternary, lineWidth: 0.5))
        }
        .textSelection(.enabled)
    }

    private func tableCell(_ content: String, bold: Bool, alignment: SwiftUI.Alignment) -> some View {
        Text(styledInline(content, baseFont: .caption))
            .fontWeight(bold ? .semibold : .regular)
            .lineLimit(nil)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func tableAlignment(_ col: Int, _ table: ParsedTable) -> SwiftUI.Alignment {
        guard col < table.alignments.count else { return .leading }
        switch table.alignments[col] {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    // MARK: - Inline Markdown

    private func inlineMarkdown(_ md: String) -> some View {
        Text(buildAttributedMarkdown(md))
            .textSelection(.enabled)
    }

    private func buildAttributedMarkdown(_ md: String) -> AttributedString {
        var result = AttributedString()
        let lines = md.components(separatedBy: "\n")

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                result.append(AttributedString("\n\n"))
                continue
            }

            if i > 0 && !trimmed.isEmpty {
                let prevTrimmed = lines[i - 1].trimmingCharacters(in: .whitespaces)
                if !prevTrimmed.isEmpty {
                    result.append(AttributedString("\n"))
                }
            }

            if trimmed.hasPrefix("### ") {
                var seg = styledInline(String(trimmed.dropFirst(4)), baseFont: .subheadline)
                seg.inlinePresentationIntent = .stronglyEmphasized
                result.append(seg)
            } else if trimmed.hasPrefix("## ") {
                var seg = styledInline(String(trimmed.dropFirst(3)), baseFont: .headline)
                seg.inlinePresentationIntent = .stronglyEmphasized
                result.append(seg)
            } else if trimmed.hasPrefix("# ") {
                var seg = styledInline(String(trimmed.dropFirst(2)), baseFont: .title3)
                seg.inlinePresentationIntent = .stronglyEmphasized
                result.append(seg)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var bullet = AttributedString("  \u{2022} ")
                bullet.foregroundColor = .secondary
                result.append(bullet)
                result.append(styledInline(String(trimmed.dropFirst(2))))
            } else if let match = trimmed.wholeMatch(of: /^(\d+)\.\s+(.+)$/) {
                var num = AttributedString("  \(match.1). ")
                num.foregroundColor = .secondary
                result.append(num)
                result.append(styledInline(String(match.2)))
            } else {
                result.append(styledInline(trimmed))
            }
        }
        return result
    }

    // MARK: - Styled Inline Attributed String

    private func styledInline(_ text: String, baseFont: Font = .body) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var attr = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }

        attr.font = baseFont

        for run in attr.runs {
            guard let intent = run.inlinePresentationIntent else { continue }
            let range = run.range

            if intent.contains(.code) {
                attr[range].font = .system(.callout, design: .monospaced).weight(.medium)
                attr[range].foregroundColor = .orange
                attr[range].backgroundColor = .orange.opacity(0.1)
            }

            if intent.contains(.stronglyEmphasized) {
                attr[range].foregroundColor = .primary
            }
        }

        return attr
    }

    // MARK: - Code Block

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let lang = language, !lang.isEmpty {
                HStack {
                    Text(lang)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        )
    }
}
