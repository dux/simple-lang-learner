import Foundation

// The pool of words to learn for the current language pair, drawn from the one shared
// base vocabulary (see Vocabulary). Holds selection state only; the data and the pair
// resolution live in Vocabulary.
@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var entries: [VocabEntry]
    private var lastIndex: Int?

    init(target: String, native: String) {
        entries = Vocabulary.entries(target: target, native: native)
    }

    func reload(target: String, native: String) {
        entries = Vocabulary.entries(target: target, native: native)
        lastIndex = nil
    }

    // A random concept that isn't the one we just showed.
    func nextRandom() -> VocabEntry? {
        guard !entries.isEmpty else { return nil }
        guard entries.count > 1 else { return entries.first }
        var i = Int.random(in: 0..<entries.count)
        while i == lastIndex { i = Int.random(in: 0..<entries.count) }
        lastIndex = i
        return entries[i]
    }
}
