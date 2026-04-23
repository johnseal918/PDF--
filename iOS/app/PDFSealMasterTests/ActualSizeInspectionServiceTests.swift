import XCTest
@testable import PDFSealMaster

final class ActualSizeInspectionServiceTests: XCTestCase {
    private let service = DefaultActualSizeInspectionService()
    private let pageSize = MillimeterSize(width: 210, height: 297)

    func testInspectStampReturnsPassForReasonableSize() {
        let object = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 20,
                originYMM: 30,
                widthMM: 40,
                heightMM: 40,
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let result = service.inspect(object: object, pageSizeMM: pageSize)
        XCTAssertEqual(result.severity, .pass)
        XCTAssertTrue(result.headline.contains("通过"))
    }

    func testInspectStampReturnsWarningForTooSmallSize() {
        let object = EditorObject(
            pageIndex: 0,
            type: .stamp,
            zIndex: 0,
            isSelected: true,
            stampPlacement: StampPlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 10,
                originYMM: 10,
                widthMM: 5,
                heightMM: 5,
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                aspectRatioLocked: true
            ),
            signaturePlacement: nil
        )

        let result = service.inspect(object: object, pageSizeMM: pageSize)
        XCTAssertEqual(result.severity, .warning)
        XCTAssertTrue(result.headline.contains("尺寸过小"))
    }

    func testInspectSignatureReturnsWarningForTooLargeSize() {
        let object = EditorObject(
            pageIndex: 0,
            type: .signature,
            zIndex: 0,
            isSelected: true,
            stampPlacement: nil,
            signaturePlacement: SignaturePlacement(
                pageIndex: 0,
                assetID: UUID(),
                originXMM: 0,
                originYMM: 0,
                widthMM: 180,
                heightMM: 90,
                rotation: 0,
                opacity: 1,
                zIndex: 0
            )
        )

        let result = service.inspect(object: object, pageSizeMM: pageSize)
        XCTAssertEqual(result.severity, .warning)
        XCTAssertTrue(result.headline.contains("尺寸过大"))
    }
}
