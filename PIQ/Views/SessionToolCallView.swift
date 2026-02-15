import SwiftUI

/// Displays a tool call with its input and output.
struct SessionToolCallView: View {
    let pair: ToolCallPair
    @State private var showInput = false
    @State private var showOutput = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tool header
            toolHeader

            // Input section
            if showInput {
                inputSection
            }

            // Output section
            if showOutput, let output = pair.output {
                outputSection(output)
            }

            // Agent conversation (for Task tool calls)
            if let agentTurns = pair.agentTurns, !agentTurns.isEmpty {
                agentSection(agentTurns)
            }
        }
        .background(toolInfo.color.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(toolInfo.color.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Tool Header

    private var toolHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: toolInfo.icon)
                .font(.caption)
                .foregroundStyle(toolInfo.color)
                .frame(width: 16)

            Text(displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(toolInfo.color)

            if let serverName = pair.serverName {
                Text("(\(serverName))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if pair.isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Spacer()

            HStack(spacing: 4) {
                togglePill("Input", icon: "arrow.right.circle", isOn: showInput) {
                    withAnimation(.easeInOut(duration: 0.15)) { showInput.toggle() }
                }

                if pair.output != nil {
                    togglePill("Output", icon: "arrow.left.circle", isOn: showOutput) {
                        withAnimation(.easeInOut(duration: 0.15)) { showOutput.toggle() }
                    }
                }

                if pair.agentTurns != nil {
                    togglePill("Agent", icon: "person.2", isOn: showAgent, tint: .cyan) {
                        withAnimation(.easeInOut(duration: 0.15)) { showAgent.toggle() }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.horizontal, 10)
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
    }

    // MARK: - Output Section

    private func outputSection(_ output: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.horizontal, 10)
            ScrollView {
                Text(output.prefix(5000))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(pair.isError ? .red : .secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Agent Section

    private func agentSection(_ turns: [SessionTurn]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showAgent {
                Divider().padding(.horizontal, 10)

                HStack(spacing: 0) {
                    // Left accent border
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

    // MARK: - Display Name

    private var displayName: String {
        pair.name
    }
}
