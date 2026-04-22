import XCTest
@testable import PDFSealMaster

final class A4NormalizerTests: XCTestCase {
    func testNormalizeCentersFittedContentInA4Canvas() {
        let original = PaperSize(width: 1000, height: 500)
        let page = A4Normalizer.normalize(
            originalSize: original,
            sourcePath: "sample.pdf",
            pageIndex: 2
        )

        let canvas = PaperSize.a4
        let expectedScale = min(canvas.width / original.width, canvas.height / original.height)
        let expectedFittedWidth = original.width * expectedScale
        let expectedFittedHeight = original.height * expectedScale
        let expectedOriginX = (canvas.width - expectedFittedWidth) / 2.0
        let expectedOriginY = (canvas.height - expectedFittedHeight) / 2.0

        XCTAssertEqual(page.index, 2)
        XCTAssertEqual(page.originalSourcePath, "sample.pdf")
        XCTAssertEqual(page.a4CanvasSizePT.width, canvas.width, accuracy: 0.0001)
        XCTAssertEqual(page.a4CanvasSizePT.height, canvas.height, accuracy: 0.0001)
        XCTAssertEqual(page.originalToA4Transform.scaleX, expectedScale, accuracy: 0.0001)
        XCTAssertEqual(page.originalToA4Transform.scaleY, expectedScale, accuracy: 0.0001)
        XCTAssertEqual(page.contentRectInA4PT.size.width, expectedFittedWidth, accuracy: 0.0001)
        XCTAssertEqual(page.contentRectInA4PT.size.height, expectedFittedHeight, accuracy: 0.0001)
        XCTAssertEqual(page.contentRectInA4PT.origin.x, expectedOriginX, accuracy: 0.0001)
        XCTAssertEqual(page.contentRectInA4PT.origin.y, expectedOriginY, accuracy: 0.0001)
    }

    func testCoordinateMapperRoundTripForPointAndSize() {
        let pointMM = MillimeterPoint(x: 12.34, y: 56.78)
        let sizeMM = MillimeterSize(width: 40.5, height: 23.75)

        let pointPT = A4CoordinateMapper.paperPoint(from: pointMM)
        let sizePT = A4CoordinateMapper.paperSize(from: sizeMM)
        let pointBack = A4CoordinateMapper.millimeterPoint(from: pointPT)
        let sizeBack = A4CoordinateMapper.millimeterSize(from: sizePT)

        XCTAssertEqual(pointBack.x, pointMM.x, accuracy: 0.0001)
        XCTAssertEqual(pointBack.y, pointMM.y, accuracy: 0.0001)
        XCTAssertEqual(sizeBack.width, sizeMM.width, accuracy: 0.0001)
        XCTAssertEqual(sizeBack.height, sizeMM.height, accuracy: 0.0001)
    }
}
