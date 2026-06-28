import Foundation

// Turns a target phrase + what whisper heard into a short spoken-feedback note via
// the CLI agent. Whisper is forgiving, so this is "did it come through and what to
// fix", not phoneme-level scoring (see doc/plan.md section 6).
@MainActor
enum Pronunciation {
    static func feedback(target: String, heard: String, language: String) async -> String {
        let backend = ChatBackends.byID(AppSettings.shared.chatBackend)
        guard backend.isAvailable() else { return "" }
        let lang = Languages.name(for: language)
        let prompt = """
        I am practicing speaking \(lang). The phrase I tried to say is: "\(target)".
        A speech recognizer heard: "\(heard)".
        In one or two short \(Languages.name(for: AppSettings.shared.nativeLanguage)) sentences, \
        tell me what I most likely got wrong and how to fix it. If it matches well, \
        just say it sounds good. Output plain text only, no preamble.
        """
        let reply = (try? await backend.complete(prompt))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return reply ?? ""
    }
}
