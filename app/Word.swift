import Foundation

// Regenerate styles, ordered low -> high. `guidance` is injected into the prompt.
enum WordStyle: String, CaseIterable, Identifiable {
    case basic, everyday, fun, formal, expert
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var guidance: String {
        switch self {
        case .basic:    return "very simple and beginner-friendly: only the most common high-frequency words, short sentences"
        case .everyday: return "neutral and natural, common everyday usage"
        case .fun:      return "casual and playful, with light slang where it sounds natural"
        case .formal:   return "polite and formal, business-appropriate register"
        case .expert:   return "advanced, idiomatic, native-level vocabulary and sentence structure"
        }
    }
}

struct SentencePair: Hashable, Identifiable {
    let id = UUID()
    let target: String     // sentence in the language being learned
    let parts: [Segment]   // segmented gloss: each foreign chunk paired with its native meaning
}

// One word's generated content. Produced by the LLM in the flat line format and
// cached verbatim; see `parse`.
struct WordContent: Hashable {
    let word: String
    let pos: String         // part of speech, e.g. "verb"
    let article: String?    // for nouns: article + plural; nil otherwise
    let meaning: String     // short native-language meaning
    let sentences: [SentencePair]

    // Parse the flat line format. One "KEY value" per line; ES/EN lines pair up in
    // order. Unknown lines (commentary, code fences) are ignored, so a chatty model
    // reply still parses as long as the keyed lines are present.
    static func parse(_ raw: String, target: String) -> WordContent? {
        var word = "", pos = "", meaning = ""
        var article: String?
        var targets: [String] = [], glosses: [String] = []

        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " ") else { continue }
            let key = line[line.startIndex..<space].uppercased()
            let value = String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "WORD":                   word = value
            case "POS":                    pos = value
            case "ARTICLE":                article = (value == "-" || value.isEmpty) ? nil : value
            case "MEANING":                meaning = value
            case "ES", "TARGET":           targets.append(value)
            case "EN", "GLOSS", "NATIVE":  glosses.append(value)
            default:                       break
            }
        }

        guard !word.isEmpty, !meaning.isEmpty else { return nil }
        let count = min(targets.count, glosses.count)
        let pairs = (0..<count).map {
            SentencePair(target: targets[$0], parts: parseGloss(glosses[$0], lang: target))
        }
        guard !pairs.isEmpty else { return nil }
        return WordContent(word: word, pos: pos, article: article, meaning: meaning, sentences: pairs)
    }

    // Parse the segmented gloss ("chunk (meaning) chunk (meaning) ...") into ordered
    // foreign chunks, each paired with its native meaning. Defensive about missing or
    // unbalanced parentheses. The result is the same Segment model the chat uses, so a
    // gloss chunk is speakable through the shared path.
    static func parseGloss(_ gloss: String, lang: String) -> [Segment] {
        var parts: [Segment] = []
        var chunk = "", meaning = "", depth = 0

        func flush() {
            let t = chunk.trimmingCharacters(in: .whitespaces)
            let m = meaning.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty {
                parts.append(Segment(text: t, lang: lang, translation: m.isEmpty ? nil : m, isForeign: true))
            }
            chunk = ""; meaning = ""
        }

        for ch in gloss {
            switch ch {
            case "(":
                depth += 1
                if depth > 1 { meaning.append(ch) }   // nested paren belongs to the meaning
            case ")":
                depth = max(0, depth - 1)
                if depth == 0 { flush() } else { meaning.append(ch) }
            default:
                if depth == 0 { chunk.append(ch) } else { meaning.append(ch) }
            }
        }
        flush()   // trailing chunk with no meaning
        return parts
    }
}
