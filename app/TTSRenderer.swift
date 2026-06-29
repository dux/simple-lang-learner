import AVFoundation

// The contract for turning text into an audio file: every TTS engine implements this,
// and callers depend only on it. A renderer carries everything it needs (which voice,
// etc.) so the call site stays engine-agnostic. Returns false on any failure so the
// caller can fall back. Sendable so a renderer resolved on the main actor can run in a
// detached task.
protocol TTSRenderer: Sendable {
    func render(_ text: String, multiplier: Double, to url: URL) async -> Bool
}

// Neural Piper voice via sherpa-onnx. `multiplier` is already Piper's speed scale.
struct PiperRenderer: TTSRenderer {
    let voice: SherpaTTS.Voice

    func render(_ text: String, multiplier: Double, to url: URL) async -> Bool {
        await SherpaTTS.render(text, voice: voice, speed: multiplier, to: url)
    }
}

// Apple's AVSpeech written to a file via the synth's write API. Carries the chosen
// voice id (and language, for the fallback) rather than the voice object so it stays
// Sendable.
struct SystemRenderer: TTSRenderer {
    let voiceID: String?
    let lang: String

    // Resolve the concrete AVSpeech voice from an id, falling back to the best voice
    // for the language. The single home for this resolution (live speech reuses it).
    static func voice(id: String?, lang: String) -> AVSpeechSynthesisVoice? {
        if let id, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return AVSpeechSynthesisVoice(language: lang)
    }

    func render(_ text: String, multiplier: Double, to url: URL) async -> Bool {
        ContentCache.ensureParent(url)
        try? FileManager.default.removeItem(at: url)

        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(id: voiceID, lang: lang)
        utterance.rate = SpeechSpeed.avRate(multiplier)
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

// Tries each renderer in order, returning the first that writes audio. Lets a neural
// voice fall back to the system voice without the caller knowing either exists.
struct FallbackRenderer: TTSRenderer {
    let chain: [TTSRenderer]

    init(_ chain: [TTSRenderer]) { self.chain = chain }

    func render(_ text: String, multiplier: Double, to url: URL) async -> Bool {
        for renderer in chain {
            if await renderer.render(text, multiplier: multiplier, to: url) { return true }
        }
        return false
    }
}

// Holds the mutable render state. @unchecked Sendable because the write callback fires
// on an internal AVFoundation queue; all access happens there serially.
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
