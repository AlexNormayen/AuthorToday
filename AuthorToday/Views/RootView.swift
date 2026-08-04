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
        .onAppear {
            offline.attach(context: modelContext)
            downloads.startMonitoring()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var notifications: NotificationPoller

    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Библиотека", systemImage: "books.vertical")
                }

            SearchView()
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }

            NotificationsView()
                .tabItem {
                    Label("Оповещения", systemImage: "bell")
                }
                .badge(notifications.unreadCount)

            SettingsHubView()
                .tabItem {
                    Label("Ещё", systemImage: "ellipsis.circle")
                }
        }
        .tint(AppTheme.moss)
    }
}

struct SettingsHubView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var readerSettings: ReaderSettingsStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let user = auth.user {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.fio ?? user.userName ?? "Читатель")
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

                Section("Читалка") {
                    NavigationLink("Настройки чтения") {
                        ReaderSettingsView()
                    }
                    Picker("Перелистывание", selection: $readerSettings.pageTurnMode) {
                        ForEach(PageTurnMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
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
                    Text("Пуш через Apple Push недоступен без платного Apple Developer. Используются локальные оповещения по опросу API.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ещё")
        }
    }
}
