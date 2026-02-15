import SwiftUI

/// Standalone session list view (used if sidebar needs to be separated).
/// Currently the list is inline in SessionWindowView's sidebar.
struct SessionListView: View {
    let sessions: [SessionEntry]
    @Binding var selectedId: String?

    var body: some View {
        List(sessions, selection: $selectedId) { session in
            SessionRowView(entry: session)
                .tag(session.id)
        }
        .listStyle(.sidebar)
    }
}
