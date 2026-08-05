import SwiftUI
import SwiftData

@main
struct AuthorTodayApp: App {
    @StateObject private var auth = AuthService.shared
    @StateObject private var readerSettings = ReaderSettingsStore()
    @StateObject private var offlineStore = OfflineStore.shared
    @StateObject private var notifications = NotificationPoller.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(readerSettings)
                .environmentObject(offlineStore)
                .environmentObject(notifications)
                .preferredColorScheme(readerSettings.appColorScheme)
                .task {
                    await notifications.configure()
                    if auth.isAuthenticated {
                        notifications.startPolling()
                    }
                }
                .onChange(of: auth.isAuthenticated) { _, loggedIn in
                    if loggedIn {
                        notifications.startPolling()
                    } else {
                        notifications.stopPolling()
                    }
                }
        }
        .modelContainer(for: [
            CachedWork.self,
            CachedChapter.self,
            ReadingProgress.self
        ])
    }
}
