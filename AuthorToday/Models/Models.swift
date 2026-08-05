import Foundation
import SwiftData

// MARK: - Auth

struct AuthTokenResponse: Codable, Sendable {
    let userId: Int?
    let token: String
    let issued: String?
    let expires: String?
}

struct LoginRequest: Codable, Sendable {
    let login: String
    let password: String
}

struct CurrentUser: Codable, Identifiable, Sendable {
    let id: Int
    let userName: String?
    let fio: String?
    let email: String?
    let avatarUrl: String?
    let status: String?
}

// MARK: - Library / Works

struct LibraryPage: Codable, Sendable {
    let works: [WorkMeta]?
    let data: [WorkMeta]?
    let searchResults: [WorkMeta]?
    let totalCount: Int?
    let hasMore: Bool?
    let realTotalCount: Int?
    let isLastPage: Bool?

    var items: [WorkMeta] {
        works ?? data ?? searchResults ?? []
    }
}

struct WorkMetaEnvelope: Codable, Sendable {
    let id: Int?
    let data: WorkMeta?
    let isSuccessful: Bool?
}

struct WorkMeta: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String?
    let authorFIO: String?
    let authorUserName: String?
    let coverUrl: String?
    let annotation: String?
    let lastChapterId: Int?
    let lastChapterTitle: String?
    let lastUpdateTime: String?
    let status: String?
    let genreName: String?
    let secondGenreName: String?
    let likeCount: Int?
    let viewsCount: Int?
    let viewCount: Int?
    let chapterCount: Int?
    let libraryState: String?
    let workInLibraryState: String?
    let inLibraryState: String?
    let progress: Double?
    let lastReadChapterId: Int?
    let lastChapterProgress: Double?

    var displayAuthor: String {
        authorFIO ?? authorUserName ?? "Автор неизвестен"
    }

    var displayTitle: String {
        title ?? "Без названия"
    }

    var resolvedLibraryState: String? {
        libraryState ?? workInLibraryState ?? inLibraryState
    }

    var resolvedProgress: Double {
        progress ?? lastChapterProgress ?? 0
    }

    /// Catalog often returns relative paths like `2026/07/01/....jpg`.
    var absoluteCoverURL: String? {
        Self.normalizeCover(coverUrl)
    }

    static func normalizeCover(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("//") {
            value = "https:" + value
        }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        if value.hasPrefix("/content/") {
            return "https://author.today" + value
        }
        if value.hasPrefix("content/") {
            return "https://author.today/" + value
        }
        return "https://author.today/content/" + value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

struct WorkDetails: Codable, Identifiable, Sendable {
    let id: Int
    let title: String?
    let authorFIO: String?
    let authorUserName: String?
    let coverUrl: String?
    let annotation: String?
    let chapters: [ChapterMeta]?
    let status: String?
    let genreName: String?
    let secondGenreName: String?
    let likeCount: Int?
    let viewsCount: Int?
    let chapterCount: Int?
    let downloadAllowed: Bool?
    let isFinished: Bool?

    var displayAuthor: String {
        authorFIO ?? authorUserName ?? "Автор неизвестен"
    }

    var displayTitle: String {
        title ?? "Без названия"
    }

    var availableChapters: [ChapterMeta] {
        (chapters ?? []).filter(\.isAvailableEffective)
    }
}

struct ChapterMeta: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let workId: Int?
    let title: String?
    let isAvailable: Bool?
    let publishTime: String?
    let lastUpdateTime: String?
    let textLength: Int?
    let isDraft: Bool?

    var isAvailableEffective: Bool {
        (isAvailable ?? true) && !(isDraft ?? false)
    }

    var displayTitle: String {
        title ?? "Глава"
    }
}

struct ChapterTextPayload: Codable, Sendable {
    let id: Int?
    let text: String?
    let title: String?
    let key: String?
    let data: Nested?

    struct Nested: Codable, Sendable {
        let text: String?
        let title: String?
        let id: Int?
        let key: String?
    }

    var resolvedText: String? {
        text ?? data?.text
    }

    var resolvedTitle: String? {
        title ?? data?.title
    }

    var resolvedKey: String? {
        key ?? data?.key
    }
}

