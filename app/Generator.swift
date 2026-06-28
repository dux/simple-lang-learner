import Foundation

// Turns a word into cached WordContent: cache hit -> parse and return; miss ->
// ask the CLI agent for the flat line format, parse, cache the raw text.
@MainActor
enum Generator {
    static func prompt(word: String, style: WordStyle, target: String, native: String) -> String {
        let t = Languages.name(for: target)
        let n = Languages.name(for: native)
        return """
        You generate language-learning content. Target language: \(t). Native language: \(n).
        For the \(t) word "\(word)", write content that is \(style.guidance).

        Output ONLY the following lines, nothing else - no markdown, no commentary, no blank lines.
        Each line is "KEY value" on a single line:
        WORD <the word in its dictionary form, corrected if my spelling was slightly off>
        POS <part of speech in \(n): noun, verb, adjective, adverb, ...>
        ARTICLE <if it is a \(t) noun, its definite article and plural, e.g. "el libro, los libros"; otherwise a single dash ->
        MEANING <short \(n) meaning>

        Then exactly 3 example sentences, each as two lines:
        ES <a natural \(t) sentence that uses the word>
        EN <a segmented gloss of that sentence: break it into short chunks in their original order, and write each \(t) chunk immediately followed by its \(n) meaning in parentheses>

        Keep the \(t) chunks in the original word order so the EN line reads as the sentence with inline help.
        EN line shape: "<chunk> (<meaning>) <chunk> (<meaning>) ...".
        Example for the \(t) sentence "danas popodne idem s prijateljima u park":
        EN danas popodne (this afternoon) idem (I am going) s prijateljima (with friends) u park (to the park)
        Always use the literal key ES for the \(t) sentence and EN for the gloss line.
        """
    }

    static func generate(word: String, style: WordStyle,
                         target: String, native: String, force: Bool = false) async throws -> WordContent {
        let pair = "\(target)-\(native)"
        let url = ContentCache.textURL(pair: pair, word: word, style: style.rawValue)

        if force {
            try? FileManager.default.removeItem(at: url)
        } else if let cached = ContentCache.loadText(url), let wc = WordContent.parse(cached) {
            return wc
        }

        let backend = ChatBackends.byID(AppSettings.shared.chatBackend)
        guard backend.isAvailable() else { throw ChatError.notInstalled(backend.displayName) }

        let raw = try await backend.complete(prompt(word: word, style: style, target: target, native: native))
        guard let wc = WordContent.parse(raw) else {
            throw ChatError.process("could not parse model reply")
        }
        ContentCache.saveText(raw, to: url)
        return wc
    }
}
