import SwiftUI

/// Column 3: displays one or more turns' full content.
struct SessionTurnDetailView: View {
    let turns: [SessionTurn]
    @State private var expandState = ExpandState()

    private var stableId: String {
        turns.map(\.id).joined(separator: "-")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(turns) { turn in
                    SessionTurnView(turn: turn)
                }
            }
            .padding(16)
        }
        .environment(expandState)
        .id(stableId)
    }
}