struct ChapterBatchResult: Codable, Sendable {
    let chapters: [ChapterTextPayload]?
    let data: [ChapterTextPayload]?

    var items: [ChapterTextPayload] {
        chapters ?? data ?? []
    }
}

// MARK: - Notifications

struct NotificationCheck: Codable, Sendable {
    let hasUnread: Bool?
    let unreadCount: Int?
    let count: Int?

    var effectiveUnread: Int {
        unreadCount ?? count ?? ((hasUnread ?? false) ? 1 : 0)
    }
}

struct NotificationItem: Codable, Identifiable, Hashable, Sendable {
    let id: Int?
    let text: String?
    let title: String?
    let message: String?
    let creationTime: String?
    let isRead: Bool?
    let workId: Int?
    let url: String?
    let category: String?

    var stableId: String {
        if let id { return String(id) }
        return "\(creationTime ?? "")-\(text ?? title ?? message ?? "")"
    }

    var displayText: String {
        text ?? message ?? title ?? "Уведомление"
    }
}

struct NotificationList: Codable, Sendable {
    let notifications: [NotificationItem]?
    let data: [NotificationItem]?
    let items: [NotificationItem]?

    var all: [NotificationItem] {
        notifications ?? data ?? items ?? []
    }
}

// MARK: - Search

struct CatalogSearchResult: Codable, Sendable {
    let works: [WorkMeta]?
    let searchWorks: [WorkMeta]?
    let searchResults: [WorkMeta]?
    let data: [WorkMeta]?
    let realTotalCount: Int?
    let isLastPage: Bool?
    let errorMessage: String?

    var items: [WorkMeta] {
        searchResults ?? works ?? searchWorks ?? data ?? []
    }
}

// MARK: - Reading progress API

struct UpdateProgressRequest: Codable, Sendable {
    let workId: Int
    let chapterId: Int
    let location: String?
    let progress: Double?
}

// MARK: - SwiftData cache

@Model
final class CachedWork {
    @Attribute(.unique) var workId: Int
    var title: String
    var author: String
    var coverURL: String?
    var annotation: String?
    var libraryState: String?
    var lastReadChapterId: Int?
    var progress: Double
    var updatedAt: Date
    var isFullyDownloaded: Bool
    var chaptersJSON: Data?

    init(
        workId: Int,
        title: String,
        author: String,
        coverURL: String? = nil,
        annotation: String? = nil,
        libraryState: String? = nil,
        lastReadChapterId: Int? = nil,
        progress: Double = 0,
        updatedAt: Date = .now,
        isFullyDownloaded: Bool = false,
        chaptersJSON: Data? = nil
    ) {
        self.workId = workId
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.annotation = annotation
        self.libraryState = libraryState
        self.lastReadChapterId = lastReadChapterId
        self.progress = progress
        self.updatedAt = updatedAt
        self.isFullyDownloaded = isFullyDownloaded
        self.chaptersJSON = chaptersJSON
    }
}

@Model
final class CachedChapter {
    @Attribute(.unique) var compositeKey: String
    var workId: Int
    var chapterId: Int
    var title: String
    var htmlText: String
    var downloadedAt: Date
    var sortIndex: Int

    init(
        workId: Int,
        chapterId: Int,
        title: String,
        htmlText: String,
        sortIndex: Int = 0,
        downloadedAt: Date = .now
    ) {
        self.compositeKey = "\(workId)-\(chapterId)"
        self.workId = workId
        self.chapterId = chapterId
        self.title = title
        self.htmlText = htmlText
        self.sortIndex = sortIndex
        self.downloadedAt = downloadedAt
    }
}

@Model
final class ReadingProgress {
    @Attribute(.unique) var workId: Int
    var chapterId: Int
    var offsetY: Double
    var pageIndex: Int
    var updatedAt: Date

    init(workId: Int, chapterId: Int, offsetY: Double = 0, pageIndex: Int = 0, updatedAt: Date = .now) {
        self.workId = workId
        self.chapterId = chapterId
        self.offsetY = offsetY
        self.pageIndex = pageIndex
        self.updatedAt = updatedAt
    }
}
