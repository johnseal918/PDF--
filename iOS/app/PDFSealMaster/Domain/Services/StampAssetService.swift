import Foundation

protocol StampAssetService {
    func loadAllStampAssets() async throws -> [StampAsset]
    func saveStampAsset(_ asset: StampAsset) async throws -> StampAsset
    func loadDefaultStampAsset() async throws -> StampAsset?
}

final class InMemoryStampAssetService: StampAssetService {
    private var assets: [StampAsset]

    init(seedAssets: [StampAsset] = [SampleStampAssetFactory.makeDefaultStampAsset()]) {
        self.assets = seedAssets
    }

    func loadAllStampAssets() async throws -> [StampAsset] {
        assets.sorted { $0.createdAt < $1.createdAt }
    }

    func saveStampAsset(_ asset: StampAsset) async throws -> StampAsset {
        if let index = assets.firstIndex(where: { $0.id == asset.id }) {
            assets[index] = asset
        } else {
            assets.append(asset)
        }

        return asset
    }

    func loadDefaultStampAsset() async throws -> StampAsset? {
        assets.first(where: { $0.isFavorite }) ?? assets.first
    }
}

final class FileStampAssetService: StampAssetService {
    private enum StorageError: Error {
        case applicationSupportUnavailable
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    func loadAllStampAssets() async throws -> [StampAsset] {
        let stampsRoot = try stampsRootDirectory()
        guard fileManager.fileExists(atPath: stampsRoot.path) else {
            return []
        }

        let directories = try fileManager.contentsOfDirectory(
            at: stampsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var assets: [StampAsset] = []
        for directoryURL in directories {
            let stampURL = directoryURL.appendingPathComponent("stamp.json", isDirectory: false)
            guard fileManager.fileExists(atPath: stampURL.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: stampURL)
                let asset = try decoder.decode(StampAsset.self, from: data)
                assets.append(asset)
            } catch {
                continue
            }
        }

        return assets.sorted { $0.updatedAt > $1.updatedAt }
    }

    func saveStampAsset(_ asset: StampAsset) async throws -> StampAsset {
        let directoryURL = try stampDirectoryURL(for: asset.id)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let fileURL = directoryURL.appendingPathComponent("stamp.json", isDirectory: false)
        let data = try encoder.encode(asset)
        try data.write(to: fileURL, options: .atomic)
        return asset
    }

    func loadDefaultStampAsset() async throws -> StampAsset? {
        let assets = try await loadAllStampAssets()
        return assets.first(where: { $0.isFavorite }) ?? assets.first
    }

    private func stampDirectoryURL(for stampID: UUID) throws -> URL {
        try stampsRootDirectory().appendingPathComponent(stampID.uuidString, isDirectory: true)
    }

    private func stampsRootDirectory() throws -> URL {
        let applicationSupportURL = try applicationSupportDirectory()
        let stampsURL = applicationSupportURL
            .appendingPathComponent("Stamps", isDirectory: true)
        try fileManager.createDirectory(
            at: stampsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return stampsURL
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.applicationSupportUnavailable
        }

        let appSupportURL = baseURL
            .appendingPathComponent("PDFSealMaster", isDirectory: true)
        try fileManager.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return appSupportURL
    }
}

enum SampleStampAssetFactory {
    static func makeDefaultStampAsset() -> StampAsset {
        let now = Date()

        return StampAsset(
            name: "Sample Stamp",
            originalImagePath: "sample-stamp-original.png",
            normalizedTransparentImagePath: "sample-stamp-normalized.png",
            normalizationMaskPath: "sample-stamp-mask.png",
            effectiveBoundsPX: PixelRect(x: 0, y: 0, width: 1024, height: 1024),
            manualCropOverrides: nil,
            normalizationStatus: .ready,
            physicalSizePresetMM: 40.0,
            finalPhysicalSizeMM: 40.0,
            defaultAspectRatio: 1.0,
            isAspectRatioLockedByDefault: true,
            isFavorite: true,
            createdAt: now,
            updatedAt: now
        )
    }
}
