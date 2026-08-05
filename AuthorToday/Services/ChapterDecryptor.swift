import Foundation

enum ChapterDecryptor {
    /// Author.Today XOR scheme used by the official web reader.
    /// Cipher = reverse(secret) + "@_@"
    /// Operates on UTF-16 code units (same as the site JS / lightnovel-crawler).
    static func decrypt(_ encrypted: String, readerSecret: String) -> String {
        let secret = readerSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty, !encrypted.isEmpty else { return encrypted }

        let cipher = String(secret.reversed()) + "@_@"
        let cipherUnits = Array(cipher.utf16)
        guard !cipherUnits.isEmpty else { return encrypted }

        var encoded = Array(encrypted.utf16)
        if encoded.first == 0xFEFF {
            encoded.removeFirst()
        }

        var decrypted = [UInt16]()
        decrypted.reserveCapacity(encoded.count)

        for (i, unit) in encoded.enumerated() {
            decrypted.append(unit ^ cipherUnits[i % cipherUnits.count])
        }

        if decrypted.first == 0xFEFF {
            decrypted.removeFirst()
        }

        return String(utf16CodeUnits: decrypted, count: decrypted.count)
    }

    /// Strict check: wrong API keys produce Cyrillic soup that fools a naive regex.
    /// Real chapters are HTML with paragraph tags and a sane letter/space ratio.
    static func looksLikePlaintext(_ value: String) -> Bool {
        let sample = String(value.prefix(800))
        guard !sample.isEmpty else { return false }

        let hasHTML = sample.range(
            of: #"(?i)<p\b|</p>|<br\s*/?>|&nbsp;|<div\b"#,
            options: .regularExpression
        ) != nil

        let letters = sample.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let spaces = sample.unicodeScalars.filter { CharacterSet.whitespacesAndNewlines.contains($0) }.count
        let weird = sample.unicodeScalars.filter { scalar in
            let v = scalar.value
            // Latin-1 / Latin Extended common in failed XOR soup
            return (v >= 0x0080 && v <= 0x024F) || (v >= 0x1E00 && v <= 0x1EFF)
        }.count

        let ratioLetters = Double(letters) / Double(max(sample.count, 1))
        let ratioSpaces = Double(spaces) / Double(max(sample.count, 1))
        let ratioWeird = Double(weird) / Double(max(sample.count, 1))

        if hasHTML && ratioWeird < 0.12 {
            return true
        }

        // Plain text chapters (rare): lots of letters/spaces, little soup
        if ratioLetters > 0.45 && ratioSpaces > 0.08 && ratioWeird < 0.05 {
            let cyr = sample.range(of: #"[А-Яа-яЁё]{4,}"#, options: .regularExpression) != nil
            let lat = sample.range(of: #"[A-Za-z]{4,}"#, options: .regularExpression) != nil
            return cyr || lat
        }
        return false
    }
}
