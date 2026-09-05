import Foundation
import SwiftUI
import UIKit
import UserNotifications

/// Checks https://tv.theinquisitor.ru/chitalnya/meta.json for a newer IPA.
/// Sideload cannot self-replace the app — UI only opens the install page.
@MainActor
final class AppUpdateChecker: ObservableObject {
    static let shared = AppUpdateChecker()

    static let metaURL = URL(string: "https://tv.theinquisitor.ru/chitalnya/meta.json")!
    static let installPageURL = URL(string: "https://tv.theinquisitor.ru/chitalnya/")!

    let appKey = "chitalnya"
    private let appDisplayName = "Читальня"

    @Published private(set) var isChecking = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var statusText: String?
    @Published private(set) var latestLabel: String?
    @Published private(set) var latestId: String?
    @Published private(set) var lastError: String?

    private let dismissedKey = "chitalnya.update.dismissedLatestId"
    private let lastCheckKey = "chitalnya.update.lastCheckAt"
    private let notifiedKey = "chitalnya.update.notifiedLatestId"
    private let minAutoCheckInterval: TimeInterval = 6 * 60 * 60

    var localVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var localBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// Stamped at Codemagic package time to match meta `latestId` (e.g. b51-ef9852e).
    var localPublishId: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "ChitalnyaPublishId") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var localDisplay: String {
        "\(localVersion) (\(localBuild))"
    }

    func openInstallPage() {
        UIApplication.shared.open(Self.installPageURL)
    }

    func dismissCurrentOffer() {
        if let latestId {
            UserDefaults.standard.set(latestId, forKey: dismissedKey)
        }
        updateAvailable = false
    }

    /// Quiet check on launch / become active (throttled).
    func checkIfDue() async {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        if last > 0, Date().timeIntervalSince1970 - last < minAutoCheckInterval {
            return
        }
        await check(force: false)
    }

    func check(force: Bool = true) async {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        defer { isChecking = false }

        do {
            var request = URLRequest(url: Self.metaURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let meta = try JSONDecoder().decode(ChitalnyaMeta.self, from: data)
            guard let app = meta.apps[appKey] else {
                statusText = "В meta.json нет записи «\(appKey)»"
                updateAvailable = false
                return
            }
            let latest = app.resolvedLatest
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)

            latestId = latest?.id
            latestLabel = latest?.displayLabel ?? app.file
            let newer = Self.isRemoteNewer(
                remote: latest,
                localBuild: localBuild,
                localPublishId: localPublishId
            )
            let dismissed = UserDefaults.standard.string(forKey: dismissedKey)
            if newer && (latest?.id != dismissed || force) {
                updateAvailable = true
                statusText = "Доступна новая сборка: \(latestLabel ?? "IPA")"
                if !force {
                    await notifyUpdateAvailable(id: latest?.id, label: latestLabel ?? "IPA")
                }
            } else if newer {
                updateAvailable = false
                statusText = "Есть новая сборка (\(latestLabel ?? "IPA")), скрыта"
            } else {
                updateAvailable = false
                statusText = "Установлена актуальная сборка"
            }
        } catch {
            lastError = error.localizedDescription
            statusText = "Не удалось проверить обновления"
            if force {
                updateAvailable = false
            }
        }
    }

    private func notifyUpdateAvailable(id: String?, label: String) async {
        guard let id, !id.isEmpty else { return }
        if UserDefaults.standard.string(forKey: notifiedKey) == id { return }
        UserDefaults.standard.set(id, forKey: notifiedKey)

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        let after = await center.notificationSettings()
        guard after.authorizationStatus == .authorized || after.authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Новая версия · \(appDisplayName)"
        content.body = "Доступна сборка \(label). Откройте приложение → Обновления IPA → SideStore."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "app.update.\(appKey).\(id)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    static func isRemoteNewer(
        remote: ChitalnyaMeta.Version?,
        localBuild: String,
        localPublishId: String?
    ) -> Bool {
        guard let remote else { return false }
        if let localPublishId, !localPublishId.isEmpty {
            return remote.id != localPublishId
        }
        if let remoteBuild = remote.buildNumber,
           let r = Int(remoteBuild),
           let l = Int(localBuild) {
            return r > l
        }
        // No reliable stamp yet — do not nag; user can still open the install page.
        return false
    }
}

struct ChitalnyaMeta: Decodable {
    let apps: [String: App]

    struct App: Decodable {
        let title: String?
        let file: String?
        let latestId: String?
        let updatedAt: String?
        let versions: [Version]?

        var resolvedLatest: Version? {
            let list = versions ?? []
            if let latestId, let match = list.first(where: { $0.id == latestId }) {
                return match
            }
            return list.first
        }
    }

    struct Version: Decodable {
        let id: String
        let label: String?
        let file: String?
        let buildNumber: String?
        let updatedAt: String?
        let commit: String?

        var displayLabel: String {
            if let label, !label.isEmpty { return label }
            if let buildNumber, !buildNumber.isEmpty { return "build \(buildNumber)" }
            return id
        }
    }
}

struct AppUpdateSettingsSection: View {
    @ObservedObject var checker: AppUpdateChecker

    var body: some View {
        Section {
            LabeledContent("Версия", value: checker.localDisplay)
            if let publishId = checker.localPublishId {
                LabeledContent("Сборка", value: publishId)
            }
            if checker.updateAvailable {
                Button {
                    checker.openInstallPage()
                } label: {
                    Label("Обновить через SideStore", systemImage: "arrow.down.circle.fill")
                }
                Button("Скрыть напоминание") {
                    checker.dismissCurrentOffer()
                }
                .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await checker.check(force: true) }
                } label: {
                    HStack {
                        Text("Проверить обновления")
                        Spacer()
                        if checker.isChecking {
                            ProgressView()
                        }
                    }
                }
                .disabled(checker.isChecking)
            }
            Button("Страница установки") {
                checker.openInstallPage()
            }
            if let statusText = checker.statusText {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(checker.updateAvailable ? Color.accentColor : Color.secondary)
            }
            if let lastError = checker.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Обновления IPA")
        } footer: {
            Text("Приложение само себя не переустанавливает. Новая IPA ставится через SideStore со страницы установки.")
        }
    }
}
