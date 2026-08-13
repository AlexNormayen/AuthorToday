import SwiftUI
import UIKit

enum AppTheme {
    static let ink = Color(red: 0.10, green: 0.14, blue: 0.16)
    static let moss = Color(red: 0.18, green: 0.42, blue: 0.36)
    static let mossSoft = Color(red: 0.22, green: 0.50, blue: 0.43)
    static let mist = Color(red: 0.93, green: 0.94, blue: 0.93)
    static let card = Color(red: 0.98, green: 0.98, blue: 0.97)
    static let danger = Color(red: 0.75, green: 0.25, blue: 0.22)

    static let titleFont = Font.system(.largeTitle, design: .serif).weight(.semibold)
    static let headlineFont = Font.system(.title3, design: .serif).weight(.semibold)
    static let bodyFont = Font.system(.body, design: .default)
}

struct CoverImage: View {
    let urlString: String?
    var corner: CGFloat = 8

    @State private var image: UIImage?
    @State private var failed = false

    private var resolvedURL: URL? {
        guard let normalized = WorkMeta.normalizeCover(urlString) else { return nil }
        return URL(string: normalized)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed || resolvedURL == nil {
                placeholder
            } else {
                ZStack {
                    placeholder
                    ProgressView()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: urlString) {
            await load()
        }
    }

    private var placeholder: some View {
        ZStack {
            AppTheme.mist
            Image(systemName: "book.closed.fill")
                .foregroundStyle(AppTheme.moss.opacity(0.55))
        }
    }

    private func load() async {
        image = nil
        failed = false
        guard let url = resolvedURL else {
            failed = true
            return
        }
        if let cached = CoverCache.shared.image(for: url) {
            image = cached
            return
        }
        if let downloaded = await CoverCache.shared.fetch(url: url) {
            image = downloaded
        } else {
            failed = true
        }
    }
}

/// Folder icon for an author: collage of up to 4 book covers.
struct AuthorCoverCollage: View {
    let coverURLs: [String?]
    var size: CGFloat = 56
    var corner: CGFloat = 10

    private var urls: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in coverURLs {
            guard let normalized = WorkMeta.normalizeCover(raw), !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
            if result.count == 4 { break }
        }
        return result
    }

