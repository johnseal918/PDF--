import Foundation

enum DocumentSourceType: String, Codable, Hashable {
    case pdf
    case images
}

struct PageModel: Identifiable, Codable, Hashable {
    var id = UUID()
    var index: Int
    var originalSizePT: PaperSize
    var a4CanvasSizePT: PaperSize
    var contentRectInA4PT: PaperRect
    var originalToA4Transform: PaperTransform
    var previewImagePath: String?
    var thumbnailPath: String?
    var originalSourcePath: String
}

struct DocumentModel: Identifiable, Codable, Hashable {
    var schemaVersion: Int = 1
    var id = UUID()
    var name: String
    var sourceType: DocumentSourceType
    var pages: [PageModel]
    var editorObjects: [EditorObject]
    var bindingStampPlacement: BindingStampPlacement?
    var previewMode: PreviewMode
    var draftVersion: Int
    var createdAt: Date
    var updatedAt: Date

    var pageCount: Int {
        pages.count
    }
}
