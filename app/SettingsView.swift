import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var voices = VoiceStore.shared
    @State private var cacheSize: String = "-"

    private let backends = ChatBackends.all

    var body: some View {
        TabView {
            languagesTab.tabItem { Label("Languages", systemImage: "globe") }
            voiceTab.tabItem { Label("Voice", systemImage: "waveform") }
            enginesTab.tabItem { Label("Engines", systemImage: "cpu") }
            cacheTab.tabItem { Label("Cache", systemImage: "internaldrive") }
        }
        .frame(width: 520, height: 420)
        .onAppear { voices.load() }
    }

    // MARK: Languages

    private var languagesTab: some View {
        Form {
            Picker("Learning", selection: $settings.targetLanguage) {
                ForEach(Languages.catalog) { Text($0.name).tag($0.code) }
            }
            Picker("Native", selection: $settings.nativeLanguage) {
                ForEach(Languages.catalog) { Text($0.name).tag($0.code) }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Voice

    private var voiceTab: some View {
        Form {
            Section("Speed") {
                Stepper(value: $settings.speechRate, in: 0.5...1.5, step: 0.02) {
                    Text("Speed: \(Int((settings.speechRate * 100).rounded()))%")
                }
                Text("Applies to spoken words and sentences. 100% is the system default.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Voice per language") {
                ForEach(Languages.catalog) { lang in voiceRow(lang) }
                if let err = voices.error {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Text("Piper voices download automatically the first time you pick one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func voiceRow(_ lang: Language) -> some View {
        HStack {
            Picker(lang.name, selection: voiceBinding(for: lang.code)) {
                ForEach(voices.options(for: lang.code)) { Text($0.label).tag($0.id) }
            }
            if voices.busyLang == lang.code {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func voiceBinding(for code: String) -> Binding<String> {
        Binding(
            get: { voices.selectedID(for: code) },
            set: { voices.select($0, for: code) }
        )
    }

    // MARK: Engines

    private var enginesTab: some View {
        Form {
            Picker("LLM agent", selection: $settings.chatBackend) {
                ForEach(backends, id: \.id) { b in
                    Text(b.isAvailable() ? b.displayName : "\(b.displayName) (not found)")
                        .tag(b.id)
                }
            }
            Picker("Whisper model", selection: $settings.whisperModel) {
                ForEach(WhisperModels.catalog) { Text("\($0.name) - \($0.size)").tag($0.name) }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Cache

    private var cacheTab: some View {
        Form {
            HStack {
                Text("Generated content + audio")
                Spacer()
                Text(cacheSize).foregroundStyle(.secondary)
            }
            Button("Clear cache") {
                ContentCache.clear()
                refreshCacheSize()
            }
            .pointingHand()
        }
        .formStyle(.grouped)
        .onAppear { refreshCacheSize() }
    }

    private func refreshCacheSize() {
        let bytes = ContentCache.sizeBytes()
        cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
