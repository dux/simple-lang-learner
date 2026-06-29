import Foundation

// One concept in the shared base vocabulary, with its word in each supported language.
// The same concept set backs every language - agua/Wasser/eau are one entry. The `id`
// (English key) is stable and is what user progress is keyed by.
struct BaseWord: Decodable, Identifiable {
    let id: String            // stable English concept key
    let cat: String           // thematic category (for grouping / filtering only)
    let tier: Tier            // starter (core subset) or basic (the rest)
    let w: [String: String]   // language code -> word

    enum Tier: String, Decodable, CaseIterable, Identifiable {
        case starter, basic
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
}

// A base concept resolved to the current (target, native) pair - ready to show, speak,
// and track. Built from a BaseWord; entries missing either side are dropped.
struct VocabEntry: Identifiable {
    let id: String          // concept id (same as BaseWord.id)
    let target: String      // word in the language being learned
    let native: String      // its meaning in the user's language
    let category: String
    let tier: BaseWord.Tier
}

// Loads the bundled shared base once and resolves it to a language pair. Pure data
// access - no selection or progress state (that lives in WordStore / ProgressStore).
enum Vocabulary {
    static let all: [BaseWord] = load()

    private static func load() -> [BaseWord] {
        guard let url = Bundle.module.url(forResource: "base", withExtension: "json", subdirectory: "words"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([BaseWord].self, from: data) else { return [] }
        return rows
    }

    // Resolve the shared base to a (target, native) pair, dropping concepts that lack a
    // word on either side. One authoritative place for the resolution.
    static func entries(target: String, native: String) -> [VocabEntry] {
        all.compactMap { b in
            guard let t = b.w[target], let n = b.w[native], !t.isEmpty, !n.isEmpty else { return nil }
            return VocabEntry(id: b.id, target: t, native: n, category: b.cat, tier: b.tier)
        }
    }
}
