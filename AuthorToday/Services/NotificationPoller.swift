import Foundation
import UserNotifications
import BackgroundTasks
import Combine
import UIKit

/// Polls Author.Today notification API and posts local notifications.
/// Remote APNs need a server + paid Apple Developer account — here we use
/// local alerts from foreground polling and BGAppRefresh.
@MainActor
final class NotificationPoller: ObservableObject {
    static let shared = NotificationPoller()
    static let refreshTaskId = "ru.chitalnya.reader.refresh"

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
    private let alertsKey = "at.localAlertsEnabled"
    private let relayKey = "at.notifyRelayEnabled"
    private let relaySinceKey = "at.notifyRelaySince"
    private let chapterCountsKey = "at.knownChapterCounts"
    /// Direct Author.Today poll while app is open (fallback / full feed sync).
    private let pollInterval: TimeInterval = 90
    /// Cheap VPS delta when relay is on — much lower latency without hammering AT.
    private let relayInterval: TimeInterval = 20
    @Published var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: alertsKey) }
    }
    /// Opt-in: VPS stores AT bearer and polls for this account.
    @Published var relayEnabled: Bool {
        didSet {
            UserDefaults.standard.set(relayEnabled, forKey: relayKey)
            Task { await applyRelayPreferenceChange() }
        }
    }
    @Published var relayStatusText: String = ""
    private let pageSize = 20
    private var cursor: String?
    private var seenStableIds = Set<String>()
    private var relayTimer: Timer?
    private var lastDirectPollAt: Date = .distantPast

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
        if UserDefaults.standard.object(forKey: alertsKey) == nil {
            alertsEnabled = true
        } else {
            alertsEnabled = UserDefaults.standard.bool(forKey: alertsKey)
        }
        relayEnabled = UserDefaults.standard.bool(forKey: relayKey)
    }

    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await NotificationPoller.shared.handleBackgroundRefresh(refresh)
            }
        }
    }

    private let deviceTokenKey = "at.apnsDeviceToken"

    func configure() async {
        let center = UNUserNotificationCenter.current()
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if isAuthorized {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Called from AppPushDelegate after APNs registration.
    func handleDeviceToken(_ hex: String) async {
        UserDefaults.standard.set(hex, forKey: deviceTokenKey)
        guard relayEnabled else { return }
        guard let userId = await resolvedUserId() else { return }
        #if DEBUG && !APPSTORE
        let env = "sandbox"
        #else
        let env = "production"
        #endif
        await NotifyRelayClient.registerDeviceToken(userId: userId, deviceToken: hex, environment: env)
        if relayStatusText.isEmpty || relayStatusText.contains("APNs") {
            relayStatusText = "APNs token зарегистрирован"
        }
    }

    func startPolling() {
        stopPolling()
        scheduleBackgroundRefresh()
        Task {
            await refresh(announceNew: false)
            if relayEnabled {
                await syncRelayRegistration()
                await pollRelayDelta(announceNew: false)
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // With relay on, full AT feed sync is less urgent — every ~3 min.
                if self.relayEnabled, Date().timeIntervalSince(self.lastDirectPollAt) < 180 {
                    return
                }
                await self.refresh(announceNew: true)
            }
        }
        if relayEnabled {
            startRelayTimer()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        relayTimer?.invalidate()
        relayTimer = nil
    }

    private func startRelayTimer() {
        relayTimer?.invalidate()
        relayTimer = Timer.scheduledTimer(withTimeInterval: relayInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.pollRelayDelta(announceNew: true)
            }
        }
    }

    private func applyRelayPreferenceChange() async {
        if relayEnabled {
            await syncRelayRegistration()
            startRelayTimer()
            await pollRelayDelta(announceNew: true)
        } else {
            relayTimer?.invalidate()
            relayTimer = nil
            await unregisterRelay()
            relayStatusText = "VPS-оповещения выключены"
        }
    }

    private func resolvedUserId() async -> Int? {
        if let id = await APIClient.shared.currentUserId(), id > 0 { return id }
        if let id = UserDefaults.standard.object(forKey: "at.auth.userId") as? Int, id > 0 { return id }
        return nil
    }

    /// Push current AT bearer to VPS (opt-in). Call after login / token refresh.
    func syncRelayRegistration() async {
        guard relayEnabled else { return }
        guard let userId = await resolvedUserId() else {
            relayStatusText = "Нужен вход в Author.Today"
            return
        }
        guard let token = AuthService.shared.loadTokenForRelay(), !token.isEmpty else {
            relayStatusText = "Нет токена Author.Today"
            return
        }
        // Ensure vault bearer is available for notify API auth.
        if BookVaultSettings.shared.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            BookVaultSettings.shared.applySharedShelfToken()
        }
        if let res = await NotifyRelayClient.register(userId: userId, atToken: token, enabled: true) {
            if let err = res.error, !err.isEmpty {
                relayStatusText = "VPS: \(err)"
            } else {
                let seeded = res.seeded ?? 0
                relayStatusText = seeded > 0
                    ? "VPS: активно · засеяно \(seeded)"
                    : "VPS: активно · опрос ~\(res.pollSeconds ?? 45)с"
            }
        } else {
            relayStatusText = "VPS: не удалось зарегистрировать"
        }
        if let hex = UserDefaults.standard.string(forKey: deviceTokenKey), !hex.isEmpty {
            await handleDeviceToken(hex)
        } else if isAuthorized {
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func unregisterRelay() async {
        guard let userId = await resolvedUserId() else { return }
        if let hex = UserDefaults.standard.string(forKey: deviceTokenKey), !hex.isEmpty {
            await NotifyRelayClient.unregisterDeviceToken(userId: userId, deviceToken: hex)
        }
        await NotifyRelayClient.unregister(userId: userId, forgetToken: true)
        UserDefaults.standard.removeObject(forKey: relaySinceKey)
    }

    func pollRelayDelta(announceNew: Bool) async {
        guard relayEnabled else { return }
        guard let userId = await resolvedUserId() else { return }
        let since = UserDefaults.standard.string(forKey: relaySinceKey)
        guard let delta = await NotifyRelayClient.delta(userId: userId, since: since) else {
            relayStatusText = "VPS: нет ответа delta"
            return
        }
        if let serverTime = delta.serverTime, !serverTime.isEmpty {
            UserDefaults.standard.set(serverTime, forKey: relaySinceKey)
        }
        if let err = delta.lastError, !err.isEmpty {
            relayStatusText = "VPS: \(err)"
        } else if let check = delta.lastCheckAt {
            relayStatusText = "VPS: ок · \(check)"
        }
        guard announceNew, !delta.items.isEmpty else { return }
        for item in delta.items {
            let sid = "relay:\(item.id)"
            if knownIds.contains(sid) { continue }
            knownIds.insert(sid)
            await postRelayLocal(item)
        }
        persistKnown()
        // Refresh in-app feed list so badge/tab catch up without waiting for 90s AT poll.
        await refresh(announceNew: false)
    }

    private func postRelayLocal(_ item: NotifyRelayClient.DeltaItem) async {
        guard alertsEnabled, isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title?.isEmpty == false ? (item.title ?? "Читальня") : "Читальня"
        content.body = item.body?.isEmpty == false ? (item.body ?? "Новое уведомление") : "Новое уведомление Author.Today"
        content.sound = .default
        if let workId = item.workId {
            content.userInfo = ["workId": workId]
        } else if let postId = item.postId {
            content.userInfo = ["postId": postId]
        }
        let request = UNNotificationRequest(
            identifier: "relay-\(item.id)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
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
            lastDirectPollAt = .now
            await applyAppBadge()
            if announceNew {
                await checkLibraryChapterUpdates()
            }
            scheduleBackgroundRefresh()
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

    func handleSceneBecameActive() async {
        scheduleBackgroundRefresh()
        await refresh(announceNew: true)
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func handleBackgroundRefresh(_ task: BGAppRefreshTask) async {
        scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            await refresh(announceNew: true)
            await checkLibraryChapterUpdates()
        }
        task.expirationHandler = {
            work.cancel()
        }
        await work.value
        task.setTaskCompleted(success: !work.isCancelled)
    }

    /// Notify about new chapters on books we already have locally.
    func checkLibraryChapterUpdates() async {
        guard alertsEnabled, isAuthorized else { return }
        guard DownloadManager.shared.online else { return }
        let store = OfflineStore.shared
        var ids: [Int] = []
        var seen = Set<Int>()
        for work in store.downloadedWorks + store.recentlyRead + store.library {
            if seen.insert(work.workId).inserted {
                ids.append(work.workId)
            }
            if ids.count >= 40 { break }
        }
        guard !ids.isEmpty else { return }
        guard let metas = try? await APIClient.shared.workMetas(ids: ids) else { return }
        var known = (UserDefaults.standard.dictionary(forKey: chapterCountsKey) as? [String: Int]) ?? [:]
        for meta in metas {
            let key = String(meta.id)
            let previous = known[key]
            let current = meta.chapterCount ?? 0
            if let previous, current > previous {
                await postChapterUpdate(
                    workId: meta.id,
                    title: meta.displayTitle,
                    added: current - previous
                )
            }
            if current > 0 {
                known[key] = current
            }
        }
        UserDefaults.standard.set(known, forKey: chapterCountsKey)
    }

    private func postChapterUpdate(workId: Int, title: String, added: Int) async {
        guard alertsEnabled, isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Читальня"
        content.body = added == 1
            ? "Новая глава в «\(title)»"
            : "+\(added) глав в «\(title)»"
        content.sound = .default
        content.userInfo = ["workId": workId]
        let request = UNNotificationRequest(
            identifier: "chapter-\(workId)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func postLocal(_ item: NotificationItem) async {
        guard alertsEnabled, isAuthorized else { return }
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

    /// Remember current chapter counts so the next poll can detect new chapters.
    func rememberChapterCount(workId: Int, count: Int) {
        guard count > 0 else { return }
        var known = (UserDefaults.standard.dictionary(forKey: chapterCountsKey) as? [String: Int]) ?? [:]
        if known[String(workId)] == nil {
            known[String(workId)] = count
            UserDefaults.standard.set(known, forKey: chapterCountsKey)
        }
    }

    /// Drop feed cursors / chapter baselines when switching Author.Today accounts.
    func clearAccountLocalState() {
        knownIds = []
        locallyReadIds = []
        items = []
        unreadCount = 0
        cursor = nil
        seenStableIds = []
        hasMore = false
        lastError = nil
        relayStatusText = ""
        UserDefaults.standard.removeObject(forKey: knownKey)
        UserDefaults.standard.removeObject(forKey: readKey)
        UserDefaults.standard.removeObject(forKey: chapterCountsKey)
        UserDefaults.standard.removeObject(forKey: relaySinceKey)
    }
}
