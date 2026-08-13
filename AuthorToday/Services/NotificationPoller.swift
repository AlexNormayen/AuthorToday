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
    /// Which feed kinds are visible (AT-style “what to show”).
    @Published var enabledKinds: Set<FeedKind>

    private var timer: Timer?
    private var knownIds: Set<String> = []
    private var locallyReadIds: Set<String> = []
    private let knownKey = "at.knownNotificationIds"
    private let readKey = "at.readNotificationIds"
    private let kindsKey = "at.feedEnabledKinds"
    private let pollInterval: TimeInterval = 120
    private let pageSize = 20
    private var cursor: String?
    private var seenStableIds = Set<String>()

    private init() {
        if let saved = UserDefaults.standard.array(forKey: knownKey) as? [String] {
            knownIds = Set(saved)
        }
        if let saved = UserDefaults.standard.array(forKey: readKey) as? [String] {
            locallyReadIds = Set(saved)
        }
        if let raw = UserDefaults.standard.array(forKey: kindsKey) as? [String], !raw.isEmpty {
            let parsed = Set(raw.compactMap(FeedKind.init(rawValue:)))
            enabledKinds = parsed.isEmpty ? Set(FeedKind.allCases) : parsed
        } else {
            enabledKinds = Set(FeedKind.allCases)
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
            Task { @MainActor [weak self] in
                await self?.refresh(announceNew: true)
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func isUnread(_ item: NotificationItem) -> Bool {
        if locallyReadIds.contains(item.stableId) { return false }
        return item.appearsUnread
    }

    func setKind(_ kind: FeedKind, enabled: Bool) {
        var next = enabledKinds
        if enabled {
            next.insert(kind)
        } else if next.count > 1 {
            next.remove(kind)
        }
        enabledKinds = next
        persistKinds()
    }

    /// First page (or pull-to-refresh).
    func refresh(announceNew: Bool) async {
        if !DownloadManager.shared.online {
            lastError = "Нет сети. Лента недоступна офлайн."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.feedPage(take: pageSize, lastItemCreationTime: nil)
            seenStableIds = Set(page.items.map(\.stableId))
            items = page.items.map { overlayLocalRead($0) }
            cursor = page.cursor
            hasMore = page.more && page.cursor != nil

            let localUnread = items.filter { isUnread($0) }.count
            if let check = try? await APIClient.shared.checkNotifications() {
                // API may know about pages we haven't loaded yet.
                unreadCount = max(localUnread, check.effectiveUnread)
            } else {
                unreadCount = localUnread
            }

            if announceNew {
                for item in items where isUnread(item) {
                    let sid = item.stableId
                    if !knownIds.contains(sid) {
                        knownIds.insert(sid)
                        await postLocal(item)
                    }
                }
                persistKnown()
            } else {
                knownIds.formUnion(items.map(\.stableId))
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
            let fresh = page.items
                .filter { seenStableIds.insert($0.stableId).inserted }
                .map { overlayLocalRead($0) }
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

    /// Mark a single row read when the user opens it (does not clear the whole feed).
    func markItemRead(_ item: NotificationItem) {
        guard isUnread(item) else { return }
        locallyReadIds.insert(item.stableId)
        persistRead()
        if let idx = items.firstIndex(where: { $0.stableId == item.stableId }) {
            items[idx] = items[idx].marking(isRead: true)
        }
        unreadCount = max(0, unreadCount - 1)
        Task { await applyAppBadge() }
    }

    /// Explicit “mark all read” (AT-style) — not called merely by opening the tab.
    func markAllRead() async {
        do {
            try await APIClient.shared.markAllNotificationsRead()
        } catch {
            lastError = error.localizedDescription
        }
        locallyReadIds.formUnion(items.map(\.stableId))
        persistRead()
        unreadCount = 0
        items = items.map { $0.marking(isRead: true) }
        await applyAppBadge()
    }

    /// Kept for call sites that still use the old name.
    func markFeedSeen() async {
        await markAllRead()
    }

    private func overlayLocalRead(_ item: NotificationItem) -> NotificationItem {
        if locallyReadIds.contains(item.stableId) {
            return item.marking(isRead: true)
        }
        return item
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

    private func persistRead() {
        let trimmed = Array(locallyReadIds.suffix(800))
        locallyReadIds = Set(trimmed)
        UserDefaults.standard.set(trimmed, forKey: readKey)
    }

    private func persistKinds() {
        UserDefaults.standard.set(enabledKinds.map(\.rawValue), forKey: kindsKey)
    }
}
