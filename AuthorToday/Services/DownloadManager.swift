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
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "at.net"))
    }

    var online: Bool { isOnline }

    /// Opens a book from the local cache when possible. Network is used to refresh, never to block a downloaded book.
    func openAndCache(
        workId: Int,
        preferredChapterId: Int?,
        store: OfflineStore
    ) async throws -> (details: WorkDetails, chapterId: Int, html: String, title: String) {
        startMonitoring()

        let cachedDetails = store.workDetailsFromCache(workId: workId)
        let hasOfflineText = store.hasReadableOfflineChapters(workId: workId)

        let details: WorkDetails
        if hasOfflineText, let cachedDetails {
            details = cachedDetails
            if isOnline {
                Task { await refreshBookPageIfPossible(workId: workId, store: store) }
            }
        } else if isOnline {
            do {
                details = try await APIClient.shared.workDetails(id: workId)
                store.cacheWorkDetails(details)
            } catch {
                if let cachedDetails {
                    details = cachedDetails
                } else {
                    throw error
                }
            }
        } else if let cachedDetails {
            details = cachedDetails
        } else {
            throw APIError.message("Нет сети и книга ещё не скачана")
        }

        let chapters = details.availableChapters
        guard !chapters.isEmpty else {
            throw APIError.message("Нет доступных глав")
        }

        var remoteChapterId: Int?
        var remoteChapterFraction = 0.0
        if isOnline, !hasOfflineText, let meta = try? await APIClient.shared.workMeta(id: workId) {
            if store.isInLibrary(workId) {
                store.upsertWork(from: meta, markFromSite: true)
            }
            remoteChapterId = meta.resolvedLastReadChapterId
            remoteChapterFraction = meta.resolvedChapterProgress
            // Keep site book-% for library display until local reading updates it.
            if meta.resolvedProgress > 0 {
                store.updateBookProgress(workId: workId, progress: meta.resolvedProgress)
            }
            // Seed local resume from portal when this device has never opened the book.
            store.adoptRemoteResumeIfNeeded(
                workId: workId,
                chapterId: remoteChapterId,
                chapterFraction: remoteChapterFraction,
                bookProgress: meta.resolvedProgress
            )
        }
        // Details payload carries the same last-read fields — use if meta-info missed them.
        if remoteChapterId == nil {
            remoteChapterId = details.resolvedLastReadChapterId
            remoteChapterFraction = details.resolvedChapterProgress
            store.adoptRemoteResumeIfNeeded(
                workId: workId,
                chapterId: remoteChapterId,
                chapterFraction: remoteChapterFraction,
                bookProgress: nil
            )
        }

        let startId = resolveStartChapterId(
            preferredChapterId: preferredChapterId,
            remoteChapterId: remoteChapterId,
            remoteChapterFraction: remoteChapterFraction,
            chapters: chapters,
            workId: workId,
            store: store,
            online: isOnline && !hasOfflineText
        )

        let chapterMeta = chapters.first(where: { $0.id == startId }) ?? chapters[0]
        let (title, html) = try await loadChapter(
            workId: workId,
            chapter: chapterMeta,
            sortIndex: chapters.firstIndex(where: { $0.id == chapterMeta.id }) ?? 0,
            store: store
        )

        // Mark reader session on the site, but do NOT call update-progress here —
        // sending chapter 1 with nil progress was wiping the portal's last-read chapter.
        // Never block opening a downloaded book on this call.
        if isOnline, !hasOfflineText {
            try? await APIClient.shared.readerStart(workId: workId, chapterId: chapterMeta.id)
        } else if isOnline {
            Task {
                try? await APIClient.shared.readerStart(workId: workId, chapterId: chapterMeta.id)
            }
        }

        return (details, chapterMeta.id, html, title)
    }

    /// Refresh the saved book page when the portal is reachable. Failures are ignored.
    private func refreshBookPageIfPossible(workId: Int, store: OfflineStore) async {
        do {
            let details = try await APIClient.shared.workDetails(id: workId)
            store.cacheWorkDetails(details)
            if let meta = try? await APIClient.shared.workMeta(id: workId) {
                if store.isInLibrary(workId) {
                    store.upsertWork(from: meta, markFromSite: true)
                }
                store.adoptRemoteResumeIfNeeded(
                    workId: workId,
                    chapterId: meta.resolvedLastReadChapterId,
                    chapterFraction: meta.resolvedChapterProgress,
                    bookProgress: meta.resolvedProgress
                )
                if meta.resolvedProgress > 0 {
                    store.updateBookProgress(workId: workId, progress: meta.resolvedProgress)
                }
            }
        } catch {
            // Keep the local copy; portal is optional.
        }
    }

    /// Explicit UI chapter first; else furthest known position (local + portal).
    private func resolveStartChapterId(
        preferredChapterId: Int?,
        remoteChapterId: Int?,
        remoteChapterFraction: Double = 0,
        chapters: [ChapterMeta],
        workId: Int,
        store: OfflineStore,
        online: Bool
    ) -> Int {
        func usable(_ id: Int?) -> Int? {
            guard let id, chapters.contains(where: { $0.id == id }) else { return nil }
            if online || store.isChapterCached(workId: workId, chapterId: id) { return id }
            return nil
        }

        // TOC / deep link — always honor.
        if let id = usable(preferredChapterId) {
            return id
        }

        // Pick the furthest chapter among local + portal signals.
        var bestId: Int?
        var bestScore = -1.0
        func consider(_ id: Int?, fraction: Double) {
            guard let id = usable(id),
                  let idx = chapters.firstIndex(where: { $0.id == id }) else { return }
            let score = Double(idx) + min(max(fraction, 0), 0.999)
            if score > bestScore {
                bestScore = score
                bestId = id
            }
        }

        if let cp = ReadingSessionStore.shared.checkpoint(for: workId) {
            consider(cp.chapterId, fraction: cp.fraction)
        }
        if let p = store.progress(for: workId) {
            consider(p.chapterId, fraction: p.fraction)
        }
        consider(remoteChapterId, fraction: remoteChapterFraction)
        consider(store.cachedWork(workId: workId)?.lastReadChapterId, fraction: 0)

        if let bestId { return bestId }

        return pickStartChapterId(
            preferred: remoteChapterId,
            chapters: chapters,
            workId: workId,
            store: store,
            online: online
        )
    }

    /// Offline: rebuild TOC from the saved book page or downloaded chapter rows.
    private func offlineDetails(workId: Int, store: OfflineStore) throws -> WorkDetails {
        guard let details = store.workDetailsFromCache(workId: workId) else {
            throw APIError.message("Нет сети и книга ещё не скачана")
        }
        guard !(details.chapters ?? []).isEmpty else {
            throw APIError.message("Нет сети и нет сохранённых глав этой книги")
        }
        return details
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

        let alreadyFull = store.cachedWork(workId: workId)?.isFullyDownloaded == true
        let allowed = ProEntitlementStore.shared.canStartFullDownload(
            workId: workId,
            fullyDownloadedCount: store.fullyDownloadedCount,
            alreadyFullyDownloaded: alreadyFull
        )
        guard allowed else {
            statusMessage = "Лимит офлайна: нужен Читальня Pro"
            return
        }

        activeDownloads.insert(workId)
        store.downloadProgress[workId] = 0
        defer {
            activeDownloads.remove(workId)
        }

        let chapters = details.availableChapters
        guard !chapters.isEmpty else { return }
        store.cacheWorkDetails(details)

        // One path only: loadChapter verifies plaintext before save, so airplane mode
        // never treats encrypted/corrupt rows as "already downloaded".
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

        let expectedIds = chapters.map(\.id)
        store.reconcileFullDownloadStatus(workId: workId, expectedChapterIds: expectedIds)
        let ready = expectedIds.filter { store.isChapterCached(workId: workId, chapterId: $0) }.count
        let complete = ready == expectedIds.count
        store.downloadProgress[workId] = complete ? 1 : Double(ready) / Double(expectedIds.count)
        statusMessage = complete
            ? "«\(details.displayTitle)» скачана"
            : "Скачано \(ready) из \(expectedIds.count) глав — повторите, когда будет сеть"
    }
}
