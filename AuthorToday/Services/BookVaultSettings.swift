import Foundation
import Combine

/// Cloud shelf settings (TubeVault /books on Aeza).
@MainActor
final class BookVaultSettings: ObservableObject {
    static let shared = BookVaultSettings()

    enum BuiltIn {
        static let apiViaHTTPS = "https://tv.theinquisitor.ru"
        static let apiPublic = "http://185.125.103.168:8787"
        static let apiViaVPN = "http://172.29.172.1:8787"
        static let apiToken = "4db49ebc4117e7a44602e94dc5ea43bb"
        static let candidates = [apiViaHTTPS, apiPublic, apiViaVPN]
    }

    private enum Keys {
        static let enabled = "at.bookvault.enabled"
        static let baseURL = "at.bookvault.baseURL"
        static let token = "at.bookvault.token"
        static let lastStatus = "at.bookvault.lastStatus"
        static let lastSyncAt = "at.bookvault.lastSyncAt"
    }

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }

    @Published var apiToken: String {
        didSet { defaults.set(apiToken, forKey: Keys.token) }
    }

    @Published var lastStatus: String {
        didSet { defaults.set(lastStatus, forKey: Keys.lastStatus) }
    }

    @Published var lastSyncAt: Date? {
        didSet {
            if let lastSyncAt {
                defaults.set(lastSyncAt.timeIntervalSince1970, forKey: Keys.lastSyncAt)
            } else {
                defaults.removeObject(forKey: Keys.lastSyncAt)
            }
        }
    }

    private init() {
        let enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        var url = defaults.string(forKey: Keys.baseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if url.isEmpty {
            url = BuiltIn.apiViaHTTPS
        }
        var token = defaults.string(forKey: Keys.token)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.isEmpty {
            token = BuiltIn.apiToken
        }
        isEnabled = enabled
        baseURL = url
        apiToken = token
        lastStatus = defaults.string(forKey: Keys.lastStatus) ?? ""
        if defaults.object(forKey: Keys.lastSyncAt) != nil {
            lastSyncAt = Date(timeIntervalSince1970: defaults.double(forKey: Keys.lastSyncAt))
        }
    }

    var resolvedBaseURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed)
    }

    var candidateBaseURLs: [URL] {
        var list: [String] = []
        let primary = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty { list.append(primary) }
        for c in BuiltIn.candidates where !list.contains(c) {
            list.append(c)
        }
        return list.compactMap {
            URL(string: $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        }
    }
}
