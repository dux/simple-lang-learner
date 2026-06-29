import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            WordsView().tabItem { Label("Words", systemImage: "character.book.closed") }
            ConversationView().tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
        }
        .frame(minWidth: 560, minHeight: 560)
        .task { VoiceStore.shared.load() }   // warm the voice list off-main
    }
}
