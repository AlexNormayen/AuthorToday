import SwiftUI
import PhotosUI
import UIKit

enum PageTurnMode: String, CaseIterable, Identifiable, Codable {
    case verticalScroll
    case horizontalSwipe
    case tapZones
    case tapAndSwipe
    case curlStyle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verticalScroll: return "Вертикальный скролл"
        case .horizontalSwipe: return "Горизонтальный свайп"
        case .tapZones: return "Тап по зонам"
        case .tapAndSwipe: return "Тап + свайп"
        case .curlStyle: return "Перелистывание"
        }
    }

    var subtitle: String {
        switch self {
        case .verticalScroll: return "Как лента в браузере"
        case .horizontalSwipe: return "Страницы влево/вправо"
        case .tapZones: return "Левая/правая треть экрана"
        case .tapAndSwipe: return "И тап, и жест"
        case .curlStyle: return "Анимация как у книги"
        }
    }
}

enum ReaderFontFamily: String, CaseIterable, Identifiable, Codable {
    case system
    case serif
    case rounded
    case monospaced
    case georgia
    case palatino
    case charter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .serif: return "New York"
        case .rounded: return "Rounded"
        case .monospaced: return "Mono"
        case .georgia: return "Georgia"
        case .palatino: return "Palatino"
        case .charter: return "Charter"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .system: return .system(size: size)
        case .serif: return .system(size: size, design: .serif)
        case .rounded: return .system(size: size, design: .rounded)
        case .monospaced: return .system(size: size, design: .monospaced)
        case .georgia: return .custom("Georgia", size: size)
        case .palatino: return .custom("Palatino", size: size)
        case .charter: return .custom("Charter", size: size)
        }
    }
}

enum ReaderThemePreset: String, CaseIterable, Identifiable, Codable {
    case paper
    case night
    case sepia
    case slate
    case mint
    case customColor
    case customImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "Бумага"
        case .night: return "Ночь"
        case .sepia: return "Сепия"
        case .slate: return "Сланец"
        case .mint: return "Мята"
        case .customColor: return "Свой цвет"
        case .customImage: return "Своя картинка"
        }
    }

    var defaultBackground: Color {
        switch self {
        case .paper: return Color(red: 0.96, green: 0.95, blue: 0.92)
        case .night: return Color(red: 0.08, green: 0.09, blue: 0.11)
        case .sepia: return Color(red: 0.93, green: 0.88, blue: 0.76)
        case .slate: return Color(red: 0.18, green: 0.20, blue: 0.23)
        case .mint: return Color(red: 0.90, green: 0.95, blue: 0.92)
        case .customColor, .customImage: return Color(red: 0.96, green: 0.95, blue: 0.92)
        }
    }

    var defaultText: Color {
        switch self {
        case .paper, .sepia, .mint, .customColor, .customImage:
            return Color(red: 0.12, green: 0.12, blue: 0.14)
        case .night, .slate:
            return Color(red: 0.90, green: 0.90, blue: 0.88)
        }
    }
}

@MainActor
final class ReaderSettingsStore: ObservableObject {
    @Published var fontFamily: ReaderFontFamily {
        didSet { persist() }
    }
    @Published var fontSize: Double {
        didSet { persist() }
    }
    @Published var lineSpacing: Double {
        didSet { persist() }
    }
    @Published var paragraphSpacing: Double {
        didSet { persist() }
    }
    @Published var marginHorizontal: Double {
        didSet { persist() }
    }
    @Published var marginVertical: Double {
        didSet { persist() }
    }
    @Published var pageTurnMode: PageTurnMode {
        didSet { persist() }
    }
    @Published var theme: ReaderThemePreset {
        didSet { persist() }
    }
    @Published var customBackgroundHex: String {
        didSet { persist() }
    }
    @Published var customTextHex: String {
        didSet { persist() }
    }
    @Published var customBackgroundImageData: Data? {
        didSet { persistImage() }
    }
    @Published var backgroundImageOpacity: Double {
        didSet { persist() }
    }
    @Published var keepScreenOn: Bool {
        didSet { persist() }
    }
    @Published var brightnessOverride: Double? {
        didSet { persist() }
    }

    private let defaults = UserDefaults.standard
    private let imageURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        imageURL = docs.appendingPathComponent("reader_custom_background.jpg")

