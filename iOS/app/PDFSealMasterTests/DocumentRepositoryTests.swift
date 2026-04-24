import XCTest
@testable import PDFSealMaster

final class DocumentRepositoryTests: XCTestCase {
    func testInMemoryRepositoryReturnsMostRecentSummaries() async throws {
        let repository = InMemoryDocumentRepository()
        let older = makeDocument(name: "older", updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = makeDocument(name: "newer", updatedAt: Date(timeIntervalSince1970: 1_700_000_100))

        try await repository.save(document: older)
        try await repository.save(document: newer)

        let summaries = try await repository.loadRecentSummaries(limit: 10)
        XCTAssertEqual(summaries.map(\.documentName), ["newer", "older"])
    }

    func testFileRepositoryPersistsAndDeduplicatesByDocumentID() async throws {
        let tempRoot = makeTempRootDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repository = FileDocumentRepository(
            maxPersistedCount: 20,
            rootDirectoryProvider: { tempRoot }
        )

        var original = makeDocument(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "合同A",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        var updated = original
        updated.updatedAt = Date(timeIntervalSince1970: 1_700_000_500)

        try await repository.save(document: original)
        try await repository.save(document: updated)

        let reloadedRepository = FileDocumentRepository(
            maxPersistedCount: 20,
            rootDirectoryProvider: { tempRoot }
        )
        let allDocuments = try await reloadedRepository.loadAll()
        XCTAssertEqual(allDocuments.count, 1)
        XCTAssertEqual(allDocuments.first?.id, original.id)
        XCTAssertEqual(allDocuments.first?.updatedAt, updated.updatedAt)
    }

    func testFileRepositoryRemoveDocument() async throws {
        let tempRoot = makeTempRootDirectory()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repository = FileDocumentRepository(
            maxPersistedCount: 20,
            rootDirectoryProvider: { tempRoot }
        )

        let first = makeDocument(name: "first", updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let second = makeDocument(name: "second", updatedAt: Date(timeIntervalSince1970: 1_700_000_100))
        try await repository.save(document: first)
        try await repository.save(document: second)

        try await repository.remove(documentID: first.id)
        let summaries = try await repository.loadRecentSummaries(limit: 10)
        XCTAssertEqual(summaries.map(\.documentID), [second.id])
    }

    private func makeTempRootDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFSealMasterTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeDocument(
        id: UUID = UUID(),
        name: String,
        updatedAt: Date
    ) -> DocumentModel {
        let page = PageModel(
            index: 0,
            originalSizePT: .a4,
            a4CanvasSizePT: .a4,
            contentRectInA4PT: PaperRect(origin: PaperPoint(x: 0, y: 0), size: .a4),
            originalToA4Transform: PaperTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0),
            previewImagePath: nil,
            thumbnailPath: nil,
            originalSourcePath: "sample.pdf"
        )

        return DocumentModel(
            id: id,
            name: name,
            sourceType: .pdf,
            pages: [page],
            editorObjects: [],
            bindingStampPlacement: nil,
            previewMode: .original,
            draftVersion: 1,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
