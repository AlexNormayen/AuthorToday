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
        .environment(\.themePreset, appearance.themePreset)
        .environment(\.themeAccent, appearance.accent)
        .onAppear {
            configureTranslucentChrome()
            configureSegmentedChrome(for: appearance.themePreset)
            if appearance.themePreset.chromeInk == .onDark, appearance.colorMode == .light {
                appearance.colorMode = .dark
            }
        }
        .onChange(of: appearance.themePreset) { _, preset in
            configureSegmentedChrome(for: preset)
        }
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
        tab.backgroundEffect = nil
        tab.backgroundColor = .clear
        tab.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().isTranslucent = true

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = nil
        nav.backgroundColor = .clear
        nav.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().isTranslucent = true

        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
    }

    private func configureSegmentedChrome(for preset: AppThemePreset) {
        let seg = UISegmentedControl.appearance()
        seg.selectedSegmentTintColor = preset.chromeSegmentSelectedUIColor
        seg.backgroundColor = preset.chromeSegmentTrackUIColor
        let title = preset.chromeSegmentTitleUIColor
        seg.setTitleTextAttributes([.foregroundColor: title], for: .normal)
        seg.setTitleTextAttributes([.foregroundColor: title], for: .selected)
    }
}

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var notifications: NotificationPoller
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @ObservedObject private var session = ReadingSessionStore.shared
    @ObservedObject private var nudge = ProNudgeStore.shared
    @State private var selectedTab = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var resumeReader: ReadingSessionStore.ResumeReader?
    @State private var didApplyColdStart = false

    private var useSidebar: Bool {
        PlatformLayout.prefersSidebar(sizeClass: sizeClass)
    }

    var body: some View {
        Group {
            if useSidebar {
                iPadSplitShell
            } else {
                iPhoneTabShell
            }
        }
        .tint(appearance.accent)
        .onAppear {
            guard !didApplyColdStart else { return }
            didApplyColdStart = true
            migrateTabIndexIfNeeded()
            selectedTab = min(max(session.selectedTab, 0), MainDestination.allCases.count - 1)
            if !useSidebar, selectedTab == MainDestination.search.rawValue {
                selectedTab = MainDestination.library.rawValue
                session.setSelectedTab(selectedTab)
            }
            session.prepareColdStartResume()
            resumeReader = session.pendingResume
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                _ = nudge.considerPresenting(isProUnlocked: pro.isProUnlocked)
            }
        }
        .onChange(of: selectedTab) { _, tab in
            session.setSelectedTab(tab)
        }
        .onChange(of: sizeClass) { _, _ in
            // Keep selection when rotating / entering Split View.
            selectedTab = min(max(selectedTab, 0), MainDestination.allCases.count - 1)
            if !PlatformLayout.prefersSidebar(sizeClass: sizeClass),
               selectedTab == MainDestination.search.rawValue {
                selectedTab = MainDestination.library.rawValue
            }
        }
        .onOpenURL { url in
            if let item = Self.resumeFromWidgetURL(url) {
                resumeReader = item
            }
        }
        .fullScreenCover(item: $resumeReader, onDismiss: {
            session.endReading()
        }) { item in
            NavigationStack {
                ReaderView(workId: item.workId, initialChapterId: item.chapterId)
            }
        }
        .sheet(isPresented: $nudge.showPaywall) {
            ProPaywallView(reason: "Вы уже читаете в Читальне несколько дней. Pro снимает лимит офлайна и открывает темы, закладки и «Мои книги».")
        }
    }

    private var iPhoneTabShell: some View {
        TabView(selection: $selectedTab) {
            ForEach(MainDestination.phoneCases) { dest in
                dest.rootView
                    .tabItem {
                        Label(dest.title, systemImage: dest.systemImage)
                    }
                    .badge(dest == .feed ? notifications.unreadCount : 0)
                    .tag(dest.rawValue)
            }
        }
        .toolbarBackground(.hidden, for: .tabBar)
        .background(Color.clear)
    }

    private var iPadSplitShell: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: Binding(
                get: { MainDestination(rawValue: selectedTab) },
                set: { if let value = $0 { selectedTab = value.rawValue } }
            )) {
                Section("Читальня") {
                    ForEach(MainDestination.padCases) { dest in
                        Label {
                            HStack {
                                Text(dest.title)
                                if dest == .feed, notifications.unreadCount > 0 {
                                    Spacer(minLength: 8)
                                    Text("\(notifications.unreadCount)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(appearance.accent))
                                }
                            }
                        } icon: {
                            Image(systemName: dest.systemImage)
                        }
                        .tag(dest)
                    }
                }
            }
            .navigationTitle("Читальня")
            .listStyle(.sidebar)
        } detail: {
            destinationDetail
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var destinationDetail: some View {
        let dest = MainDestination(rawValue: selectedTab) ?? .library
        dest.rootView
            .id(dest) // reset navigation stacks when switching sidebar item
    }

    private static func resumeFromWidgetURL(_ url: URL) -> ReadingSessionStore.ResumeReader? {
        guard url.scheme == "chitalnya", url.host == "resume" else { return nil }
        let parts = url.path.split(separator: "/").compactMap { Int($0) }
        guard let workId = parts.first else { return nil }
        let chapter = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "chapter" })
            .flatMap { Int($0.value ?? "") }
        return .init(workId: workId, chapterId: chapter)
    }

    /// Previous: 0 Library, 1 Recent, 2 Search, 3 Feed, 4 More.
    /// Current:  0 Library, 1 Downloaded, 2 Recent, 3 Search, 4 Feed, 5 More.
    private func migrateTabIndexIfNeeded() {
        let removeKey = "at.tabs.localLibraryRemoved.v1"
        if !UserDefaults.standard.bool(forKey: removeKey) {
            let insertKey = "at.tabs.localLibraryInserted.v1"
            if UserDefaults.standard.bool(forKey: insertKey) {
                let tab = session.selectedTab
                if tab == 1 {
                    session.setSelectedTab(0)
                } else if tab > 1 {
                    session.setSelectedTab(tab - 1)
                }
            }
            UserDefaults.standard.set(true, forKey: removeKey)
        }

        let downloadedKey = "at.tabs.downloadedInserted.v1"
        if !UserDefaults.standard.bool(forKey: downloadedKey) {
            let tab = session.selectedTab
            if tab >= 1 {
                session.setSelectedTab(tab + 1)
            }
            UserDefaults.standard.set(true, forKey: downloadedKey)
        }

        // Search moved into Library on iPhone; keep pad raw values, remap saved Search tab.
        let searchKey = "at.tabs.searchMovedIntoLibrary.v1"
        guard !UserDefaults.standard.bool(forKey: searchKey) else { return }
        if session.selectedTab == MainDestination.search.rawValue {
            session.setSelectedTab(MainDestination.library.rawValue)
        }
        UserDefaults.standard.set(true, forKey: searchKey)
    }
}

