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
    let target: String   // sentence in the language being learned
    let gloss: String    // segmented translation: each chunk followed by its meaning in (...)
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
    static func parse(_ raw: String) -> WordContent? {
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
        let pairs = (0..<count).map { SentencePair(target: targets[$0], gloss: glosses[$0]) }
        guard !pairs.isEmpty else { return nil }
        return WordContent(word: word, pos: pos, article: article, meaning: meaning, sentences: pairs)
    }

    // Split a gloss into runs for styling: isMeaning == true for a "(...)" part
    // (rendered muted), false for an original-language chunk. Parentheses are kept
    // with the meaning. Defensive about unbalanced/nested parens.
    static func glossSegments(_ gloss: String) -> [(text: String, isMeaning: Bool)] {
        var segments: [(String, Bool)] = []
        var current = ""
        var depth = 0
        for ch in gloss {
            switch ch {
            case "(":
                if depth == 0, !current.isEmpty {
                    segments.append((current, false))
                    current = ""
                }
                current.append(ch)
                depth += 1
            case ")":
                current.append(ch)
                depth = max(0, depth - 1)
                if depth == 0 {
                    segments.append((current, true))
                    current = ""
                }
            default:
                current.append(ch)
            }
        }
        if !current.isEmpty { segments.append((current, depth > 0)) }
        return segments
    }
}
