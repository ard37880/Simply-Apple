import SwiftUI
import UIKit

// MARK: - Khaki brand palette
//
// The warm "khaki" light theme mirrors the Android app and the website:
// background paper #F7F3E8, cards/surfaces #FFFDF6, ink #152418,
// primary green #1B5E20, deep green #0E3B13, accent yellow #FDE898,
// hairlines #D8D2BE. In dark mode these fall back to system colors so the
// app reads exactly as it did before.

extension Color {
    /// Warm "paper" page background — khaki in light, system in dark.
    static let simplyPaper = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.systemBackground
            : UIColor(red: 0xF7 / 255, green: 0xF3 / 255, blue: 0xE8 / 255, alpha: 1)
    })

    /// Card / raised surface — soft cream in light, elevated system in dark.
    static let simplyCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground
            : UIColor(red: 0xFF / 255, green: 0xFD / 255, blue: 0xF6 / 255, alpha: 1)
    })

    /// Text-link green: dark enough for AA contrast on khaki paper in
    /// light mode (matches Android's primary), lighter in dark mode.
    static let simplyLink = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x1B/255, green: 0x8E/255, blue: 0x3E/255, alpha: 1)
            : UIColor(red: 0x1B/255, green: 0x5E/255, blue: 0x20/255, alpha: 1)
    })

    /// Hairline / divider tone for the khaki theme.
    static let simplyHairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.separator
            : UIColor(red: 0xD8 / 255, green: 0xD2 / 255, blue: 0xBE / 255, alpha: 1)
    })
}

// MARK: - Appearance setting

/// App appearance choice, persisted via ProfileStore (@AppStorage).
/// Feature-identical with the Android "Light / Dark / System" control.
enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// The color scheme to force. `nil` follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// Older releases stored the light theme as "khaki"; treat the legacy
    /// value (and anything unknown) as light so saved preferences keep working.
    static func from(_ raw: String) -> Appearance { Appearance(rawValue: raw) ?? .light }
}

extension View {
    /// Paper page background for a top-level screen in the khaki theme.
    func simplyScreenBackground() -> some View {
        background(Color.simplyPaper.ignoresSafeArea())
    }

    /// Navigation bars sit directly on the paper background; the system bar
    /// material would otherwise render a slightly different shade in light
    /// mode. `simplyPaper` is adaptive, so dark mode is unaffected.
    func simplyToolbarBackground() -> some View {
        self
            .toolbarBackground(Color.simplyPaper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
