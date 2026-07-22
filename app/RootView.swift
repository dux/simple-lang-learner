import SwiftUI

struct RootView: View {
    @ObservedObject private var hints = ShortcutHints.shared
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        TabView(selection: $hints.tab) {
            WordsView().tabItem { Label("Words", systemImage: "character.book.closed") }
                .tag(AppTab.words)
            ConversationView().tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.chat)
        }
        .frame(minWidth: 560, minHeight: 560)
        .task { VoiceStore.shared.load() }   // warm the voice list off-main
        .overlay(alignment: .bottom) {
            // controlActiveState gate keeps the HUD off while another window (Settings) is key
            if hints.visible && activeState == .key {
                ShortcutHintsOverlay(tab: hints.tab)
                    .padding(.bottom, 28)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hints.visible)
    }
}
