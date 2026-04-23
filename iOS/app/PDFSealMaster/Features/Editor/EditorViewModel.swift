import Foundation

@MainActor
final class EditorViewModel: ObservableObject {
    @Published private(set) var session: EditorSession
    @Published private(set) var availableStampAssets: [StampAsset] = []
    @Published private(set) var selectedStampAssetID: UUID?
    @Published private(set) var availableSignatureAssets: [SignatureAsset] = []
    @Published private(set) var selectedSignatureAssetID: UUID?
    @Published private(set) var lastExportURL: URL?
    @Published private(set) var exportStatusMessage = "尚未导出"
    @Published private(set) var exportDetailMessage = "导出后可使用分享按钮保存或发送。"
    @Published private(set) var isExportingPDF = false
    @Published private(set) var draftStatusMessage = "自动保存已启用"
    @Published private(set) var signatureSyncStatusMessage = "签名素材已就绪"
    @Published private(set) var signatureReplaceReceiptMessage = "暂无替换回执。"
    @Published private(set) var stampSizeSyncStatusMessage = "统一尺寸未执行。"

    private let draftRecoveryService: DraftRecoveryService
    private let stampAssetService: StampAssetService
    private let signatureAssetService: SignatureAssetService
    private let pdfExportService: PDFExportService
    private let issueLogService: IssueLogService
    private var autoSaveTask: Task<Void, Never>?

    init(
        session: EditorSession,
        draftRecoveryService: DraftRecoveryService,
        stampAssetService: StampAssetService,
        signatureAssetService: SignatureAssetService,
        pdfExportService: PDFExportService,
        issueLogService: IssueLogService
    ) {
        self.session = session
        self.draftRecoveryService = draftRecoveryService
        self.stampAssetService = stampAssetService
        self.signatureAssetService = signatureAssetService
        self.pdfExportService = pdfExportService
        self.issueLogService = issueLogService
        self.signatureReplaceReceiptMessage = session.signatureReplaceReceiptMessage
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
            return "未选中对象"
        }

        if let stamp = selectedObject.stampPlacement {
            return "印章：\(String(format: "%.1f", stamp.originXMM))mm, \(String(format: "%.1f", stamp.originYMM))mm · \(String(format: "%.1f", stamp.widthMM)) × \(String(format: "%.1f", stamp.heightMM)) mm"
        }

        if let signature = selectedObject.signaturePlacement {
            return "签名：\(String(format: "%.1f", signature.originXMM))mm, \(String(format: "%.1f", signature.originYMM))mm · \(String(format: "%.1f", signature.widthMM)) × \(String(format: "%.1f", signature.heightMM)) mm"
        }

