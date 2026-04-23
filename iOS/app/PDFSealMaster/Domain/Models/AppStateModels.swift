import Foundation

enum AppError: Error, Equatable {
    case fileImportFailed
    case unsupportedFileType
    case stampNormalizationFailed
    case invalidStampAsset
    case draftSaveFailed
    case draftRestoreFailed
    case exportFailed
    case purchaseFailed
    case permissionDenied
    case unknown
}

enum ProFeature: Equatable {
    case export
    case bindingStamp
    case unifyStampSize
}

enum EntitlementState: Equatable {
    case free
    case pro
    case unknown
}

enum PaywallTrigger: Equatable {
    case export
    case bindingStamp
    case unifyStampSize
}

extension EntitlementState {
    var displayName: String {
        switch self {
        case .free:
            return "免费版"
        case .pro:
            return "专业版"
        case .unknown:
            return "检测中"
        }
    }
}

extension PaywallTrigger {
    var displayTitle: String {
        switch self {
        case .export:
            return "正式导出"
        case .bindingStamp:
            return "骑缝章"
        case .unifyStampSize:
            return "统一所有印章尺寸"
        }
    }

    var paywallDescription: String {
        switch self {
        case .export:
            return "免费版可试用编辑，但正式导出属于专业版能力。"
        case .bindingStamp:
            return "骑缝章是首发差异化能力，当前仅对专业版开放。"
        case .unifyStampSize:
            return "批量统一印章尺寸用于正式文档处理，当前仅对专业版开放。"
        }
    }
}

enum PreviewMode: String, Codable, Hashable {
    case original
    case matchedLowRes
}
