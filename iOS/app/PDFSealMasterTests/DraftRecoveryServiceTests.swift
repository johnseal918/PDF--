import XCTest
@testable import PDFSealMaster

final class DraftRecoveryServiceTests: XCTestCase {
    func testRestoreLatestDraftReturnsMostRecentlyUpdatedSession() async throws {
        let service = InMemoryDraftRecoveryService()

        let older = makeSession(
            documentName: "older",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            signaturePlacementCounts: [:]
        )
        let newer = makeSession(
            documentName: "newer",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            signaturePlacementCounts: [:]
        )

        try await service.saveDraft(session: older)
        try await service.saveDraft(session: newer)

        let restored = try await service.restoreLatestDraft()
        XCTAssertEqual(restored?.document.id, newer.document.id)
        XCTAssertEqual(restored?.document.name, "newer")
    }

    func testInspectSignatureUsageAggregatesAcrossDrafts() async throws {
        let service = InMemoryDraftRecoveryService()
        let targetAssetID = UUID()
        let otherAssetID = UUID()

        let doc1 = makeSession(
            documentName: "doc-1",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_200),
            signaturePlacementCounts: [
                targetAssetID: 2,
                otherAssetID: 1
            ]
        )
        let doc2 = makeSession(
            documentName: "doc-2",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
            signaturePlacementCounts: [
                targetAssetID: 1
            ]
        )
        let doc3 = makeSession(
            documentName: "doc-3",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_400),
            signaturePlacementCounts: [
                otherAssetID: 4
            ]
        )

        try await service.saveDraft(session: doc1)
        try await service.saveDraft(session: doc2)
        try await service.saveDraft(session: doc3)

        let usage = try await service.inspectSignatureAssetUsage(assetID: targetAssetID)
        XCTAssertEqual(usage.referencedDraftCount, 2)
        XCTAssertEqual(usage.referencedPlacementCount, 3)
        XCTAssertEqual(usage.referencedDrafts.map(\.documentName), ["doc-2", "doc-1"])
        XCTAssertEqual(usage.sampleDocumentNames, ["doc-2", "doc-1"])
    }

    func testEditorSessionSignatureReceiptMessageRoundTrip() throws {
        let expectedReceipt = "[12:34:56] Global replace: 3 object(s), page(s): 1,2, remaining missing: 0"
        let session = makeSession(
            documentName: "receipt-doc",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_500),
            signaturePlacementCounts: [:],
            signatureReplaceReceiptMessage: expectedReceipt
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(session)
        let restored = try decoder.decode(EditorSession.self, from: data)

        XCTAssertEqual(restored.signatureReplaceReceiptMessage, expectedReceipt)
    }

    private func makeSession(
        documentName: String,
        updatedAt: Date,
        signaturePlacementCounts: [UUID: Int],
        signatureReplaceReceiptMessage: String = "No receipt yet."
    ) -> EditorSession {
        let page = PageModel(
            index: 0,
            originalSizePT: .a4,
            a4CanvasSizePT: .a4,
            contentRectInA4PT: PaperRect(
                origin: PaperPoint(x: 0, y: 0),
                size: .a4
            ),
            originalToA4Transform: PaperTransform(
                scaleX: 1,
                scaleY: 1,
                translateX: 0,
                translateY: 0
            ),
            previewImagePath: nil,
            thumbnailPath: nil,
            originalSourcePath: "sample.pdf"
        )

        var editorObjects: [EditorObject] = []
        var zIndex = 0
        for (assetID, count) in signaturePlacementCounts {
            for _ in 0..<count {
                let placement = SignaturePlacement(
                    pageIndex: 0,
                    assetID: assetID,
                    originXMM: 10,
                    originYMM: 20,
                    widthMM: 30,
                    heightMM: 12,
                    rotation: 0,
                    opacity: 1,
                    zIndex: zIndex
                )
                editorObjects.append(
                    EditorObject(
                        pageIndex: 0,
                        type: .signature,
                        zIndex: zIndex,
                        isSelected: false,
                        stampPlacement: nil,
                        signaturePlacement: placement
                    )
                )
                zIndex += 1
            }
        }

        let document = DocumentModel(
            id: UUID(),
            name: documentName,
            sourceType: .pdf,
            pages: [page],
            editorObjects: editorObjects,
            bindingStampPlacement: nil,
            previewMode: .original,
            draftVersion: 1,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )

        return EditorSession(
            schemaVersion: 1,
            document: document,
            selectedObjectID: nil,
            activePageIndex: 0,
            signatureReplaceReceiptMessage: signatureReplaceReceiptMessage
        )
    }
}
