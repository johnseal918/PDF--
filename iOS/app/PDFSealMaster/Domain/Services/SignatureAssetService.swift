import Foundation

protocol SignatureAssetService {
    func createSignatureAsset(
        name: String,
        sourcePath: String,
        transparentImagePath: String?
    ) async throws -> SignatureAsset

    func renameSignatureAsset(_ asset: SignatureAsset, to newName: String) async throws -> SignatureAsset
    func loadAllSignatureAssets() async throws -> [SignatureAsset]
}

final class InMemorySignatureAssetService: SignatureAssetService {
    private var assets: [SignatureAsset] = []

    func createSignatureAsset(
        name: String,
        sourcePath: String,
        transparentImagePath: String?
    ) async throws -> SignatureAsset {
        let asset = SignatureAsset(
            name: name,
            originalSignaturePath: sourcePath,
            normalizedTransparentImagePath: transparentImagePath,
            createdAt: Date(),
            updatedAt: Date()
        )

        assets.append(asset)
        return asset
    }

    func renameSignatureAsset(_ asset: SignatureAsset, to newName: String) async throws -> SignatureAsset {
        var updated = asset
        updated.name = newName
        updated.updatedAt = Date()

        assets.removeAll { $0.id == asset.id }
        assets.append(updated)
        return updated
    }

    func loadAllSignatureAssets() async throws -> [SignatureAsset] {
        assets.sorted { $0.updatedAt > $1.updatedAt }
    }
}
