import Foundation

enum A4Normalizer {
    static func normalize(
        originalSize: PaperSize,
        sourcePath: String,
        pageIndex: Int
    ) -> PageModel {
        let canvas = PaperSize.a4
        let widthRatio = canvas.width / originalSize.width
        let heightRatio = canvas.height / originalSize.height
        let scale = min(widthRatio, heightRatio)

        let fittedSize = PaperSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        let origin = PaperPoint(
            x: (canvas.width - fittedSize.width) / 2.0,
            y: (canvas.height - fittedSize.height) / 2.0
        )

        return PageModel(
            index: pageIndex,
            originalSizePT: originalSize,
            a4CanvasSizePT: canvas,
            contentRectInA4PT: PaperRect(origin: origin, size: fittedSize),
            originalToA4Transform: PaperTransform(
                scaleX: scale,
                scaleY: scale,
                translateX: origin.x,
                translateY: origin.y
            ),
            previewImagePath: nil,
            thumbnailPath: nil,
            originalSourcePath: sourcePath
        )
    }
}

enum A4CoordinateMapper {
    static func paperPoint(from point: MillimeterPoint) -> PaperPoint {
        point.asPaperPoint
    }

    static func paperSize(from size: MillimeterSize) -> PaperSize {
        size.asPaperSize
    }

    static func millimeterPoint(from point: PaperPoint) -> MillimeterPoint {
        point.asMillimeterPoint
    }

    static func millimeterSize(from size: PaperSize) -> MillimeterSize {
        size.asMillimeterSize
    }
}
