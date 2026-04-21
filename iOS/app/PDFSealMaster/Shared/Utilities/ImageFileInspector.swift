import Foundation
import UIKit

enum ImageFileInspector {
    static func displayPixelSize(for url: URL) -> PaperSize? {
        guard let image = UIImage(contentsOfFile: url.path), let cgImage = image.cgImage else {
            return nil
        }

        let pixelWidth = Double(cgImage.width)
        let pixelHeight = Double(cgImage.height)

        if image.imageOrientation.rotatesCanvas {
            return PaperSize(width: max(pixelHeight, 1), height: max(pixelWidth, 1))
        }

        return PaperSize(width: max(pixelWidth, 1), height: max(pixelHeight, 1))
    }

    static func displayPixelRect(for url: URL) -> PixelRect? {
        guard let size = displayPixelSize(for: url) else {
            return nil
        }

        return PixelRect(x: 0, y: 0, width: size.width, height: size.height)
    }

    static func normalizedCGImage(for url: URL) -> CGImage? {
        guard let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }

        return normalizedCGImage(from: image)
    }

    static func normalizedCGImage(from image: UIImage) -> CGImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }

        if image.imageOrientation == .up {
            return cgImage
        }

        let renderSize = normalizedCanvasSize(for: image)
        guard renderSize.width > 0, renderSize.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: renderSize))
        }

        return rendered.cgImage
    }

    private static func normalizedCanvasSize(for image: UIImage) -> CGSize {
        guard let cgImage = image.cgImage else {
            return .zero
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        if image.imageOrientation.rotatesCanvas {
            return CGSize(width: height, height: width)
        }

        return CGSize(width: width, height: height)
    }
}

private extension UIImage.Orientation {
    var rotatesCanvas: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored:
            return true
        default:
            return false
        }
    }
}
