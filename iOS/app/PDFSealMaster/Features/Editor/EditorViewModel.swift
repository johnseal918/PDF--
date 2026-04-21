import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var session: EditorSession
    @Published private(set) var availableStampAssets: [StampAsset] = []
    @Published private(set) var selectedStampAssetID: UUID?
    @Published private(set) var lastExportURL: URL?
    @Published private(set) var exportStatusMessage = "灏氭湭瀵煎嚭"
    @Published private(set) var exportDetailMessage = "导出后可使用分享按钮保存或发送。"
    @Published private(set) var isExportingPDF = false
    @Published private(set) var draftStatusMessage = "自动保存已启用"

    private let draftRecoveryService: DraftRecoveryService
    private let stampAssetService: StampAssetService
    private let pdfExportService: PDFExportService
    private let issueLogService: IssueLogService
    private var autoSaveTask: Task<Void, Never>?

    init(
        session: EditorSession,
        draftRecoveryService: DraftRecoveryService,
        stampAssetService: StampAssetService,
        pdfExportService: PDFExportService,
        issueLogService: IssueLogService
    ) {
        self.session = session
        self.draftRecoveryService = draftRecoveryService
        self.stampAssetService = stampAssetService
        self.pdfExportService = pdfExportService
        self.issueLogService = issueLogService
        normalizeSelectionForActivePage()
    }

    var document: DocumentModel {
        session.document
    }

    var activePageDisplay: Int {
        session.activePageIndex + 1
    }

    var currentPageObjectCount: Int {
        document.editorObjects.filter { $0.pageIndex == session.activePageIndex }.count
    }

    var currentPageObjects: [EditorObject] {
        document.editorObjects
            .filter { $0.pageIndex == session.activePageIndex }
            .sorted { $0.zIndex < $1.zIndex }
    }

    var selectedObject: EditorObject? {
        guard let selectedObjectID = session.selectedObjectID else {
            return nil
        }

        return currentPageObjects.first(where: { $0.id == selectedObjectID })
    }

    var selectedObjectSummary: String {
        guard let selectedObject else {
            return "鏈€変腑瀵硅薄"
        }

        if let stamp = selectedObject.stampPlacement {
            return "鍗扮珷锛歕(String(format: "%.1f", stamp.originXMM))mm, \(String(format: "%.1f", stamp.originYMM))mm 路 \(String(format: "%.1f", stamp.widthMM)) 脳 \(String(format: "%.1f", stamp.heightMM)) mm"
        }

        if let signature = selectedObject.signaturePlacement {
            return "绛惧悕锛歕(String(format: "%.1f", signature.originXMM))mm, \(String(format: "%.1f", signature.originYMM))mm 路 \(String(format: "%.1f", signature.widthMM)) 脳 \(String(format: "%.1f", signature.heightMM)) mm"
        }

        return "鏈€変腑瀵硅薄"
    }

    var selectedStampPlacement: StampPlacement? {
        selectedObject?.stampPlacement
    }

    var selectedStampName: String {
        guard
            let selectedStampAssetID,
            let asset = availableStampAssets.first(where: { $0.id == selectedStampAssetID })
        else {
            return "鏈€夋嫨"
        }

        return asset.name
    }

    var availableStampCount: Int {
        availableStampAssets.count
    }

    func loadStampAssets() async {
        do {
            let assets = try await stampAssetService.loadAllStampAssets()
            availableStampAssets = assets
            selectedStampAssetID = selectedStampAssetID ?? assets.first?.id
        } catch {
            availableStampAssets = []
            selectedStampAssetID = nil
            await issueLogService.recordError(
                "编辑页加载印章素材失败",
                error: error,
                category: .stampImport,
                context: ["scope": "loadStampAssets"]
            )
        }
    }

    func goToPreviousPage() {
        guard session.activePageIndex > 0 else {
            return
        }

        session.activePageIndex -= 1
        refreshSelectionForActivePage()
        touchSession()
    }

    func goToNextPage() {
        guard session.activePageIndex + 1 < document.pageCount else {
            return
        }

        session.activePageIndex += 1
        refreshSelectionForActivePage()
        touchSession()
    }

    func togglePreviewMode() {
        session.document.previewMode = session.document.previewMode == .original ? .matchedLowRes : .original
        touchSession()
    }

    func insertSelectedStamp() {
        guard
            let selectedStampAssetID,
            let asset = availableStampAssets.first(where: { $0.id == selectedStampAssetID })
        else {
            return
        }

        let widthMM = asset.finalPhysicalSizeMM ?? asset.physicalSizePresetMM ?? 40.0
        let aspectRatio = asset.defaultAspectRatio ?? 1.0
        let heightMM = widthMM / max(aspectRatio, 0.1)
        let pageSizeMM = document.pages[session.activePageIndex].a4CanvasSizePT.asMillimeterSize
        let originXMM = max((pageSizeMM.width - widthMM) / 2.0, 0)
        let originYMM = max((pageSizeMM.height - heightMM) / 3.0, 0)
        let zIndex = (document.editorObjects.map(\.zIndex).max() ?? -1) + 1

        let placement = StampPlacement(
            pageIndex: session.activePageIndex,
            assetID: asset.id,
            originXMM: originXMM,
            originYMM: originYMM,
            widthMM: widthMM,
            heightMM: heightMM,
            rotation: 0,
            opacity: 0.9,
            zIndex: zIndex,
            aspectRatioLocked: asset.isAspectRatioLockedByDefault
        )

        let editorObject = EditorObject(
            pageIndex: session.activePageIndex,
            type: .stamp,
            zIndex: zIndex,
            isSelected: true,
            stampPlacement: placement,
            signaturePlacement: nil
        )

        for index in session.document.editorObjects.indices {
            session.document.editorObjects[index].isSelected = false
        }

        session.document.editorObjects.append(editorObject)
        session.selectedObjectID = editorObject.id
        touchSession()
    }

    func cycleSelectedStampAsset() {
        guard !availableStampAssets.isEmpty else {
            selectedStampAssetID = nil
            return
        }

        guard let selectedStampAssetID else {
            self.selectedStampAssetID = availableStampAssets.first?.id
            return
        }

        guard let currentIndex = availableStampAssets.firstIndex(where: { $0.id == selectedStampAssetID }) else {
            self.selectedStampAssetID = availableStampAssets.first?.id
            return
        }

        let nextIndex = (currentIndex + 1) % availableStampAssets.count
        self.selectedStampAssetID = availableStampAssets[nextIndex].id
    }

    func selectObject(_ objectID: UUID) {
        guard document.editorObjects.contains(where: { $0.id == objectID }) else {
            return
        }

        for index in session.document.editorObjects.indices {
            session.document.editorObjects[index].isSelected = session.document.editorObjects[index].id == objectID
        }

        session.selectedObjectID = objectID
        touchSession()
    }

    func deleteSelectedObject() {
        guard let selectedObjectID = session.selectedObjectID else {
            return
        }

        session.document.editorObjects.removeAll { $0.id == selectedObjectID }
        session.selectedObjectID = currentPageObjects.last?.id

        for index in session.document.editorObjects.indices {
            session.document.editorObjects[index].isSelected = session.document.editorObjects[index].id == session.selectedObjectID
        }

        touchSession()
    }

    func moveSelectedObject(deltaXMM: Double, deltaYMM: Double) {
        mutateSelectedStamp { placement, pageSize in
            placement.originXMM = min(max(placement.originXMM + deltaXMM, 0), max(pageSize.width - placement.widthMM, 0))
            placement.originYMM = min(max(placement.originYMM + deltaYMM, 0), max(pageSize.height - placement.heightMM, 0))
        }
    }

    func resizeSelectedStamp(deltaMM: Double) {
        mutateSelectedStamp { placement, pageSize in
            let currentAspectRatio = max(placement.widthMM / max(placement.heightMM, 0.1), 0.1)
            let nextWidth = max(placement.widthMM + deltaMM, 5.0)
            let nextHeight = placement.aspectRatioLocked
                ? max(nextWidth / currentAspectRatio, 5.0)
                : max(placement.heightMM + deltaMM, 5.0)

            placement.widthMM = min(nextWidth, pageSize.width)
            placement.heightMM = min(nextHeight, pageSize.height)
            placement.originXMM = min(placement.originXMM, max(pageSize.width - placement.widthMM, 0))
            placement.originYMM = min(placement.originYMM, max(pageSize.height - placement.heightMM, 0))
        }
    }

    func adjustSelectedStampWidth(deltaMM: Double) {
        mutateSelectedStamp { placement, pageSize in
            let currentAspectRatio = max(placement.widthMM / max(placement.heightMM, 0.1), 0.1)
            let nextWidth = max(placement.widthMM + deltaMM, 5.0)
            placement.widthMM = min(nextWidth, pageSize.width)

            if placement.aspectRatioLocked {
                placement.heightMM = min(max(placement.widthMM / currentAspectRatio, 5.0), pageSize.height)
            }

            placement.originXMM = min(placement.originXMM, max(pageSize.width - placement.widthMM, 0))
            placement.originYMM = min(placement.originYMM, max(pageSize.height - placement.heightMM, 0))
        }
    }

    func adjustSelectedStampHeight(deltaMM: Double) {
        mutateSelectedStamp { placement, pageSize in
            if placement.aspectRatioLocked {
                let currentAspectRatio = max(placement.widthMM / max(placement.heightMM, 0.1), 0.1)
                let nextHeight = max(placement.heightMM + deltaMM, 5.0)
                placement.heightMM = min(nextHeight, pageSize.height)
                placement.widthMM = min(max(placement.heightMM * currentAspectRatio, 5.0), pageSize.width)
            } else {
                placement.heightMM = min(max(placement.heightMM + deltaMM, 5.0), pageSize.height)
            }

            placement.originXMM = min(placement.originXMM, max(pageSize.width - placement.widthMM, 0))
            placement.originYMM = min(placement.originYMM, max(pageSize.height - placement.heightMM, 0))
        }
    }

    func adjustSelectedStampOpacity(delta: Double) {
        mutateSelectedStamp { placement, _ in
            placement.opacity = min(max(placement.opacity + delta, 0.1), 1.0)
        }
    }

    func saveDraft() async {
        do {
            draftStatusMessage = "保存中..."
            try await draftRecoveryService.saveDraft(session: session)
            draftStatusMessage = "草稿已保存"
            await issueLogService.recordFeedback(
                "草稿手动保存成功",
                category: .draftSave,
                context: ["documentID": session.document.id.uuidString]
            )
        } catch {
            draftStatusMessage = "草稿保存失败"
            await issueLogService.recordError(
                "草稿手动保存失败",
                error: error,
                category: .draftSave,
                context: ["documentID": session.document.id.uuidString]
            )
        }
    }

    func exportPDF() async {
        isExportingPDF = true
        exportStatusMessage = "正在生成导出文件..."
        exportDetailMessage = "将优先渲染真实页面内容与真实印章素材。"

        await issueLogService.recordFeedback(
            "开始导出",
            category: .export,
            context: [
                "documentID": session.document.id.uuidString,
                "pageCount": String(session.document.pageCount)
            ]
        )

        do {
            let exportedURL = try await pdfExportService.export(session: session)
            lastExportURL = exportedURL
            exportStatusMessage = "已导出：\(exportedURL.lastPathComponent)"
            exportDetailMessage = "导出完成，可以点击分享按钮继续保存或发送。"
            await issueLogService.recordFeedback(
                "导出成功",
                category: .export,
                context: [
                    "documentID": session.document.id.uuidString,
                    "exportFile": exportedURL.lastPathComponent
                ]
            )
        } catch {
            lastExportURL = nil
            exportStatusMessage = exportMessage(for: error)
            exportDetailMessage = exportDetailMessageText(for: error)
            await issueLogService.recordError(
                "导出失败",
                error: error,
                category: .export,
                context: ["documentID": session.document.id.uuidString]
            )
        }

        isExportingPDF = false
    }

    private func refreshSelectionForActivePage() {
        normalizeSelectionForActivePage()
    }

    private func mutateSelectedStamp(_ mutate: (inout StampPlacement, MillimeterSize) -> Void) {
        guard let selectedObjectID = session.selectedObjectID else {
            return
        }

        guard let objectIndex = session.document.editorObjects.firstIndex(where: { $0.id == selectedObjectID }) else {
            return
        }

        guard var placement = session.document.editorObjects[objectIndex].stampPlacement else {
            return
        }

        let objectPageIndex = session.document.editorObjects[objectIndex].pageIndex
        guard session.document.pages.indices.contains(objectPageIndex) else {
            return
        }

        let pageSizeMM = document.pages[objectPageIndex].a4CanvasSizePT.asMillimeterSize
        mutate(&placement, pageSizeMM)
        session.document.editorObjects[objectIndex].stampPlacement = placement
        touchSession()
    }

    private func normalizeSelectionForActivePage() {
        let objectsOnPage = session.document.editorObjects
            .filter { $0.pageIndex == session.activePageIndex }
            .sorted { $0.zIndex < $1.zIndex }

        let currentSelectionIsOnActivePage = objectsOnPage.contains { $0.id == session.selectedObjectID }
        let nextSelectedID = currentSelectionIsOnActivePage ? session.selectedObjectID : objectsOnPage.first?.id
        session.selectedObjectID = nextSelectedID

        for index in session.document.editorObjects.indices {
            let object = session.document.editorObjects[index]
            session.document.editorObjects[index].isSelected =
                object.pageIndex == session.activePageIndex && object.id == nextSelectedID
        }
    }

    private func touchSession() {
        session.document.updatedAt = Date()
        session.document.draftVersion += 1
        draftStatusMessage = "草稿待保存"
        scheduleAutoSave()
    }

    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        let snapshot = session

        autoSaveTask = Task {
            await MainActor.run {
                self.draftStatusMessage = "自动保存中..."
            }

            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            do {
                try await draftRecoveryService.saveDraft(session: snapshot)
                await MainActor.run {
                    self.draftStatusMessage = "草稿已自动保存"
                }
                await issueLogService.recordFeedback(
                    "草稿自动保存成功",
                    category: .draftSave,
                    context: ["documentID": snapshot.document.id.uuidString]
                )
            } catch {
                await MainActor.run {
                    self.draftStatusMessage = "自动保存失败"
                }
                await issueLogService.recordError(
                    "草稿自动保存失败",
                    error: error,
                    category: .draftSave,
                    context: ["documentID": snapshot.document.id.uuidString]
                )
            }
        }
    }

    private func exportMessage(for error: Error) -> String {
        if error is CancellationError {
            return "已取消导出"
        }

        guard let exportError = error as? PDFExportError else {
            return "导出失败，请重试。"
        }

        switch exportError {
        case .noPages:
            return "导出失败：当前文档没有可导出页面。"
        case .exportDirectoryUnavailable:
            return "导出失败：无法创建导出目录。"
        case .writeFailed:
            return "导出失败：PDF 写入失败。"
        }
    }

    private func exportDetailMessageText(for error: Error) -> String {
        if error is CancellationError {
            return "导出流程已被取消，没有生成新的文件。"
        }

        guard let exportError = error as? PDFExportError else {
            return "导出过程遇到未知错误，请重试。"
        }

        switch exportError {
        case .noPages:
            return "当前文档没有可导出的页面，需要先导入内容或恢复草稿。"
        case .exportDirectoryUnavailable:
            return "导出目录无法创建，可能是缓存目录权限或磁盘状态异常。"
        case .writeFailed:
            return "PDF 写入过程中失败，可能是文件名冲突、存储受限或渲染异常。"
        }
    }
}
