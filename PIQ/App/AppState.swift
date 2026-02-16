import Foundation

@MainActor
@Observable
final class AppState {
    var sessionStore: SessionStore?

    /// Session ID to auto-select when the Sessions window opens.
    var pendingSessionId: String?

    func setupSessionStore() {
        guard sessionStore == nil else { return }
        let store = SessionStore()
        store.rescan()
        store.startWatching()
        sessionStore = store
    }
}
