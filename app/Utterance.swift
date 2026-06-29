import Foundation

// The shared unit of speech: what to say and in which language. Used by both the word
// announce (Words tab) and the conversation, so there is one "speakable" type.
struct Utterance {
    let text: String
    let lang: String
    var speed: SpeechSpeed = .normal
}

// The speak contract: anything that can be voiced exposes its utterances. The chat's
// auto-speak and its per-sentence replay buttons both go through this, never through a
// concrete type. Native (non-spoken) content simply returns an empty list.
protocol Speakable {
    var utterances: [Utterance] { get }
}

extension Speech {
    // One way to speak any Speakable (a single segment replay or a whole turn), at an
    // optional speed that overrides the utterances' own.
    func speak(_ s: Speakable, speed: SpeechSpeed = .normal) {
        let u = s.utterances.map { Utterance(text: $0.text, lang: $0.lang, speed: speed) }
        guard !u.isEmpty else { return }
        sequence(u)
    }
}
