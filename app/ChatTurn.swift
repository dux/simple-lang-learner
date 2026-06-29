import Foundation

// One sentence in the chat. `isForeign` (non-native) sentences carry a translation and
// are speakable; native sentences render plain. `lang` is the language to speak it in.
struct Segment: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let lang: String
    let translation: String?   // full-sentence translation (used for my own foreign messages)
    let isForeign: Bool        // non-native -> speaker, and it is spoken
    var parts: [Segment] = []  // per-chunk gloss of a foreign sentence (rendered like the Words tab)
}

extension Segment: Speakable {
    var utterances: [Utterance] { isForeign ? [Utterance(text: text, lang: lang)] : [] }
}

// One chat turn (me or tutor), made of ordered segments. `segments` is var so a user
// turn can be annotated with its translation once the tutor reply comes back.
struct ChatTurn: Identifiable {
    enum Speaker { case me, tutor }
    let id = UUID()
    let speaker: Speaker
    var segments: [Segment]

    var plainText: String { segments.map(\.text).joined(separator: " ") }   // for the prompt
}

extension ChatTurn: Speakable {
    var utterances: [Utterance] { segments.flatMap(\.utterances) }   // speak only foreign segments
}
