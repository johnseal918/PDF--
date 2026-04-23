import XCTest
@testable import PDFSealMaster

@MainActor
final class EditorViewModelM5EntitlementTests: XCTestCase {
    func testExportPresentsPaywallForFreeUser() async {
        let exportService = M5SpyPDFExportService()
        let viewModel = makeViewModel(
            purchaseService: InMemoryPurchaseService(initialState: .free),
            exportService: exportService
        )

        await viewModel.exportPDF()

        XCTAssertTrue(viewModel.isPaywallPresented)
        XCTAssertEqual(viewModel.activePaywallTrigger, .export)
        let exportCalls = await exportService.exportCallCount()
        XCTAssertEqual(exportCalls, 0)
    }

    func testPurchaseUnlocksExportAfterPaywall() async {
        let exportService = M5SpyPDFExportService()
        let viewModel = makeViewModel(
            purchaseService: InMemoryPurchaseService(initialState: .free),
            exportService: exportService
        )

        await viewModel.exportPDF()
        XCTAssertTrue(viewModel.isPaywallPresented)

        await viewModel.purchaseProFromPaywall()
        XCTAssertEqual(viewModel.entitlementState, .pro)
        XCTAssertFalse(viewModel.isPaywallPresented)

        await viewModel.exportPDF()
        let exportCalls = await exportService.exportCallCount()
        XCTAssertEqual(exportCalls, 1)
    }

    func testUnifyStampSizePresentsPaywallForFreeUser() async {
        let exportService = M5SpyPDFExportService()
        let viewModel = makeViewModel(
            purchaseService: InMemoryPurchaseService(initialState: .free),
            exportService: exportService
        )

        await viewModel.unifyStampSizesOnActivePage()

        XCTAssertTrue(viewModel.isPaywallPresented)
        XCTAssertEqual(viewModel.activePaywallTrigger, .unifyStampSize)
        XCTAssertEqual(viewModel.stampSizeSyncStatusMessage, "统一尺寸需要专业版。")
    }

    func testEnableBindingStampPresentsPaywallForFreeUser() async {
        let exportService = M5SpyPDFExportService()
        let viewModel = makeViewModel(
            purchaseService: InMemoryPurchaseService(initialState: .free),
            exportService: exportService
        )

        await viewModel.toggleBindingStampEnabled()

        XCTAssertTrue(viewModel.isPaywallPresented)
        XCTAssertEqual(viewModel.activePaywallTrigger, .bindingStamp)
        XCTAssertFalse(viewModel.bindingStampEnabled)
    }

    private func makeViewModel(
        purchaseService: PurchaseService,
        exportService: PDFExportService
    ) -> EditorViewModel {
        let now = Date()
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

        let stampAssetID = UUID()
        let selectedStamp = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: stampAssetID,
                originXMM: 20,
                originYMM: 20,
                widthMM: 30,
                heightMM: 30,
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let anotherStamp = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 1,
            isSelected: false,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: stampAssetID,
                originXMM: 60,
                originYMM: 40,
                widthMM: 45,
                heightMM: 45,
                rotation: 0,
                opacity: 1,
                zIndex: 1,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let session = EditorSession(
            document: DocumentModel(
                id: UUID(),
                name: "m5-entitlement",
                sourceType: .pdf,
                pages: [page],
                editorObjects: [selectedStamp, anotherStamp],
                bindingStampPlacement: nil,
                previewMode: .original,
                draftVersion: 1,
                createdAt: now,
                updatedAt: now
            ),
            selectedObjectID: selectedStamp.id,
            activePageIndex: 0
        )

        return EditorViewModel(
            session: session,
            draftRecoveryService: InMemoryDraftRecoveryService(),
            stampAssetService: InMemoryStampAssetService(seedAssets: []),
            signatureAssetService: InMemorySignatureAssetService(),
            pdfExportService: exportService,
            purchaseService: purchaseService,
            issueLogService: M5NoopIssueLogService()
        )
    }
}

private actor M5NoopIssueLogService: IssueLogService {
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

private actor M5SpyPDFExportService: PDFExportService {
    private var calls = 0

    func export(session: EditorSession) async throws -> URL {
        _ = session
        calls += 1
        return URL(fileURLWithPath: "/tmp/m5-export.pdf")
    }

    func exportCallCount() async -> Int {
        calls
    }
}
