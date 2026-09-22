import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var searchScope: LibrarySearchScope = .library
    @State private var catalogSearchSeed: CatalogSearchSeed?
    @State private var mode: LibraryBrowseMode = .authors
    @State private var authorSort: AuthorSortMode = .name

    private var shelfWorks: [CachedWork] {
        offline.library
    }

    private var filteredWorks: [CachedWork] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [CachedWork]
        if q.isEmpty {
            base = shelfWorks
        } else {
            base = shelfWorks.filter { work in
                if work.title.lowercased().contains(q) { return true }
                return work.allAuthorNames.contains { $0.lowercased().contains(q) }
            }
        }
        return offline.worksSorted(base, by: authorSort)
    }

    private var filteredAuthors: [(author: String, works: [CachedWork])] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let groups = offline.authorsGrouped(sortedBy: authorSort)
        if q.isEmpty { return groups }
        return groups.compactMap { group in
            if group.author.lowercased().contains(q) {
                return group
            }
            let works = group.works.filter { $0.title.lowercased().contains(q) }
            return works.isEmpty ? nil : (author: group.author, works: works)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Вид", selection: $mode) {
                    ForEach(LibraryBrowseMode.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if mode == .authors || mode == .all {
                    Picker("Сортировка", selection: $authorSort) {
                        ForEach(AuthorSortMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .themedChromeChip()
                    .tint(appearance.themePreset.chromePrimaryText(colorScheme: .dark))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Group {
                    switch mode {
                    case .authors:
                        authorsContent
                    case .all:
                        allBooksContent
                    case .mine:
                        LocalLibraryPane()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .environment(\.themePreset, appearance.themePreset)
            .environment(\.themeAccent, appearance.accent)
            .navigationTitle("Библиотека")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if mode != .mine {
                    Picker("Где искать", selection: $searchScope) {
                        ForEach(LibrarySearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.clear)
                }
            }
            .onChange(of: searchScope) { _, scope in
                guard scope == .catalog else { return }
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                catalogSearchSeed = CatalogSearchSeed(query: q)
                // Keep library filter when user comes back.
                searchScope = .library
            }
            .onSubmit(of: .search) {
                if searchScope == .catalog {
                    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    catalogSearchSeed = CatalogSearchSeed(query: q)
                    searchScope = .library
                }
            }
            .toolbar {
                if mode != .mine {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await offline.syncLibrary(force: true) }
                        } label: {
                            if offline.isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if mode != .mine, offline.isSyncing || offline.lastSyncCount > 0 || !offline.library.isEmpty || !offline.downloadedWorks.isEmpty {
                    HStack {
                        Text(shelfSummary)
                            .font(.caption)
                            .themedSecondaryText()
                        Spacer()
                        if offline.isSyncing {
                            Text(offline.syncStatusText ?? "синхронизация…")
                                .font(.caption2)
                                .themedSecondaryText()
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.clear)
                }
            }
            .refreshable {
                if mode != .mine {
                    await offline.syncLibrary(force: true)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    Color.clear
                        .onAppear {
                            ReadingSessionStore.shared.presentReader(workId: workId, chapterId: chapterId)
                        }
                case .details(let workId):
                    BookDetailView(workId: workId)
                case .author(let name, let downloadedOnly):
                    AuthorBooksView(author: name, path: $path, downloadedOnly: downloadedOnly)
                case .authorSeries(let author, let series, let downloadedOnly):
                    AuthorSeriesBooksView(author: author, series: series, path: $path, downloadedOnly: downloadedOnly)
                case .authorProfile(let userName, let displayName):
                    AuthorProfileView(userName: userName, displayNameHint: displayName)
                }
            }
            .sheet(item: $catalogSearchSeed) { seed in
                SearchView(initialQuery: seed.query, showsDismissButton: true)
                    .environmentObject(appearance)
                    .environmentObject(downloads)
                    .environmentObject(offline)
                    .environment(\.themePreset, appearance.themePreset)
                    .environment(\.themeAccent, appearance.accent)
                    .preferredColorScheme(appearance.preferredColorScheme)
                    .tint(appearance.accent)
            }
            .safeAreaInset(edge: .bottom) {
                if let msg = downloads.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .themedReadableText()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .padding(.bottom, 8)
                } else if mode != .mine, let err = offline.lastSyncError,
                          !err.localizedCaseInsensitiveContains("отменено"),
                          !err.localizedCaseInsensitiveContains("cancelled"),
                          !err.localizedCaseInsensitiveContains("canceled") {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .themedReadableText()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .padding(.bottom, 8)
                }
            }
            .task {
                offline.reloadLibrary()
                if let err = offline.lastSyncError,
                   err.localizedCaseInsensitiveContains("отменено")
                    || err.localizedCaseInsensitiveContains("cancelled")
                    || err.localizedCaseInsensitiveContains("canceled") {
                    offline.lastSyncError = nil
                }
                if offline.library.isEmpty, !offline.isSyncing {
                    await offline.syncLibrary(force: true)
                }
            }
        }
    }

    @ViewBuilder
    private var authorsContent: some View {
        if offline.library.isEmpty && offline.isSyncing {
            ProgressView(offline.syncStatusText.map { "Синхронизация… \($0)" } ?? "Синхронизация библиотеки…")
        } else if offline.library.isEmpty {
            ThemedEmptyStateView(
                title: "Библиотека пуста",
                systemImage: "books.vertical",
                description: emptyLibraryMessage
            )
        } else {
            authorsList
        }
    }

    @ViewBuilder
    private var allBooksContent: some View {
        if offline.library.isEmpty && offline.isSyncing {
            ProgressView(offline.syncStatusText.map { "Синхронизация… \($0)" } ?? "Синхронизация библиотеки…")
        } else if filteredWorks.isEmpty {
            ThemedEmptyStateView(
                title: "Библиотека пуста",
                systemImage: "books.vertical",
                description: emptyLibraryMessage
            )
        } else {
            booksList(works: filteredWorks)
        }
    }

    private var shelfSummary: String {
        "\(offline.library.count) книг · \(offline.authorsGrouped.count) авторов"
    }

    private var authorsList: some View {
        List {
            ForEach(filteredAuthors, id: \.author) { group in
                Button {
                    path.append(LibraryRoute.author(group.author, downloadedOnly: false))
                } label: {
                    HStack(spacing: 14) {
                        AuthorCoverCollage(
                            coverURLs: group.works
                                .sorted { ($0.coverURL?.isEmpty == false ? 0 : 1) < ($1.coverURL?.isEmpty == false ? 0 : 1) }
                                .prefix(8)
                                .map(\.coverURL),
                            size: 56,
                            corner: 10
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.author)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .themedReadableText()
                            Text(authorSubtitle(group))
                                .font(.caption.weight(.medium))
                                .themedSecondaryText()
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                .themedPanelRow()
            }
        }
        .themedAtmosphereList()
        .environment(\.themePreset, appearance.themePreset)
    }

    private func booksList(works: [CachedWork]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(works, id: \.workId) { work in
                    Button {
                        path.append(LibraryRoute.details(workId: work.workId))
                    } label: {
                        LibraryRow(work: work)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var emptyLibraryMessage: String {
        if offline.isSyncing {
            return "Синхронизация с author.today…"
        }
        if let err = offline.lastSyncError {
            return "Ошибка синхронизации: \(err)\nПотяните вниз или нажмите обновить.\nНужен доступ к /u/\(AuthService.shared.resolvedUserName ?? "…")/library"
        }
        if downloads.online {
            return "На сайте в библиотеке пока пусто, либо синхронизация не нашла книги.\nПрофиль: \(AuthService.shared.resolvedUserName ?? "не загружен"). Нажмите обновить."
        }
        return "Нет сети. Когда появится интернет — обновите библиотеку."
    }

    private func authorSubtitle(_ group: (author: String, works: [CachedWork])) -> String {
        let count = booksCountText(group.works.count)
        switch authorSort {
        case .name, .bookCount:
            return count
        case .recentlyRead:
            let date = group.works.map { offline.effectiveLastReadAt($0) }.max() ?? .distantPast
            if date > .distantPast {
                let f = RelativeDateTimeFormatter()
                f.locale = Locale(identifier: "ru_RU")
                f.unitsStyle = .short
                return "\(count) · \(f.localizedString(for: date, relativeTo: Date()))"
            }
            return count
        case .popularity:
            let likes = group.works.reduce(0) { $0 + ($1.likeCount ?? 0) }
            if likes > 0 {
                return "\(count) · ★ \(likes)"
            }
            return count
        }
    }

    private func booksCountText(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod10 == 1, mod100 != 11 { return "\(n) книга" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return "\(n) книги" }
        return "\(n) книг"
    }
}

enum LibraryBrowseMode: String, CaseIterable, Identifiable {
    case authors
    case all
    case mine

    var id: String { rawValue }
    var title: String {
        switch self {
        case .authors: return "Авторы"
        case .all: return "Все книги"
        case .mine: return "Мои книги"
        }
    }
}

private enum LibrarySearchScope: String, CaseIterable, Identifiable {
    case library
    case catalog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: return "В библиотеке"
        case .catalog: return "Author.Today"
        }
    }
}

private struct LibrarySearchModifier: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $query, prompt: "Название или автор")
        } else {
            content
        }
    }
}

enum AuthorSortMode: String, CaseIterable, Identifiable {
    case name
    case bookCount
    case recentlyRead
    case popularity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "По алфавиту"
        case .bookCount: return "По числу книг"
        case .recentlyRead: return "По недавнему чтению"
        case .popularity: return "По популярности"
        }
    }
}

enum LibraryRoute: Hashable {
    case reader(workId: Int, chapterId: Int?)
    case details(workId: Int)
    case author(String, downloadedOnly: Bool)
    case authorSeries(author: String, series: String, downloadedOnly: Bool)
    case authorProfile(userName: String, displayName: String?)
}

private struct CatalogSearchSeed: Identifiable {
    let id = UUID()
    let query: String
}

struct AuthorBooksView: View {
    let author: String
    @Binding var path: NavigationPath
    var downloadedOnly: Bool = false
    @EnvironmentObject private var offline: OfflineStore
    @State private var sort: AuthorSortMode = .recentlyRead

    private var works: [CachedWork] {
        let source = downloadedOnly ? offline.downloadedWorks : offline.library
        let filtered = source.filter { $0.belongsToAuthor(author) }
        return downloadedOnly ? offline.worksSorted(filtered, by: sort) : filtered
    }

    private var seriesGroups: [(series: String, works: [CachedWork])] {
        var titleBySeriesId: [Int: String] = [:]
        for work in works {
            guard let id = work.seriesId else { continue }
            let title = work.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { titleBySeriesId[id] = title }
        }
        let grouped = Dictionary(grouping: works) { Self.seriesFolderName(for: $0, titleBySeriesId: titleBySeriesId) }
        return grouped
            .map { key, value in
                let sorted = value.sorted { a, b in
                    let oa = a.seriesOrder ?? Int.max
                    let ob = b.seriesOrder ?? Int.max
                    if oa != ob { return oa < ob }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                return (series: key, works: sorted)
            }
            .sorted { a, b in
                if a.series == "Без серии" { return false }
                if b.series == "Без серии" { return true }
                return a.series.localizedCaseInsensitiveCompare(b.series) == .orderedAscending
            }
    }

    static func seriesFolderName(for work: CachedWork, titleBySeriesId: [Int: String] = [:]) -> String {
        let own = work.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !own.isEmpty { return own }
        if let id = work.seriesId, let shared = titleBySeriesId[id] { return shared }
        if let id = work.seriesId { return "Серия #\(id)" }
        return "Без серии"
    }

    private var onlyFlatList: Bool {
        seriesGroups.count <= 1 && seriesGroups.first?.series == "Без серии"
    }

    var body: some View {
        Group {
            if onlyFlatList {
                booksScroll(works.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
            } else {
                List {
                    ForEach(seriesGroups, id: \.series) { group in
                        Button {
                            path.append(LibraryRoute.authorSeries(author: author, series: group.series, downloadedOnly: downloadedOnly))
                        } label: {
                            HStack(spacing: 14) {
                                AuthorCoverCollage(
                                    coverURLs: group.works
                                        .sorted { ($0.coverURL?.isEmpty == false ? 0 : 1) < ($1.coverURL?.isEmpty == false ? 0 : 1) }
                                        .prefix(8)
                                        .map(\.coverURL),
                                    size: 52,
                                    corner: 10
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(group.series)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(booksCountText(group.works.count))
                                        .font(.caption)
                                        .themedSecondaryText()
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .themedSecondaryText()
                            }
                            .padding(.vertical, 4)
                        }
                        .themedPanelRow()
                    }
                }
                .themedAtmosphereList()
            }
        }
        .themedGroupedFill()
        .navigationTitle(author)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: author) {
            await offline.enrichMissingSeriesMetadata(forAuthor: author, limit: 60)
        }
        .toolbar {
            if downloadedOnly {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Сортировка", selection: $sort) {
                        ForEach(AuthorSortMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            if let userName = siteUserName {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Профиль") {
                        path.append(LibraryRoute.authorProfile(userName: userName, displayName: author))
                    }
                }
            }
        }
    }

    private var siteUserName: String? {
        works.compactMap(\.authorUserName).first { !$0.isEmpty }
    }

    private func booksScroll(_ items: [CachedWork]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.workId) { work in
                    Button {
                        path.append(LibraryRoute.details(workId: work.workId))
                    } label: {
                        LibraryRow(work: work, showAuthor: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func booksCountText(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        if mod10 == 1, mod100 != 11 { return "\(n) книга" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return "\(n) книги" }
        return "\(n) книг"
    }
}

struct AuthorSeriesBooksView: View {
    let author: String
    let series: String
    @Binding var path: NavigationPath
    var downloadedOnly: Bool = false
    @EnvironmentObject private var offline: OfflineStore

    private var works: [CachedWork] {
        let source = downloadedOnly ? offline.downloadedWorks : offline.library
        let authorWorks = source.filter { $0.belongsToAuthor(author) }
        var titleBySeriesId: [Int: String] = [:]
        for work in authorWorks {
            guard let id = work.seriesId else { continue }
            let title = work.seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty { titleBySeriesId[id] = title }
        }
        return authorWorks
            .filter { AuthorBooksView.seriesFolderName(for: $0, titleBySeriesId: titleBySeriesId) == series }
            .sorted { a, b in
                let oa = a.seriesOrder ?? Int.max
                let ob = b.seriesOrder ?? Int.max
                if oa != ob { return oa < ob }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(works, id: \.workId) { work in
                    Button {
                        path.append(LibraryRoute.details(workId: work.workId))
                    } label: {
                        LibraryRow(work: work, showAuthor: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 8)
        }
        .themedGroupedFill()
        .navigationTitle(series)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Tab: books sorted by last read time (app + portal).
struct RecentReadsView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if offline.recentlyRead.isEmpty {
                    ThemedEmptyStateView(
                        title: "Пока пусто",
                        systemImage: "clock",
                        description: "Здесь появятся книги после чтения в приложении. Завершённые давно книги скрываются. Потяните вниз, чтобы подтянуть порядок с портала."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(offline.recentlyRead, id: \.workId) { work in
                                Button {
                                    path.append(LibraryRoute.details(workId: work.workId))
                                } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        LibraryRow(work: work)
                                        let date = offline.effectiveLastReadAt(work)
                                        if date > .distantPast {
                                            Text(Self.dateText(date))
                                                .font(.caption2)
                                                .themedSecondaryText()
                                                .padding(.leading, 86)
                                                .padding(.bottom, 6)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .themedGroupedFill()
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .refreshable {
                await offline.syncLibrary(force: true)
            }
            .navigationTitle("Недавние")
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    Color.clear
                        .onAppear {
                            ReadingSessionStore.shared.presentReader(workId: workId, chapterId: chapterId)
                        }
                case .details(let workId):
                    BookDetailView(workId: workId)
                case .author(let name, let downloadedOnly):
                    AuthorBooksView(author: name, path: $path, downloadedOnly: downloadedOnly)
                case .authorSeries(let author, let series, let downloadedOnly):
                    AuthorSeriesBooksView(author: author, series: series, path: $path, downloadedOnly: downloadedOnly)
                case .authorProfile(let userName, let displayName):
                    AuthorProfileView(userName: userName, displayNameHint: displayName)
                }
            }
            .onAppear { offline.reloadLibrary() }
        }
    }

    private static func dateText(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.locale = Locale(identifier: "ru_RU")
        return "Читали \(f.localizedString(for: date, relativeTo: Date()))"
    }
}

struct LibraryRow: View {
    let work: CachedWork
    var showAuthor: Bool = true
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        HStack(spacing: 14) {
            CoverImage(urlString: work.coverURL)
                .frame(width: 56, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text(work.title)
                    .font(.system(.body, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .themedReadableText()

                if showAuthor {
                    Text(work.displayAuthors)
                        .font(.caption)
                        .themedSecondaryText()
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if work.isFullyDownloaded {
                        Label("Офлайн", systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .themedSecondaryText()
                    } else if let cov = offline.offlineChapterCoverage(workId: work.workId), cov.ready > 0 {
                        Label("\(cov.ready)/\(cov.total)", systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .themedSecondaryText()
                    } else if let chapterId = work.lastReadChapterId,
                              offline.isChapterCached(workId: work.workId, chapterId: chapterId) {
                        Label("Глава офлайн", systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .themedSecondaryText()
                    } else if let p = offline.downloadProgress[work.workId], p > 0, p < 1 {
                        ProgressView(value: p)
                            .frame(width: 60)
                    } else if downloads.activeDownloads.contains(work.workId) {
                        ProgressView()
                            .scaleEffect(0.7)
                    }

                    if work.displayProgressPercent > 0 {
                        Text("\(work.displayProgressPercent)%")
                            .font(.caption2)
                            .themedSecondaryText()
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .themedSecondaryText()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// Flat list of offline books — own tab, no author drill-down.
struct DownloadedLibraryView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var appearance: AppAppearanceStore
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var sort: AuthorSortMode = .recentlyRead

    private var filteredWorks: [CachedWork] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base: [CachedWork]
        if q.isEmpty {
            base = offline.downloadedWorks
        } else {
            base = offline.downloadedWorks.filter {
                $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q)
            }
        }
        return offline.worksSorted(base, by: sort)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if offline.downloadedWorks.isEmpty {
                    ThemedEmptyStateView(
                        title: "Нет скачанных книг",
                        systemImage: "arrow.down.circle",
                        description: "Скачайте книгу на её странице — она появится здесь и будет доступна без сети."
                    )
                } else {
                    List {
                        ForEach(filteredWorks, id: \.workId) { work in
                            Button {
                                path.append(LibraryRoute.details(workId: work.workId))
                            } label: {
                                LibraryRow(work: work)
                            }
                            .buttonStyle(.plain)
                            .themedPanelRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task {
                                        await BookVaultSync.shared.deleteOfflineATWork(
                                            workId: work.workId,
                                            store: offline
                                        )
                                    }
                                } label: {
                                    Label("Удалить копию", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .themedAtmosphereList()
                }
            }
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .environment(\.themePreset, appearance.themePreset)
            .environment(\.themeAccent, appearance.accent)
            .navigationTitle("Скачанные")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $query, prompt: "Название или автор")
            .safeAreaInset(edge: .top) {
                if !offline.downloadedWorks.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Picker("Сортировка", selection: $sort) {
                            ForEach(AuthorSortMode.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .themedChromeChip()
                        .tint(appearance.themePreset.chromePrimaryText(colorScheme: .dark))
                        Spacer(minLength: 0)
                        Text(summaryText)
                            .font(.caption)
                            .themedSecondaryText()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.clear)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    Color.clear
                        .onAppear {
                            ReadingSessionStore.shared.presentReader(workId: workId, chapterId: chapterId)
                        }
                case .details(let workId):
                    BookDetailView(workId: workId)
                case .author(let name, let downloadedOnly):
                    AuthorBooksView(author: name, path: $path, downloadedOnly: downloadedOnly)
                case .authorSeries(let author, let series, let downloadedOnly):
                    AuthorSeriesBooksView(author: author, series: series, path: $path, downloadedOnly: downloadedOnly)
                case .authorProfile(let userName, let displayName):
                    AuthorProfileView(userName: userName, displayNameHint: displayName)
                }
            }
            .onAppear { offline.reloadLibrary() }
        }
    }

    private var summaryText: String {
        let full = offline.downloadedWorks.filter(\.isFullyDownloaded).count
        let total = offline.downloadedWorks.count
        if full == total {
            return "\(total) книг офлайн"
        }
        return "\(total) книг · \(full) целиком"
    }
}
