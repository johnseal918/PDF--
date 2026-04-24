import XCTest
@testable import PDFSealMaster

@MainActor
final class EditorViewModelM6PreviewAppearanceTests: XCTestCase {
    func testTogglePreviewAppearanceDoesNotChangeSelectedStampPlacement() {
        let stampObject = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 32,
                originYMM: 48,
                widthMM: 36,
                heightMM: 36,
                rotation: 0,
                opacity: 0.9,
                zIndex: 0,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let session = EditorSession(
            document: makeDocument(objects: [stampObject]),
            selectedObjectID: stampObject.id,
            activePageIndex: 0
        )

        let viewModel = EditorViewModel(
            session: session,
            draftRecoveryService: InMemoryDraftRecoveryService(),
            stampAssetService: InMemoryStampAssetService(seedAssets: []),
            signatureAssetService: InMemorySignatureAssetService(),
            pdfExportService: M6DummyPDFExportService(),
            issueLogService: M6NoopIssueLogService()
        )

        let before = viewModel.selectedStampPlacement
        viewModel.togglePreviewAppearance()
        let after = viewModel.selectedStampPlacement

        XCTAssertEqual(viewModel.previewAppearanceDisplayText, "灰度扫描风")
        XCTAssertTrue(viewModel.isScanPreviewEnabled)
        XCTAssertEqual(viewModel.document.previewMode, .original)
        XCTAssertEqual(before?.originXMM ?? 0, after?.originXMM ?? 0, accuracy: 0.0001)
        XCTAssertEqual(before?.originYMM ?? 0, after?.originYMM ?? 0, accuracy: 0.0001)
        XCTAssertEqual(before?.widthMM ?? 0, after?.widthMM ?? 0, accuracy: 0.0001)
        XCTAssertEqual(before?.heightMM ?? 0, after?.heightMM ?? 0, accuracy: 0.0001)
    }

    func testLegacySessionWithoutPreviewAppearanceDefaultsToStandard() throws {
        let session = EditorSession(
            document: makeDocument(objects: []),
            selectedObjectID: nil,
            activePageIndex: 0
        )

        let encoder = JSONEncoder()
        let originalData = try encoder.encode(session)
        let originalJSON = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: originalData) as? [String: Any]
        )

        var legacyJSON = originalJSON
        legacyJSON.removeValue(forKey: "previewAppearance")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSON)

        let decoded = try JSONDecoder().decode(EditorSession.self, from: legacyData)
        XCTAssertEqual(decoded.previewAppearance, .standard)
    }

    private func makeDocument(objects: [EditorObject]) -> DocumentModel {
        DocumentModel(
            id: UUID(),
            name: "m6-preview-appearance",
            sourceType: .pdf,
            pages: [
                PageModel(
                    index: 0,
                    originalSizePT: .a4,
                    a4CanvasSizePT: .a4,
                    contentRectInA4PT: PaperRect(
                        origin: PaperPoint(x: 0, y: 0),
                        size: PaperSize(width: 560, height: 810)
                    ),
                    originalToA4Transform: PaperTransform(scaleX: 1, scaleY: 1, translateX: 0, translateY: 0),
                    previewImagePath: nil,
                    thumbnailPath: nil,
                    originalSourcePath: "sample.pdf"
                )
            ],
            editorObjects: objects,
            bindingStampPlacement: nil,
            previewMode: .original,
            draftVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

private actor M6NoopIssueLogService: IssueLogService {
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

private struct M6DummyPDFExportService: PDFExportService {
    func export(session: EditorSession) async throws -> URL {
        URL(fileURLWithPath: "/tmp/m6-dummy.pdf")
    }
}
