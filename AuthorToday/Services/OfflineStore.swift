import Foundation
import SwiftData
import Combine

@MainActor
final class OfflineStore: ObservableObject {
    static let shared = OfflineStore()

    @Published var library: [CachedWork] = []
    @Published var isSyncing = false
    @Published var syncStatusText: String?
    @Published var syncLoadedCount: Int = 0
    @Published var syncExpectedTotal: Int = 0
    @Published var downloadProgress: [Int: Double] = [:] // workId -> 0...1
    @Published var lastSyncError: String?
    @Published var lastSyncCount: Int = 0

    private(set) var modelContext: ModelContext?
    private var lastLibrarySync: Date? {
        get { UserDefaults.standard.object(forKey: "at.lastLibrarySync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "at.lastLibrarySync") }
    }

    private var librarySyncIncomplete: Bool {
        get { UserDefaults.standard.bool(forKey: "at.librarySyncIncomplete") }
        set { UserDefaults.standard.set(newValue, forKey: "at.librarySyncIncomplete") }
    }

    private var pendingExpectedTotal: Int {
        get { UserDefaults.standard.integer(forKey: "at.librarySyncExpected") }
        set { UserDefaults.standard.set(newValue, forKey: "at.librarySyncExpected") }
    }

    private var lastSuccessfulLibraryPage: Int {
        get { UserDefaults.standard.integer(forKey: "at.librarySyncLastPage") }
        set { UserDefaults.standard.set(newValue, forKey: "at.librarySyncLastPage") }
    }

    func attach(context: ModelContext) {
        modelContext = context
        purgeBadChapterCacheIfNeeded()
        backfillLastReadAtIfNeeded()
        repairLastReadAtFromLocalProgressIfNeeded()
        normalizeStoredProgressIfNeeded()
        seedKnownChapterCounts()
        reloadLibrary()
    }

    private func seedKnownChapterCounts() {
        for work in downloadedWorks {
            let count: Int
            if let data = work.chaptersJSON,
               let chapters = try? JSONDecoder().decode([ChapterMeta].self, from: data) {
                count = chapters.count
            } else {
                count = cachedChapters(workId: work.workId).count
            }
            NotificationPoller.shared.rememberChapterCount(workId: work.workId, count: count)
        }
    }

    /// Migrate older installs: copy ReadingProgress.updatedAt → CachedWork.lastReadAt
    private func backfillLastReadAtIfNeeded() {
        let key = "at.lastReadAtBackfill.v2"
        guard !UserDefaults.standard.bool(forKey: key), let modelContext else { return }
        let works = (try? modelContext.fetch(FetchDescriptor<CachedWork>())) ?? []
        let progressRows = (try? modelContext.fetch(FetchDescriptor<ReadingProgress>())) ?? []
        let byWork = Dictionary(uniqueKeysWithValues: progressRows.map { ($0.workId, $0) })
        for work in works where work.lastReadAt == nil {
            if let p = byWork[work.workId] {
                work.lastReadAt = p.updatedAt
                work.lastReadChapterId = work.lastReadChapterId ?? p.chapterId
            } else if work.lastReadChapterId != nil || work.progress > 0.001 {
                // Site sync already had reading markers without a local timestamp.
                work.lastReadAt = work.updatedAt
            }
        }
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Older builds set lastReadAt from work lastUpdateTime / library sync time — not user reading.
    /// Re-anchor to local ReadingProgress and drop invented timestamps.
    private func repairLastReadAtFromLocalProgressIfNeeded() {
        let key = "at.lastReadAtRepair.v3"
        guard !UserDefaults.standard.bool(forKey: key), let modelContext else { return }
        let works = (try? modelContext.fetch(FetchDescriptor<CachedWork>())) ?? []
        let progressRows = (try? modelContext.fetch(FetchDescriptor<ReadingProgress>())) ?? []
        let byWork = Dictionary(uniqueKeysWithValues: progressRows.map { ($0.workId, $0) })
        for work in works {
            if let p = byWork[work.workId] {
                work.lastReadAt = p.updatedAt
                work.lastReadChapterId = work.lastReadChapterId ?? p.chapterId
            } else {
                work.lastReadAt = nil
            }
        }
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Fix rows where API percent (e.g. 96) was stored instead of 0…1 fraction.
    private func normalizeStoredProgressIfNeeded() {
        let key = "at.progressNormalized.v1"
        guard !UserDefaults.standard.bool(forKey: key), let modelContext else { return }
        let works = (try? modelContext.fetch(FetchDescriptor<CachedWork>())) ?? []
        for work in works where work.progress > 1 {
            work.progress = min(work.progress / 100.0, 1)
        }
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// One-shot wipe of chapters cached by older builds that used the wrong decrypt key.
    private func purgeBadChapterCacheIfNeeded() {
        let key = "at.chapterCacheVersion"
        let current = 3
        let stored = UserDefaults.standard.integer(forKey: key)
        guard stored < current, let modelContext else {
            if stored < current { UserDefaults.standard.set(current, forKey: key) }
            return
        }
        let descriptor = FetchDescriptor<CachedChapter>()
        if let items = try? modelContext.fetch(descriptor) {
            for item in items where !ChapterDecryptor.looksLikePlaintext(item.htmlText) {
                modelContext.delete(item)
            }
            try? modelContext.save()
        }
        UserDefaults.standard.set(current, forKey: key)
    }

    func reloadLibrary() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedWork>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        // Only show works that belong to the site library (or were explicitly added)
        let all = (try? modelContext.fetch(descriptor)) ?? []
        library = all.filter { work in
            guard let state = work.libraryState?.lowercased() else { return true }
            return state != "localonly" && state != "none"
        }
        objectWillChange.send()
    }

    /// Books read recently in the app or on the portal, newest first.
    var recentlyRead: [CachedWork] {
        guard let modelContext else { return [] }
        let all = (try? modelContext.fetch(FetchDescriptor<CachedWork>())) ?? []
        let localDates = localProgressDates()
        return all
            .filter { work in
                work.lastReadAt != nil
                    || work.lastReadChapterId != nil
                    || work.progress > 0.001
                    || localDates[work.workId] != nil
            }
            .sorted {
                effectiveLastReadAt($0, localDates: localDates)
                    > effectiveLastReadAt($1, localDates: localDates)
            }
    }

    /// Prefer real in-app ReadingProgress time; else CachedWork.lastReadAt (incl. portal order).
    func effectiveLastReadAt(_ work: CachedWork) -> Date {
        effectiveLastReadAt(work, localDates: localProgressDates())
    }

    private func effectiveLastReadAt(_ work: CachedWork, localDates: [Int: Date]) -> Date {
        if let local = localDates[work.workId] {
            return max(local, work.lastReadAt ?? .distantPast)
        }
        return work.lastReadAt ?? .distantPast
    }

    private func localProgressDates() -> [Int: Date] {
        guard let modelContext else { return [:] }
        let rows = (try? modelContext.fetch(FetchDescriptor<ReadingProgress>())) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.workId, $0.updatedAt) })
    }

    /// Authors as folders for the library shelf.
    var authorsGrouped: [(author: String, works: [CachedWork])] {
        authorsGrouped(sortedBy: .name)
    }

    /// Books with at least one readable cached chapter (or marked fully downloaded).
    var downloadedWorks: [CachedWork] {
        guard let modelContext else { return [] }
        let all = (try? modelContext.fetch(FetchDescriptor<CachedWork>())) ?? []
        let readableIds = readableOfflineWorkIds()
        return all.filter { $0.isFullyDownloaded || readableIds.contains($0.workId) }
    }

    func downloadedAuthorsGrouped(sortedBy mode: AuthorSortMode) -> [(author: String, works: [CachedWork])] {
        authorsGrouped(from: downloadedWorks, sortedBy: mode)
    }

    func authorsGrouped(sortedBy mode: AuthorSortMode) -> [(author: String, works: [CachedWork])] {
        authorsGrouped(from: library, sortedBy: mode)
    }

    func authorsGrouped(
        from works: [CachedWork],
        sortedBy mode: AuthorSortMode
    ) -> [(author: String, works: [CachedWork])] {
        let grouped = Dictionary(grouping: works) { work -> String in
            let name = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Без автора" : name
        }
        let mapped = grouped.map { key, value -> (author: String, works: [CachedWork]) in
            let sortedWorks = value.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return (author: key, works: sortedWorks)
        }
        switch mode {
        case .name:
            return mapped.sorted {
                $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
        case .bookCount:
            return mapped.sorted {
                if $0.works.count != $1.works.count { return $0.works.count > $1.works.count }
                return $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
        case .recentlyRead:
            let localDates = localProgressDates()
            return mapped.sorted {
                let l = $0.works.map { effectiveLastReadAt($0, localDates: localDates) }.max() ?? .distantPast
                let r = $1.works.map { effectiveLastReadAt($0, localDates: localDates) }.max() ?? .distantPast
                if l != r { return l > r }
                return $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
        case .popularity:
            return mapped.sorted {
                let l = $0.works.reduce(0) { $0 + ($1.likeCount ?? 0) }
                let r = $1.works.reduce(0) { $0 + ($1.likeCount ?? 0) }
                if l != r { return l > r }
                let lv = $0.works.reduce(0) { $0 + ($1.viewsCount ?? 0) }
                let rv = $1.works.reduce(0) { $0 + ($1.viewsCount ?? 0) }
                if lv != rv { return lv > rv }
                return $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending
            }
        }
    }

    /// Flat shelf sorted with the same modes as the authors list.
    func worksSorted(_ works: [CachedWork], by mode: AuthorSortMode) -> [CachedWork] {
        switch mode {
        case .name:
            return works.sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .bookCount:
            let counts = Dictionary(grouping: library) { work -> String in
                let name = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? "Без автора" : name
            }.mapValues(\.count)
            return works.sorted { a, b in
                let ca = counts[authorKey(a)] ?? 0
                let cb = counts[authorKey(b)] ?? 0
                if ca != cb { return ca > cb }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .recentlyRead:
            let localDates = localProgressDates()
            return works.sorted { a, b in
                let la = effectiveLastReadAt(a, localDates: localDates)
                let lb = effectiveLastReadAt(b, localDates: localDates)
                if la != lb { return la > lb }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        case .popularity:
            return works.sorted { a, b in
                let la = a.likeCount ?? 0
                let lb = b.likeCount ?? 0
                if la != lb { return la > lb }
                let va = a.viewsCount ?? 0
                let vb = b.viewsCount ?? 0
                if va != vb { return va > vb }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    private func authorKey(_ work: CachedWork) -> String {
        let name = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Без автора" : name
    }

    func syncLibraryIfNeeded(force: Bool = false) async {
        if librarySyncIncomplete {
            await syncLibrary(force: true)
            return
        }
        if !force, let last = lastLibrarySync, Date().timeIntervalSince(last) < 60 {
            reloadLibrary()
            return
        }
        await syncLibrary(force: force)
    }

    func syncLibrary(force: Bool = false) async {
        guard let modelContext else { return }
        if isSyncing { return }
        if !force, let last = lastLibrarySync, Date().timeIntervalSince(last) < 15 {
            reloadLibrary()
            return
        }
        isSyncing = true
        lastSyncError = nil
        syncStatusText = "Подключение…"
        syncLoadedCount = 0
        syncExpectedTotal = 0
        defer {
            isSyncing = false
            syncStatusText = nil
        }

        do {
            try? await APIClient.shared.establishWebSession()

            // Ensure profile username is known before scraping /u/{user}/library
            if AuthService.shared.user?.userName == nil || AuthService.shared.user?.userName?.isEmpty == true {
                await AuthService.shared.refreshProfile()
            }

            var collected: [WorkMeta] = []
            var errors: [String] = []
            var byID: [Int: WorkMeta] = [:]

            // Resume incomplete sync from what is already on disk
            if librarySyncIncomplete {
                for work in library {
                    if byID[work.workId] == nil {
                        byID[work.workId] = WorkMeta.stub(
                            id: work.workId,
                            title: work.title,
                            author: work.author,
                            coverUrl: work.coverURL,
                            libraryState: work.libraryState ?? "Reading"
                        )
                    }
                }
                if pendingExpectedTotal > 0 {
                    syncExpectedTotal = pendingExpectedTotal
                }
            }

            func merge(_ items: [WorkMeta]) {
                for item in items {
                    byID[item.id] = item
                }
            }

            func publishProgress(expected: Int?) {
                syncLoadedCount = byID.count
                if let expected, expected > 0 {
                    syncExpectedTotal = max(syncExpectedTotal, expected)
                    syncStatusText = "\(byID.count) / \(syncExpectedTotal)"
                } else {
                    syncStatusText = "\(byID.count) книг…"
                }
            }

            publishProgress(expected: syncExpectedTotal > 0 ? syncExpectedTotal : nil)

            // Primary: official API — keep going until last page / totalCount, pacing 429s automatically.
            let pageSize = 100
            let deadline = Date().addingTimeInterval(20 * 60) // one continuous sync session
            var expectedTotal: Int? = syncExpectedTotal > 0 ? syncExpectedTotal : nil
            var page = librarySyncIncomplete ? max(1, lastSuccessfulLibraryPage + 1) : 1
            var consecutiveRateLimits = 0

            if !librarySyncIncomplete {
                lastSuccessfulLibraryPage = 0
            }

            while Date() < deadline, page <= 200 {
                do {
                    let result = try await APIClient.shared.userLibraryPage(page: page, pageSize: pageSize)
                    consecutiveRateLimits = 0
                    if let total = result.totalCount, total > 0 {
                        expectedTotal = total
                    }
                    merge(result.items)
                    for meta in result.items {
                        upsertWork(from: meta, context: modelContext, markFromSite: true)
                    }
                    try? modelContext.save()
                    lastSuccessfulLibraryPage = page
                    reloadLibrary()
                    publishProgress(expected: expectedTotal)

                    let reachedTotal = expectedTotal.map { byID.count >= $0 } ?? false
                    if result.items.isEmpty || result.isLastPage || reachedTotal {
                        break
                    }
                    page += 1
                    // Gentle pacing so we rarely hit 429 (~6 pages for ~547 books at 100/page)
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                } catch let error as APIError {
                    if case .http(let code, _) = error, code == 429 || code == 503 {
                        consecutiveRateLimits += 1
                        let seconds = min(90, 8 + consecutiveRateLimits * 7) // 15, 22, 29… → 90
                        syncStatusText = "Пауза \(seconds)с (лимит API) · \(byID.count)"
                            + (expectedTotal.map { " / \($0)" } ?? "")
                        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                        continue // same page
                    }
                    errors.append("api: \(error.localizedDescription)")
                    break
                } catch {
                    errors.append("api: \(error.localizedDescription)")
                    break
                }
            }

            if let expected = expectedTotal, byID.count < expected, Date() >= deadline {
                errors.append("api: время ожидания истекло (\(byID.count)/\(expected))")
            }

            // Supplement: profile HTML shelf fills any gaps without requiring another tap
            let username = AuthService.shared.resolvedUserName
            if let username, !username.isEmpty {
                let needMore = expectedTotal.map { byID.count < $0 } ?? true
                if needMore || byID.isEmpty {
                    syncStatusText = "Догрузка с профиля…"
                    do {
                        let profileItems = try await APIClient.shared.libraryFromProfile(
                            username: username,
                            maxPages: 60,
                            enrichMissingOnly: true,
                            knownIDs: Set(byID.keys)
                        )
                        merge(profileItems)
                        for meta in profileItems {
                            upsertWork(from: meta, context: modelContext, markFromSite: true)
                        }
                        try? modelContext.save()
                        reloadLibrary()
                        publishProgress(expected: expectedTotal ?? byID.count)
                    } catch {
                        errors.append("profile: \(error.localizedDescription)")
                    }
                }

                // Always refresh "Недавние" order from portal last-read shelf.
                syncStatusText = "Недавние с сайта…"
                do {
                    let recentIDs = try await APIClient.shared.libraryLastReadIDs(
                        username: username,
                        maxPages: 5
                    )
                    applyPortalLastReadOrder(recentIDs, context: modelContext)
                    try? modelContext.save()
                } catch {
                    errors.append("recent: \(error.localizedDescription)")
                }
            } else if byID.isEmpty {
                errors.append("profile: нет userName — обновите профиль в «Ещё»")
            }

            collected = Array(byID.values)

            guard !collected.isEmpty else {
                lastSyncError = errors.isEmpty
                    ? "Библиотека на сайте пуста или недоступна"
                    : errors.joined(separator: "; ")
                reloadLibrary()
                return
            }

            let syncedIDs = Set(collected.map(\.id))
            for meta in collected {
                upsertWork(from: meta, context: modelContext, markFromSite: true)
            }

            let syncLooksComplete = expectedTotal.map { collected.count >= $0 } ?? errors.isEmpty
            // Drop local-only leftovers only after a complete sync (partial runs must not prune unread pages)
            if syncLooksComplete {
                let descriptor = FetchDescriptor<CachedWork>()
                if let existing = try? modelContext.fetch(descriptor) {
                    for work in existing where !syncedIDs.contains(work.workId) {
                        let state = (work.libraryState ?? "").lowercased()
                        if state == "localonly" || work.isFullyDownloaded == false && work.chaptersJSON == nil {
                            if !work.isFullyDownloaded {
                                modelContext.delete(work)
                            } else {
                                work.libraryState = "localonly"
                            }
                        }
                    }
                }
            }

            try modelContext.save()
            lastLibrarySync = .now
            lastSyncCount = collected.count
            if let expected = expectedTotal, collected.count < expected {
                librarySyncIncomplete = true
                pendingExpectedTotal = expected
                lastSyncError = nil
                // Site rate limit window — resume automatically without another tap
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 45_000_000_000)
                    await self?.syncLibrary(force: true)
                }
            } else {
                librarySyncIncomplete = false
                pendingExpectedTotal = 0
                lastSuccessfulLibraryPage = 0
                lastSyncError = errors.isEmpty ? nil : errors.joined(separator: "; ")
            }
            reloadLibrary()
        } catch {
            lastSyncError = error.localizedDescription
            reloadLibrary()
        }
    }

    func addToSiteLibrary(workId: Int, state: String = "Reading") async throws {
        try await APIClient.shared.addToLibrary(workId: workId, state: state)
        if let meta = try? await APIClient.shared.workMeta(id: workId) {
            upsertWork(from: meta, markFromSite: true)
            try? modelContext?.save()
            reloadLibrary()
        }
    }

    func removeCachedChapter(workId: Int, chapterId: Int) {
        guard let modelContext else { return }
        let key = "\(workId)-\(chapterId)"
        let descriptor = FetchDescriptor<CachedChapter>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }

    func clearCachedChapters(workId: Int) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedChapter>(
            predicate: #Predicate { $0.workId == workId }
        )
        if let items = try? modelContext.fetch(descriptor) {
            for item in items { modelContext.delete(item) }
            try? modelContext.save()
        }
        markDownloaded(workId: workId, fully: false)
    }

    func upsertWork(from meta: WorkMeta, context: ModelContext? = nil, markFromSite: Bool = true) {
        let ctx = context ?? modelContext
        guard let ctx else { return }
        let id = meta.id
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == id }
        )
        let existing = try? ctx.fetch(descriptor).first
        var state = markFromSite
            ? (meta.resolvedLibraryState ?? "Reading")
            : (meta.resolvedLibraryState ?? existing?.libraryState)
        // Never persist guest "None" for shelf sync — it hides books from the library tab
        if markFromSite, (state ?? "").lowercased() == "none" {
            state = "Reading"
        }
        if let existing {
            existing.title = meta.displayTitle
            existing.author = meta.displayAuthor
            if let uname = meta.authorUserName, !uname.isEmpty {
                existing.authorUserName = uname
            }
            existing.coverURL = meta.absoluteCoverURL ?? existing.coverURL
            existing.annotation = meta.annotation ?? existing.annotation
            existing.libraryState = state
            // Site → app: adopt remote last-read chapter when API provides it
            if let remoteChapter = meta.lastReadChapterId {
                existing.lastReadChapterId = remoteChapter
            }
            let remoteProgress = meta.resolvedProgress
            if remoteProgress > 0 {
                existing.progress = min(max(existing.progress, remoteProgress), 1)
            }
            if let likes = meta.likeCount {
                existing.likeCount = likes
            }
            if let views = meta.viewsCount ?? meta.viewCount {
                existing.viewsCount = views
            }
            if let chapters = meta.chapterCount {
                NotificationPoller.shared.rememberChapterCount(workId: meta.id, count: chapters)
            }
            if let seriesTitle = meta.displaySeriesTitle {
                existing.seriesTitle = seriesTitle
            }
            if let seriesId = meta.seriesId {
                existing.seriesId = seriesId
            }
            if let seriesOrder = meta.seriesOrder {
                existing.seriesOrder = seriesOrder
            }
            // lastReadAt comes from local reading or portal last-read order — not lastUpdateTime.
        } else {
            let work = CachedWork(
                workId: meta.id,
                title: meta.displayTitle,
                author: meta.displayAuthor,
                authorUserName: meta.authorUserName,
                coverURL: meta.absoluteCoverURL,
                annotation: meta.annotation,
                libraryState: state,
                lastReadChapterId: meta.lastReadChapterId,
                progress: min(max(meta.resolvedProgress, 0), 1),
                seriesId: meta.seriesId,
                seriesTitle: meta.displaySeriesTitle,
                seriesOrder: meta.seriesOrder,
                likeCount: meta.likeCount,
                viewsCount: meta.viewsCount ?? meta.viewCount
            )
            ctx.insert(work)
        }
    }

    /// Maps portal shelf order (`sorting=lr`) onto lastReadAt.
    /// Does not use work lastUpdateTime (author publish time). Local ReadingProgress always wins.
    func applyPortalLastReadOrder(_ orderedIDs: [Int], context: ModelContext? = nil) {
        let ctx = context ?? modelContext
        guard let ctx, !orderedIDs.isEmpty else { return }
        // Keep very recent in-app reads above portal ranks that haven't caught up yet.
        let base = Date().addingTimeInterval(-5 * 60)
        for (index, workId) in orderedIDs.enumerated() {
            let descriptor = FetchDescriptor<CachedWork>(
                predicate: #Predicate { $0.workId == workId }
            )
            guard let work = try? ctx.fetch(descriptor).first else { continue }
            if let local = try? ctx.fetch(
                FetchDescriptor<ReadingProgress>(predicate: #Predicate { $0.workId == workId })
            ).first {
                work.lastReadAt = local.updatedAt
                work.lastReadChapterId = work.lastReadChapterId ?? local.chapterId
                continue
            }
            // Synthetic timestamps preserve portal order; refresh every sync.
            work.lastReadAt = base.addingTimeInterval(-Double(index) * 120)
        }
    }

    /// Updates chapter list / cover for a book without adding it to the site library shelf.
    /// - Parameter shelfState: when non-nil, used for newly inserted rows (e.g. `"Reading"` after VPS restore).
    func cacheWorkDetails(_ details: WorkDetails, shelfState: String? = nil) {
        guard let modelContext else { return }
        let id = details.id
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == id }
        )
        let existing = try? modelContext.fetch(descriptor).first
        let chaptersData = try? JSONEncoder().encode(details.chapters ?? [])
        let snapshot = try? JSONEncoder().encode(details)
        if let existing {
            existing.title = details.displayTitle
            existing.author = details.displayAuthor
            if let uname = details.authorUserName, !uname.isEmpty {
                existing.authorUserName = uname
            }
            existing.coverURL = WorkMeta.normalizeCover(details.coverUrl)
            existing.annotation = details.annotation
            existing.chaptersJSON = chaptersData
            existing.detailsJSON = snapshot
            if let remoteChapter = details.resolvedLastReadChapterId {
                existing.lastReadChapterId = existing.lastReadChapterId ?? remoteChapter
            }
            if let shelfState {
                existing.libraryState = shelfState
            }
            existing.updatedAt = .now
            NotificationPoller.shared.rememberChapterCount(
                workId: details.id,
                count: details.chapterCount ?? details.chapters?.count ?? 0
            )
            // TOC may gain new chapters — never keep a stale "fully downloaded" flag.
            let expectedIds = details.availableChapters.map(\.id)
            if !expectedIds.isEmpty {
                let readable = readableOfflineChapterIds(workId: id)
                existing.isFullyDownloaded = expectedIds.allSatisfy { readable.contains($0) }
            }
        } else {
            modelContext.insert(
                CachedWork(
                    workId: details.id,
                    title: details.displayTitle,
                    author: details.displayAuthor,
                    authorUserName: details.authorUserName,
                    coverURL: WorkMeta.normalizeCover(details.coverUrl),
                    annotation: details.annotation,
                    libraryState: shelfState ?? "localonly",
                    lastReadChapterId: details.resolvedLastReadChapterId,
                    chaptersJSON: chaptersData,
                    detailsJSON: snapshot
                )
            )
            NotificationPoller.shared.rememberChapterCount(
                workId: details.id,
                count: details.chapterCount ?? details.chapters?.count ?? 0
            )
        }
        try? modelContext.save()
        reloadLibrary()
    }

    func promoteVaultWorkToShelf(workId: Int) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        guard let work = try? modelContext.fetch(descriptor).first else { return }
        let state = (work.libraryState ?? "").lowercased()
        if state == "localonly" || state == "none" || state.isEmpty {
            work.libraryState = "Reading"
            work.updatedAt = .now
            try? modelContext.save()
            reloadLibrary()
        }
    }

    func ensureVaultPlaceholderWork(workId: Int, title: String) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        if (try? modelContext.fetch(descriptor).first) != nil { return }
        modelContext.insert(
            CachedWork(
                workId: workId,
                title: title,
                author: "",
                libraryState: "Reading",
                isFullyDownloaded: false
            )
        )
        try? modelContext.save()
        reloadLibrary()
    }

    /// Deletes offline chapters/work cache for an AT book. Does not touch author.today library.
    func removeDownloadedWork(workId: Int) {
        guard let modelContext else { return }
        clearCachedChapters(workId: workId)
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        if let work = try? modelContext.fetch(descriptor).first {
            // Keep shelf row if it came from the site; only strip download flags.
            let state = (work.libraryState ?? "").lowercased()
            work.isFullyDownloaded = false
            work.updatedAt = .now
            if state == "localonly" {
                modelContext.delete(work)
            }
        }
        try? modelContext.save()
        reloadLibrary()
    }

    /// Import portal last-read chapter/position when this device has no local resume yet.
    func adoptRemoteResumeIfNeeded(
        workId: Int,
        chapterId: Int?,
        chapterFraction: Double,
        bookProgress: Double?
    ) {
        guard let chapterId else { return }
        let hasLocalCheckpoint = ReadingSessionStore.shared.checkpoint(for: workId)?.hasInChapterProgress == true
        let local = progress(for: workId)
        let hasLocalProgress = (local?.fraction ?? 0) > 0.01
            || (local.map { $0.pageIndex > 0 || $0.offsetY > 8 } ?? false)
        // Same chapter on device but no in-chapter offset yet — still take portal %.
        let canEnrichSameChapter = local?.chapterId == chapterId
            && (local?.fraction ?? 0) < 0.01
            && chapterFraction > 0.01
        if let modelContext {
            let workDesc = FetchDescriptor<CachedWork>(
                predicate: #Predicate { $0.workId == workId }
            )
            if let work = try? modelContext.fetch(workDesc).first {
                if work.lastReadChapterId == nil {
                    work.lastReadChapterId = chapterId
                }
                if let bookProgress, bookProgress > work.progress {
                    work.progress = min(max(bookProgress, 0), 1)
                }
                try? modelContext.save()
            }
        }
        guard canEnrichSameChapter || (!hasLocalCheckpoint && !hasLocalProgress) else { return }
        saveProgress(
            workId: workId,
            chapterId: chapterId,
            offsetY: 0,
            pageIndex: 0,
            fraction: min(max(chapterFraction, 0), 1),
            bookProgress: bookProgress,
            forceChapter: true
        )
    }

    /// Rebuild the book page from the last saved snapshot / TOC / downloaded chapters.
    func workDetailsFromCache(workId: Int) -> WorkDetails? {
        guard let cached = cachedWork(workId: workId) else { return nil }
        if let data = cached.detailsJSON,
           let snapshot = try? JSONDecoder().decode(WorkDetails.self, from: data) {
            return snapshot.mergingOfflineChapters(cachedChapters(workId: workId), workId: workId)
        }
        return detailsFromLegacyCache(cached)
    }

    func hasReadableOfflineChapters(workId: Int) -> Bool {
        cachedChapters(workId: workId).contains { ChapterDecryptor.looksLikePlaintext($0.htmlText) }
    }

    func hasOfflineBookPage(workId: Int) -> Bool {
        guard let cached = cachedWork(workId: workId) else { return false }
        if cached.detailsJSON != nil { return true }
        if cached.chaptersJSON != nil { return true }
        return !cachedChapters(workId: workId).isEmpty
    }

    private func readableOfflineWorkIds() -> Set<Int> {
        guard let modelContext else { return [] }
        let rows = (try? modelContext.fetch(FetchDescriptor<CachedChapter>())) ?? []
        return Set(
            rows.compactMap { chapter in
                ChapterDecryptor.looksLikePlaintext(chapter.htmlText) ? chapter.workId : nil
            }
        )
    }

    private func detailsFromLegacyCache(_ cached: CachedWork) -> WorkDetails {
        var chapters: [ChapterMeta] = []
        if let data = cached.chaptersJSON,
           let decoded = try? JSONDecoder().decode([ChapterMeta].self, from: data),
           !decoded.isEmpty {
            chapters = decoded
        } else {
            chapters = cachedChapters(workId: cached.workId).map {
                ChapterMeta(
                    id: $0.chapterId,
                    workId: cached.workId,
                    title: $0.title,
                    isAvailable: true,
                    publishTime: nil,
                    lastUpdateTime: nil,
                    textLength: nil,
                    isDraft: false
                )
            }
        }
        return WorkDetails(
            id: cached.workId,
            title: cached.title,
            authorFIO: cached.author,
            authorUserName: cached.authorUserName,
            coverUrl: cached.coverURL,
            annotation: cached.annotation,
            chapters: chapters,
            status: nil,
            genreName: nil,
            secondGenreName: nil,
            likeCount: cached.likeCount,
            viewsCount: cached.viewsCount,
            chapterCount: chapters.count,
            downloadAllowed: nil,
            isFinished: nil,
            price: nil,
            discount: nil,
            isPurchased: nil,
            orderStatus: nil,
            orderStatusMessage: nil,
            freeChapterCount: nil,
            lastChapterId: cached.lastReadChapterId,
            lastChapterProgress: nil,
            textLengthLastRead: nil,
            textLength: nil
        ).mergingOfflineChapters(cachedChapters(workId: cached.workId), workId: cached.workId)
    }

    /// Lookup including local-only cached works (not shown in library shelf).
    func cachedWork(workId: Int) -> CachedWork? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func cachedChapters(workId: Int) -> [CachedChapter] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<CachedChapter>(
            predicate: #Predicate { $0.workId == workId },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.chapterId)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func chapter(workId: Int, chapterId: Int) -> CachedChapter? {
        guard let modelContext else { return nil }
        let key = "\(workId)-\(chapterId)"
        let descriptor = FetchDescriptor<CachedChapter>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        return try? modelContext.fetch(descriptor).first
    }

    func saveChapter(
        workId: Int,
        chapterId: Int,
        title: String,
        html: String,
        sortIndex: Int,
        uploadToVault: Bool = true
    ) {
        guard let modelContext else { return }
        let key = "\(workId)-\(chapterId)"
        let descriptor = FetchDescriptor<CachedChapter>(
            predicate: #Predicate { $0.compositeKey == key }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.title = title
            existing.htmlText = html
            existing.sortIndex = sortIndex
            existing.downloadedAt = .now
        } else {
            modelContext.insert(
                CachedChapter(
                    workId: workId,
                    chapterId: chapterId,
                    title: title,
                    htmlText: html,
                    sortIndex: sortIndex
                )
            )
        }
        try? modelContext.save()
        if uploadToVault {
            BookVaultSync.shared.enqueueChapterUpload(
                workId: workId,
                chapterId: chapterId,
                title: title,
                html: html
            )
        }
    }

    func markDownloaded(workId: Int, fully: Bool) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        if let work = try? modelContext.fetch(descriptor).first {
            work.isFullyDownloaded = fully
            work.updatedAt = .now
            try? modelContext.save()
            reloadLibrary()
        }
    }

