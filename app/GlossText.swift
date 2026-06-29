import SwiftUI

// Renders a segmented gloss inline: each foreign chunk in primary (tappable to hear just
// that chunk) and its "(meaning)" muted + italic (not tappable). Shared by the Words tab
// and the Chat tab so a tutor reply breaks down exactly like an example sentence.
struct GlossText: View {
    @ObservedObject private var settings = AppSettings.shared
    let parts: [Segment]
    var role: AppText = .small
    let speak: (Segment) -> Void

    private var font: Font { settings.font(role) }

    var body: some View {
        Text(attributed)
            .font(font)
            .tint(.primary)
            .pointingHand()
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "fltgloss",
                      let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let p = comps.queryItems?.first(where: { $0.name == "p" })?.value, let i = Int(p),
                      parts.indices.contains(i) else { return .systemAction }
                speak(parts[i])
                return .handled
            })
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for (i, seg) in parts.enumerated() {
            var chunk = AttributedString(seg.text)
            chunk.foregroundColor = .primary
            if let url = url(for: i) { chunk.link = url }
            result += chunk
            if let tr = seg.translation, !tr.isEmpty {
                var meaning = AttributedString(" (\(tr))")
                meaning.foregroundColor = .secondary
                meaning.font = font.italic()
                result += meaning
            }
            result += AttributedString(" ")
        }
        return result
    }

    // A custom-scheme URL identifying a chunk by its index, intercepted above so a tap
    // speaks just that chunk.
    private func url(for part: Int) -> URL? {
        var comps = URLComponents()
        comps.scheme = "fltgloss"
        comps.host = "speak"
        comps.queryItems = [URLQueryItem(name: "p", value: String(part))]
        return comps.url
    }
}
