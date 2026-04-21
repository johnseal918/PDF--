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

enum PreviewMode: String, Codable, Hashable {
    case original
    case matchedLowRes
}
