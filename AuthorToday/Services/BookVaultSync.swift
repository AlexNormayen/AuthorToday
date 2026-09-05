import Foundation
import SwiftData
import Combine

/// Orchestrates push/pull between OfflineStore / LocalLibrary and the VPS book shelf.
@MainActor
final class BookVaultSync: ObservableObject {
    static let shared = BookVaultSync()

    @Published private(set) var isSyncing = false
    @Published private(set) var statusText = ""

    private var progressDebounce: Task<Void, Never>?
    private var uploadWork = Set<Int>()
    private var uploadLocal = Set<UUID>()
    /// Suppress vault re-upload while restoring from VPS.
    private var isRestoring = false
    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {}

    var resolvedUserId: Int? {
        if let id = AuthService.shared.user?.id, id > 0 { return id }
        let saved = UserDefaults.standard.object(forKey: "at.auth.userId") as? Int
        if let saved, saved > 0 { return saved }
        return nil
    }

    // MARK: - Push hooks

    func enqueueChapterUpload(workId: Int, chapterId: Int, title: String, html: String) {
        guard !isRestoring else { return }
        guard BookVaultSettings.shared.isEnabled else { return }
        guard let userId = resolvedUserId else { return }
        Task {
            do {
                try await BookVaultClient.shared.putChapter(
                    userId: userId,
                    workId: workId,
                    chapterId: chapterId,
                    title: title,
                    html: html
                )
            } catch {
                BookVaultSettings.shared.lastStatus = error.localizedDescription
            }
        }
    }

    func enqueueWorkUpload(workId: Int, store: OfflineStore) {
        guard !isRestoring else { return }
        guard BookVaultSettings.shared.isEnabled else { return }
        guard resolvedUserId != nil else { return }
        guard !uploadWork.contains(workId) else { return }
        uploadWork.insert(workId)
        Task {
            defer { uploadWork.remove(workId) }
            await pushWork(workId: workId, store: store)
        }
    }

    func enqueueLocalBookUpload(_ book: LocalBook) {
        guard !isRestoring else { return }
        guard BookVaultSettings.shared.isEnabled else { return }
        guard resolvedUserId != nil else { return }
        guard !uploadLocal.contains(book.id) else { return }
        uploadLocal.insert(book.id)
        Task {
            defer { uploadLocal.remove(book.id) }
            await pushLocalBook(book)
        }
    }

