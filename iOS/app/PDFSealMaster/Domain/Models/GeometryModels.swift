import Foundation

enum A4Measurement {
    static let pointsPerMillimeter: Double = 72.0 / 25.4
    static let millimetersPerPoint: Double = 25.4 / 72.0
}

struct MillimeterPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct MillimeterSize: Codable, Hashable {
    var width: Double
    var height: Double
}

struct PixelRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct PaperPoint: Codable, Hashable {
    var x: Double
    var y: Double
}

struct PaperSize: Codable, Hashable {
    var width: Double
    var height: Double

    static let a4 = PaperSize(width: 595.28, height: 841.89)
}

struct PaperRect: Codable, Hashable {
    var origin: PaperPoint
    var size: PaperSize
}

struct PaperTransform: Codable, Hashable {
    var scaleX: Double
    var scaleY: Double
    var translateX: Double
    var translateY: Double
}

extension MillimeterPoint {
    var asPaperPoint: PaperPoint {
        PaperPoint(
            x: x * A4Measurement.pointsPerMillimeter,
            y: y * A4Measurement.pointsPerMillimeter
        )
    }
}

extension MillimeterSize {
    var asPaperSize: PaperSize {
        PaperSize(
            width: width * A4Measurement.pointsPerMillimeter,
            height: height * A4Measurement.pointsPerMillimeter
        )
    }
}

extension PaperPoint {
    var asMillimeterPoint: MillimeterPoint {
        MillimeterPoint(
            x: x * A4Measurement.millimetersPerPoint,
            y: y * A4Measurement.millimetersPerPoint
        )
    }
}

extension PaperSize {
    var asMillimeterSize: MillimeterSize {
        MillimeterSize(
            width: width * A4Measurement.millimetersPerPoint,
            height: height * A4Measurement.millimetersPerPoint
        )
    }
}
