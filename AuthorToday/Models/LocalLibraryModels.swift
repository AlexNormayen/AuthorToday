import Foundation
import SwiftData

enum LocalBookFormat: String, Codable, CaseIterable, Sendable {
    case txt
    case epub
}

@Model
final class LocalBook {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var formatRaw: String
    /// Relative path under Application Support/LocalBooks/
    var relativePath: String
    var coverData: Data?
    var addedAt: Date
    var lastReadAt: Date?
    var lastChapterIndex: Int
    /// Whole-book progress 0…1
    var progress: Double
    var chapterOffsetY: Double
    var chapterFraction: Double
    var chapterPageIndex: Int
    @Relationship(deleteRule: .cascade, inverse: \LocalChapter.book)
    var chapters: [LocalChapter]

    var format: LocalBookFormat {
        get { LocalBookFormat(rawValue: formatRaw) ?? .txt }
        set { formatRaw = newValue.rawValue }
    }

    var displayProgressPercent: Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }

    init(
        id: UUID = UUID(),
        title: String,
        author: String = "",
        format: LocalBookFormat,
        relativePath: String,
        coverData: Data? = nil,
        addedAt: Date = .now,
        lastReadAt: Date? = nil,
        lastChapterIndex: Int = 0,
        progress: Double = 0,
        chapterOffsetY: Double = 0,
        chapterFraction: Double = 0,
        chapterPageIndex: Int = 0,
        chapters: [LocalChapter] = []
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.formatRaw = format.rawValue
        self.relativePath = relativePath
        self.coverData = coverData
        self.addedAt = addedAt
        self.lastReadAt = lastReadAt
        self.lastChapterIndex = lastChapterIndex
        self.progress = progress
        self.chapterOffsetY = chapterOffsetY
        self.chapterFraction = chapterFraction
        self.chapterPageIndex = chapterPageIndex
        self.chapters = chapters
    }
}

@Model
final class LocalChapter {
    @Attribute(.unique) var id: UUID
    var index: Int
    var title: String
    /// HTML when available (EPUB); otherwise empty and use plainText.
    var htmlText: String
    var plainText: String
    var book: LocalBook?

    init(
        id: UUID = UUID(),
        index: Int,
        title: String,
        htmlText: String = "",
        plainText: String
    ) {
        self.id = id
        self.index = index
        self.title = title
        self.htmlText = htmlText
        self.plainText = plainText
    }

    var readerPlain: String {
        if !plainText.isEmpty { return plainText }
        if !htmlText.isEmpty { return HTMLText.readerPlain(from: htmlText) }
        return ""
    }
}
