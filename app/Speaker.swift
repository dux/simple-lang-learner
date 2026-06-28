import AVFoundation
import SwiftUI

// Speaks text with the best installed system voice for a language. Two paths:
//   - live `speak`/`announce` via AVSpeechSynthesizer (always works), used for the
//     spoken word + meaning when a new word appears,
//   - `play` from a pre-rendered cache file (instant on repeat), falling back to a
//     live render and then to live speech if a voice refuses the write API.
@MainActor
final class Speaker: ObservableObject {
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
    }

    // Replace whatever is playing with this single utterance. A nil rate uses the
    // configured baseline speed.
    func speak(_ text: String, language: String, rate: Float? = nil) {
        stop()
        enqueue(text, language: language, rate: rate ?? Self.rate(AppSettings.shared.speechRate))
    }

    // Speak several (text, language) pairs back to back, e.g. word then meaning.
    func announce(_ items: [(String, String)]) {
        stop()
        let rate = Self.rate(AppSettings.shared.speechRate)
        for (text, lang) in items { enqueue(text, language: lang, rate: rate) }
    }

    private func enqueue(_ text: String, language: String, rate: Float) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.bestVoice(for: language)
        utterance.rate = rate
        synth.speak(utterance)
    }

    // Map a speed multiplier (1.0 = default) onto AVSpeech's rate scale, clamped to
    // the supported range.
    static func rate(_ multiplier: Double) -> Float {
        let scaled = Double(AVSpeechUtteranceDefaultSpeechRate) * multiplier
        let lo = Double(AVSpeechUtteranceMinimumSpeechRate)
        let hi = Double(AVSpeechUtteranceMaximumSpeechRate)
        return Float(min(max(scaled, lo), hi))
    }

    // Play a pre-rendered file if present; otherwise render it now (and cache it),
    // and if that fails, just speak live.
    func play(_ text: String, language: String, rate: Float, cacheURL: URL?) {
        stop()
        if let url = cacheURL, ContentCache.exists(url) {
            playFile(url)
            return
        }
        guard let url = cacheURL else { speak(text, language: language, rate: rate); return }
        Task {
            if await Self.render(text, language: language, rate: rate, to: url) {
                self.playFile(url)
            } else {
                self.speak(text, language: language, rate: rate)
            }
        }
    }

    private func playFile(_ url: URL) {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            player = p
            p.play()
        } catch {
            NSLog("audio play failed: \(error.localizedDescription)")
        }
    }

    // Prefer premium > enhanced > default for the language; fall back to whatever
    // the system picks for the bare code.
    static func bestVoice(for code: String) -> AVSpeechSynthesisVoice? {
        let short = String(code.prefix(2)).lowercased()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix(short) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first ?? AVSpeechSynthesisVoice(language: code)
    }

    // A filesystem-safe tag for the chosen voice, so cached word audio is keyed by
    // which voice rendered it.
    static func voiceTag(_ code: String) -> String {
        let id = bestVoice(for: code)?.identifier ?? code
        let safe = id.map { ($0.isLetter || $0.isNumber) ? $0 : "_" }
        return String(safe)
    }

    // Render an utterance to a .caf file via the write API. Returns true if any
    // audio was written; some premium/personal voices yield nothing here.
    static func render(_ text: String, language: String, rate: Float, to url: URL) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        ContentCache.ensureParent(url)
        try? FileManager.default.removeItem(at: url)

        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = bestVoice(for: language)
        utterance.rate = rate
        let sink = RenderSink(url: url)

        return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            sink.onDone = { ok in cont.resume(returning: ok) }
            sink.retain = synth
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { sink.finish(false); return }
                if pcm.frameLength == 0 { sink.finish(sink.wrote); return }
                sink.append(pcm)
            }
        }
    }
}

// Playback speed choices offered as buttons. The factor scales the user's
// configured baseline speed, so "normal" follows the Settings speed.
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
}

// Holds the mutable render state. @unchecked Sendable because the write callback
// fires on an internal AVFoundation queue; all access happens there serially.
private final class RenderSink: @unchecked Sendable {
    private let url: URL
    private var file: AVAudioFile?
    private(set) var wrote = false
    private var done = false
    var onDone: ((Bool) -> Void)?
    var retain: AnyObject?

    init(url: URL) { self.url = url }

    func append(_ pcm: AVAudioPCMBuffer) {
        if file == nil {
            file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings)
        }
        if let file, (try? file.write(from: pcm)) != nil { wrote = true }
    }

    func finish(_ ok: Bool) {
        if done { return }
        done = true
        onDone?(ok)
    }
}
