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
        if let token = KeychainStore.get(tokenKey), !token.isEmpty, token != "guest" {
            Task {
                await APIClient.shared.setToken(token)
                let savedId = UserDefaults.standard.object(forKey: userIdKey) as? Int
                await APIClient.shared.setUserId(savedId)
                isAuthenticated = true
                await refreshProfile()
            }
        }
    }

    /// Username for /u/{user}/library — from profile or last successful sync.
    var resolvedUserName: String? {
        if let name = user?.resolvedUserName { return name }
        let saved = UserDefaults.standard.string(forKey: userNameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (saved?.isEmpty == false) ? saved : nil
    }

    var storedToken: String? {
        KeychainStore.get(tokenKey)
    }

    /// Stable per-install device id for Author.Today login-by-password (2FA / new device).
    private func deviceSecretKey(preferring serverKey: String? = nil) -> String {
        if let serverKey = serverKey?.trimmingCharacters(in: .whitespacesAndNewlines), !serverKey.isEmpty {
            KeychainStore.set(serverKey, for: deviceSecretKeyKey)
            return serverKey
        }
        if let existing = KeychainStore.get(deviceSecretKeyKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString.lowercased()
        KeychainStore.set(generated, for: deviceSecretKeyKey)
        return generated
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
        KeychainStore.set(response.token, for: tokenKey)
        if let userId = response.userId {
            UserDefaults.standard.set(userId, forKey: userIdKey)
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
            if let token = KeychainStore.get(tokenKey) {
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
            ProEntitlementStore.shared.applyAccount(
                email: profile.email ?? loginEmail,
                userName: profile.resolvedUserName
            )
        } catch {
            if case APIError.unauthorized = error {
                logout()
            }
        }
    }

    func logout() {
        KeychainStore.delete(tokenKey)
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

enum KeychainStore {
    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
