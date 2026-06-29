import Foundation

// Persisted user settings, stored as JSON under ~/.config/friendly_lang_tutor.
// (JSON only for this tiny settings blob; generated word content uses the flat
// line format - see Word.swift.)
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var whisperModel: String { didSet { save() } }
    @Published var targetLanguage: String { didSet { save() } }   // the language being learned
    @Published var nativeLanguage: String { didSet { save() } }   // the user's own language
    @Published var chatBackend: String { didSet { save() } }
    @Published var style: String { didSet { save() } }
    @Published var speechRate: Double { didSet { save() } }   // 1.0 = system default; <1 slower, >1 faster
    @Published var ttsVoices: [String: String] { didSet { save() } }   // language code -> selected voice id (Piper package or Apple voice id)
    @Published var autoRefreshMinutes: Int { didSet { save() } }   // 0 = off; auto-advance to the next word every N minutes

    private static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/friendly_lang_tutor", isDirectory: true)
    private static let fileURL = dir.appendingPathComponent("settings.json")

    private struct Payload: Codable {
        var whisperModel: String
        var targetLanguage: String?
        var nativeLanguage: String?
        var chatBackend: String?
        var style: String?
        var speechRate: Double?
        var ttsVoices: [String: String]?
        var autoRefreshMinutes: Int?
    }

    private init() {
        let loaded = Self.load()
        whisperModel = loaded?.whisperModel ?? "large-v3-turbo"
        targetLanguage = loaded?.targetLanguage ?? "es"
        nativeLanguage = loaded?.nativeLanguage ?? "en"
        chatBackend = loaded?.chatBackend ?? "claude"
        style = loaded?.style ?? WordStyle.everyday.rawValue
        speechRate = loaded?.speechRate ?? 1.0
        ttsVoices = loaded?.ttsVoices ?? [:]
        autoRefreshMinutes = loaded?.autoRefreshMinutes ?? 10
    }

    var pair: String { "\(targetLanguage)-\(nativeLanguage)" }

    private static func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private func save() {
        let payload = Payload(whisperModel: whisperModel, targetLanguage: targetLanguage,
                              nativeLanguage: nativeLanguage, chatBackend: chatBackend,
                              style: style, speechRate: speechRate, ttsVoices: ttsVoices,
                              autoRefreshMinutes: autoRefreshMinutes)
        do {
            try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("settings save failed: \(error.localizedDescription)")
        }
    }
}
