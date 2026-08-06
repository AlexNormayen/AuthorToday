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
    // Daredevil / Сорвиголова
    case daredevil
    case hellsKitchen
    case murdock
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moss: return "Мох"
        case .ocean: return "Океан"
        case .wine: return "Вино"
        case .graphite: return "Графит"
        case .sand: return "Песок"
        case .neon: return "Неон"
        case .plasma: return "Плазма"
        case .orbit: return "Орбита"
        case .hologram: return "Голограмма"
        case .ion: return "Ион"
        case .daredevil: return "Сорвиголова"
        case .hellsKitchen: return "Адская кухня"
        case .murdock: return "Мёрдок"
        case .custom: return "Свой цвет"
        }
    }

    var accent: Color {
        switch self {
        case .moss: return Color(red: 0.18, green: 0.42, blue: 0.36)
        case .ocean: return Color(red: 0.14, green: 0.35, blue: 0.55)
        case .wine: return Color(red: 0.55, green: 0.18, blue: 0.28)
        case .graphite: return Color(red: 0.35, green: 0.38, blue: 0.42)
        case .sand: return Color(red: 0.62, green: 0.48, blue: 0.30)
        case .neon: return Color(red: 0.00, green: 0.90, blue: 0.95)
        case .plasma: return Color(red: 0.55, green: 0.20, blue: 1.00)
        case .orbit: return Color(red: 0.20, green: 0.45, blue: 1.00)
        case .hologram: return Color(red: 0.25, green: 0.95, blue: 0.75)
        case .ion: return Color(red: 0.70, green: 0.85, blue: 1.00)
        case .daredevil: return Color(red: 0.78, green: 0.09, blue: 0.14)
        case .hellsKitchen: return Color(red: 0.55, green: 0.05, blue: 0.08)
        case .murdock: return Color(red: 0.90, green: 0.22, blue: 0.18)
        case .custom: return Color(red: 0.18, green: 0.42, blue: 0.36)
        }
    }

    var mistLight: Color {
        switch self {
        case .moss: return Color(red: 0.93, green: 0.94, blue: 0.93)
        case .ocean: return Color(red: 0.92, green: 0.95, blue: 0.97)
        case .wine: return Color(red: 0.97, green: 0.93, blue: 0.94)
        case .graphite: return Color(red: 0.94, green: 0.94, blue: 0.95)
        case .sand: return Color(red: 0.96, green: 0.94, blue: 0.90)
        case .neon, .plasma, .orbit, .hologram, .ion:
            return Color(red: 0.07, green: 0.09, blue: 0.12)
        case .daredevil, .hellsKitchen, .murdock:
            return Color(red: 0.08, green: 0.06, blue: 0.06)
        case .custom: return Color(red: 0.94, green: 0.94, blue: 0.94)
        }
    }

    var mistDark: Color {
        switch self {
        case .daredevil, .hellsKitchen, .murdock:
            return Color(red: 0.06, green: 0.04, blue: 0.04)
        case .neon, .plasma, .orbit, .hologram, .ion:
            return Color(red: 0.05, green: 0.06, blue: 0.09)
        default:
            return Color(red: 0.10, green: 0.11, blue: 0.12)
        }
    }

    /// Themes that look best with dark UI chrome.
    var prefersDark: Bool {
        switch self {
        case .neon, .plasma, .orbit, .hologram, .ion, .daredevil, .hellsKitchen, .murdock:
            return true
        default:
            return false
        }
    }

    var atmosphereStyle: ThemeAtmosphereStyle {
        switch self {
        case .neon: return .neon
        case .plasma: return .plasma
        case .orbit: return .orbit
        case .hologram: return .hologram
        case .ion: return .ion
        case .daredevil, .hellsKitchen, .murdock: return .daredevil
        default: return .classic
        }
    }

    var atmosphereBase: Color {
        switch self {
        case .moss: return Color(red: 0.90, green: 0.93, blue: 0.91)
        case .ocean: return Color(red: 0.88, green: 0.93, blue: 0.97)
        case .wine: return Color(red: 0.95, green: 0.90, blue: 0.92)
        case .graphite: return Color(red: 0.91, green: 0.92, blue: 0.93)
        case .sand: return Color(red: 0.96, green: 0.93, blue: 0.87)
        case .neon: return Color(red: 0.02, green: 0.05, blue: 0.08)
        case .plasma: return Color(red: 0.06, green: 0.02, blue: 0.12)
        case .orbit: return Color(red: 0.02, green: 0.04, blue: 0.12)
        case .hologram: return Color(red: 0.02, green: 0.08, blue: 0.08)
        case .ion: return Color(red: 0.04, green: 0.06, blue: 0.12)
        case .daredevil: return Color(red: 0.06, green: 0.02, blue: 0.02)
        case .hellsKitchen: return Color(red: 0.08, green: 0.02, blue: 0.02)
        case .murdock: return Color(red: 0.05, green: 0.03, blue: 0.03)
        case .custom: return Color(red: 0.92, green: 0.93, blue: 0.93)
        }
    }

    var atmosphereBlobColors: [Color] {
        switch self {
        case .moss:
            return [Color(red: 0.25, green: 0.55, blue: 0.42), Color(red: 0.45, green: 0.62, blue: 0.40)]
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
        case .daredevil:
            return [Color(red: 0.85, green: 0.08, blue: 0.12), Color(red: 0.45, green: 0.02, blue: 0.05), Color(red: 0.25, green: 0.02, blue: 0.02)]
        case .hellsKitchen:
            return [Color(red: 0.95, green: 0.25, blue: 0.05), Color(red: 0.70, green: 0.08, blue: 0.05), Color(red: 0.35, green: 0.02, blue: 0.02)]
        case .murdock:
            return [Color(red: 0.90, green: 0.20, blue: 0.15), Color(red: 0.35, green: 0.08, blue: 0.08)]
        case .custom:
            return [accent, accent.opacity(0.7)]
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
        themePreset = AppThemePreset(rawValue: defaults.string(forKey: "aa.theme") ?? "") ?? .moss
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
