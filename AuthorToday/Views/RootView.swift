import SwiftUI
import SwiftData
import UIKit

struct RootView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var appearance: AppAppearanceStore
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var localLibrary: LocalLibraryStore
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
            localLibrary.attach(context: modelContext)
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

            LocalLibraryView()
                .tabItem {
                    Label("Мои книги", systemImage: "tray.full")
                }
                .tag(1)

            RecentReadsView()
                .tabItem {
                    Label("Недавние", systemImage: "clock")
                }
                .tag(2)

            SearchView()
                .tabItem {
                    Label("Поиск", systemImage: "magnifyingglass")
                }
                .tag(3)

            NotificationsView()
                .tabItem {
                    Label("Лента", systemImage: "bell")
                }
                .badge(notifications.unreadCount)
                .tag(4)

            SettingsHubView()
                .tabItem {
                    Label("Ещё", systemImage: "ellipsis.circle")
                }
                .tag(5)
        }
        .tint(appearance.accent)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .background(Color.clear)
        .onAppear {
            guard !didApplyColdStart else { return }
            didApplyColdStart = true
            migrateTabIndexIfNeeded()
            selectedTab = min(max(session.selectedTab, 0), 5)
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

    /// Old tabs: 0 Library, 1 Recent, 2 Search, 3 Feed, 4 More.
    /// New tabs insert «Мои книги» at index 1 — bump saved indices ≥ 1 once.
    private func migrateTabIndexIfNeeded() {
        let key = "at.tabs.localLibraryInserted.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if session.selectedTab >= 1 {
            session.setSelectedTab(session.selectedTab + 1)
        }
        UserDefaults.standard.set(true, forKey: key)
    }
}

struct SettingsHubView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var readerSettings: ReaderSettingsStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var pro: ProEntitlementStore

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

                Section {
                    NavigationLink {
                        ProPaywallView()
                    } label: {
                        HStack {
                            Label(
                                pro.isProUnlocked ? "Читальня Pro" : "Открыть Читальню Pro",
                                systemImage: pro.isProUnlocked ? "checkmark.seal.fill" : "sparkles"
                            )
                            Spacer()
                            if pro.isComplimentaryPro {
                                Text("По аккаунту")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if pro.isProUnlocked {
                                Text("Активен")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Темы · офлайн · файлы")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Поддержка")
                } footer: {
                    Text("Pro улучшает клиент Читальня (темы, офлайн, свои TXT/EPUB). Книги и оплата контента — только на author.today.")
                }

                if ProFeatures.isOwnerAccount(
                    email: auth.user?.email,
                    userName: auth.user?.resolvedUserName ?? auth.resolvedUserName
                ) {
                    Section {
                        NavigationLink {
                            ProGrantsAdminView()
                        } label: {
                            Label("Pro-доступы (временно)", systemImage: "person.badge.key")
                        }
                    } header: {
                        Text("Владелец")
                    } footer: {
                        Text("Выдача Pro друзьям до Apple IAP. Перед App Store убрать или заменить.")
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
