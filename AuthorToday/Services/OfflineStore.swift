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

    private var modelContext: ModelContext?
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
        reloadLibrary()
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

    func authorsGrouped(sortedBy mode: AuthorSortMode) -> [(author: String, works: [CachedWork])] {
        let grouped = Dictionary(grouping: library) { work -> String in
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
    func cacheWorkDetails(_ details: WorkDetails) {
        guard let modelContext else { return }
        let id = details.id
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == id }
        )
        let existing = try? modelContext.fetch(descriptor).first
        let chaptersData = try? JSONEncoder().encode(details.chapters ?? [])
            if let existing {
            existing.title = details.displayTitle
            existing.author = details.displayAuthor
            if let uname = details.authorUserName, !uname.isEmpty {
                existing.authorUserName = uname
            }
            existing.coverURL = WorkMeta.normalizeCover(details.coverUrl)
            existing.annotation = details.annotation
            existing.chaptersJSON = chaptersData
            existing.updatedAt = .now
        } else {
            // Keep offline metadata, but hide from library shelf via localonly
            modelContext.insert(
                CachedWork(
                    workId: details.id,
                    title: details.displayTitle,
                    author: details.displayAuthor,
                    authorUserName: details.authorUserName,
                    coverURL: WorkMeta.normalizeCover(details.coverUrl),
                    annotation: details.annotation,
                    libraryState: "localonly",
                    chaptersJSON: chaptersData
                )
            )
        }
        try? modelContext.save()
        if library.contains(where: { $0.workId == id }) {
            reloadLibrary()
        }
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
        sortIndex: Int
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
        bookProgress: Double? = nil
    ) {
        guard let modelContext else { return }
        let clampedFraction = min(max(fraction, 0), 1)
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate { $0.workId == workId }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            // Don't let a transient zero wipe a good in-chapter position.
            let isSpuriousZero = clampedFraction < 0.01 && pageIndex == 0 && offsetY < 8
            if isSpuriousZero,
               existing.chapterId == chapterId,
               existing.fraction > 0.05 {
                return
            }
            // Don't let a same-chapter regression overwrite a stronger position
            // (reflow / chrome flicker can report ~0.3 right after a 1.0 save).
            if existing.chapterId == chapterId,
               clampedFraction + 0.02 < existing.fraction,
               existing.fraction > 0.2,
               Date().timeIntervalSince(existing.updatedAt) < 3 {
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

        let workDesc = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        if let work = try? modelContext.fetch(workDesc).first {
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

    func isChapterCached(workId: Int, chapterId: Int) -> Bool {
        chapter(workId: workId, chapterId: chapterId) != nil
    }

    func isInLibrary(_ workId: Int) -> Bool {
        library.contains(where: { $0.workId == workId })
    }

    /// Books with all chapters downloaded for offline.
    var fullyDownloadedCount: Int {
        library.filter(\.isFullyDownloaded).count
    }
}
