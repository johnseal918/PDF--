import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var router: AppRouter
    @ObservedObject var settings: AppSettings
    let documentService: DocumentService
    let draftRecoveryService: DraftRecoveryService
    let stampAssetService: StampAssetService
    let pdfExportService: PDFExportService
    let issueLogService: IssueLogService

    @State private var latestDraftSession: EditorSession?
    @State private var draftSummaries: [DraftSnapshotSummary] = []
    @State private var isLoadingDraft = false
    @State private var isImportingDocument = false
    @State private var isShowingPDFImporter = false
    @State private var isShowingImageFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var importStatusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch router.currentRoute {
                case .home:
                    homeContent
                case .editor(let session):
                    EditorView(
                        session: session,
                        draftRecoveryService: draftRecoveryService,
                        stampAssetService: stampAssetService,
                        pdfExportService: pdfExportService,
                        issueLogService: issueLogService,
                        onBack: {
                            router.showHome()
                            Task {
                                await refreshLatestDraft()
                            }
                        }
                    )
                case .stampImport:
                    StampImportView(
                        stampAssetService: stampAssetService,
                        issueLogService: issueLogService,
                        onClose: { router.showHome() }
                    )
                }
            }
            .navigationTitle("PDF Seal Master")
        }
        .task {
            await refreshLatestDraft()
        }
        .onChange(of: selectedPhotoItems) { newItems in
            guard !newItems.isEmpty else {
                return
            }

            Task {
                await importImagesFromPhotos(newItems)
            }
        }
        .fileImporter(
            isPresented: $isShowingPDFImporter,
            allowedContentTypes: [.pdf]
        ) { result in
            Task {
                await handlePDFFileImport(result)
            }
        }
        .fileImporter(
            isPresented: $isShowingImageFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            Task {
                await handleImageFileImport(result)
            }
        }
    }

    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("iPhone 首发版已启动")
                .font(.title2.weight(.semibold))

            Text("当前先跑通主链路：导入文档、A4 归一化、印章规范化、普通盖章、草稿恢复、PDF 导出。")
                .font(.body)
                .foregroundStyle(.secondary)

            Button("继续最近草稿") {
                guard let latestDraftSession else {
                    return
                }
                router.showEditor(session: latestDraftSession)
            }
            .buttonStyle(.borderedProminent)
            .disabled(latestDraftSession == nil || isLoadingDraft)

            Text(draftStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let latestDraftSession {
                Text("鏈€杩戣崏绋匡細\(latestDraftSession.document.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("瀵煎叆 PDF锛堟枃浠讹級") {
                isShowingPDFImporter = true
            }
            .buttonStyle(.bordered)
            .disabled(isImportingDocument)

            Button("瀵煎叆鍥剧墖锛堟枃浠讹級") {
                isShowingImageFileImporter = true
            }
            .buttonStyle(.bordered)
            .disabled(isImportingDocument)

            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Text("瀵煎叆鍥剧墖锛堢浉鍐岋級")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isImportingDocument)

            Button("杩涘叆鍗扮珷瀵煎叆楠ㄦ灦") {
                router.showStampImport()
            }
            .buttonStyle(.bordered)
            .disabled(isImportingDocument)

            if isImportingDocument {
                ProgressView("姝ｅ湪瀵煎叆...")
                    .font(.caption)
            }

            if let importStatusMessage {
                Text(importStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
    }

    private var draftStatusText: String {
        if isLoadingDraft {
            return "正在检查最近草稿..."
        }

        if let latestDraftSession {
            return "发现 \(draftSummaries.count) 份草稿，可以继续最近一次编辑。"
        }

        return "当前没有可恢复的草稿。"
    }

    private func refreshLatestDraft() async {
        isLoadingDraft = true
        do {
            latestDraftSession = try await draftRecoveryService.restoreLatestDraft()
        } catch {
            latestDraftSession = nil
            await issueLogService.recordError(
                "恢复最近草稿失败",
                error: error,
                category: .draftRecovery,
                context: ["scope": "restoreLatestDraft"]
            )
        }

        do {
            draftSummaries = try await draftRecoveryService.loadDraftSummaries()
        } catch {
            draftSummaries = []
            await issueLogService.recordError(
                "鍔犺浇鑽夌鎽樿澶辫触",
                error: error,
                category: .draftRecovery,
                context: ["scope": "loadDraftSummaries"]
            )
        }
        isLoadingDraft = false
    }

    private func openEditor(with document: DocumentModel) async {
        let session = EditorSession(
            document: document,
            selectedObjectID: nil,
            activePageIndex: 0
        )

        var didPersistDraft = false
        do {
            try await draftRecoveryService.saveDraft(session: session)
            didPersistDraft = true
            await issueLogService.recordFeedback(
                "草稿已写入",
                category: .draftSave,
                context: [
                    "documentID": session.document.id.uuidString,
                    "documentName": session.document.name
                ]
            )
        } catch {
            await issueLogService.recordError(
                "鎵撳紑缂栬緫鍣ㄥ墠淇濆瓨鑽夌澶辫触",
                error: error,
                category: .draftSave,
                context: [
                    "documentID": session.document.id.uuidString,
                    "documentName": session.document.name
                ]
            )
        }

        await MainActor.run {
            if didPersistDraft {
                latestDraftSession = session
            }
            router.showEditor(session: session)
        }
    }

    private func handlePDFFileImport(_ result: Result<URL, Error>) async {
        guard !isImportingDocument else {
            return
        }

        isImportingDocument = true
        defer { isImportingDocument = false }

        var sourceFileName = "unknown"
        var stagedURL: URL?

        do {
            let pickedURL = try result.get()
            sourceFileName = pickedURL.lastPathComponent
            let resolvedStagedURL = try ImportStagingService.stageExternalFile(
                pickedURL,
                preferredExtension: "pdf"
            )
            stagedURL = resolvedStagedURL
            let document = try await documentService.importDocument(from: resolvedStagedURL)
            importStatusMessage = "已导入 PDF：\(document.name)"
            await issueLogService.recordFeedback(
                "PDF 导入成功",
                category: .documentImport,
                context: [
                    "sourceFile": pickedURL.lastPathComponent,
                    "stagedFile": resolvedStagedURL.lastPathComponent,
                    "documentName": document.name
                ]
            )
            try? FileManager.default.removeItem(at: resolvedStagedURL)
            await openEditor(with: document)
        } catch {
            if let stagedURL {
                try? FileManager.default.removeItem(at: stagedURL)
            }
            let failure = classifyImportFailure(error)
            await issueLogService.recordError(
                "PDF 导入失败",
                error: error,
                category: .documentImport,
                context: [
                    "sourceFile": sourceFileName,
                    "failureKind": failure.rawValue
                ]
            )
            importStatusMessage = importFailureMessage(for: failure, source: .pdfFile)
        }
    }

    private func handleImageFileImport(_ result: Result<[URL], Error>) async {
        guard !isImportingDocument else {
            return
        }

        isImportingDocument = true
        defer { isImportingDocument = false }

        var sourceCount = 0
        var stagedURLs: [URL] = []

        do {
            let pickedURLs = try result.get()
            sourceCount = pickedURLs.count
            guard !pickedURLs.isEmpty else {
                importStatusMessage = "未选择图片文件。"
                await issueLogService.recordFeedback(
                    "图片文件导入未选择有效文件",
                    category: .documentImport,
                    context: ["sourceCount": "0"]
                )
                return
            }

            stagedURLs = try pickedURLs.map { url in
                try ImportStagingService.stageExternalFile(url)
            }
            let document = try await documentService.importImages(from: stagedURLs)
            importStatusMessage = "已导入 \(document.pageCount) 张图片。"
            await issueLogService.recordFeedback(
                "图片文件导入成功",
                category: .documentImport,
                context: [
                    "sourceCount": String(pickedURLs.count),
                    "stagedCount": String(stagedURLs.count),
                    "documentName": document.name
                ]
            )
            for url in stagedURLs {
                try? FileManager.default.removeItem(at: url)
            }
            await openEditor(with: document)
        } catch {
            if !stagedURLs.isEmpty {
                for url in stagedURLs {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            let failure = classifyImportFailure(error)
            await issueLogService.recordError(
                "图片文件导入失败",
                error: error,
                category: .documentImport,
                context: [
                    "sourceCount": String(sourceCount),
                    "failureKind": failure.rawValue
                ]
            )
            importStatusMessage = importFailureMessage(for: failure, source: .imageFile)
        }
    }

    private func importImagesFromPhotos(_ items: [PhotosPickerItem]) async {
        guard !isImportingDocument else {
            return
        }

        isImportingDocument = true
        defer {
            isImportingDocument = false
            selectedPhotoItems = []
        }

        var stagedCount = 0
        var stagedURLs: [URL] = []

        do {
            for item in items {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let fileExtension = item
                    .supportedContentTypes
                    .first?
                    .preferredFilenameExtension ?? "jpg"
                let stagedURL = try ImportStagingService.stageData(
                    data,
                    fileExtension: fileExtension
                )
                stagedURLs.append(stagedURL)
            }

            stagedCount = stagedURLs.count
            guard !stagedURLs.isEmpty else {
                importStatusMessage = "相册导入失败，请重新选择。"
                await issueLogService.recordFeedback(
                    "相册导入未找到有效图片",
                    category: .documentImport,
                    context: ["itemCount": String(items.count)]
                )
                return
            }

            let document = try await documentService.importImages(from: stagedURLs)
            importStatusMessage = "已从相册导入 \(document.pageCount) 张图片。"
            await issueLogService.recordFeedback(
                "相册图片导入成功",
                category: .documentImport,
                context: [
                    "sourceCount": String(items.count),
                    "stagedCount": String(stagedURLs.count),
                    "documentName": document.name
                ]
            )
            for url in stagedURLs {
                try? FileManager.default.removeItem(at: url)
            }
            await openEditor(with: document)
        } catch {
            if !stagedURLs.isEmpty {
                for url in stagedURLs {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            let failure = classifyImportFailure(error)
            await issueLogService.recordError(
                "相册图片导入失败",
                error: error,
                category: .documentImport,
                context: [
                    "sourceCount": String(items.count),
                    "stagedCount": String(stagedCount),
                    "failureKind": failure.rawValue
                ]
            )
            importStatusMessage = importFailureMessage(for: failure, source: .photoLibrary)
        }
    }

    private func classifyImportFailure(_ error: Error) -> ImportFailure {
        if isUserCancelled(error) {
            return .cancelled
        }

        if let appError = error as? AppError {
            switch appError {
            case .unsupportedFileType:
                return .unsupportedType
            case .permissionDenied:
                return .permissionDenied
            case .fileImportFailed:
                return .parseFailed
            default:
                break
            }
        }

        if let stagingError = error as? ImportStagingError {
            switch stagingError {
            case .invalidSource:
                return .permissionDenied
            case .writeFailed:
                return .permissionDenied
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            if nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
                return .permissionDenied
            }

            if nsError.code == NSFileReadCorruptFileError || nsError.code == NSFileReadUnknownStringEncodingError {
                return .parseFailed
            }
        }

        return .unknown
    }

    private func importFailureMessage(
        for failure: ImportFailure,
        source: ImportSource
    ) -> String {
        switch failure {
        case .cancelled:
            switch source {
            case .pdfFile:
                return "已取消 PDF 导入。"
            case .imageFile:
                return "已取消图片导入。"
            case .photoLibrary:
                return "已取消相册导入。"
            }
        case .unsupportedType:
            switch source {
            case .pdfFile:
                return "PDF 格式错误，仅支持 .pdf 文件。"
            case .imageFile:
                return "图片格式错误，请选择 PNG/JPG/HEIC 等图片文件。"
            case .photoLibrary:
                return "相册图片格式暂不支持，请更换图片后重试。"
            }
        case .permissionDenied:
            switch source {
            case .pdfFile, .imageFile:
                return "导入失败：没有文件访问权限，请在系统弹窗中允许访问后重试。"
            case .photoLibrary:
                return "相册导入失败：没有相册访问权限，请在系统设置中开启权限后重试。"
            }
        case .parseFailed:
            switch source {
            case .pdfFile:
                return "PDF 解析失败，文件可能损坏或内容不可读。"
            case .imageFile:
                return "图片解析失败，文件可能损坏或格式不完整。"
            case .photoLibrary:
                return "相册图片解析失败，请重新选择或更换图片。"
            }
        case .unknown:
            switch source {
            case .pdfFile:
                return "PDF 导入失败，请重试。"
            case .imageFile:
                return "图片文件导入失败，请重试。"
            case .photoLibrary:
                return "相册导入失败，请重试。"
            }
        }
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }
}

private enum ImportSource {
    case pdfFile
    case imageFile
    case photoLibrary
}

private enum ImportFailure: String {
    case cancelled
    case unsupportedType
    case permissionDenied
    case parseFailed
    case unknown
}

