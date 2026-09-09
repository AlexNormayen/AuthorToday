import Foundation

/// Free vs Pro catalog for «Читальня Pro».
/// Pro sells client convenience — never Author.Today book content.
enum ProFeatures {
    /// Fully offline books (all chapters) allowed without Pro.
    static let freeFullDownloadLimit = 2

    /// Always-Pro accounts (no StoreKit). Debug builds only — not in App Store / Release.
    static var complimentaryEmails: Set<String> {
        #if DEBUG
        ["fowl_348@mail.ru"]
        #else
        []
        #endif
    }

    static var complimentaryUserNames: Set<String> {
        #if DEBUG
        ["dark_tarkhan"]
        #else
        []
        #endif
    }

    /// Owner allowlist (complimentary Pro + optional internal tools). Debug only.
    static func isOwnerAccount(email: String?, userName: String?) -> Bool {
        guard ChitalnyaDistribution.allowsComplimentaryPro else { return false }
        if let email = normalize(email), complimentaryEmails.contains(email) {
            return true
        }
        if let userName = normalize(userName), complimentaryUserNames.contains(userName) {
            return true
        }
        return false
    }

    static func isComplimentaryAccount(email: String?, userName: String?) -> Bool {
        guard ChitalnyaDistribution.allowsComplimentaryPro else { return false }
        if isOwnerAccount(email: email, userName: userName) {
            return true
        }
        // Runtime grants (UserDefaults) — checked from ProEntitlementStore / ProGrantStore.
        return false
    }

    static func normalize(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        return raw
    }

    static func requiresPro(_ preset: AppThemePreset) -> Bool {
        preset.isFuturisticFamily || preset.isDaredevilFamily || preset == .custom
    }

    static func requiresPro(_ mode: PageTurnMode) -> Bool {
        mode == .curlStyle
    }

    static func requiresPro(_ theme: ReaderThemePreset) -> Bool {
        theme == .customColor || theme == .customImage
    }

    static var freeAppThemePresets: [AppThemePreset] {
        AppThemePreset.allCases.filter { !requiresPro($0) }
    }

    /// Optional promo codes. Debug only — paid Pro is App Store IAP in Release.
    static var sideloadInviteCodes: Set<String> {
        #if DEBUG
        ["CHITALNYA-FRIENDS"]
        #else
        []
        #endif
    }

    /// Local file shelf (TXT/EPUB) — Pro only.
    static let localLibraryRequiresPro = true

    static var paywallBullets: [String] {
        [
            "Все темы оформления (неон, фото-фоны и свой цвет)",
            "Скачивание книг целиком без лимита (\(freeFullDownloadLimit) книги бесплатно)",
            "Закладки и заметки в читалке",
            "«Мои книги»: свои TXT и EPUB на устройстве",
            "Режим «Перелистывание» как у бумажной книги",
            "Свой цвет и картинка фона в читалке"
        ]
    }
}
