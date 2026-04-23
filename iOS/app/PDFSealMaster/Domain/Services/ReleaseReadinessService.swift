import Foundation

enum ReleaseReadinessStatus: Equatable {
    case pass
    case attention
}

struct ReleaseReadinessCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let status: ReleaseReadinessStatus
    let recommendation: String
}

struct ReleaseBuildMetadata: Equatable {
    let bundleIdentifier: String
    let marketingVersion: String
    let buildNumber: String

    static func fromMainBundle() -> ReleaseBuildMetadata {
        let info = Bundle.main.infoDictionary ?? [:]
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        let marketingVersion = info["CFBundleShortVersionString"] as? String ?? ""
        let buildNumber = info["CFBundleVersion"] as? String ?? ""
        return ReleaseBuildMetadata(
            bundleIdentifier: bundleIdentifier,
            marketingVersion: marketingVersion,
            buildNumber: buildNumber
        )
    }
}

struct ReleaseReadinessService {
    func evaluateAutoChecks(
        metadata: ReleaseBuildMetadata = .fromMainBundle(),
        productID: String = PurchaseProductCatalog.proLifetime
    ) -> [ReleaseReadinessCheck] {
        [
            evaluateBundleIdentifier(metadata.bundleIdentifier),
            evaluateMarketingVersion(metadata.marketingVersion),
            evaluateBuildNumber(metadata.buildNumber),
            evaluateStoreProductID(productID)
        ]
    }

    private func evaluateBundleIdentifier(_ value: String) -> ReleaseReadinessCheck {
        let segments = value.split(separator: ".")
        let isValid = !value.isEmpty && segments.count >= 3 && !segments.contains(where: \.isEmpty)
        return ReleaseReadinessCheck(
            id: "bundle_identifier",
            title: "Bundle Identifier",
            detail: value.isEmpty ? "当前为空" : "当前：\(value)",
            status: isValid ? .pass : .attention,
            recommendation: "建议使用反向域名格式，例如 com.company.appname。"
        )
    }

    private func evaluateMarketingVersion(_ value: String) -> ReleaseReadinessCheck {
        let segments = value.split(separator: ".")
        let isAllDigits = segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy(\.isNumber)
        }
        let isValid = segments.count >= 2 && isAllDigits
        return ReleaseReadinessCheck(
            id: "marketing_version",
            title: "Marketing Version",
            detail: value.isEmpty ? "当前为空" : "当前：\(value)",
            status: isValid ? .pass : .attention,
            recommendation: "建议格式为 x.y 或 x.y.z（如 1.0 或 1.0.3）。"
        )
    }

    private func evaluateBuildNumber(_ value: String) -> ReleaseReadinessCheck {
        let buildNumber = Int(value)
        let isValid = (buildNumber ?? 0) > 0
        return ReleaseReadinessCheck(
            id: "build_number",
            title: "Build Number",
            detail: value.isEmpty ? "当前为空" : "当前：\(value)",
            status: isValid ? .pass : .attention,
            recommendation: "应为递增正整数（如 1、2、3...）。"
        )
    }

    private func evaluateStoreProductID(_ value: String) -> ReleaseReadinessCheck {
        let segments = value.split(separator: ".")
        let isValid = !value.isEmpty && segments.count >= 4 && !segments.contains(where: \.isEmpty)
        return ReleaseReadinessCheck(
            id: "storekit_product_id",
            title: "StoreKit Product ID",
            detail: value.isEmpty ? "当前为空" : "当前：\(value)",
            status: isValid ? .pass : .attention,
            recommendation: "建议使用稳定命名，例如 com.company.app.pro.lifetime。"
        )
    }
}
