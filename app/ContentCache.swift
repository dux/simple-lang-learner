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

    // Headword spoken alone - reusable across styles, keyed by voice + speed.
    static func wordAudioURL(pair: String, word: String, voice: String, ratePct: Int) -> URL {
        root.appendingPathComponent("audio/\(pair)/\(hash(word))/word.\(voice).\(ratePct).caf")
    }

    // A whole sentence spoken - tied to one style + index + language + speed.
    static func sentenceAudioURL(pair: String, word: String, style: String,
                                 index: Int, lang: String, ratePct: Int) -> URL {
        root.appendingPathComponent("audio/\(pair)/\(hash(word))/\(style)/\(index).\(lang).\(ratePct).caf")
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
