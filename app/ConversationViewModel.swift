import Combine
import Foundation

// Drives the Microphone tab: wires the transcriber, the chat backend, and speech, and
// holds the published session state. No conversation rules live here - prompt building
// and reply parsing are in Conversation; this only orchestrates and republishes.
@MainActor
final class ConversationViewModel: ObservableObject {
    @Published private(set) var turns: [ChatTurn] = []
    @Published var input = ""
    @Published private(set) var isThinking = false
    @Published private(set) var status = ""
    @Published private(set) var listeningLang: String?   // which mic is live, for highlight

    let transcriber = Transcriber()
    private let speech = Speech()
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        transcriber.onResult = { [weak self] heard in Task { await self?.send(heard, spoken: true) } }
        // SwiftUI does not observe nested ObservableObjects, so forward the transcriber's
        // changes (recording state, status) to this view model.
        transcriber.objectWillChange
            .sink { [weak self] in MainActor.assumeIsolated { self?.objectWillChange.send() } }
            .store(in: &cancellables)
    }

    var canSend: Bool { !input.trimmingCharacters(in: .whitespaces).isEmpty && !isThinking }

    // One mic per language: the user names which language they're speaking, so whisper
    // is forced to it and never has to (mis)detect. Tapping again, or the other mic,
    // stops the current recording.
    func mic(_ lang: String) {
        if transcriber.isRecording { transcriber.toggle(); return }
        transcriber.language = lang
        listeningLang = lang
        transcriber.toggle()
    }
    func isListening(_ lang: String) -> Bool { transcriber.isRecording && listeningLang == lang }
    func sendTyped() { let t = input; input = ""; Task { await send(t, spoken: false) } }
    func replay(_ s: Speakable, speed: SpeechSpeed = .normal) { speech.speak(s, speed: speed) }
    func reset() { speech.stop(); turns.removeAll(); status = "" }

    private func send(_ text: String, spoken: Bool) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        // Show my message immediately (provisionally native; annotated after the reply).
        let mine = turns.count
        turns.append(ChatTurn(speaker: .me, segments: [
            Segment(text: trimmed, lang: settings.nativeLanguage, translation: nil, isForeign: false)]))
        isThinking = true
        defer { isThinking = false }

        let backend = ChatBackends.byID(settings.chatBackend)
        guard backend.isAvailable() else { status = "\(backend.displayName) not found"; return }
        do {
            let raw = try await backend.complete(
                Conversation.prompt(history: turns, target: settings.targetLanguage,
                                    native: settings.nativeLanguage, spoken: spoken))
            let r = Conversation.parse(raw, target: settings.targetLanguage, native: settings.nativeLanguage)
            // If my message was in the target language, attach its translation + speaker.
            if let tr = r.mineTranslation, turns.indices.contains(mine) {
                turns[mine].segments = [Segment(text: trimmed, lang: settings.targetLanguage,
                                                translation: tr, isForeign: true)]
            }
            let reply = ChatTurn(speaker: .tutor, segments: r.segments)
            turns.append(reply)
            speech.speak(reply)   // auto-speak the tutor's foreign sentences
            status = ""
        } catch {
            status = error.localizedDescription
        }
    }
}
