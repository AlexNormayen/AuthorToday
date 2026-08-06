import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var offline: OfflineStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var mode: LibraryBrowseMode = .authors

    private var filteredWorks: [CachedWork] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return offline.library }
        return offline.library.filter {
            $0.title.lowercased().contains(q) || $0.author.lowercased().contains(q)
        }
    }

    private var filteredAuthors: [(author: String, works: [CachedWork])] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let groups = offline.authorsGrouped
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
            Group {
                if offline.library.isEmpty && offline.isSyncing {
                    ProgressView("Синхронизация библиотеки…")
                } else if offline.library.isEmpty {
                    ContentUnavailableView(
                        "Библиотека пуста",
                        systemImage: "books.vertical",
                        description: Text(emptyLibraryMessage)
                    )
                } else {
                    VStack(spacing: 0) {
                        Picker("Вид", selection: $mode) {
                            ForEach(LibraryBrowseMode.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        if mode == .authors {
                            authorsList
                        } else {
                            booksList(works: filteredWorks)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Библиотека")
            .searchable(text: $query, prompt: "Название или автор")
            .toolbar {
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
            .refreshable {
                await offline.syncLibrary(force: true)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    ReaderView(workId: workId, initialChapterId: chapterId)
                case .details(let workId):
                    BookDetailView(workId: workId)
                case .author(let name):
                    AuthorBooksView(author: name, path: $path)
                }
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
                } else if let err = offline.lastSyncError {
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
                // Show SwiftData shelf immediately; sync only if empty
                offline.reloadLibrary()
                if offline.library.isEmpty, !offline.isSyncing {
                    await offline.syncLibrary(force: true)
                }
            }
        }
    }

    private var authorsList: some View {
        List {
            ForEach(filteredAuthors, id: \.author) { group in
                Button {
                    path.append(LibraryRoute.author(group.author))
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
                            Text(booksCountText(group.works.count))
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
            }
        }
        .listStyle(.plain)
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

    var id: String { rawValue }
    var title: String {
        switch self {
        case .authors: return "Авторы"
        case .all: return "Все книги"
        }
    }
}

enum LibraryRoute: Hashable {
    case reader(workId: Int, chapterId: Int?)
    case details(workId: Int)
    case author(String)
}

struct AuthorBooksView: View {
    let author: String
    @Binding var path: NavigationPath
    @EnvironmentObject private var offline: OfflineStore

    private var works: [CachedWork] {
        offline.library
            .filter { $0.author.caseInsensitiveCompare(author) == .orderedSame || (author == "Без автора" && $0.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(author)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Tab: books sorted by last open/read time in the app.
struct RecentReadsView: View {
    @EnvironmentObject private var offline: OfflineStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if offline.recentlyRead.isEmpty {
                    ContentUnavailableView(
                        "Пока пусто",
                        systemImage: "clock",
                        description: Text("Здесь появятся книги после того, как вы начнёте чтение. Сортировка — по дате последнего открытия.")
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
                                        if let date = work.lastReadAt {
                                            Text(Self.dateText(date))
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .padding(.leading, 88)
                                                .padding(.bottom, 8)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                Divider().padding(.leading, 88)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Недавние")
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .reader(let workId, let chapterId):
                    ReaderView(workId: workId, initialChapterId: chapterId)
                case .details(let workId):
                    BookDetailView(workId: workId)
                case .author(let name):
                    AuthorBooksView(author: name, path: $path)
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