        fontFamily = ReaderFontFamily(rawValue: defaults.string(forKey: "rs.fontFamily") ?? "") ?? .serif
        fontSize = defaults.object(forKey: "rs.fontSize") as? Double ?? 19
        lineSpacing = defaults.object(forKey: "rs.lineSpacing") as? Double ?? 8
        paragraphSpacing = defaults.object(forKey: "rs.paragraphSpacing") as? Double ?? 12
        marginHorizontal = defaults.object(forKey: "rs.marginH") as? Double ?? 20
        marginVertical = defaults.object(forKey: "rs.marginV") as? Double ?? 16
        pageTurnMode = PageTurnMode(rawValue: defaults.string(forKey: "rs.pageMode") ?? "") ?? .tapAndSwipe
        theme = ReaderThemePreset(rawValue: defaults.string(forKey: "rs.theme") ?? "") ?? .paper
        customBackgroundHex = defaults.string(forKey: "rs.bgHex") ?? "#F5F3EB"
        customTextHex = defaults.string(forKey: "rs.textHex") ?? "#1F1F22"
        backgroundImageOpacity = defaults.object(forKey: "rs.bgOpacity") as? Double ?? 0.35
        keepScreenOn = defaults.object(forKey: "rs.keepOn") as? Bool ?? true
        if defaults.object(forKey: "rs.brightness") != nil {
            brightnessOverride = defaults.double(forKey: "rs.brightness")
        } else {
            brightnessOverride = nil
        }
        customBackgroundImageData = try? Data(contentsOf: imageURL)
    }

    var textColor: Color {
        if theme == .customColor || theme == .customImage {
            return Color(hex: customTextHex) ?? theme.defaultText
        }
        return theme.defaultText
    }

    var solidBackground: Color {
        if theme == .customColor {
            return Color(hex: customBackgroundHex) ?? theme.defaultBackground
        }
        if theme == .customImage {
            return Color(hex: customBackgroundHex) ?? .black.opacity(0.85)
        }
        return theme.defaultBackground
    }

    var backgroundImage: Image? {
        guard theme == .customImage,
              let data = customBackgroundImageData,
              let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
    }

    var appColorScheme: ColorScheme? {
        switch theme {
        case .night, .slate: return .dark
        case .paper, .sepia, .mint: return .light
        case .customColor, .customImage: return nil
        }
    }

    func setCustomBackground(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            customBackgroundImageData = data
            theme = .customImage
        }
    }

    func clearCustomBackground() {
        customBackgroundImageData = nil
        try? FileManager.default.removeItem(at: imageURL)
        if theme == .customImage {
            theme = .paper
        }
    }

    private func persist() {
        defaults.set(fontFamily.rawValue, forKey: "rs.fontFamily")
        defaults.set(fontSize, forKey: "rs.fontSize")
        defaults.set(lineSpacing, forKey: "rs.lineSpacing")
        defaults.set(paragraphSpacing, forKey: "rs.paragraphSpacing")
        defaults.set(marginHorizontal, forKey: "rs.marginH")
        defaults.set(marginVertical, forKey: "rs.marginV")
        defaults.set(pageTurnMode.rawValue, forKey: "rs.pageMode")
        defaults.set(theme.rawValue, forKey: "rs.theme")
        defaults.set(customBackgroundHex, forKey: "rs.bgHex")
        defaults.set(customTextHex, forKey: "rs.textHex")
        defaults.set(backgroundImageOpacity, forKey: "rs.bgOpacity")
        defaults.set(keepScreenOn, forKey: "rs.keepOn")
        if let brightnessOverride {
            defaults.set(brightnessOverride, forKey: "rs.brightness")
        } else {
            defaults.removeObject(forKey: "rs.brightness")
        }
    }

    private func persistImage() {
        if let customBackgroundImageData {
            try? customBackgroundImageData.write(to: imageURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: imageURL)
        }
    }
}

extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8 else { return nil }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let a, r, g, b: UInt64
        if s.count == 8 {
            a = (value & 0xFF000000) >> 24
            r = (value & 0x00FF0000) >> 16
            g = (value & 0x0000FF00) >> 8
            b = value & 0x000000FF
        } else {
            a = 255
            r = (value & 0xFF0000) >> 16
            g = (value & 0x00FF00) >> 8
            b = value & 0x0000FF
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func toHex() -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "#%02X%02X%02X",
            Int(r * 255), Int(g * 255), Int(b * 255)
        )
    }
}
