import XCTest
@testable import PDFSealMaster

@MainActor
final class EditorViewModelM3Tests: XCTestCase {
    func testUnifyStampSizesGloballySyncsBindingStampTargetWidth() async {
        let assetID = UUID()
        let page0 = makePage(index: 0)
        let page1 = makePage(index: 1)

        let basePlacement = StampPlacement(
            pageIndex: 0,
            assetID: assetID,
            originXMM: 10,
            originYMM: 10,
            widthMM: 30,
            heightMM: 30,
            rotation: 0,
            opacity: 0.9,
            zIndex: 0,
            aspectRatioLocked: true
        )

        let secondPlacement = StampPlacement(
            pageIndex: 1,
            assetID: assetID,
            originXMM: 20,
            originYMM: 20,
            widthMM: 50,
            heightMM: 50,
            rotation: 0,
            opacity: 0.9,
            zIndex: 1,
            aspectRatioLocked: true
        )

        let firstObject = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: basePlacement,
            signaturePlacement: nil
        )

        let secondObject = EditorObject(
            pageIndex: 1,
            type: .stamp,
            zIndex: 1,
            isSelected: false,
            stampPlacement: secondPlacement,
            signaturePlacement: nil
        )

        let bindingPlacement = BindingStampPlacement(
            assetID: assetID,
            startPage: 0,
            endPage: 1,
            targetWidthMM: 88,
            marginMM: 3,
            lossMM: 0.5,
            rotation: 0,
            yOffsetMM: 0,
            enabled: true
        )

        let now = Date()
        let session = EditorSession(
            document: DocumentModel(
                id: UUID(),
                name: "m3-test",
                sourceType: .pdf,
                pages: [page0, page1],
                editorObjects: [firstObject, secondObject],
                bindingStampPlacement: bindingPlacement,
                previewMode: .original,
                draftVersion: 1,
                createdAt: now,
                updatedAt: now
            ),
            selectedObjectID: firstObject.id,
            activePageIndex: 0
        )

        let viewModel = EditorViewModel(
            session: session,
            draftRecoveryService: InMemoryDraftRecoveryService(),
            stampAssetService: InMemoryStampAssetService(seedAssets: []),
            signatureAssetService: InMemorySignatureAssetService(),
            pdfExportService: DummyPDFExportService(),
            issueLogService: NoopIssueLogService()
        )

        await viewModel.unifyStampSizesGlobally()

        let syncedTargetWidth = viewModel.document.bindingStampPlacement?.targetWidthMM
        XCTAssertEqual(syncedTargetWidth ?? 0, 30, accuracy: 0.0001)

        let page1Stamp = viewModel.document.editorObjects
            .first(where: { $0.pageIndex == 1 })?
            .stampPlacement
        XCTAssertEqual(page1Stamp?.widthMM ?? 0, 30, accuracy: 0.0001)
        XCTAssertEqual(page1Stamp?.heightMM ?? 0, 30, accuracy: 0.0001)
    }

    private func makePage(index: Int) -> PageModel {
        PageModel(
            index: index,
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
    }
}

private actor NoopIssueLogService: IssueLogService {
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

private struct DummyPDFExportService: PDFExportService {
    func export(session: EditorSession) async throws -> URL {
        URL(fileURLWithPath: "/tmp/dummy.pdf")
    }
}
