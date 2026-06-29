import SwiftUI

struct ContentView: View {
    @StateObject private var vm = TutorViewModel()
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
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
        .frame(minWidth: 560, minHeight: 520)
        .onAppear { vm.onAppear() }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Text("\(Languages.name(for: settings.targetLanguage)) -> \(Languages.name(for: settings.nativeLanguage))")
                .font(.headline)
            Spacer()
            HStack(spacing: 4) {
                Text("Auto").font(.caption).foregroundStyle(.secondary)
                TextField("", value: Binding(get: { settings.autoRefreshMinutes },
                                             set: { vm.setAutoMinutes($0) }), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 38)
                    .multilineTextAlignment(.center)
                Text("min").font(.caption).foregroundStyle(.secondary)
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
                    .font(.system(size: 40, weight: .semibold))
                if let pos = vm.content?.pos, !pos.isEmpty {
                    Text(pos).font(.title3).foregroundStyle(.secondary)
                }
            }
            if let article = vm.content?.article, !article.isEmpty {
                Text(article).font(.title3).foregroundStyle(.secondary)
            }
            Text(vm.content?.meaning ?? " ")
                .font(.title2)
                .foregroundStyle(.primary)
            HStack(spacing: 10) {
                speedControls(font: .title3) { vm.speakWord($0) }
                Divider().frame(height: 18)
                Button { vm.practiceWord() } label: {
                    Image(systemName: vm.isPracticingWord ? "mic.fill" : "mic").font(.title3)
                        .foregroundStyle(vm.isPracticingWord ? Color.red : Color.accentColor)
                }
                .buttonStyle(.borderless)
                .pointingHand()
                .help("Speak the word to check your pronunciation")
            }
            .disabled(vm.content == nil)
            .padding(.top, 2)
        }
    }

    // Three speaker buttons: normal, slow, super slow.
    private func speedControls(font: Font = .body, _ play: @escaping (SpeechSpeed) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(SpeechSpeed.allCases, id: \.self) { speed in
                Button { play(speed) } label: {
                    Image(systemName: speed.icon).font(font)
                }
                .buttonStyle(.borderless)
                .pointingHand()
                .help(speed.label)
            }
        }
    }

    // MARK: sentences

    private func sentences(_ content: WordContent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Examples").font(.headline).foregroundStyle(.secondary)
            ForEach(Array(content.sentences.enumerated()), id: \.element.id) { index, pair in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        speedControls { vm.speakTarget(index, speed: $0) }
                        Divider().frame(height: 16)
                        Button { vm.practiceSentence(index) } label: {
                            Image(systemName: vm.isPracticing(index) ? "mic.fill" : "mic")
                                .foregroundStyle(vm.isPracticing(index) ? Color.red : Color.accentColor)
                        }
                        .buttonStyle(.borderless)
                        .pointingHand()
                        .help("Speak this sentence to check your pronunciation")
                    }
                    Text(pair.target).font(.title3.weight(.medium))
                    Text(glossAttributed(pair.gloss))
                        .font(.body)
                        .tint(.primary)
                        .pointingHand()
                        .environment(\.openURL, OpenURLAction { url in
                            guard url.scheme == "fltspeak",
                                  let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                                  let word = comps.queryItems?.first(where: { $0.name == "w" })?.value
                            else { return .systemAction }
                            vm.speakChunk(word)
                            return .handled
                        })
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
                Image(systemName: vm.isRecording ? "mic.fill" : "mic")
                    .foregroundStyle(vm.isRecording ? Color.red : .secondary)
                Text(vm.isRecording
                     ? "Listening... tap the mic again to stop"
                     : "Tap a mic to speak. Your speech is matched against the example.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if !vm.transcriber.status.isEmpty {
                Text(vm.transcriber.status).font(.caption).foregroundStyle(.secondary)
            }
            if !vm.heardText.isEmpty {
                Text("Heard: \(vm.heardText)").font(.callout).foregroundStyle(.secondary)
            }
            if !vm.feedback.isEmpty {
                Text(vm.feedback)
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // Render a gloss with the original-language chunks in primary (tappable to hear
    // just that chunk) and the "(meanings)" muted + italic (not tappable).
    private func glossAttributed(_ gloss: String) -> AttributedString {
        var result = AttributedString()
        for segment in WordContent.glossSegments(gloss) {
            var piece = AttributedString(segment.text)
            if segment.isMeaning {
                piece.foregroundColor = .secondary
                piece.font = .body.italic()
            } else {
                piece.foregroundColor = .primary
                if let url = speakURL(for: segment.text) { piece.link = url }
            }
            result += piece
        }
        return result
    }

    // A custom-scheme URL carrying the chunk text, intercepted by the gloss's
    // OpenURLAction so a tap speaks only that chunk.
    private func speakURL(for chunk: String) -> URL? {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = "fltspeak"
        comps.host = "speak"
        comps.queryItems = [URLQueryItem(name: "w", value: trimmed)]
        return comps.url
    }

    // MARK: footer

    private var footer: some View {
        HStack {
            if !vm.status.isEmpty {
                Text(vm.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !vm.nextReady {
                ProgressView().controlSize(.small)
                Text("preparing next...").font(.caption).foregroundStyle(.secondary)
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
