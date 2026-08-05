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
        library = (try? modelContext.fetch(descriptor)) ?? []
    }

    func syncLibraryIfNeeded(force: Bool = false) async {
        if !force, let last = lastLibrarySync, Date().timeIntervalSince(last) < 60 {
            reloadLibrary()
            return
        }
        await syncLibrary()
    }

    func syncLibrary() async {
        guard let modelContext else { return }
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }

        do {
            var page = 1
            var collected: [WorkMeta] = []
            while true {
                let items = try await APIClient.shared.userLibrary(page: page, pageSize: 50)
                collected.append(contentsOf: items)
                if items.isEmpty || items.count < 50 { break }
                page += 1
                if page > 40 { break }
            }

            for meta in collected {
                upsertWork(from: meta, context: modelContext)
            }
            try modelContext.save()
            lastLibrarySync = .now
            reloadLibrary()
        } catch {
            lastSyncError = error.localizedDescription
            reloadLibrary()
        }
    }

    func upsertWork(from meta: WorkMeta, context: ModelContext? = nil) {
        let ctx = context ?? modelContext
        guard let ctx else { return }
        let id = meta.id
        let descriptor = FetchDescriptor<CachedWork>(
            predicate: #Predicate { $0.workId == id }
        )
        let existing = try? ctx.fetch(descriptor).first
        if let existing {
            existing.title = meta.displayTitle
            existing.author = meta.displayAuthor
            existing.coverURL = meta.absoluteCoverURL
            existing.annotation = meta.annotation
            existing.libraryState = meta.resolvedLibraryState
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
                libraryState: meta.resolvedLibraryState,
                lastReadChapterId: meta.lastReadChapterId ?? meta.lastChapterId,
                progress: meta.resolvedProgress
            )
            ctx.insert(work)
        }
    }

    func upsertWork(from details: WorkDetails) {
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
            modelContext.insert(
                CachedWork(
                    workId: details.id,
                    title: details.displayTitle,
                    author: details.displayAuthor,
                    coverURL: WorkMeta.normalizeCover(details.coverUrl),
                    annotation: details.annotation,
                    chaptersJSON: chaptersData
                )
            )
        }
        try? modelContext.save()
        reloadLibrary()
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
}
