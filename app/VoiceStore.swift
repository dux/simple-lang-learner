import AVFoundation

// One user-selectable voice for a language: a downloaded-on-demand Piper model or an
// installed Apple system voice. The `id` is what gets stored in settings.
struct VoiceOption: Identifiable, Hashable {
    enum Engine: String { case piper = "Piper", system = "System" }
    let id: String              // Piper: package; System: AVSpeechSynthesisVoice.identifier
    let name: String
    let engine: Engine
    let piper: SherpaTTS.Voice?  // set when engine == .piper
    var label: String { "\(name) (\(engine.rawValue))" }
}

// The voice authority: the one place that knows which voice a language uses. It caches
// the (slow, off-main) system-voice enumeration, builds the per-language option lists,
// drives on-demand Piper downloads, tracks the selection, and vends both a cache tag
// and a renderer for the selected voice. The Settings UI and Speech both depend on it,
// so neither resolves voices on its own. The default selection is the best installed
// Apple voice, so playback works with no download.
@MainActor
final class VoiceStore: ObservableObject {
    static let shared = VoiceStore()

    @Published private(set) var systemByLang: [String: [VoiceOption]] = [:]
    @Published var busyLang: String?    // language whose Piper voice is downloading
    @Published var error: String?

    private var loaded = false

    // Enumerate installed system voices once, off the main thread, then publish.
    func load() {
        guard !loaded else { return }
        loaded = true
        Task { self.systemByLang = await Self.enumerateSystemVoices() }
    }

    func options(for code: String) -> [VoiceOption] {
        let piper = SherpaTTS.voices(for: code).map {
            VoiceOption(id: $0.package, name: $0.name, engine: .piper, piper: $0)
        }
        return piper + (systemByLang[SherpaTTS.short(code)] ?? [])
    }

    func selectedID(for code: String) -> String {
        let opts = options(for: code)
        if let stored = AppSettings.shared.ttsVoices[SherpaTTS.short(code)],
           opts.contains(where: { $0.id == stored }) {
            return stored
        }
        return defaultID(for: code)
    }

    func selected(for code: String) -> VoiceOption? {
        options(for: code).first { $0.id == selectedID(for: code) }
    }

    func select(_ id: String, for code: String) {
        AppSettings.shared.ttsVoices[SherpaTTS.short(code)] = id
        ensureDownloaded(for: code)
    }

    // MARK: resolution (used by Speech)

    // The renderer for a language's selected voice: a Piper voice (with system
    // fallback) when one is selected and installed, else the system voice.
    func renderer(for code: String) -> TTSRenderer {
        let system = SystemRenderer(voiceID: systemVoiceID(for: code), lang: code)
        if let sel = selected(for: code), sel.engine == .piper, let pv = sel.piper,
           SherpaTTS.isBinaryInstalled(), SherpaTTS.isModelInstalled(pv) {
            return FallbackRenderer([PiperRenderer(voice: pv), system])
        }
        return system
    }

    // A filesystem-safe tag for the chosen voice, so cached audio is keyed by which
    // voice rendered it.
    func tag(for code: String) -> String {
        if let sel = selected(for: code), sel.engine == .piper, let pv = sel.piper,
           SherpaTTS.isBinaryInstalled(), SherpaTTS.isModelInstalled(pv) {
            return SherpaTTS.tag(for: pv)
        }
        let id = systemVoiceID(for: code) ?? code
        return String(id.map { ($0.isLetter || $0.isNumber) ? $0 : "_" })
    }

    // The chosen system voice id (the selected one, else the best installed for the
    // language); nil lets the renderer fall back to a language-default voice.
    func systemVoiceID(for code: String) -> String? {
        if let sel = selected(for: code), sel.engine == .system { return sel.id }
        return bestSystemID(for: code)
    }

    // MARK: downloads

    // Pull the engine (once) and the model in the background when a not-yet-installed
    // Piper voice is chosen. Never blocks the main thread.
    func ensureDownloaded(for code: String) {
        guard let sel = selected(for: code), sel.engine == .piper, let pv = sel.piper,
              !(SherpaTTS.isBinaryInstalled() && SherpaTTS.isModelInstalled(pv)),
              busyLang == nil else { return }
        busyLang = code
        error = nil
        Task {
            do {
                if !SherpaTTS.isBinaryInstalled() { try await SherpaTTS.downloadBinary() }
                if !SherpaTTS.isModelInstalled(pv) { try await SherpaTTS.downloadModel(pv) }
            } catch {
                self.error = error.localizedDescription
            }
            busyLang = nil
        }
    }

    // MARK: internals

    // Best installed system voice id (the list is already sorted best-first).
    private func bestSystemID(for code: String) -> String? {
        systemByLang[SherpaTTS.short(code)]?.first?.id
    }

    private func defaultID(for code: String) -> String {
        let opts = options(for: code)
        return opts.first { $0.engine == .system }?.id ?? opts.first?.id ?? ""
    }

    // The expensive part: enumerate + sort all installed voices on a background thread.
    nonisolated static func enumerateSystemVoices() async -> [String: [VoiceOption]] {
        await Task.detached(priority: .userInitiated) {
            var byLang: [String: [VoiceOption]] = [:]
            let sorted = AVSpeechSynthesisVoice.speechVoices().sorted {
                $0.quality.rawValue != $1.quality.rawValue
                    ? $0.quality.rawValue > $1.quality.rawValue
                    : $0.name < $1.name
            }
            for v in sorted {
                let code = String(v.language.prefix(2)).lowercased()
                byLang[code, default: []].append(
                    VoiceOption(id: v.identifier, name: v.name, engine: .system, piper: nil))
            }
            return byLang
        }.value
    }
}
