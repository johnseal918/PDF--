import Foundation

protocol SignatureAssetService {
    func createSignatureAsset(
        name: String,
        sourcePath: String,
        transparentImagePath: String?
    ) async throws -> SignatureAsset

    func renameSignatureAsset(_ asset: SignatureAsset, to newName: String) async throws -> SignatureAsset
    func deleteSignatureAsset(_ asset: SignatureAsset) async throws
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

    func deleteSignatureAsset(_ asset: SignatureAsset) async throws {
        assets.removeAll { $0.id == asset.id }
    }
}

final class FileSignatureAssetService: SignatureAssetService {
    private enum StorageError: Error {
        case applicationSupportUnavailable
        case invalidSourcePath
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

    func createSignatureAsset(
        name: String,
        sourcePath: String,
        transparentImagePath: String?
    ) async throws -> SignatureAsset {
        let signatureID = UUID()
        let rootDirectory = try signatureDirectoryURL(for: signatureID)
        let originalDirectory = rootDirectory.appendingPathComponent("original", isDirectory: true)
        let normalizedDirectory = rootDirectory.appendingPathComponent("normalized", isDirectory: true)

        try fileManager.createDirectory(at: originalDirectory, withIntermediateDirectories: true, attributes: nil)
        try fileManager.createDirectory(at: normalizedDirectory, withIntermediateDirectories: true, attributes: nil)

        let originalURL = try copyImage(
            atPath: sourcePath,
            to: originalDirectory,
            fileName: "signature-original"
        )

        var normalizedURL: URL?
        if let transparentImagePath, !transparentImagePath.isEmpty {
            normalizedURL = try copyImage(
                atPath: transparentImagePath,
                to: normalizedDirectory,
                fileName: "signature-transparent"
            )
        }

        let now = Date()
        let asset = SignatureAsset(
            id: signatureID,
            name: name,
            originalSignaturePath: originalURL.path,
            normalizedTransparentImagePath: normalizedURL?.path,
            createdAt: now,
            updatedAt: now
        )

        try persist(asset: asset, at: rootDirectory)
        return asset
    }

    func renameSignatureAsset(_ asset: SignatureAsset, to newName: String) async throws -> SignatureAsset {
        var updated = asset
        updated.name = newName
        updated.updatedAt = Date()
        let directory = try signatureDirectoryURL(for: updated.id)
        try persist(asset: updated, at: directory)
        return updated
    }

    func loadAllSignatureAssets() async throws -> [SignatureAsset] {
        let signaturesRoot = try signaturesRootDirectory()
        guard fileManager.fileExists(atPath: signaturesRoot.path) else {
            return []
        }

        let directories = try fileManager.contentsOfDirectory(
            at: signaturesRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var assets: [SignatureAsset] = []
        for directoryURL in directories {
            let signatureURL = directoryURL.appendingPathComponent("signature.json", isDirectory: false)
            guard fileManager.fileExists(atPath: signatureURL.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: signatureURL)
                let asset = try decoder.decode(SignatureAsset.self, from: data)
                assets.append(asset)
            } catch {
                continue
            }
        }

        return assets.sorted { $0.updatedAt > $1.updatedAt }
    }

    func deleteSignatureAsset(_ asset: SignatureAsset) async throws {
        let directory = try signatureDirectoryURL(for: asset.id)
        guard fileManager.fileExists(atPath: directory.path) else {
            return
        }

        try fileManager.removeItem(at: directory)
    }

    private func copyImage(
        atPath sourcePath: String,
        to destinationDirectory: URL,
        fileName: String
    ) throws -> URL {
        guard !sourcePath.isEmpty else {
            throw StorageError.invalidSourcePath
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw StorageError.invalidSourcePath
        }

        let fileExtension = normalizedExtension(sourceURL.pathExtension)
        let destinationURL = destinationDirectory.appendingPathComponent(
            "\(fileName).\(fileExtension)",
            isDirectory: false
        )

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func persist(asset: SignatureAsset, at directory: URL) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let fileURL = directory.appendingPathComponent("signature.json", isDirectory: false)
        let data = try encoder.encode(asset)
        try data.write(to: fileURL, options: .atomic)
    }

    private func signatureDirectoryURL(for signatureID: UUID) throws -> URL {
        try signaturesRootDirectory().appendingPathComponent(signatureID.uuidString, isDirectory: true)
    }

    private func signaturesRootDirectory() throws -> URL {
        let applicationSupportURL = try applicationSupportDirectory()
        let signaturesURL = applicationSupportURL
            .appendingPathComponent("Signatures", isDirectory: true)
        try fileManager.createDirectory(
            at: signaturesURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return signaturesURL
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

    private func normalizedExtension(_ fileExtension: String) -> String {
        let normalized = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? "png" : normalized
    }
}
