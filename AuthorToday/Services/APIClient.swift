import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized(String?)
    case http(Int, String?)
    case decoding(Error)
    case emptyBody
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Некорректный URL"
        case .unauthorized(let m): return m ?? "Требуется авторизация"
        case .http(let code, let m): return m ?? "Ошибка сервера (\(code))"
        case .decoding(let e): return "Ошибка разбора ответа: \(e.localizedDescription)"
        case .emptyBody: return "Пустой ответ сервера"
        case .message(let m): return m
        }
    }
}

struct APIErrorBody: Codable {
    let code: String?
    let message: String?
    let invalidFields: [String: [String]]?
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL = URL(string: "https://api.author.today")!
    private let webURL = URL(string: "https://author.today")!
    private let session: URLSession
    private let decoder: JSONDecoder

    private var token: String = "guest"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        // API often uses camelCase already
    }

    func setToken(_ token: String) {
        self.token = token.isEmpty ? "guest" : token
    }

    func currentToken() -> String { token }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> AuthTokenResponse {
        let body = LoginRequest(login: email, password: password)
        let response: AuthTokenResponse = try await post(
            path: "/v1/account/login-by-password",
            body: body,
            authed: false
        )
        setToken(response.token)
        return response
    }

    func refreshToken() async throws -> AuthTokenResponse {
        let response: AuthTokenResponse = try await post(path: "/v1/account/refresh-token", body: Optional<String>.none)
        setToken(response.token)
        return response
    }

    func currentUser() async throws -> CurrentUser {
        try await get(path: "/v1/account/current-user")
    }

    // MARK: - Library / works

    func userLibrary(page: Int = 1, pageSize: Int = 50) async throws -> LibraryPage {
        try await get(path: "/v1/account/user-library", query: [
            "page": "\(page)",
            "pageSize": "\(pageSize)"
        ])
    }

    func workDetails(id: Int) async throws -> WorkDetails {
        try await get(path: "/v1/work/\(id)/details", query: [
            "recommendationsCount": "0"
        ])
    }

    func workMeta(id: Int) async throws -> WorkMeta {
        try await get(path: "/v1/work/\(id)/meta-info")
    }

    func search(query: String, page: Int = 1) async throws -> CatalogSearchResult {
        try await get(path: "/v1/catalog/search", query: [
            "page": "\(page)",
            "ps": "40",
            "sorting": "popular",
            "q": query,
            "tag": query
        ])
    }

    func catalogRecent(page: Int = 1) async throws -> CatalogSearchResult {
        try await get(path: "/v1/catalog/search", query: [
            "page": "\(page)",
            "ps": "40",
            "sorting": "recent",
            "genre": "all"
        ])
    }

    // MARK: - Chapters

    /// Fetches encrypted chapter text and decrypts using Reader-Secret.
    func chapterText(workId: Int, chapterId: Int) async throws -> (title: String?, html: String) {
        // Prefer official API endpoint
        do {
            let (data, headers) = try await rawGet(
                path: "/v1/work/\(workId)/chapter/\(chapterId)/text"
            )
            let secret = headers["Reader-Secret"] ?? headers["reader-secret"]
            let payload = try decodeFlexible(ChapterTextPayload.self, from: data)
            guard let encrypted = payload.resolvedText else {
                throw APIError.emptyBody
            }
            let html: String
            if let secret, !secret.isEmpty {
                html = ChapterDecryptor.decrypt(encrypted, readerSecret: secret)
            } else {
                // Already plain HTML in some responses
                html = encrypted
            }
            return (payload.resolvedTitle, html)
        } catch {
            // Fallback: web reader endpoint used by crawlers
            let (data, headers) = try await rawGet(
                absoluteURL: try {
                    let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard let url = URL(string: "\(base)/reader/\(workId)/chapter") else {
                        throw APIError.invalidURL
                    }
                    return url
                }(),
                query: ["id": "\(chapterId)"]
            )
            let secret = headers["Reader-Secret"] ?? headers["reader-secret"]
            let payload = try decodeFlexible(ChapterTextPayload.self, from: data)
            guard let encrypted = payload.resolvedText else {
                throw APIError.emptyBody
            }
            let html: String
            if let secret, !secret.isEmpty {
                html = ChapterDecryptor.decrypt(encrypted, readerSecret: secret)
            } else {
                html = encrypted
            }
            return (payload.resolvedTitle, html)
        }
    }

    func manyChapterTexts(workId: Int, chapterIds: [Int] = []) async throws -> [(id: Int, title: String?, html: String)] {
        var query: [String: String] = [:]
        if chapterIds.isEmpty {
            // empty list means all chapters per API docs
        } else {
            for (i, id) in chapterIds.enumerated() {
                query["ids[\(i)]"] = "\(id)"
            }
        }

        let (data, headers) = try await rawGet(
            path: "/v1/work/\(workId)/chapter/many-texts",
            query: query
        )
        let secret = headers["Reader-Secret"] ?? headers["reader-secret"]
        // Response may be array or wrapped
        if let batch = try? decodeFlexible(ChapterBatchResult.self, from: data) {
            return batch.items.compactMap { item in
                guard let text = item.resolvedText else { return nil }
                let html: String
                if let secret, !secret.isEmpty {
                    html = ChapterDecryptor.decrypt(text, readerSecret: secret)
                } else {
                    html = text
                }
                return (item.id ?? item.data?.id ?? 0, item.resolvedTitle, html)
            }
        }
        if let array = try? decoder.decode([ChapterTextPayload].self, from: data) {
            return array.compactMap { item in
                guard let text = item.resolvedText else { return nil }
                let html: String
                if let secret, !secret.isEmpty {
                    html = ChapterDecryptor.decrypt(text, readerSecret: secret)
                } else {
                    html = text
                }
                return (item.id ?? 0, item.resolvedTitle, html)
            }
        }
        throw APIError.message("Не удалось разобрать главы")
    }

    func readerStart(workId: Int, chapterId: Int) async throws {
        let _: EmptyJSON = try await get(path: "/v1/reader/start/\(workId)/\(chapterId)")
    }

    func updateProgress(workId: Int, chapterId: Int, progress: Double?, location: String?) async throws {
        let body = UpdateProgressRequest(
            workId: workId,
            chapterId: chapterId,
            location: location,
            progress: progress
        )
        let _: EmptyJSON = try await post(path: "/v1/reader/update-progress", body: body)
    }

    // MARK: - Notifications

    func checkNotifications() async throws -> NotificationCheck {
        try await get(path: "/v1/notification/check")
    }

    func notifications(take: Int = 30, category: String? = nil) async throws -> [NotificationItem] {
        var q: [String: String] = ["take": "\(take)"]
        if let category { q["category"] = category }
        let list: NotificationList = try await get(path: "/v1/notification/get", query: q)
        return list.all
    }

    func markAllNotificationsRead() async throws {
        let _: EmptyJSON = try await post(path: "/v1/notification/mark-all-as-read", body: Optional<String>.none)
    }

    // MARK: - HTTP helpers

    private struct EmptyJSON: Codable {}

    private func get<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> T {
        let (data, _) = try await rawGet(path: path, query: query)
        return try decodeFlexible(T.self, from: data)
    }

    private func makeURL(path: String, query: [String: String] = [:]) throws -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(base)/\(trimmed)") else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func post<T: Decodable, B: Encodable>(path: String, body: B?, authed: Bool = true) async throws -> T {
        let url = try makeURL(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request, authed: authed)
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        } else {
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        if T.self == EmptyJSON.self {
            return EmptyJSON() as! T
        }
        if data.isEmpty {
            throw APIError.emptyBody
        }
        return try decodeFlexible(T.self, from: data)
    }

    private func rawGet(path: String, query: [String: String] = [:]) async throws -> (Data, [String: String]) {
        try await rawGet(absoluteURL: try makeURL(path: path, query: query), query: [:])
    }

    private func rawGet(absoluteURL: URL, query: [String: String] = [:]) async throws -> (Data, [String: String]) {
        var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            let existing = components.queryItems ?? []
            components.queryItems = existing + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request, authed: true)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        var headers: [String: String] = [:]
        if let http = response as? HTTPURLResponse {
            for (k, v) in http.allHeaderFields {
                if let ks = k as? String {
                    headers[ks] = "\(v)"
                }
            }
        }
        return (data, headers)
    }

    private func applyHeaders(_ request: inout URLRequest, authed: Bool) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "AuthorToday/ios_1.0 (iPhone15,3; iOS 17) AuthorTodayReader",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = authed
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200..<300).contains(http.statusCode) { return }
        let body = try? decoder.decode(APIErrorBody.self, from: data)
        let message = body?.message
        if http.statusCode == 401 {
            throw APIError.unauthorized(message)
        }
        throw APIError.http(http.statusCode, message)
    }

    private func decodeFlexible<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if data.isEmpty {
            if T.self == EmptyJSON.self {
                return EmptyJSON() as! T
            }
            throw APIError.emptyBody
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Sometimes wrapped as { "data": ... }
            if let wrapped = try? decoder.decode(Wrapper<T>.self, from: data) {
                return wrapped.data
            }
            throw APIError.decoding(error)
        }
    }

    private struct Wrapper<T: Decodable>: Decodable {
        let data: T
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        if hasPrefix(prefix) {
            return String(dropFirst(prefix.count))
        }
        return self
    }
}
