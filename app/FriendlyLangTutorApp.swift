import SwiftUI

@main
struct FriendlyLangTutorApp: App {
    var body: some Scene {
        WindowGroup("Friendly Lang Tutor") {
            RootView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
