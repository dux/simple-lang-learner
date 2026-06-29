import SwiftUI

struct ConversationView: View {
    @StateObject private var vm = ConversationViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            inputBar
        }
    }

    private var header: some View {
        HStack {
            Text("Conversation - \(Languages.name(for: settings.targetLanguage))")
                .appFont(.normal, weight: .semibold)
            Spacer()
            Button { vm.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                .pointingHand().disabled(vm.turns.isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.turns) { bubble($0) }
                    if vm.isThinking {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("thinking...") }
                            .foregroundStyle(.secondary).appFont(.small)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: vm.turns.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: vm.isThinking) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
    }

    // Tutor left, me right; each foreign segment shows a translation + a small speaker.
    private func bubble(_ turn: ChatTurn) -> some View {
        HStack {
            if turn.speaker == .me { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(turn.segments) { segmentView($0) }
            }
            .padding(10)
            .background(turn.speaker == .me ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
            if turn.speaker == .tutor { Spacer(minLength: 40) }
        }
    }

    private func segmentView(_ seg: Segment) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(seg.text).appFont(.normal)
                if seg.isForeign {
                    SpeedControls { vm.replay(seg, speed: $0) }
                }
            }
            // The same reply, broken into tappable chunks (exactly like the Words tab).
            if !seg.parts.isEmpty {
                GlossText(parts: seg.parts) { vm.replay($0) }
            } else if let tr = seg.translation, !tr.isEmpty {
                Text(tr).appFont(.small).foregroundStyle(.secondary)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                micButton(settings.targetLanguage)   // say it in the language you're learning
                micButton(settings.nativeLanguage)   // ask in your own language

                TextField("Type a message...", text: $vm.input)
                    .textFieldStyle(.roundedBorder).appFont(.normal).onSubmit { vm.sendTyped() }

                Button { vm.sendTyped() } label: { Image(systemName: "paperplane.fill") }
                    .pointingHand().disabled(!vm.canSend)
                if vm.isThinking { ProgressView().controlSize(.small) }
            }
            let note = vm.status.isEmpty ? vm.transcriber.status : vm.status
            if !note.isEmpty {
                Text(note).appFont(.small).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // One mic per language so the user picks what they're speaking - no detection.
    private func micButton(_ lang: String) -> some View {
        let on = vm.isListening(lang)
        return Button { vm.mic(lang) } label: {
            VStack(spacing: 1) {
                Image(systemName: on ? "mic.fill" : "mic.circle").font(.system(size: 22))
                Text(lang.uppercased()).appFont(.small, weight: .semibold)
            }
            .foregroundStyle(on ? Color.red : Color.accentColor)
        }
        .buttonStyle(.borderless).pointingHand()
        .help("Speak in \(Languages.name(for: lang))")
    }
}
