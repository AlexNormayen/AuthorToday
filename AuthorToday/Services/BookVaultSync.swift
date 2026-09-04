import Foundation
import SwiftData
import Combine

/// Orchestrates push/pull between OfflineStore and the VPS book shelf.
@MainActor
final class BookVaultSync: ObservableObject {
    static let shared = BookVaultSync()

    @Published private(set) var isSyncing = false
    @Published private(set) var statusText = ""

    private var progressDebounce: Task<Void, Never>?
    private var uploadWork = Set<Int>()
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
        guard BookVaultSettings.shared.isEnabled else { return }
        guard resolvedUserId != nil else { return }
        guard !uploadWork.contains(workId) else { return }
        uploadWork.insert(workId)
        Task {
            defer { uploadWork.remove(workId) }
            await pushWork(workId: workId, store: store)
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

    func pushAllDownloaded(store: OfflineStore) async {
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
        statusText = "Выгрузка \(works.count) книг…"
        for (idx, work) in works.enumerated() {
            statusText = "Выгрузка \(idx + 1)/\(works.count): \(work.title)"
            await pushWork(workId: work.workId, store: store)
            await pushProgress(workId: work.workId, store: store)
        }
        if let ctx = store.modelContext {
            await pushBookmarks(modelContext: ctx)
        }
        BookVaultSettings.shared.lastSyncAt = .now
        BookVaultSettings.shared.lastStatus = "Выгружено \(works.count) книг"
        statusText = BookVaultSettings.shared.lastStatus
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

    func pullAndRestore(store: OfflineStore) async {
        guard BookVaultSettings.shared.isEnabled else {
            statusText = "Облачная полка выключена"
            return
        }
        guard let userId = resolvedUserId else {
            statusText = "Нужен вход в Author.Today"
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            statusText = "Чтение манифеста…"
            let manifest = try await BookVaultClient.shared.manifest(userId: userId)
            let sizeMb = Double(manifest.sizeBytes ?? 0) / 1_048_576
            statusText = "Восстановление \(manifest.works.count) книг (\(String(format: "%.1f", sizeMb)) МБ)…"

            for (idx, item) in manifest.works.enumerated() {
                statusText = "Книга \(idx + 1)/\(manifest.works.count)…"
                await restoreWork(userId: userId, workId: item.id, store: store)
            }

            let progressItems = try await BookVaultClient.shared.listProgress(userId: userId)
            for p in progressItems {
                applyRemoteProgress(p, store: store)
            }

            if let ctx = store.modelContext {
                await pullBookmarks(userId: userId, modelContext: ctx)
            }

            BookVaultSettings.shared.lastSyncAt = .now
            BookVaultSettings.shared.lastStatus = "Восстановлено \(manifest.works.count) книг"
            statusText = BookVaultSettings.shared.lastStatus
            store.reloadLibrary()
        } catch {
            statusText = error.localizedDescription
            BookVaultSettings.shared.lastStatus = error.localizedDescription
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

    private func restoreWork(userId: Int, workId: Int, store: OfflineStore) async {
        if let data = try? await BookVaultClient.shared.getMeta(userId: userId, workId: workId),
           let details = try? JSONDecoder().decode(WorkDetails.self, from: data) {
            store.cacheWorkDetails(details)
            if !store.isInLibrary(workId) {
                // Keep as local-only cache; user can add to site library separately.
            }
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
            if store.isChapterCached(workId: workId, chapterId: chapterId) { continue }
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
                sortIndex: index
            )
        }
        store.reconcileFullDownloadStatus(workId: workId)
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
