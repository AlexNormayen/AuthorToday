import Foundation

enum LocalBookImportError: LocalizedError {
    case unsupportedFormat
    case emptyFile
    case invalidZIP
    case unsupportedZIPCompression(Int)
    case inflateFailed
    case invalidEPUB
    case copyFailed
    case proRequired

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Поддерживаются только TXT и EPUB"
        case .emptyFile:
            return "Файл пустой"
        case .invalidZIP, .invalidEPUB:
            return "Не удалось прочитать EPUB"
        case .unsupportedZIPCompression(let m):
            return "Неподдерживаемое сжатие ZIP (\(m))"
        case .inflateFailed:
            return "Ошибка распаковки EPUB"
        case .copyFailed:
            return "Не удалось скопировать файл"
        case .proRequired:
            return "Импорт файлов доступен в Читальня Pro"
        }
    }
}

struct ImportedLocalChapter: Sendable {
    let title: String
    let htmlText: String
    let plainText: String
}

struct ImportedLocalBook: Sendable {
    let title: String
    let author: String
    let format: LocalBookFormat
    let relativePath: String
    let coverData: Data?
    let chapters: [ImportedLocalChapter]
}

enum LocalBookImporter {
    static var booksDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("LocalBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func importFile(from sourceURL: URL) throws -> ImportedLocalBook {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let ext = sourceURL.pathExtension.lowercased()
        let format: LocalBookFormat
        switch ext {
        case "txt": format = .txt
        case "epub": format = .epub
        default:
            throw LocalBookImportError.unsupportedFormat
        }

        let bookId = UUID()
        let folder = booksDirectory.appendingPathComponent(bookId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destName = "book.\(ext)"
        let destURL = folder.appendingPathComponent(destName)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw LocalBookImportError.copyFailed
        }

        let relativePath = "\(bookId.uuidString)/\(destName)"

        do {
            switch format {
            case .txt:
                let chapters = try parseTXT(url: destURL)
                let title = sourceURL.deletingPathExtension().lastPathComponent
                return ImportedLocalBook(
                    title: title.isEmpty ? "Без названия" : title,
                    author: "",
                    format: .txt,
                    relativePath: relativePath,
                    coverData: nil,
                    chapters: chapters
                )
            case .epub:
                return try parseEPUB(url: destURL, relativePath: relativePath)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    // MARK: - TXT

    static func parseTXT(url: URL) throws -> [ImportedLocalChapter] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw LocalBookImportError.emptyFile }
        let text = decodeText(data)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return splitTXTIntoChapters(text)
    }

    static func decodeText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        if let win = String(data: data, encoding: .windowsCP1251) { return win }
        return String(decoding: data, as: UTF8.self)
    }

