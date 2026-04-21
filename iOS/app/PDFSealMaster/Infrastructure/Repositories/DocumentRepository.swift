import Foundation

protocol DocumentRepository {
    func save(document: DocumentModel) async throws
    func loadAll() async throws -> [DocumentModel]
}

final class InMemoryDocumentRepository: DocumentRepository {
    private var documents: [DocumentModel] = []

    func save(document: DocumentModel) async throws {
        documents.removeAll { $0.id == document.id }
        documents.append(document)
    }

    func loadAll() async throws -> [DocumentModel] {
        documents.sorted { $0.updatedAt > $1.updatedAt }
    }
}
