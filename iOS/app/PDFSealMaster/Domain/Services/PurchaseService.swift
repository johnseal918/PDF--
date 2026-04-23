import Foundation

protocol PurchaseService {
    func currentEntitlements() async -> EntitlementState
    func purchasePro() async throws
    func restorePurchases() async throws
    func canUse(_ feature: ProFeature) async -> Bool
}

enum PurchaseServiceError: LocalizedError, Equatable {
    case productNotFound
    case purchasePending
    case purchaseCancelled
    case purchaseVerificationFailed
    case restoreFailed

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "未找到可购买的专业版商品，请稍后重试。"
        case .purchasePending:
            return "购买正在等待系统确认，请稍后刷新权益状态。"
        case .purchaseCancelled:
            return "已取消购买。"
        case .purchaseVerificationFailed:
            return "购买校验失败，请重试或恢复购买。"
        case .restoreFailed:
            return "恢复购买失败，请稍后重试。"
        }
    }
}

enum PurchaseProductCatalog {
    // First App Store submission uses a one-time unlock product.
    static let proLifetime = "com.johnseal918.pdfsealmaster.pro.lifetime"
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
        // Local fallback mode has no App Store receipt to sync.
        // Keep existing local entitlement state unchanged.
    }

    func canUse(_ feature: ProFeature) async -> Bool {
        _ = feature
        return defaults.bool(forKey: Keys.proUnlocked)
    }
}