    static func splitTXTIntoChapters(_ text: String) -> [ImportedLocalChapter] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var chapterStarts: [(index: Int, title: String)] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if let title = headingTitle(trimmed) {
                chapterStarts.append((i, title))
            }
        }

        if chapterStarts.count >= 2 {
            var chapters: [ImportedLocalChapter] = []
            for (idx, start) in chapterStarts.enumerated() {
                let endLine = idx + 1 < chapterStarts.count ? chapterStarts[idx + 1].index : lines.count
                let body = lines[start.index..<endLine].joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else { continue }
                chapters.append(ImportedLocalChapter(title: start.title, htmlText: "", plainText: body))
            }
            if !chapters.isEmpty { return chapters }
        }

        return chunkPlainText(text, preferredSize: 5000)
    }

    private static func headingTitle(_ line: String) -> String? {
        if line.hasPrefix("# ") {
            let t = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        let lower = line.lowercased()
        if lower.hasPrefix("глава ") || lower.hasPrefix("chapter ") || lower.hasPrefix("часть ") {
            return line.count <= 80 ? line : String(line.prefix(80))
        }
        // Short ALL-CAPS line after blank — heuristic handled by caller only for current line.
        if line.count <= 60,
           line == line.uppercased(),
           line.rangeOfCharacter(from: .letters) != nil,
           !line.contains(".") {
            return line
        }
        return nil
    }

    private static func chunkPlainText(_ text: String, preferredSize: Int) -> [ImportedLocalChapter] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return [ImportedLocalChapter(title: "Текст", htmlText: "", plainText: "")]
        }
        if trimmed.count <= preferredSize * 2 {
            return [ImportedLocalChapter(title: "Текст", htmlText: "", plainText: trimmed)]
        }

        var chapters: [ImportedLocalChapter] = []
        var remaining = trimmed[...]
        var part = 1
        while !remaining.isEmpty {
            if remaining.count <= preferredSize {
                chapters.append(
                    ImportedLocalChapter(
                        title: "Часть \(part)",
                        htmlText: "",
                        plainText: String(remaining)
                    )
                )
                break
            }
            let approxEnd = remaining.index(remaining.startIndex, offsetBy: preferredSize)
            var cut = remaining[...approxEnd]
            if let blank = cut.range(of: "\n\n", options: .backwards)?.lowerBound,
               blank > remaining.startIndex {
                cut = remaining[..<blank]
            } else if let nl = cut.range(of: "\n", options: .backwards)?.lowerBound,
                      nl > remaining.startIndex {
                cut = remaining[..<nl]
            }
            let body = String(cut).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                chapters.append(ImportedLocalChapter(title: "Часть \(part)", htmlText: "", plainText: body))
                part += 1
            }
            remaining = remaining[cut.endIndex...].drop(while: { $0 == "\n" || $0 == " " })
        }
        return chapters.isEmpty
            ? [ImportedLocalChapter(title: "Текст", htmlText: "", plainText: trimmed)]
            : chapters
    }

    // MARK: - EPUB

    static func parseEPUB(url: URL, relativePath: String) throws -> ImportedLocalBook {
        let zipEntries = try LocalZIP.entries(from: url)
        var byPath: [String: Data] = [:]
        for e in zipEntries {
            byPath[normalizePath(e.path)] = e.data
        }

        guard let containerData = byPath["meta-inf/container.xml"]
                ?? byPath.first(where: { $0.key.hasSuffix("container.xml") })?.value,
              let containerXML = String(data: containerData, encoding: .utf8)
        else {
            throw LocalBookImportError.invalidEPUB
        }

        guard let rootPathRaw = firstMatch(
            in: containerXML,
            pattern: #"full-path\s*=\s*"([^"]+)""#
        ) else {
            throw LocalBookImportError.invalidEPUB
        }
        let rootPath = normalizePath(rootPathRaw)
        guard let opfData = byPath[rootPath],
              let opf = String(data: opfData, encoding: .utf8)
        else {
            throw LocalBookImportError.invalidEPUB
        }

        let opfDir = rootPath.contains("/")
            ? String(rootPath[..<(rootPath.lastIndex(of: "/") ?? rootPath.startIndex)])
            : ""

        let title = firstMatch(in: opf, pattern: #"<dc:title[^>]*>([^<]+)</dc:title>"#)
            ?? url.deletingPathExtension().lastPathComponent
        let author = firstMatch(in: opf, pattern: #"<dc:creator[^>]*>([^<]+)</dc:creator>"#) ?? ""

        // manifest id -> href
        var manifest: [String: String] = [:]
        let itemRegex = try! NSRegularExpression(
            pattern: #"<item\b[^>]*\bid\s*=\s*"([^"]+)"[^>]*\bhref\s*=\s*"([^"]+)"[^>]*/?>|<item\b[^>]*\bhref\s*=\s*"([^"]+)"[^>]*\bid\s*=\s*"([^"]+)"[^>]*/?>"#,
            options: [.caseInsensitive]
        )
        let opfNS = NSRange(opf.startIndex..., in: opf)
        itemRegex.enumerateMatches(in: opf, options: [], range: opfNS) { match, _, _ in
            guard let match else { return }
            func g(_ i: Int) -> String? {
                let r = match.range(at: i)
                guard r.location != NSNotFound, let swift = Range(r, in: opf) else { return nil }
                return String(opf[swift])
            }
            if let id = g(1), let href = g(2) {
                manifest[id] = href
            } else if let href = g(3), let id = g(4) {
                manifest[id] = href
            }
        }

        var spineIDs: [String] = []
        let spineRegex = try! NSRegularExpression(
            pattern: #"<itemref\b[^>]*\bidref\s*=\s*"([^"]+)""#,
            options: [.caseInsensitive]
        )
        spineRegex.enumerateMatches(in: opf, options: [], range: opfNS) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: opf) else { return }
            spineIDs.append(String(opf[r]))
        }

        // TOC titles from NCX
        var tocTitles: [String: String] = [:] // href path -> title
        if let ncxHref = manifest.values.first(where: { $0.lowercased().hasSuffix(".ncx") })
            ?? firstMatch(in: opf, pattern: #"href\s*=\s*"([^"]+\.ncx)""#) {
            let ncxPath = joinPath(opfDir, ncxHref)
            if let ncxData = byPath[normalizePath(ncxPath)],
               let ncx = String(data: ncxData, encoding: .utf8) {
                let navRegex = try! NSRegularExpression(
                    pattern: #"<navPoint\b[\s\S]*?<navLabel>\s*<text>([^<]*)</text>[\s\S]*?<content\s+src\s*=\s*"([^"]+)""#,
                    options: [.caseInsensitive]
                )
                let ncxNS = NSRange(ncx.startIndex..., in: ncx)
                navRegex.enumerateMatches(in: ncx, options: [], range: ncxNS) { match, _, _ in
                    guard let match,
                          let tR = Range(match.range(at: 1), in: ncx),
                          let sR = Range(match.range(at: 2), in: ncx) else { return }
                    let title = String(ncx[tR]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let src = String(ncx[sR]).split(separator: "#").first.map(String.init) ?? String(ncx[sR])
                    let full = normalizePath(joinPath((ncxPath as NSString).deletingLastPathComponent, src))
                    if !title.isEmpty { tocTitles[full] = title }
                }
            }
        }

        var chapters: [ImportedLocalChapter] = []
        for (idx, idref) in spineIDs.enumerated() {
            guard let href = manifest[idref] else { continue }
            let hrefDecoded = (href.removingPercentEncoding ?? href)
            let lower = hrefDecoded.lowercased()
            guard lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm") || lower.hasSuffix(".xml") else {
                continue
            }
            let fullPath = normalizePath(joinPath(opfDir, hrefDecoded))
            guard let fileData = byPath[fullPath],
                  let html = String(data: fileData, encoding: .utf8)
                    ?? String(data: fileData, encoding: .isoLatin1)
            else { continue }

            let plain = HTMLText.readerPlain(from: html)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard plain.count > 20 else { continue } // skip nav/cover stubs

            let title = tocTitles[fullPath]
                ?? firstMatch(in: html, pattern: #"<title[^>]*>([^<]+)</title>"#)
                ?? "Глава \(idx + 1)"
            chapters.append(ImportedLocalChapter(title: title, htmlText: html, plainText: plain))
        }

        if chapters.isEmpty {
            // Fallback: every html-ish file
            for (path, data) in byPath.sorted(by: { $0.key < $1.key }) {
                let lower = path.lowercased()
                guard lower.hasSuffix(".xhtml") || lower.hasSuffix(".html") || lower.hasSuffix(".htm") else { continue }
                guard let html = String(data: data, encoding: .utf8) else { continue }
                let plain = HTMLText.readerPlain(from: html).trimmingCharacters(in: .whitespacesAndNewlines)
                guard plain.count > 40 else { continue }
                chapters.append(
                    ImportedLocalChapter(
                        title: (path as NSString).lastPathComponent,
                        htmlText: html,
                        plainText: plain
                    )
                )
            }
        }

        if chapters.isEmpty {
            throw LocalBookImportError.invalidEPUB
        }

        return ImportedLocalBook(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: author.trimmingCharacters(in: .whitespacesAndNewlines),
            format: .epub,
            relativePath: relativePath,
            coverData: nil,
            chapters: chapters
        )
    }

    // MARK: - Helpers

    private static func normalizePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    private static func joinPath(_ dir: String, _ file: String) -> String {
        if file.hasPrefix("/") { return String(file.dropFirst()) }
        if dir.isEmpty { return file }
        return "\(dir)/\(file)"
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

private extension String.Encoding {
    static var windowsCP1251: String.Encoding {
        let cf = CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
    }
}
