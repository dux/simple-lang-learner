import Combine
import Foundation
import SwiftUI

// Coordinates the word loop: pick a word -> generate (cached) -> pre-render target
// audio -> show + speak. Also drives the pronunciation check.
@MainActor
final class TutorViewModel: ObservableObject {
    @Published var content: WordContent?
    @Published var isLoading = false
    @Published var status = ""
    @Published var heardText = ""
    @Published var feedback = ""
    @Published var styleSelection: WordStyle

    // What the user is currently practicing: nil index = the headword, else a
    // sentence index. `practiceTarget` is the text we match the spoken audio against.
    @Published var practicingIndex: Int?
    private var practiceTarget = ""

    let speaker = Speaker()
    let transcriber = Transcriber()
    let store: WordStore
    let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        let s = AppSettings.shared
        store = WordStore(language: s.targetLanguage)
        styleSelection = WordStyle(rawValue: s.style) ?? .everyday
        transcriber.onResult = { [weak self] heard in
            guard let self else { return }
            let target = self.practiceTarget.isEmpty ? (self.content?.word ?? "") : self.practiceTarget
            guard !target.isEmpty else { return }
            Task { await self.checkPronunciation(target: target, heard: heard) }
        }
        // SwiftUI does not observe nested ObservableObjects, so forward the
        // transcriber's changes (recording state, status) to this view model.
        transcriber.objectWillChange
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &cancellables)
    }

    var pair: String { settings.pair }
    private var ratePct: Int { Int((settings.speechRate * 100).rounded()) }

    func onAppear() {
        transcriber.installPushToTalk()
        ModelResolver.ensureAvailable(settings.whisperModel)
        if content == nil { next() }
    }

    // MARK: word loop

    func next() {
        let word = store.nextRandom()
        Task { await load(word, force: false) }
    }

    func regenerate() {
        guard let word = content?.word else { return }
        Task { await load(word, force: true) }
    }

    func setStyle(_ style: WordStyle) {
        guard style != styleSelection else { return }
        styleSelection = style
        settings.style = style.rawValue
        if let word = content?.word {
            Task { await load(word, force: false) }
        }
    }

    private func load(_ word: String, force: Bool) async {
        isLoading = true
        status = "generating..."
        feedback = ""
        heardText = ""
        defer { isLoading = false }
        do {
            let wc = try await Generator.generate(
                word: word, style: styleSelection,
                target: settings.targetLanguage, native: settings.nativeLanguage, force: force)
            await prerender(wc)        // pre-generate target audio before showing
            content = wc
            practiceTarget = wc.word   // default practice target is the headword
            practicingIndex = nil
            status = ""
            announce(wc)
        } catch {
            content = nil
            status = error.localizedDescription
        }
    }

    // Pre-render only the headword so its playback is instant. Example sentences
    // render lazily on first play (Speaker.play renders on a cache miss).
    private func prerender(_ wc: WordContent) async {
        let voice = Speaker.voiceTag(settings.targetLanguage)
        let wordURL = ContentCache.wordAudioURL(pair: pair, word: wc.word, voice: voice, ratePct: ratePct)
        if !ContentCache.exists(wordURL) {
            _ = await Speaker.render(wc.word, language: settings.targetLanguage,
                                     rate: Speaker.rate(settings.speechRate), to: wordURL)
        }
    }

    // On a new word: say the word in the target language, then its meaning.
    private func announce(_ wc: WordContent) {
        speaker.announce([(wc.word, settings.targetLanguage),
                          (wc.meaning, settings.nativeLanguage)])
    }

    // MARK: playback buttons

    // Effective rate + cache key for a chosen speed, scaled off the baseline.
    private func rateInfo(_ speed: SpeechSpeed) -> (rate: Float, pct: Int) {
        let multiplier = settings.speechRate * speed.factor
        return (Speaker.rate(multiplier), Int((multiplier * 100).rounded()))
    }

    func speakWord(_ speed: SpeechSpeed = .normal) {
        guard let wc = content else { return }
        let info = rateInfo(speed)
        let url = ContentCache.wordAudioURL(
            pair: pair, word: wc.word, voice: Speaker.voiceTag(settings.targetLanguage), ratePct: info.pct)
        speaker.play(wc.word, language: settings.targetLanguage, rate: info.rate, cacheURL: url)
    }

    func speakTarget(_ index: Int, speed: SpeechSpeed = .normal) {
        guard let wc = content, wc.sentences.indices.contains(index) else { return }
        let info = rateInfo(speed)
        let url = ContentCache.sentenceAudioURL(
            pair: pair, word: wc.word, style: styleSelection.rawValue,
            index: index, lang: settings.targetLanguage, ratePct: info.pct)
        speaker.play(wc.sentences[index].target, language: settings.targetLanguage, rate: info.rate, cacheURL: url)
    }

    // Speak a single tapped gloss chunk (target language). Ad-hoc, so not cached.
    func speakChunk(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speaker.play(trimmed, language: settings.targetLanguage,
                     rate: rateInfo(.normal).rate, cacheURL: nil)
    }

    // MARK: pronunciation / mic

    var isRecording: Bool { transcriber.isRecording }
    var isPracticingWord: Bool { transcriber.isRecording && practicingIndex == nil }
    func isPracticing(_ index: Int) -> Bool { transcriber.isRecording && practicingIndex == index }

    // Tap a mic to record; tap again to stop and check. Only one at a time, so a
    // tap while recording just stops (matching against whatever was set on start).
    func practiceWord() {
        if transcriber.isRecording { transcriber.toggle(); return }
        guard let wc = content else { return }
        clearResults()
        practiceTarget = wc.word
        practicingIndex = nil
        transcriber.toggle()
    }

    func practiceSentence(_ index: Int) {
        if transcriber.isRecording { transcriber.toggle(); return }
        guard let wc = content, wc.sentences.indices.contains(index) else { return }
        clearResults()
        practiceTarget = wc.sentences[index].target
        practicingIndex = index
        transcriber.toggle()
    }

    // Wipe the previous attempt's transcript + feedback so the bottom panel
    // isn't showing stale results while a new attempt records.
    private func clearResults() {
        heardText = ""
        feedback = ""
    }

    private func checkPronunciation(target: String, heard: String) async {
        heardText = heard
        status = "checking pronunciation..."
        let note = await Pronunciation.feedback(
            target: target, heard: heard, language: settings.targetLanguage)
        feedback = note
        status = ""
        // Play the thing they practiced, said correctly.
        if let index = practicingIndex { speakTarget(index) } else { speakWord() }
    }
}
