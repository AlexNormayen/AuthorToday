import SwiftUI
import SwiftData
import UIKit

struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var offline: OfflineStore
    @StateObject private var downloads = DownloadManager.shared

    var body: some View {
        ZStack {
            ThemeAtmosphereView(preset: appearance.themePreset)
            Group {
                if auth.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
        }
        .environmentObject(downloads)
        .onAppear { configureTranslucentChrome() }
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

    private func configureTranslucentChrome() {
        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().isTranslucent = true

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().isTranslucent = true

        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }
}

struct MainTabView: View {
    @EnvironmentObject private var notifications: NotificationPoller
    @EnvironmentObject private var appearance: AppAppearanceStore
    @ObservedObject private var session = ReadingSessionStore.shared
    @State private var selectedTab = 0
    @State private var resumeReader: ReadingSessionStore.ResumeReader?
    @State private var didApplyColdStart = false

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("Библиотека", systemImage: "books.vertical")
                }
                .tag(0)

            RecentReadsView()
                .tabItem {
                    Label("Недавние", systemImage: "clock")
                }
                .tag(1)

            SearchView()
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }
                .tag(2)

            NotificationsView()
                .tabItem {
                    Label("Лента", systemImage: "bell")
                }
                .badge(notifications.unreadCount)
                .tag(3)

            SettingsHubView()
                .tabItem {
                    Label("Ещё", systemImage: "ellipsis.circle")
                }
                .tag(4)
        }
        .tint(appearance.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .background(Color.clear)
        .onAppear {
            guard !didApplyColdStart else { return }
            didApplyColdStart = true
            selectedTab = session.selectedTab
            session.prepareColdStartResume()
            resumeReader = session.pendingResume
        }
        .onChange(of: selectedTab) { _, tab in
            session.setSelectedTab(tab)
        }
        .fullScreenCover(item: $resumeReader, onDismiss: {
            session.endReading()
        }) { item in
            NavigationStack {
                ReaderView(workId: item.workId, initialChapterId: item.chapterId)
            }
        }
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

                Section("Общение") {
                    NavigationLink {
                        MessagesView()
                    } label: {
                        Label("Сообщения", systemImage: "bubble.left.and.bubble.right")
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
                    LabeledContent("Приложение", value: "Читальня")
                    LabeledContent("Статус", value: "Клиент Author.Today (неофициальный)")
                    LabeledContent("Платформа", value: "author.today")
                    LabeledContent("Режим", value: "онлайн + офлайн")
                    if let user = auth.user?.resolvedUserName ?? auth.resolvedUserName {
                        LabeledContent("Профиль", value: "/u/\(user)/library")
                    }
                    if offline.lastSyncCount > 0 {
                        LabeledContent("Книг с сайта", value: "\(offline.lastSyncCount)")
                    }
                }

                Section {
                    Text("Читальня не является официальным приложением Author.Today и не связана с порталом. Author.Today не отвечает за работу этого клиента. Книги и оплата — только через author.today. Локальные оповещения опрашивают публичный API портала.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Важно")
                }
            }
            .navigationTitle("Ещё")
            .themedScreenChrome()
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }
}
