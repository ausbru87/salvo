import SwiftUI

@main
struct CoderMailApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Message") {
                    appState.isComposePresented = true
                }
                .keyboardShortcut("N", modifiers: .command)
            }
        }
    }
}
