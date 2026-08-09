import SwiftUI
import SwiftData

@main
struct AuthorTodayApp: App {
    @StateObject private var auth = AuthService.shared
    @StateObject private var readerSettings = ReaderSettingsStore()
    @StateObject private var appearance = AppAppearanceStore()
    @StateObject private var offlineStore = OfflineStore.shared
    @StateObject private var localLibrary = LocalLibraryStore.shared
    @StateObject private var notifications = NotificationPoller.shared
    @StateObject private var pro = ProEntitlementStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(readerSettings)
                .environmentObject(appearance)
                .environmentObject(offlineStore)
                .environmentObject(localLibrary)
                .environmentObject(notifications)
                .environmentObject(pro)
                .preferredColorScheme(appearance.preferredColorScheme)
                .tint(appearance.accent)
                .task {
                    await notifications.configure()
                    await pro.refresh()
                    let loginEmail = UserDefaults.standard.string(forKey: "at.auth.loginEmail")
                    pro.applyAccount(
                        email: auth.user?.email ?? loginEmail,
                        userName: auth.user?.resolvedUserName ?? auth.resolvedUserName
                    )
                    enforceFreeTierIfNeeded()
                    if auth.isAuthenticated {
                        notifications.startPolling()
                    }
                }
                .onChange(of: auth.isAuthenticated) { _, loggedIn in
                    if loggedIn {
                        notifications.startPolling()
                        let loginEmail = UserDefaults.standard.string(forKey: "at.auth.loginEmail")
                        pro.applyAccount(
                            email: auth.user?.email ?? loginEmail,
                            userName: auth.user?.resolvedUserName ?? auth.resolvedUserName
                        )
                    } else {
                        notifications.stopPolling()
                        pro.applyAccount(nil)
                    }
                    enforceFreeTierIfNeeded()
                }
                .onChange(of: pro.isProUnlocked) { _, _ in
                    enforceFreeTierIfNeeded()
                }
        }
        .modelContainer(for: [
            CachedWork.self,
            CachedChapter.self,
            ReadingProgress.self,
            LocalBook.self,
            LocalChapter.self
        ])
    }

    private func enforceFreeTierIfNeeded() {
        guard !pro.isProUnlocked else { return }
        if ProFeatures.requiresPro(appearance.themePreset) {
            appearance.themePreset = .moss
            appearance.colorMode = .system
        }
        if ProFeatures.requiresPro(readerSettings.pageTurnMode) {
            readerSettings.pageTurnMode = .verticalScroll
        }
        if ProFeatures.requiresPro(readerSettings.theme) {
            readerSettings.theme = .paper
            readerSettings.useCustomColors = false
        }
    }
}
