import XCTest
@testable import PDFSealMaster

final class PreviewModeServiceTests: XCTestCase {
    private let service = DefaultPreviewModeService()

    func testMatchedLowResWarnsForTinyStamp() {
        let stampObject = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 20,
                originYMM: 20,
                widthMM: 8,
                heightMM: 8,
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let result = service.inspect(
            mode: .matchedLowRes,
            selectedObject: stampObject,
            page: makePage()
        )

        XCTAssertEqual(result.severity, .warning)
        XCTAssertLessThan(result.simulatedScale, 1)
    }

    func testOriginalPreviewKeepsSameStampAsPass() {
        let stampObject = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 20,
                originYMM: 20,
                widthMM: 8,
                heightMM: 8,
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let result = service.inspect(
            mode: .original,
            selectedObject: stampObject,
            page: makePage()
        )

        XCTAssertEqual(result.severity, .pass)
        XCTAssertEqual(result.simulatedScale, 1, accuracy: 0.0001)
    }

    func testMatchedLowResPassesForReasonableSignature() {
        let signatureObject = EditorObject(
            pageIndex: 0,
            type: .signature,
            zIndex: 0,
            isSelected: true,
            stampPlacement: nil,
            signaturePlacement: SignaturePlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 30,
                originYMM: 30,
                widthMM: 45,
                heightMM: 20,
                rotation: 0,
                opacity: 1,
                zIndex: 0
            )
        )

        let result = service.inspect(
            mode: .matchedLowRes,
            selectedObject: signatureObject,
            page: makePage()
        )

        XCTAssertEqual(result.severity, .pass)
        XCTAssertLessThan(result.simulatedScale, 1)
        XCTAssertGreaterThan(result.simulatedScale, 0.35)
    }

    private func makePage() -> PageModel {
        PageModel(
            index: 0,
            originalSizePT: .a4,
            a4CanvasSizePT: .a4,
            contentRectInA4PT: PaperRect(
                origin: PaperPoint(x: 20, y: 20),
                size: PaperSize(width: 555.28, height: 801.89)
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
