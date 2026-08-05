import Foundation

enum ChapterDecryptor {
    /// Author.Today XOR scheme used by the official web reader / mobile API.
    /// Cipher = reverse(secret) + "@_@"
    /// Operates on UTF-16 code units (same as popular open-source clients).
    static func decrypt(_ encrypted: String, readerSecret: String) -> String {
        let secret = readerSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty, !encrypted.isEmpty else { return encrypted }

        let cipher = String(secret.reversed()) + "@_@"
        let cipherScalars = Array(cipher.unicodeScalars)
        guard !cipherScalars.isEmpty else { return encrypted }

        // Mirror Python: encrypted.encode("utf-16")[2:] then LE code units.
        var encoded = Array(encrypted.utf16)
        // If Swift string somehow carried BOM, drop it before XOR.
        if encoded.first == 0xFEFF {
            encoded.removeFirst()
        }

        var decrypted = [UInt16]()
        decrypted.reserveCapacity(encoded.count + 1)

        for (i, unit) in encoded.enumerated() {
            let key = UInt16(cipherScalars[i % cipherScalars.count].value)
            decrypted.append(unit ^ key)
        }

        if decrypted.first == 0xFEFF {
            decrypted.removeFirst()
        }

        return String(utf16CodeUnits: decrypted, count: decrypted.count)
    }

    /// Returns true when decrypted output looks like readable HTML/text rather than ciphertext.
    static func looksLikePlaintext(_ value: String) -> Bool {
        let sample = String(value.prefix(400))
        if sample.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) != nil { return true }
        if sample.range(of: #"(?i)<p|<br|</p>|&nbsp;"#, options: .regularExpression) != nil { return true }
        if sample.range(of: #"[A-Za-z]{3,}"#, options: .regularExpression) != nil,
           sample.range(of: #"[+\/=]{3,}"#, options: .regularExpression) == nil {
            return true
        }
        return false
    }
}
