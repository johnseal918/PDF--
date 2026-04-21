import SwiftUI

@main
struct PDFSealMasterApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var settings = AppSettings()

    private let documentService: DocumentService = DefaultDocumentService()
    private let draftRecoveryService: DraftRecoveryService = FileDraftRecoveryService()
    private let stampAssetService: StampAssetService = FileStampAssetService()
    private let pdfExportService: PDFExportService = FilePDFExportService()
    private let issueLogService: IssueLogService = FileIssueLogService()

    var body: some Scene {
        WindowGroup {
            HomeView(
                router: router,
                settings: settings,
                documentService: documentService,
                draftRecoveryService: draftRecoveryService,
                stampAssetService: stampAssetService,
                pdfExportService: pdfExportService,
                issueLogService: issueLogService
            )
        }
    }
}
