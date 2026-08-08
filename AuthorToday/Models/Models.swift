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
    /// Email / 2FA confirmation code from Author.Today.
    let code: String?
    /// Stable per-install device key required by login-by-password when 2FA is enabled.
    let secretKey: String?

    init(login: String, password: String, code: String? = nil, secretKey: String? = nil) {
        self.login = login
        self.password = password
        self.code = code
        self.secretKey = secretKey
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(login, forKey: .login)
        try c.encode(password, forKey: .password)
        try c.encodeIfPresent(code, forKey: .code)
        try c.encodeIfPresent(secretKey, forKey: .secretKey)
    }

    private enum CodingKeys: String, CodingKey {
        case login, password, code, secretKey
    }
}

struct CurrentUser: Codable, Identifiable, Sendable {
    let id: Int
    let userName: String?
    let username: String?
    let fio: String?
    let email: String?
    let avatarUrl: String?
    let status: String?

    var resolvedUserName: String? {
        let value = userName ?? username
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

// MARK: - Library / Works

struct LibraryPage: Codable, Sendable {
    /// Official `/v1/account/user-library` payload field.
    let worksInLibrary: [WorkMeta]?
    let works: [WorkMeta]?
    let data: [WorkMeta]?
    let searchResults: [WorkMeta]?
    let totalCount: Int?
    let readingCount: Int?
    let savedCount: Int?
    let finishedCount: Int?
    let purchasedCount: Int?
    let hasMore: Bool?
    let realTotalCount: Int?
    let isLastPage: Bool?

    var items: [WorkMeta] {
        worksInLibrary ?? works ?? data ?? searchResults ?? []
    }
}

struct UserLibraryPageResult: Sendable {
    let items: [WorkMeta]
    let totalCount: Int?
    let isLastPage: Bool
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
    let price: Double?
    let discount: Double?
    let isPurchased: Bool?
    let seriesId: Int?
    let seriesTitle: String?
    let seriesOrder: Int?

    /// Minimal row built from profile HTML when meta-info is empty/unavailable.
    static func stub(
        id: Int,
        title: String?,
        author: String?,
        coverUrl: String? = nil,
        libraryState: String = "Reading",
        seriesId: Int? = nil,
        seriesTitle: String? = nil,
        seriesOrder: Int? = nil
    ) -> WorkMeta {
        WorkMeta(
            id: id,
            title: title,
            authorFIO: author,
            authorUserName: nil,
            coverUrl: coverUrl,
            annotation: nil,
            lastChapterId: nil,
            lastChapterTitle: nil,
            lastUpdateTime: nil,
            status: nil,
            genreName: nil,
            secondGenreName: nil,
            likeCount: nil,
            viewsCount: nil,
            viewCount: nil,
            chapterCount: nil,
            libraryState: libraryState,
            workInLibraryState: nil,
            inLibraryState: libraryState,
            progress: nil,
            lastReadChapterId: nil,
            lastChapterProgress: nil,
            price: nil,
            discount: nil,
            isPurchased: nil,
            seriesId: seriesId,
            seriesTitle: seriesTitle,
            seriesOrder: seriesOrder
        )
    }

    func withLibraryState(_ state: String) -> WorkMeta {
        WorkMeta(
            id: id,
            title: title,
            authorFIO: authorFIO,
            authorUserName: authorUserName,
            coverUrl: coverUrl,
            annotation: annotation,
            lastChapterId: lastChapterId,
            lastChapterTitle: lastChapterTitle,
            lastUpdateTime: lastUpdateTime,
            status: status,
            genreName: genreName,
            secondGenreName: secondGenreName,
            likeCount: likeCount,
            viewsCount: viewsCount,
            viewCount: viewCount,
            chapterCount: chapterCount,
            libraryState: state,
            workInLibraryState: state,
            inLibraryState: state,
            progress: progress,
            lastReadChapterId: lastReadChapterId,
            lastChapterProgress: lastChapterProgress,
            price: price,
            discount: discount,
            isPurchased: isPurchased,
            seriesId: seriesId,
            seriesTitle: seriesTitle,
            seriesOrder: seriesOrder
        )
    }

    var displaySeriesTitle: String? {
        let raw = seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    var displayAuthor: String {
        authorFIO ?? authorUserName ?? "Автор неизвестен"
    }

    var displayTitle: String {
        title ?? "Без названия"
    }

    var resolvedLibraryState: String? {
        libraryState ?? workInLibraryState ?? inLibraryState
    }

    var isInLibrary: Bool {
        guard let state = resolvedLibraryState?.lowercased(), !state.isEmpty else { return false }
        return state != "none"
    }

    var resolvedProgress: Double {
        let raw = progress ?? lastChapterProgress ?? 0
        // API often sends 0…100 (percent); app stores/displays 0…1
        let normalized = raw > 1.0 ? raw / 100.0 : raw
        return min(max(normalized, 0), 1)
    }

    var displayPriceText: String? {
        if isPurchased == true { return "Куплено" }
        let statusLower = (status ?? "").lowercased()
        if statusLower == "free" { return "Бесплатно" }
        guard let price, price > 0 else { return nil }
        if let discount, discount > 0 {
            let final = price * (1.0 - discount / 100.0)
            return String(format: "%.0f ₽ (−%.0f%%)", final, discount)
        }
        return String(format: "%.0f ₽", price)
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
    let price: Double?
    let discount: Double?
    let isPurchased: Bool?
    let orderStatus: String?
    let orderStatusMessage: String?
    let freeChapterCount: Int?

    var displayAuthor: String {
        authorFIO ?? authorUserName ?? "Автор неизвестен"
    }

    var displayTitle: String {
        title ?? "Без названия"
    }

    var availableChapters: [ChapterMeta] {
        (chapters ?? []).filter(\.isAvailableEffective)
    }

    var needsPurchase: Bool {
        if isPurchased == true { return false }
        let statusLower = (status ?? "").lowercased()
        if statusLower == "free" { return false }
        if let price, price > 0 { return true }
        let locked = (chapters ?? []).contains { !$0.isAvailableEffective }
        return locked && statusLower.contains("sale")
    }

    var displayPriceText: String? {
        guard let price, price > 0 else { return nil }
        if let discount, discount > 0 {
            let final = price * (1.0 - discount / 100.0)
            return String(format: "%.0f ₽ (−%.0f%%)", final, discount)
        }
        return String(format: "%.0f ₽", price)
    }

    var purchaseURL: URL {
        // Dedicated work page checkout / buy flow on site (not a blank SPA shell).
        URL(string: "https://author.today/work/\(id)?buy=1")!
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

// MARK: - Comments

struct WorkComment: Identifiable, Hashable, Sendable {
    let id: Int
    let parentId: Int?
    let threadId: Int?
    let level: Int
    let authorName: String
    let authorUserName: String?
    let text: String
    let createdAt: String?
    let isPinned: Bool
    let isAuthor: Bool
    let rating: Int?
}

struct CommentLoadPage: Sendable {
    let comments: [WorkComment]
    let hasMore: Bool
    let nextPage: Int?
}

// MARK: - Author profile

struct AuthorProfile: Sendable {
    let userName: String
    let displayName: String
    let userId: Int?
    let avatarURL: String?
    let about: String?
    let works: [WorkMeta]
    let series: [AuthorSeriesGroup]
}

// MARK: - Private messages (author.today/pm)

struct PMChat: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let preview: String?
    let avatarURL: String?
    let peerUserId: Int?
    let peerUserName: String?
    let unreadCount: Int
    let updatedAt: String?
}

struct PMMessage: Identifiable, Hashable, Sendable {
    let id: Int
    let text: String
    let isMine: Bool
    let senderName: String?
    let createdAt: String?
}

struct AuthorSeriesGroup: Identifiable, Hashable, Sendable {
    var id: String { title }
    let title: String
    let seriesId: Int?
    let works: [WorkMeta]
}

struct AuthorSearchHit: Identifiable, Hashable, Sendable {
    var id: String { userName }
    let userName: String
    let displayName: String
}

struct CatalogSearchBundle: Sendable {
    var authors: [AuthorSearchHit]
    var works: [WorkMeta]
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
    let content: String?
    let body: String?
    let html: String?
    let creationTime: String?
    let isRead: Bool?
    let workId: Int?
    let workID: Int?
    let url: String?
    let link: String?
    let category: String?
    /// Stable server id (UUID string from feed).
    let notificationId: String?
    /// API type: NewPost, WorkUpdate, NewChapter, …
    let feedType: String?
    let postId: Int?
    let authorName: String?
    let authorUserName: String?
    let coverURL: String?

    var resolvedWorkId: Int? { workId ?? workID }

    var isBlogPost: Bool {
        if postId != nil { return true }
        let t = (feedType ?? category ?? "").lowercased()
        return t.contains("post") || t == "newpost"
    }

    var stableId: String {
        if let notificationId, !notificationId.isEmpty { return notificationId }
        if let postId { return "post-\(postId)" }
        if let id { return String(id) }
        return "\(creationTime ?? "")-\(displayText)"
    }

    var displayTitle: String? {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    var displayText: String {
        let raw = text ?? message ?? content ?? body ?? html ?? title ?? "Уведомление"
        return HTMLText.plain(from: raw)
    }

    /// Filter SPA chrome / catalog filters mistaken for feed rows.
    var isJunk: Bool {
        let t = displayText.lowercased()
        if t.isEmpty || t.count < 6 { return true }
        if t.contains("тыс. зн") || t.contains("тыс зн") { return true }
        if t.contains("размер") && t.contains("зн") { return true }
        if t.range(of: #"^\+?\s*\d[\d\s]*зн"#, options: .regularExpression) != nil { return true }
        if t.contains("войти") && t.contains("парол") { return true }
        if t.contains("framework7") { return true }
        if t == "лента" || t == "уведомление" { return true }
        return false
    }
}

/// Real `/v1/notification/get` payload (blog posts + work updates).
struct FeedPage: Codable, Sendable {
    let items: [FeedEntry]?
    let more: Bool?
    let lastItemCreationTime: String?
    let showUnread: Bool?
}

struct FeedEntry: Codable, Sendable {
    let notificationId: String?
    let itemId: Int?
    let id: Int?
    let title: String?
    let previewText: String?
    let text: String?
    let creationTime: String?
    let publishTime: String?
    let isRead: Bool?
    let type: String?
    let actionType: String?
    let chapterTitle: String?
    let chapterId: Int?
    let authorFIO: String?
    let authorUserName: String?
    let coverUrl: String?
    let imageUrl: String?
    let images: [String]?
    let category: FeedCategory?

    struct FeedCategory: Codable, Sendable {
        let title: String?
        let code: String?
    }

    func asNotificationItem() -> NotificationItem {
        let workRelated = ["WorkUpdate", "NewChapter", "DiscountStart", "DiscountEnd", "PriceChange"]
        let typeName = type ?? actionType ?? ""
        let isPost = ["NewPost", "Post", "BlogPost", "DiscussionPost"].contains(typeName)
            || (category?.code?.lowercased().contains("post") == true)

        let resolvedPost: Int? = isPost ? (itemId ?? id) : nil
        let resolvedWork: Int? = {
            if resolvedPost != nil { return nil }
            if workRelated.contains(typeName) || workRelated.contains(actionType ?? "") {
                return id
            }
            if chapterId != nil || chapterTitle != nil { return id }
            return nil
        }()

        var lines: [String] = []
        if let title, !title.isEmpty { lines.append(title) }
        if let chapterTitle, !chapterTitle.isEmpty {
            lines.append(chapterTitle)
        }
        if let previewText, !previewText.isEmpty {
            lines.append(previewText)
        } else if let text, !text.isEmpty {
            lines.append(text)
        }
        if let authorFIO, !authorFIO.isEmpty, isPost {
            lines.insert(authorFIO, at: min(1, lines.count))
        }
        let combined = lines.joined(separator: "\n")
        let cover = WorkMeta.normalizeCover(coverUrl ?? imageUrl ?? images?.first)
        let deepLink: String? = {
            if let resolvedPost { return "https://author.today/post/\(resolvedPost)" }
            if let resolvedWork { return "https://author.today/work/\(resolvedWork)" }
            return nil
        }()

        return NotificationItem(
            id: itemId ?? id,
            text: combined,
            title: title,
            message: previewText ?? text,
            content: previewText,
            body: nil,
            html: text,
            creationTime: creationTime ?? publishTime,
            isRead: isRead,
            workId: resolvedWork,
            workID: nil,
            url: deepLink,
            link: nil,
            category: category?.title ?? typeName,
            notificationId: notificationId,
            feedType: typeName,
            postId: resolvedPost,
            authorName: authorFIO,
            authorUserName: authorUserName,
            coverURL: cover
        )
    }
}

struct PostDetails: Sendable {
    let id: Int
    let title: String
    let authorName: String?
    let authorUserName: String?
    let html: String
    let plainText: String
    let attributedBody: AttributedString
    let imageURLs: [URL]
    let videoEmbedURLs: [URL]
    let linkURLs: [URL]
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
    var authorUserName: String?
    var coverURL: String?
    var annotation: String?
    var libraryState: String?
    var lastReadChapterId: Int?
    /// Last time the user opened/read this book (app or inferred from site progress).
    var lastReadAt: Date?
    var progress: Double
    var updatedAt: Date
    var isFullyDownloaded: Bool
    var chaptersJSON: Data?
    var seriesId: Int?
    var seriesTitle: String?
    var seriesOrder: Int?
    /// Site like count — used for author popularity sort.
    var likeCount: Int?
    var viewsCount: Int?

    init(
        workId: Int,
        title: String,
        author: String,
        authorUserName: String? = nil,
        coverURL: String? = nil,
        annotation: String? = nil,
        libraryState: String? = nil,
        lastReadChapterId: Int? = nil,
        lastReadAt: Date? = nil,
        progress: Double = 0,
        updatedAt: Date = .now,
        isFullyDownloaded: Bool = false,
        chaptersJSON: Data? = nil,
        seriesId: Int? = nil,
        seriesTitle: String? = nil,
        seriesOrder: Int? = nil,
        likeCount: Int? = nil,
        viewsCount: Int? = nil
    ) {
        self.workId = workId
        self.title = title
        self.author = author
        self.authorUserName = authorUserName
        self.coverURL = coverURL
        self.annotation = annotation
        self.libraryState = libraryState
        self.lastReadChapterId = lastReadChapterId
        self.lastReadAt = lastReadAt
        self.progress = progress
        self.updatedAt = updatedAt
        self.isFullyDownloaded = isFullyDownloaded
        self.chaptersJSON = chaptersJSON
        self.seriesId = seriesId
        self.seriesTitle = seriesTitle
        self.seriesOrder = seriesOrder
        self.likeCount = likeCount
        self.viewsCount = viewsCount
    }

    /// Safe 0…100 for UI (handles legacy rows that stored API percent as-is).
    var displayProgressPercent: Int {
        let raw = progress
        let fraction = raw > 1.0 ? raw / 100.0 : raw
        return Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    var displaySeriesFolder: String {
        let raw = seriesTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Без серии" : raw
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
    /// 0...1 position within the chapter (preferred over raw offsetY after reflow).
    var fraction: Double
    var pageIndex: Int
    var updatedAt: Date

    init(
        workId: Int,
        chapterId: Int,
        offsetY: Double = 0,
        fraction: Double = 0,
        pageIndex: Int = 0,
        updatedAt: Date = .now
    ) {
        self.workId = workId
        self.chapterId = chapterId
        self.offsetY = offsetY
        self.fraction = min(max(fraction, 0), 1)
        self.pageIndex = pageIndex
        self.updatedAt = updatedAt
    }
}
