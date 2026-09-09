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

    /// Promo / complimentary Pro — Debug only (Guideline 3.1.1).
    static var allowsComplimentaryPro: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static var channelLabel: String {
        isAppStore ? "App Store" : "Sideload"
    }
}
