import Foundation
import CryptoKit
import Combine

/// Optional promo-code grants (device-local). Paid Pro goes through StoreKit.
@MainActor
final class ProGrantStore: ObservableObject {
    static let shared = ProGrantStore()

    private let grantsKey = "pro.grants.v1"
    private let inviteCodeKey = "pro.inviteCode.v1"
    private let inviteExpiresKey = "pro.inviteExpires.v1"
    private let issuedKey = "pro.issuedCodes.v1"
    private let usedNoncesKey = "pro.usedNonces.v1"
    private let signingKey = "chitalnya.pro.sideload.v1.raif"

    struct Grant: Identifiable, Codable, Hashable {
        var id: String { email }
        var email: String
        var note: String
        var createdAt: Date
        var expiresAt: Date?

        var isActive: Bool {
            guard let expiresAt else { return true }
            return expiresAt > Date()
        }
    }

    struct IssuedCode: Identifiable, Codable, Hashable {
        var id: String { code }
        var code: String
        var days: Int
        var createdAt: Date
        var note: String
    }

    enum Plan: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case year = 365

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .year: return "Год"
            }
        }

        var subtitle: String {
            switch self {
            case .week: return "7 дней Pro"
            case .month: return "30 дней Pro"
            case .year: return "365 дней Pro · выгоднее"
            }
        }

        /// Reference label for promo admin UI (not charged via SBP).
        var priceRub: Int {
            switch self {
            case .week: return 149
            case .month: return 349
            case .year: return 1990
            }
        }

        var priceLabel: String {
            "\(priceRub.formatted()) ₽"
        }

        var perMonthHint: String? {
            switch self {
            case .week: return nil
            case .month: return nil
            case .year: return "≈ \(Int((Double(priceRub) / 12.0).rounded())) ₽/мес"
            }
        }
    }

    @Published private(set) var grants: [Grant] = []
    @Published private(set) var issuedCodes: [IssuedCode] = []
    @Published var inviteCode: String {
        didSet { UserDefaults.standard.set(inviteCode, forKey: inviteCodeKey) }
    }
    @Published var inviteExpiresAt: Date? {
        didSet {
            if let inviteExpiresAt {
                UserDefaults.standard.set(inviteExpiresAt, forKey: inviteExpiresKey)
            } else {
                UserDefaults.standard.removeObject(forKey: inviteExpiresKey)
            }
        }
    }

    private var usedNonces: Set<String> = []

    private init() {
        grants = Self.load(grantsKey) ?? []
        issuedCodes = Self.load(issuedKey) ?? []
        usedNonces = Set(Self.load(usedNoncesKey) ?? [String]())
        let storedCode = UserDefaults.standard.string(forKey: inviteCodeKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        inviteCode = (storedCode?.isEmpty == false) ? storedCode! : "CHITALNYA-FRIENDS"
        inviteExpiresAt = UserDefaults.standard.object(forKey: inviteExpiresKey) as? Date
    }

    func isGranted(email: String?, userName: String?) -> Bool {
        let candidates = [normalize(email), normalize(userName)].compactMap { $0 }
        guard !candidates.isEmpty else { return false }
        return grants.contains { grant in
            grant.isActive && candidates.contains(grant.email)
        }
    }

    @discardableResult
    func grant(raw: String, days: Int?, note: String = "") -> String? {
        guard let key = normalize(raw) else { return "Укажите email или username" }
        let expires: Date? = {
            guard let days, days > 0 else { return nil }
            let fromNow = Calendar.current.date(byAdding: .day, value: days, to: Date())!
            if let existing = grants.first(where: { $0.email == key })?.expiresAt, existing > Date() {
                return max(existing, fromNow)
            }
            return fromNow
        }()
        grants.removeAll { $0.email == key }
        grants.insert(
            Grant(
                email: key,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAt: .now,
                expiresAt: expires
            ),
            at: 0
        )
        persistGrants()
        return nil
    }

    func revoke(_ email: String) {
        let key = normalize(email) ?? email
        grants.removeAll { $0.email == key }
        persistGrants()
    }

    /// Owner: create signed code for week / month / year.
    func generateAccessCode(plan: Plan, note: String = "") -> String {
        let nonce = randomNonce(length: 6)
        let sig = signature(days: plan.rawValue, nonce: nonce)
        let code = "CN\(plan.rawValue)-\(nonce)-\(sig)"
        issuedCodes.insert(
            IssuedCode(code: code, days: plan.rawValue, createdAt: .now, note: note),
            at: 0
        )
        if issuedCodes.count > 100 {
            issuedCodes = Array(issuedCodes.prefix(100))
        }
        persistIssued()
        return code
    }

    /// Friend redeems signed plan code or legacy invite.
    func redeemInvite(code: String, email: String?, userName: String?) -> String? {
        let entered = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !entered.isEmpty else { return "Введите код" }

        let target = normalize(email) ?? normalize(userName)
        guard let target else {
            return "Войдите в аккаунт Author.Today, затем введите код"
        }

        if let parsed = parseSignedCode(entered) {
            if usedNonces.contains(parsed.nonce) {
                return "Этот код уже использован на устройстве"
            }
            if let err = grant(raw: target, days: parsed.days, note: "код \(parsed.days)д") {
                return err
            }
            usedNonces.insert(parsed.nonce)
            persistUsedNonces()
            return nil
        }

        let builtin = ProFeatures.sideloadInviteCodes.map { $0.uppercased() }
        let local = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let matchedBuiltin = builtin.contains(entered)
        let matchedLocal = !local.isEmpty && entered == local
        guard matchedBuiltin || matchedLocal else {
            return "Неверный код"
        }
        if matchedLocal, !matchedBuiltin, let inviteExpiresAt, inviteExpiresAt < Date() {
            return "Срок действия кода истёк"
        }
        return grant(raw: target, days: nil, note: "код доступа")
    }

    private func parseSignedCode(_ code: String) -> (days: Int, nonce: String)? {
        // CN7-XXXXXX-YYYYYYYY or CN30-... or CN365-...
        let parts = code.split(separator: "-").map(String.init)
        guard parts.count == 3, parts[0].hasPrefix("CN") else { return nil }
        let daysStr = String(parts[0].dropFirst(2))
        guard let days = Int(daysStr), Plan(rawValue: days) != nil else { return nil }
        let nonce = parts[1]
        let sig = parts[2]
        guard nonce.count >= 4, sig.count >= 6 else { return nil }
        let expected = signature(days: days, nonce: nonce)
        guard sig == expected else { return nil }
        return (days, nonce)
    }

    private func signature(days: Int, nonce: String) -> String {
        let payload = "\(days).\(nonce.uppercased())"
        let key = SymmetricKey(data: Data(signingKey.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return Data(mac).prefix(4).map { String(format: "%02X", $0) }.joined()
    }

    private func randomNonce(length: Int) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    private func persistGrants() {
        persist(grants, key: grantsKey)
    }

    private func persistIssued() {
        persist(issuedCodes, key: issuedKey)
    }

    private func persistUsedNonces() {
        persist(Array(usedNonces), key: usedNoncesKey)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func normalize(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !s.isEmpty else { return nil }
        if s.hasPrefix("@") { s.removeFirst() }
        return s
    }
}
