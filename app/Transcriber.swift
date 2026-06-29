import AVFoundation
import SwiftUI

// Records a short mic clip to a 16 kHz mono WAV, then shells out to whisper-cli
// (the same engine and model cache the `srt` recipe uses) to turn it into text.
// Lifted from swift-learn-lang, pointed at the target (learning) language.
@MainActor
final class Transcriber: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var transcript = ""
    @Published var status = ""

    // Called on the main actor with a fresh, non-empty transcript.
    var onResult: ((String) -> Void)?

    private var recorder: AVAudioRecorder?
    private var wavURL: URL?
    private let settings = AppSettings.shared

    func toggle() {
        if isRecording {
            stopAndTranscribe()
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        guard await requestMic() else {
            status = "microphone permission denied"
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flt-clip-\(UUID().uuidString).wav")
        // 16 kHz mono 16-bit PCM is exactly what whisper-cli expects.
        let recSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: recSettings)
            r.record()
            recorder = r
            wavURL = url
            isRecording = true
            transcript = ""
            status = "recording..."
        } catch {
            status = "record failed: \(error.localizedDescription)"
        }
    }

    private func stopAndTranscribe() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        guard let wav = wavURL else { return }
        Task { await transcribe(wav) }
    }

    private func requestMic() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func transcribe(_ wav: URL) async {
        isTranscribing = true
        status = "transcribing..."
        defer { isTranscribing = false }

        ModelResolver.ensureAvailable(settings.whisperModel)
        let model = WhisperModels.path(for: settings.whisperModel)
        guard FileManager.default.fileExists(atPath: model.path) else {
            status = "model '\(settings.whisperModel)' not available"
            return
        }

        do {
            let text = try await Self.runWhisper(
                model: model, language: settings.targetLanguage, wav: wav)
            transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            status = transcript.isEmpty ? "no speech detected" : "done"
            if !transcript.isEmpty { onResult?(transcript) }
        } catch {
            status = error.localizedDescription
        }
        try? FileManager.default.removeItem(at: wav)
    }

    // Subprocess + pipe read run off the main actor. Plain Sendable values in,
    // String out.
    nonisolated static func runWhisper(model: URL, language: String, wav: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let cli = whisperCLIURL() else { throw TranscribeError.cliNotFound }
            let outBase = wav.deletingPathExtension()
            let process = Process()
            process.executableURL = cli
            process.arguments = ["-m", model.path, "-l", language, "-mc", "0",
                                 "-nt", "-otxt", "-of", outBase.path, wav.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let log = String(data: data, encoding: .utf8) ?? ""
                throw TranscribeError.whisperFailed(log)
            }
            let txt = outBase.appendingPathExtension("txt")
            defer { try? FileManager.default.removeItem(at: txt) }
            return (try? String(contentsOf: txt, encoding: .utf8)) ?? ""
        }.value
    }

    nonisolated static func whisperCLIURL() -> URL? {
        for candidate in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"]
        where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    enum TranscribeError: LocalizedError {
        case cliNotFound
        case whisperFailed(String)

        var errorDescription: String? {
            switch self {
            case .cliNotFound:
                return "whisper-cli not found - install with `brew install whisper-cpp`"
            case .whisperFailed(let log):
                return "whisper-cli failed: \(log.suffix(200))"
            }
        }
    }
}
