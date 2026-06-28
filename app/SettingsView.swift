import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var cacheSize: String = "-"

    private let backends = ChatBackends.all

    var body: some View {
        Form {
            Section("Languages") {
                Picker("Learning", selection: $settings.targetLanguage) {
                    ForEach(Languages.catalog) { Text($0.name).tag($0.code) }
                }
                Picker("Native", selection: $settings.nativeLanguage) {
                    ForEach(Languages.catalog) { Text($0.name).tag($0.code) }
                }
            }

            Section("Engines") {
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

            Section("Speech") {
                Stepper(value: $settings.speechRate, in: 0.5...1.5, step: 0.02) {
                    Text("Speed: \(Int((settings.speechRate * 100).rounded()))%")
                }
                Text("Applies to spoken words and sentences. 100% is the system default.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Cache") {
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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onAppear { refreshCacheSize() }
    }

    private func refreshCacheSize() {
        let bytes = ContentCache.sizeBytes()
        cacheSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
