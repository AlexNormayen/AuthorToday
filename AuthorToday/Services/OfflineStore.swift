import Foundation
import SwiftData
import Combine

@MainActor
final class OfflineStore: ObservableObject {
    static let shared = OfflineStore()

    @Published var library: [CachedWork] = []
    @Published var isSyncing = false
    @Published var downloadProgress: [Int: Double] = [:] // workId -> 0...1
    @Published var lastSyncError: String?
    @Published var lastSyncCount: Int = 0

    private var modelContext: ModelContext?
    private var lastLibrarySync: Date? {
        get { UserDefaults.standard.object(forKey: "at.lastLibrarySync") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "at.lastLibrarySync") }
    }

    func attach(context: ModelContext) {
        modelContext = context
        purgeBadChapterCacheIfNeeded()
        backfillLastReadAtIfNeeded()
        normalizeStoredProgressIfNeeded()
        reloadLibrary()
    }

    /// Migrate older installs: copy ReadingProgress.updatedAt → CachedWork.lastReadAt
    private func backfillLastReadAtIfNeeded() {
        let key = "at.lastReadAtBackfill"
        guard !UserDefaults.standard.bool(forKey: key), let modelContext else { return }
        let works = (try? modelContext.fetch(FetchDescriptor<CachedWork>())) ?? []
        let progressRows = (try? modelContext.fetch(FetchDescriptor<ReadingProgress>())) ?? []
        let byWork = Dictionary(uniqueKeysWithValues: progressRows.map { ($0.workId, $0) })
        for work in works where work.lastReadAt == nil {
            if let p = byWork[work.workId] {
                work.lastReadAt = p.updatedAt
                work.lastReadChapterId = work.lastReadChapterId ?? p.chapterId
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

    /// Books opened recently, newest first (includes local-only downloads with read history).
    var recentlyRead: [CachedWork] {
        guard let modelContext else { return [] }
        let descriptor = FetchDescriptor<CachedWork>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return all
            .filter { $0.lastReadAt != nil }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
    }

    /// Authors as folders for the library shelf.
    var authorsGrouped: [(author: String, works: [CachedWork])] {
        let grouped = Dictionary(grouping: library) { work -> String in
            let name = work.author.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Без автора" : name
        }
        return grouped
            .map { (author: $0.key, works: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
    }

    func syncLibraryIfNeeded(force: Bool = false) async {
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
        defer { isSyncing = false }

        do {
            try? await APIClient.shared.establishWebSession()

            // Ensure profile username is known before scraping /u/{user}/library
            if AuthService.shared.user?.userName == nil || AuthService.shared.user?.userName?.isEmpty == true {
                await AuthService.shared.refreshProfile()
            }

            var collected: [WorkMeta] = []
            var errors: [String] = []
            var byID: [Int: WorkMeta] = [:]

            func merge(_ items: [WorkMeta]) {
                for item in items {
                    byID[item.id] = item
                }
            }

            // Primary: full profile shelf HTML (what the site shows)
            let username = AuthService.shared.resolvedUserName
            if let username, !username.isEmpty {
                do {
                    let profileItems = try await APIClient.shared.libraryFromProfile(username: username, maxPages: 60)
                    merge(profileItems)
                } catch {
                    errors.append("profile: \(error.localizedDescription)")
                }
            } else {
                errors.append("profile: нет userName — обновите профиль в «Ещё»")
            }

            // Always also pull API library and merge (covers private shelf + progress)
            do {
                var page = 1
                while true {
                    let items = try await APIClient.shared.userLibrary(page: page, pageSize: 50)
                    for item in items {
                        let state = (item.resolvedLibraryState ?? "").lowercased()
                        if let existing = byID[item.id] {
                            // Prefer richer meta, keep non-None shelf state
                            let existingState = (existing.resolvedLibraryState ?? "").lowercased()
                            if existingState == "none" || existingState.isEmpty {
                                byID[item.id] = item
                            } else if state != "none" {
                                byID[item.id] = item.withLibraryState(existing.resolvedLibraryState ?? "Reading")
                            }
                        } else if state != "none" {
                            byID[item.id] = item
                        }
                    }
                    if items.isEmpty || items.count < 50 { break }
                    page += 1
                    if page > 40 { break }
                }
            } catch {
                errors.append("api: \(error.localizedDescription)")
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

            // Drop local-only leftovers that are not on the site shelf anymore
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

            try modelContext.save()
            lastLibrarySync = .now
            lastSyncCount = collected.count
            lastSyncError = nil
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
            existing.coverURL = meta.absoluteCoverURL ?? existing.coverURL
            existing.annotation = meta.annotation ?? existing.annotation
            existing.libraryState = state
            // Site → app: adopt remote last-read chapter when API provides it
            if let remoteChapter = meta.lastReadChapterId {
                existing.lastReadChapterId = remoteChapter
            }
            let remoteProgress = meta.resolvedProgress
            if remoteProgress > 0 {
                // Furthest known progress wins (site or app)
                existing.progress = min(max(existing.progress, remoteProgress), 1)
            }
            existing.updatedAt = .now
        } else {
            let work = CachedWork(
                workId: meta.id,
                title: meta.displayTitle,
                author: meta.displayAuthor,
                coverURL: meta.absoluteCoverURL,
                annotation: meta.annotation,
                libraryState: state,
                lastReadChapterId: meta.lastReadChapterId,
                progress: min(max(meta.resolvedProgress, 0), 1)
            )
            ctx.insert(work)
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

    func saveProgress(workId: Int, chapterId: Int, offsetY: Double, pageIndex: Int) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ReadingProgress>(
            predicate: #Predicate { $0.workId == workId }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.chapterId = chapterId
            existing.offsetY = offsetY
            existing.pageIndex = pageIndex
            existing.updatedAt = .now
        } else {
            modelContext.insert(
                ReadingProgress(workId: workId, chapterId: chapterId, offsetY: offsetY, pageIndex: pageIndex)
            )
        }

        let workDesc = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == workId }
        )
        if let work = try? modelContext.fetch(workDesc).first {
            work.lastReadChapterId = chapterId
            work.lastReadAt = .now
            work.updatedAt = .now
        }
        try? modelContext.save()
        reloadLibrary()
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
}
