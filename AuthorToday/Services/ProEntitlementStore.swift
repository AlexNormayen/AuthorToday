import Foundation
import StoreKit
import Combine

/// StoreKit 2 entitlements for «Читальня Pro».
@MainActor
final class ProEntitlementStore: ObservableObject {
    static let shared = ProEntitlementStore()

    static let monthlyProductID = "ru.chitalnya.reader.pro.monthly"
    static let yearlyProductID = "ru.chitalnya.reader.pro.yearly"
    static let lifetimeProductID = "ru.chitalnya.reader.pro.lifetime"

    static var allProductIDs: [String] {
        [monthlyProductID, yearlyProductID, lifetimeProductID]
    }

    @Published private(set) var isPro = false
    @Published private(set) var isProUnlocked = false
    /// Pro granted by email/username allowlist (not StoreKit).
    @Published private(set) var isComplimentaryPro = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductID: String?
    @Published var lastError: String?
    @Published var isPurchasing = false
    @Published var isLoadingProducts = false

    private var transactionListener: Task<Void, Never>?
    private let debugUnlockKey = "pro.debugUnlocked"
    private var allowlistEmail: String?
    private var allowlistUserName: String?

    private init() {
        refreshUnlockedFlag()
        transactionListener = Task { [weak self] in
            guard let self else { return }
            for await update in Transaction.updates {
                await self.handle(update)
            }
        }
        Task { await refresh() }
    }

    /// Call after login / profile refresh / logout so allowlisted accounts get Pro.
    func applyAccount(email: String?, userName: String?) {
        allowlistEmail = email
        allowlistUserName = userName
        refreshUnlockedFlag()
    }

    func applyAccount(_ user: CurrentUser?) {
        applyAccount(email: user?.email, userName: user?.resolvedUserName)
    }

    var monthlyProduct: Product? {
        products.first { $0.id == Self.monthlyProductID }
    }

    var yearlyProduct: Product? {
        products.first { $0.id == Self.yearlyProductID }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.lifetimeProductID }
    }

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            products = loaded.sorted { lhs, rhs in
                let order = Self.allProductIDs
                let li = order.firstIndex(of: lhs.id) ?? 99
                let ri = order.firstIndex(of: rhs.id) ?? 99
                return li < ri
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                lastError = nil
                return isProUnlocked
            case .userCancelled:
                return false
            case .pending:
                lastError = "Покупка ожидает подтверждения"
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

#if DEBUG
    func setDebugUnlocked(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: debugUnlockKey)
        refreshUnlockedFlag()
    }
#endif

    /// How many fully downloaded books the free tier may keep (excluding `exceptWorkId` if already full).
    func canStartFullDownload(workId: Int, fullyDownloadedCount: Int, alreadyFullyDownloaded: Bool) -> Bool {
        if isProUnlocked { return true }
        if alreadyFullyDownloaded { return true }
        return fullyDownloadedCount < ProFeatures.freeFullDownloadLimit
    }

    private func refreshEntitlements() async {
        var active = false
        var productID: String?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expiration = transaction.expirationDate, expiration < Date() { continue }
            active = true
            productID = transaction.productID
        }
        isPro = active
        purchasedProductID = productID
        refreshUnlockedFlag()
    }

    private func refreshUnlockedFlag() {
        let builtIn = ProFeatures.isOwnerAccount(
            email: allowlistEmail,
            userName: allowlistUserName
        )
        let granted = ProGrantStore.shared.isGranted(
            email: allowlistEmail,
            userName: allowlistUserName
        )
        isComplimentaryPro = builtIn || granted
        let debug = UserDefaults.standard.bool(forKey: debugUnlockKey)
        isProUnlocked = isPro || isComplimentaryPro || debug
    }

    /// After admin grant / invite redeem.
    func refreshComplimentaryFromGrants() {
        refreshUnlockedFlag()
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard let transaction = try? checkVerified(result) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
