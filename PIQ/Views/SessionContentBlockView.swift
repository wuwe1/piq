import SwiftUI

/// Renders a single content block from an assistant message.
struct SessionContentBlockView: View {
    let block: SessionContentBlock

    var body: some View {
        switch block {
        case .text(_, let text):
            textBlock(text)
        case .thinking(_, let text):
            thinkingBlock(text)
        case .toolUse:
            EmptyView() // Handled by SessionToolCallView via ToolCallPair
        case .toolResult:
            EmptyView() // Handled by SessionToolCallView via ToolCallPair
        }
    }

    // MARK: - Text Block

    private func textBlock(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Thinking Block

    private func thinkingBlock(_ text: String) -> some View {
        DisclosureGroup {
            ScrollView {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)
        } label: {
            Label("Thinking", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.purple)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}
