import Foundation

enum SampleDocumentFactory {
    static func makeSampleDocument() -> DocumentModel {
        let sampleSizes: [PaperSize] = [
            PaperSize(width: 500, height: 700),
            PaperSize(width: 612, height: 792),
            PaperSize(width: 430, height: 860)
        ]

        let pages = sampleSizes.enumerated().map { index, size in
            A4Normalizer.normalize(
                originalSize: size,
                sourcePath: "sample-\(index + 1).pdf",
                pageIndex: index
            )
        }

        return DocumentModel(
            name: "Sample Document",
            sourceType: .pdf,
            pages: pages,
            editorObjects: [],
            bindingStampPlacement: nil,
            previewMode: .original,
            draftVersion: 1,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
