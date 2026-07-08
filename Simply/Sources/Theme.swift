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

    /// Hairline / divider tone for the khaki theme.
    static let simplyHairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.separator
            : UIColor(red: 0xD8 / 255, green: 0xD2 / 255, blue: 0xBE / 255, alpha: 1)
    })
}

// MARK: - Appearance setting

/// App appearance choice, persisted via ProfileStore (@AppStorage).
/// Feature-identical with the Android "Khaki / Dark / System" control.
enum Appearance: String, CaseIterable, Identifiable {
    case khaki, dark, system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .khaki: return "Khaki"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// The color scheme to force. `nil` follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .khaki: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    static func from(_ raw: String) -> Appearance { Appearance(rawValue: raw) ?? .khaki }
}

extension View {
    /// Paper page background for a top-level screen in the khaki theme.
    func simplyScreenBackground() -> some View {
        background(Color.simplyPaper.ignoresSafeArea())
    }
}
