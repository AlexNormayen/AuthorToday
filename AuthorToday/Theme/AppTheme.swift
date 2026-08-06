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

    private var resolvedURL: URL? {
        guard let normalized = WorkMeta.normalizeCover(urlString) else { return nil }
        return URL(string: normalized)
    }

    var body: some View {
        Group {
            if let url = resolvedURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            AppTheme.mist
            Image(systemName: "book.closed.fill")
                .foregroundStyle(AppTheme.moss.opacity(0.55))
        }
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
