import Foundation

/// Checks «Читальня Pro» purchased on our VPS (not author.today, not StoreKit).
enum ProWebEntitlementClient {
    static let purchasePageURL = URL(string: "https://at.theinquisitor.ru/chitalnya/pro.html")!
    private static let statusURL = URL(string: "https://at.theinquisitor.ru/chitalnya/api/pro-status")!

    struct Status: Decodable {
        var active: Bool
        var expiresAt: Date?
    }

    static func fetch(email: String?, userName: String?) async -> Status? {
        guard ChitalnyaDistribution.allowsWebPurchasedPro else { return nil }
        let emailNorm = ProFeatures.normalize(email)
        let userNorm = ProFeatures.normalize(userName)
        guard emailNorm != nil || userNorm != nil else {
            return Status(active: false, expiresAt: nil)
        }

        var components = URLComponents(url: statusURL, resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = []
        if let emailNorm { items.append(URLQueryItem(name: "email", value: emailNorm)) }
        if let userNorm { items.append(URLQueryItem(name: "user", value: userNorm)) }
        components?.queryItems = items
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Status.self, from: data)
        } catch {
            return nil
        }
    }
}
