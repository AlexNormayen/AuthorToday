import SwiftUI
import SwiftData

struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var offline: OfflineStore
    @StateObject private var downloads = DownloadManager.shared

    var body: some View {
        Group {
            if auth.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .environmentObject(downloads)
        .task {
            offline.attach(context: modelContext)
            downloads.startMonitoring()
            if auth.isAuthenticated {
                await auth.refreshProfile()
                // Soft sync: keep local shelf/covers visible, refresh in background
                await offline.syncLibraryIfNeeded(force: false)
            }
        }
        .onChange(of: auth.isAuthenticated) { _, loggedIn in
            if loggedIn {
                Task {
                    await auth.refreshProfile()
                    await offline.syncLibrary(force: true)
                }
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var notifications: NotificationPoller
    @EnvironmentObject private var appearance: AppAppearanceStore

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Библиотека", systemImage: "books.vertical")
                }

            RecentReadsView()
                .tabItem {
                    Label("Недавние", systemImage: "clock")
                }

            SearchView()
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }

            NotificationsView()
                .tabItem {
                    Label("Лента", systemImage: "bell")
                }
                .badge(notifications.unreadCount)

            SettingsHubView()
                .tabItem {
                    Label("Ещё", systemImage: "ellipsis.circle")
                }
        }
        .tint(appearance.accent)
    }
}

struct SettingsHubView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var readerSettings: ReaderSettingsStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var offline: OfflineStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = auth.user {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.fio ?? user.resolvedUserName ?? "Читатель")
                                .font(AppTheme.headlineFont)
                            if let email = user.email {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Оформление") {
                    NavigationLink("Тема приложения и тёмный режим") {
                        AppearanceSettingsView()
                    }
                    NavigationLink("Настройки читалки") {
                        ReaderSettingsView()
                    }
                }

                Section("Аккаунт") {
                    Button("Обновить профиль") {
                        Task { await auth.refreshProfile() }
                    }
                    Button("Выйти", role: .destructive) {
                        auth.logout()
                    }
                }

                Section("О приложении") {
                    LabeledContent("Платформа", value: "author.today")
                    LabeledContent("Режим", value: "онлайн + офлайн")
                    if let user = auth.user?.resolvedUserName ?? auth.resolvedUserName {
                        LabeledContent("Профиль", value: "/u/\(user)/library")
                    }
                    if offline.lastSyncCount > 0 {
                        LabeledContent("Книг с сайта", value: "\(offline.lastSyncCount)")
                    }
                    Text("Покупка книг открывает оплату на author.today. Пуш через Apple Push недоступен без платного Developer — используются локальные оповещения.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ещё")
        }
    }
}
