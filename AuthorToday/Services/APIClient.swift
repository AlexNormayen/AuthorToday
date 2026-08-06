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
        try await userLibraryPage(page: page, pageSize: pageSize).items
    }

    /// One page of `/v1/account/user-library` with totalCount (no inner retry — caller paces 429s).
    func userLibraryPage(page: Int = 1, pageSize: Int = 100) async throws -> UserLibraryPageResult {
        let (data, _) = try await rawGet(path: "/v1/account/user-library", query: [
            "page": "\(page)",
            "pageSize": "\(pageSize)"
        ])
        if let pagePayload = try? decoder.decode(LibraryPage.self, from: data) {
            let items = pagePayload.items.map { normalize($0) }
            let total = pagePayload.realTotalCount ?? pagePayload.totalCount
            let last = pagePayload.isLastPage
                ?? (pagePayload.hasMore.map { !$0 })
                ?? (items.isEmpty || items.count < pageSize)
            return UserLibraryPageResult(items: items, totalCount: total, isLastPage: last)
        }
        let items = try decodeWorkList(from: data)
        return UserLibraryPageResult(
            items: items,
            totalCount: nil,
            isLastPage: items.isEmpty || items.count < pageSize
        )
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

    func feedPage(take: Int = 20, lastItemCreationTime: String? = nil) async throws -> (items: [NotificationItem], more: Bool, cursor: String?) {
        try? await establishWebSession()
        var q: [String: String] = ["take": "\(take)"]
        if let lastItemCreationTime, !lastItemCreationTime.isEmpty {
            q["lastItemCreationTime"] = lastItemCreationTime
        }
        let (data, _) = try await rawGet(path: "/v1/notification/get", query: q)

        if let page = try? decodeFlexible(FeedPage.self, from: data) {
            let mapped = (page.items ?? []).map { $0.asNotificationItem() }.filter { !$0.isJunk }
            return (mapped, page.more ?? false, page.lastItemCreationTime)
        }

        // Legacy shapes
        if let list = try? decodeFlexible(NotificationList.self, from: data), !list.all.isEmpty {
            return (list.all.filter { !$0.isJunk }, false, nil)
        }
        return ([], false, nil)
    }

    func feedItems(limit: Int = 20) async throws -> [NotificationItem] {
        let page = try await feedPage(take: limit, lastItemCreationTime: nil)
        if !page.items.isEmpty { return page.items }

        // Fallback: desktop feed HTML
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
                    category: "feed",
                    notificationId: nil,
                    feedType: nil,
                    postId: nil,
                    authorName: nil,
                    authorUserName: nil,
                    coverURL: nil
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
                category: "feed",
                notificationId: nil,
                feedType: nil,
                postId: nil,
                authorName: nil,
                authorUserName: nil,
                coverURL: nil
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

    /// Platform search: authors first, then works.
    func search(query: String, page: Int = 1) async throws -> CatalogSearchBundle {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return CatalogSearchBundle(authors: [], works: []) }

        if let site = try? await searchSiteBundle(query: trimmed), !site.workIDs.isEmpty || !site.authors.isEmpty {
            let works: [WorkMeta]
            if site.workIDs.isEmpty {
                works = []
            } else {
                works = try await workMetas(ids: Array(site.workIDs.prefix(40)))
            }
            return CatalogSearchBundle(authors: site.authors, works: works)
        }

        // Fallback: catalog by tag (works only)
        let tagged: CatalogSearchResult = try await get(path: "/v1/catalog/search", query: [
            "page": "\(page)",
            "ps": "40",
            "sorting": "popular",
            "tag": trimmed
        ])
        return CatalogSearchBundle(authors: [], works: tagged.items.map { normalize($0) })
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
        if let enriched = try? await workMetas(ids: ids), !enriched.isEmpty {
            return enriched
        }
        return items
    }

    private struct SiteSearchParse {
        var authors: [AuthorSearchHit]
        var workIDs: [Int]
    }

    private func searchSiteBundle(query: String) async throws -> SiteSearchParse {
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
        guard let html = String(data: data, encoding: .utf8) else {
            return SiteSearchParse(authors: [], workIDs: [])
        }
        return SiteSearchParse(
            authors: Self.parseSearchAuthors(from: html),
            workIDs: Self.parseSearchWorkIDs(from: html)
        )
    }

    private static func parseSearchAuthors(from html: String) -> [AuthorSearchHit] {
        // Prefer the «Авторы» block when present; otherwise collect /u/ links that appear before works.
        let authorsSection: String
        if let range = html.range(of: #"Авторы"#, options: [.caseInsensitive]) {
            let after = html[range.lowerBound...]
            if let works = after.range(of: #"Произведения"#, options: [.caseInsensitive]) {
                authorsSection = String(after[..<works.lowerBound])
            } else {
                authorsSection = String(after.prefix(12_000))
            }
        } else {
            authorsSection = String(html.prefix(20_000))
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)<a[^>]+href=["']/u/([^"'/]+)["'][^>]*>(.*?)</a>"#
        ) else { return [] }

        let ns = authorsSection as NSString
        var ordered: [AuthorSearchHit] = []
        var seen = Set<String>()
        for match in regex.matches(in: authorsSection, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges >= 3,
                  let uRange = Range(match.range(at: 1), in: authorsSection),
                  let nRange = Range(match.range(at: 2), in: authorsSection) else { continue }
            let user = String(authorsSection[uRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !user.isEmpty, seen.insert(user).inserted else { continue }
            var name = HTMLText.plain(from: String(authorsSection[nRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { name = user }
            if name.count > 80 { continue }
            // Skip pure icon/empty chrome links
            if name == user, user.count < 2 { continue }
            ordered.append(AuthorSearchHit(userName: user, displayName: name))
            if ordered.count >= 20 { break }
        }
        return ordered
    }

    private static func parseSearchWorkIDs(from html: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #"/work/(\d+)"#) else { return [] }
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

    // MARK: - Comments (site web API)

    /// Work comments: rootType = 1. Blog posts: rootType = 2.
    func loadWorkComments(workId: Int, page: Int = 1, sorting: String = "reverse") async throws -> CommentLoadPage {
        try await loadComments(rootId: workId, rootType: 1, pagePath: "/work/\(workId)", page: page, sorting: sorting)
    }

    func loadPostComments(postId: Int, page: Int = 1, sorting: String = "reverse") async throws -> CommentLoadPage {
        try await loadComments(rootId: postId, rootType: 2, pagePath: "/post/\(postId)", page: page, sorting: sorting)
    }

    func loadComments(
        rootId: Int,
        rootType: Int,
        pagePath: String,
        page: Int = 1,
        sorting: String = "reverse"
    ) async throws -> CommentLoadPage {
        try? await establishWebSession()
        _ = try? await fetchWebHTML(path: pagePath)
        let (data, _) = try await webJSONGet(path: "/comment/load", query: [
            "rootId": "\(rootId)",
            "rootType": "\(rootType)",
            "c": "",
            "th": "",
            "page": page <= 1 ? "" : "\(page)",
            "sorting": sorting,
            "_": "\(Int(Date().timeIntervalSince1970 * 1000))"
        ])
        struct Envelope: Decodable {
            let isSuccessful: Bool?
            let messages: [String]?
            let data: Payload?
            struct Payload: Decodable { let html: String? }
        }
        let env = try decoder.decode(Envelope.self, from: data)
        guard env.isSuccessful != false, let html = env.data?.html else {
            throw APIError.message(env.messages?.first ?? "Не удалось загрузить комментарии")
        }
        let comments = Self.parseCommentsHTML(html)
        let hasMore = html.contains("rel=\"next\"") && !html.contains("next disabled")
        let nextPage = hasMore ? page + 1 : nil
        return CommentLoadPage(comments: comments, hasMore: hasMore, nextPage: nextPage)
    }

    func submitWorkComment(
        workId: Int,
        text: String,
        parentId: Int? = nil,
        threadId: Int? = nil,
        level: Int = 0
    ) async throws {
        try await submitComment(
            rootId: workId,
            rootType: 1,
            pagePath: "/work/\(workId)",
            text: text,
            parentId: parentId,
            threadId: threadId,
            level: level
        )
    }

    func submitPostComment(
        postId: Int,
        text: String,
        parentId: Int? = nil,
        threadId: Int? = nil,
        level: Int = 0
    ) async throws {
        try await submitComment(
            rootId: postId,
            rootType: 2,
            pagePath: "/post/\(postId)",
            text: text,
            parentId: parentId,
            threadId: threadId,
            level: level
        )
    }

    func submitComment(
        rootId: Int,
        rootType: Int,
        pagePath: String,
        text: String,
        parentId: Int? = nil,
        threadId: Int? = nil,
        level: Int = 0
    ) async throws {
        try await establishWebSession()
        let html = try await fetchWebHTML(path: pagePath)
        guard let verificationToken = Self.extractRequestVerificationToken(from: html) else {
            throw APIError.message("Не удалось получить токен для комментария")
        }

        var payload: [String: Any] = [
            "rootId": rootId,
            "rootType": rootType,
            "text": text,
            "isPinned": false
        ]
        if let parentId {
            payload["parentId"] = parentId
            payload["threadId"] = threadId ?? parentId
            payload["level"] = max(level, 1)
            payload["id"] = NSNull()
            payload["isIgnored"] = false
        }

        try await webJSONPost(
            path: "/comment/submit",
            body: payload,
            verificationToken: verificationToken,
            refererPath: pagePath
        )
    }

    // MARK: - Blog posts

    func postDetails(id: Int) async throws -> PostDetails {
        try? await establishWebSession()
        let html = try await fetchWebHTML(path: "/post/\(id)")
        return Self.parsePostHTML(id: id, html: html)
    }

    private static func parsePostHTML(id: Int, html: String) -> PostDetails {
        let title = firstMatch(#"<h1[^>]*>([\s\S]*?)</h1>"#, in: html)
            .map { HTMLText.plain(from: $0) }
            ?? firstMatch(#"<title>([^<]+)</title>"#, in: html).map { HTMLText.plain(from: $0) }
            ?? "Пост"

        let authorUser = firstMatch(#"href="/u/([^"/]+)"[^>]*>\s*(?:<[^>]+>\s*)*[^<]*"#, in: html)
            ?? firstMatch(#"href="/u/([^"/]+)""#, in: html)
        let authorName = firstMatch(#"class="[^"]*user-name[^"]*"[^>]*>([^<]+)<"#, in: html)
            ?? authorUser

        let bodyHTML = firstMatch(#"(?s)class="[^"]*fr-view[^"]*"[^>]*>([\s\S]*?)</div>\s*</div>"#, in: html)
            ?? firstMatch(#"(?s)class="[^"]*rich-content[^"]*"[^>]*>([\s\S]*?)</div>"#, in: html)
            ?? ""

        var imageURLs: [URL] = []
        var videoURLs: [URL] = []
        var linkURLs: [URL] = []
        var seenMedia = Set<String>()
        var seenLinks = Set<String>()

        for raw in matches(#"<img[^>]+src="([^"]+)""#, in: bodyHTML) {
            let normalized = MediaURL.normalize(raw)
            guard let url = URL(string: normalized), seenMedia.insert(normalized).inserted else { continue }
            if normalized.contains("emoji") || normalized.contains("smiley") { continue }
            imageURLs.append(url)
        }

        for raw in matches(#"<iframe[^>]+src="([^"]+)""#, in: bodyHTML)
            + matches(#"<video[^>]+src="([^"]+)""#, in: bodyHTML)
        {
            let normalized = MediaURL.normalize(raw)
            guard var url = URL(string: normalized), seenMedia.insert(normalized).inserted else { continue }
            if MediaURL.isVideo(url) {
                url = MediaURL.embedURL(for: url)
            }
            videoURLs.append(url)
        }

        // Anchors: collect links + promote video anchors to in-app players
        for raw in matches(#"(?is)<a[^>]+href=["']([^"']+)["']"#, in: bodyHTML) {
            let normalized = MediaURL.normalize(raw)
            guard let url = URL(string: normalized), seenLinks.insert(normalized).inserted else { continue }
            linkURLs.append(url)
            if MediaURL.isVideo(url) {
                let embed = MediaURL.embedURL(for: url)
                if seenMedia.insert(embed.absoluteString).inserted {
                    videoURLs.append(embed)
                }
            }
        }

        // Bare URLs in stripped text (authors often paste YouTube without <a>)
        let plainBody = HTMLText.plain(from: bodyHTML)
        if let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s<>\[\]\(\)]+"#) {
            let range = NSRange(plainBody.startIndex..<plainBody.endIndex, in: plainBody)
            for match in urlRegex.matches(in: plainBody, range: range) {
                guard let r = Range(match.range, in: plainBody) else { continue }
                let normalized = MediaURL.normalize(String(plainBody[r]))
                guard let url = URL(string: normalized) else { continue }
                if seenLinks.insert(normalized).inserted {
                    linkURLs.append(url)
                }
                if MediaURL.isVideo(url) {
                    let embed = MediaURL.embedURL(for: url)
                    if seenMedia.insert(embed.absoluteString).inserted {
                        videoURLs.append(embed)
                    }
                }
            }
        }

        return PostDetails(
            id: id,
            title: title,
            authorName: authorName.map { HTMLText.plain(from: $0) },
            authorUserName: authorUser,
            html: bodyHTML,
            plainText: plainBody,
            attributedBody: HTMLText.attributedPostBody(from: bodyHTML),
            imageURLs: imageURLs,
            videoEmbedURLs: videoURLs,
            linkURLs: linkURLs
        )
    }

    private static func normalizeMediaURL(_ raw: String) -> String {
        MediaURL.normalize(raw)
    }

    // MARK: - Author profile

    func authorProfile(userName: String, displayNameHint: String? = nil) async throws -> AuthorProfile {
        let user = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { throw APIError.message("Нет имени автора") }
        try? await establishWebSession()

        let encoded = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? user
        let profileHTML = (try? await fetchWebHTML(path: "/u/\(encoded)")) ?? ""
        let worksHTML = (try? await fetchWebHTML(path: "/u/\(encoded)/works")) ?? profileHTML

        let displayName = Self.firstMatch(#"class="[^"]*user-name[^"]*"[^>]*>([^<]+)<"#, in: profileHTML)
            ?? Self.firstMatch(#"<h1[^>]*>([^<]+)</h1>"#, in: profileHTML)
            ?? displayNameHint
            ?? user
        let avatar = Self.extractAuthorAvatar(from: profileHTML, userName: user)
        let about = Self.firstMatch(#"class="[^"]*about[^"]*"[^>]*>([\s\S]*?)</div>"#, in: profileHTML)
            .map { HTMLText.plain(from: $0) }

        // Collect work ids + series from works page
        var orderedIDs: [Int] = []
        var seen = Set<Int>()
        for idStr in matches(#"href="/work/(\d+)""#, in: worksHTML) {
            guard let id = Int(idStr), seen.insert(id).inserted else { continue }
            orderedIDs.append(id)
        }
        var metas: [WorkMeta] = []
        for chunkStart in stride(from: 0, to: orderedIDs.count, by: 40) {
            let end = min(chunkStart + 40, orderedIDs.count)
            let chunk = Array(orderedIDs[chunkStart..<end])
            if let items = try? await workMetas(ids: chunk) {
                let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
                for id in chunk {
                    if let m = byId[id] {
                        metas.append(m)
                    } else {
                        metas.append(WorkMeta.stub(id: id, title: nil, author: displayName, coverUrl: nil))
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let grouped = Dictionary(grouping: metas) { meta -> String in
            meta.displaySeriesTitle ?? "Без серии"
        }
        let series: [AuthorSeriesGroup] = grouped.map { title, works in
            let sid = works.compactMap(\.seriesId).first
            let sorted = works.sorted { a, b in
                let oa = a.seriesOrder ?? Int.max
                let ob = b.seriesOrder ?? Int.max
                if oa != ob { return oa < ob }
                return (a.title ?? "").localizedCaseInsensitiveCompare(b.title ?? "") == .orderedAscending
            }
            return AuthorSeriesGroup(title: title, seriesId: sid, works: sorted)
        }
        .sorted { a, b in
            if a.title == "Без серии" { return false }
            if b.title == "Без серии" { return true }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }

        return AuthorProfile(
            userName: user,
            displayName: HTMLText.plain(from: displayName),
            avatarURL: avatar,
            about: about,
            works: metas,
            series: series
        )
    }

    private static func extractAuthorAvatar(from html: String, userName: String) -> String? {
        let lower = userName.lowercased()
        // Prefer the main profile avatar block (not header/current-user chips).
        if let fromBlock = firstMatch(
            #"(?s)class="[^"]*profile-avatar[^"]*"[\s\S]{0,500}?src="(https://[^"]+)""#,
            in: html
        ) {
            return decodeHTMLEntities(fromBlock)
        }
        let all = matches(#"src="(https://cm\.author\.today/[^"]+)""#, in: html)
            .map(decodeHTMLEntities)
        if let named = all.first(where: {
            let u = $0.lowercased()
            return u.contains("/u/\(lower)") || u.contains("\(lower)_") || u.contains("/\(lower).")
        }) {
            return named
        }
        // Larger profile image often has width=500 in query.
        if let large = all.first(where: { $0.contains("width=500") || $0.contains("data-width") }) {
            return large
        }
        return nil
    }

    private static func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private func fetchWebHTML(path: String) async throws -> String {
        let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue(base + "/", forHTTPHeaderField: "Referer")
        // Prefer LoginCookie from establishWebSession; Bearer alone does not set CSRF correctly.
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func extractRequestVerificationToken(from html: String) -> String? {
        // Same as site: $("input[name='__RequestVerificationToken']").val() — first match.
        if let token = firstMatch(#"name=["']__RequestVerificationToken["'][^>]*value=["']([^"']+)["']"#, in: html) {
            return token
        }
        return firstMatch(#"value=["']([^"']+)["'][^>]*name=["']__RequestVerificationToken["']"#, in: html)
    }

    private func webJSONGet(path: String, query: [String: String]) async throws -> (Data, HTTPURLResponse) {
        let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var components = URLComponents(string: base + path)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://author.today/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        if token != "guest" {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.message("Нет ответа") }
        try validate(response: response, data: data)
        return (data, http)
    }

    private func webJSONPost(
        path: String,
        body: [String: Any],
        verificationToken: String,
        refererPath: String
    ) async throws {
        let base = webURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + path) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(verificationToken, forHTTPHeaderField: "RequestVerificationToken")
        request.setValue("https://author.today", forHTTPHeaderField: "Origin")
        request.setValue(base + refererPath, forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        // Site AjaxUtils uses cookies (LoginCookie + CSRFToken), not Bearer.
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)

        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
            throw APIError.message("Сервер вернул неожиданный ответ при отправке комментария\(snippet.isEmpty ? "" : ": \(snippet)")")
        }
        let ok = obj["isSuccessful"] as? Bool
        guard ok == true else {
            throw APIError.message(Self.messageFromAPIResult(obj) ?? "Не удалось отправить комментарий")
        }
    }

    private static func messageFromAPIResult(_ obj: [String: Any]) -> String? {
        if let messages = obj["messages"] as? [String], let first = messages.first, !first.isEmpty {
            return first
        }
        if let messages = obj["messages"] as? [[String: Any]] {
            for item in messages {
                if let text = item["message"] as? String, !text.isEmpty { return text }
                if let text = item["text"] as? String, !text.isEmpty { return text }
            }
        }
        if let message = obj["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = obj["error"] as? String, !error.isEmpty {
            return error
        }
        return nil
    }

    private static func parseCommentsHTML(_ html: String) -> [WorkComment] {
        var result: [WorkComment] = []
        guard let regex = try? NSRegularExpression(
            pattern: #"(?s)<div class=\"comment[^\"]*\"[^>]*data-id=\"(\d+)\"[^>]*data-level=\"(\d+)\"[^>]*data-thread=\"(\d+)\"[^>]*>(.*?)</div>\s*(?=<div class=\"comment|</div>\s*<div class=\"pagination|</div>\s*$)"#
        ) else {
            // Fallback: simpler per-comment blocks
            return parseCommentsHTMLSimple(html)
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, range: range)
        if matches.isEmpty {
            return parseCommentsHTMLSimple(html)
        }
        for match in matches {
            guard match.numberOfRanges >= 5,
                  let idR = Range(match.range(at: 1), in: html),
                  let levelR = Range(match.range(at: 2), in: html),
                  let threadR = Range(match.range(at: 3), in: html),
                  let bodyR = Range(match.range(at: 4), in: html),
                  let id = Int(html[idR]),
                  let level = Int(html[levelR]),
                  let thread = Int(html[threadR]) else { continue }
            let chunk = String(html[bodyR])
            result.append(commentFromChunk(id: id, level: level, threadId: thread, chunk: chunk))
        }
        return result
    }

    private static func parseCommentsHTMLSimple(_ html: String) -> [WorkComment] {
        var result: [WorkComment] = []
        guard let idRegex = try? NSRegularExpression(pattern: #"data-id=\"(\d+)\""#) else { return [] }
        let full = NSRange(html.startIndex..<html.endIndex, in: html)
        let ids = idRegex.matches(in: html, range: full).compactMap { m -> (Int, Int)? in
            guard let r = Range(m.range(at: 1), in: html), let id = Int(html[r]) else { return nil }
            return (id, m.range.location)
        }
        for (idx, item) in ids.enumerated() {
            let start = item.1
            let end = idx + 1 < ids.count ? ids[idx + 1].1 : html.count
            let startIdx = html.index(html.startIndex, offsetBy: start)
            let endIdx = html.index(html.startIndex, offsetBy: min(end, html.count))
            let chunk = String(html[startIdx..<endIdx])
            let level = Int(Self.firstMatch(#"data-level=\"(\d+)\""#, in: chunk) ?? "0") ?? 0
            let thread = Int(Self.firstMatch(#"data-thread=\"(\d+)\""#, in: chunk) ?? "\(item.0)") ?? item.0
            result.append(commentFromChunk(id: item.0, level: level, threadId: thread, chunk: chunk))
        }
        return result
    }

    private static func commentFromChunk(id: Int, level: Int, threadId: Int, chunk: String) -> WorkComment {
        let author = Self.firstMatch(#"comment-user-name\">([^<]+)<"#, in: chunk)
            ?? Self.firstMatch(#"/u/([^\"/]+)\"[^>]*>\s*<span"#, in: chunk)
            ?? "Пользователь"
        let userName = Self.firstMatch(#"href=\"/u/([^\"]+)\""#, in: chunk)
        let textHTML = Self.firstMatch(#"(?s)class=\"rich-content[^\"]*\">([\s\S]*?)</div>"#, in: chunk)
            ?? Self.firstMatch(#"(?s)<article[^>]*>([\s\S]*?)</article>"#, in: chunk)
            ?? ""
        let created = Self.firstMatch(#"data-time=\"([^\"]+)\""#, in: chunk)
        let pinned = chunk.contains("data-is-pinned=\"true\"") || chunk.contains("is-pinned")
        let isAuthor = chunk.contains(">автор<") || chunk.contains("label-primary")
        let ratingStr = Self.firstMatch(#"comment-rating-count[^>]*>\s*([+\-]?\d+)"#, in: chunk)
        return WorkComment(
            id: id,
            parentId: level > 0 ? threadId : nil,
            threadId: threadId,
            level: level,
            authorName: HTMLText.plain(from: author),
            authorUserName: userName,
            text: HTMLText.plain(from: textHTML),
            createdAt: created,
            isPinned: pinned,
            isAuthor: isAuthor,
            rating: ratingStr.flatMap(Int.init)
        )
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        Self.matches(pattern, in: text)
    }

    // MARK: - Notifications

    func checkNotifications() async throws -> NotificationCheck {
        try await get(path: "/v1/notification/check")
    }

    func notifications(take: Int = 30, category: String? = nil) async throws -> [NotificationItem] {
        _ = category
        let page = try await feedPage(take: take, lastItemCreationTime: nil)
        return page.items
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
