import Foundation
#if canImport(StoreKit)
import StoreKit

@available(iOS 15.0, *)
actor StoreKitPurchaseService: PurchaseService {
    private enum Keys {
        static let proUnlocked = "purchase.pro.unlocked"
    }

    private let productID: String
    private let defaults: UserDefaults

    init(
        productID: String = PurchaseProductCatalog.proLifetime,
        defaults: UserDefaults = .standard
    ) {
        self.productID = productID
        self.defaults = defaults
    }

    func currentEntitlements() async -> EntitlementState {
        let state = await refreshEntitlementFromStoreKit()
        return state
    }

    func purchasePro() async throws {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw PurchaseServiceError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case let .success(verification):
            switch verification {
            case let .verified(transaction):
                defaults.set(true, forKey: Keys.proUnlocked)
                await transaction.finish()
            case .unverified:
                throw PurchaseServiceError.purchaseVerificationFailed
            }
        case .pending:
            throw PurchaseServiceError.purchasePending
        case .userCancelled:
            throw PurchaseServiceError.purchaseCancelled
        @unknown default:
            throw PurchaseServiceError.purchaseVerificationFailed
        }
    }

    func restorePurchases() async throws {
        do {
            try await AppStore.sync()
            _ = await refreshEntitlementFromStoreKit()
        } catch {
            throw PurchaseServiceError.restoreFailed
        }
    }

    func canUse(_ feature: ProFeature) async -> Bool {
        _ = feature
        return await currentEntitlements() == .pro
    }

    private func refreshEntitlementFromStoreKit() async -> EntitlementState {
        var unlocked = false

        for await verification in Transaction.currentEntitlements {
            switch verification {
            case let .verified(transaction):
                guard transaction.productID == productID else {
                    continue
                }

                let isRevoked = transaction.revocationDate != nil
                if !isRevoked {
                    unlocked = true
                }
            case .unverified:
                continue
            }
        }

        defaults.set(unlocked, forKey: Keys.proUnlocked)
        return unlocked ? .pro : .free
    }
}
#endif

