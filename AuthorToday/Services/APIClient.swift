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
    private var userId: String = ""

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
    }

    func setToken(_ token: String) {
        self.token = token.isEmpty ? "guest" : token
    }

    func setUserId(_ id: Int?) {
        if let id {
            userId = String(id)
        } else {
            userId = ""
        }
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
        try? await establishWebSession(token: response.token)
        return response
    }

    /// Exchanges bearer token for site LoginCookie so /feed and profile pages work.
    func establishWebSession(token: String? = nil) async throws {
        let t = token ?? self.token
        guard t != "guest", !t.isEmpty else { return }
        let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/account/login-cookie-by-token?token=\(t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? t)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyHeaders(&request, authed: true)
        request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: request)
        _ = response
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

    func userLibrary(page: Int = 1, pageSize: Int = 50) async throws -> [WorkMeta] {
        try await withRetry(times: 4) {
            let (data, _) = try await rawGet(path: "/v1/account/user-library", query: [
                "page": "\(page)",
                "pageSize": "\(pageSize)"
            ])
            return try decodeWorkList(from: data)
        }
    }

    /// Retries transient HTTP errors (esp. 429 rate limit).
    private func withRetry<T>(times: Int, operation: () async throws -> T) async throws -> T {
        var attempt = 0
        var lastError: Error?
        while attempt < times {
            do {
                return try await operation()
            } catch let error as APIError {
                lastError = error
                if case .http(let code, _) = error, code == 429 || code == 503 {
                    attempt += 1
                    let ns = UInt64(pow(2.0, Double(attempt))) * 400_000_000
                    try? await Task.sleep(nanoseconds: ns)
                    continue
                }
                throw error
            } catch {
                lastError = error
                attempt += 1
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        throw lastError ?? APIError.message("Повтор запроса не удался")
    }

    /// Public (or cookie-authenticated) profile library pages, e.g. /u/dark_tarkhan/library
    /// - Parameter enrichMissingOnly: if true, skip meta-info for IDs already known (avoids 429).
    func libraryFromProfile(
        username: String,
        maxPages: Int = 25,
        enrichMissingOnly: Bool = false,
        knownIDs: Set<Int> = []
    ) async throws -> [WorkMeta] {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return [] }
        try? await establishWebSession()

        var scraped: [ScrapedShelfItem] = []
        var seen = Set<Int>()
        for page in 1...maxPages {
            let encoded = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
            let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: "\(base)/u/\(encoded)/library?sorting=lr&page=\(page)") else { continue }
            var request = URLRequest(url: url)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.setValue(
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
            if token != "guest" {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await session.data(for: request)
            try validate(response: response, data: data)
            guard let html = String(data: data, encoding: .utf8) else { break }
            let pageItems = extractShelfItems(from: html)
            let fresh = pageItems.filter { seen.insert($0.id).inserted }
            if fresh.isEmpty { break }
            scraped.append(contentsOf: fresh)
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        guard !scraped.isEmpty else { return [] }

        let needMeta = scraped.map(\.id).filter { !enrichMissingOnly || !knownIDs.contains($0) }
        var metaByID: [Int: WorkMeta] = [:]
        for chunkStart in stride(from: 0, to: needMeta.count, by: 40) {
            let end = min(chunkStart + 40, needMeta.count)
            let chunk = Array(needMeta[chunkStart..<end])
            if let metas = try? await workMetas(ids: chunk) {
                for meta in metas {
                    metaByID[meta.id] = meta
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        return scraped.compactMap { item -> WorkMeta? in
            if enrichMissingOnly, knownIDs.contains(item.id) {
                return nil
            }
            let state = Self.normalizeLibraryState(item.state) ?? "Reading"
            if let meta = metaByID[item.id] {
                let remote = (meta.resolvedLibraryState ?? "").lowercased()
                if remote.isEmpty || remote == "none" {
                    return meta.withLibraryState(state)
                }
                return meta
            }
            return WorkMeta.stub(
                id: item.id,
                title: item.title,
                author: item.author,
                coverUrl: item.coverURL,
                libraryState: state
            )
        }
    }

    private struct ScrapedShelfItem {
        let id: Int
        let title: String?
        let author: String?
        let coverURL: String?
        let state: String?
    }

    private static func normalizeLibraryState(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        switch raw.lowercased() {
        case "reading": return "Reading"
        case "read": return "Read"
        case "wish", "wishlist": return "Wish"
        case "none": return "None"
        default:
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }

    private func extractShelfItems(from html: String) -> [ScrapedShelfItem] {
        var items: [ScrapedShelfItem] = []
        var seen = Set<Int>()

        let idPattern = #"id="work-(\d+)""#
        guard let idRegex = try? NSRegularExpression(pattern: idPattern) else { return [] }
        let full = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in idRegex.matches(in: html, range: full) {
            guard let idRange = Range(match.range(at: 1), in: html),
                  let id = Int(html[idRange]),
                  seen.insert(id).inserted else { continue }

            // Window around the card for title/author/cover/state
            let matchStart = match.range.location
            let startIdx = html.index(html.startIndex, offsetBy: max(0, matchStart - 20))
            let endOffset = min(html.count, matchStart + 1800)
            let endIdx = html.index(html.startIndex, offsetBy: endOffset)
            let chunk = String(html[startIdx..<endIdx])

            let title = firstMatch(#"bookcard-title"[^>]*>\s*<a[^>]*>(.*?)</a>"#, in: chunk)
                .map { HTMLText.plain(from: $0) }
            let author = firstMatch(#"bookcard-authors"[^>]*>(.*?)</h5>"#, in: chunk)
                .map { HTMLText.plain(from: $0) }
            let state = firstMatch(#""state"\s*:\s*"([^"]+)""#, in: chunk)
            let cover = firstMatch(#"(?:data-src|src)="(https://cm\.author\.today[^"]+)""#, in: chunk)
                ?? firstMatch(#"(?:data-src|src)="(https://[^"]+/content/[^"]+)""#, in: chunk)

            items.append(
                ScrapedShelfItem(id: id, title: title, author: author, coverURL: cover, state: state)
            )
        }

        if !items.isEmpty { return items }

        for id in extractWorkIDs(from: html) where seen.insert(id).inserted {
            items.append(ScrapedShelfItem(id: id, title: nil, author: nil, coverURL: nil, state: "Reading"))
        }
        return items
    }

    private func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    func feedItems(limit: Int = 50) async throws -> [NotificationItem] {
        try? await establishWebSession()

        // Prefer official notifications — they contain readable text when authenticated.
        if let apiItems = try? await notifications(take: limit) {
            let cleaned = apiItems
                .map { item in
                    NotificationItem(
                        id: item.id,
                        text: item.displayText,
                        title: item.title,
                        message: item.message.map { HTMLText.plain(from: $0) },
                        content: item.content,
                        body: item.body,
                        html: item.html,
                        creationTime: item.creationTime,
                        isRead: item.isRead,
                        workId: item.resolvedWorkId,
                        workID: nil,
                        url: item.url ?? item.link,
                        link: item.link,
                        category: item.category
                    )
                }
                .filter { !$0.isJunk }
            if !cleaned.isEmpty { return Array(cleaned.prefix(limit)) }
        }

        // Fallback: desktop feed HTML (mobile returns Framework7 filter chrome).
        let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/feed") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        if token != "guest" {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        guard let html = String(data: data, encoding: .utf8) else { return [] }
        // Unauthenticated feed is a login page — don't scrape junk.
        if html.localizedCaseInsensitiveContains("id=\"loginForm\"")
            || html.localizedCaseInsensitiveContains("Размер, тыс. зн") {
            return []
        }
        return parseFeedHTML(html, limit: limit).filter { !$0.isJunk }
    }

    private func extractWorkIDs(from html: String) -> [Int] {
        let pattern = #"/work/(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var ordered: [Int] = []
        var seen = Set<Int>()
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: html),
                  let id = Int(html[idRange]),
                  seen.insert(id).inserted else { continue }
            ordered.append(id)
        }
        return ordered
    }

    private func parseFeedHTML(_ html: String, limit: Int) -> [NotificationItem] {
        // Prefer structured feed rows if present
        let rowPattern = #"(?is)<(?:div|li|article)[^>]*(?:feed|activity|notification)[^>]*>(.*?)</(?:div|li|article)>"#
        if let regex = try? NSRegularExpression(pattern: rowPattern) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            var items: [NotificationItem] = []
            for (idx, match) in regex.matches(in: html, range: range).prefix(limit).enumerated() {
                guard let r = Range(match.range(at: 1), in: html) else { continue }
                let chunk = String(html[r])
                let text = HTMLText.plain(from: chunk)
                guard text.count >= 8 else { continue }
                let workId = extractWorkIDs(from: chunk).first
                let item = NotificationItem(
                    id: (workId ?? idx) + idx * 1_000_000,
                    text: text,
                    title: "Лента",
                    message: text,
                    content: nil,
                    body: nil,
                    html: nil,
                    creationTime: nil,
                    isRead: false,
                    workId: workId,
                    workID: nil,
                    url: workId.map { "https://author.today/work/\($0)" },
                    link: nil,
                    category: "feed"
                )
                if !item.isJunk { items.append(item) }
            }
            if !items.isEmpty { return items }
        }

        let ids = extractWorkIDs(from: html).filter { id in
            // Ignore catalog/genre links that are not real works in feed context
            true
        }
        var items: [NotificationItem] = []
        for (idx, id) in ids.prefix(limit).enumerated() {
            let marker = "/work/\(id)"
            var snippet = "Обновление произведения"
            if let range = html.range(of: marker) {
                let start = html.index(range.lowerBound, offsetBy: -200, limitedBy: html.startIndex) ?? html.startIndex
                let end = html.index(range.upperBound, offsetBy: 240, limitedBy: html.endIndex) ?? html.endIndex
                snippet = HTMLText.plain(from: String(html[start..<end]))
                if snippet.count > 180 {
                    snippet = String(snippet.prefix(180)) + "…"
                }
                if snippet.count < 8 {
                    snippet = "Обновление в ленте"
                }
            }
            let item = NotificationItem(
                id: id + idx * 1_000_000,
                text: snippet,
                title: "Лента",
                message: snippet,
                content: nil,
                body: nil,
                html: nil,
                creationTime: nil,
                isRead: true,
                workId: id,
                workID: nil,
                url: "https://author.today/work/\(id)",
                link: nil,
                category: "feed"
            )
            if !item.isJunk { items.append(item) }
        }
        return items
    }

    func workDetails(id: Int) async throws -> WorkDetails {
        try await get(path: "/v1/work/\(id)/details", query: [
            "recommendationsCount": "0"
        ])
    }

    func workMeta(id: Int) async throws -> WorkMeta {
        let list = try await workMetas(ids: [id])
        guard let first = list.first else {
            throw APIError.message("Произведение не найдено")
        }
        return first
    }

    func workMetas(ids: [Int]) async throws -> [WorkMeta] {
        guard !ids.isEmpty else { return [] }
        // Keep stable query order (Dictionary would shuffle ids[i]).
        var items: [URLQueryItem] = []
        for (i, id) in ids.enumerated() {
            items.append(URLQueryItem(name: "ids[\(i)]", value: "\(id)"))
        }
        let trimmed = "v1/work/meta-info"
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: "\(base)/\(trimmed)") else {
            throw APIError.invalidURL
        }
        components.queryItems = items
        guard let url = components.url else { throw APIError.invalidURL }
        let (data, _) = try await rawGet(absoluteURL: url, query: [:])
        if let envelopes = try? decoder.decode([WorkMetaEnvelope].self, from: data) {
            return envelopes.compactMap(\.data).map { normalize($0) }
        }
        // Per-item recovery if one envelope fails the whole array decode
        if let rawArr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            var recovered: [WorkMeta] = []
            for obj in rawArr {
                guard let piece = try? JSONSerialization.data(withJSONObject: obj),
                      let env = try? decoder.decode(WorkMetaEnvelope.self, from: piece),
                      let meta = env.data else { continue }
                recovered.append(normalize(meta))
            }
            if !recovered.isEmpty { return recovered }
        }
        return try decodeWorkList(from: data)
    }

    /// Platform search: HTML search page → work ids → meta-info (catalog has no title query).
    func search(query: String, page: Int = 1) async throws -> [WorkMeta] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1) Prefer site search (titles + authors)
        if let ids = try? await searchWorkIDsFromSite(query: trimmed), !ids.isEmpty {
            return try await workMetas(ids: Array(ids.prefix(40)))
        }

        // 2) Fallback: catalog by tag
        let tagged: CatalogSearchResult = try await get(path: "/v1/catalog/search", query: [
            "page": "\(page)",
            "ps": "40",
            "sorting": "popular",
            "tag": trimmed
        ])
        return tagged.items.map { normalize($0) }
    }

    func catalogRecent(page: Int = 1) async throws -> [WorkMeta] {
        let result: CatalogSearchResult = try await get(path: "/v1/catalog/search", query: [
            "page": "\(page)",
            "ps": "40",
            "sorting": "recent",
            "genre": "all"
        ])
        let items = result.items.map { normalize($0) }
        let ids = items.map(\.id)
        if ids.isEmpty { return items }
        // meta-info has price / purchase / library state
        if let enriched = try? await workMetas(ids: ids), !enriched.isEmpty {
            return enriched
        }
        return items
    }

    private func searchWorkIDsFromSite(query: String) async throws -> [Int] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://author.today/search?q=\(encoded)") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 AuthorTodayReader",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        if token != "guest" {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        let pattern = #"/work/(\d+)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var ordered: [Int] = []
        var seen = Set<Int>()
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges > 1,
                  let idRange = Range(match.range(at: 1), in: html),
                  let id = Int(html[idRange]),
                  !seen.contains(id) else { continue }
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }

    private func decodeWorkList(from data: Data) throws -> [WorkMeta] {
        if let page = try? decoder.decode(LibraryPage.self, from: data), !page.items.isEmpty {
            return page.items.map { normalize($0) }
        }
        if let arr = try? decoder.decode([WorkMeta].self, from: data) {
            return arr.map { normalize($0) }
        }
        if let envelopes = try? decoder.decode([WorkMetaEnvelope].self, from: data) {
            return envelopes.compactMap(\.data).map { normalize($0) }
        }
        if let catalog = try? decoder.decode(CatalogSearchResult.self, from: data) {
            return catalog.items.map { normalize($0) }
        }
        // Empty library is a valid empty array
        if let page = try? decoder.decode(LibraryPage.self, from: data) {
            return page.items
        }
        throw APIError.message("Не удалось разобрать список книг")
    }

    private func normalize(_ work: WorkMeta) -> WorkMeta {
        WorkMeta(
            id: work.id,
            title: work.title,
            authorFIO: work.authorFIO,
            authorUserName: work.authorUserName,
            coverUrl: WorkMeta.normalizeCover(work.coverUrl),
            annotation: work.annotation,
            lastChapterId: work.lastChapterId,
            lastChapterTitle: work.lastChapterTitle,
            lastUpdateTime: work.lastUpdateTime,
            status: work.status,
            genreName: work.genreName,
            secondGenreName: work.secondGenreName,
            likeCount: work.likeCount,
            viewsCount: work.viewsCount ?? work.viewCount,
            viewCount: work.viewCount ?? work.viewsCount,
            chapterCount: work.chapterCount,
            libraryState: work.resolvedLibraryState,
            workInLibraryState: work.workInLibraryState,
            inLibraryState: work.inLibraryState,
            progress: work.resolvedProgress,
            // Never fall back to lastChapterId — that is the latest published chapter, not last read
            lastReadChapterId: work.lastReadChapterId,
            lastChapterProgress: work.lastChapterProgress,
            price: work.price,
            discount: work.discount,
            isPurchased: work.isPurchased,
            seriesId: work.seriesId,
            seriesTitle: work.seriesTitle,
            seriesOrder: work.seriesOrder
        )
    }

    // MARK: - Chapters

    /// Fetches chapter text via the web reader (Reader-Secret header).
    /// The `/v1/.../text` JSON `key` does **not** decrypt with the public XOR scheme — do not use it.
    func chapterText(workId: Int, chapterId: Int) async throws -> (title: String?, html: String) {
        var errors: [String] = []
        try? await establishWebSession()

        // 1) Web reader — only proven source of Reader-Secret
        do {
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
            if let result = try decryptChapterPayload(data: data, headers: headers, preferHeaderSecret: true) {
                return result
            }
            errors.append("web: текст не расшифрован (нет Reader-Secret?)")
        } catch {
            errors.append("web: \(error.localizedDescription)")
        }

        // 2) Official API — only if response includes Reader-Secret header (rare)
        do {
            let (data, headers) = try await rawGet(
                path: "/v1/work/\(workId)/chapter/\(chapterId)/text"
            )
            if let result = try decryptChapterPayload(data: data, headers: headers, preferHeaderSecret: true) {
                return result
            }
            errors.append("api: нет Reader-Secret / неверный ключ")
        } catch {
            errors.append("api: \(error.localizedDescription)")
        }

        throw APIError.message("Не удалось расшифровать главу (\(errors.joined(separator: "; ")))")
    }

    private func decryptChapterPayload(
        data: Data,
        headers: [String: String],
        preferHeaderSecret: Bool
    ) throws -> (title: String?, html: String)? {
        _ = preferHeaderSecret
        let payload = try decodeFlexible(ChapterTextPayload.self, from: data)
        guard let encrypted = payload.resolvedText, !encrypted.isEmpty else {
            throw APIError.emptyBody
        }

        if ChapterDecryptor.looksLikePlaintext(encrypted) {
            return (payload.resolvedTitle, encrypted)
        }

        let headerSecret =
            headers["Reader-Secret"]
            ?? headers["reader-secret"]
            ?? headers.first(where: { $0.key.lowercased() == "reader-secret" })?.value

        // Only the web Reader-Secret works with the public XOR scheme.
        guard let headerSecret, !headerSecret.isEmpty else { return nil }

        let html = ChapterDecryptor.decrypt(encrypted, readerSecret: headerSecret, userId: userId)
        if ChapterDecryptor.looksLikePlaintext(html) {
            return (payload.resolvedTitle, html)
        }
        return nil
    }

    func manyChapterTexts(workId: Int, chapterIds: [Int] = []) async throws -> [(id: Int, title: String?, html: String)] {
        // Prefer per-chapter web reader decrypt — batch API key is unreliable.
        var result: [(id: Int, title: String?, html: String)] = []
        let ids: [Int]
        if chapterIds.isEmpty {
            let details = try await workDetails(id: workId)
            ids = details.availableChapters.map(\.id)
        } else {
            ids = chapterIds
        }
        for id in ids {
            let (title, html) = try await chapterText(workId: workId, chapterId: id)
            result.append((id, title, html))
        }
        return result
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

    /// Adds/updates a work in the site library (Reading / Read / Wish / None…).
    func updateLibrary(workIds: [Int], state: String) async throws {
        try? await establishWebSession()
        let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/work/updateLibrary") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request, authed: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        let body: [String: Any] = ["ids": workIds, "state": state]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let message = (try? decoder.decode(APIErrorBody.self, from: data))?.message
            throw APIError.http(http.statusCode, message)
        }
    }

    func addToLibrary(workId: Int, state: String = "Reading") async throws {
        try await updateLibrary(workIds: [workId], state: state)
    }

    // MARK: - Notifications

    func checkNotifications() async throws -> NotificationCheck {
        try await get(path: "/v1/notification/check")
    }

    func notifications(take: Int = 30, category: String? = nil) async throws -> [NotificationItem] {
        var q: [String: String] = ["take": "\(take)"]
        if let category { q["category"] = category }
        let (data, _) = try await rawGet(path: "/v1/notification/get", query: q)
        if let list = try? decodeFlexible(NotificationList.self, from: data), !list.all.isEmpty {
            return list.all
        }
        if let arr = try? decoder.decode([NotificationItem].self, from: data), !arr.isEmpty {
            return arr
        }
        if let wrapped = try? decoder.decode(Wrapper<[NotificationItem]>.self, from: data), !wrapped.data.isEmpty {
            return wrapped.data
        }
        return []
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
