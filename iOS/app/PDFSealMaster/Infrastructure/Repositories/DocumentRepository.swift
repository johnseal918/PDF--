import Foundation

struct RecentDocumentSummary: Identifiable, Equatable {
    let id: UUID
    let documentID: UUID
    let documentName: String
    let sourceType: DocumentSourceType
    let updatedAt: Date
    let pageCount: Int
}

protocol DocumentRepository {
    func save(document: DocumentModel) async throws
    func load(documentID: UUID) async throws -> DocumentModel?
    func loadAll() async throws -> [DocumentModel]
    func loadRecentSummaries(limit: Int) async throws -> [RecentDocumentSummary]
    func remove(documentID: UUID) async throws
}

final class InMemoryDocumentRepository: DocumentRepository {
    private var documentsByID: [UUID: DocumentModel] = [:]

    func save(document: DocumentModel) async throws {
        documentsByID[document.id] = document
    }

    func load(documentID: UUID) async throws -> DocumentModel? {
        documentsByID[documentID]
    }

    func loadAll() async throws -> [DocumentModel] {
        documentsByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadRecentSummaries(limit: Int) async throws -> [RecentDocumentSummary] {
        try await loadAll()
            .prefix(max(limit, 0))
            .map(RecentDocumentSummary.init)
    }

    func remove(documentID: UUID) async throws {
        documentsByID.removeValue(forKey: documentID)
    }
}

final class FileDocumentRepository: DocumentRepository {
    private enum StorageError: Error {
        case invalidRootDirectory
        case applicationSupportUnavailable
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let maxPersistedCount: Int
    private let rootDirectoryProvider: () throws -> URL

    init(
        fileManager: FileManager = .default,
        maxPersistedCount: Int = 50,
        rootDirectoryProvider: (() throws -> URL)? = nil
    ) {
        self.fileManager = fileManager
        self.maxPersistedCount = max(maxPersistedCount, 1)
        self.rootDirectoryProvider = rootDirectoryProvider ?? {
            guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw StorageError.applicationSupportUnavailable
            }

            let appSupportURL = baseURL
                .appendingPathComponent("PDFSealMaster", isDirectory: true)
                .appendingPathComponent("Documents", isDirectory: true)
            return appSupportURL
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    func save(document: DocumentModel) async throws {
        var documents = try loadStoredDocuments()
        documents.removeAll { $0.id == document.id }
        documents.append(document)
        let sortedDocuments = documents
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxPersistedCount)
        try persist(Array(sortedDocuments))
    }

    func load(documentID: UUID) async throws -> DocumentModel? {
        try loadStoredDocuments().first { $0.id == documentID }
    }

    func loadAll() async throws -> [DocumentModel] {
        try loadStoredDocuments().sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadRecentSummaries(limit: Int) async throws -> [RecentDocumentSummary] {
        try await loadAll()
            .prefix(max(limit, 0))
            .map(RecentDocumentSummary.init)
    }

    func remove(documentID: UUID) async throws {
        let filtered = try loadStoredDocuments().filter { $0.id != documentID }
        try persist(filtered)
    }

    private func loadStoredDocuments() throws -> [DocumentModel] {
        let indexURL = try indexFileURL()
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        let decoded = try decoder.decode([DocumentModel].self, from: data)
        return deduplicatedSortedDocuments(decoded)
    }

    private func persist(_ documents: [DocumentModel]) throws {
        let normalizedDocuments = deduplicatedSortedDocuments(documents)
        let indexURL = try indexFileURL()
        try ensureDirectoryExists(at: indexURL.deletingLastPathComponent())
        let data = try encoder.encode(normalizedDocuments)
        try data.write(to: indexURL, options: .atomic)
    }

    private func deduplicatedSortedDocuments(_ documents: [DocumentModel]) -> [DocumentModel] {
        var seenIDs = Set<UUID>()
        let sorted = documents.sorted { $0.updatedAt > $1.updatedAt }
        return sorted.filter { document in
            let inserted = seenIDs.insert(document.id).inserted
            return inserted
        }
    }

    private func indexFileURL() throws -> URL {
        let rootDirectory = try rootDirectoryProvider()
        guard !rootDirectory.path.isEmpty else {
            throw StorageError.invalidRootDirectory
        }
        return rootDirectory.appendingPathComponent("recent_documents.json", isDirectory: false)
    }

    private func ensureDirectoryExists(at directoryURL: URL) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }
}

private extension RecentDocumentSummary {
    init(document: DocumentModel) {
        self.id = document.id
        self.documentID = document.id
        self.documentName = document.name
        self.sourceType = document.sourceType
        self.updatedAt = document.updatedAt
        self.pageCount = document.pageCount
    }
}
