import SwiftUI

@main
struct FriendlyLangTutorApp: App {
    var body: some Scene {
        WindowGroup("Friendly Lang Tutor") {
            ContentView()
                .task { VoiceStore.shared.load() }   // warm the voice list off-main
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}
