import Foundation

// The authority for per-word user progress: view counts and self-rated knowledge,
// keyed by concept id + language (knowing a word in Spanish is independent from French).
// Persists to its own JSON under ~/.config, mirroring AppSettings' IO. Callers read and
// mutate only through this contract; the dict, file, and key shape stay private.
@MainActor
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()

    @Published private(set) var byKey: [String: WordProgress]

    private static let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/friendly_lang_tutor", isDirectory: true)
    private static let fileURL = dir.appendingPathComponent("progress.json")

    private init() { byKey = Self.load() }

    func progress(id: String, lang: String) -> WordProgress { byKey[key(id, lang)] ?? WordProgress() }

    // A manual view ("he clicked"): bump the count for this concept.
    func recordShown(id: String, lang: String) {
        var p = progress(id: id, lang: lang)
        p.shown += 1
        byKey[key(id, lang)] = p
        save()
    }

    func setLevel(_ level: Knowledge, id: String, lang: String) {
        var p = progress(id: id, lang: lang)
        p.level = level
        byKey[key(id, lang)] = p
        save()
    }

    private func key(_ id: String, _ lang: String) -> String { "\(lang)/\(id)" }

    private static func load() -> [String: WordProgress] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: WordProgress].self, from: data) else { return [:] }
        return decoded
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(byKey)
            try data.write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("progress save failed: \(error.localizedDescription)")
        }
    }
}
