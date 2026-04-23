import Foundation
import UIKit
import PDFKit

enum PDFExportError: Error {
    case noPages
    case exportDirectoryUnavailable
    case writeFailed
}

protocol PDFExportService {
    func export(session: EditorSession) async throws -> URL
}

final class FilePDFExportService: PDFExportService {
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let bindingStampService: BindingStampService

    init(
        fileManager: FileManager = .default,
        bindingStampService: BindingStampService = DefaultBindingStampService()
    ) {
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.bindingStampService = bindingStampService
    }

    func export(session: EditorSession) async throws -> URL {
        guard !session.document.pages.isEmpty else {
            throw PDFExportError.noPages
        }

        let exportDirectory = try exportTempDirectory()
        do {
            try fileManager.createDirectory(
                at: exportDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw PDFExportError.exportDirectoryUnavailable
        }

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let safeName = session.document.name.isEmpty ? "document" : session.document.name
        let fileURL = exportDirectory.appendingPathComponent("\(safeName)-\(timestamp).pdf", isDirectory: false)

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(
                x: 0,
                y: 0,
                width: PaperSize.a4.width,
                height: PaperSize.a4.height
            )
        )

        let pdfDocumentsByPath = buildPDFDocumentCache(for: session.document)
        let stampAssetsByID = loadStampAssetsByID()
        let signatureAssetsByID = loadSignatureAssetsByID()

        do {
            try renderer.writePDF(to: fileURL) { context in
                for page in session.document.pages {
                    let pageBounds = CGRect(
                        x: 0,
                        y: 0,
                        width: page.a4CanvasSizePT.width,
                        height: page.a4CanvasSizePT.height
                    )

                    context.beginPage(withBounds: pageBounds, pageInfo: [:])
                    drawPage(
                        page,
                        in: pageBounds,
                        session: session,
                        pdfDocumentsByPath: pdfDocumentsByPath,
                        stampAssetsByID: stampAssetsByID,
                        signatureAssetsByID: signatureAssetsByID
                    )
                }
            }
        } catch {
            throw PDFExportError.writeFailed
        }

        return fileURL
    }

    private func drawPage(
        _ page: PageModel,
        in bounds: CGRect,
        session: EditorSession,
        pdfDocumentsByPath: [String: PDFDocument],
        stampAssetsByID: [UUID: StampAsset],
        signatureAssetsByID: [UUID: SignatureAsset]
    ) {
        UIColor.white.setFill()
        UIRectFill(bounds)

        let contentRect = CGRect(
            x: page.contentRectInA4PT.origin.x,
            y: page.contentRectInA4PT.origin.y,
            width: page.contentRectInA4PT.size.width,
            height: page.contentRectInA4PT.size.height
        )

        let didDrawDocumentContent = drawDocumentContent(
            for: page,
            in: contentRect,
            session: session,
            pdfDocumentsByPath: pdfDocumentsByPath
        )

        if !didDrawDocumentContent {
            UIColor.systemGray6.setFill()
            UIRectFill(contentRect)
            UIColor.systemGray4.setStroke()
            UIBezierPath(rect: contentRect).stroke()
            drawText(
                "\(session.document.name) - 页面内容占位",
                at: CGPoint(x: contentRect.minX + 20, y: contentRect.minY + 20),
                font: .systemFont(ofSize: 14)
            )
        }

        let pageObjects = session.document.editorObjects
            .filter { $0.pageIndex == page.index }
            .sorted { $0.zIndex < $1.zIndex }

        for object in pageObjects {
            if let stamp = object.stampPlacement {
                drawStamp(stamp, asset: stampAssetsByID[stamp.assetID])
            } else if let signature = object.signaturePlacement {
                drawSignature(signature, asset: signatureAssetsByID[signature.assetID])
            }
        }

        if let bindingPlacement = session.document.bindingStampPlacement {
            drawBindingStampIfNeeded(
                bindingPlacement,
                on: page,
                documentPageCount: session.document.pageCount,
                stampAsset: stampAssetsByID[bindingPlacement.assetID]
            )
        }
    }