    func enqueueProgressUpload(workId: Int, store: OfflineStore) {
        guard BookVaultSettings.shared.isEnabled else { return }
        progressDebounce?.cancel()
        progressDebounce = Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            await pushProgress(workId: workId, store: store)
        }
    }

    func enqueueBookmarksUpload(modelContext: ModelContext) {
        guard BookVaultSettings.shared.isEnabled else { return }
        Task { await pushBookmarks(modelContext: modelContext) }
    }

    // MARK: - Full sync

    /// Push AT downloads + «Мои книги». Used by button and auto-backfill.
    func pushAllDownloaded(store: OfflineStore, localStore: LocalLibraryStore? = nil) async {
        guard BookVaultSettings.shared.isEnabled else {
            statusText = "Облачная полка выключена"
            return
        }
        guard resolvedUserId != nil else {
            statusText = "Нужен вход в Author.Today"
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        let works = store.downloadedWorks
        let locals = localStore?.books ?? LocalLibraryStore.shared.books
        let total = works.count + locals.count
        statusText = "Выгрузка \(total) книг…"

        var okAT = 0
        for (idx, work) in works.enumerated() {
            statusText = "Author.Today \(idx + 1)/\(works.count): \(work.title)"
            await pushWork(workId: work.workId, store: store)
            await pushProgress(workId: work.workId, store: store)
            okAT += 1
        }

        var okLocal = 0
        for (idx, book) in locals.enumerated() {
            statusText = "Мои книги \(idx + 1)/\(locals.count): \(book.title)"
            await pushLocalBook(book)
            okLocal += 1
        }

        if let ctx = store.modelContext {
            await pushBookmarks(modelContext: ctx)
        }
        BookVaultSettings.shared.lastSyncAt = .now
        BookVaultSettings.shared.lastStatus = "Выгружено: AT \(okAT), локальных \(okLocal)"
        statusText = BookVaultSettings.shared.lastStatus
    }

    /// If local shelf has more than remote, push automatically (once per session debounce via status).
    func autoBackfillIfNeeded(store: OfflineStore, localStore: LocalLibraryStore) async {
        guard BookVaultSettings.shared.isEnabled else { return }
        guard let userId = resolvedUserId else { return }
        guard !isSyncing else { return }
        do {
            let manifest = try await BookVaultClient.shared.manifest(userId: userId)
            let remoteAT = manifest.works.count
            let remoteLocal = manifest.localBooks?.count ?? 0
            let localAT = store.downloadedWorks.count
            let localMine = localStore.books.count
            if localAT > remoteAT || localMine > remoteLocal {
                await pushAllDownloaded(store: store, localStore: localStore)
            }
        } catch {
            // Quiet — user can push manually.
        }
    }

    func pullProgressAndBookmarks(store: OfflineStore) async {
        guard BookVaultSettings.shared.isEnabled else { return }
        guard let userId = resolvedUserId else { return }
        do {
            let progressItems = try await BookVaultClient.shared.listProgress(userId: userId)
            for p in progressItems {
                applyRemoteProgress(p, store: store)
            }
            if let ctx = store.modelContext {
                await pullBookmarks(userId: userId, modelContext: ctx)
            }
            BookVaultSettings.shared.lastSyncAt = .now
        } catch {
            BookVaultSettings.shared.lastStatus = error.localizedDescription
        }
    }

    func pullAndRestore(store: OfflineStore, localStore: LocalLibraryStore? = nil) async {
        guard BookVaultSettings.shared.isEnabled else {
            statusText = "Облачная полка выключена"
            return
        }
        guard let userId = resolvedUserId else {
            statusText = "Нужен вход в Author.Today"
            return
        }
        isSyncing = true
        isRestoring = true
        defer {
            isSyncing = false
            isRestoring = false
        }
        do {
            statusText = "Чтение манифеста…"
            let manifest = try await BookVaultClient.shared.manifest(userId: userId)
            let localItems = manifest.localBooks ?? []
            let total = manifest.works.count + localItems.count
            let sizeMb = Double(manifest.sizeBytes ?? 0) / 1_048_576
            statusText = "Восстановление \(total) книг (\(String(format: "%.1f", sizeMb)) МБ)…"

            var restoredAT = 0
            for (idx, item) in manifest.works.enumerated() {
                statusText = "Author.Today \(idx + 1)/\(manifest.works.count)…"
                let ok = await restoreWork(userId: userId, workId: item.id, store: store)
                if ok { restoredAT += 1 }
            }

            var restoredLocal = 0
            let locals = localStore ?? LocalLibraryStore.shared
            for (idx, item) in localItems.enumerated() {
                statusText = "Мои книги \(idx + 1)/\(localItems.count)…"
                let ok = await restoreLocalBook(userId: userId, bookId: item.id, localStore: locals)
                if ok { restoredLocal += 1 }
            }

            let progressItems = try await BookVaultClient.shared.listProgress(userId: userId)
            for p in progressItems {
                applyRemoteProgress(p, store: store)
            }

            if let ctx = store.modelContext {
                await pullBookmarks(userId: userId, modelContext: ctx)
            }

            BookVaultSettings.shared.lastSyncAt = .now
            BookVaultSettings.shared.lastStatus =
                "Восстановлено: AT \(restoredAT)/\(manifest.works.count), локальных \(restoredLocal)/\(localItems.count)"
            statusText = BookVaultSettings.shared.lastStatus
            store.reloadLibrary()
            locals.reload()
        } catch {
            statusText = error.localizedDescription
            BookVaultSettings.shared.lastStatus = error.localizedDescription
        }
    }

    func deleteLocalBookEverywhere(_ book: LocalBook, localStore: LocalLibraryStore) async {
        let id = book.id
        localStore.delete(book)
        guard BookVaultSettings.shared.isEnabled, let userId = resolvedUserId else { return }
        do {
            try await BookVaultClient.shared.deleteLocalBook(userId: userId, bookId: id.uuidString.lowercased())
            BookVaultSettings.shared.lastStatus = "Удалено с устройства и VPS"
        } catch {
            BookVaultSettings.shared.lastStatus = "С устройства удалено; VPS: \(error.localizedDescription)"
        }
    }

    /// Remove offline AT download from device (+ VPS). Does not change author.today library.
    func deleteOfflineATWork(workId: Int, store: OfflineStore) async {
        store.removeDownloadedWork(workId: workId)
        guard BookVaultSettings.shared.isEnabled, let userId = resolvedUserId else { return }
        do {
            try await BookVaultClient.shared.deleteWork(userId: userId, workId: workId)
            BookVaultSettings.shared.lastStatus = "Скачанная копия удалена (устройство + VPS)"
        } catch {
            BookVaultSettings.shared.lastStatus = "С устройства удалено; VPS: \(error.localizedDescription)"
        }
    }

    func ping() async -> String {
        guard let userId = resolvedUserId else { return "Нужен вход" }
        do {
            let info = try await BookVaultClient.shared.health(userId: userId)
            let free: Int
            if let n = info["freeMb"] as? Int {
                free = n
            } else if let n = info["freeMb"] as? Int64 {
                free = Int(n)
            } else if let n = info["freeMb"] as? Double {
                free = Int(n)
            } else {
                free = 0
            }
            let msg = "OK · свободно \(free) МБ"
            BookVaultSettings.shared.lastStatus = msg
            return msg
        } catch {
            BookVaultSettings.shared.lastStatus = error.localizedDescription
            return error.localizedDescription
        }
    }

    // MARK: - Fallback helpers

    func fetchChapterHTML(workId: Int, chapterId: Int) async -> String? {
        guard BookVaultSettings.shared.isEnabled else { return nil }
        guard let userId = resolvedUserId else { return nil }
        return try? await BookVaultClient.shared.getChapter(
            userId: userId,
            workId: workId,
            chapterId: chapterId
        )
    }

    func fetchWorkDetails(workId: Int) async -> WorkDetails? {
        guard BookVaultSettings.shared.isEnabled else { return nil }
        guard let userId = resolvedUserId else { return nil }
        guard let data = try? await BookVaultClient.shared.getMeta(userId: userId, workId: workId) else {
            return nil
        }
        return try? JSONDecoder().decode(WorkDetails.self, from: data)
    }

    // MARK: - Internals

    private func pushWork(workId: Int, store: OfflineStore) async {
        guard let userId = resolvedUserId else { return }
        if let details = store.workDetailsFromCache(workId: workId),
           let data = try? JSONEncoder().encode(details) {
            try? await BookVaultClient.shared.putMeta(userId: userId, workId: workId, json: data)
        } else if let cached = store.cachedWork(workId: workId),
                  let data = cached.detailsJSON {
            try? await BookVaultClient.shared.putMeta(userId: userId, workId: workId, json: data)
        }

        let chapters = store.cachedChapters(workId: workId)
            .filter { ChapterDecryptor.looksLikePlaintext($0.htmlText) }
        for chapter in chapters {
            do {
                try await BookVaultClient.shared.putChapter(
                    userId: userId,
                    workId: workId,
                    chapterId: chapter.chapterId,
                    title: chapter.title,
                    html: chapter.htmlText
                )
            } catch {
                BookVaultSettings.shared.lastStatus = error.localizedDescription
            }
        }
    }

    private func pushLocalBook(_ book: LocalBook) async {
        guard let userId = resolvedUserId else { return }
        let meta = BookVaultLocalMeta(
            id: book.id.uuidString.lowercased(),
            title: book.title,
            author: book.author,
            format: book.format.rawValue,
            addedAt: isoFormatter.string(from: book.addedAt),
            lastChapterIndex: book.lastChapterIndex,
            progress: book.progress,
            chapterOffsetY: book.chapterOffsetY,
            chapterFraction: book.chapterFraction,
            chapterPageIndex: book.chapterPageIndex
        )
        do {
            try await BookVaultClient.shared.putLocalMeta(userId: userId, meta: meta)
        } catch {
            BookVaultSettings.shared.lastStatus = error.localizedDescription
            return
        }
        let chapters = book.chapters.sorted { $0.index < $1.index }
        for ch in chapters {
            let body = ch.htmlText.isEmpty ? ch.plainText : ch.htmlText
            guard !body.isEmpty else { continue }
            do {
                try await BookVaultClient.shared.putLocalChapter(
                    userId: userId,
                    bookId: meta.id,
                    chapterIndex: ch.index,
                    title: ch.title,
                    text: body
                )
            } catch {
                BookVaultSettings.shared.lastStatus = error.localizedDescription
            }
        }
    }

    private func pushProgress(workId: Int, store: OfflineStore) async {
        guard let userId = resolvedUserId else { return }
        guard let prog = store.progress(for: workId) else { return }
        let dto = BookVaultProgressDTO(
            workId: workId,
            chapterId: prog.chapterId,
            fraction: prog.fraction,
            offsetY: prog.offsetY,
            pageIndex: prog.pageIndex,
            updatedAt: isoFormatter.string(from: prog.updatedAt)
        )
        do {
            try await BookVaultClient.shared.putProgress(userId: userId, progress: dto)
        } catch {
            BookVaultSettings.shared.lastStatus = error.localizedDescription
        }
    }

    private func pushBookmarks(modelContext: ModelContext) async {
        guard let userId = resolvedUserId else { return }
        let rows = (try? modelContext.fetch(FetchDescriptor<ReadingBookmark>())) ?? []
        let items = rows.map { bm in
            BookVaultBookmarkDTO(
                id: bm.id.uuidString,
                workId: bm.workId,
                chapterId: bm.chapterId,
                workTitle: bm.workTitle,
                chapterTitle: bm.chapterTitle,
                charOffset: bm.charOffset,
                fraction: bm.fraction,
                createdAt: isoFormatter.string(from: bm.createdAt)
            )
        }
        let payload = BookVaultBookmarksPayload(
            items: items,
            updatedAt: isoFormatter.string(from: .now)
        )
        do {
            try await BookVaultClient.shared.putBookmarks(userId: userId, payload: payload)
        } catch {
            BookVaultSettings.shared.lastStatus = error.localizedDescription
        }
    }

    @discardableResult
    private func restoreWork(userId: Int, workId: Int, store: OfflineStore) async -> Bool {
        var restoredAny = false
        if let data = try? await BookVaultClient.shared.getMeta(userId: userId, workId: workId),
           let details = try? JSONDecoder().decode(WorkDetails.self, from: data) {
            store.cacheWorkDetails(details, shelfState: "Reading")
            restoredAny = true
        }

        let remoteChapters = (try? await BookVaultClient.shared.listChapters(userId: userId, workId: workId)) ?? []
        for (index, row) in remoteChapters.enumerated() {
            let chapterId: Int?
            if let n = row["id"] as? Int {
                chapterId = n
            } else if let n = row["id"] as? NSNumber {
                chapterId = n.intValue
            } else {
                chapterId = nil
            }
            guard let chapterId else { continue }
            if store.isChapterCached(workId: workId, chapterId: chapterId) {
                restoredAny = true
                continue
            }
            guard let html = try? await BookVaultClient.shared.getChapter(
                userId: userId,
                workId: workId,
                chapterId: chapterId
            ), ChapterDecryptor.looksLikePlaintext(html) else { continue }
            let title = (row["title"] as? String) ?? "Глава"
            store.saveChapter(
                workId: workId,
                chapterId: chapterId,
                title: title,
                html: html,
                sortIndex: index,
                uploadToVault: false
            )
            restoredAny = true
        }

        if restoredAny, store.cachedWork(workId: workId) == nil {
            // Meta missing — still surface orphan chapters on the shelf.
            store.ensureVaultPlaceholderWork(workId: workId, title: "Книга \(workId)")
        }
        if restoredAny {
            store.promoteVaultWorkToShelf(workId: workId)
            store.reconcileFullDownloadStatus(workId: workId)
        }
        return restoredAny
    }

    @discardableResult
    private func restoreLocalBook(userId: Int, bookId: String, localStore: LocalLibraryStore) async -> Bool {
        guard let uuid = UUID(uuidString: bookId) else { return false }
        if localStore.book(id: uuid) != nil { return true }
        guard let meta = try? await BookVaultClient.shared.getLocalMeta(userId: userId, bookId: bookId) else {
            return false
        }
        let remoteChapters = (try? await BookVaultClient.shared.listLocalChapters(userId: userId, bookId: bookId)) ?? []
        var chapters: [(index: Int, title: String, body: String)] = []
        for row in remoteChapters {
            let index: Int?
            if let n = row["index"] as? Int {
                index = n
            } else if let n = row["index"] as? NSNumber {
                index = n.intValue
            } else {
                index = nil
            }
            guard let index else { continue }
            guard let body = try? await BookVaultClient.shared.getLocalChapter(
                userId: userId,
                bookId: bookId,
                chapterIndex: index
            ), !body.isEmpty else { continue }
            let title = (row["title"] as? String) ?? "Глава \(index + 1)"
            chapters.append((index, title, body))
        }
        guard !chapters.isEmpty else { return false }
        do {
            try localStore.restoreFromVault(
                id: uuid,
                title: meta.title,
                author: meta.author,
                format: LocalBookFormat(rawValue: meta.format) ?? .txt,
                chapters: chapters,
                lastChapterIndex: meta.lastChapterIndex ?? 0,
                progress: meta.progress ?? 0,
                chapterOffsetY: meta.chapterOffsetY ?? 0,
                chapterFraction: meta.chapterFraction ?? 0,
                chapterPageIndex: meta.chapterPageIndex ?? 0
            )
            return true
        } catch {
            BookVaultSettings.shared.lastStatus = error.localizedDescription
            return false
        }
    }

    private func applyRemoteProgress(_ remote: BookVaultProgressDTO, store: OfflineStore) {
        let remoteDate = isoFormatter.date(from: remote.updatedAt) ?? .distantPast
        if let local = store.progress(for: remote.workId), local.updatedAt > remoteDate {
            return
        }
        store.saveProgress(
            workId: remote.workId,
            chapterId: remote.chapterId,
            offsetY: remote.offsetY ?? 0,
            pageIndex: remote.pageIndex ?? 0,
            fraction: remote.fraction,
            bookProgress: nil,
            forceChapter: true
        )
    }

    private func pullBookmarks(userId: Int, modelContext: ModelContext) async {
        guard let payload = try? await BookVaultClient.shared.getBookmarks(userId: userId) else { return }
        let existing = (try? modelContext.fetch(FetchDescriptor<ReadingBookmark>())) ?? []
        var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id.uuidString.lowercased(), $0) })
        for item in payload.items {
            let key = item.id.lowercased()
            if byId[key] != nil { continue }
            guard let uuid = UUID(uuidString: item.id) else { continue }
            let created = isoFormatter.date(from: item.createdAt) ?? .now
            let bm = ReadingBookmark(
                id: uuid,
                workId: item.workId,
                chapterId: item.chapterId,
                workTitle: item.workTitle,
                chapterTitle: item.chapterTitle,
                charOffset: item.charOffset,
                fraction: item.fraction,
                createdAt: created
            )
            modelContext.insert(bm)
            byId[key] = bm
        }
        try? modelContext.save()
    }
}
