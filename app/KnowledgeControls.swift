import SwiftUI

// Three self-rating buttons - Remind me / OK-ish / I know - that report the chosen level;
// the current one is highlighted in its color. Shared by the Words panel (interactive)
// and the All Words list (where it shows the level read-only). This is the single place
// that maps a Knowledge level to a color.
struct KnowledgeControls: View {
    let level: Knowledge
    var labelled = true                 // false -> icon-only (compact, for list rows)
    let choose: (Knowledge) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Knowledge.allCases) { k in
                Button { choose(k) } label: {
                    if labelled {
                        Label(k.label, systemImage: k.icon).appFont(.small)
                    } else {
                        Image(systemName: k.icon).appFont(.small)
                    }
                }
                .buttonStyle(.borderless)
                .pointingHand()
                .foregroundStyle(level == k ? Self.color(k) : .secondary)
                .help(k.label)
            }
        }
    }

    static func color(_ k: Knowledge) -> Color {
        switch k {
        case .remind: return .orange
        case .okish:  return .yellow
        case .known:  return .green
        }
    }
}
