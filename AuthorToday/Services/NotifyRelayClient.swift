import Foundation

/// Cheap delta client for VPS Author.Today notification relay.
/// Server polls AT; app only asks "what's new since …".
enum NotifyRelayClient {
    static let baseURL = URL(string: "https://at.theinquisitor.ru/chitalnya/api")!

    struct DeltaItem: Decodable, Sendable, Identifiable {
        let id: String
        let title: String?
        let body: String?
        let workId: Int?
        let postId: Int?
        let createdAt: String?
        let seenAt: String?
    }

    struct DeltaResponse: Decodable, Sendable {
        let items: [DeltaItem]
        let serverTime: String?
        let enabled: Bool?
        let lastCheckAt: String?
        let lastError: String?
    }

    struct StatusResponse: Decodable, Sendable {
        let registered: Bool
        let enabled: Bool?
        let lastCheckAt: String?
        let lastUnread: Int?
        let lastError: String?
        let eventCount: Int?
        let pollSeconds: Int?
    }

    struct RegisterResponse: Decodable, Sendable {
        let ok: Bool?
        let enabled: Bool?
        let seeded: Int?
        let error: String?
        let pollSeconds: Int?
    }

    private static func vaultToken() -> String {
        let trimmed = BookVaultSettings.shared.apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return BookVaultSettings.BuiltIn.sharedShelfToken
    }

    private static func authorizedRequest(path: String, method: String, body: Data? = None) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(vaultToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        if let body {
            request.httpBody = body
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func register(userId: Int, atToken: String, enabled: Bool = true) async -> RegisterResponse? {
        let payload: [String: Any] = [
            "userId": userId,
            "atToken": atToken,
            "enabled": enabled,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        let request = authorizedRequest(path: "notify-register", method: "POST", body: body)
        return await decode(RegisterResponse.self, request: request)
    }

    static func unregister(userId: Int, forgetToken: Bool = true) async {
        let payload: [String: Any] = [
            "userId": userId,
            "forgetToken": forgetToken,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let request = authorizedRequest(path: "notify-unregister", method: "POST", body: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func delta(userId: Int, since: String?) async -> DeltaResponse? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("notify-delta"),
            resolvingAgainstBaseURL: false
        )
        var items = [URLQueryItem(name: "userId", value: String(userId))]
        if let since, !since.isEmpty {
            items.append(URLQueryItem(name: "since", value: since))
        }
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(vaultToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return await decode(DeltaResponse.self, request: request)
    }

    static func registerDeviceToken(userId: Int, deviceToken: String, environment: String) async {
        let payload: [String: Any] = [
            "userId": userId,
            "deviceToken": deviceToken,
            "environment": environment,
            "bundleId": Bundle.main.bundleIdentifier ?? "ru.chitalnya.reader",
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let request = authorizedRequest(path: "notify-device", method: "POST", body: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func unregisterDeviceToken(userId: Int, deviceToken: String) async {
        let payload: [String: Any] = [
            "userId": userId,
            "deviceToken": deviceToken,
            "forget": true,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let request = authorizedRequest(path: "notify-device", method: "POST", body: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func status(userId: Int) async -> StatusResponse? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("notify-status"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "userId", value: String(userId))]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(vaultToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12
        return await decode(StatusResponse.self, request: request)
    }

    private static func decode<T: Decodable>(_ type: T.Type, request: URLRequest) async -> T? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }
}
