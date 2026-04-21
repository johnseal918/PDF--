import Foundation
import ImageIO
import CoreGraphics
import UIKit

protocol StampNormalizationService {
    func importStamp(from url: URL, name: String) async throws -> StampAsset
    func autoNormalize(asset: StampAsset) async throws -> StampAsset
    func applyManualCrop(_ crop: PixelRect, to asset: StampAsset) async throws -> StampAsset
    func setPhysicalSize(_ sizeMM: Double, for asset: StampAsset) async throws -> StampAsset
}

struct DefaultStampNormalizationService: StampNormalizationService {
    func importStamp(from url: URL, name: String) async throws -> StampAsset {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.fileImportFailed
        }

        let assetID = UUID()
        let originalURL = try copyImportedImage(url, stampID: assetID)
        let detectedBounds = loadImageBounds(from: originalURL) ?? PixelRect(x: 0, y: 0, width: 1024, height: 1024)
        let aspectRatio = max(detectedBounds.width / max(detectedBounds.height, 1), 0.1)
        let now = Date()

        return StampAsset(
            id: assetID,
            name: name,
            originalImagePath: originalURL.path,
            normalizedTransparentImagePath: nil,
            normalizationMaskPath: nil,
            effectiveBoundsPX: detectedBounds,
            manualCropOverrides: nil,
            normalizationStatus: .imported,
            physicalSizePresetMM: 40.0,
            finalPhysicalSizeMM: nil,
            defaultAspectRatio: aspectRatio,
            isAspectRatioLockedByDefault: true,
            isFavorite: false,
            createdAt: now,
            updatedAt: now
        )
    }

    func autoNormalize(asset: StampAsset) async throws -> StampAsset {
        var updated = asset
        let imageURL = URL(fileURLWithPath: asset.originalImagePath)
        let fullBounds = loadImageBounds(from: imageURL) ?? PixelRect(x: 0, y: 0, width: 1024, height: 1024)
        let detectedBounds = detectContentBounds(from: imageURL) ?? fullBounds
        let normalizedBounds = asset.manualCropOverrides ?? detectedBounds
        updated.effectiveBoundsPX = normalizedBounds
        let artifactPaths = try persistNormalizationArtifacts(
            from: imageURL,
            cropBounds: normalizedBounds,
            stampID: asset.id
        )
        updated.normalizedTransparentImagePath = artifactPaths.normalizedImagePath
        updated.normalizationMaskPath = artifactPaths.maskPath
        updated.normalizationStatus = .autoDetected
        updated.defaultAspectRatio = max(normalizedBounds.width / max(normalizedBounds.height, 1), 0.1)
        updated.updatedAt = Date()
        return updated
    }

    func applyManualCrop(_ crop: PixelRect, to asset: StampAsset) async throws -> StampAsset {
        var updated = asset
        let sourceBounds = asset.effectiveBoundsPX ?? PixelRect(x: 0, y: 0, width: 1024, height: 1024)
        let clampedCrop = PixelRect(
            x: min(max(crop.x, sourceBounds.x), sourceBounds.x + sourceBounds.width - 1),
            y: min(max(crop.y, sourceBounds.y), sourceBounds.y + sourceBounds.height - 1),
            width: min(max(crop.width, 1), sourceBounds.width),
            height: min(max(crop.height, 1), sourceBounds.height)
        )
        updated.manualCropOverrides = clampedCrop
        updated.effectiveBoundsPX = clampedCrop
        let artifactPaths = try persistNormalizationArtifacts(
            from: URL(fileURLWithPath: asset.originalImagePath),
            cropBounds: clampedCrop,
            stampID: asset.id
        )
        updated.normalizedTransparentImagePath = artifactPaths.normalizedImagePath
        updated.normalizationMaskPath = artifactPaths.maskPath
        updated.normalizationStatus = .manuallyAdjusted
        updated.defaultAspectRatio = max(clampedCrop.width / max(clampedCrop.height, 1), 0.1)
        updated.updatedAt = Date()
        return updated
    }

    func setPhysicalSize(_ sizeMM: Double, for asset: StampAsset) async throws -> StampAsset {
        var updated = asset
        updated.finalPhysicalSizeMM = min(max(sizeMM, 5.0), 80.0)
        updated.normalizationStatus = .ready
        updated.updatedAt = Date()
        return updated
    }

    private func loadImageBounds(from url: URL) -> PixelRect? {
        ImageFileInspector.displayPixelRect(for: url)
    }

    private func detectContentBounds(from url: URL) -> PixelRect? {
        guard let cgImage = ImageFileInspector.normalizedCGImage(for: url) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let rendered = pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return false
            }

            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard rendered else {
            return nil
        }

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let index = y * bytesPerRow + x * bytesPerPixel
                let r = pixels[index]
                let g = pixels[index + 1]
                let b = pixels[index + 2]
                let a = pixels[index + 3]

                guard isContentPixel(r: r, g: g, b: b, a: a) else {
                    continue
                }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return PixelRect(
            x: Double(minX),
            y: Double(minY),
            width: Double(maxX - minX + 1),
            height: Double(maxY - minY + 1)
        )
    }

    private func isContentPixel(r: UInt8, g: UInt8, b: UInt8, a: UInt8) -> Bool {
        if a < 16 {
            return false
        }

        if a < 245 {
            return true
        }

        if r < 245 || g < 245 || b < 245 {
            return true
        }

        return false
    }

    private func copyImportedImage(_ sourceURL: URL, stampID: UUID) throws -> URL {
        let fileExtension = normalizedExtension(sourceURL.pathExtension)
        let destinationDirectory = try stampDirectory(for: stampID)
        let destinationURL = destinationDirectory.appendingPathComponent("original.\(fileExtension)", isDirectory: false)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func persistNormalizationArtifacts(
        from sourceURL: URL,
        cropBounds: PixelRect,
        stampID: UUID
    ) throws -> NormalizationArtifactPaths {
        let directory = try stampDirectory(for: stampID)
        let normalizedImageURL = directory.appendingPathComponent("normalized-transparent.png", isDirectory: false)
        let maskURL = directory.appendingPathComponent("normalization-mask.json", isDirectory: false)

        if let sourceImage = ImageFileInspector.normalizedCGImage(for: sourceURL),
           let normalizedImage = renderNormalizedImage(from: sourceImage, cropBounds: cropBounds) {
            try writeImage(normalizedImage, to: normalizedImageURL)
        }

        let record = NormalizationMaskRecord(
            originalPixelSize: ImageFileInspector.displayPixelRect(for: sourceURL),
            cropBounds: cropBounds,
            updatedAt: Date()
        )

        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: maskURL, options: .atomic)
        }

        return NormalizationArtifactPaths(
            normalizedImagePath: normalizedImageURL.path,
            maskPath: maskURL.path
        )
    }

    private func renderNormalizedImage(from sourceImage: CGImage, cropBounds: PixelRect) -> UIImage? {
        let canvasRect = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
        guard canvasRect.width > 0, canvasRect.height > 0 else {
            return nil
        }

        let cropRect = clampedCropRect(cropBounds, within: canvasRect)
        guard let croppedCGImage = sourceImage.cropping(to: cropRect) else {
            return nil
        }

        let width = croppedCGImage.width
        let height = croppedCGImage.height
        guard width > 0, height > 0 else {
            return nil
        }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let rendered = pixels.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return false
            }

            guard let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }

            context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            let pixelBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * bytesPerRow + x * bytesPerPixel
                    let r = pixelBuffer[index]
                    let g = pixelBuffer[index + 1]
                    let b = pixelBuffer[index + 2]
                    let a = pixelBuffer[index + 3]

                    if !isContentPixel(r: r, g: g, b: b, a: a) {
                        pixelBuffer[index + 3] = 0
                    }
                }
            }

            return true
        }

        guard rendered else {
            return nil
        }

        let pixelData = Data(pixels)
        guard let provider = CGDataProvider(data: pixelData as CFData) else {
            return nil
        }

        guard let outputCGImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return UIImage(cgImage: outputCGImage, scale: 1, orientation: .up)
    }

    private func writeImage(_ image: UIImage, to url: URL) throws {
        guard let data = image.pngData() else {
            throw AppError.fileImportFailed
        }

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try data.write(to: url, options: .atomic)
    }

    private func clampedCropRect(_ cropBounds: PixelRect, within canvas: CGRect) -> CGRect {
        let x = max(min(cropBounds.x, canvas.maxX - 1), canvas.minX)
        let y = max(min(cropBounds.y, canvas.maxY - 1), canvas.minY)
        let width = max(min(cropBounds.width, canvas.width), 1)
        let height = max(min(cropBounds.height, canvas.height), 1)
        return CGRect(x: x, y: y, width: width, height: height).intersection(canvas)
    }

    private func stampDirectory(for stampID: UUID) throws -> URL {
        let directory = try stampsRootDirectory().appendingPathComponent(stampID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private func stampsRootDirectory() throws -> URL {
        let appSupport = try applicationSupportDirectory()
        let stampsDirectory = appSupport.appendingPathComponent("Stamps", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stampsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return stampsDirectory
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.fileImportFailed
        }

        let directory = baseURL.appendingPathComponent("PDFSealMaster", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private func normalizedExtension(_ fileExtension: String) -> String {
        let normalized = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? "png" : normalized
    }

    private struct NormalizationArtifactPaths {
        let normalizedImagePath: String
        let maskPath: String
    }

    private struct NormalizationMaskRecord: Codable {
        var originalPixelSize: PixelRect?
        var cropBounds: PixelRect
        var updatedAt: Date
    }
}
