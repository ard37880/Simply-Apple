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
    /// Opaque sRGB color from a 0xRRGGBB literal, so the theme tables can
    /// carry the exact hex values from the Android palette.
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }

    /// Warm "paper" page background: khaki in light, system in dark, or
    /// the active theme preset's paper when one is selected.
    static var simplyPaper: Color {
        presetFor(ProfileStore.shared.appearance)?.paper ?? khakiPaper
    }
    private static let khakiPaper = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.systemBackground
            : UIColor(red: 0xF7 / 255, green: 0xF3 / 255, blue: 0xE8 / 255, alpha: 1)
    })

    /// Card / raised surface: soft cream in light, elevated system in dark.
    static var simplyCard: Color {
        presetFor(ProfileStore.shared.appearance)?.card ?? khakiCard
    }
    private static let khakiCard = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.secondarySystemBackground
            : UIColor(red: 0xFF / 255, green: 0xFD / 255, blue: 0xF6 / 255, alpha: 1)
    })

    /// Text-link green: dark enough for AA contrast on khaki paper in
    /// light mode (matches Android's primary), lighter in dark mode.
    /// A theme preset swaps in its own accent.
    static var simplyLink: Color {
        presetFor(ProfileStore.shared.appearance)?.accent ?? khakiLink
    }
    private static let khakiLink = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x1B/255, green: 0x8E/255, blue: 0x3E/255, alpha: 1)
            : UIColor(red: 0x1B/255, green: 0x5E/255, blue: 0x20/255, alpha: 1)
    })

    /// Hairline / divider tone for the khaki theme.
    static var simplyHairline: Color {
        presetFor(ProfileStore.shared.appearance)?.outlineSoft ?? khakiHairline
    }
    private static let khakiHairline = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.separator
            : UIColor(red: 0xD8 / 255, green: 0xD2 / 255, blue: 0xBE / 255, alpha: 1)
    })
}

// MARK: - Theme presets

/// A selected premium theme is stored as "theme:<id>"; an id that no longer
/// exists falls back to the light brand palette.
let appearanceThemePrefix = "theme:"

/// A hand-tuned premium theme. Every pairing (text on paper, label on
/// button, accent as link text) is pre-checked against WCAG 4.5:1, which is
/// why themes are curated palettes rather than free-form color pickers.
/// Score and risk colors are deliberately not themeable: green/yellow/red
/// carry meaning. Ids, labels, and hex values match Android exactly.
struct ThemePreset: Identifiable {
    let id: String
    let label: String
    let dark: Bool
    let accent: Color
    let onAccent: Color
    let accentContainer: Color
    let onAccentContainer: Color
    let paper: Color
    let ink: Color
    let card: Color
    let soft: Color
    let softInk: Color
    let outline: Color
    let outlineSoft: Color
}

