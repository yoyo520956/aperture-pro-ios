import SwiftUI

@main
struct ApertureProApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(appState.colorScheme)
                .tint(Color(CNTheme.indigo))
                .statusBarHidden(false)
        }
    }
}
