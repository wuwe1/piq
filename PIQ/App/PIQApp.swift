import SwiftUI

@main
struct PIQApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("PIQ", systemImage: "eyes") {
            MenuBarView()
                .environment(appState)
                .frame(width: 360, height: 500)
                .task {
                    appState.setupSessionStore()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Claude Sessions", id: "sessions") {
            SessionWindowView()
                .environment(appState)
        }
        .defaultSize(width: 900, height: 640)
    }
}
