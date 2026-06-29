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
    @Published private(set) var nextReady = false   // next word prefetched + ready to show

    // What the user is currently practicing: nil index = the headword, else a
    // sentence index. `practiceTarget` is the text we match the spoken audio against.
    @Published var practicingIndex: Int?
    private var practiceTarget = ""

    let speech = Speech()
    let transcriber = Transcriber()
    let store: WordStore
    let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    private var prefetched: WordContent?
    private var prefetchTask: Task<Void, Never>?
    private var autoTimer: Timer?
    private var advanceWhenReady = false   // auto-advance fired before the next word was ready

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

    func onAppear() {
        ModelResolver.ensureAvailable(settings.whisperModel)
        if content == nil { Task { await loadForeground(store.nextRandom(), force: false) } }
    }

    // MARK: word loop

    // Advance to the prefetched word (instant). The button is disabled until one is
    // ready, so `prefetched` is normally non-nil here.
    func next() {
        guard let wc = prefetched else { return }
        prefetched = nil
        nextReady = false
        show(wc)
        startPrefetch()
    }

    func regenerate() {
        guard let word = content?.word else { return }
        Task { await loadForeground(word, force: true) }
    }

    func setStyle(_ style: WordStyle) {
        guard style != styleSelection else { return }
        styleSelection = style
        settings.style = style.rawValue
        guard let word = content?.word else { return }
        Task { await loadForeground(word, force: false) }
    }

    // Foreground load: show progress, generate this word, display + speak it, then
    // begin prefetching the following word.
    private func loadForeground(_ word: String, force: Bool) async {
        isLoading = true
        status = "generating..."
        feedback = ""
        heardText = ""
        defer { isLoading = false }
        do {
            let wc = try await produce(word, force: force)
            show(wc)
        } catch {
            if !force { content = nil }
            status = error.localizedDescription
        }
        startPrefetch()
    }

    // Generate (cached) + pre-render a word's audio without touching the UI.
    private func produce(_ word: String, force: Bool) async throws -> WordContent {
        let wc = try await Generator.generate(
            word: word, style: styleSelection,
            target: settings.targetLanguage, native: settings.nativeLanguage, force: force)
        await prerender(wc)
        return wc
    }

    // Display a ready word, reset practice + auto-advance state, and speak it.
    private func show(_ wc: WordContent) {
        content = wc
        practiceTarget = wc.word   // default practice target is the headword
        practicingIndex = nil
        feedback = ""
        heardText = ""
        status = ""
        announce(wc)
        scheduleAuto()
    }

    // Generate the next random word in the background so "Next" is instant. Tries a
    // few words so a single generation failure doesn't leave the button stuck.
    private func startPrefetch() {
        prefetchTask?.cancel()
        nextReady = false
        prefetchTask = Task {
            for _ in 0..<3 {
                if Task.isCancelled { return }
                let word = store.nextRandom()
                if let wc = try? await produce(word, force: false) {
                    if Task.isCancelled { return }
                    prefetched = wc
                    nextReady = true
                    if advanceWhenReady { advanceWhenReady = false; next() }
                    return
                }
            }
        }
    }

    // MARK: auto-refresh

    var autoMinutes: Int { settings.autoRefreshMinutes }

    func setAutoMinutes(_ minutes: Int) {
        settings.autoRefreshMinutes = max(0, minutes)
        objectWillChange.send()
        scheduleAuto()
    }

    // (Re)start the countdown to the next automatic advance. 0 minutes disables it.
    private func scheduleAuto() {
        autoTimer?.invalidate()
        autoTimer = nil
        let minutes = settings.autoRefreshMinutes
        guard minutes > 0 else { return }
        autoTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes) * 60, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.autoFire() }
        }
    }

    // On timeout: advance now if the next word is ready, else as soon as it is.
    private func autoFire() {
        if nextReady { next() } else { advanceWhenReady = true }
    }

    // Pre-render the headword at normal and slow speed (both used by the new-word
    // announce) so its playback is instant. Example sentences render lazily on first play.
    private func prerender(_ wc: WordContent) async {
        await speech.prepare([
            .init(text: wc.word, lang: settings.targetLanguage),
            .init(text: wc.word, lang: settings.targetLanguage, speed: .slow),
        ])
    }

    // On a new word: say the word in the target language, its meaning in the native
    // language, then the word again slowly in the target language. Each uses the voice
    // selected for that language in Settings.
    private func announce(_ wc: WordContent) {
        speech.sequence([
            .init(text: wc.word, lang: settings.targetLanguage),
            .init(text: wc.meaning, lang: settings.nativeLanguage),
            .init(text: wc.word, lang: settings.targetLanguage, speed: .slow),
        ])
    }

    // MARK: playback buttons

    func speakWord(_ speed: SpeechSpeed = .normal) {
        guard let wc = content else { return }
        speech.say(wc.word, lang: settings.targetLanguage, speed: speed)
    }

    func speakTarget(_ index: Int, speed: SpeechSpeed = .normal) {
        guard let wc = content, wc.sentences.indices.contains(index) else { return }
        speech.say(wc.sentences[index].target, lang: settings.targetLanguage, speed: speed)
    }

    // Speak a single tapped gloss chunk in the target language.
    func speakChunk(_ text: String) {
        speech.say(text, lang: settings.targetLanguage)
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
