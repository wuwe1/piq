import SwiftUI

/// Lightweight Markdown renderer for Claude assistant output.
/// Handles code blocks, headers, lists, and inline formatting with styled highlights.
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
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Segment Parsing

    private enum Segment {
        case text(String)
        case codeBlock(language: String?, code: String)
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var current = ""
        var inCode = false
        var codeLang: String?
        var codeLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            if !inCode && line.hasPrefix("```") {
                if !current.isEmpty {
                    result.append(.text(current))
                    current = ""
                }
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
            } else {
                if !current.isEmpty { current += "\n" }
                current += line
            }
        }

        if inCode {
            result.append(.codeBlock(language: codeLang, code: codeLines.joined(separator: "\n")))
        } else if !current.isEmpty {
            result.append(.text(current))
        }

        return result
    }

    // MARK: - Inline Markdown

    private func inlineMarkdown(_ md: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(md.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                if line.isEmpty {
                    Spacer().frame(height: 4)
                } else {
                    lineView(line)
                }
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("### ") {
            Text(styledInline(String(trimmed.dropFirst(4)), baseFont: .subheadline))
                .padding(.top, 4)
        } else if trimmed.hasPrefix("## ") {
            Text(styledInline(String(trimmed.dropFirst(3)), baseFont: .headline))
                .padding(.top, 6)
        } else if trimmed.hasPrefix("# ") {
            Text(styledInline(String(trimmed.dropFirst(2)), baseFont: .title3))
                .fontWeight(.bold)
                .padding(.top, 8)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2022}")
                    .foregroundStyle(.secondary)
                Text(styledInline(String(trimmed.dropFirst(2))))
            }
        } else if let match = trimmed.wholeMatch(of: /^(\d+)\.\s+(.+)$/) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(match.1).")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(styledInline(String(match.2)))
            }
        } else {
            Text(styledInline(trimmed))
        }
    }

    // MARK: - Styled Inline Attributed String

    private func styledInline(_ text: String, baseFont: Font = .body) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var attr = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }

        // Apply base font to the whole string
        attr.font = baseFont

        // Style inline code and bold runs
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
