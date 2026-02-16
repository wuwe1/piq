import SwiftUI

/// Renders a single content block from an assistant message.
struct SessionContentBlockView: View {
    let block: SessionContentBlock

    var body: some View {
        switch block {
        case .text(_, let text):
            MarkdownTextView(text: text)
        case .thinking(let id, let text):
            ThinkingBlockView(blockId: id, text: text)
        case .toolUse:
            EmptyView()
        case .toolResult:
            EmptyView()
        }
    }
}

/// Thinking block with click-anywhere expand/collapse.
/// Uses ExpandState from environment so state survives view recreation.
private struct ThinkingBlockView: View {
    let blockId: String
    let text: String
    @Environment(ExpandState.self) private var expandState

    private var isExpanded: Bool { expandState.isExpanded(blockId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Label("Thinking", systemImage: "brain")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if isExpanded {
                ScrollView {
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }
                .frame(maxHeight: 200)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { expandState.toggle(blockId) }
        }
        .background(.purple.opacity(0.05))
    }
}
