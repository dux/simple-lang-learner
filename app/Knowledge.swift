import Foundation

// How well the user knows a word - their self-rated recall, lowest to highest. A new
// word defaults to `.remind` (in the review pool) until rated up. Pure model: the label
// and icon are here; the color mapping lives in the view layer (KnowledgeControls).
enum Knowledge: String, Codable, CaseIterable, Identifiable {
    case remind, okish, known

    var id: String { rawValue }

    var label: String {
        switch self {
        case .remind: return "Remind me"
        case .okish:  return "OK-ish"
        case .known:  return "I know"
        }
    }

    var icon: String {
        switch self {
        case .remind: return "exclamationmark.circle"
        case .okish:  return "circle.lefthalf.filled"
        case .known:  return "checkmark.circle"
        }
    }
}

// One word's user progress: how many times it was opened on demand, and the self-rating.
struct WordProgress: Codable {
    var shown: Int = 0
    var level: Knowledge = .remind   // default: a new word stays in the review pool until rated up
}
