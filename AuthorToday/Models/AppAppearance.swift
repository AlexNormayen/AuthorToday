import SwiftUI
import Combine
import UIKit

enum AppColorMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum ThemeChromeInk: String, Sendable {
    /// Dark labels on pale / soft grounds (Мох, Бумага, Океан…).
    case onLight
    /// Light labels on dark / busy photos (Песок, Неон, Сорвиголова…).
    case onDark
}

enum AppThemePreset: String, CaseIterable, Identifiable, Codable {
    case moss
    /// Official Author.Today site colors (accent #4582af).
    case authorToday
    /// Calm free themes — flat wash, high contrast for lists.
    case paper
    case cloud
    case stone
    case ocean
    case wine
    case graphite
    case sand
    // Futuristic
    case neon
    case plasma
    case orbit
    case hologram
    case ion
    // Сорвиголова — 10 фото-фонов
    case ddRooftop
    case ddSilhouette
    case ddLeap
    case ddRain
    case ddShadow
    case ddRadar
    case ddBatons
    case ddCourt
    case ddEscape
    case ddFabric
    case custom

    var id: String { rawValue }

    /// Legacy theme keys from earlier builds.
    static func resolved(rawValue: String?) -> AppThemePreset {
        guard let raw = rawValue, !raw.isEmpty else { return .moss }
        switch raw {
        case "daredevil": return .ddLeap
        case "hellsKitchen": return .ddShadow
        case "murdock": return .ddRain
        case "at", "author.today", "site": return .authorToday
        default:
            return AppThemePreset(rawValue: raw) ?? .moss
        }
    }

    var isDaredevilFamily: Bool {
        switch self {
        case .ddRooftop, .ddSilhouette, .ddLeap, .ddRain, .ddShadow,
             .ddRadar, .ddBatons, .ddCourt, .ddEscape, .ddFabric:
            return true
        default:
            return false
        }
    }

    var isFuturisticFamily: Bool {
        switch self {
        case .neon, .plasma, .orbit, .hologram, .ion: return true
        default: return false
        }
    }

    /// Flat, low-contrast-photo themes meant for comfortable browsing.
    var isCalmFamily: Bool {
        switch self {
        case .paper, .cloud, .stone, .authorToday: return true
        default: return false
        }
    }

    var title: String {
        switch self {
        case .moss: return "Мох"
        case .authorToday: return "Author.Today"
        case .paper: return "Бумага"
        case .cloud: return "Облако"
        case .stone: return "Камень"
        case .ocean: return "Океан"
        case .wine: return "Вино"
        case .graphite: return "Графит"
        case .sand: return "Песок"
        case .neon: return "Неон"
        case .plasma: return "Плазма"
        case .orbit: return "Орбита"
        case .hologram: return "Голограмма"
        case .ion: return "Ион"
        case .ddRooftop: return "Крыша"
        case .ddSilhouette: return "Силуэт"
        case .ddLeap: return "Прыжок"
        case .ddRain: return "Дождь"
        case .ddShadow: return "Тень"
        case .ddRadar: return "Радар"
        case .ddBatons: return "Дубинки"
        case .ddCourt: return "Суд"
        case .ddEscape: return "Лестница"
        case .ddFabric: return "Багрянец"
        case .custom: return "Свой цвет"
        }
    }