    var body: some View {
        Group {
            switch urls.count {
            case 0:
                placeholder
            case 1:
                tile(urls[0])
            case 2:
                HStack(spacing: gap) {
                    tile(urls[0])
                    tile(urls[1])
                }
            case 3:
                HStack(spacing: gap) {
                    tile(urls[0])
                    VStack(spacing: gap) {
                        tile(urls[1])
                        tile(urls[2])
                    }
                }
            default:
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        tile(urls[0])
                        tile(urls[1])
                    }
                    HStack(spacing: gap) {
                        tile(urls[2])
                        tile(urls[3])
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .background(AppTheme.mist)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var gap: CGFloat { 1.5 }

    private func tile(_ url: String) -> some View {
        CoverImage(urlString: url, corner: 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
    }

    private var placeholder: some View {
        ZStack {
            AppTheme.mist
            Image(systemName: "person.crop.rectangle.stack")
                .font(.system(size: size * 0.36))
                .foregroundStyle(AppTheme.moss.opacity(0.7))
        }
    }
}

/// Disk + memory cache for cover art so the library does not re-download on every launch.
final class CoverCache: @unchecked Sendable {
    static let shared = CoverCache()

    private let lock = NSLock()
    private var memory: [String: UIImage] = [:]
    private let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("CoverCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func image(for url: URL) -> UIImage? {
        let key = cacheKey(for: url)
        if let mem = memoryImage(forKey: key) { return mem }
        let file = folder.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: file), let img = UIImage(data: data) else { return nil }
        storeMemoryImage(img, forKey: key)
        return img
    }

    func fetch(url: URL) async -> UIImage? {
        if let cached = image(for: url) { return cached }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let img = UIImage(data: data) else { return nil }
            let key = cacheKey(for: url)
            let file = folder.appendingPathComponent(key)
            try? data.write(to: file, options: .atomic)
            storeMemoryImage(img, forKey: key)
            return img
        } catch {
            return nil
        }
    }

    private func memoryImage(forKey key: String) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return memory[key]
    }

    private func storeMemoryImage(_ image: UIImage, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        memory[key] = image
    }

    private func cacheKey(for url: URL) -> String {
        let raw = url.absoluteString
        let digest = raw.data(using: .utf8)?.base64EncodedString() ?? raw
        let safe = digest
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return String(safe.prefix(120)) + ".img"
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Strips basic HTML to plain text / attributed for the reader.
enum HTMLText {
    static func plain(from html: String) -> String {
        var s = html
        for pattern in [#"(?is)<script[^>]*>.*?</script>"#, #"(?is)<style[^>]*>.*?</style>"#] {
            s = s.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        let replacements: [(String, String)] = [
            ("<br>", "\n"), ("<br/>", "\n"), ("<br />", "\n"),
            ("</p>", "\n\n"), ("</div>", "\n"), ("</li>", "\n"),
            ("&nbsp;", " "), ("&#160;", " "), ("&#xa0;", " "), ("&#xA0;", " "),
            ("&amp;", "&"), ("&lt;", "<"),
            ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&laquo;", "«"), ("&raquo;", "»"), ("&mdash;", "—"), ("&ndash;", "–")
        ]
        for (a, b) in replacements {
            s = s.replacingOccurrences(of: a, with: b, options: .caseInsensitive)
        }
        // Numeric entities &#1234; and &#x1F4A;
        while let match = s.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let token = String(s[match])
            let digits = token
                .replacingOccurrences(of: "&#", with: "")
                .replacingOccurrences(of: ";", with: "")
            if let value = UInt32(digits), let scalar = UnicodeScalar(value) {
                s.replaceSubrange(match, with: String(Character(scalar)))
            } else {
                break
            }
        }
        while let match = s.range(of: #"&#x([0-9a-fA-F]+);"#, options: .regularExpression) {
            let token = String(s[match])
            let hex = token
                .replacingOccurrences(of: "&#x", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: ";", with: "")
            if let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) {
                s.replaceSubrange(match, with: String(Character(scalar)))
            } else {
                break
            }
        }
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return s
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reader text with first-line paragraph indent (as in paper books).
    static func readerPlain(from html: String) -> String {
        let indent = "\u{2003}\u{2003}" // two em-spaces
        let plain = plain(from: html)
        let paragraphs = plain.components(separatedBy: "\n\n")
        return paragraphs
            .map { raw -> String in
                let para = raw
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !para.isEmpty else { return "" }
                if para.hasPrefix(indent) { return para }
                return indent + para
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// Chapter body for the reader with the author's chapter title at the top.
    static func readerPlain(title: String?, html: String) -> String {
        withChapterHeading(title, body: readerPlain(from: html))
    }

    /// Prepends the chapter name unless the body already starts with it.
    static func withChapterHeading(_ title: String?, body: String) -> String {
        let heading = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !heading.isEmpty else { return body }
        var start = body.trimmingCharacters(in: .whitespacesAndNewlines)
        while start.hasPrefix("\u{2003}") || start.hasPrefix(" ") || start.hasPrefix("\t") {
            start.removeFirst()
        }
        if start.localizedCaseInsensitiveCompare(heading) == .orderedSame
            || start.lowercased().hasPrefix(heading.lowercased()) {
            return body
        }
        if body.isEmpty { return heading }
        return heading + "\n\n" + body
    }

    /// Bold chapter title on the first page of paged reading mode.
    static func attributedReaderPage(
        _ page: String,
        chapterHeading: String,
        isFirstPage: Bool,
        size: CGFloat,
        family: ReaderFontFamily? = nil
    ) -> AttributedString {
        var attr = AttributedString(page)
        let heading = chapterHeading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isFirstPage, !heading.isEmpty, page.hasPrefix(heading),
              let range = attr.range(of: heading) else {
            return attr
        }
        if let family {
            attr[range].font = family.font(size: size).bold()
        } else {
            attr[range].font = .system(size: size, weight: .bold)
        }
        return attr
    }

    /// Post body with tappable links (Markdown → AttributedString).
    static func attributedPostBody(from html: String) -> AttributedString {
        var s = html
        for pattern in [#"(?is)<script[^>]*>.*?</script>"#, #"(?is)<style[^>]*>.*?</style>"#, #"(?is)<iframe[\s\S]*?</iframe>"#] {
            s = s.replacingOccurrences(of: pattern, with: "\n", options: .regularExpression)
        }
        // <a href="url">label</a> → [label](url)
        if let regex = try? NSRegularExpression(
            pattern: #"(?is)<a[^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>"#,
            options: []
        ) {
            let ns = s as NSString
            let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
            for match in matches {
                guard match.numberOfRanges >= 3,
                      let hrefRange = Range(match.range(at: 1), in: s),
                      let labelRange = Range(match.range(at: 2), in: s),
                      let full = Range(match.range(at: 0), in: s) else { continue }
                let href = MediaURL.normalize(String(s[hrefRange]))
                var label = plain(from: String(s[labelRange]))
                    .replacingOccurrences(of: "[", with: "(")
                    .replacingOccurrences(of: "]", with: ")")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if label.isEmpty { label = href }
                let md = "[\(label)](\(href))"
                s.replaceSubrange(full, with: md)
            }
        }
        s = s
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Autolink bare video / http URLs that are not already markdown links.
        s = autolinkBareURLs(in: s)

        if let attributed = try? AttributedString(
            markdown: s,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(plain(from: html))
    }

    private static func autolinkBareURLs(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(https?://[^\s<>\[\]\(\)]+|www\.[^\s<>\[\]\(\)]+)"#
        ) else { return text }
        var result = text
        let ns = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            let prefix = String(result[..<range.lowerBound])
            // Skip URLs already inside markdown: [label](url) or [url](...)
            if prefix.hasSuffix("](") || prefix.hasSuffix("[") { continue }

            let original = String(result[range])
            var cleaned = original
            var suffix = ""
            while let last = cleaned.last, ".,;:!?)]»\"".contains(last) {
                suffix = String(last) + suffix
                cleaned.removeLast()
            }
            guard !cleaned.isEmpty else { continue }
            if cleaned.hasPrefix("www.") {
                cleaned = "https://" + cleaned
            }
            result.replaceSubrange(range, with: "[\(cleaned)](\(cleaned))" + suffix)
        }
        return result
    }
}

enum MediaURL {
    static func normalize(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("//") { value = "https:" + value }
        if value.hasPrefix("/") { value = "https://author.today" + value }
        if value.hasPrefix("www.") { value = "https://" + value }
        return value
    }

    static func isVideo(_ url: URL) -> Bool {
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        let abs = url.absoluteString.lowercased()
        if host.contains("youtube") || host.contains("youtu.be") { return true }
        if host.contains("vimeo.com") { return true }
        if host.contains("rutube.ru") { return true }
        if host.contains("vk.com") || host.contains("vkvideo") {
            return path.contains("video") || abs.contains("video")
        }
        if host.contains("dailymotion") { return true }
        if ["mp4", "m3u8", "webm", "mov"].contains(url.pathExtension.lowercased()) { return true }
        return abs.contains("/embed/")
    }

    /// Prefer an embeddable player URL for in-app WKWebView.
    static func embedURL(for url: URL) -> URL {
        let abs = url.absoluteString
        let host = (url.host ?? "").lowercased()

        if host.contains("youtu.be") {
            let id = url.path.split(separator: "/").first.map(String.init) ?? ""
            if !id.isEmpty, let embed = URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1") {
                return embed
            }
        }
        if host.contains("youtube.com") {
            if abs.contains("/embed/") {
                return url
            }
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let id = comps.queryItems?.first(where: { $0.name == "v" })?.value,
               let embed = URL(string: "https://www.youtube.com/embed/\(id)?playsinline=1") {
                return embed
            }
            // /shorts/ID
            let parts = url.path.split(separator: "/")
            if parts.count >= 2, parts[0] == "shorts",
               let embed = URL(string: "https://www.youtube.com/embed/\(parts[1])?playsinline=1") {
                return embed
            }
        }
        if host.contains("vimeo.com"), !host.contains("player.") {
            let id = url.path.split(separator: "/").first(where: { Int($0) != nil }).map(String.init)
            if let id, let embed = URL(string: "https://player.vimeo.com/video/\(id)") {
                return embed
            }
        }
        if host.contains("rutube.ru"), abs.contains("/video/") {
            let id = url.path.split(separator: "/").last.map(String.init) ?? ""
            if !id.isEmpty, let embed = URL(string: "https://rutube.ru/play/embed/\(id)") {
                return embed
            }
        }
        return url
    }
}
