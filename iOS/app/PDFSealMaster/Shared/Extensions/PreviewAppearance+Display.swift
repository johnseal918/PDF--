import Foundation

extension PreviewAppearance {
    var displayName: String {
        switch self {
        case .standard:
            return "标准"
        case .grayscaleScan:
            return "灰度扫描风"
        }
    }
}
