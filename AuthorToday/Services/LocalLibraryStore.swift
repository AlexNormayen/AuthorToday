import Foundation
import SwiftData
import Combine

@MainActor
final class LocalLibraryStore: ObservableObject {
    static let shared = LocalLibraryStore()

    @Published private(set) var books: [LocalBook] = []
    @Published var isImporting = false
    @Published var lastError: String?

    private var modelContext: ModelContext?

    func attach(context: ModelContext) {
        modelContext = context
        reload()
    }

    func reload() {
        guard let modelContext else {
            books = []
            return
        }
        var descriptor = FetchDescriptor<LocalBook>(
            sortBy: [SortDescriptor(\.lastReadAt, order: .reverse), SortDescriptor(\.addedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        books = (try? modelContext.fetch(descriptor)) ?? []
    }

    func book(id: UUID) -> LocalBook? {
        if let found = books.first(where: { $0.id == id }) {
            return found
        }
        guard let modelContext else { return nil }
        let target = id
        var descriptor = FetchDescriptor<LocalBook>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    func sortedChapters(for book: LocalBook) -> [LocalChapter] {
        book.chapters.sorted { $0.index < $1.index }
    }

    @discardableResult
    func importFile(from url: URL) throws -> LocalBook {
        guard ProFeatures.localLibraryRequiresPro == false
                || ProEntitlementStore.shared.isProUnlocked else {
            throw LocalBookImportError.proRequired
        }
        guard let modelContext else {
            throw LocalBookImportError.copyFailed
        }
        isImporting = true
        lastError = nil
        defer { isImporting = false }

        let imported = try LocalBookImporter.importFile(from: url)
        let book = LocalBook(
            title: imported.title,
            author: imported.author,
            format: imported.format,
            relativePath: imported.relativePath,
            coverData: imported.coverData
        )
        modelContext.insert(book)
        for (idx, ch) in imported.chapters.enumerated() {
            let chapter = LocalChapter(
                index: idx,
                title: ch.title,
                htmlText: ch.htmlText,
                plainText: ch.plainText
            )
            chapter.book = book
            modelContext.insert(chapter)
        }
        try modelContext.save()
        reload()
        return book
    }

    func delete(_ book: LocalBook) {
        guard let modelContext else { return }
        let folderName = book.relativePath.split(separator: "/").first.map(String.init)
        modelContext.delete(book)
        try? modelContext.save()
        if let folderName {
            let folder = LocalBookImporter.booksDirectory.appendingPathComponent(folderName, isDirectory: true)
            try? FileManager.default.removeItem(at: folder)
        }
        reload()
    }

    func saveProgress(
        bookId: UUID,
        chapterIndex: Int,
        offsetY: Double,
        fraction: Double,
        pageIndex: Int
    ) {
        guard let modelContext, let book = book(id: bookId) else { return }
        let chapterCount = max(book.chapters.count, 1)
        let bookProgress = min(max((Double(chapterIndex) + min(max(fraction, 0), 1)) / Double(chapterCount), 0), 1)
        book.lastChapterIndex = chapterIndex
        book.chapterOffsetY = offsetY
        book.chapterFraction = fraction
        book.chapterPageIndex = pageIndex
        book.progress = bookProgress
        book.lastReadAt = .now
        try? modelContext.save()
        // Keep published list order fresh without full refetch flicker when possible.
        if let idx = books.firstIndex(where: { $0.id == bookId }) {
            books[idx] = book
            books.sort {
                let l = $0.lastReadAt ?? $0.addedAt
                let r = $1.lastReadAt ?? $1.addedAt
                return l > r
            }
        } else {
            reload()
        }
    }
}
