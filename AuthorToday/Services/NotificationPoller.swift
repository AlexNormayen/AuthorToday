import Foundation
import UserNotifications
import Combine

/// Polls Author.Today notification API and posts local notifications.
/// Remote APNs/FCM require a paid Apple Developer account — not used here.
@MainActor
final class NotificationPoller: ObservableObject {
    static let shared = NotificationPoller()

    @Published var items: [NotificationItem] = []
    @Published var unreadCount = 0
    @Published var isAuthorized = false
    @Published var lastError: String?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = false

    private var timer: Timer?
    private var knownIds: Set<String> = []
    private let knownKey = "at.knownNotificationIds"
    private let pollInterval: TimeInterval = 120
    private let pageSize = 20
    private var cursor: String?
    private var seenStableIds = Set<String>()

    private init() {
        if let saved = UserDefaults.standard.array(forKey: knownKey) as? [String] {
            knownIds = Set(saved)
        }
    }

    func configure() async {
        let center = UNUserNotificationCenter.current()
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            lastError = error.localizedDescription
        }
    }

    func startPolling() {
        stopPolling()
        Task { await refresh(announceNew: false) }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(announceNew: true)
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// First page (or pull-to-refresh).
    func refresh(announceNew: Bool) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.feedPage(take: pageSize, lastItemCreationTime: nil)
            seenStableIds = Set(page.items.map(\.stableId))
            items = page.items
            cursor = page.cursor
            hasMore = page.more && page.cursor != nil

            if let check = try? await APIClient.shared.checkNotifications() {
                unreadCount = check.effectiveUnread
            } else {
                unreadCount = page.items.filter { !($0.isRead ?? true) }.count
            }

            if announceNew {
                for item in page.items where !(item.isRead ?? true) {
                    let sid = item.stableId
                    if !knownIds.contains(sid) {
                        knownIds.insert(sid)
                        await postLocal(item)
                    }
                }
                persistKnown()
            } else {
                knownIds.formUnion(page.items.map(\.stableId))
                persistKnown()
            }
            lastError = nil
            await applyAppBadge()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Next 20 rows when user scrolls to the bottom.
    func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading, let cursor else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await APIClient.shared.feedPage(take: pageSize, lastItemCreationTime: cursor)
            let fresh = page.items.filter { seenStableIds.insert($0.stableId).inserted }
            items.append(contentsOf: fresh)
            self.cursor = page.cursor
            hasMore = page.more && page.cursor != nil && !fresh.isEmpty
            knownIds.formUnion(fresh.map(\.stableId))
            persistKnown()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Call when the user opens the feed tab.
    func markFeedSeen() async {
        do {
            try await APIClient.shared.markAllNotificationsRead()
        } catch {
            lastError = error.localizedDescription
        }
        unreadCount = 0
        items = items.map { item in
            NotificationItem(
                id: item.id,
                text: item.text,
                title: item.title,
                message: item.message,
                content: item.content,
                body: item.body,
                html: item.html,
                creationTime: item.creationTime,
                isRead: true,
                workId: item.resolvedWorkId,
                workID: nil,
                url: item.url,
                link: item.link,
                category: item.category,
                notificationId: item.notificationId,
                feedType: item.feedType,
                postId: item.postId,
                authorName: item.authorName,
                authorUserName: item.authorUserName,
                coverURL: item.coverURL
            )
        }
        await applyAppBadge()
    }

    func markAllRead() async {
        await markFeedSeen()
    }

    private func applyAppBadge() async {
        if isAuthorized {
            try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
        }
    }

    private func postLocal(_ item: NotificationItem) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Читальня"
        content.body = item.displayText
        content.sound = .default
        if let workId = item.resolvedWorkId {
            content.userInfo = ["workId": workId]
        }
        let request = UNNotificationRequest(
            identifier: item.stableId,
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func persistKnown() {
        let trimmed = Array(knownIds.suffix(500))
        knownIds = Set(trimmed)
        UserDefaults.standard.set(trimmed, forKey: knownKey)
    }
}
