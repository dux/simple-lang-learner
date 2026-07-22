import SwiftUI

// Three speaker buttons - normal, slow, super slow - that call `play` with the chosen
// speed. Shared by the Words and Microphone tabs so both speak at matching speeds.
struct SpeedControls: View {
    @ObservedObject private var settings = AppSettings.shared
    var role: AppText = .normal
    var slowShortcut: KeyboardShortcut? = nil   // key equivalent for the middle (slow) button
    let play: (SpeechSpeed) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SpeechSpeed.allCases, id: \.self) { speed in
                Button { play(speed) } label: {
                    Image(systemName: speed.icon).font(settings.font(role))
                }
                .buttonStyle(.borderless)
                .pointingHand()
                .help(speed.label)
                .keyboardShortcut(speed == .slow ? slowShortcut : nil)
            }
        }
    }
}
