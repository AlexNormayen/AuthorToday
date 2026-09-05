import SwiftUI
import SwiftData

@main
struct AuthorTodayApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthService.shared
    @StateObject private var readerSettings = ReaderSettingsStore()
    @StateObject private var appearance = AppAppearanceStore()
    @StateObject private var offlineStore = OfflineStore.shared
    @StateObject private var localLibrary = LocalLibraryStore.shared
    @StateObject private var notifications = NotificationPoller.shared
    @StateObject private var pro = ProEntitlementStore.shared

    init() {
        NotificationPoller.registerBackgroundRefresh()
    }

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
                        if BookVaultSettings.shared.isEnabled {
                            Task {
                                await BookVaultSync.shared.pullProgressAndBookmarks(store: offlineStore)
                                await BookVaultSync.shared.autoBackfillIfNeeded(
                                    store: offlineStore,
                                    localStore: localLibrary
                                )
                            }
                        }
                    }
                    _ = localLibrary.importNewFilesFromDocuments()
                    await AppUpdateChecker.shared.checkIfDue()
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
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if auth.isAuthenticated {
                            Task { await notifications.handleSceneBecameActive() }
                        }
                        Task { await AppUpdateChecker.shared.checkIfDue() }
                    case .background:
                        notifications.scheduleBackgroundRefresh()
                    default:
                        break
                    }
                }
        }
        .modelContainer(for: [
            CachedWork.self,
            CachedChapter.self,
            ReadingProgress.self,
            LocalBook.self,
            LocalChapter.self,
            ReadingBookmark.self,
            ReadingNote.self
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