    private func drawDocumentContent(
        for page: PageModel,
        in contentRect: CGRect,
        session: EditorSession,
        pdfDocumentsByPath: [String: PDFDocument]
    ) -> Bool {
        switch session.document.sourceType {
        case .pdf:
            guard let document = pdfDocumentsByPath[page.originalSourcePath] else {
                return false
            }
            return drawPDFPage(document: document, pageIndex: page.index, in: contentRect)
        case .images:
            return drawImagePage(atPath: page.originalSourcePath, in: contentRect)
        }
    }

    private func drawPDFPage(
        document: PDFDocument,
        pageIndex: Int,
        in rect: CGRect
    ) -> Bool {
        guard let context = UIGraphicsGetCurrentContext() else {
            return false
        }

        guard let pdfPage = document.page(at: pageIndex) else {
            return false
        }

        let mediaBox = pdfPage.bounds(for: .mediaBox)
        guard mediaBox.width > 0, mediaBox.height > 0 else {
            return false
        }

        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: rect.width / mediaBox.width, y: -rect.height / mediaBox.height)
        context.translateBy(x: -mediaBox.minX, y: -mediaBox.minY)
        pdfPage.draw(with: .mediaBox, to: context)
        context.restoreGState()
        return true
    }

    private func drawImagePage(atPath path: String, in rect: CGRect) -> Bool {
        guard let image = UIImage(contentsOfFile: path) else {
            return false
        }

        image.draw(in: rect)
        return true
    }

    private func drawStamp(_ stamp: StampPlacement, asset: StampAsset?) {
        let rect = CGRect(
            x: stamp.originXMM * A4Measurement.pointsPerMillimeter,
            y: stamp.originYMM * A4Measurement.pointsPerMillimeter,
            width: stamp.widthMM * A4Measurement.pointsPerMillimeter,
            height: stamp.heightMM * A4Measurement.pointsPerMillimeter
        )

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.setAlpha(stamp.opacity)
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(stamp.rotation * .pi / 180.0))
        context.translateBy(x: -rect.midX, y: -rect.midY)

        if
            let asset,
            let stampImage = renderedStampImage(for: asset)
        {
            stampImage.draw(in: rect)
            context.restoreGState()
            return
        }

        let stampColor = UIColor.systemRed.withAlphaComponent(0.8)
        stampColor.setStroke()
        let ellipse = UIBezierPath(ovalIn: rect)
        ellipse.lineWidth = 2
        ellipse.stroke()

        drawText(
            "印章",
            at: CGPoint(x: rect.midX - 14, y: rect.midY - 8),
            font: .boldSystemFont(ofSize: max(rect.width * 0.12, 10)),
            color: stampColor
        )

        context.restoreGState()
    }

    private func preferredStampImagePath(for asset: StampAsset) -> String? {
        if let normalizedPath = asset.normalizedTransparentImagePath, !normalizedPath.isEmpty {
            return normalizedPath
        }

        return asset.originalImagePath.isEmpty ? nil : asset.originalImagePath
    }

    private func renderedStampImage(for asset: StampAsset) -> UIImage? {
        if
            let normalizedPath = asset.normalizedTransparentImagePath,
            !normalizedPath.isEmpty,
            fileManager.fileExists(atPath: normalizedPath),
            let normalizedImage = UIImage(contentsOfFile: normalizedPath)
        {
            return normalizedImage
        }

        guard let imagePath = preferredStampImagePath(for: asset) else {
            return nil
        }

        guard let image = UIImage(contentsOfFile: imagePath) else {
            return nil
        }

        guard let cropBounds = loadNormalizationCropBounds(for: asset) ?? asset.effectiveBoundsPX else {
            return image
        }

        guard let cgImage = ImageFileInspector.normalizedCGImage(from: image) else {
            return image
        }

        let fullBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)

        let clampedCrop = CGRect(
            x: max(min(cropBounds.x, Double(cgImage.width - 1)), 0),
            y: max(min(cropBounds.y, Double(cgImage.height - 1)), 0),
            width: max(min(cropBounds.width, Double(cgImage.width)), 1),
            height: max(min(cropBounds.height, Double(cgImage.height)), 1)
        ).intersection(fullBounds)

        guard !clampedCrop.isNull, clampedCrop.width > 0, clampedCrop.height > 0 else {
            return image
        }

        guard let croppedCGImage = cgImage.cropping(to: clampedCrop) else {
            return image
        }

        return UIImage(cgImage: croppedCGImage, scale: 1, orientation: .up)
    }

    private func loadNormalizationCropBounds(for asset: StampAsset) -> PixelRect? {
        guard let maskPath = asset.normalizationMaskPath, !maskPath.isEmpty else {
            return nil
        }

        let maskURL = URL(fileURLWithPath: maskPath)
        guard fileManager.fileExists(atPath: maskURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: maskURL) else {
            return nil
        }

        guard let record = try? decoder.decode(NormalizationMaskRecord.self, from: data) else {
            return nil
        }

        return record.cropBounds
    }

    private func drawSignature(_ signature: SignaturePlacement, asset: SignatureAsset?) {
        let rect = CGRect(
            x: signature.originXMM * A4Measurement.pointsPerMillimeter,
            y: signature.originYMM * A4Measurement.pointsPerMillimeter,
            width: signature.widthMM * A4Measurement.pointsPerMillimeter,
            height: signature.heightMM * A4Measurement.pointsPerMillimeter
        )

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.setAlpha(signature.opacity)
        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: CGFloat(signature.rotation * .pi / 180.0))
        context.translateBy(x: -rect.midX, y: -rect.midY)

        if
            let asset,
            let signatureImage = renderedSignatureImage(for: asset)
        {
            signatureImage.draw(in: rect)
            context.restoreGState()
            return
        }

        drawText(
            "签名",
            at: CGPoint(x: rect.minX, y: rect.minY),
            font: .italicSystemFont(ofSize: max(signature.heightMM * A4Measurement.pointsPerMillimeter * 0.45, 12)),
            color: UIColor.label.withAlphaComponent(signature.opacity * 0.8)
        )
        context.restoreGState()
    }

    private func drawBindingStampIfNeeded(
        _ placement: BindingStampPlacement,
        on page: PageModel,
        documentPageCount: Int,
        stampAsset: StampAsset?
    ) {
        let pageSizeMM = page.a4CanvasSizePT.asMillimeterSize
        guard let plan = bindingStampService.drawPlan(
            for: page.index,
            documentPageCount: documentPageCount,
            pageSizeMM: pageSizeMM,
            placement: placement,
            aspectRatio: stampAsset?.defaultAspectRatio
        ) else {
            return
        }

        let drawRect = CGRect(
            x: plan.originXMM * A4Measurement.pointsPerMillimeter,
            y: plan.originYMM * A4Measurement.pointsPerMillimeter,
            width: plan.widthMM * A4Measurement.pointsPerMillimeter,
            height: plan.heightMM * A4Measurement.pointsPerMillimeter
        )

        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        context.saveGState()
        context.setAlpha(0.9)
        context.translateBy(x: drawRect.midX, y: drawRect.midY)
        context.rotate(by: CGFloat(plan.rotation * .pi / 180.0))
        context.translateBy(x: -drawRect.midX, y: -drawRect.midY)

        if
            let stampAsset,
            let renderedImage = renderedStampImage(for: stampAsset),
            let sliceImage = bindingStampSliceImage(
                from: renderedImage,
                pageOffset: plan.pageOffset,
                pageCount: plan.pageCount
            )
        {
            sliceImage.draw(in: drawRect)
            context.restoreGState()
            return
        }

        let fallbackColor = UIColor.systemRed.withAlphaComponent(0.7)
        fallbackColor.setStroke()
        UIBezierPath(rect: drawRect).stroke()
        drawText(
            "骑缝章",
            at: CGPoint(x: drawRect.minX + 4, y: drawRect.midY - 8),
            font: .boldSystemFont(ofSize: 10),
            color: fallbackColor
        )

        context.restoreGState()
    }

    private func bindingStampSliceImage(
        from image: UIImage,
        pageOffset: Int,
        pageCount: Int
    ) -> UIImage? {
        guard pageCount > 0 else {
            return nil
        }

        guard let cgImage = ImageFileInspector.normalizedCGImage(from: image) else {
            return image
        }

        guard let crop = bindingStampService.sliceCrop(
            forImageWidth: cgImage.width,
            imageHeight: cgImage.height,
            pageOffset: pageOffset,
            pageCount: pageCount
        ) else {
            return nil
        }

        let cropRect = CGRect(
            x: crop.x,
            y: 0,
            width: crop.width,
            height: crop.height
        )

        guard let cropped = cgImage.cropping(to: cropRect) else {
            return image
        }

        return UIImage(cgImage: cropped, scale: 1, orientation: .up)
    }

    private func drawText(
        _ text: String,
        at point: CGPoint,
        font: UIFont,
        color: UIColor = .label
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        NSString(string: text).draw(at: point, withAttributes: attributes)
    }

    private func exportTempDirectory() throws -> URL {
        guard let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw PDFExportError.exportDirectoryUnavailable
        }

        return cachesURL
            .appendingPathComponent("PDFSealMaster", isDirectory: true)
            .appendingPathComponent("ExportTemp", isDirectory: true)
    }

    private func buildPDFDocumentCache(for document: DocumentModel) -> [String: PDFDocument] {
        guard document.sourceType == .pdf else {
            return [:]
        }

        let uniquePaths = Set(document.pages.map(\.originalSourcePath))
        var cache: [String: PDFDocument] = [:]
        for path in uniquePaths {
            let url = URL(fileURLWithPath: path)
            guard let pdfDocument = PDFDocument(url: url) else {
                continue
            }
            cache[path] = pdfDocument
        }
        return cache
    }

    private func loadStampAssetsByID() -> [UUID: StampAsset] {
        guard let rootDirectory = try? stampsRootDirectory() else {
            return [:]
        }

        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return [:]
        }

        let directories = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var assetsByID: [UUID: StampAsset] = [:]
        for directory in directories {
            let stampFileURL = directory.appendingPathComponent("stamp.json", isDirectory: false)
            guard fileManager.fileExists(atPath: stampFileURL.path) else {
                continue
            }

            guard
                let data = try? Data(contentsOf: stampFileURL),
                let asset = try? decoder.decode(StampAsset.self, from: data)
            else {
                continue
            }

            assetsByID[asset.id] = asset
        }

        return assetsByID
    }

    private func loadSignatureAssetsByID() -> [UUID: SignatureAsset] {
        guard let rootDirectory = try? signaturesRootDirectory() else {
            return [:]
        }

        guard fileManager.fileExists(atPath: rootDirectory.path) else {
            return [:]
        }

        let directories = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var assetsByID: [UUID: SignatureAsset] = [:]
        for directory in directories {
            let signatureFileURL = directory.appendingPathComponent("signature.json", isDirectory: false)
            guard fileManager.fileExists(atPath: signatureFileURL.path) else {
                continue
            }

            guard
                let data = try? Data(contentsOf: signatureFileURL),
                let asset = try? decoder.decode(SignatureAsset.self, from: data)
            else {
                continue
            }

            assetsByID[asset.id] = asset
        }

        return assetsByID
    }

    private func preferredSignatureImagePath(for asset: SignatureAsset) -> String? {
        if let normalizedPath = asset.normalizedTransparentImagePath, !normalizedPath.isEmpty {
            return normalizedPath
        }

        return asset.originalSignaturePath.isEmpty ? nil : asset.originalSignaturePath
    }

    private func renderedSignatureImage(for asset: SignatureAsset) -> UIImage? {
        guard let imagePath = preferredSignatureImagePath(for: asset) else {
            return nil
        }

        return UIImage(contentsOfFile: imagePath)
    }

    private func stampsRootDirectory() throws -> URL {
        let applicationSupportDirectory = try appSupportDirectory()
        return applicationSupportDirectory.appendingPathComponent("Stamps", isDirectory: true)
    }

    private func signaturesRootDirectory() throws -> URL {
        let applicationSupportDirectory = try appSupportDirectory()
        return applicationSupportDirectory.appendingPathComponent("Signatures", isDirectory: true)
    }

    private func appSupportDirectory() throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PDFExportError.exportDirectoryUnavailable
        }

        return baseURL.appendingPathComponent("PDFSealMaster", isDirectory: true)
    }

    private struct NormalizationMaskRecord: Codable {
        var originalPixelSize: PixelRect?
        var cropBounds: PixelRect
        var updatedAt: Date
    }
}
