import Foundation

/// Free vs Pro catalog for «Читальня Pro».
/// Pro sells client convenience — never Author.Today book content.
enum ProFeatures {
    /// Fully offline books (all chapters) allowed without Pro.
    static let freeFullDownloadLimit = 2

    /// Always-Pro accounts (no StoreKit). Matched case-insensitively.
    /// Add emails and/or Author.Today usernames here.
    static let complimentaryEmails: Set<String> = [
        "fowl_348@mail.ru",
    ]

    static let complimentaryUserNames: Set<String> = [
        "dark_tarkhan",
    ]

    /// Owner allowlist (complimentary Pro + optional internal tools).
    static func isOwnerAccount(email: String?, userName: String?) -> Bool {
        if let email = normalize(email), complimentaryEmails.contains(email) {
            return true
        }
        if let userName = normalize(userName), complimentaryUserNames.contains(userName) {
            return true
        }
        return false
    }

    static func isComplimentaryAccount(email: String?, userName: String?) -> Bool {
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

    /// Optional promo codes. Paid Pro is App Store IAP.
    static let sideloadInviteCodes: Set<String> = [
        "CHITALNYA-FRIENDS",
    ]

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
