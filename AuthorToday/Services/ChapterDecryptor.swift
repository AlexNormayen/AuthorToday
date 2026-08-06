import Foundation

enum ChapterDecryptor {
    /// Author.Today XOR scheme used by the official web reader.
    /// Cipher = reverse(secret) + "@_@" + userId
    /// Operates on UTF-16 code units (same as site JS: charCodeAt).
    static func decrypt(_ encrypted: String, readerSecret: String, userId: String = "") -> String {
        let secret = readerSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty, !encrypted.isEmpty else { return encrypted }

        let uid = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cipher = String(secret.reversed()) + "@_@" + uid
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

    /// Strict check: wrong keys produce Cyrillic soup that fools a naive letter ratio.
    /// Real chapters are HTML with paragraph tags and readable words.
    static func looksLikePlaintext(_ value: String) -> Bool {
        let sample = String(value.prefix(1200))
        guard sample.count > 40 else { return false }

        if sample.contains("\u{FFFD}") { return false }

        let hasHTML = sample.range(
            of: #"(?i)<p\b|</p>|<br\s*/?>|&nbsp;"#,
            options: .regularExpression
        ) != nil

        guard hasHTML else { return false }

        let letters = sample.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let spaces = sample.unicodeScalars.filter { CharacterSet.whitespacesAndNewlines.contains($0) }.count
        let weird = sample.unicodeScalars.filter { scalar in
            let v = scalar.value
            return (v >= 0x0080 && v <= 0x024F)
                || (v >= 0x0370 && v <= 0x03FF)
                || (v >= 0x0460 && v <= 0x052F)
                || (v >= 0x1E00 && v <= 0x1EFF)
        }.count

        let ratioWeird = Double(weird) / Double(max(sample.count, 1))
        let ratioLetters = Double(letters) / Double(max(sample.count, 1))
        guard ratioWeird < 0.08, ratioLetters > 0.25 else { return false }

        let cyr = sample.range(of: #"[А-Яа-яЁё]{4,}"#, options: .regularExpression) != nil
        let lat = sample.range(of: #"[A-Za-z]{4,}"#, options: .regularExpression) != nil
        guard cyr || lat else { return false }

        let ratioSpaces = Double(spaces) / Double(max(sample.count, 1))
        return ratioSpaces > 0.02
    }
}
