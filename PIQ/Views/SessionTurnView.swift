import SwiftUI

/// Displays a single conversation turn: user message + assistant response + tool calls.
struct SessionTurnView: View {
    let turn: SessionTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // User message bubble
            if let userMsg = turn.userMessage {
                userBubble(userMsg)
            }

            // Assistant content blocks
            ForEach(turn.assistantMessages) { msg in
                ForEach(msg.contentBlocks) { block in
                    SessionContentBlockView(block: block)
                }
            }

            // Tool calls
            if !turn.toolPairs.isEmpty {
                ForEach(turn.toolPairs) { pair in
                    SessionToolCallView(pair: pair)
                }
            }

            // Turn footer
            turnFooter
        }
        .padding(.bottom, 8)
    }

    // MARK: - User Bubble

    private func userBubble(_ message: SessionMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(message.contentBlocks) { block in
                    if case .text(_, let text) = block {
                        Text(text)
                            .font(.body)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var turnFooter: some View {
        HStack(spacing: 12) {
            if let duration = turn.durationMs {
                Label(formatDuration(duration), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let usage = turn.totalUsage {
                HStack(spacing: 6) {
                    Text("\(formatTokens(usage.inputTokens)) in")
                        .foregroundStyle(.blue.opacity(0.7))
                    Text("\(formatTokens(usage.outputTokens)) out")
                        .foregroundStyle(.green.opacity(0.7))
                    if usage.cacheReadTokens > 0 {
                        Text("\(formatTokens(usage.cacheReadTokens)) cached")
                            .foregroundStyle(.orange.opacity(0.7))
                    }
                }
                .font(.caption2)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    private func formatDuration(_ ms: Double) -> String {
        let seconds = ms / 1000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)m \(secs)s"
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
