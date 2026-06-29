import Foundation

// On-device neural TTS via the sherpa-onnx `sherpa-onnx-offline-tts` CLI, using
// Piper (VITS) voices. Mirrors the whisper setup: the engine binary and the voice
// models are pulled on demand into a shared ~/.cache dir, never bundled. It backs
// PiperRenderer, writing a WAV that the shared cache/playback path consumes unchanged;
// any failure lets the renderer chain fall back to Apple's AVSpeech.
enum SherpaTTS {
    struct Voice: Identifiable, Hashable {
        let package: String   // archive name == extracted dir name
        let model: String     // .onnx filename inside
        let name: String      // human-friendly label for the picker
        let size: String      // archive size, shown on the download button
        var sid: Int = 0      // speaker id (0 for single-speaker Piper voices)
        var id: String { package }
    }

    // Per-language Piper voices hosted on the sherpa-onnx `tts-models` release. The
    // first entry is the default when nothing is selected; keeping the historical
    // default first leaves existing selections and cached audio untouched.
    static let catalog: [String: [Voice]] = [
        "es": [
            .init(package: "vits-piper-es_ES-davefx-medium",   model: "es_ES-davefx-medium.onnx",   name: "Davefx (m)",     size: "64 MB"),
            .init(package: "vits-piper-es_ES-sharvard-medium", model: "es_ES-sharvard-medium.onnx", name: "Sharvard",       size: "77 MB"),
            .init(package: "vits-piper-es_MX-ald-medium",      model: "es_MX-ald-medium.onnx",      name: "ALD (m, MX)",    size: "64 MB"),
        ],
        "en": [
            .init(package: "vits-piper-en_US-lessac-medium",     model: "en_US-lessac-medium.onnx",     name: "Lessac (f, US)", size: "64 MB"),
            .init(package: "vits-piper-en_US-ryan-medium",       model: "en_US-ryan-medium.onnx",       name: "Ryan (m, US)",   size: "64 MB"),
            .init(package: "vits-piper-en_GB-jenny_dioco-medium", model: "en_GB-jenny_dioco-medium.onnx", name: "Jenny (f, GB)", size: "64 MB"),
            .init(package: "vits-piper-en_GB-alan-medium",       model: "en_GB-alan-medium.onnx",       name: "Alan (m, GB)",   size: "64 MB"),
        ],
        "de": [
            .init(package: "vits-piper-de_DE-thorsten-medium", model: "de_DE-thorsten-medium.onnx", name: "Thorsten (m)",    size: "64 MB"),
            .init(package: "vits-piper-de_DE-kerstin-low",     model: "de_DE-kerstin-low.onnx",     name: "Kerstin (f)",     size: "64 MB"),
            .init(package: "vits-piper-de_DE-thorsten-high",   model: "de_DE-thorsten-high.onnx",   name: "Thorsten HQ (m)", size: "110 MB"),
        ],
        "fr": [
            .init(package: "vits-piper-fr_FR-siwis-medium", model: "fr_FR-siwis-medium.onnx", name: "Siwis (f)", size: "64 MB"),
            .init(package: "vits-piper-fr_FR-tom-medium",   model: "fr_FR-tom-medium.onnx",   name: "Tom (m)",   size: "64 MB"),
        ],
        "it": [
            .init(package: "vits-piper-it_IT-paola-medium",    model: "it_IT-paola-medium.onnx",    name: "Paola (f)",    size: "64 MB"),
            .init(package: "vits-piper-it_IT-riccardo-x_low", model: "it_IT-riccardo-x_low.onnx", name: "Riccardo (m)", size: "25 MB"),
        ],
    ]

    static func short(_ code: String) -> String { String(code.prefix(2)).lowercased() }
    static func voices(for code: String) -> [Voice] { catalog[short(code)] ?? [] }

    // Cache tag so neural audio never collides with Apple-rendered files.
    static func tag(for voice: Voice) -> String {
        String(voice.package.map { ($0.isLetter || $0.isNumber) ? $0 : "_" })
    }

    // MARK: on-disk layout (shared cache, sibling to whisper-models)

    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/sherpa-tts", isDirectory: true)
    static let modelsDir = root.appendingPathComponent("models", isDirectory: true)

