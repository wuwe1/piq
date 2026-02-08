import AppKit
import Foundation

enum ActionService {

    // MARK: - File Operations

    static func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Clipboard

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Browser

    static func openInBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Terminal

    static func openTerminal(at path: URL) {
        let pathString = path.path(percentEncoded: false)
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", pathString]
        try? process.run()
    }

    // MARK: - Claude Code

    static func openClaudeCode(at path: URL) {
        let pathString = path.path(percentEncoded: false)
        let script = "tell application \"Terminal\" to do script \"cd \(pathString) && claude\""
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    // MARK: - Status Summary

    static func projectStatusSummary(_ project: Project) -> String {
        var lines: [String] = []
        lines.append("\(project.name)")
        lines.append("PRDs: \(project.prds.count) | Epics: \(project.epics.count) | Tasks: \(project.tasks.count)")
        for epic in project.epics {
            let done = epic.tasks.filter { $0.status == .done }.count
            lines.append("  \(epic.name): \(done)/\(epic.tasks.count) tasks (\(epic.progressPercent)%)")
        }
        return lines.joined(separator: "\n")
    }
}
