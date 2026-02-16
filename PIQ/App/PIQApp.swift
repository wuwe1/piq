import SwiftUI

@main
struct PIQApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("PIQ", id: "main") {
            SessionWindowView()
                .environment(appState)
                .task {
                    appState.setupSessionStore()
                }
        }
        .defaultSize(width: 1000, height: 700)

        MenuBarExtra("PIQ", systemImage: "eyes") {
            MenuBarView()
                .environment(appState)
                .frame(width: 360, height: 500)
        }
        .menuBarExtraStyle(.window)
    }
}
