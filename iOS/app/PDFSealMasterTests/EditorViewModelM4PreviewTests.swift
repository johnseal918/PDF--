import XCTest
@testable import PDFSealMaster

@MainActor
final class EditorViewModelM4PreviewTests: XCTestCase {
    func testTogglePreviewModeDoesNotChangeSelectedStampPlacement() {
        let assetID = UUID()
        let selectedObject = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: assetID,
                originXMM: 28,
                originYMM: 36,
                widthMM: 32,
                heightMM: 32,
                rotation: 0,
                opacity: 0.9,
                zIndex: 0,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let session = EditorSession(
            document: DocumentModel(
                id: UUID(),
                name: "m4-preview-test",
                sourceType: .pdf,
                pages: [makePage(index: 0)],
                editorObjects: [selectedObject],
                bindingStampPlacement: nil,
                previewMode: .original,
                draftVersion: 1,
                createdAt: Date(),
                updatedAt: Date()
            ),
            selectedObjectID: selectedObject.id,
            activePageIndex: 0
        )

        let viewModel = EditorViewModel(
            session: session,
            draftRecoveryService: InMemoryDraftRecoveryService(),
            stampAssetService: InMemoryStampAssetService(seedAssets: []),
            signatureAssetService: InMemorySignatureAssetService(),
            pdfExportService: M4DummyPDFExportService(),
            issueLogService: M4NoopIssueLogService()
        )

        let before = viewModel.selectedStampPlacement
        viewModel.togglePreviewMode()
        let after = viewModel.selectedStampPlacement

        XCTAssertEqual(viewModel.document.previewMode, .matchedLowRes)
        XCTAssertEqual(before?.originXMM ?? 0, after?.originXMM ?? 0, accuracy: 0.0001)
        XCTAssertEqual(before?.originYMM ?? 0, after?.originYMM ?? 0, accuracy: 0.0001)
        XCTAssertEqual(before?.widthMM ?? 0, after?.widthMM ?? 0, accuracy: 0.0001)
        XCTAssertEqual(before?.heightMM ?? 0, after?.heightMM ?? 0, accuracy: 0.0001)
    }

    func testPreviewJudgementWarnsForTinySignatureInMatchedLowResMode() {
        let signatureObject = EditorObject(
            pageIndex: 0,
            type: .signature,
            zIndex: 0,
            isSelected: true,
            stampPlacement: nil,
            signaturePlacement: SignaturePlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 20,
                originYMM: 20,
                widthMM: 12,
                heightMM: 4,
                rotation: 0,
                opacity: 1,
                zIndex: 0
            )
        )

        let session = EditorSession(
            document: DocumentModel(
                id: UUID(),
                name: "m4-preview-warning",
                sourceType: .pdf,
                pages: [makePage(index: 0)],
                editorObjects: [signatureObject],
                bindingStampPlacement: nil,
                previewMode: .original,
                draftVersion: 1,
                createdAt: Date(),
                updatedAt: Date()
            ),
            selectedObjectID: signatureObject.id,
            activePageIndex: 0
        )

        let viewModel = EditorViewModel(
            session: session,
            draftRecoveryService: InMemoryDraftRecoveryService(),
            stampAssetService: InMemoryStampAssetService(seedAssets: []),
            signatureAssetService: InMemorySignatureAssetService(),
            pdfExportService: M4DummyPDFExportService(),
            issueLogService: M4NoopIssueLogService()
        )

        viewModel.togglePreviewMode()
        XCTAssertTrue(viewModel.previewJudgementIsWarning)
    }

    private func makePage(index: Int) -> PageModel {
        PageModel(
            index: index,
            originalSizePT: .a4,
            a4CanvasSizePT: .a4,
            contentRectInA4PT: PaperRect(
                origin: PaperPoint(x: 0, y: 0),
                size: PaperSize(width: 560, height: 810)
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
    }
}

private actor M4NoopIssueLogService: IssueLogService {
    func record(
        level: IssueLogLevel,
        category: IssueLogCategory,
        message: String,
        context: [String: String]
    ) async {}

    func recordError(
        _ message: String,
        error: Error,
        category: IssueLogCategory,
        context: [String: String]
    ) async {}

    func recordFeedback(
        _ message: String,
        category: IssueLogCategory,
        context: [String: String]
    ) async {}
}

private struct M4DummyPDFExportService: PDFExportService {
    func export(session: EditorSession) async throws -> URL {
        URL(fileURLWithPath: "/tmp/dummy.pdf")
    }
}
