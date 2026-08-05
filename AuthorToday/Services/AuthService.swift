import Foundation
import Combine
import Security

@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published private(set) var isAuthenticated = false
    @Published private(set) var user: CurrentUser?
    @Published var lastError: String?
    @Published var isBusy = false

    private let tokenKey = "at.auth.token"
    private let userIdKey = "at.auth.userId"

    private init() {
        if let token = KeychainStore.get(tokenKey), !token.isEmpty, token != "guest" {
            Task {
                await APIClient.shared.setToken(token)
                isAuthenticated = true
                await refreshProfile()
            }
        }
    }

    var storedToken: String? {
        KeychainStore.get(tokenKey)
    }

    func login(email: String, password: String) async {
        isBusy = true
        lastError = nil
        defer { isBusy = false }
        do {
            let response = try await APIClient.shared.login(email: email, password: password)
            KeychainStore.set(response.token, for: tokenKey)
            if let userId = response.userId {
                UserDefaults.standard.set(userId, forKey: userIdKey)
            }
            isAuthenticated = true
            await refreshProfile()
            try? await APIClient.shared.establishWebSession(token: response.token)
        } catch {
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
            user = try await APIClient.shared.currentUser()
        } catch {
            if case APIError.unauthorized = error {
                logout()
            }
        }
    }

    func logout() {
        KeychainStore.delete(tokenKey)
        UserDefaults.standard.removeObject(forKey: userIdKey)
        Task { await APIClient.shared.setToken("guest") }
        user = nil
        isAuthenticated = false
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
