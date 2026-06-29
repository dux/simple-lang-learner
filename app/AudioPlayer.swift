import AVFoundation

// Owns all audio output: playing a rendered file, playing a sequence of files back to
// back, and speaking live as a last resort. Single owner of the players and the live
// synthesizer so `stop()` can reliably silence whatever is currently playing.
@MainActor
final class AudioPlayer {
    private var player: AVAudioPlayer?
    private var sequence: SequencePlayer?
    private let synth = AVSpeechSynthesizer()

    func play(_ url: URL) {
        stop()
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            player = p
            p.play()
        } catch {
            NSLog("audio play failed: \(error.localizedDescription)")
        }
    }

    func play(sequence urls: [URL]) {
        stop()
        let seq = SequencePlayer(urls)
        sequence = seq
        seq.start()
    }

    // Last-resort live speech for voices that refuse the file-write API.
    func speakLive(_ text: String, voiceID: String?, lang: String, multiplier: Double) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = SystemRenderer.voice(id: voiceID, lang: lang)
        utterance.rate = SpeechSpeed.avRate(multiplier)
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        player?.stop()
        player = nil
        sequence?.stop()
        sequence = nil
    }
}

// Plays a list of audio files back to back via AVAudioPlayer (which detects format by
// content, so our .caf-named WAV files play fine). Main-thread confined: created and
// started from AudioPlayer (@MainActor) and the finish callback arrives on the main
// run loop.
private final class SequencePlayer: NSObject, AVAudioPlayerDelegate {
    private var remaining: [URL]
    private var player: AVAudioPlayer?

    init(_ urls: [URL]) { remaining = urls }

    func start() { playNext() }

    func stop() {
        player?.stop()
        player = nil
        remaining.removeAll()
    }

    private func playNext() {
        guard !remaining.isEmpty else { player = nil; return }
        let url = remaining.removeFirst()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { playNext(); return }
        p.delegate = self
        player = p
        p.play()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playNext()
    }
}
