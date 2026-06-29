import SwiftUI

// Browse the full shared vocabulary for the current language: every base concept as
// target word <-> native meaning, searchable and grouped by category, with each word's
// progress (level dot + view count). Tapping a word loads it into the Words pane; the
// speaker plays it. Embedded in the Words pane - depends only on data + two closures.
struct AllWordsView: View {
    let entries: [VocabEntry]
    let speak: (String) -> Void
    let select: (VocabEntry) -> Void

    @ObservedObject private var progressStore = ProgressStore.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var query = ""
    @State private var tier: BaseWord.Tier? = nil   // nil = all tiers

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            TextField("Search words or meanings", text: $query)
                .textFieldStyle(.roundedBorder).appFont(.normal)
            Text("\(filtered.count)").appFont(.small).foregroundStyle(.secondary)
            Picker("", selection: $tier) {
                Text("All").tag(BaseWord.Tier?.none)
                ForEach(BaseWord.Tier.allCases) { Text($0.label).tag(BaseWord.Tier?.some($0)) }
            }
            .labelsHidden().frame(width: 130)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            Spacer()
            Text(entries.isEmpty ? "No words for this language yet." : "No matches.")
                .appFont(.small).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
            Spacer()
        } else {
            List {
                ForEach(grouped, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.items) { row($0) }
                    }
                }
            }
        }
    }

    private func row(_ e: VocabEntry) -> some View {
        let p = progressStore.progress(id: e.id, lang: settings.targetLanguage)
        return HStack(spacing: 12) {
            Circle().fill(KnowledgeControls.color(p.level)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.target).appFont(.normal)
                Text(e.native).appFont(.small).foregroundStyle(.secondary)
            }
            Spacer()
            if p.shown > 0 {
                Text("seen \(p.shown)x").appFont(.small).foregroundStyle(.secondary)
            }
            Button { speak(e.target) } label: { Image(systemName: "speaker.wave.2").appFont(.small) }
                .buttonStyle(.borderless).pointingHand().help("Play")
        }
        .contentShape(Rectangle())
        .onTapGesture { select(e) }
        .pointingHand()
    }

    // Filter by tier + a diacritic/case-insensitive match on either side.
    private var filtered: [VocabEntry] {
        entries.filter { e in
            (tier == nil || e.tier == tier)
            && (query.isEmpty
                || e.target.localizedStandardContains(query)
                || e.native.localizedStandardContains(query))
        }
    }

    // Group by category, preserving the base order so meaningful sequences stay intact
    // (numbers 1-15, days Mon-Sun, months Jan-Dec) instead of being scrambled alphabetically.
    private var grouped: [(category: String, items: [VocabEntry])] {
        var order: [String] = []
        var byCat: [String: [VocabEntry]] = [:]
        for e in filtered {
            if byCat[e.category] == nil { order.append(e.category) }
            byCat[e.category, default: []].append(e)
        }
        return order.map { (category: $0, items: byCat[$0] ?? []) }
    }
}
