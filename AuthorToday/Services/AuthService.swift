import Foundation
import Combine
import Security

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var user: CurrentUser?
    @Published private(set) var awaitingTwoFactor = false
    @Published var lastError: String?
    @Published var isBusy = false

    private let tokenKey = "at.auth.token"
    private let userIdKey = "at.auth.userId"
    private let userNameKey = "at.auth.userName"
    private let loginEmailKey = "at.auth.loginEmail"
    private let deviceSecretKeyKey = "at.auth.deviceSecretKey"

    private var pendingEmail = ""
    private var pendingPassword = ""

    private init() {
        // Sideload over-installs often lose Keychain (signing/team change) while the
        // app container survives — restore token from Application Support backup.
        if let token = loadPersistedToken(), !token.isEmpty, token != "guest" {
            isAuthenticated = true
            Task {
                await APIClient.shared.setToken(token)
                let savedId = UserDefaults.standard.object(forKey: userIdKey) as? Int
                    ?? SessionFileBackup.load()?.userId
                await APIClient.shared.setUserId(savedId)
                await refreshProfile()
            }
        }
    }

    /// Username for /u/{user}/library — from profile or last successful sync.
    var resolvedUserName: String? {
        if let name = user?.resolvedUserName { return name }
        let saved = UserDefaults.standard.string(forKey: userNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty { return saved }
        return SessionFileBackup.load()?.userName
    }

    /// Last email/login used on this install (survives updates, not full uninstall).
    var rememberedLogin: String? {
        let saved = UserDefaults.standard.string(forKey: loginEmailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let saved, !saved.isEmpty { return saved }
        return SessionFileBackup.load()?.loginEmail
    }

    var storedToken: String? {
        loadPersistedToken()
    }

    /// Stable per-install device id for Author.Today login-by-password (2FA / new device).
    private func deviceSecretKey(preferring serverKey: String? = nil) -> String {
        if let serverKey = serverKey?.trimmingCharacters(in: .whitespacesAndNewlines), !serverKey.isEmpty {
            persistDeviceSecret(serverKey)
            return serverKey
        }
        if let existing = KeychainStore.get(deviceSecretKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            SessionFileBackup.update { $0.deviceSecret = existing }
            return existing
        }
        if let backup = SessionFileBackup.load()?.deviceSecret?.trimmingCharacters(in: .whitespacesAndNewlines),
           !backup.isEmpty {
            KeychainStore.set(backup, for: deviceSecretKeyKey)
            return backup
        }
        let generated = UUID().uuidString.lowercased()
        persistDeviceSecret(generated)
        return generated
    }

    private func persistDeviceSecret(_ secret: String) {
        KeychainStore.set(secret, for: deviceSecretKeyKey)
        SessionFileBackup.update { $0.deviceSecret = secret }
    }

    private func loadPersistedToken() -> String? {
        if let token = KeychainStore.get(tokenKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty, token != "guest" {
            // Keep disk mirror warm for the next sideload update.
            SessionFileBackup.update { $0.token = token }
            return token
        }
        if let token = SessionFileBackup.load()?.token?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty, token != "guest" {
            KeychainStore.set(token, for: tokenKey)
            return token
        }
        return nil
    }

    private func persistToken(_ token: String) {
        KeychainStore.set(token, for: tokenKey)
        SessionFileBackup.update { $0.token = token }
    }

    func login(email: String, password: String, code: String? = nil) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = code?.trimmingCharacters(in: .whitespacesAndNewlines)
        let codeToSend = (trimmedCode?.isEmpty == false) ? trimmedCode : nil
        let secret = deviceSecretKey()

        do {
            let response = try await APIClient.shared.login(
                email: trimmedEmail,
                password: password,
                code: codeToSend,
                secretKey: secret
            )
            UserDefaults.standard.set(trimmedEmail, forKey: loginEmailKey)
            SessionFileBackup.update { $0.loginEmail = trimmedEmail }
            await applySuccessfulLogin(response)
            pendingEmail = ""
            pendingPassword = ""
            awaitingTwoFactor = false
        } catch let error as APIError {
            handleLoginError(error, email: trimmedEmail, password: password, sentCode: codeToSend != nil)
        } catch {
            lastError = error.localizedDescription
            isAuthenticated = false
        }
    }

    /// Step 2: submit the email confirmation code.
    func submitTwoFactorCode(_ code: String) async {
        guard !pendingEmail.isEmpty else {
            lastError = "Сначала введите email и пароль."
            awaitingTwoFactor = false
            return
        }
        await login(email: pendingEmail, password: pendingPassword, code: code)
    }

    /// Ask Author.Today to send the confirmation email again (login without code).
    func resendTwoFactorCode() async {
        guard !pendingEmail.isEmpty else { return }
        await login(email: pendingEmail, password: pendingPassword, code: nil)
        if !isAuthenticated {
            awaitingTwoFactor = true
            if lastError == nil {
                lastError = "Если письмо не пришло, проверьте папку «Спам»."
            }
        }
    }

    func cancelTwoFactor() {
        awaitingTwoFactor = false
        pendingEmail = ""
        pendingPassword = ""
        lastError = nil
    }

    private func applySuccessfulLogin(_ response: AuthTokenResponse) async {
        persistToken(response.token)
        if let userId = response.userId {
            UserDefaults.standard.set(userId, forKey: userIdKey)
            SessionFileBackup.update { $0.userId = userId }
            await APIClient.shared.setUserId(userId)
        }
        isAuthenticated = true
        await refreshProfile()
        try? await APIClient.shared.establishWebSession(token: response.token)
    }

    private func handleLoginError(
        _ error: APIError,
        email: String,
        password: String,
        sentCode: Bool
    ) {
        switch error {
        case .twoFactorRequired(let message, let serverKey):
            _ = deviceSecretKey(preferring: serverKey)
            pendingEmail = email
            pendingPassword = password
            awaitingTwoFactor = true
            lastError = message
            isAuthenticated = false

        case .twoFactorInvalid(let message):
            // Without a code, CodeNotValid often means “enter the email code”.
            if !sentCode {
                pendingEmail = email
                pendingPassword = password
                awaitingTwoFactor = true
                lastError = message ?? "На почту отправлен код подтверждения. Введите его для входа."
            } else {
                awaitingTwoFactor = true
                lastError = message ?? "Неверный код подтверждения."
            }
            isAuthenticated = false

        case .twoFactorVersionUnsupported(let message):
            lastError = message
                ?? "Сервер отклонил версию клиента для входа с кодом. Обновите приложение."
            isAuthenticated = false

        case .unauthorized(let message):
            lastError = message ?? "Неверный логин или пароль."
            isAuthenticated = false

        default:
            lastError = error.localizedDescription
            isAuthenticated = false
        }
    }

    func refreshProfile() async {
        do {
            try await loadProfile()
        } catch {
            guard case APIError.unauthorized = error else { return }
            // Expired access token after an update — refresh before forcing re-login.
            if await refreshSessionToken() {
                do {
                    try await loadProfile()
                    return
                } catch {
                    if case APIError.unauthorized = error {
                        logout()
                    }
                    return
                }
            }
            logout()
        }
    }

    private func loadProfile() async throws {
        if let token = loadPersistedToken() {
            await APIClient.shared.setToken(token)
            try? await APIClient.shared.establishWebSession(token: token)
        }
        let profile = try await APIClient.shared.currentUser()
        user = profile
        await APIClient.shared.setUserId(profile.id)
        if let name = profile.resolvedUserName {
            UserDefaults.standard.set(name, forKey: userNameKey)
        }
        UserDefaults.standard.set(profile.id, forKey: userIdKey)
        let loginEmail = UserDefaults.standard.string(forKey: loginEmailKey)
            ?? SessionFileBackup.load()?.loginEmail
        SessionFileBackup.update {
            $0.userId = profile.id
            $0.userName = profile.resolvedUserName
            if let loginEmail, !loginEmail.isEmpty {
                $0.loginEmail = loginEmail
            }
            if let token = loadPersistedToken() {
                $0.token = token
            }
        }
        ProEntitlementStore.shared.applyAccount(
            email: profile.email ?? loginEmail,
            userName: profile.resolvedUserName
        )
    }

    @discardableResult
    private func refreshSessionToken() async -> Bool {
        do {
            let response = try await APIClient.shared.refreshToken()
            persistToken(response.token)
            await APIClient.shared.setToken(response.token)
            if let userId = response.userId {
                UserDefaults.standard.set(userId, forKey: userIdKey)
                SessionFileBackup.update { $0.userId = userId }
                await APIClient.shared.setUserId(userId)
            }
            try? await APIClient.shared.establishWebSession(token: response.token)
            return true
        } catch {
            return false
        }
    }

    func logout() {
        KeychainStore.delete(tokenKey)
        SessionFileBackup.clear()
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: loginEmailKey)
        awaitingTwoFactor = false
        pendingEmail = ""
        pendingPassword = ""
        Task {
            await APIClient.shared.setToken("guest")
            await APIClient.shared.setUserId(nil)
        }
        user = nil
        isAuthenticated = false
        ProEntitlementStore.shared.applyAccount(nil)
    }
}

