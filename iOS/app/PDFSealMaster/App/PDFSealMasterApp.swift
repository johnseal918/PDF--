import SwiftUI

@main
struct PDFSealMasterApp: App {
    @StateObject private var router = AppRouter()
    @StateObject private var settings = AppSettings()

    private let documentService: DocumentService = DefaultDocumentService()
    private let draftRecoveryService: DraftRecoveryService = FileDraftRecoveryService()
    private let stampAssetService: StampAssetService = FileStampAssetService()
    private let signatureAssetService: SignatureAssetService = FileSignatureAssetService()
    private let pdfExportService: PDFExportService = FilePDFExportService()
    private let purchaseService: PurchaseService = LocalPurchaseService()
    private let issueLogService: IssueLogService = FileIssueLogService()

    var body: some Scene {
        WindowGroup {
            HomeView(
                router: router,
                settings: settings,
                documentService: documentService,
                draftRecoveryService: draftRecoveryService,
                stampAssetService: stampAssetService,
                signatureAssetService: signatureAssetService,
                pdfExportService: pdfExportService,
                purchaseService: purchaseService,
                issueLogService: issueLogService
            )
        }
    }
}
