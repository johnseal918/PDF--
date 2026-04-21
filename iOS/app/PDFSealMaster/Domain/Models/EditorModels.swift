import Foundation

enum EditorObjectType: String, Codable, Hashable {
    case stamp
    case signature
}

struct EditorObject: Identifiable, Codable, Hashable {
    var id = UUID()
    var pageIndex: Int
    var type: EditorObjectType
    var zIndex: Int
    var isSelected: Bool
    var stampPlacement: StampPlacement?
    var signaturePlacement: SignaturePlacement?
}

struct StampPlacement: Codable, Hashable {
    var id = UUID()
    var pageIndex: Int
    var assetID: UUID
    var originXMM: Double
    var originYMM: Double
    var widthMM: Double
    var heightMM: Double
    var rotation: Double
    var opacity: Double
    var zIndex: Int
    var aspectRatioLocked: Bool = true
}

struct SignaturePlacement: Codable, Hashable {
    var id = UUID()
    var pageIndex: Int
    var assetID: UUID
    var originXMM: Double
    var originYMM: Double
    var widthMM: Double
    var heightMM: Double
    var rotation: Double
    var opacity: Double
    var zIndex: Int
}

struct BindingStampPlacement: Codable, Hashable {
    var assetID: UUID
    var startPage: Int
    var endPage: Int
    var targetWidthMM: Double
    var marginMM: Double
    var lossMM: Double
    var rotation: Double
    var yOffsetMM: Double
    var enabled: Bool
}

struct EditorSession: Codable, Hashable {
    var schemaVersion: Int = 1
    var document: DocumentModel
    var selectedObjectID: UUID?
    var activePageIndex: Int
}
