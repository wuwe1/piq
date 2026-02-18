import SwiftUI

/// Standalone session list view (used if sidebar needs to be separated).
/// Currently the list is inline in SessionWindowView's sidebar.
struct SessionListView: View {
    let rootSessions: [RootSession]
    @Binding var selectedId: String?

    var body: some View {
        List(rootSessions, selection: $selectedId) { rs in
            SessionRowView(rootSession: rs)
                .tag(rs.id)
        }
        .listStyle(.sidebar)
    }
}
