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
            base = shelfWorks.filter {
                $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q)
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
            .navigationTitle("Библиотека")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .modifier(LibrarySearchModifier(isEnabled: mode != .mine, query: $query))
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
                    .background(.ultraThinMaterial.opacity(0.7))
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
                            .foregroundStyle(.secondary)
                        Spacer()
                        if offline.isSyncing {
                            Text(offline.syncStatusText ?? "синхронизация…")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial.opacity(0.55))
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
                    ReaderView(workId: workId, initialChapterId: chapterId)
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
            }
            .safeAreaInset(edge: .bottom) {
                if let msg = downloads.statusMessage {
                    Text(msg)
                        .font(.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                } else if mode != .mine, let err = offline.lastSyncError {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                }
            }
            .task {
                offline.reloadLibrary()
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
            ContentUnavailableView(
                "Библиотека пуста",
                systemImage: "books.vertical",
                description: Text(emptyLibraryMessage)
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
            ContentUnavailableView(
                "Библиотека пуста",
                systemImage: "books.vertical",
                description: Text(emptyLibraryMessage)
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
                            Text(authorSubtitle(group))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(
                    Rectangle().fill(.ultraThinMaterial.opacity(0.82))
                )
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                    Divider().padding(.leading, 88)
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
        let filtered = source.filter { matchesAuthor($0) }
        return downloadedOnly ? offline.worksSorted(filtered, by: sort) : filtered
    }

    private var seriesGroups: [(series: String, works: [CachedWork])] {
        let grouped = Dictionary(grouping: works) { $0.displaySeriesFolder }
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
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .themedGroupedFill()
        .navigationTitle(author)
        .navigationBarTitleDisplayMode(.inline)
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
                    Divider().padding(.leading, 88)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func matchesAuthor(_ work: CachedWork) -> Bool {
        if author == "Без автора" {
            return work.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return work.author.caseInsensitiveCompare(author) == .orderedSame
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
        return source
            .filter { work in
                let authorMatch = author == "Без автора"
                    ? work.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    : work.author.caseInsensitiveCompare(author) == .orderedSame
                return authorMatch && work.displaySeriesFolder == series
            }
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
                    Divider().padding(.leading, 88)
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
                    ContentUnavailableView(
                        "Пока пусто",
                        systemImage: "clock",
                        description: Text("Здесь появятся книги после чтения в приложении или на сайте. Потяните вниз, чтобы обновить порядок с портала.")
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
                                                .foregroundStyle(.tertiary)
                                                .padding(.leading, 88)
                                                .padding(.bottom, 8)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .background(.ultraThinMaterial.opacity(0.75))
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 88)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .refreshable {
                await offline.syncLibrary(force: true)
            }
            .navigationTitle("Недавние")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    ReaderView(workId: workId, initialChapterId: chapterId)
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
    @EnvironmentObject private var appearance: AppAppearanceStore

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

                if showAuthor {
                    Text(work.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if work.isFullyDownloaded {
                        Label("Офлайн", systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(appearance.accent)
                    } else if let cov = offline.offlineChapterCoverage(workId: work.workId), cov.ready > 0 {
                        Label("\(cov.ready)/\(cov.total)", systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let chapterId = work.lastReadChapterId,
                              offline.isChapterCached(workId: work.workId, chapterId: chapterId) {
                        Label("Глава офлайн", systemImage: "arrow.down.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
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
                    ContentUnavailableView(
                        "Нет скачанных книг",
                        systemImage: "arrow.down.circle",
                        description: Text("Скачайте книгу на её странице — она появится здесь и будет доступна без сети.")
                    )
                } else {
                    VStack(spacing: 0) {
                        Picker("Сортировка", selection: $sort) {
                            ForEach(AuthorSortMode.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredWorks, id: \.workId) { work in
                                    Button {
                                        path.append(LibraryRoute.details(workId: work.workId))
                                    } label: {
                                        LibraryRow(work: work)
                                    }
                                    .buttonStyle(.plain)
                                    Divider().padding(.leading, 88)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .background {
                ThemeAtmosphereView(preset: appearance.themePreset)
            }
            .navigationTitle("Скачанные")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .searchable(text: $query, prompt: "Название или автор")
            .safeAreaInset(edge: .top) {
                if !offline.downloadedWorks.isEmpty {
                    HStack {
                        Text(summaryText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial.opacity(0.55))
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    ReaderView(workId: workId, initialChapterId: chapterId)
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