    var accent: Color {
        switch self {
        case .moss: return Color(red: 0.18, green: 0.42, blue: 0.36)
        // Site brand / theme-color tile: #4582af
        case .authorToday: return Color(red: 0.271, green: 0.510, blue: 0.686)
        case .paper: return Color(red: 0.22, green: 0.25, blue: 0.28) // ink
        case .cloud: return Color(red: 0.32, green: 0.45, blue: 0.55) // soft steel
        case .stone: return Color(red: 0.38, green: 0.40, blue: 0.44) // slate
        case .ocean: return Color(red: 0.14, green: 0.35, blue: 0.55)
        case .wine: return Color(red: 0.55, green: 0.18, blue: 0.28)
        case .graphite: return Color(red: 0.35, green: 0.38, blue: 0.42)
        case .sand: return Color(red: 0.62, green: 0.48, blue: 0.30)
        case .neon: return Color(red: 0.00, green: 0.90, blue: 0.95)
        case .plasma: return Color(red: 0.55, green: 0.20, blue: 1.00)
        case .orbit: return Color(red: 0.20, green: 0.45, blue: 1.00)
        case .hologram: return Color(red: 0.25, green: 0.95, blue: 0.75)
        case .ion: return Color(red: 0.70, green: 0.85, blue: 1.00)
        case .ddRooftop: return Color(red: 0.72, green: 0.08, blue: 0.12)
        case .ddSilhouette: return Color(red: 0.85, green: 0.10, blue: 0.14)
        case .ddLeap: return Color(red: 0.78, green: 0.09, blue: 0.14)
        case .ddRain: return Color(red: 0.90, green: 0.22, blue: 0.18)
        case .ddShadow: return Color(red: 0.55, green: 0.05, blue: 0.08)
        case .ddRadar: return Color(red: 0.95, green: 0.15, blue: 0.20)
        case .ddBatons: return Color(red: 0.80, green: 0.12, blue: 0.10)
        case .ddCourt: return Color(red: 0.70, green: 0.10, blue: 0.12)
        case .ddEscape: return Color(red: 0.88, green: 0.18, blue: 0.12)
        case .ddFabric: return Color(red: 0.65, green: 0.05, blue: 0.10)
        case .custom: return Color(red: 0.18, green: 0.42, blue: 0.36)
        }
    }

    var mistLight: Color {
        switch self {
        case .moss: return Color(red: 0.93, green: 0.94, blue: 0.93)
        // Site surfaces: #f5f7fa / #fcfcfc
        case .authorToday: return Color(red: 0.961, green: 0.969, blue: 0.980)
        case .paper: return Color(red: 0.975, green: 0.972, blue: 0.965)
        case .cloud: return Color(red: 0.945, green: 0.955, blue: 0.965)
        case .stone: return Color(red: 0.945, green: 0.945, blue: 0.948)
        case .ocean: return Color(red: 0.92, green: 0.95, blue: 0.97)
        case .wine: return Color(red: 0.97, green: 0.93, blue: 0.94)
        case .graphite: return Color(red: 0.94, green: 0.94, blue: 0.95)
        case .sand: return Color(red: 0.96, green: 0.94, blue: 0.90)
        case _ where isFuturisticFamily:
            return Color(red: 0.07, green: 0.09, blue: 0.12)
        case _ where isDaredevilFamily:
            return Color(red: 0.08, green: 0.06, blue: 0.06)
        case .custom: return Color(red: 0.94, green: 0.94, blue: 0.94)
        default: return Color(red: 0.94, green: 0.94, blue: 0.94)
        }
    }

    var mistDark: Color {
        switch self {
        case _ where isDaredevilFamily:
            return Color(red: 0.06, green: 0.04, blue: 0.04)
        case _ where isFuturisticFamily:
            return Color(red: 0.05, green: 0.06, blue: 0.09)
        case .authorToday:
            // Navbar / chrome gray-blue from the site
            return Color(red: 0.16, green: 0.20, blue: 0.24)
        case .paper, .cloud, .stone:
            return Color(red: 0.12, green: 0.13, blue: 0.15)
        default:
            return Color(red: 0.10, green: 0.11, blue: 0.12)
        }
    }

    /// Themes that look best with dark UI chrome.
    var prefersDark: Bool {
        isFuturisticFamily || isDaredevilFamily
    }

    /// Ink on chrome: dark labels on pale flat grounds; light labels on photo / neon.
    var chromeInk: ThemeChromeInk {
        switch self {
        case .authorToday, .paper, .cloud, .stone, .custom:
            return .onLight
        // All photo themes are busy/dark enough that pale plates + dark ink fail
        // (Мох forest, Песок dunes, Океан, Вино, Графит, Futuristic, DD).
        case .moss, .ocean, .sand, .wine, .graphite:
            return .onDark
        case _ where prefersDark:
            return .onDark
        default:
            return .onLight
        }
    }

    /// Soft dark wash over photo themes so list chrome reads without plates (Option A).
    var contentScrimOpacity: Double {
        guard backgroundImageName != nil else { return 0 }
        switch self {
        case .moss, .ocean:
            return 0.46
        case .sand, .wine, .graphite:
            return 0.42
        case _ where prefersDark:
            return 0.38
        default:
            return 0.40
        }
    }

