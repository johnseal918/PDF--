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
    var signatureReplaceReceiptMessage: String = "暂无替换回执。"

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case document
        case selectedObjectID
        case activePageIndex
        case signatureReplaceReceiptMessage
    }

    init(
        schemaVersion: Int = 1,
        document: DocumentModel,
        selectedObjectID: UUID?,
        activePageIndex: Int,
        signatureReplaceReceiptMessage: String = "暂无替换回执。"
    ) {
        self.schemaVersion = schemaVersion
        self.document = document
        self.selectedObjectID = selectedObjectID
        self.activePageIndex = activePageIndex
        self.signatureReplaceReceiptMessage = signatureReplaceReceiptMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        document = try container.decode(DocumentModel.self, forKey: .document)
        selectedObjectID = try container.decodeIfPresent(UUID.self, forKey: .selectedObjectID)
        activePageIndex = try container.decode(Int.self, forKey: .activePageIndex)
        signatureReplaceReceiptMessage = try container.decodeIfPresent(String.self, forKey: .signatureReplaceReceiptMessage)
            ?? "暂无替换回执。"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(document, forKey: .document)
        try container.encodeIfPresent(selectedObjectID, forKey: .selectedObjectID)
        try container.encode(activePageIndex, forKey: .activePageIndex)
        try container.encode(signatureReplaceReceiptMessage, forKey: .signatureReplaceReceiptMessage)
    }
}
