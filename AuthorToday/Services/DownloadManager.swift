import Foundation
import Network

/// Downloads a book when reading starts. Any opened book is cached locally for offline use.
@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var activeDownloads: Set<Int> = []
    @Published var statusMessage: String?

    private let monitor = NWPathMonitor()
    private var isOnline = true
    private var started = false

    private init() {}

    func startMonitoring() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "at.net"))
    }

    var online: Bool { isOnline }

    /// Ensures the chapter is available offline; then downloads the rest of the book in background.
    func openAndCache(
        workId: Int,
        preferredChapterId: Int?,
        store: OfflineStore
    ) async throws -> (details: WorkDetails, chapterId: Int, html: String, title: String) {
        startMonitoring()

        let details: WorkDetails
        if isOnline {
            details = try await APIClient.shared.workDetails(id: workId)
            store.cacheWorkDetails(details)
        } else {
            details = try offlineDetails(workId: workId, store: store)
        }

        let chapters = details.availableChapters
        guard !chapters.isEmpty else {
            throw APIError.message("Нет доступных глав")
        }

        var remoteChapterId: Int?
        if isOnline, let meta = try? await APIClient.shared.workMeta(id: workId) {
            if store.isInLibrary(workId) {
                store.upsertWork(from: meta, markFromSite: true)
            }
            remoteChapterId = meta.lastReadChapterId
        }

        let preferred = preferredChapterId
            ?? store.progress(for: workId)?.chapterId
            ?? remoteChapterId
            ?? store.cachedWork(workId: workId)?.lastReadChapterId

        let startId = pickStartChapterId(
            preferred: preferred,
            chapters: chapters,
            workId: workId,
            store: store,
            online: isOnline
        )

        let chapterMeta = chapters.first(where: { $0.id == startId }) ?? chapters[0]
        let (title, html) = try await loadChapter(
            workId: workId,
            chapter: chapterMeta,
            sortIndex: chapters.firstIndex(where: { $0.id == chapterMeta.id }) ?? 0,
            store: store
        )

        if isOnline {
            try? await APIClient.shared.readerStart(workId: workId, chapterId: chapterMeta.id)
            try? await APIClient.shared.updateProgress(
                workId: workId,
                chapterId: chapterMeta.id,
                progress: nil,
                location: nil
            )
        }

        return (details, chapterMeta.id, html, title)
    }

    /// Offline: rebuild TOC from chaptersJSON or from already cached chapter rows.
    private func offlineDetails(workId: Int, store: OfflineStore) throws -> WorkDetails {
        guard let cached = store.cachedWork(workId: workId) else {
            throw APIError.message("Нет сети и книга ещё не скачана")
        }
        var chapters: [ChapterMeta] = []
        if let data = cached.chaptersJSON,
           let decoded = try? JSONDecoder().decode([ChapterMeta].self, from: data),
           !decoded.isEmpty {
            chapters = decoded
        } else {
            let cachedChapters = store.cachedChapters(workId: workId)
            chapters = cachedChapters.map {
                ChapterMeta(
                    id: $0.chapterId,
                    workId: workId,
                    title: $0.title,
                    isAvailable: true,
                    publishTime: nil,
                    lastUpdateTime: nil,
                    textLength: nil,
                    isDraft: false
                )
            }
        }
        guard !chapters.isEmpty else {
            throw APIError.message("Нет сети и нет сохранённых глав этой книги")
        }
        return WorkDetails(
            id: workId,
            title: cached.title,
            authorFIO: cached.author,
            authorUserName: nil,
            coverUrl: cached.coverURL,
            annotation: cached.annotation,
            chapters: chapters,
            status: nil,
            genreName: nil,
            secondGenreName: nil,
            likeCount: nil,
            viewsCount: nil,
            chapterCount: chapters.count,
            downloadAllowed: nil,
            isFinished: nil,
            price: nil,
            discount: nil,
            isPurchased: nil,
            orderStatus: nil,
            orderStatusMessage: nil,
            freeChapterCount: nil
        )
    }

    /// Prefer requested chapter if cached; otherwise any downloaded chapter (offline).
    private func pickStartChapterId(
        preferred: Int?,
        chapters: [ChapterMeta],
        workId: Int,
        store: OfflineStore,
        online: Bool
    ) -> Int {
        if let preferred,
           chapters.contains(where: { $0.id == preferred }),
           online || store.isChapterCached(workId: workId, chapterId: preferred) {
            return preferred
        }
        if !online {
            if let cached = chapters.first(where: { store.isChapterCached(workId: workId, chapterId: $0.id) }) {
                return cached.id
            }
        }
        return preferred.flatMap { id in chapters.contains(where: { $0.id == id }) ? id : nil }
            ?? chapters.first?.id
            ?? chapters[0].id
    }

    func loadChapter(
        workId: Int,
        chapter: ChapterMeta,
        sortIndex: Int,
        store: OfflineStore
    ) async throws -> (title: String, html: String) {
        if let cached = store.chapter(workId: workId, chapterId: chapter.id) {
            if ChapterDecryptor.looksLikePlaintext(cached.htmlText) {
                return (cached.title, cached.htmlText)
            }
            store.removeCachedChapter(workId: workId, chapterId: chapter.id)
        }
        guard isOnline else {
            if let cached = store.chapter(workId: workId, chapterId: chapter.id),
               ChapterDecryptor.looksLikePlaintext(cached.htmlText) {
                return (cached.title, cached.htmlText)
            }
            throw APIError.message("Эта глава не скачана. Нужен интернет или скачайте книгу целиком на карточке книги.")
        }

        let (remoteTitle, html) = try await APIClient.shared.chapterText(
            workId: workId,
            chapterId: chapter.id
        )
        guard ChapterDecryptor.looksLikePlaintext(html) else {
            throw APIError.message("Получен повреждённый текст главы")
        }
        let title = remoteTitle ?? chapter.displayTitle
        store.saveChapter(
            workId: workId,
            chapterId: chapter.id,
            title: title,
            html: html,
            sortIndex: sortIndex
        )
        return (title, html)
    }

    func downloadEntireBook(details: WorkDetails, store: OfflineStore) async {
        let workId = details.id
        guard !activeDownloads.contains(workId) else { return }
        guard isOnline else { return }

        activeDownloads.insert(workId)
        store.downloadProgress[workId] = 0
        defer {
            activeDownloads.remove(workId)
        }

        let chapters = details.availableChapters
        guard !chapters.isEmpty else { return }

        do {
            let batch = try await APIClient.shared.manyChapterTexts(workId: workId)
            if !batch.isEmpty {
                let byId = Dictionary(uniqueKeysWithValues: chapters.enumerated().map { ($0.element.id, $0.offset) })
                for item in batch where item.id != 0 {
                    store.saveChapter(
                        workId: workId,
                        chapterId: item.id,
                        title: item.title ?? "Глава",
                        html: item.html,
                        sortIndex: byId[item.id] ?? 0
                    )
                }
                store.downloadProgress[workId] = 1
                store.markDownloaded(workId: workId, fully: true)
                statusMessage = "«\(details.displayTitle)» скачана"
                return
            }
        } catch {
            // fall through
        }

        for (index, chapter) in chapters.enumerated() {
            if store.isChapterCached(workId: workId, chapterId: chapter.id) {
                store.downloadProgress[workId] = Double(index + 1) / Double(chapters.count)
                continue
            }
            do {
                _ = try await loadChapter(
                    workId: workId,
                    chapter: chapter,
                    sortIndex: index,
                    store: store
                )
            } catch {
                statusMessage = "Ошибка загрузки главы: \(chapter.displayTitle)"
            }
            store.downloadProgress[workId] = Double(index + 1) / Double(chapters.count)
        }

        let cachedCount = store.cachedChapters(workId: workId).count
        store.markDownloaded(workId: workId, fully: cachedCount >= chapters.count)
        statusMessage = cachedCount >= chapters.count
            ? "«\(details.displayTitle)» скачана"
            : "Скачано \(cachedCount) из \(chapters.count) глав"
    }
}
