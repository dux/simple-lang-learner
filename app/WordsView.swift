import SwiftUI

struct WordsView: View {
    @StateObject private var vm = TutorViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var progress = ProgressStore.shared   // re-render on view-count / rating changes
    @State private var showAllWords = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showAllWords {
                AllWordsView(entries: vm.entries,
                             speak: { vm.say($0) },
                             select: { vm.load($0); showAllWords = false })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        wordBlock
                        if let content = vm.content {
                            sentences(content)
                        }
                        sayIt
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                footer
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { vm.onAppear() }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Text("\(Languages.name(for: settings.targetLanguage)) -> \(Languages.name(for: settings.nativeLanguage))")
                .appFont(.normal, weight: .semibold)
            Spacer()
            if !showAllWords {
                HStack(spacing: 4) {
                    Text("Auto").appFont(.small).foregroundStyle(.secondary)
                    TextField("", value: Binding(get: { settings.autoRefreshMinutes },
                                                 set: { vm.setAutoMinutes($0) }), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 38)
                        .multilineTextAlignment(.center)
                    Text("min").appFont(.small).foregroundStyle(.secondary)
                }
                .help("Auto-advance to the next word every N minutes (0 = off)")
                Picker("", selection: Binding(get: { vm.styleSelection },
                                              set: { vm.setStyle($0) })) {
                    ForEach(WordStyle.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                Button {
                    vm.regenerate()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Regenerate in this style")
                .pointingHand()
                .disabled(vm.content == nil || vm.isLoading)
            }
            Button { showAllWords.toggle() } label: {
                Image(systemName: showAllWords ? "chevron.backward" : "list.bullet")
            }
            .help(showAllWords ? "Back to the word" : "Browse all words")
            .pointingHand()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: word

    private var wordBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.isLoading && vm.content == nil {
                ProgressView().controlSize(.small)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(vm.content?.word ?? "-")
                    .appFont(.title, weight: .semibold)
                if let pos = vm.content?.pos, !pos.isEmpty {
                    Text(pos).appFont(.small).foregroundStyle(.secondary)
                }
            }
            if let article = vm.content?.article, !article.isEmpty {
                Text(article).appFont(.small).foregroundStyle(.secondary)
            }
            Text(vm.content?.meaning ?? " ")
                .appFont(.normal)
                .foregroundStyle(.primary)
            HStack(spacing: 10) {
                SpeedControls { vm.speakWord($0) }
                Divider().frame(height: 18)
                Button { vm.practiceWord() } label: {
                    Image(systemName: vm.isPracticingWord ? "mic.fill" : "mic").appFont(.normal)
                        .foregroundStyle(vm.isPracticingWord ? Color.red : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .pointingHand()
                .help("Speak the word to check your pronunciation")
            }
            .disabled(vm.content == nil)
            .padding(.top, 2)

            // How well do you know this word? (defaults to "Remind me" until rated up)
            HStack(spacing: 12) {
                KnowledgeControls(level: vm.knowledge) { vm.rate($0) }
                if vm.shownCount > 0 {
                    Text("seen \(vm.shownCount)x").appFont(.small).foregroundStyle(.secondary)
                }
            }
            .disabled(vm.entry == nil)
            .padding(.top, 2)
        }
    }

    // MARK: sentences

    private func sentences(_ content: WordContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Examples").appFont(.normal, weight: .semibold).foregroundStyle(.secondary)
            ForEach(Array(content.sentences.enumerated()), id: \.element.id) { index, pair in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        SpeedControls { vm.speakTarget(index, speed: $0) }
                        Divider().frame(height: 16)
                        Button { vm.practiceSentence(index) } label: {
                            Image(systemName: vm.isPracticing(index) ? "mic.fill" : "mic").appFont(.normal)
                                .foregroundStyle(vm.isPracticing(index) ? Color.red : Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .pointingHand()
                        .help("Speak this sentence to check your pronunciation")
                    }
                    Text(pair.target).appFont(.normal, weight: .medium)
                    GlossText(parts: pair.parts) { vm.speak($0) }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
            }
        }
    }

    // MARK: say it

    private var sayIt: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: vm.isRecording ? "mic.fill" : "mic").appFont(.normal)
                    .foregroundStyle(vm.isRecording ? Color.red : .secondary)
                Text(vm.isRecording
                     ? "Listening... tap the mic again to stop"
                     : "Tap a mic to speak. Your speech is matched against the example.")
                    .appFont(.small).foregroundStyle(.secondary)
            }
            if !vm.transcriber.status.isEmpty {
                Text(vm.transcriber.status).appFont(.small).foregroundStyle(.secondary)
            }
            if !vm.heardText.isEmpty {
                Text("Heard: \(vm.heardText)").appFont(.small).foregroundStyle(.secondary)
            }
            if !vm.feedback.isEmpty {
                Text(vm.feedback)
                    .appFont(.normal)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            if !vm.status.isEmpty {
                Text(vm.status).appFont(.small).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.nextReady {
                ProgressView().controlSize(.small)
                Text("preparing next...").appFont(.small).foregroundStyle(.secondary)
            }
            Button {
                vm.next()
            } label: {
                Label("Next random word", systemImage: "arrow.right.circle.fill")
            }
            .keyboardShortcut(.return, modifiers: [])
            .pointingHand()
            .disabled(!vm.nextReady || vm.isLoading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
