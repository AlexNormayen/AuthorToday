import SwiftUI

/// Adaptive layout helpers — prefers size class so iPad Split View / Stage Manager stay usable.
enum PlatformLayout {
    /// Sidebar shell instead of bottom tabs (iPad full width, not Slide Over).
    static func prefersSidebar(sizeClass: UserInterfaceSizeClass?) -> Bool {
        sizeClass == .regular
    }

    /// Comfortable reading column on large screens (~book page).
    static let readerMaxWidth: CGFloat = 720

    /// Login / forms — avoid stretched fields on 12.9".
    static let formMaxWidth: CGFloat = 440

    /// Lists and settings content width on regular size class.
    static let listContentMaxWidth: CGFloat = 900
}

extension View {
    /// Centers content and caps width on iPad / regular width.
    func readableColumn(maxWidth: CGFloat = PlatformLayout.readerMaxWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    func adaptiveFormWidth(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        Group {
            if sizeClass == .regular {
                self
                    .frame(maxWidth: PlatformLayout.formMaxWidth)
                    .frame(maxWidth: .infinity)
            } else {
                self
            }
        }
    }
}
