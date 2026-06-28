import Foundation

struct WhisperModel: Identifiable, Hashable {
    let name: String
    let size: String
    let info: String
    var id: String { name }
}

// Shares the on-disk cache at ~/.cache/whisper-models with the user's `srt` recipe
// and the swift-learn-lang reference, so a model already pulled by either is reused
// as-is. ModelResolver additionally links in OpenSuperWhisper's copy before falling
// back to a download.
enum WhisperModels {
    static let catalog: [WhisperModel] = [
        .init(name: "tiny",           size: "39 MB",  info: "fastest, multilingual"),
        .init(name: "base",           size: "74 MB",  info: "small + balanced"),
        .init(name: "small",          size: "244 MB", info: "good quality"),
        .init(name: "medium",         size: "769 MB", info: "better quality, slower"),
        .init(name: "large-v3",       size: "1.5 GB", info: "best quality, slowest"),
        .init(name: "large-v3-turbo", size: "1.6 GB", info: "near-large quality, much faster"),
    ]

    static let modelsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/whisper-models", isDirectory: true)

    static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    static func path(for name: String) -> URL {
        modelsDir.appendingPathComponent("ggml-\(name).bin")
    }

    static func isDownloaded(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: path(for: name).path)
    }

    static func downloadURL(for name: String) -> URL {
        URL(string: "\(baseURL)/ggml-\(name).bin")!
    }

    static func download(_ name: String) async throws {
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        let (tmpURL, response) = try await URLSession.shared.download(from: downloadURL(for: name))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let dest = path(for: name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmpURL, to: dest)
    }
}

enum ModelResolver {
    // OpenSuperWhisper keeps its (non-sandboxed) models here.
    private static let openSuperWhisperDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models",
            isDirectory: true)

    // whisper ggml magic on disk: uint32 0x67676d6c written little-endian.
    private static let ggmlMagic = Data([0x6c, 0x6d, 0x67, 0x67])

    // Ensure ggml-<name>.bin is in our shared cache, reusing a sibling copy before
    // any download. Returns true if the model is present afterward.
    @discardableResult
    static func ensureAvailable(_ name: String) -> Bool {
        let fm = FileManager.default
        let dest = WhisperModels.path(for: name)
        if fm.fileExists(atPath: dest.path) { return true }

        let source = openSuperWhisperDir.appendingPathComponent("ggml-\(name).bin")
        guard fm.fileExists(atPath: source.path), isGGML(source) else { return false }

        try? fm.createDirectory(at: WhisperModels.modelsDir, withIntermediateDirectories: true)
        // Hardlink shares disk blocks on the same volume; symlink across volumes.
        if (try? fm.linkItem(at: source, to: dest)) != nil { return true }
        try? fm.createSymbolicLink(at: dest, withDestinationURL: source)
        return fm.fileExists(atPath: dest.path)
    }

    private static func isGGML(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4)) ?? Data()
        return head == ggmlMagic
    }
}
