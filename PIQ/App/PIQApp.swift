import SwiftUI

@main
struct PIQApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("PIQ", systemImage: "chart.bar.fill") {
            MenuBarView()
                .environment(appState)
                .frame(width: 360, height: 500)
        }
        .menuBarExtraStyle(.window)
    }
}
