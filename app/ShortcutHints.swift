import AppKit
import SwiftUI

enum AppTab: Hashable { case words, chat }

// Hold Cmd for a moment to see the shortcuts available on the current tab (like the
// iPadOS hold-Cmd HUD). Any keyDown while Cmd is held cancels the pending show, so
// normal Cmd-combo usage never flashes it.
@MainActor
final class ShortcutHints: ObservableObject {
    static let shared = ShortcutHints()

    @Published var visible = false
    @Published var tab: AppTab = .words

    private var pending: Task<Void, Never>?
    private var monitor: Any?

    private init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if event.type == .keyDown {
                    self.pending?.cancel()
                    self.pending = nil
                } else {
                    self.flagsChanged(event.modifierFlags)
                }
            }
            return event   // observe only, never consume
        }
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                   object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        if flags.intersection(.deviceIndependentFlagsMask) == .command {
            guard !visible, pending == nil else { return }
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                self?.visible = true
            }
        } else {
            hide()
        }
    }

    private func hide() {
        pending?.cancel()
        pending = nil
        visible = false
    }
}

// The HUD itself: keycap + description rows for the active tab.
struct ShortcutHintsOverlay: View {
    let tab: AppTab

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch tab {
            case .words:
                row("⌘R", "Replay word slowly")
                row("⌘1-3", "Say sentence slowly")
                row("↩", "Next random word")
            case .chat:
                row("↩", "Send message")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 6, y: 2)
        .allowsHitTesting(false)
    }

    private func row(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 10) {
            Text(keys)
                .appFont(.small, weight: .semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(minWidth: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(label).appFont(.small)
        }
    }
}