        return "未选中对象"
    }

    var selectedStampPlacement: StampPlacement? {
        selectedObject?.stampPlacement
    }

    var selectedSignaturePlacement: SignaturePlacement? {
        selectedObject?.signaturePlacement
    }

    var selectedStampName: String {
        guard
            let selectedStampAssetID,
            let asset = availableStampAssets.first(where: { $0.id == selectedStampAssetID })
        else {
            return "未选择"
        }

        return asset.name
    }

    var availableStampCount: Int {
        availableStampAssets.count
    }

    var stampPlacementCount: Int {
        session.document.editorObjects.reduce(into: 0) { count, object in
            if object.stampPlacement != nil {
                count += 1
            }
        }
    }

    var stampPlacementCountOnActivePage: Int {
        session.document.editorObjects.reduce(into: 0) { count, object in
            guard object.pageIndex == session.activePageIndex else {
                return
            }
            if object.stampPlacement != nil {
                count += 1
            }
        }
    }

    var canUnifyStampSizesGlobally: Bool {
        selectedStampPlacement != nil && stampPlacementCount > 1
    }

    var canUnifyStampSizesOnActivePage: Bool {
        selectedStampPlacement != nil && stampPlacementCountOnActivePage > 1
    }

    var stampSizeSyncTargetText: String {
        guard let selectedStampPlacement else {
            return "请选择一个印章对象作为统一尺寸基准。"
        }
        return "基准尺寸：\(String(format: "%.1f", selectedStampPlacement.widthMM)) × \(String(format: "%.1f", selectedStampPlacement.heightMM)) mm"
    }

    var selectedSignatureName: String {
        guard
            let selectedSignatureAssetID,
            let asset = availableSignatureAssets.first(where: { $0.id == selectedSignatureAssetID })
        else {
            return "未选择"
        }

        return asset.name
    }

    var availableSignatureCount: Int {
        availableSignatureAssets.count
    }

    var missingSignaturePlacementCount: Int {
        let availableIDs = Set(availableSignatureAssets.map(\.id))
        return signaturePlacementMissingCount(using: availableIDs)
    }

    var hasMissingSignaturePlacement: Bool {
        missingSignaturePlacementCount > 0
    }

    var canBulkReplaceMissingSignatures: Bool {
        guard let selectedSignatureAssetID else {
            return false
        }

        let hasTargetAsset = availableSignatureAssets.contains { $0.id == selectedSignatureAssetID }
        return hasTargetAsset && hasMissingSignaturePlacement
    }

    var missingSignaturePlacementCountOnActivePage: Int {
        let availableIDs = Set(availableSignatureAssets.map(\.id))
        return signaturePlacementMissingCount(
            using: availableIDs,
            pageIndex: session.activePageIndex
        )
    }

    var hasMissingSignaturePlacementOnActivePage: Bool {
        missingSignaturePlacementCountOnActivePage > 0
    }

    var canBulkReplaceMissingSignaturesOnActivePage: Bool {
        guard let selectedSignatureAssetID else {
            return false
        }

        let hasTargetAsset = availableSignatureAssets.contains { $0.id == selectedSignatureAssetID }
        return hasTargetAsset && hasMissingSignaturePlacementOnActivePage
    }

    var selectedSignatureAssetReadyForRepair: Bool {
        guard let selectedSignatureAssetID else {
            return false
        }
        return availableSignatureAssets.contains { $0.id == selectedSignatureAssetID }
    }

    var canLocateMissingSignaturePlacement: Bool {
        hasMissingSignaturePlacement
    }

    var missingSignatureOverviewText: String {
        if hasMissingSignaturePlacement {
            return "共 \(missingSignaturePlacementCount) 个缺失引用（本页 \(missingSignaturePlacementCountOnActivePage) 个）。"
        }
        return "未检测到缺失签名引用。"
    }

    var signatureRepairTargetText: String {
        let selectedName = selectedSignatureName
        if selectedSignatureAssetReadyForRepair {
            return "替换目标：\(selectedName)"
        }
        return "替换目标未就绪：请先选择并刷新签名素材。"
    }

    var selectedSignaturePlacementAssetName: String {
        guard let placement = selectedSignaturePlacement else {
            return "未选中签名对象"
        }

        if let asset = availableSignatureAssets.first(where: { $0.id == placement.assetID }) {
            return asset.name
        }

        return "素材缺失（\(placement.assetID.uuidString.prefix(8))）"
    }

    var selectedSignaturePlacementAssetMissing: Bool {
        guard let placement = selectedSignaturePlacement else {
            return false
        }
        return !availableSignatureAssets.contains(where: { $0.id == placement.assetID })
    }

    var canQuickReplaceSelectedSignature: Bool {
        guard
            let placement = selectedSignaturePlacement,
            let selectedSignatureAssetID
        else {
            return false
        }

        return placement.assetID != selectedSignatureAssetID
    }

    func loadEditorAssets() async {
        await loadStampAssets()
        await loadSignatureAssets()
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

    func loadSignatureAssets() async {
        do {
            let assets = try await signatureAssetService.loadAllSignatureAssets()
            availableSignatureAssets = assets
            let availableIDs = Set(assets.map(\.id))
            if let selectedSignatureAssetID, availableIDs.contains(selectedSignatureAssetID) {
                self.selectedSignatureAssetID = selectedSignatureAssetID
            } else {
                selectedSignatureAssetID = assets.first?.id
            }

            let missingCount = signaturePlacementMissingCount(using: availableIDs)
            if missingCount > 0 {
                signatureSyncStatusMessage = "检测到 \(missingCount) 个签名对象引用了缺失素材，请选中对象后快速替换。"
            } else {
                signatureSyncStatusMessage = "签名素材与编辑对象已同步。"
            }
        } catch {
            availableSignatureAssets = []
            selectedSignatureAssetID = nil
            signatureSyncStatusMessage = "签名素材加载失败。"
            await issueLogService.recordError(
                "编辑页加载签名素材失败",
                error: error,
                category: .signatureImport,
                context: ["scope": "loadSignatureAssets"]
            )
        }
    }

    func refreshSignatureAssetsForEditor() async {
        await loadSignatureAssets()
        await issueLogService.recordFeedback(
            "编辑页手动刷新签名素材",
            category: .signatureImport,
            context: [
                "documentID": session.document.id.uuidString,
                "assetCount": String(availableSignatureAssets.count),
                "missingPlacementCount": String(missingSignaturePlacementCount)
            ]
        )
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

    func insertSelectedSignature() {
        guard
            let selectedSignatureAssetID,
            let asset = availableSignatureAssets.first(where: { $0.id == selectedSignatureAssetID })
        else {
            return
        }

        let pageSizeMM = document.pages[session.activePageIndex].a4CanvasSizePT.asMillimeterSize
        let signatureWidthMM = min(max(pageSizeMM.width * 0.28, 24), 70)
        let aspectRatio = signatureAspectRatio(for: asset)
        let signatureHeightMM = min(max(signatureWidthMM / max(aspectRatio, 0.1), 8), pageSizeMM.height * 0.4)
        let originXMM = max((pageSizeMM.width - signatureWidthMM) / 2.0, 0)
        let originYMM = max((pageSizeMM.height - signatureHeightMM) * 0.72, 0)
        let zIndex = (document.editorObjects.map(\.zIndex).max() ?? -1) + 1

        let placement = SignaturePlacement(
            pageIndex: session.activePageIndex,
            assetID: asset.id,
            originXMM: originXMM,
            originYMM: originYMM,
            widthMM: signatureWidthMM,
            heightMM: signatureHeightMM,
            rotation: 0,
            opacity: 0.95,
            zIndex: zIndex
        )

        let editorObject = EditorObject(
            pageIndex: session.activePageIndex,
            type: .signature,
            zIndex: zIndex,
            isSelected: true,
            stampPlacement: nil,
            signaturePlacement: placement
        )

        for index in session.document.editorObjects.indices {
            session.document.editorObjects[index].isSelected = false
        }

        session.document.editorObjects.append(editorObject)
        session.selectedObjectID = editorObject.id
        touchSession()
    }

    func cycleSelectedSignatureAsset() {
        guard !availableSignatureAssets.isEmpty else {
            selectedSignatureAssetID = nil
            return
        }

        guard let selectedSignatureAssetID else {
            self.selectedSignatureAssetID = availableSignatureAssets.first?.id
            return
        }

        guard let currentIndex = availableSignatureAssets.firstIndex(where: { $0.id == selectedSignatureAssetID }) else {
            self.selectedSignatureAssetID = availableSignatureAssets.first?.id
            return
        }

        let nextIndex = (currentIndex + 1) % availableSignatureAssets.count
        self.selectedSignatureAssetID = availableSignatureAssets[nextIndex].id
    }

    func replaceSelectedSignatureAsset() async {
        guard let selectedSignatureAssetID else {
            signatureSyncStatusMessage = "请先选择目标签名素材。"
            return
        }

        guard let selectedObjectID = session.selectedObjectID else {
            signatureSyncStatusMessage = "请先选中签名对象。"
            return
        }

        guard let objectIndex = session.document.editorObjects.firstIndex(where: { $0.id == selectedObjectID }) else {
            signatureSyncStatusMessage = "未找到选中的对象。"
            return
        }

        guard var signaturePlacement = session.document.editorObjects[objectIndex].signaturePlacement else {
            signatureSyncStatusMessage = "当前对象不是签名对象。"
            return
        }

        let objectPageIndex = session.document.editorObjects[objectIndex].pageIndex
        if signaturePlacement.assetID == selectedSignatureAssetID {
            signatureSyncStatusMessage = "当前签名对象已使用所选素材。"
            return
        }

        let previousAssetID = signaturePlacement.assetID
        signaturePlacement.assetID = selectedSignatureAssetID
        session.document.editorObjects[objectIndex].signaturePlacement = signaturePlacement
        signatureSyncStatusMessage = "已完成签名素材替换。"
        recordSignatureReplacementReceipt(
            scope: "Single",
            replacedCount: 1,
            touchedPages: [objectPageIndex]
        )
        touchSession()

        await issueLogService.recordFeedback(
            "编辑页签名对象素材替换成功",
            category: .signatureImport,
            context: [
                "documentID": session.document.id.uuidString,
                "objectID": selectedObjectID.uuidString,
                "previousAssetID": previousAssetID.uuidString,
                "newAssetID": selectedSignatureAssetID.uuidString
            ]
        )
    }

    func signatureAssetDisplayName(for assetID: UUID) -> String {
        if let asset = availableSignatureAssets.first(where: { $0.id == assetID }) {
            return asset.name
        }
        return "缺失（\(assetID.uuidString.prefix(8))）"
    }

    func isSignatureAssetMissing(assetID: UUID) -> Bool {
        !availableSignatureAssets.contains(where: { $0.id == assetID })
    }

    func focusFirstMissingSignaturePlacement() async {
        let availableIDs = Set(availableSignatureAssets.map(\.id))
        let missingCandidates = session.document.editorObjects
            .filter { object in
                guard let signature = object.signaturePlacement else {
                    return false
                }
                return !availableIDs.contains(signature.assetID)
            }
            .sorted { lhs, rhs in
                if lhs.pageIndex == rhs.pageIndex {
                    return lhs.zIndex < rhs.zIndex
                }
                return lhs.pageIndex < rhs.pageIndex
            }

        guard let target = missingCandidates.first else {
            signatureSyncStatusMessage = "未找到缺失签名引用。"
            return
        }

        session.activePageIndex = target.pageIndex
        session.selectedObjectID = target.id
        for index in session.document.editorObjects.indices {
            session.document.editorObjects[index].isSelected = session.document.editorObjects[index].id == target.id
        }

        signatureSyncStatusMessage = "已定位到缺失签名对象（第 \(target.pageIndex + 1) 页）。"
        touchSession()

        await issueLogService.recordFeedback(
            "定位缺失签名对象成功",
            category: .signatureImport,
            context: [
                "documentID": session.document.id.uuidString,
                "objectID": target.id.uuidString,
                "pageIndex": String(target.pageIndex)
            ]
        )
    }

    func replaceAllMissingSignaturePlacements() async {
        guard let targetAssetID = selectedSignatureAssetID else {
            signatureSyncStatusMessage = "请先选择替换用签名素材。"
            return
        }

        guard availableSignatureAssets.contains(where: { $0.id == targetAssetID }) else {
            signatureSyncStatusMessage = "当前选中的签名素材不可用，请先刷新签名素材。"
            return
        }

        let availableIDs = Set(availableSignatureAssets.map(\.id))
        var replacedCount = 0
        var firstReplacedObjectID: UUID?
        var firstReplacedPageIndex: Int?
        var touchedPages = Set<Int>()

        for index in session.document.editorObjects.indices {
            guard var signaturePlacement = session.document.editorObjects[index].signaturePlacement else {
                continue
            }

            guard !availableIDs.contains(signaturePlacement.assetID) else {
                continue
            }

            if firstReplacedObjectID == nil {
                firstReplacedObjectID = session.document.editorObjects[index].id
                firstReplacedPageIndex = session.document.editorObjects[index].pageIndex
            }

            touchedPages.insert(session.document.editorObjects[index].pageIndex)
            signaturePlacement.assetID = targetAssetID
            session.document.editorObjects[index].signaturePlacement = signaturePlacement
            replacedCount += 1
        }

        guard replacedCount > 0 else {
            signatureSyncStatusMessage = "没有可批量替换的缺失签名对象。"
            return
        }

        if let firstReplacedObjectID, let firstReplacedPageIndex {
            session.activePageIndex = firstReplacedPageIndex
            session.selectedObjectID = firstReplacedObjectID
            normalizeSelectionForActivePage()
        }

        signatureSyncStatusMessage = "已批量替换 \(replacedCount) 个缺失签名对象。"
        recordSignatureReplacementReceipt(
            scope: "Global",
            replacedCount: replacedCount,
            touchedPages: touchedPages
        )
        touchSession()

        await issueLogService.recordFeedback(
            "批量替换缺失签名对象成功",
            category: .signatureImport,
            context: [
                "documentID": session.document.id.uuidString,
                "targetAssetID": targetAssetID.uuidString,
                "replacedCount": String(replacedCount)
            ]
        )
    }

    func replaceMissingSignaturesOnActivePage() async {
        guard let targetAssetID = selectedSignatureAssetID else {
            signatureSyncStatusMessage = "请先选择替换用签名素材。"
            return
        }

        guard availableSignatureAssets.contains(where: { $0.id == targetAssetID }) else {
            signatureSyncStatusMessage = "当前选中的签名素材不可用，请先刷新签名素材。"
            return
        }

        let availableIDs = Set(availableSignatureAssets.map(\.id))
        var replacedCount = 0
        var firstReplacedObjectID: UUID?

        for index in session.document.editorObjects.indices {
            let object = session.document.editorObjects[index]
            guard object.pageIndex == session.activePageIndex else {
                continue
            }

            guard var signaturePlacement = object.signaturePlacement else {
                continue
            }

            guard !availableIDs.contains(signaturePlacement.assetID) else {
                continue
            }

            if firstReplacedObjectID == nil {
                firstReplacedObjectID = object.id
            }

            signaturePlacement.assetID = targetAssetID
            session.document.editorObjects[index].signaturePlacement = signaturePlacement
            replacedCount += 1
        }

        guard replacedCount > 0 else {
            signatureSyncStatusMessage = "当前页没有可替换的缺失签名对象。"
            return
        }

        if let firstReplacedObjectID {
            session.selectedObjectID = firstReplacedObjectID
            normalizeSelectionForActivePage()
        }

        signatureSyncStatusMessage = "当前页已替换 \(replacedCount) 个缺失签名对象。"
        recordSignatureReplacementReceipt(
            scope: "Page \(session.activePageIndex + 1)",
            replacedCount: replacedCount,
            touchedPages: [session.activePageIndex]
        )
        touchSession()

        await issueLogService.recordFeedback(
            "当前页批量替换缺失签名对象成功",
            category: .signatureImport,
            context: [
                "documentID": session.document.id.uuidString,
                "pageIndex": String(session.activePageIndex),
                "targetAssetID": targetAssetID.uuidString,
                "replacedCount": String(replacedCount)
            ]
        )
    }

    private func signatureAspectRatio(for asset: SignatureAsset) -> Double {
        guard let imagePath = signatureImagePath(for: asset) else {
            return 3.2
        }

        let imageURL = URL(fileURLWithPath: imagePath)
        guard let size = ImageFileInspector.displayPixelSize(for: imageURL), size.width > 0, size.height > 0 else {
            return 3.2
        }

        return max(size.width / size.height, 0.5)
    }

    private func signatureImagePath(for asset: SignatureAsset) -> String? {
        if let normalizedPath = asset.normalizedTransparentImagePath, !normalizedPath.isEmpty {
            return normalizedPath
        }

        return asset.originalSignaturePath.isEmpty ? nil : asset.originalSignaturePath
    }

    private func signaturePlacementMissingCount(
        using availableSignatureIDs: Set<UUID>,
        pageIndex: Int? = nil
    ) -> Int {
        session.document.editorObjects.reduce(into: 0) { count, object in
            if let pageIndex, object.pageIndex != pageIndex {
                return
            }

            guard let signaturePlacement = object.signaturePlacement else {
                return
            }

            if !availableSignatureIDs.contains(signaturePlacement.assetID) {
                count += 1
            }
        }
    }

    private func recordSignatureReplacementReceipt(
        scope: String,
        replacedCount: Int,
        touchedPages: Set<Int>
    ) {
        let pagesText = touchedPages.isEmpty
            ? "-"
            : touchedPages
                .sorted()
                .map { String($0 + 1) }
                .joined(separator: ",")
        let remainingMissing = missingSignaturePlacementCount
        let timestamp = replacementTimestampText()
        let localizedScope = localizedReplacementScope(scope)
        signatureReplaceReceiptMessage = "[\(timestamp)] \(localizedScope)替换：已替换\(replacedCount)个对象，页码：\(pagesText)，剩余缺失：\(remainingMissing)"
        session.signatureReplaceReceiptMessage = signatureReplaceReceiptMessage
    }

    private func localizedReplacementScope(_ scope: String) -> String {
        switch scope {
        case "Single":
            return "单对象"
        case "Global":
            return "全稿"
        default:
            if scope.hasPrefix("Page ") {
                let pageText = scope.replacingOccurrences(of: "Page ", with: "")
                return "第\(pageText)页"
            }
            return scope
        }
    }

    private func replacementTimestampText() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
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
        mutateSelectedObjectPlacement(
            mutateStamp: { placement, pageSize in
                placement.originXMM = min(max(placement.originXMM + deltaXMM, 0), max(pageSize.width - placement.widthMM, 0))
                placement.originYMM = min(max(placement.originYMM + deltaYMM, 0), max(pageSize.height - placement.heightMM, 0))
            },
            mutateSignature: { placement, pageSize in
                placement.originXMM = min(max(placement.originXMM + deltaXMM, 0), max(pageSize.width - placement.widthMM, 0))
                placement.originYMM = min(max(placement.originYMM + deltaYMM, 0), max(pageSize.height - placement.heightMM, 0))
            }
        )
    }

    func resizeSelectedStamp(deltaMM: Double) {
        mutateSelectedObjectPlacement(
            mutateStamp: { placement, pageSize in
                let currentAspectRatio = max(placement.widthMM / max(placement.heightMM, 0.1), 0.1)
                let nextWidth = max(placement.widthMM + deltaMM, 5.0)
                let nextHeight = placement.aspectRatioLocked
                    ? max(nextWidth / currentAspectRatio, 5.0)
                    : max(placement.heightMM + deltaMM, 5.0)

                placement.widthMM = min(nextWidth, pageSize.width)
                placement.heightMM = min(nextHeight, pageSize.height)
                placement.originXMM = min(placement.originXMM, max(pageSize.width - placement.widthMM, 0))
                placement.originYMM = min(placement.originYMM, max(pageSize.height - placement.heightMM, 0))
            },
            mutateSignature: { placement, pageSize in
                let nextWidth = max(placement.widthMM + deltaMM, 5.0)
                let nextHeight = max(placement.heightMM + deltaMM, 5.0)
                placement.widthMM = min(nextWidth, pageSize.width)
                placement.heightMM = min(nextHeight, pageSize.height)
                placement.originXMM = min(placement.originXMM, max(pageSize.width - placement.widthMM, 0))
                placement.originYMM = min(placement.originYMM, max(pageSize.height - placement.heightMM, 0))
            }
        )
    }

    func adjustSelectedStampWidth(deltaMM: Double) {
        mutateSelectedObjectPlacement(
            mutateStamp: { placement, pageSize in
                let currentAspectRatio = max(placement.widthMM / max(placement.heightMM, 0.1), 0.1)
                let nextWidth = max(placement.widthMM + deltaMM, 5.0)
                placement.widthMM = min(nextWidth, pageSize.width)

                if placement.aspectRatioLocked {
                    placement.heightMM = min(max(placement.widthMM / currentAspectRatio, 5.0), pageSize.height)
                }

                placement.originXMM = min(placement.originXMM, max(pageSize.width - placement.widthMM, 0))
                placement.originYMM = min(placement.originYMM, max(pageSize.height - placement.heightMM, 0))
            },
            mutateSignature: { placement, pageSize in
                placement.widthMM = min(max(placement.widthMM + deltaMM, 5.0), pageSize.width)
                placement.originXMM = min(placement.originXMM, max(pageSize.width - placement.widthMM, 0))
            }
        )
    }

    func adjustSelectedStampHeight(deltaMM: Double) {
        mutateSelectedObjectPlacement(
            mutateStamp: { placement, pageSize in
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
            },
            mutateSignature: { placement, pageSize in
                placement.heightMM = min(max(placement.heightMM + deltaMM, 5.0), pageSize.height)
                placement.originYMM = min(placement.originYMM, max(pageSize.height - placement.heightMM, 0))
            }
        )
    }

    func adjustSelectedStampOpacity(delta: Double) {
        mutateSelectedObjectPlacement(
            mutateStamp: { placement, _ in
                placement.opacity = min(max(placement.opacity + delta, 0.1), 1.0)
            },
            mutateSignature: { placement, _ in
                placement.opacity = min(max(placement.opacity + delta, 0.1), 1.0)
            }
        )
    }

    func unifyStampSizesOnActivePage() async {
        await unifyStampSizes(scope: .activePage)
    }

    func unifyStampSizesGlobally() async {
        await unifyStampSizes(scope: .global)
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
        exportDetailMessage = "将优先渲染真实页面内容与印章/签名素材。"

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

    private func mutateSelectedObjectPlacement(
        mutateStamp: ((inout StampPlacement, MillimeterSize) -> Void)? = nil,
        mutateSignature: ((inout SignaturePlacement, MillimeterSize) -> Void)? = nil
    ) {
        guard let selectedObjectID = session.selectedObjectID else {
            return
        }

        guard let objectIndex = session.document.editorObjects.firstIndex(where: { $0.id == selectedObjectID }) else {
            return
        }

        let objectPageIndex = session.document.editorObjects[objectIndex].pageIndex
        guard session.document.pages.indices.contains(objectPageIndex) else {
            return
        }

        let pageSizeMM = document.pages[objectPageIndex].a4CanvasSizePT.asMillimeterSize
        if var stampPlacement = session.document.editorObjects[objectIndex].stampPlacement,
           let mutateStamp
        {
            mutateStamp(&stampPlacement, pageSizeMM)
            session.document.editorObjects[objectIndex].stampPlacement = stampPlacement
            touchSession()
            return
        }

        if var signaturePlacement = session.document.editorObjects[objectIndex].signaturePlacement,
           let mutateSignature
        {
            mutateSignature(&signaturePlacement, pageSizeMM)
            session.document.editorObjects[objectIndex].signaturePlacement = signaturePlacement
            touchSession()
        }
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

    private enum StampSizeSyncScope {
        case activePage
        case global
    }

    private func unifyStampSizes(scope: StampSizeSyncScope) async {
        guard let selectedStamp = selectedStampPlacement else {
            stampSizeSyncStatusMessage = "请先选中一个印章对象。"
            return
        }

        let targetWidth = max(selectedStamp.widthMM, 5.0)
        let targetHeight = max(selectedStamp.heightMM, 5.0)
        var updatedCount = 0
        var touchedPages = Set<Int>()

        for index in session.document.editorObjects.indices {
            guard var placement = session.document.editorObjects[index].stampPlacement else {
                continue
            }

            if scope == .activePage, placement.pageIndex != session.activePageIndex {
                continue
            }

            guard session.document.pages.indices.contains(placement.pageIndex) else {
                continue
            }

            let pageSizeMM = session.document.pages[placement.pageIndex].a4CanvasSizePT.asMillimeterSize
            let nextWidth = min(targetWidth, pageSizeMM.width)
            let nextHeight = min(targetHeight, pageSizeMM.height)
            let nextOriginX = min(max(placement.originXMM, 0), max(pageSizeMM.width - nextWidth, 0))
            let nextOriginY = min(max(placement.originYMM, 0), max(pageSizeMM.height - nextHeight, 0))

            let hasChanged =
                abs(placement.widthMM - nextWidth) > 0.0001 ||
                abs(placement.heightMM - nextHeight) > 0.0001 ||
                abs(placement.originXMM - nextOriginX) > 0.0001 ||
                abs(placement.originYMM - nextOriginY) > 0.0001

            guard hasChanged else {
                continue
            }

            placement.widthMM = nextWidth
            placement.heightMM = nextHeight
            placement.originXMM = nextOriginX
            placement.originYMM = nextOriginY
            session.document.editorObjects[index].stampPlacement = placement
            updatedCount += 1
            touchedPages.insert(placement.pageIndex)
        }

        guard updatedCount > 0 else {
            stampSizeSyncStatusMessage = scope == .global
                ? "全稿印章尺寸已一致，无需同步。"
                : "本页印章尺寸已一致，无需同步。"
            return
        }

        touchSession()

        let pagesText = touchedPages
            .sorted()
            .map { String($0 + 1) }
            .joined(separator: ",")

        stampSizeSyncStatusMessage = scope == .global
            ? "已统一全稿 \(updatedCount) 个印章对象尺寸（页码：\(pagesText)）。"
            : "已统一本页 \(updatedCount) 个印章对象尺寸。"

        await issueLogService.recordFeedback(
            "统一印章尺寸完成",
            category: .stampImport,
            context: [
                "documentID": session.document.id.uuidString,
                "scope": scope == .global ? "global" : "activePage",
                "updatedCount": String(updatedCount),
                "targetWidthMM": String(format: "%.2f", targetWidth),
                "targetHeightMM": String(format: "%.2f", targetHeight),
                "activePageIndex": String(session.activePageIndex)
            ]
        )
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
