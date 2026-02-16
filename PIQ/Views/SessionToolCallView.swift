import SwiftUI

/// Displays a tool call with its input and output.
/// Clicking the header row toggles expand/collapse of the combined content.
struct SessionToolCallView: View {
    let pair: ToolCallPair
    var expandAll: Bool = false

    @State private var isExpanded = false
    @State private var showAgent = false

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
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
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
        .onChange(of: expandAll) { _, newValue in
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded = newValue }
        }
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
        VStack(alignment: .leading, spacing: 0) {
            // Tool-specific input rendering
            if pair.name == "Edit", let input = parsedInput {
                editDiffView(input)
            } else {
                rawInputView
            }

            // Output
            if let output = pair.output {
                Divider().padding(.horizontal, 10)
                outputSection(output)
            }
        }
    }

    // MARK: - Edit Diff View

    private func editDiffView(_ input: [String: Any]) -> some View {
        let filePath = input["file_path"] as? String ?? ""
        let oldStr = input["old_string"] as? String ?? ""
        let newStr = input["new_string"] as? String ?? ""

        return VStack(alignment: .leading, spacing: 0) {
            // File path
            if !filePath.isEmpty {
                Text(filePath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3))
            }

            // Diff
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Removed lines
                    ForEach(Array(oldStr.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 0) {
                            Text("−")
                                .frame(width: 16)
                                .foregroundStyle(.red.opacity(0.6))
                            Text(line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 1)
                        .background(.red.opacity(0.08))
                    }

                    // Added lines
                    ForEach(Array(newStr.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 0) {
                            Text("+")
                                .frame(width: 16)
                                .foregroundStyle(.green.opacity(0.6))
                            Text(line)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 1)
                        .background(.green.opacity(0.08))
                    }
                }
                .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
        }
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
                            SessionTurnView(turn: turn, expandAll: expandAll)
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
