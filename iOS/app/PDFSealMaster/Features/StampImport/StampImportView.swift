import SwiftUI
import UniformTypeIdentifiers

struct StampImportView: View {
    let stampAssetService: StampAssetService
    let issueLogService: IssueLogService
    let onClose: () -> Void
    private let normalizationService: StampNormalizationService = DefaultStampNormalizationService()

    @State private var workingAsset: StampAsset?
    @State private var savedAssetCount = 0
    @State private var isProcessing = false
    @State private var isShowingImporter = false
    @State private var stampName = ""
    @State private var targetSizeMM = 40.0
    @State private var statusMessage = "请选择一张印章图片开始导入。"
    @State private var cropInsetLeftPX = 0.0
    @State private var cropInsetTopPX = 0.0
    @State private var cropInsetRightPX = 0.0
    @State private var cropInsetBottomPX = 0.0
    @State private var cropDragStartInsets: CropInsets?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("鍏抽棴", action: onClose)
                Spacer()
                Text("鍗扮珷瀵煎叆楠ㄦ灦")
                    .font(.headline)
                Spacer()
            }

            Text("这一页先对齐规范后的导入链路：导入、自动规范化、必要时手动裁切、再设定真实尺寸。")
                .foregroundStyle(.secondary)

            Button("閫夋嫨鍗扮珷鍥剧墖") {
                isShowingImporter = true
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)

            TextField("鍗扮珷鍚嶇О锛堥粯璁ゅ彇鏂囦欢鍚嶏級", text: $stampName)
                .textFieldStyle(.roundedBorder)
                .disabled(isProcessing)

            Stepper(value: $targetSizeMM, in: 5...80, step: 0.5) {
                Text("鐩爣鐪熷疄灏哄锛\(targetSizeMM, specifier: "%.1f") mm")
            }
            .disabled(isProcessing)

            Text("褰撳墠绱犳潗姹犲嵃绔犳暟锛\(savedAssetCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let workingAsset {
                VStack(alignment: .leading, spacing: 8) {
                    Text("绱犳潗鍚嶏細\(workingAsset.name)")
                    Text("鐘舵€侊細\(workingAsset.normalizationStatus.rawValue)")
                    Text("鐩爣灏哄锛\(workingAsset.finalPhysicalSizeMM ?? targetSizeMM, specifier: "%.1f") mm")
                    Text("鏈夋晥杈圭晫锛\(boundsSummary(for: workingAsset))")
                    Text("瑁佽竟棰勮锛\(boundsSummary(for: manualCropPreview(for: workingAsset)))")
                    Text("schemaVersion锛\(workingAsset.schemaVersion)")
                }
                .font(.subheadline)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                cropControlPanel(for: workingAsset)
            }

            HStack(spacing: 12) {
                Button("自动规范化") {
                    Task {
                        await autoNormalizeStamp()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing || workingAsset == nil)

                Button("鎵嬪姩寰皟瑁佽竟") {
                    Task {
                        await applyManualCropAdjustment()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing || workingAsset == nil)

                Button("淇濆瓨鍗扮珷绱犳潗") {
                    Task {
                        await finalizeAndSaveStamp()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing || workingAsset == nil)
            }

            if isProcessing {
                ProgressView("澶勭悊涓?..")
                    .font(.caption)
            }

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .task {
            await refreshAssetCount()
        }
        .fileImporter(
            isPresented: $isShowingImporter,
            allowedContentTypes: [.image]
        ) { result in
            Task {
                await handleStampFilePick(result)
            }
        }
    }

    private func refreshAssetCount() async {
        let assets = (try? await stampAssetService.loadAllStampAssets()) ?? []
        savedAssetCount = assets.count
    }

    private func handleStampFilePick(_ result: Result<URL, Error>) async {
        isProcessing = true
        defer { isProcessing = false }

        var stagedURL: URL?
        defer {
            if let stagedURL {
                try? FileManager.default.removeItem(at: stagedURL)
            }
        }

        do {
            let pickedURL = try result.get()
            let resolvedStagedURL = try ImportStagingService.stageExternalFile(pickedURL)
            stagedURL = resolvedStagedURL
            let fallbackName = pickedURL.deletingPathExtension().lastPathComponent
            let resolvedName = stampName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? fallbackName
                : stampName

            workingAsset = try await normalizationService.importStamp(
                from: resolvedStagedURL,
                name: resolvedName
            )
            resetCropInsets()
            statusMessage = "已导入印章图片，下一步可执行自动规范化。"
            await issueLogService.recordFeedback(
                "印章导入成功",
                category: .stampImport,
                context: [
                    "sourceFile": pickedURL.lastPathComponent,
                    "stagedFile": resolvedStagedURL.lastPathComponent,
                    "stampName": resolvedName
                ]
            )
        } catch {
            let failure = classifyStampFailure(error)
            await issueLogService.recordError(
                "印章导入失败",
                error: error,
                category: .stampImport,
                context: [
                    "stampName": stampName,
                    "failureKind": failure.rawValue
                ]
            )
            statusMessage = stampFailureMessage(for: failure, source: .importFile)
        }
    }

    private func autoNormalizeStamp() async {
        guard let workingAsset else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            self.workingAsset = try await normalizationService.autoNormalize(asset: workingAsset)
            resetCropInsets()
            statusMessage = "自动规范化已完成，可按需手动微调后保存。"
            await issueLogService.recordFeedback(
                "印章自动规范化成功",
                category: .stampImport,
                context: ["stampName": workingAsset.name]
            )
        } catch {
            let failure = classifyStampFailure(error)
            await issueLogService.recordError(
                "印章自动规范化失败",
                error: error,
                category: .stampImport,
                context: [
                    "stampName": workingAsset.name,
                    "failureKind": failure.rawValue
                ]
            )
            statusMessage = stampFailureMessage(for: failure, source: .autoNormalize)
        }
    }

    private func applyManualCropAdjustment() async {
        guard let workingAsset else {
            return
        }

        let adjustment = manualCropPreview(for: workingAsset)

        isProcessing = true
        defer { isProcessing = false }

        do {
            self.workingAsset = try await normalizationService.applyManualCrop(
                adjustment,
                to: workingAsset
            )
            statusMessage = "已应用手动裁边微调。"
            await issueLogService.recordFeedback(
                "印章手动裁边成功",
                category: .stampImport,
                context: ["stampName": workingAsset.name]
            )
        } catch {
            let failure = classifyStampFailure(error)
            await issueLogService.recordError(
                "印章手动裁边失败",
                error: error,
                category: .stampImport,
                context: [
                    "stampName": workingAsset.name,
                    "failureKind": failure.rawValue
                ]
            )
            statusMessage = stampFailureMessage(for: failure, source: .manualCrop)
        }
    }

    private func finalizeAndSaveStamp() async {
        guard let workingAsset else {
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            let sized = try await normalizationService.setPhysicalSize(targetSizeMM, for: workingAsset)
            let saved = try await stampAssetService.saveStampAsset(sized)
            self.workingAsset = saved
            statusMessage = "印章素材已保存。"
            await refreshAssetCount()
            await issueLogService.recordFeedback(
                "印章素材保存成功",
                category: .stampImport,
                context: [
                    "stampName": saved.name,
                    "savedAssetCount": String(savedAssetCount)
                ]
            )
        } catch {
            let failure = classifyStampFailure(error)
            await issueLogService.recordError(
                "印章素材保存失败",
                error: error,
                category: .stampImport,
                context: [
                    "stampName": workingAsset.name,
                    "failureKind": failure.rawValue
                ]
            )
            statusMessage = stampFailureMessage(for: failure, source: .saveAsset)
        }
    }

    private func boundsSummary(for asset: StampAsset) -> String {
        guard let bounds = asset.effectiveBoundsPX else {
            return "未识别"
        }

        return "x:\(Int(bounds.x)) y:\(Int(bounds.y)) w:\(Int(bounds.width)) h:\(Int(bounds.height))"
    }

    private func boundsSummary(for bounds: PixelRect) -> String {
        "x:\(Int(bounds.x)) y:\(Int(bounds.y)) w:\(Int(bounds.width)) h:\(Int(bounds.height))"
    }

    @ViewBuilder
    private func cropControlPanel(for asset: StampAsset) -> some View {
        let sourceBounds = sourceBounds(for: asset)
        let maxLeft = max(sourceBounds.width - 1, 0)
        let maxTop = max(sourceBounds.height - 1, 0)
        let maxRight = max(sourceBounds.width - 1, 0)
        let maxBottom = max(sourceBounds.height - 1, 0)

        VStack(alignment: .leading, spacing: 8) {
            Text("鎵嬪姩瑁佽竟鍙傛暟锛堝儚绱狅級")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Stepper(value: $cropInsetLeftPX, in: 0...maxLeft, step: 1) {
                Text("宸﹀唴缂╋細\(Int(cropInsetLeftPX))")
            }
            .disabled(isProcessing)

            Stepper(value: $cropInsetTopPX, in: 0...maxTop, step: 1) {
                Text("涓婂唴缂╋細\(Int(cropInsetTopPX))")
            }
            .disabled(isProcessing)

            Stepper(value: $cropInsetRightPX, in: 0...maxRight, step: 1) {
                Text("鍙冲唴缂╋細\(Int(cropInsetRightPX))")
            }
            .disabled(isProcessing)

            Stepper(value: $cropInsetBottomPX, in: 0...maxBottom, step: 1) {
                Text("涓嬪唴缂╋細\(Int(cropInsetBottomPX))")
            }
            .disabled(isProcessing)

            Button("閲嶇疆瑁佽竟鍙傛暟") {
                resetCropInsets()
            }
            .buttonStyle(.bordered)
            .font(.caption)
            .disabled(isProcessing)

            cropPreviewView(sourceBounds: sourceBounds, cropBounds: manualCropPreview(for: asset))
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func cropPreviewView(sourceBounds: PixelRect, cropBounds: PixelRect) -> some View {
        GeometryReader { geometry in
            let sourceWidth = CGFloat(max(sourceBounds.width, 1))
            let sourceHeight = CGFloat(max(sourceBounds.height, 1))
            let scale = min(
                geometry.size.width / sourceWidth,
                geometry.size.height / sourceHeight
            )
            let safeScale = max(scale, 0.0001)

            let canvasWidth = sourceWidth * scale
            let canvasHeight = sourceHeight * scale
            let canvasX = (geometry.size.width - canvasWidth) / 2
            let canvasY = (geometry.size.height - canvasHeight) / 2

            let cropOffsetX = CGFloat(max(cropBounds.x - sourceBounds.x, 0))
            let cropOffsetY = CGFloat(max(cropBounds.y - sourceBounds.y, 0))
            let cropX = canvasX + cropOffsetX * scale
            let cropY = canvasY + cropOffsetY * scale
            let cropWidth = max(CGFloat(cropBounds.width) * scale, 1)
            let cropHeight = max(CGFloat(cropBounds.height) * scale, 1)
            let handleDiameter = min(max(min(canvasWidth, canvasHeight) * 0.08, 16.0), 28.0)
            let leftHandleX = cropX
            let rightHandleX = cropX + cropWidth
            let topHandleY = cropY
            let bottomHandleY = cropY + cropHeight

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: canvasWidth, height: canvasHeight)
                    .position(x: canvasX + canvasWidth / 2, y: canvasY + canvasHeight / 2)

                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.red, lineWidth: 2)
                    .frame(width: cropWidth, height: cropHeight)
                    .position(x: cropX + cropWidth / 2, y: cropY + cropHeight / 2)

                Circle()
                    .fill(Color.red)
                    .frame(width: handleDiameter, height: handleDiameter)
                    .position(x: leftHandleX, y: cropY + cropHeight / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                applyCropDrag(
                                    edge: .left,
                                    translation: value.translation,
                                    scale: safeScale,
                                    sourceBounds: sourceBounds
                                )
                            }
                            .onEnded { _ in
                                cropDragStartInsets = nil
                            }
                    )

                Circle()
                    .fill(Color.red)
                    .frame(width: handleDiameter, height: handleDiameter)
                    .position(x: rightHandleX, y: cropY + cropHeight / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                applyCropDrag(
                                    edge: .right,
                                    translation: value.translation,
                                    scale: safeScale,
                                    sourceBounds: sourceBounds
                                )
                            }
                            .onEnded { _ in
                                cropDragStartInsets = nil
                            }
                    )

                Circle()
                    .fill(Color.red)
                    .frame(width: handleDiameter, height: handleDiameter)
                    .position(x: cropX + cropWidth / 2, y: topHandleY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                applyCropDrag(
                                    edge: .top,
                                    translation: value.translation,
                                    scale: safeScale,
                                    sourceBounds: sourceBounds
                                )
                            }
                            .onEnded { _ in
                                cropDragStartInsets = nil
                            }
                    )

                Circle()
                    .fill(Color.red)
                    .frame(width: handleDiameter, height: handleDiameter)
                    .position(x: cropX + cropWidth / 2, y: bottomHandleY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                applyCropDrag(
                                    edge: .bottom,
                                    translation: value.translation,
                                    scale: safeScale,
                                    sourceBounds: sourceBounds
                                )
                            }
                            .onEnded { _ in
                                cropDragStartInsets = nil
                            }
                    )
            }
        }
        .frame(height: 140)
    }

    private func sourceBounds(for asset: StampAsset) -> PixelRect {
        asset.effectiveBoundsPX ?? PixelRect(x: 0, y: 0, width: 1024, height: 1024)
    }

    private func manualCropPreview(for asset: StampAsset) -> PixelRect {
        let sourceBounds = sourceBounds(for: asset)

        let left = min(max(cropInsetLeftPX, 0), max(sourceBounds.width - 1, 0))
        let top = min(max(cropInsetTopPX, 0), max(sourceBounds.height - 1, 0))
        let maxRight = max(sourceBounds.width - left - 1, 0)
        let maxBottom = max(sourceBounds.height - top - 1, 0)
        let right = min(max(cropInsetRightPX, 0), maxRight)
        let bottom = min(max(cropInsetBottomPX, 0), maxBottom)

        return PixelRect(
            x: sourceBounds.x + left,
            y: sourceBounds.y + top,
            width: max(sourceBounds.width - left - right, 1),
            height: max(sourceBounds.height - top - bottom, 1)
        )
    }

    private func resetCropInsets() {
        cropInsetLeftPX = 0
        cropInsetTopPX = 0
        cropInsetRightPX = 0
        cropInsetBottomPX = 0
        cropDragStartInsets = nil
    }

    private func applyCropDrag(
        edge: CropDragEdge,
        translation: CGSize,
        scale: CGFloat,
        sourceBounds: PixelRect
    ) {
        let baseline = cropDragStartInsets ?? currentCropInsets()
        if cropDragStartInsets == nil {
            cropDragStartInsets = baseline
        }

        var next = baseline
        let deltaX = Double(translation.width / scale)
        let deltaY = Double(translation.height / scale)

        switch edge {
        case .left:
            next.left = baseline.left + deltaX
        case .top:
            next.top = baseline.top + deltaY
        case .right:
            next.right = baseline.right - deltaX
        case .bottom:
            next.bottom = baseline.bottom - deltaY
        }

        updateCropInsets(clampInsets(next, sourceBounds: sourceBounds))
    }

    private func currentCropInsets() -> CropInsets {
        CropInsets(
            left: cropInsetLeftPX,
            top: cropInsetTopPX,
            right: cropInsetRightPX,
            bottom: cropInsetBottomPX
        )
    }

    private func updateCropInsets(_ insets: CropInsets) {
        cropInsetLeftPX = insets.left
        cropInsetTopPX = insets.top
        cropInsetRightPX = insets.right
        cropInsetBottomPX = insets.bottom
    }

    private func clampInsets(_ insets: CropInsets, sourceBounds: PixelRect) -> CropInsets {
        let sourceWidth = max(sourceBounds.width, 1)
        let sourceHeight = max(sourceBounds.height, 1)

        var left = max(insets.left, 0)
        var right = max(insets.right, 0)
        let maxLeft = max(sourceWidth - right - 1, 0)
        left = min(left, maxLeft)
        let maxRight = max(sourceWidth - left - 1, 0)
        right = min(right, maxRight)

        var top = max(insets.top, 0)
        var bottom = max(insets.bottom, 0)
        let maxTop = max(sourceHeight - bottom - 1, 0)
        top = min(top, maxTop)
        let maxBottom = max(sourceHeight - top - 1, 0)
        bottom = min(bottom, maxBottom)

        return CropInsets(left: left, top: top, right: right, bottom: bottom)
    }

    private func isUserCancelled(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func classifyStampFailure(_ error: Error) -> StampImportFailure {
        if isUserCancelled(error) {
            return .cancelled
        }

        if let appError = error as? AppError {
            switch appError {
            case .unsupportedFileType:
                return .unsupportedType
            case .permissionDenied:
                return .permissionDenied
            case .invalidStampAsset:
                return .invalidAsset
            case .fileImportFailed, .stampNormalizationFailed:
                return .parseFailed
            default:
                break
            }
        }

        if let stagingError = error as? ImportStagingError {
            switch stagingError {
            case .invalidSource, .writeFailed:
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

    private func stampFailureMessage(
        for failure: StampImportFailure,
        source: StampOperationSource
    ) -> String {
        switch failure {
        case .cancelled:
            return "已取消印章导入。"
        case .unsupportedType:
            return "印章格式错误，请选择 PNG/JPG/HEIC 等图片文件。"
        case .permissionDenied:
            switch source {
            case .importFile:
                return "导入失败：没有文件访问权限，请在系统弹窗中允许访问后重试。"
            case .autoNormalize, .manualCrop, .saveAsset:
                return "处理失败：没有文件写入权限，请检查存储权限后重试。"
            }
        case .parseFailed:
            switch source {
            case .importFile:
                return "印章导入失败：图片可能损坏或内容不可读。"
            case .autoNormalize:
                return "自动规范化失败：图片解析异常，请更换素材后重试。"
            case .manualCrop:
                return "手动裁边失败：裁边结果无效或素材解析异常。"
            case .saveAsset:
                return "保存失败：素材写入异常，请重试。"
            }
        case .invalidAsset:
            return "当前印章素材无效，请重新导入后再试。"
        case .unknown:
            switch source {
            case .importFile:
                return "导入印章失败，请重试。"
            case .autoNormalize:
                return "自动规范化失败，请重试。"
            case .manualCrop:
                return "手动裁边失败，请重试。"
            case .saveAsset:
                return "保存失败，请重试。"
            }
        }
    }
}

private struct CropInsets {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double
}

private enum CropDragEdge {
    case left
    case top
    case right
    case bottom
}

private enum StampOperationSource {
    case importFile
    case autoNormalize
    case manualCrop
    case saveAsset
}

private enum StampImportFailure: String {
    case cancelled
    case unsupportedType
    case permissionDenied
    case parseFailed
    case invalidAsset
    case unknown
}
