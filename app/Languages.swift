import Foundation

struct Language: Identifiable, Hashable {
    let code: String   // whisper -l code, also the AVSpeech/TTS language prefix
    let name: String
    var id: String { code }
}

// Languages offered in the pickers. Codes are the ones whisper-cli accepts via -l.
enum Languages {
    static let catalog: [Language] = [
        .init(code: "es", name: "Spanish"),
        .init(code: "en", name: "English"),
        .init(code: "de", name: "German"),
        .init(code: "fr", name: "French"),
        .init(code: "it", name: "Italian"),
    ]

    static func name(for code: String) -> String {
        catalog.first { $0.code == code }?.name ?? code
    }
}