private enum MainDestination: Int, CaseIterable, Identifiable, Hashable {
    case library = 0
    case downloaded = 1
    case recent = 2
    case search = 3
    case feed = 4
    case more = 5

    var id: Int { rawValue }

    /// iPhone tab bar — search lives inside Library.
    static var phoneCases: [MainDestination] {
        [.library, .downloaded, .recent, .feed, .more]
    }

    /// iPad sidebar — search stays as its own row.
    static var padCases: [MainDestination] {
        allCases
    }

    var title: String {
        switch self {
        case .library: return "Библиотека"
        case .downloaded: return "Скачанные"
        case .recent: return "Недавние"
        case .search: return "Поиск"
        case .feed: return "Лента"
        case .more: return "Ещё"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "books.vertical"
        case .downloaded: return "arrow.down.circle"
        case .recent: return "clock"
        case .search: return "magnifyingglass"
        case .feed: return "bell"
        case .more: return "ellipsis.circle"
        }
    }

    @ViewBuilder
    var rootView: some View {
        switch self {
        case .library: LibraryView()
        case .downloaded: DownloadedLibraryView()
        case .recent: RecentReadsView()
        case .search: SearchView()
        case .feed: NotificationsView()
        case .more: SettingsHubView()
        }
    }
}

struct SettingsHubView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var readerSettings: ReaderSettingsStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var notifications: NotificationPoller
    @StateObject private var updates = AppUpdateChecker.shared

    var body: some View {
        NavigationStack {
            List {
                if ChitalnyaDistribution.showsSideloadUpdates, updates.updateAvailable {
                    Section {
                        Button {
                            updates.openInstallPage()
                        } label: {
                            Label(
                                "Доступна новая сборка: \(updates.latestLabel ?? "IPA")",
                                systemImage: "arrow.down.circle.fill"
                            )
                        }
                        .themedPanelRow()
                    }
                }

                Section {
                    if let user = auth.user {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.fio ?? user.resolvedUserName ?? "Читатель")
                                .font(AppTheme.headlineFont)
                            if let email = user.email {
                                Text(email)
                                    .font(.subheadline.weight(.medium))
                                    .themedSecondaryText()
                            }
                        }
                        .padding(.vertical, 4)
                        .themedPanelRow()
                    }
                }

                Section {
                    NavigationLink {
                        MessagesView()
                    } label: {
                        Label("Сообщения", systemImage: "bubble.left.and.bubble.right")
                    }
                    .themedPanelRow()
                } header: {
                    Text("Общение").themedSectionChrome()
                }

                Section {
                    if !pro.isProUnlocked {
                        OfflineQuotaStatusView(compact: true)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
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
                                    .font(.caption.weight(.semibold))
                                    .themedSecondaryText()
                            } else if pro.isProUnlocked {
                                Text("Активен")
                                    .font(.caption.weight(.semibold))
                                    .themedSecondaryText()
                            } else {
                                Text("\(offline.fullyDownloadedCount)/\(ProFeatures.freeFullDownloadLimit) офлайн")
                                    .font(.caption.weight(.semibold))
                                    .themedSecondaryText()
                            }
                        }
                    }
                    .themedPanelRow()
                    NavigationLink {
                        BookmarksNotesView()
                    } label: {
                        Label("Закладки и заметки", systemImage: "bookmark")
                    }
                    .themedPanelRow()
                } header: {
                    Text("Поддержка").themedSectionChrome()
                } footer: {
                    Text("Pro улучшает клиент Читальня (темы, офлайн, закладки, свои TXT/EPUB). Оплата через App Store. Книги и оплата контента — только на author.today. Виджет «Продолжить» бесплатный.")
                         .themedSectionChrome()
                }

                Section {
                    Toggle("Пуш об обновлениях Author.Today", isOn: $notifications.alertsEnabled)
                        .tint(.green)
                        .themedPanelRow()
                } header: {
                    Text("Оповещения").themedSectionChrome()
                } footer: {
                    Text("Читальня опрашивает ленту и новые главы, пока приложение открыто или в фоне. Это локальные оповещения на устройстве, не удалённые push с сервера Author.Today.")
                         .themedSectionChrome()
                }

                Section {
                    NavigationLink("Тема приложения и тёмный режим") {
                        AppearanceSettingsView()
                    }
                    .themedPanelRow()
                    NavigationLink("Настройки читалки") {
                        ReaderSettingsView()
                    }
                    .themedPanelRow()
                } header: {
                    Text("Оформление").themedSectionChrome()
                }

                Section {
                    NavigationLink {
                        BookVaultSettingsView()
                    } label: {
                        Label(
                            ChitalnyaDistribution.isAppStore
                                ? "Облачная полка (опционально)"
                                : "Облачная полка (VPS)",
                            systemImage: "externaldrive.badge.icloud"
                        )
                    }
                    .themedPanelRow()
                } header: {
                    Text("Резервная копия").themedSectionChrome()
                } footer: {
                    Text(
                        ChitalnyaDistribution.isAppStore
                            ? "По умолчанию выключено. Если включите — книги, прогресс и закладки можно синхронизировать на сервер разработчика (явное согласие)."
                            : "Скачанные книги, прогресс и закладки на вашем сервере — бэкап и синк между устройствами."
                    )
                     .themedSectionChrome()
                }

                Section {
                    Button("Обновить профиль") {
                        Task { await auth.refreshProfile() }
                    }
                    .themedPanelRow()
                    Button("Выйти", role: .destructive) {
                        auth.logout()
                    }
                    .themedPanelRow()
                } header: {
                    Text("Аккаунт").themedSectionChrome()
                }

                Section {
                    LabeledContent("Приложение", value: "Читальня").themedPanelRow()
                    LabeledContent("Версия", value: updates.localDisplay).themedPanelRow()
                    LabeledContent("Канал", value: ChitalnyaDistribution.channelLabel).themedPanelRow()
                    LabeledContent("Статус", value: "Клиент Author.Today (неофициальный)").themedPanelRow()
                    LabeledContent("Платформа", value: "author.today").themedPanelRow()
                    LabeledContent("Режим", value: "онлайн + офлайн").themedPanelRow()
                    if let user = auth.user?.resolvedUserName ?? auth.resolvedUserName {
                        LabeledContent("Профиль", value: "/u/\(user)/library").themedPanelRow()
                    }
                    if offline.lastSyncCount > 0 {
                        LabeledContent("Книг с сайта", value: "\(offline.lastSyncCount)").themedPanelRow()
                    }
                } header: {
                    Text("О приложении").themedSectionChrome()
                }

                if ChitalnyaDistribution.showsSideloadUpdates {
                    AppUpdateSettingsSection(checker: updates)
                }

                Section {
                    Text("Читальня не является официальным приложением Author.Today и не связана с порталом. Author.Today не отвечает за работу этого клиента. Книги и оплата — только через author.today. Локальные оповещения опрашивают публичный API портала.")
                        .font(.footnote.weight(.medium))
                        .themedSecondaryText()
                        .themedPanelRow()
                } header: {
                    Text("Важно").themedSectionChrome()
                }
            }
            .listStyle(.plain)
            .environment(\.themePreset, appearance.themePreset)
            .environment(\.themeAccent, appearance.accent)
            .navigationTitle("Ещё")
            .themedScreenChrome()
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .scrollContentBackground(.hidden)
            .toolbarBackground(.hidden, for: .navigationBar)
            .task {
                if ChitalnyaDistribution.showsSideloadUpdates {
                    await updates.checkIfDue()
                }
            }
        }
    }
}