    /// Soft plates / chips / empty-state cards — tinted glass, never system white.
    var chromePanelFill: Color {
        switch self {
        case .moss:
            return Color(red: 0.05, green: 0.13, blue: 0.09).opacity(0.82)
        case .ocean:
            return Color(red: 0.05, green: 0.12, blue: 0.20).opacity(0.80)
        case .authorToday:
            return Color(red: 0.90, green: 0.93, blue: 0.97).opacity(0.92)
        case .paper:
            return Color(red: 0.96, green: 0.95, blue: 0.92).opacity(0.94)
        case .cloud:
            return Color(red: 0.92, green: 0.94, blue: 0.96).opacity(0.92)
        case .stone:
            return Color(red: 0.93, green: 0.93, blue: 0.94).opacity(0.92)
        case .sand:
            return Color(red: 0.14, green: 0.09, blue: 0.05).opacity(0.78)
        case .wine:
            return Color(red: 0.16, green: 0.05, blue: 0.09).opacity(0.80)
        case .graphite:
            return Color(red: 0.09, green: 0.10, blue: 0.12).opacity(0.78)
        case .neon, .plasma, .orbit, .hologram, .ion:
            return Color.white.opacity(0.16)
        case _ where isDaredevilFamily:
            return Color(red: 0.24, green: 0.04, blue: 0.06).opacity(0.72)
        case .custom:
            return Color.primary.opacity(0.08)
        default:
            return Color.primary.opacity(0.07)
        }
    }

    /// Primary labels on themed chrome.
    var chromePrimaryText: Color {
        switch chromeInk {
        case .onDark:
            return Color.white.opacity(0.96)
        case .onLight:
            return Color(red: 0.10, green: 0.12, blue: 0.13)
        }
    }

    /// Small / secondary copy — nearly as bright as primary on scrim themes.
    func chromeSecondaryText(accent: Color) -> Color {
        switch chromeInk {
        case .onDark:
            // Keep a hint of accent, but stay close to white so footnotes aren't muddy.
            return accent.blended(toward: .white, amount: 0.93)
        case .onLight:
            return accent.blended(toward: .black, amount: 0.55)
        }
    }

    func chromePanelHighlight(accent: Color) -> Color {
        switch chromeInk {
        case .onDark:
            return accent.blended(toward: .white, amount: 0.25).opacity(0.55)
        case .onLight:
            return accent.opacity(0.22)
        }
    }

    func chromePanelBorder(accent: Color) -> Color {
        switch chromeInk {
        case .onDark:
            return accent.blended(toward: .white, amount: 0.35).opacity(0.55)
        case .onLight:
            return accent.opacity(0.28)
        }
    }

    func chromePanelShadow(accent: Color) -> Color {
        switch chromeInk {
        case .onDark:
            return Color.black.opacity(0.50)
        case .onLight:
            return accent.opacity(0.22)
        }
    }

    /// Selected segment / chip highlight tint (UIKit).
    var chromeSegmentSelectedUIColor: UIColor {
        let accent = UIColor(self.accent)
        switch self {
        case .moss, .ocean, .sand, .wine, .graphite:
            return accent.withAlphaComponent(0.78)
        case .authorToday, .paper, .cloud, .stone:
            return UIColor.secondarySystemGroupedBackground
        case _ where prefersDark:
            return UIColor.white.withAlphaComponent(0.28)
        case .custom:
            return accent.withAlphaComponent(0.85)
        default:
            return UIColor.secondarySystemGroupedBackground
        }
    }

    var chromeSegmentTrackUIColor: UIColor {
        switch chromeInk {
        case .onLight:
            return UIColor.black.withAlphaComponent(0.10)
        case .onDark:
            return UIColor.black.withAlphaComponent(0.38)
        }
    }

    var chromeSegmentTitleUIColor: UIColor {
        UIColor(chromeSecondaryText(accent: accent))
    }

    /// Hard text outline (contrasts ink) for photo readability without plates.
    func chromeTextOutline(accent: Color) -> Color {
        switch chromeInk {
        case .onDark:
            return accent.blended(toward: .black, amount: 0.82).opacity(0.95)
        case .onLight:
            return accent.blended(toward: .white, amount: 0.88).opacity(0.95)
        }
    }

    /// Outline radius in points (hard shadow ring).
    var chromeTextOutlineWidth: CGFloat {
        needsContrastChrome ? 1.25 : 0.7
    }

    /// Prefer this scheme so `.primary` / `.secondary` match the ink.
    var preferredContentScheme: ColorScheme {
        chromeInk == .onDark ? .dark : .light
    }

    /// Soft plates behind empty states / chips over busy photos.
    var needsContrastChrome: Bool {
        backgroundImageName != nil || prefersDark
    }

