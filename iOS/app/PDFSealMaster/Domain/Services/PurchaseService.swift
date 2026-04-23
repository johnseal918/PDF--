import Foundation

protocol PurchaseService {
    func currentEntitlements() async -> EntitlementState
    func purchasePro() async throws
    func restorePurchases() async throws
    func canUse(_ feature: ProFeature) async -> Bool
}

actor InMemoryPurchaseService: PurchaseService {
    private var entitlementState: EntitlementState

    init(initialState: EntitlementState = .free) {
        self.entitlementState = initialState
    }

    func currentEntitlements() async -> EntitlementState {
        entitlementState
    }

    func purchasePro() async throws {
        entitlementState = .pro
    }

    func restorePurchases() async throws {
        if entitlementState == .unknown {
            entitlementState = .free
        }
    }

    func canUse(_ feature: ProFeature) async -> Bool {
        _ = feature
        return entitlementState == .pro
    }
}

actor LocalPurchaseService: PurchaseService {
    private enum Keys {
        static let proUnlocked = "purchase.pro.unlocked"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func currentEntitlements() async -> EntitlementState {
        defaults.bool(forKey: Keys.proUnlocked) ? .pro : .free
    }

    func purchasePro() async throws {
        defaults.set(true, forKey: Keys.proUnlocked)
    }

    func restorePurchases() async throws {
        // Placeholder restore behavior for M5 skeleton.
        // StoreKit transaction sync will replace this in the next milestone slice.
    }

    func canUse(_ feature: ProFeature) async -> Bool {
        _ = feature
        return defaults.bool(forKey: Keys.proUnlocked)
    }
}
