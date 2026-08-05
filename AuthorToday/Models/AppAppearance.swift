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
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moss: return "Мох"
        case .ocean: return "Океан"
        case .wine: return "Вино"
        case .graphite: return "Графит"
        case .sand: return "Песок"
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
        case .custom: return Color(red: 0.94, green: 0.94, blue: 0.94)
        }
    }

    var mistDark: Color {
        Color(red: 0.10, green: 0.11, blue: 0.12)
    }
}

@MainActor
final class AppAppearanceStore: ObservableObject {
    @Published var colorMode: AppColorMode {
        didSet { defaults.set(colorMode.rawValue, forKey: "aa.colorMode") }
    }
    @Published var themePreset: AppThemePreset {
        didSet { defaults.set(themePreset.rawValue, forKey: "aa.theme") }
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
        // Resolved roughly; views can still use semantic colors.
        themePreset.mistLight
    }

    var preferredColorScheme: ColorScheme? {
        colorMode.colorScheme
    }
}