    func saveProgress(
        workId: Int,
        chapterId: Int,
        offsetY: Double,
        pageIndex: Int,
        fraction: Double = 0,
        bookProgress: Double? = nil,
        forceChapter: Bool = false
    ) {
        guard let modelContext else { return }
        let clampedFraction = min(max(fraction, 0), 1)
        let isSpuriousZero = clampedFraction < 0.01 && pageIndex == 0 && offsetY < 8
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate { $0.workId == workId }
        )
        let workDesc = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        let work = try? modelContext.fetch(workDesc).first

        // Opening the wrong chapter at offset 0 must not erase a further resume point
        // (e.g. feed → book card → reader briefly landing on chapter 1).
        if !forceChapter, isSpuriousZero, let bookProgress, let work,
           bookProgress + 0.03 < work.progress {
            return
        }

        if let existing = try? modelContext.fetch(descriptor).first {
            // Don't let a transient zero wipe a good in-chapter position.
            if isSpuriousZero,
               existing.chapterId == chapterId,
               existing.fraction > 0.05 {
                return
            }
            // Don't let a same-chapter regression overwrite a stronger position
            // (reflow / early restore can report ~0.3 after a ~0.45+ save).
            if existing.chapterId == chapterId,
               clampedFraction + 0.04 < existing.fraction,
               existing.fraction > 0.15,
               Date().timeIntervalSince(existing.updatedAt) < 4 {
                return
            }
            if !forceChapter, isSpuriousZero, existing.chapterId != chapterId,
               existing.fraction > 0.05 || existing.pageIndex > 0 || existing.offsetY > 8 {
                return
            }
            existing.chapterId = chapterId
            existing.offsetY = offsetY
            existing.fraction = clampedFraction
            existing.pageIndex = pageIndex
            existing.updatedAt = .now
        } else {
            modelContext.insert(
                ReadingProgress(
                    workId: workId,
                    chapterId: chapterId,
                    offsetY: offsetY,
                    fraction: clampedFraction,
                    pageIndex: pageIndex
                )
            )
        }

