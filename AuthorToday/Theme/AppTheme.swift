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
        lock.lock()
        let mem = memory[key]
        lock.unlock()
        if let mem { return mem }
        let file = folder.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: file), let img = UIImage(data: data) else { return nil }
        lock.lock()
        memory[key] = img
        lock.unlock()
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
            lock.lock()
            memory[key] = img
            lock.unlock()
            return img
        } catch {
            return nil
        }
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
}
