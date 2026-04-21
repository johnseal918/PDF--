import Foundation
import ImageIO
import PDFKit

protocol DocumentService {
    func importDocument(from url: URL) async throws -> DocumentModel
    func importImages(from urls: [URL]) async throws -> DocumentModel
}

struct DefaultDocumentService: DocumentService {
    func importDocument(from url: URL) async throws -> DocumentModel {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AppError.fileImportFailed
        }

        guard url.pathExtension.lowercased() == "pdf" else {
            throw AppError.unsupportedFileType
        }

        guard let pageSizes = loadPDFPageSizes(from: url), !pageSizes.isEmpty else {
            throw AppError.fileImportFailed
        }

        let documentID = UUID()
        do {
            let storedSourceURL = try storeImportedPDF(url, documentID: documentID)
            let pages = pageSizes.enumerated().map { index, size in
                A4Normalizer.normalize(
                    originalSize: size,
                    sourcePath: storedSourceURL.path,
                    pageIndex: index
                )
            }

            return DocumentModel(
                id: documentID,
                name: url.deletingPathExtension().lastPathComponent,
                sourceType: .pdf,
                pages: pages,
                editorObjects: [],
                bindingStampPlacement: nil,
                previewMode: .original,
                draftVersion: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        } catch {
            try? removeImportedDocumentDirectory(for: documentID)
            throw error
        }
    }

    func importImages(from urls: [URL]) async throws -> DocumentModel {
        guard !urls.isEmpty else {
            throw AppError.fileImportFailed
        }

        let documentID = UUID()
        do {
            let storedImageURLs: [URL] = try urls.enumerated().map { index, url in
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw AppError.fileImportFailed
                }

                return try storeImportedImage(url, documentID: documentID, pageIndex: index)
            }

            let resolvedPages: [PageModel] = try storedImageURLs.enumerated().map { index, url in
                guard let size = loadImageSize(from: url) else {
                    throw AppError.fileImportFailed
                }

                return A4Normalizer.normalize(
                    originalSize: size,
                    sourcePath: url.path,
                    pageIndex: index
                )
            }

            return DocumentModel(
                id: documentID,
                name: urls.first?.deletingPathExtension().lastPathComponent ?? "images",
                sourceType: .images,
                pages: resolvedPages,
                editorObjects: [],
                bindingStampPlacement: nil,
                previewMode: .original,
                draftVersion: 1,
                createdAt: Date(),
                updatedAt: Date()
            )
        } catch {
            try? removeImportedDocumentDirectory(for: documentID)
            throw error
        }
    }

    private func loadPDFPageSizes(from url: URL) -> [PaperSize]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            return nil
        }

        return (0..<document.pageCount).compactMap { index in
            guard let page = document.page(at: index) else {
                return nil
            }

            let bounds = page.bounds(for: .mediaBox)
            return PaperSize(width: max(bounds.width, 1), height: max(bounds.height, 1))
        }
    }

    private func loadImageSize(from url: URL) -> PaperSize? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return ImageFileInspector.displayPixelSize(for: url)
    }

    private func storeImportedPDF(_ sourceURL: URL, documentID: UUID) throws -> URL {
        let documentDirectory = try importedDocumentDirectory(for: documentID)
        let destinationURL = documentDirectory.appendingPathComponent("source.pdf", isDirectory: false)
        try copyFile(from: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func storeImportedImage(
        _ sourceURL: URL,
        documentID: UUID,
        pageIndex: Int
    ) throws -> URL {
        let fileExtension = normalizedExtension(sourceURL.pathExtension)
        let sourceDirectory = try importedSourceDirectory(for: documentID)
        let pageNumber = String(format: "%03d", pageIndex + 1)
        let destinationURL = sourceDirectory.appendingPathComponent("page-\(pageNumber).\(fileExtension)", isDirectory: false)
        try copyFile(from: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    private func importedDocumentDirectory(for documentID: UUID) throws -> URL {
        let directory = try documentsRootDirectory().appendingPathComponent(documentID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private func removeImportedDocumentDirectory(for documentID: UUID) throws {
        let directory = try documentRootDirectory(for: documentID)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return
        }

        try FileManager.default.removeItem(at: directory)
    }

    private func documentRootDirectory(for documentID: UUID) throws -> URL {
        try documentsRootDirectory().appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    private func importedSourceDirectory(for documentID: UUID) throws -> URL {
        let directory = try importedDocumentDirectory(for: documentID)
            .appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory
    }

    private func documentsRootDirectory() throws -> URL {
        let applicationSupportURL = try applicationSupportDirectory()
        let documentsURL = applicationSupportURL
            .appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: documentsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return documentsURL
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.fileImportFailed
        }

        let appSupportURL = baseURL
            .appendingPathComponent("PDFSealMaster", isDirectory: true)
        try FileManager.default.createDirectory(
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
        return normalized.isEmpty ? "dat" : normalized
    }
}
