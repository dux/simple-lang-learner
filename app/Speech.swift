import AVFoundation

// The single entry point for speaking in the app. Callers express intent only - "say
// this text, in this language, at this speed" - and Speech resolves the voice
// (VoiceStore), the speed, and the on-disk cache key, renders through the selected
// TTSRenderer, and plays the result (AudioPlayer). Nothing else needs to know how the
// audio is produced or where it is cached.
@MainActor
final class Speech {
    private let player = AudioPlayer()

    // One utterance, optionally at a non-default speed.
    struct Part {
        let text: String
        let lang: String
        var speed: SpeechSpeed = .normal
    }

    func stop() { player.stop() }

    // Speak a single utterance: play the cached clip if present, else render and cache
    // it; if rendering yields no audio, speak it live as a last resort.
    func say(_ text: String, lang: String, speed: SpeechSpeed = .normal) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let r = resolve(trimmed, lang: lang, speed: speed)
        if ContentCache.exists(r.url) { player.play(r.url); return }
        Task {
            if await r.renderer.render(trimmed, multiplier: r.multiplier, to: r.url) {
                player.play(r.url)
            } else {
                player.speakLive(trimmed, voiceID: r.systemVoiceID, lang: lang, multiplier: r.multiplier)
            }
        }
    }

    // Speak several utterances back to back (e.g. word, meaning, then word again slow).
    // Each renders with its own language's voice and speed, then plays in order.
    func sequence(_ parts: [Part]) {
        stop()
        Task {
            var urls: [URL] = []
            for part in parts {
                let trimmed = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let r = resolve(trimmed, lang: part.lang, speed: part.speed)
                if ContentCache.exists(r.url) { urls.append(r.url); continue }
                if await r.renderer.render(trimmed, multiplier: r.multiplier, to: r.url) {
                    urls.append(r.url)
                }
            }
            guard !urls.isEmpty else { return }
            player.play(sequence: urls)
        }
    }

    // Warm the cache for utterances we expect to play soon, so playback is instant.
    func prepare(_ parts: [Part]) async {
        for part in parts {
            let trimmed = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let r = resolve(trimmed, lang: part.lang, speed: part.speed)
            if !ContentCache.exists(r.url) {
                _ = await r.renderer.render(trimmed, multiplier: r.multiplier, to: r.url)
            }
        }
    }

    // Everything a single utterance needs, resolved once: the speed multiplier, the
    // renderer for the language's selected voice, the cache file, and the system voice
    // id for the live fallback.
    private struct Resolved {
        let multiplier: Double
        let renderer: TTSRenderer
        let url: URL
        let systemVoiceID: String?
    }

    private func resolve(_ text: String, lang: String, speed: SpeechSpeed) -> Resolved {
        let store = VoiceStore.shared
        let multiplier = AppSettings.shared.speechRate * speed.factor
        let pct = Int((multiplier * 100).rounded())
        let url = ContentCache.audioURL(text: text, lang: lang, voice: store.tag(for: lang), ratePct: pct)
        return Resolved(multiplier: multiplier, renderer: store.renderer(for: lang),
                        url: url, systemVoiceID: store.systemVoiceID(for: lang))
    }
}

// Playback speed choices offered as buttons. The factor scales the user's configured
// baseline speed, so "normal" follows the Settings speed.
enum SpeechSpeed: CaseIterable, Hashable {
    case normal, slow, superSlow

    var factor: Double {
        switch self {
        case .normal:    return 1.0
        case .slow:      return 0.7
        case .superSlow: return 0.5
        }
    }

    var icon: String {
        switch self {
        case .normal:    return "speaker.wave.2.fill"
        case .slow:      return "tortoise"
        case .superSlow: return "tortoise.fill"
        }
    }

    var label: String {
        switch self {
        case .normal:    return "Normal speed"
        case .slow:      return "Slow"
        case .superSlow: return "Super slow"
        }
    }

    // Map a speed multiplier (1.0 = default) onto AVSpeech's clamped rate scale. The
    // one home for this conversion, shared by the system renderer and live speech.
    static func avRate(_ multiplier: Double) -> Float {
        let scaled = Double(AVSpeechUtteranceDefaultSpeechRate) * multiplier
        let lo = Double(AVSpeechUtteranceMinimumSpeechRate)
        let hi = Double(AVSpeechUtteranceMaximumSpeechRate)
        return Float(min(max(scaled, lo), hi))
    }
}
