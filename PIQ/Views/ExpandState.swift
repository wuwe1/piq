import SwiftUI

/// Holds expand/collapse state for tool calls and thinking blocks.
@MainActor @Observable
final class ExpandState {
    var expandedIds: Set<String> = []

    func isExpanded(_ id: String) -> Bool { expandedIds.contains(id) }

    func toggle(_ id: String) {
        if expandedIds.contains(id) {
            expandedIds.remove(id)
        } else {
            expandedIds.insert(id)
        }
    }

    func expandAll(turns: [SessionTurn]) {
        for turn in turns {
            for pair in turn.toolPairs { expandedIds.insert(pair.id) }
            for msg in turn.assistantMessages {
                for block in msg.contentBlocks {
                    if case .thinking(let id, _) = block { expandedIds.insert(id) }
                }
            }
        }
    }

    func collapseAll() { expandedIds.removeAll() }
}