    /// Text halo: pale themes get a light lift; dark themes get a dark shadow.
    var readableTextShadow: (Color, CGFloat) {
        switch chromeInk {
        case .onLight:
            return (Color.white.opacity(0.65), 2.5)
        case .onDark:
            return (Color.black.opacity(0.55), 3)
        }
    }

    /// Whether the photo scrim should bleach toward white (light UI) or darken (dark UI).
    /// Black overlays on moss/bookshelf make primary text unreadable.
    var atmosphereUsesLightScrim: Bool {
        !prefersDark
    }

    /// Overlay strength — photo themes: no wash; flat themes: barely any.
    var atmosphereOverlayTop: Double {
        if backgroundImageName != nil { return 0 }
        if prefersDark { return 0.10 }
        if isCalmFamily { return 0 }
        return 0.03
    }

    var atmosphereOverlayBottom: Double {
        if backgroundImageName != nil { return 0 }
        if prefersDark { return 0.18 }
        if isCalmFamily { return 0 }
        return 0.05
    }

    /// Accent wash on flat (no-photo) backgrounds.
    var atmosphereAccentWash: Double {
        isCalmFamily ? 0.10 : 0.35
    }

    var atmosphereStyle: ThemeAtmosphereStyle {
        switch self {
        case .neon: return .neon
        case .plasma: return .plasma
        case .orbit: return .orbit
        case .hologram: return .hologram
        case .ion: return .ion
        case _ where isDaredevilFamily: return .daredevil
        default: return .classic
        }
    }

    /// Asset catalog image name for the full-app background photo.
    var backgroundImageName: String? {
        switch self {
        case .moss: return "ThemeMoss"
        // Soft site-like wash (no photo) — matches flat AT chrome.
        case .authorToday, .paper, .cloud, .stone: return nil
        case .ocean: return "ThemeOcean"
        case .wine: return "ThemeWine"
        case .graphite: return "ThemeGraphite"
        case .sand: return "ThemeSand"
        case .neon: return "ThemeNeon"
        case .plasma: return "ThemePlasma"
        case .orbit: return "ThemeOrbit"
        case .hologram: return "ThemeHologram"
        case .ion: return "ThemeIon"
        case .ddRooftop: return "ThemeDD01"
        case .ddSilhouette: return "ThemeDD02"
        case .ddLeap: return "ThemeDD03"
        case .ddRain: return "ThemeDD04"
        case .ddShadow: return "ThemeDD05"
        case .ddRadar: return "ThemeDD06"
        case .ddBatons: return "ThemeDD07"
        case .ddCourt: return "ThemeDD08"
        case .ddEscape: return "ThemeDD09"
        case .ddFabric: return "ThemeDD10"
        case .custom: return "ThemeGraphite"
        }
    }

    var atmosphereBase: Color {
        switch self {
        case .moss: return Color(red: 0.90, green: 0.93, blue: 0.91)
        // #e6f0fc — soft AT link/panel blue wash
        case .authorToday: return Color(red: 0.902, green: 0.941, blue: 0.988)
        case .paper: return Color(red: 0.968, green: 0.964, blue: 0.955)
        case .cloud: return Color(red: 0.935, green: 0.948, blue: 0.960)
        case .stone: return Color(red: 0.935, green: 0.936, blue: 0.940)
        case .ocean: return Color(red: 0.88, green: 0.93, blue: 0.97)
        case .wine: return Color(red: 0.95, green: 0.90, blue: 0.92)
        case .graphite: return Color(red: 0.91, green: 0.92, blue: 0.93)
        case .sand: return Color(red: 0.96, green: 0.93, blue: 0.87)
        case .neon: return Color(red: 0.02, green: 0.05, blue: 0.08)
        case .plasma: return Color(red: 0.06, green: 0.02, blue: 0.12)
        case .orbit: return Color(red: 0.02, green: 0.04, blue: 0.12)
        case .hologram: return Color(red: 0.02, green: 0.08, blue: 0.08)
        case .ion: return Color(red: 0.04, green: 0.06, blue: 0.12)
        case _ where isDaredevilFamily:
            return Color(red: 0.06, green: 0.02, blue: 0.02)
        case .custom: return Color(red: 0.92, green: 0.93, blue: 0.93)
        default: return Color(red: 0.92, green: 0.93, blue: 0.93)
        }
    }

