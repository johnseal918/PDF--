import Foundation

extension PreviewMode {
    var displayName: String {
        switch self {
        case .original:
            return "原始预览"
        case .matchedLowRes:
            return "自动匹配低分辨率"
        }
    }
}
