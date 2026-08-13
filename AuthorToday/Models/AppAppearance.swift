import SwiftUI
import Combine

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

    /// Dim overlay strength for the living backdrop (lower = more readable lists).
    var atmosphereOverlayTop: Double {
        if prefersDark { return 0.35 }
        if isCalmFamily { return 0.03 }
        return 0.12
    }

    var atmosphereOverlayBottom: Double {
        if prefersDark { return 0.55 }
        if isCalmFamily { return 0.06 }
        return 0.22
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
        if let forced = colorMode.colorScheme { return forced }
        return themePreset.prefersDark ? .dark : nil
    }
}
