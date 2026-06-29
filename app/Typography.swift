import SwiftUI

// The app's only text sizes. Every piece of text picks one of these three roles; the
// concrete pixel size per role lives in AppSettings and is user-adjustable. This enum
// is the role catalog only - it knows each role's default size and adjustable range,
// nothing about storage or SwiftUI.
enum AppText: String, CaseIterable, Identifiable {
    case title, normal, small

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var defaultSize: Double {
        switch self {
        case .title: return 24
        case .normal: return 15
        case .small: return 12
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .title: return 16...44
        case .normal: return 11...26
        case .small: return 9...20
        }
    }
}

// The single authority that turns a role into a Font (reading the live size from
// settings) plus the binding the size steppers edit. Kept in the UI layer as an
// extension so AppSettings itself stays free of SwiftUI.
extension AppSettings {
    func font(_ role: AppText, weight: Font.Weight = .regular) -> Font {
        .system(size: fontSize(role), weight: weight)
    }

    func fontBinding(_ role: AppText) -> Binding<Double> {
        Binding(get: { self.fontSize(role) }, set: { self.setFontSize($0, for: role) })
    }
}

// Applies a role's font and re-renders when its size changes in Settings.
private struct AppFontModifier: ViewModifier {
    @ObservedObject private var settings = AppSettings.shared
    let role: AppText
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(settings.font(role, weight: weight))
    }
}

extension View {
    func appFont(_ role: AppText, weight: Font.Weight = .regular) -> some View {
        modifier(AppFontModifier(role: role, weight: weight))
    }
}
