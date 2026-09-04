import Foundation

enum BookVaultError: LocalizedError {
    case disabled
    case noUser
    case badURL
    case http(Int, String)
    case empty

    var errorDescription: String? {
        switch self {
        case .disabled: return "Облачная полка выключена"
        case .noUser: return "Нужен вход в Author.Today"
        case .badURL: return "Некорректный URL облачной полки"
        case .http(let code, let body): return "Облако \(code): \(body.prefix(160))"
        case .empty: return "Пустой ответ облака"
        }
    }
}

struct BookVaultManifest: Codable, Sendable {
    struct Work: Codable, Sendable {
        let id: Int
        let updatedAt: String?
        let chapterCount: Int?
    }

    let works: [Work]
    let progressUpdatedAt: String?
    let bookmarksUpdatedAt: String?
    let sizeBytes: Int64?
    let generatedAt: String?
}

struct BookVaultProgressDTO: Codable, Sendable {
    var workId: Int
    var chapterId: Int
    var fraction: Double
    var offsetY: Double?
    var pageIndex: Int?
    var updatedAt: String
}

struct BookVaultBookmarkDTO: Codable, Sendable, Identifiable {
    var id: String
    var workId: Int
    var chapterId: Int
    var workTitle: String
    var chapterTitle: String
    var charOffset: Int
    var fraction: Double
    var createdAt: String
}

struct BookVaultBookmarksPayload: Codable, Sendable {
    var items: [BookVaultBookmarkDTO]
    var updatedAt: String
}

/// Low-level HTTP client for `/books/{userId}/…` on TubeVault.
actor BookVaultClient {
    static let shared = BookVaultClient()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 45
        cfg.timeoutIntervalForResource = 180
        cfg.waitsForConnectivity = true
        return URLSession(configuration: cfg)
    }()

    private var preferredBase: URL?

    func resetPreferredBase() {
        preferredBase = nil
    }

    private func settingsSnapshot() async -> (enabled: Bool, token: String, candidates: [URL]) {
        await MainActor.run {
            let s = BookVaultSettings.shared
            return (s.isEnabled, s.apiToken, s.candidateBaseURLs)
        }
    }

    private func requireUserId(_ userId: Int?) throws -> Int {
        guard let userId, userId > 0 else { throw BookVaultError.noUser }
        return userId
    }

    private func authorizedRequest(
        path: String,
        userId: Int,
        method: String,
        body: Data? = nil,
        contentType: String? = "application/json",
        extraHeaders: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        let snap = await settingsSnapshot()
        guard snap.enabled else { throw BookVaultError.disabled }
        guard !snap.token.isEmpty else { throw BookVaultError.disabled }

        var bases = snap.candidates
        if let preferredBase {
            bases.removeAll { $0 == preferredBase }
            bases.insert(preferredBase, at: 0)
        }

        var lastError: Error = BookVaultError.badURL
        for base in bases {
            guard let url = URL(string: path, relativeTo: base)?.absoluteURL else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(snap.token)", forHTTPHeaderField: "Authorization")
            request.setValue("\(userId)", forHTTPHeaderField: "X-AT-User-Id")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            for (k, v) in extraHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
            if let body {
                request.httpBody = body
                if let contentType {
                    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                }
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 401 || http.statusCode == 404 && method == "GET" && path.contains("/health") {
                    lastError = BookVaultError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
                    continue
                }
                preferredBase = base
                await MainActor.run {
                    if BookVaultSettings.shared.baseURL != base.absoluteString {
                        BookVaultSettings.shared.baseURL = base.absoluteString
                    }
                }
                return (data, http)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func validate(_ data: Data, _ http: HTTPURLResponse) throws {
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw BookVaultError.http(http.statusCode, body)
        }
    }

    func health(userId: Int) async throws -> [String: Any] {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(path: "/books/\(uid)/health", userId: uid, method: "GET")
        try validate(data, http)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    func manifest(userId: Int) async throws -> BookVaultManifest {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(path: "/books/\(uid)/manifest", userId: uid, method: "GET")
        try validate(data, http)
        return try JSONDecoder().decode(BookVaultManifest.self, from: data)
    }

    func putMeta(userId: Int, workId: Int, json: Data) async throws {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/works/\(workId)/meta",
            userId: uid,
            method: "PUT",
            body: json
        )
        try validate(data, http)
    }

    func getMeta(userId: Int, workId: Int) async throws -> Data {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/works/\(workId)/meta",
            userId: uid,
            method: "GET"
        )
        try validate(data, http)
        return data
    }

    func putChapter(userId: Int, workId: Int, chapterId: Int, title: String, html: String) async throws {
        let uid = try requireUserId(userId)
        guard let body = html.data(using: .utf8) else { throw BookVaultError.empty }
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/works/\(workId)/chapters/\(chapterId)",
            userId: uid,
            method: "PUT",
            body: body,
            contentType: "text/html; charset=utf-8",
            extraHeaders: ["X-Chapter-Title": title]
        )
        try validate(data, http)
    }

    func getChapter(userId: Int, workId: Int, chapterId: Int) async throws -> String {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/works/\(workId)/chapters/\(chapterId)",
            userId: uid,
            method: "GET"
        )
        try validate(data, http)
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw BookVaultError.empty
        }
        return html
    }

    func listChapters(userId: Int, workId: Int) async throws -> [[String: Any]] {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/works/\(workId)/chapters",
            userId: uid,
            method: "GET"
        )
        try validate(data, http)
        let obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return (obj["chapters"] as? [[String: Any]]) ?? []
    }

    func putProgress(userId: Int, progress: BookVaultProgressDTO) async throws {
        let uid = try requireUserId(userId)
        let body = try JSONEncoder().encode(progress)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/progress/\(progress.workId)",
            userId: uid,
            method: "PUT",
            body: body
        )
        try validate(data, http)
    }

    func getProgress(userId: Int, workId: Int) async throws -> BookVaultProgressDTO? {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/progress/\(workId)",
            userId: uid,
            method: "GET"
        )
        if http.statusCode == 404 { return nil }
        try validate(data, http)
        return try JSONDecoder().decode(BookVaultProgressDTO.self, from: data)
    }

    func listProgress(userId: Int) async throws -> [BookVaultProgressDTO] {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/progress",
            userId: uid,
            method: "GET"
        )
        try validate(data, http)
        struct Wrap: Codable { let items: [BookVaultProgressDTO] }
        return try JSONDecoder().decode(Wrap.self, from: data).items
    }

    func putBookmarks(userId: Int, payload: BookVaultBookmarksPayload) async throws {
        let uid = try requireUserId(userId)
        let body = try JSONEncoder().encode(payload)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/bookmarks",
            userId: uid,
            method: "PUT",
            body: body
        )
        try validate(data, http)
    }

    func getBookmarks(userId: Int) async throws -> BookVaultBookmarksPayload {
        let uid = try requireUserId(userId)
        let (data, http) = try await authorizedRequest(
            path: "/books/\(uid)/bookmarks",
            userId: uid,
            method: "GET"
        )
        try validate(data, http)
        return try JSONDecoder().decode(BookVaultBookmarksPayload.self, from: data)
    }
}
