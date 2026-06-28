import Foundation

// The pool of words to learn. Seeds come from the bundled plain-text list
// (seeds/<lang>.txt, one word per line); a small embedded list is the fallback so
// the app still works if the resource bundle is missing.
@MainActor
final class WordStore: ObservableObject {
    @Published private(set) var words: [String]
    private var lastIndex: Int?

    init(language: String = "es") {
        words = Self.loadSeeds(language) ?? Self.fallback
    }

    func reload(language: String) {
        words = Self.loadSeeds(language) ?? Self.fallback
        lastIndex = nil
    }

    // A random word that isn't the one we just showed.
    func nextRandom() -> String {
        guard words.count > 1 else { return words.first ?? "hola" }
        var i = Int.random(in: 0..<words.count)
        while i == lastIndex { i = Int.random(in: 0..<words.count) }
        lastIndex = i
        return words[i]
    }

    static func loadSeeds(_ lang: String) -> [String]? {
        guard let url = Bundle.module.url(forResource: lang, withExtension: "txt", subdirectory: "seeds"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let list = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return list.isEmpty ? nil : list
    }

    static let fallback = [
        "hola", "gracias", "comer", "casa", "agua", "amigo",
        "trabajo", "tiempo", "hablar", "libro",
    ]
}
