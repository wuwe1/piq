import AppKit
import Foundation

/// Exports session data to various formats.
///
/// NOTE: This file must be added to the Xcode project's Sources build phase.
/// The core logic is currently inlined in SessionWindowView.swift so it builds
/// without modifying project.pbxproj.
enum SessionExporter {

    /// Convert a root session and its turns into Markdown text.
    static func exportToMarkdown(rootSession: RootSession, turns: [SessionTurn]) -> String {
        var lines: [String] = []

        lines.append("# Session: \(rootSession.projectName)")

        var metaParts: [String] = []
        if !rootSession.gitBranch.isEmpty {
            metaParts.append("**Branch:** \(rootSession.gitBranch)")
        }
        if !rootSession.model.isEmpty {
            metaParts.append("**Model:** \(rootSession.model)")
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        metaParts.append("**Date:** \(dateFormatter.string(from: rootSession.createdAt))")
        lines.append(metaParts.joined(separator: " | "))
        lines.append("")
        lines.append("---")

        for (index, turn) in turns.enumerated() {
            lines.append("")
            lines.append("## Turn \(index + 1)")

            // User message
            if let userMsg = turn.userMessage {
                lines.append("")
                lines.append("### User")
                let userText = extractText(from: userMsg.contentBlocks)
                lines.append(userText.isEmpty ? "(no text)" : userText)
            }

            // Assistant messages
            let assistantText = turn.assistantMessages.flatMap { extractText(from: $0.contentBlocks).components(separatedBy: "\n") }
                .joined(separator: "\n")
            if !assistantText.isEmpty {
                lines.append("")
                lines.append("### Assistant")
                lines.append(assistantText)
            }

            // Tool usage summary
            if !turn.toolPairs.isEmpty {
                let toolNames = turn.toolPairs.map(\.name)
                let unique = Array(Set(toolNames)).sorted()
                lines.append("")
                lines.append("**Tools used:** \(unique.joined(separator: ", "))")
            }

            lines.append("")
            lines.append("---")
        }

        return lines.joined(separator: "\n")
    }

    /// Present an NSSavePanel and write the markdown content to the chosen location.
    @MainActor
    static func saveWithPanel(markdown: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    // MARK: - Helpers

    private static func extractText(from blocks: [SessionContentBlock]) -> String {
        blocks.compactMap { block in
            switch block {
            case .text(_, let text):
                return text
            case .thinking(_, let text):
                return text.isEmpty ? nil : "<thinking>\(text)</thinking>"
            case .toolUse, .toolResult:
                return nil
            }
        }.joined(separator: "\n")
    }
}
