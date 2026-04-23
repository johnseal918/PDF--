import SwiftUI

struct EditorView: View {
    @StateObject private var viewModel: EditorViewModel
    let onBack: () -> Void

    init(
        session: EditorSession,
        draftRecoveryService: DraftRecoveryService,
        stampAssetService: StampAssetService,
        signatureAssetService: SignatureAssetService,
        pdfExportService: PDFExportService,
        issueLogService: IssueLogService,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: EditorViewModel(
                session: session,
                draftRecoveryService: draftRecoveryService,
                stampAssetService: stampAssetService,
                signatureAssetService: signatureAssetService,
                pdfExportService: pdfExportService,
                issueLogService: issueLogService
            )
        )
        self.onBack = onBack
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            canvas
            Divider()
            toolbar
        }
        .background(Color(.systemBackground))
        .task {
            await viewModel.loadEditorAssets()
        }
    }

    private var header: some View {
        HStack {
            Button("返回", action: onBack)

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.document.name)
                    .font(.headline)
                    .lineLimit(1)

                Text("第\(viewModel.activePageDisplay) / \(viewModel.document.pageCount) 页")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("保存草稿") {
                Task {
                    await viewModel.saveDraft()
                }
            }

            Button("导出 PDF") {
                Task {
                    await viewModel.exportPDF()
                }
            }
            .disabled(viewModel.isExportingPDF)

            if let exportURL = viewModel.lastExportURL {
                ShareLink(item: exportURL) {
                    Text("分享")
                }
            }
        }
        .padding()
    }

    private var canvas: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    VStack(spacing: 10) {
                        Text("A4 统一画布")
                            .font(.headline)

                        Text("当前页对象数：\(viewModel.currentPageObjectCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("预览模式：\(viewModel.document.previewMode.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if viewModel.currentPageObjects.isEmpty {
                            Text("当前页还没有印章或签名对象。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(viewModel.currentPageObjects, id: \.id) { object in
                                    objectSummaryButton(object)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding()
                )
                .aspectRatio(595.28 / 841.89, contentMode: .fit)
                .padding()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("当前印章：\(viewModel.selectedStampName)")
                        .font(.footnote.weight(.medium))

                    Spacer()

                    Button("切换印章") {
                        viewModel.cycleSelectedStampAsset()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.availableStampCount <= 1)
                }

                Text("素材池数量：\(viewModel.availableStampCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("当前签名：\(viewModel.selectedSignatureName)")
                        .font(.footnote.weight(.medium))

                    Spacer()

                    Button("切换签名") {
                        viewModel.cycleSelectedSignatureAsset()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.availableSignatureCount <= 1)

                    Button("刷新签名") {
                        Task {
                            await viewModel.refreshSignatureAssetsForEditor()
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }

                Text("签名素材数量：\(viewModel.availableSignatureCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("签名同步：\(viewModel.signatureSyncStatusMessage)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                missingSignatureRepairPanel

                Text("当前选中：\(viewModel.selectedObjectSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("导出状态：\(viewModel.exportStatusMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("导出细节：\(viewModel.exportDetailMessage)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if viewModel.isExportingPDF {
                    ProgressView("正在生成导出文件...")
                        .font(.caption)
                }

                Text("草稿状态：\(viewModel.draftStatusMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("本轮已接入签名链路与统一尺寸能力，下一步继续完善骑缝章。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                stampSizeSyncPanel
            }
            .padding(.horizontal)

            if viewModel.selectedObject != nil {
                objectAdjustmentPanel
                    .padding(.horizontal)
                    .padding(.top, 4)

                if let selectedStamp = viewModel.selectedStampPlacement {
                    parameterPanel(for: selectedStamp)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }

                if let selectedSignature = viewModel.selectedSignaturePlacement {
                    signatureParameterPanel(for: selectedSignature)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack {
            toolbarItem(title: "上一页") {
                viewModel.goToPreviousPage()
            }
            toolbarItem(title: "预览") {
                viewModel.togglePreviewMode()
            }
            toolbarItem(title: "印章") {
                viewModel.insertSelectedStamp()
            }
            toolbarItem(title: "签名") {
                viewModel.insertSelectedSignature()
            }
            toolbarItem(title: "骑缝章") {}
            toolbarItem(title: "下一页") {
                viewModel.goToNextPage()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
    }

    private var missingSignatureRepairPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("缺失签名一键处理")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(viewModel.missingSignatureOverviewText)
                .font(.caption2)
                .foregroundStyle(viewModel.hasMissingSignaturePlacement ? Color.red : Color.secondary)

            Text(viewModel.signatureRepairTargetText)
                .font(.caption2)
                .foregroundStyle(viewModel.selectedSignatureAssetReadyForRepair ? Color.secondary : Color.orange)

            HStack(spacing: 8) {
                Button("定位处理") {
                    Task {
                        await viewModel.focusFirstMissingSignaturePlacement()
                    }
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .disabled(!viewModel.canLocateMissingSignaturePlacement)

                Button("本页替换") {
                    Task {
                        await viewModel.replaceMissingSignaturesOnActivePage()
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canBulkReplaceMissingSignaturesOnActivePage)

                Button("全局替换") {
                    Task {
                        await viewModel.replaceAllMissingSignaturePlacements()
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canBulkReplaceMissingSignatures)
            }

            Text("最近回执：\(viewModel.signatureReplaceReceiptMessage)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var stampSizeSyncPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("统一所有印章尺寸")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(viewModel.stampSizeSyncTargetText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("本页统一") {
                    Task {
                        await viewModel.unifyStampSizesOnActivePage()
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption2)
                .disabled(!viewModel.canUnifyStampSizesOnActivePage)

                Button("全稿统一") {
                    Task {
                        await viewModel.unifyStampSizesGlobally()
                    }
                }
                .buttonStyle(.borderedProminent)
                .font(.caption2)
                .disabled(!viewModel.canUnifyStampSizesGlobally)
            }

            Text("执行结果：\(viewModel.stampSizeSyncStatusMessage)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toolbarItem(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 34, height: 34)
                Text(title)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var objectAdjustmentPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("基础微调")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                adjustmentButton("上移") {
                    viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: -1)
                }
                adjustmentButton("下移") {
                    viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: 1)
                }
                adjustmentButton("左移") {
                    viewModel.moveSelectedObject(deltaXMM: -1, deltaYMM: 0)
                }
                adjustmentButton("右移") {
                    viewModel.moveSelectedObject(deltaXMM: 1, deltaYMM: 0)
                }
            }

            HStack(spacing: 8) {
                adjustmentButton("缩小") {
                    viewModel.resizeSelectedStamp(deltaMM: -1)
                }
                adjustmentButton("放大") {
                    viewModel.resizeSelectedStamp(deltaMM: 1)
                }
                adjustmentButton("删除") {
                    viewModel.deleteSelectedObject()
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func parameterPanel(for stamp: StampPlacement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("参数面板")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            parameterRow(
                title: "X",
                value: "\(String(format: "%.1f", stamp.originXMM)) mm",
                minusAction: { viewModel.moveSelectedObject(deltaXMM: -1, deltaYMM: 0) },
                plusAction: { viewModel.moveSelectedObject(deltaXMM: 1, deltaYMM: 0) }
            )

            parameterRow(
                title: "Y",
                value: "\(String(format: "%.1f", stamp.originYMM)) mm",
                minusAction: { viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: -1) },
                plusAction: { viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: 1) }
            )

            parameterRow(
                title: "宽",
                value: "\(String(format: "%.1f", stamp.widthMM)) mm",
                minusAction: { viewModel.adjustSelectedStampWidth(deltaMM: -1) },
                plusAction: { viewModel.adjustSelectedStampWidth(deltaMM: 1) }
            )

            parameterRow(
                title: stamp.aspectRatioLocked ? "高（锁定）" : "高",
                value: "\(String(format: "%.1f", stamp.heightMM)) mm",
                minusAction: { viewModel.adjustSelectedStampHeight(deltaMM: -1) },
                plusAction: { viewModel.adjustSelectedStampHeight(deltaMM: 1) }
            )

            parameterRow(
                title: "透明度",
                value: "\(String(format: "%.2f", stamp.opacity))",
                minusAction: { viewModel.adjustSelectedStampOpacity(delta: -0.05) },
                plusAction: { viewModel.adjustSelectedStampOpacity(delta: 0.05) }
            )
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func signatureParameterPanel(for signature: SignaturePlacement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("签名参数")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("当前素材：\(viewModel.selectedSignaturePlacementAssetName)")
                .font(.caption2)
                .foregroundStyle(viewModel.selectedSignaturePlacementAssetMissing ? Color.red : Color.secondary)

            Text("替换目标：\(viewModel.selectedSignatureName)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Button("用当前签名替换此对象") {
                Task {
                    await viewModel.replaceSelectedSignatureAsset()
                }
            }
            .buttonStyle(.borderedProminent)
            .font(.caption)
            .disabled(!viewModel.canQuickReplaceSelectedSignature)

            parameterRow(
                title: "X",
                value: "\(String(format: "%.1f", signature.originXMM)) mm",
                minusAction: { viewModel.moveSelectedObject(deltaXMM: -1, deltaYMM: 0) },
                plusAction: { viewModel.moveSelectedObject(deltaXMM: 1, deltaYMM: 0) }
            )

            parameterRow(
                title: "Y",
                value: "\(String(format: "%.1f", signature.originYMM)) mm",
                minusAction: { viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: -1) },
                plusAction: { viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: 1) }
            )

            parameterRow(
                title: "宽",
                value: "\(String(format: "%.1f", signature.widthMM)) mm",
                minusAction: { viewModel.adjustSelectedStampWidth(deltaMM: -1) },
                plusAction: { viewModel.adjustSelectedStampWidth(deltaMM: 1) }
            )

            parameterRow(
                title: "高",
                value: "\(String(format: "%.1f", signature.heightMM)) mm",
                minusAction: { viewModel.adjustSelectedStampHeight(deltaMM: -1) },
                plusAction: { viewModel.adjustSelectedStampHeight(deltaMM: 1) }
            )

            parameterRow(
                title: "透明度",
                value: "\(String(format: "%.2f", signature.opacity))",
                minusAction: { viewModel.adjustSelectedStampOpacity(delta: -0.05) },
                plusAction: { viewModel.adjustSelectedStampOpacity(delta: 0.05) }
            )
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func adjustmentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .font(.caption)
            .frame(maxWidth: .infinity)
    }

    private func parameterRow(
        title: String,
        value: String,
        minusAction: @escaping () -> Void,
        plusAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .frame(width: 50, alignment: .leading)

            Spacer()

            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("-", action: minusAction)
                .buttonStyle(.bordered)
                .font(.caption)

            Button("+", action: plusAction)
                .buttonStyle(.bordered)
                .font(.caption)
        }
    }

    @ViewBuilder
    private func objectSummaryButton(_ object: EditorObject) -> some View {
        Button {
            viewModel.selectObject(object.id)
        } label: {
            HStack {
                objectSummaryText(object)
                    .multilineTextAlignment(.leading)
                Spacer()
                if object.isSelected {
                    Text("已选中")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                object.isSelected
                    ? Color.accentColor.opacity(0.12)
                    : Color(.tertiarySystemBackground),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func objectSummaryText(_ object: EditorObject) -> some View {
        if let stamp = object.stampPlacement {
            Text(
                "印章 · 第\(stamp.pageIndex + 1)页 · 位置 \(String(format: "%.1f", stamp.originXMM)), \(String(format: "%.1f", stamp.originYMM)) mm · 尺寸 \(String(format: "%.1f", stamp.widthMM)) × \(String(format: "%.1f", stamp.heightMM)) mm"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let signature = object.signaturePlacement {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    "签名 · 第\(signature.pageIndex + 1)页 · 位置 \(String(format: "%.1f", signature.originXMM)), \(String(format: "%.1f", signature.originYMM)) mm · 尺寸 \(String(format: "%.1f", signature.widthMM)) x \(String(format: "%.1f", signature.heightMM)) mm"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(
                    viewModel.isSignatureAssetMissing(assetID: signature.assetID)
                        ? "素材状态：缺失"
                        : "素材状态：\(viewModel.signatureAssetDisplayName(for: signature.assetID))"
                )
                .font(.caption2)
                .foregroundStyle(viewModel.isSignatureAssetMissing(assetID: signature.assetID) ? Color.red : Color.secondary)
            }
        }
    }
}