        if let work {
            work.lastReadChapterId = chapterId
            work.lastReadAt = .now
            work.updatedAt = .now
            if let bookProgress {
                let clamped = min(max(bookProgress, 0), 1)
                // Never decrease book % from a transient early-chapter report.
                work.progress = max(work.progress, clamped)
            }
        }
        try? modelContext.save()
        BookVaultSync.shared.enqueueProgressUpload(workId: workId, store: self)
    }

    /// Site / computed book-level progress (0…1) for library %.
    func updateBookProgress(workId: Int, progress: Double) {
        guard let modelContext else { return }
        let clamped = min(max(progress, 0), 1)
        let workDesc = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        guard let work = try? modelContext.fetch(workDesc).first else { return }
        work.progress = max(work.progress, clamped)
        try? modelContext.save()
    }

    func progress(for workId: Int) -> ReadingProgress? {
        guard let modelContext else { return nil }
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate { $0.workId == workId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// True only when chapter body is present and readable offline (not encrypted soup).
    func isChapterCached(workId: Int, chapterId: Int) -> Bool {
        guard let cached = chapter(workId: workId, chapterId: chapterId) else { return false }
        return ChapterDecryptor.looksLikePlaintext(cached.htmlText)
    }

    /// Available TOC ids that already have readable offline bodies.
    func readableOfflineChapterIds(workId: Int) -> Set<Int> {
        Set(
            cachedChapters(workId: workId).compactMap { row in
                ChapterDecryptor.looksLikePlaintext(row.htmlText) ? row.chapterId : nil
            }
        )
    }

    /// Recompute `isFullyDownloaded` from TOC vs readable chapter bodies.
    /// Call after full download and whenever the saved TOC changes.
    func reconcileFullDownloadStatus(workId: Int, expectedChapterIds: [Int]? = nil) {
        let expected: [Int]
        if let expectedChapterIds {
            expected = expectedChapterIds
        } else if let details = workDetailsFromCache(workId: workId) {
            expected = details.availableChapters.map(\.id)
        } else {
            return
        }
        guard !expected.isEmpty else { return }
        let readable = readableOfflineChapterIds(workId: workId)
        let complete = expected.allSatisfy { readable.contains($0) }
        markDownloaded(workId: workId, fully: complete)
    }

    func offlineChapterCoverage(workId: Int) -> (ready: Int, total: Int)? {
        guard let details = workDetailsFromCache(workId: workId) else { return nil }
        let expected = details.availableChapters.map(\.id)
        guard !expected.isEmpty else { return nil }
        let ready = expected.filter { isChapterCached(workId: workId, chapterId: $0) }.count
        return (ready, expected.count)
    }

    func isInLibrary(_ workId: Int) -> Bool {
        library.contains(where: { $0.workId == workId })
    }

    /// Books with all chapters downloaded for offline.
    var fullyDownloadedCount: Int {
        library.filter(\.isFullyDownloaded).count
    }
}