let themePresets: [ThemePreset] = [
    ThemePreset(
        id: "ocean", label: "Ocean", dark: false,
        accent: Color(rgb: 0x0E5A8A), onAccent: .white,
        accentContainer: Color(rgb: 0xCFE5F4), onAccentContainer: Color(rgb: 0x063A5C),
        paper: Color(rgb: 0xF2F6F9), ink: Color(rgb: 0x14232D),
        card: Color(rgb: 0xFCFDFE), soft: Color(rgb: 0xE1EAF1), softInk: Color(rgb: 0x4A5A66),
        outline: Color(rgb: 0x9FB1BE), outlineSoft: Color(rgb: 0xC8D4DD)),
    ThemePreset(
        id: "blush", label: "Blush", dark: false,
        accent: Color(rgb: 0xB2124F), onAccent: .white,
        accentContainer: Color(rgb: 0xF8D3DF), onAccentContainer: Color(rgb: 0x6B0A30),
        paper: Color(rgb: 0xFBF1F3), ink: Color(rgb: 0x331821),
        card: Color(rgb: 0xFFFCFD), soft: Color(rgb: 0xF3DFE5), softInk: Color(rgb: 0x6E5560),
        outline: Color(rgb: 0xC4A6B0), outlineSoft: Color(rgb: 0xE2CBD3)),
    ThemePreset(
        id: "lavender", label: "Lavender", dark: false,
        accent: Color(rgb: 0x6247AA), onAccent: .white,
        accentContainer: Color(rgb: 0xE5DBF6), onAccentContainer: Color(rgb: 0x3A2A68),
        paper: Color(rgb: 0xF5F2FA), ink: Color(rgb: 0x221B33),
        card: Color(rgb: 0xFDFCFF), soft: Color(rgb: 0xE9E3F4), softInk: Color(rgb: 0x5A5268),
        outline: Color(rgb: 0xABA1C0), outlineSoft: Color(rgb: 0xD4CCE4)),
    ThemePreset(
        id: "mint", label: "Mint", dark: false,
        accent: Color(rgb: 0x0B7154), onAccent: .white,
        accentContainer: Color(rgb: 0xCDEEDF), onAccentContainer: Color(rgb: 0x06442F),
        paper: Color(rgb: 0xEFF7F2), ink: Color(rgb: 0x12271C),
        card: Color(rgb: 0xFBFEFC), soft: Color(rgb: 0xDFEEE5), softInk: Color(rgb: 0x4A5F53),
        outline: Color(rgb: 0x9DB6A8), outlineSoft: Color(rgb: 0xC9DBD0)),
    ThemePreset(
        id: "sunset", label: "Sunset", dark: false,
        accent: Color(rgb: 0xB84A21), onAccent: .white,
        accentContainer: Color(rgb: 0xF9DACB), onAccentContainer: Color(rgb: 0x6E2A0E),
        paper: Color(rgb: 0xFDF4EE), ink: Color(rgb: 0x2F1E12),
        card: Color(rgb: 0xFFFDFB), soft: Color(rgb: 0xF5E3D7), softInk: Color(rgb: 0x6B5546),
        outline: Color(rgb: 0xC4A78F), outlineSoft: Color(rgb: 0xE2CDBC)),
    ThemePreset(
        id: "midnight", label: "Midnight", dark: true,
        accent: Color(rgb: 0x63A4FF), onAccent: Color(rgb: 0x04234E),
        accentContainer: Color(rgb: 0x1E3A66), onAccentContainer: Color(rgb: 0xC8DCFF),
        paper: Color(rgb: 0x0E1420), ink: Color(rgb: 0xE6ECF5),
        card: Color(rgb: 0x17202F), soft: Color(rgb: 0x1C2637), softInk: Color(rgb: 0xA8B4C8),
        outline: Color(rgb: 0x55637A), outlineSoft: Color(rgb: 0x333F53)),
    ThemePreset(
        id: "graphite", label: "Graphite", dark: true,
        accent: Color(rgb: 0xFF9A57), onAccent: Color(rgb: 0x3A1D04),
        accentContainer: Color(rgb: 0x5A2F10), onAccentContainer: Color(rgb: 0xFFD9BE),
        paper: Color(rgb: 0x151719), ink: Color(rgb: 0xECEDEE),
        card: Color(rgb: 0x1F2226), soft: Color(rgb: 0x26292E), softInk: Color(rgb: 0xAEB4BB),
        outline: Color(rgb: 0x5E656D), outlineSoft: Color(rgb: 0x3A3F45)),
    ThemePreset(
        id: "evergreen", label: "Evergreen", dark: true,
        accent: Color(rgb: 0x3FCF8C), onAccent: Color(rgb: 0x00301B),
        accentContainer: Color(rgb: 0x0E4D31), onAccentContainer: Color(rgb: 0xB5F2D3),
        paper: Color(rgb: 0x0F1B15), ink: Color(rgb: 0xE2EFE6),
        card: Color(rgb: 0x16241D), soft: Color(rgb: 0x1C2E24), softInk: Color(rgb: 0xA3BCAC),
        outline: Color(rgb: 0x4E6A59), outlineSoft: Color(rgb: 0x2C4034)),
    ThemePreset(
        id: "plum", label: "Plum", dark: true,
        accent: Color(rgb: 0xC79BF2), onAccent: Color(rgb: 0x33115C),
        accentContainer: Color(rgb: 0x4A2B73), onAccentContainer: Color(rgb: 0xEBD9FF),
        paper: Color(rgb: 0x171020), ink: Color(rgb: 0xEDE5F7),
        card: Color(rgb: 0x211831), soft: Color(rgb: 0x291F3A), softInk: Color(rgb: 0xB5A8C9),
        outline: Color(rgb: 0x6A5C82), outlineSoft: Color(rgb: 0x40345A)),
    ThemePreset(
        id: "steel", label: "Steel", dark: true,
        accent: Color(rgb: 0x6FC7D9), onAccent: Color(rgb: 0x003239),
        accentContainer: Color(rgb: 0x0F4A56), onAccentContainer: Color(rgb: 0xC2ECF4),
        paper: Color(rgb: 0x121619), ink: Color(rgb: 0xE8EDEF),
        card: Color(rgb: 0x1B2126), soft: Color(rgb: 0x212930), softInk: Color(rgb: 0xA9B6BD),
        outline: Color(rgb: 0x5A6A72), outlineSoft: Color(rgb: 0x354048)),
]

/// The preset a stored appearance value points at, or nil for the three
/// standard modes (and for stale ids from removed presets).
func presetFor(_ appearance: String) -> ThemePreset? {
    guard appearance.hasPrefix(appearanceThemePrefix) else { return nil }
    let id = String(appearance.dropFirst(appearanceThemePrefix.count))
    return themePresets.first { $0.id == id }
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

    /// The color scheme a stored appearance value forces. A theme preset
    /// forces its own light or dark so the status bar text stays readable:
    /// a dark preset on a light-mode phone otherwise shows an unreadable
    /// dark-on-dark clock.
    static func colorScheme(for raw: String) -> ColorScheme? {
        if let preset = presetFor(raw) { return preset.dark ? .dark : .light }
        return from(raw).colorScheme
    }
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
