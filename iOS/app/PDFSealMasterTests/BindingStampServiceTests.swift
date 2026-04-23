import XCTest
@testable import PDFSealMaster

final class BindingStampServiceTests: XCTestCase {
    private let service = DefaultBindingStampService()

    func testNormalizePlacementClampsRangeAndParameters() {
        let placement = BindingStampPlacement(
            assetID: UUID(),
            startPage: -3,
            endPage: 99,
            targetWidthMM: 500,
            marginMM: -4,
            lossMM: 20,
            rotation: 90,
            yOffsetMM: -500,
            enabled: true
        )

        let normalized = service.normalizePlacement(placement, pageCount: 4)

        XCTAssertEqual(normalized.startPage, 0)
        XCTAssertEqual(normalized.endPage, 3)
        XCTAssertEqual(normalized.targetWidthMM, 300, accuracy: 0.0001)
        XCTAssertEqual(normalized.marginMM, 0, accuracy: 0.0001)
        XCTAssertEqual(normalized.lossMM, 15, accuracy: 0.0001)
        XCTAssertEqual(normalized.rotation, 45, accuracy: 0.0001)
        XCTAssertEqual(normalized.yOffsetMM, -120, accuracy: 0.0001)
    }

    func testDrawPlanReturnsNilWhenPlacementDisabledOrPageOutOfRange() {
        let disabled = BindingStampPlacement(
            assetID: UUID(),
            startPage: 0,
            endPage: 2,
            targetWidthMM: 90,
            marginMM: 3,
            lossMM: 0.5,
            rotation: 0,
            yOffsetMM: 0,
            enabled: false
        )

        let disabledPlan = service.drawPlan(
            for: 1,
            documentPageCount: 3,
            pageSizeMM: MillimeterSize(width: 210, height: 297),
            placement: disabled,
            aspectRatio: 1.0
        )
        XCTAssertNil(disabledPlan)

        var enabled = disabled
        enabled.enabled = true
        let outOfRangePlan = service.drawPlan(
            for: 4,
            documentPageCount: 3,
            pageSizeMM: MillimeterSize(width: 210, height: 297),
            placement: enabled,
            aspectRatio: 1.0
        )
        XCTAssertNil(outOfRangePlan)
    }

    func testDrawPlanComputesExpectedSliceGeometry() {
        let placement = BindingStampPlacement(
            assetID: UUID(),
            startPage: 0,
            endPage: 2,
            targetWidthMM: 90,
            marginMM: 3,
            lossMM: 0.5,
            rotation: 2,
            yOffsetMM: 10,
            enabled: true
        )

        let plan = service.drawPlan(
            for: 1,
            documentPageCount: 3,
            pageSizeMM: MillimeterSize(width: 210, height: 297),
            placement: placement,
            aspectRatio: 1.0
        )

        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.pageOffset, 1)
        XCTAssertEqual(plan?.pageCount, 3)
        XCTAssertEqual(plan?.widthMM ?? 0, 30.5, accuracy: 0.0001)
        XCTAssertEqual(plan?.heightMM ?? 0, 90, accuracy: 0.0001)
        XCTAssertEqual(plan?.originXMM ?? 0, 176.5, accuracy: 0.0001)
        XCTAssertEqual(plan?.originYMM ?? 0, 113.5, accuracy: 0.0001)
        XCTAssertEqual(plan?.rotation ?? 0, 2, accuracy: 0.0001)
    }

    func testSliceCropSplitsImageWidthAndKeepsLastRemainder() {
        let first = service.sliceCrop(
            forImageWidth: 100,
            imageHeight: 60,
            pageOffset: 0,
            pageCount: 3
        )
        let second = service.sliceCrop(
            forImageWidth: 100,
            imageHeight: 60,
            pageOffset: 1,
            pageCount: 3
        )
        let third = service.sliceCrop(
            forImageWidth: 100,
            imageHeight: 60,
            pageOffset: 2,
            pageCount: 3
        )

        XCTAssertEqual(first, BindingStampSliceCrop(x: 0, width: 33, height: 60))
        XCTAssertEqual(second, BindingStampSliceCrop(x: 33, width: 33, height: 60))
        XCTAssertEqual(third, BindingStampSliceCrop(x: 66, width: 34, height: 60))
        XCTAssertEqual((first?.width ?? 0) + (second?.width ?? 0) + (third?.width ?? 0), 100)
    }
}