    var atmosphereBlobColors: [Color] {
        switch self {
        case .moss:
            return [Color(red: 0.25, green: 0.55, blue: 0.42), Color(red: 0.45, green: 0.62, blue: 0.40)]
        case .authorToday:
            // #4582af, #34749e, #6da3bd
            return [
                Color(red: 0.271, green: 0.510, blue: 0.686),
                Color(red: 0.204, green: 0.455, blue: 0.620),
                Color(red: 0.427, green: 0.639, blue: 0.741)
            ]
        case .paper:
            return [
                Color(red: 0.88, green: 0.86, blue: 0.82),
                Color(red: 0.78, green: 0.80, blue: 0.82)
            ]
        case .cloud:
            return [
                Color(red: 0.72, green: 0.80, blue: 0.88),
                Color(red: 0.82, green: 0.88, blue: 0.92)
            ]
        case .stone:
            return [
                Color(red: 0.72, green: 0.74, blue: 0.76),
                Color(red: 0.82, green: 0.83, blue: 0.85)
            ]
        case .ocean:
            return [Color(red: 0.25, green: 0.50, blue: 0.75), Color(red: 0.40, green: 0.70, blue: 0.85)]
        case .wine:
            return [Color(red: 0.70, green: 0.25, blue: 0.35), Color(red: 0.55, green: 0.20, blue: 0.40)]
        case .graphite:
            return [Color(red: 0.45, green: 0.50, blue: 0.55), Color(red: 0.55, green: 0.58, blue: 0.62)]
        case .sand:
            return [Color(red: 0.85, green: 0.68, blue: 0.40), Color(red: 0.75, green: 0.55, blue: 0.35)]
        case .neon:
            return [Color(red: 0.00, green: 0.95, blue: 1.00), Color(red: 1.00, green: 0.15, blue: 0.75), Color(red: 0.20, green: 0.40, blue: 1.00)]
        case .plasma:
            return [Color(red: 0.70, green: 0.20, blue: 1.00), Color(red: 0.95, green: 0.25, blue: 0.70), Color(red: 0.35, green: 0.15, blue: 0.90)]
        case .orbit:
            return [Color(red: 0.25, green: 0.45, blue: 1.00), Color(red: 0.45, green: 0.70, blue: 1.00)]
        case .hologram:
            return [Color(red: 0.20, green: 1.00, blue: 0.75), Color(red: 0.35, green: 0.90, blue: 1.00)]
        case .ion:
            return [Color(red: 0.55, green: 0.75, blue: 1.00), Color(red: 0.75, green: 0.90, blue: 1.00)]
        case _ where isDaredevilFamily:
            return [
                Color(red: 0.85, green: 0.08, blue: 0.12),
                Color(red: 0.45, green: 0.02, blue: 0.05),
                Color(red: 0.25, green: 0.02, blue: 0.02)
            ]
        case .custom:
            return [accent, accent.opacity(0.7)]
        default:
            return [accent]
        }
    }
}

@MainActor
final class AppAppearanceStore: ObservableObject {
    @Published var colorMode: AppColorMode {
        didSet { defaults.set(colorMode.rawValue, forKey: "aa.colorMode") }
    }
    @Published var themePreset: AppThemePreset {
        didSet {
            defaults.set(themePreset.rawValue, forKey: "aa.theme")
            if themePreset.prefersDark, colorMode == .system {
                // Soft nudge: keep system, but preferredColorScheme will darken.
            }
        }
    }
    @Published var customAccentHex: String {
        didSet { defaults.set(customAccentHex, forKey: "aa.accentHex") }
    }

    private let defaults = UserDefaults.standard

    init() {
        colorMode = AppColorMode(rawValue: defaults.string(forKey: "aa.colorMode") ?? "") ?? .system
        themePreset = AppThemePreset.resolved(rawValue: defaults.string(forKey: "aa.theme"))
        customAccentHex = defaults.string(forKey: "aa.accentHex") ?? "#2E6B5C"
    }

    var accent: Color {
        if themePreset == .custom {
            return Color(hex: customAccentHex) ?? themePreset.accent
        }
        return themePreset.accent
    }

    var mist: Color {
        themePreset.mistLight
    }

    var preferredColorScheme: ColorScheme? {
        // Busy / photo themes: lock content scheme to the theme’s ink profile.
        if themePreset.backgroundImageName != nil || themePreset.prefersDark {
            return themePreset.preferredContentScheme
        }
        if let forced = colorMode.colorScheme { return forced }
        return themePreset.prefersDark ? .dark : nil
    }
}
