import SwiftUI

@main
struct FriendlyLangTutorApp: App {
    var body: some Scene {
        WindowGroup("Friendly Lang Tutor") {
            ContentView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
