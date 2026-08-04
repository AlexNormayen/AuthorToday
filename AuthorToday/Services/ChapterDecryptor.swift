import Foundation

enum ChapterDecryptor {
    /// Author.Today XOR obfuscation using `Reader-Secret` response header.
    /// Ported from public crawler implementations of the same scheme.
    static func decrypt(_ encrypted: String, readerSecret: String) -> String {
        let cipher = String(readerSecret.reversed()) + "@_@"
        let cipherScalars = Array(cipher.unicodeScalars)

        // Treat encrypted string as UTF-16 code units (as returned by JSON),
        // then XOR each unit with the repeating cipher.
        let units = Array(encrypted.utf16)
        guard !units.isEmpty, !cipherScalars.isEmpty else { return encrypted }

        var decrypted = [UInt16]()
        decrypted.reserveCapacity(units.count)

        // Skip BOM if present in decrypted stream logic used by crawlers —
        // they prepend BOM after XOR. We XOR in place and strip BOM at end.
        for (i, unit) in units.enumerated() {
            let key = UInt16(cipherScalars[i % cipherScalars.count].value)
            decrypted.append(unit ^ key)
        }

        if decrypted.first == 0xFEFF {
            decrypted.removeFirst()
        }

        return String(utf16CodeUnits: decrypted, count: decrypted.count)
    }
}
