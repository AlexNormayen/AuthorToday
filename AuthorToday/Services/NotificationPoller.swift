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

    private var timer: Timer?
    private var knownIds: Set<String> = []
    private let knownKey = "at.knownNotificationIds"
    private let pollInterval: TimeInterval = 120

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

    func refresh(announceNew: Bool) async {
        do {
            let check = try await APIClient.shared.checkNotifications()
            unreadCount = check.effectiveUnread
            let list = try await APIClient.shared.notifications(take: 40)
            items = list

            if announceNew {
                for item in list where !(item.isRead ?? false) {
                    let sid = item.stableId
                    if !knownIds.contains(sid) {
                        knownIds.insert(sid)
                        await postLocal(item)
                    }
                }
                persistKnown()
            } else {
                knownIds.formUnion(list.map(\.stableId))
                persistKnown()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func markAllRead() async {
        do {
            try await APIClient.shared.markAllNotificationsRead()
            unreadCount = 0
            items = items.map { item in
                NotificationItem(
                    id: item.id,
                    text: item.text,
                    title: item.title,
                    message: item.message,
                    creationTime: item.creationTime,
                    isRead: true,
                    workId: item.workId,
                    url: item.url,
                    category: item.category
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func postLocal(_ item: NotificationItem) async {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Author.Today"
        content.body = item.displayText
        content.sound = .default
        if let workId = item.workId {
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
        // keep last 500
        let trimmed = Array(knownIds.suffix(500))
        knownIds = Set(trimmed)
        UserDefaults.standard.set(trimmed, forKey: knownKey)
    }
}