/// App-container session mirror. Survives over-the-top IPA updates when Keychain
/// becomes unreachable after a signing/team change (common for sideload builds).
private enum SessionFileBackup {
    struct Payload: Codable {
        var token: String?
        var deviceSecret: String?
        var loginEmail: String?
        var userId: Int?
        var userName: String?
    }

    private static var fileURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = root.appendingPathComponent("Chitalnya", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("session.v1.json")
    }

    static func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    static func update(_ mutate: (inout Payload) -> Void) {
        var payload = load() ?? Payload()
        mutate(&payload)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

enum KeychainStore {
    private static var service: String {
        Bundle.main.bundleIdentifier ?? "ru.chitalnya.reader"
    }

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        // Remove both new and legacy (no-service) rows to avoid duplicates.
        delete(key)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // AfterFirstUnlock (not ThisDeviceOnly): more tolerant across resign/update.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        if let value = copy(account: key, service: service) {
            return value
        }
        // Migrate items written by older builds without kSecAttrService.
        if let legacy = copy(account: key, service: nil) {
            set(legacy, for: key)
            return legacy
        }
        return nil
    }

    static func delete(_ key: String) {
        delete(account: key, service: service)
        delete(account: key, service: nil)
    }

    private static func copy(account: String, service: String?) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let service {
            query[kSecAttrService as String] = service
        }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String, service: String?) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        if let service {
            query[kSecAttrService as String] = service
        }
        SecItemDelete(query as CFDictionary)
    }
}
