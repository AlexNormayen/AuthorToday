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
        reloadLibrary()
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
        if !force, let last = lastLibrarySync, Date().timeIntervalSince(last) < 15 {
            reloadLibrary()
            return
        }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            try? await APIClient.shared.establishWebSession()

            // Ensure we know the profile username (needed for /u/{user}/library)
            if AuthService.shared.user?.userName == nil {
                await AuthService.shared.refreshProfile()
            }

            var collected: [WorkMeta] = []
            var errors: [String] = []

            // Primary: full public profile library — this is what the site shows at
            // https://author.today/u/{user}/library (e.g. dark_tarkhan)
            if let username = AuthService.shared.user?.userName, !username.isEmpty {
                do {
                    collected = try await APIClient.shared.libraryFromProfile(username: username, maxPages: 60)
                } catch {
                    errors.append("profile: \(error.localizedDescription)")
                }
            } else {
                errors.append("profile: нет userName")
            }

            // Supplement / fallback: official API (often incomplete vs the site shelf)
            if collected.isEmpty {
                var page = 1
                do {
                    while true {
                        let items = try await APIClient.shared.userLibrary(page: page, pageSize: 50)
                        collected.append(contentsOf: items)
                        if items.isEmpty || items.count < 50 { break }
                        page += 1
                        if page > 40 { break }
                    }
                } catch {
                    errors.append("api: \(error.localizedDescription)")
                }
            }

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
                        // keep offline downloads even if removed remotely
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
        let state = markFromSite
            ? (meta.resolvedLibraryState ?? "Reading")
            : (meta.resolvedLibraryState ?? existing?.libraryState)
        if let existing {
            existing.title = meta.displayTitle
            existing.author = meta.displayAuthor
            existing.coverURL = meta.absoluteCoverURL
            existing.annotation = meta.annotation
            existing.libraryState = state
            existing.lastReadChapterId = meta.lastReadChapterId ?? meta.lastChapterId ?? existing.lastReadChapterId
            existing.progress = meta.resolvedProgress
            existing.updatedAt = .now
        } else {
            let work = CachedWork(
                workId: meta.id,
                title: meta.displayTitle,
                author: meta.displayAuthor,
                coverURL: meta.absoluteCoverURL,
                annotation: meta.annotation,
                libraryState: state,
                lastReadChapterId: meta.lastReadChapterId ?? meta.lastChapterId,
                progress: meta.resolvedProgress
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
            work.updatedAt = .now
        }
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
}
