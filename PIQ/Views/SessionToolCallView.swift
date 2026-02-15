import SwiftUI

/// Displays a tool call with its input and output.
struct SessionToolCallView: View {
    let pair: ToolCallPair
    @State private var showInput = false
    @State private var showOutput = false

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

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showInput.toggle()
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(showInput ? 90 : 0))
                    Text("Input")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if pair.output != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showOutput.toggle()
                    }
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showOutput ? 90 : 0))
                        Text("Output")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
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

    // MARK: - Display Name

    private var displayName: String {
        pair.name
    }
}
