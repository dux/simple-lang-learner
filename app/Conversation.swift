import Foundation

// Owns the conversation's wire format with the LLM: how we ask (prompt) and how we read
// the reply (parse). Mirrors Generator.prompt / WordContent.parse.
@MainActor
enum Conversation {
    // Response style: a real-person tutor that adapts to whichever language I use, and
    // tags every sentence so we know what to translate and speak.
    static func prompt(history: [ChatTurn], target t: String, native n: String, spoken: Bool) -> String {
        let target = Languages.name(for: t), native = Languages.name(for: n)
        var lines = [
            "You are a warm, patient human language tutor and friend having a real-time chat with me.",
            "My native language is \(native). I am learning \(target).",
            "I may write in \(native), in \(target), or mix them - understand me whichever I use.",
            "Always reply only in \(target), in 1-3 short, natural sentences. React like a friend would - briefly reflect or acknowledge what I said - then keep the conversation going with a follow-up question. Gently correct clear mistakes.",
            "",
            "Output ONLY these tagged lines, in reading order - no markdown, no preamble:",
            "MINE_TR <\(native) translation of MY last message if it was in \(target); otherwise a single dash ->",
            "F <one sentence, written entirely in \(target) - do not mix in \(native) or any other language>",
            "G <segmented gloss of the F line: break it into short chunks in original order, each \(target) chunk immediately followed by its \(native) meaning in parentheses, e.g. \"chunk (meaning) chunk (meaning)\">",
            "Pair every F with a G. Use as many F/G pairs as your reply needs.",
            "",
            "Conversation so far:",
        ]
        for turn in history { lines.append("\(turn.speaker == .me ? "Me" : "You"): \(turn.plainText)") }
        if spoken {
            lines.append("\nMy last message was spoken aloud and auto-transcribed, so it may be slightly off. Briefly reflect what you understood, and if it seems wrong or unclear, gently check what I meant (e.g. \"Did you mean ...?\") - always in \(target).")
        }
        lines.append("\nReply to my last message now.")
        return lines.joined(separator: "\n")
    }

    // Parse the tagged reply into segments, plus the translation of my own last message
    // (so a foreign sentence I sent also gets translation + speaker). Falls back to one
    // native segment if the model ignored the format, so nothing is lost.
    static func parse(_ raw: String, target: String, native: String)
        -> (mineTranslation: String?, segments: [Segment]) {
        var mineTR: String?
        var segments: [Segment] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let sp = line.firstIndex(of: " ") else { continue }
            let key = line[..<sp].uppercased()
            let value = String(line[line.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            switch key {
            case "MINE_TR":
                mineTR = (value == "-") ? nil : value
            case "F":
                segments.append(Segment(text: value, lang: target, translation: nil, isForeign: true))
            case "G":
                if let i = segments.lastIndex(where: { $0.isForeign && $0.parts.isEmpty }) {
                    segments[i].parts = WordContent.parseGloss(value, lang: target)
                }
            default:
                break
            }
        }
        if segments.isEmpty {
            let f = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !f.isEmpty { segments.append(Segment(text: f, lang: native, translation: nil, isForeign: false)) }
        }
        return (mineTR, segments)
    }
}
