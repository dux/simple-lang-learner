import Foundation
import CryptoKit

// Disposable on-disk cache for generated text and rendered audio. Lives under
// ~/Library/Caches/<bundle-id>/ so it is safe to purge and easy to find for
// cleaning. Paths are content-addressed by a short hash of the word.
enum ContentCache {
    static let root: URL = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.dux.friendly-lang-tutor", isDirectory: true)

    private static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // Generated content (flat line format).
    static func textURL(pair: String, word: String, style: String) -> URL {
        root.appendingPathComponent("text/\(pair)/\(hash(word))/\(style).txt")
    }

    // Rendered speech, content-addressed by the exact text plus the voice and speed
    // that produced it. Any identical utterance is reused across words, sentences,
    // languages, and pairs, and a voice or speed change never serves stale audio.
    static func audioURL(text: String, lang: String, voice: String, ratePct: Int) -> URL {
        root.appendingPathComponent("audio/\(hash(text)).\(lang).\(voice).\(ratePct).caf")
    }

    static func loadText(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    static func saveText(_ text: String, to url: URL) {
        ensureParent(url)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func ensureParent(_ url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: root)
    }

    static func sizeBytes() -> Int64 {
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
