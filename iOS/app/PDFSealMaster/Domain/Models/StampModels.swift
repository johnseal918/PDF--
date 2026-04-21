import Foundation

enum StampNormalizationStatus: String, Codable, Hashable {
    case imported
    case autoDetected
    case manuallyAdjusted
    case ready
}

struct StampAsset: Identifiable, Codable, Hashable {
    var schemaVersion: Int = 1
    var id = UUID()
    var name: String
    var originalImagePath: String
    var normalizedTransparentImagePath: String?
    var normalizationMaskPath: String?
    var effectiveBoundsPX: PixelRect?
    var manualCropOverrides: PixelRect?
    var normalizationStatus: StampNormalizationStatus
    var physicalSizePresetMM: Double?
    var finalPhysicalSizeMM: Double?
    var defaultAspectRatio: Double?
    var isAspectRatioLockedByDefault: Bool
    var isFavorite: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct SignatureAsset: Identifiable, Codable, Hashable {
    var schemaVersion: Int = 1
    var id = UUID()
    var name: String
    var originalSignaturePath: String
    var normalizedTransparentImagePath: String?
    var createdAt: Date
    var updatedAt: Date
}