    static let version = "1.13.3"   // pinned so download URLs stay stable
    #if arch(arm64)
    static let arch = "osx-arm64"
    #else
    static let arch = "osx-x64"
    #endif
    static var binaryStem: String { "sherpa-onnx-v\(version)-\(arch)-shared" }
    static var binaryDir: URL { root.appendingPathComponent(binaryStem, isDirectory: true) }
    static var binaryURL: URL { binaryDir.appendingPathComponent("bin/sherpa-onnx-offline-tts") }
    static var libDir: URL { binaryDir.appendingPathComponent("lib", isDirectory: true) }

    static func modelDir(_ voice: Voice) -> URL {
        modelsDir.appendingPathComponent(voice.package, isDirectory: true)
    }
    static func isBinaryInstalled() -> Bool {
        FileManager.default.isExecutableFile(atPath: binaryURL.path)
    }
    static func isModelInstalled(_ voice: Voice) -> Bool {
        FileManager.default.fileExists(atPath: modelDir(voice).appendingPathComponent(voice.model).path)
    }

    // MARK: render

    // Render `text` with `voice` to `outURL` (WAV bytes, any extension). The
    // subprocess runs off the main actor. Returns false on any failure so the
    // caller can fall back.
    nonisolated static func render(_ text: String, voice: Voice, speed: Double, to outURL: URL) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isBinaryInstalled(), isModelInstalled(voice) else { return false }
        let dir = modelDir(voice)
        return await Task.detached(priority: .userInitiated) {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("flt-tts-\(UUID().uuidString).wav")
            let p = Process()
            p.executableURL = binaryURL
            p.arguments = [
                "--vits-model=\(dir.appendingPathComponent(voice.model).path)",
                "--vits-tokens=\(dir.appendingPathComponent("tokens.txt").path)",
                "--vits-data-dir=\(dir.appendingPathComponent("espeak-ng-data").path)",
                "--sid=\(voice.sid)",
                "--speed=\(String(format: "%.2f", speed))",
                "--num-threads=2",
                "--output-filename=\(tmp.path)",
                trimmed,
            ]
            var env = ProcessInfo.processInfo.environment
            env["DYLD_LIBRARY_PATH"] = libDir.path   // resolve the bundled dylibs
            p.environment = env
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch { return false }
            _ = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: tmp.path)
            else { return false }
            ContentCache.ensureParent(outURL)
            try? FileManager.default.removeItem(at: outURL)
            return (try? FileManager.default.moveItem(at: tmp, to: outURL)) != nil
        }.value
    }

    // MARK: downloads

    static func binaryDownloadURL() -> URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/v\(version)/\(binaryStem).tar.bz2")!
    }
    static func modelDownloadURL(_ voice: Voice) -> URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/\(voice.package).tar.bz2")!
    }

    static func downloadBinary() async throws {
        try await downloadAndExtract(from: binaryDownloadURL(), into: root)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryURL.path)
        clearQuarantine(binaryDir)   // unsigned binary: keep Gatekeeper from killing it
    }
    static func downloadModel(_ voice: Voice) async throws {
        try await downloadAndExtract(from: modelDownloadURL(voice), into: modelsDir)
    }

    private static func downloadAndExtract(from url: URL, into dest: URL) async throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
        let archive = tmp.appendingPathExtension("tar.bz2")   // give tar an extension to sniff
        try? FileManager.default.removeItem(at: archive)
        try FileManager.default.moveItem(at: tmp, to: archive)
        defer { try? FileManager.default.removeItem(at: archive) }
        try run("/usr/bin/tar", ["-xjf", archive.path, "-C", dest.path], TTSError.extractFailed)
    }

    private static func clearQuarantine(_ dir: URL) {
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dir.path], nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String], _ failure: Error?) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0, let failure { throw failure }
        return p.terminationStatus
    }

    enum TTSError: LocalizedError {
        case extractFailed
        var errorDescription: String? {
            switch self {
            case .extractFailed: return "failed to extract archive"
            }
        }
    }
}
