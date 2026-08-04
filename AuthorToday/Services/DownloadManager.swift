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
            store.upsertWork(from: details)
        } else if let cached = store.library.first(where: { $0.workId == workId }),
                  let data = cached.chaptersJSON,
                  let chapters = try? JSONDecoder().decode([ChapterMeta].self, from: data) {
            details = WorkDetails(
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
                isFinished: nil
            )
        } else {
            throw APIError.message("Нет сети и книга ещё не скачана")
        }

        let chapters = details.availableChapters
        guard !chapters.isEmpty else {
            throw APIError.message("Нет доступных глав")
        }

        let startId = preferredChapterId
            ?? store.progress(for: workId)?.chapterId
            ?? chapters.first?.id
            ?? chapters[0].id

        let chapterMeta = chapters.first(where: { $0.id == startId }) ?? chapters[0]
        let (title, html) = try await loadChapter(
            workId: workId,
            chapter: chapterMeta,
            sortIndex: chapters.firstIndex(where: { $0.id == chapterMeta.id }) ?? 0,
            store: store
        )

        // Fire-and-forget full book download once reading started
        Task {
            await downloadEntireBook(details: details, store: store)
        }

        if isOnline {
            try? await APIClient.shared.readerStart(workId: workId, chapterId: chapterMeta.id)
        }

        return (details, chapterMeta.id, html, title)
    }

    func loadChapter(
        workId: Int,
        chapter: ChapterMeta,
        sortIndex: Int,
        store: OfflineStore
    ) async throws -> (title: String, html: String) {
        if let cached = store.chapter(workId: workId, chapterId: chapter.id) {
            return (cached.title, cached.htmlText)
        }
        guard isOnline else {
            throw APIError.message("Глава не скачана, нет сети")
        }

        let (remoteTitle, html) = try await APIClient.shared.chapterText(
            workId: workId,
            chapterId: chapter.id
        )
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

        // Try batch first
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
            // fall through to per-chapter
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
        statusMessage = "«\(details.displayTitle)» — \(cachedCount)/\(chapters.count) глав"
    }
}
