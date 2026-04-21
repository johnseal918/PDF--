import Foundation

enum ImportStagingError: Error {
    case invalidSource
    case writeFailed
}

enum ImportStagingService {
    private static let rootFolderName = "ImportStaging"

    static func stageExternalFile(
        _ url: URL,
        preferredExtension: String? = nil
    ) throws -> URL {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportStagingError.invalidSource
        }

        let fileExtension = normalizedExtension(preferredExtension ?? url.pathExtension)
        let destinationURL = makeDestinationURL(fileExtension: fileExtension)
        try ensureStagingDirectoryExists(at: destinationURL.deletingLastPathComponent())
        try FileManager.default.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    static func stageData(
        _ data: Data,
        fileExtension: String
    ) throws -> URL {
        guard !data.isEmpty else {
            throw ImportStagingError.invalidSource
        }

        let destinationURL = makeDestinationURL(fileExtension: normalizedExtension(fileExtension))
        try ensureStagingDirectoryExists(at: destinationURL.deletingLastPathComponent())
        do {
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw ImportStagingError.writeFailed
        }
        return destinationURL
    }

    private static func makeDestinationURL(fileExtension: String) -> URL {
        let fileName = "\(UUID().uuidString).\(fileExtension)"
        return stagingRootDirectory().appendingPathComponent(fileName, isDirectory: false)
    }

    private static func stagingRootDirectory() -> URL {
        let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent("PDFSealMaster", isDirectory: true)
            .appendingPathComponent(rootFolderName, isDirectory: true)
    }

    private static func ensureStagingDirectoryExists(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private static func normalizedExtension(_ fileExtension: String) -> String {
        let normalized = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? "dat" : normalized
    }
}
