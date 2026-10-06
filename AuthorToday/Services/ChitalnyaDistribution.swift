import Foundation

/// Build / distribution channel for «Читальня».
/// App Store builds set `APPSTORE` compilation condition (+ Info key) via Codemagic signed workflow.
/// Sideload (unsigned IPA / SideStore) keeps the default channel.
enum ChitalnyaDistribution {
    /// True for App Store / TestFlight binaries.
    static var isAppStore: Bool {
        #if APPSTORE
        return true
        #else
        let raw = (Bundle.main.object(forInfoDictionaryKey: "ChitalnyaDistribution") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return raw == "appstore"
        #endif
    }

    static var isSideload: Bool { !isAppStore }

    /// IPA / SideStore update checks and settings — sideload only.
    static var showsSideloadUpdates: Bool { isSideload }

    /// Optional VPS cloud shelf — App Store: opt-in only, no baked-in token.
    static var bookVaultDefaultEnabled: Bool { isSideload }

    static var embedsBookVaultBuiltInToken: Bool { isSideload }

    /// Promo / complimentary Pro (owner allowlist + invite grants).
    /// - Debug: always on
    /// - Sideload Release: on
    /// - App Store: on only while IAP is off (web-purchased Pro / grants — reader account model)
    static var allowsComplimentaryPro: Bool {
        #if DEBUG
        return true
        #else
        return isSideload || !offersInAppPurchases
        #endif
    }

    /// StoreKit purchase / restore UI and Pro buy nudges.
    /// Off while Paid Applications Agreement is unavailable (RF legal entity / sanctions).
    /// When Paid Apps is Active: set to `isAppStore` and ship a new version with IAP attached.
    static var offersInAppPurchases: Bool { false }

    /// Unlock Pro after purchase on at.theinquisitor.ru (silent status check).
    /// On while IAP is off — App Store and sideload. Buy UI is gated separately.
    static var allowsWebPurchasedPro: Bool { !offersInAppPurchases }

    /// Upsell / «buy Pro» entry points (StoreKit or web checkout button).
    /// App Store: no commerce UI while IAP unavailable (Guideline 2.2); paid users still unlock via status API.
    static var showsProCommerce: Bool {
        if offersInAppPurchases { return true }
        return isSideload && allowsWebPurchasedPro
    }

    /// Do not auto-unlock everything on App Store — Pro comes from web purchase (or future IAP).
    static var unlocksProFeaturesWithoutPurchase: Bool { false }

    /// App Store: no «Pro» / pricing / checkout copy — only docs + silent account unlock.
    static var hidesProMarketing: Bool { isAppStore && !offersInAppPurchases }

    /// Author.Today documentation post (no payment links in the post for App Review).
    static let authorTodayDocumentationURL = URL(string: "https://author.today/post/913007")!

    static var channelLabel: String {
        isAppStore ? "App Store" : "Sideload"
    }
}
