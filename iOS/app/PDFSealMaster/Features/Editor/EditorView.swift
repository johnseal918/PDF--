import SwiftUI

struct EditorView: View {
    @StateObject private var viewModel: EditorViewModel
    let onBack: () -> Void

    init(
        session: EditorSession,
        draftRecoveryService: DraftRecoveryService,
        stampAssetService: StampAssetService,
        pdfExportService: PDFExportService,
        issueLogService: IssueLogService,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: EditorViewModel(
                session: session,
                draftRecoveryService: draftRecoveryService,
                stampAssetService: stampAssetService,
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
            await viewModel.loadStampAssets()
        }
    }

    private var header: some View {
        HStack {
            Button("杩斿洖", action: onBack)

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

            Button("淇濆瓨鑽夌") {
                Task {
                    await viewModel.saveDraft()
                }
            }

            Button("瀵煎嚭 PDF") {
                Task {
                    await viewModel.exportPDF()
                }
            }
            .disabled(viewModel.isExportingPDF)

            if let exportURL = viewModel.lastExportURL {
                ShareLink(item: exportURL) {
                    Text("鍒嗕韩")
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
                        Text("A4 缁熶竴鐢诲竷")
                            .font(.headline)

                        Text("褰撳墠椤靛璞℃暟锛\(viewModel.currentPageObjectCount)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("棰勮妯″紡锛\(viewModel.document.previewMode.displayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if viewModel.currentPageObjects.isEmpty {
                            Text("当前页还没有印章对象。")
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
                    Text("褰撳墠鍗扮珷锛\(viewModel.selectedStampName)")
                        .font(.footnote.weight(.medium))

                    Spacer()

                    Button("鍒囨崲鍗扮珷") {
                        viewModel.cycleSelectedStampAsset()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .disabled(viewModel.availableStampCount <= 1)
                }

                Text("绱犳潗姹犳暟閲忥細\(viewModel.availableStampCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("褰撳墠閫変腑锛\(viewModel.selectedObjectSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("瀵煎嚭鐘舵€侊細\(viewModel.exportStatusMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("瀵煎嚭缁嗚妭锛\(viewModel.exportDetailMessage)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if viewModel.isExportingPDF {
                    ProgressView("姝ｅ湪鐢熸垚瀵煎嚭鏂囦欢...")
                        .font(.caption)
                }

                Text("鑽夌鐘舵€侊細\(viewModel.draftStatusMessage)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("这一版先把普通盖章对象链路接通，后续继续接 PDFKit 预览、拖拽缩放和底部抽屉参数面板。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack {
            toolbarItem(title: "上一页") {
                viewModel.goToPreviousPage()
            }
            toolbarItem(title: "棰勮") {
                viewModel.togglePreviewMode()
            }
            toolbarItem(title: "鍗扮珷") {
                viewModel.insertSelectedStamp()
            }
            toolbarItem(title: "绛惧悕") {}
            toolbarItem(title: "骑缝章") {}
            toolbarItem(title: "下一页") {
                viewModel.goToNextPage()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
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
            Text("鍩虹寰皟")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                adjustmentButton("涓婄Щ") {
                    viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: -1)
                }
                adjustmentButton("涓嬬Щ") {
                    viewModel.moveSelectedObject(deltaXMM: 0, deltaYMM: 1)
                }
                adjustmentButton("宸︾Щ") {
                    viewModel.moveSelectedObject(deltaXMM: -1, deltaYMM: 0)
                }
                adjustmentButton("鍙崇Щ") {
                    viewModel.moveSelectedObject(deltaXMM: 1, deltaYMM: 0)
                }
            }

            HStack(spacing: 8) {
                adjustmentButton("缂╁皬") {
                    viewModel.resizeSelectedStamp(deltaMM: -1)
                }
                adjustmentButton("鏀惧ぇ") {
                    viewModel.resizeSelectedStamp(deltaMM: 1)
                }
                adjustmentButton("鍒犻櫎") {
                    viewModel.deleteSelectedObject()
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func parameterPanel(for stamp: StampPlacement) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("鍙傛暟闈㈡澘")
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
                    Text("宸查€変腑")
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
                "鍗扮珷 路 绗琝(stamp.pageIndex + 1)椤?路 浣嶇疆 \(String(format: "%.1f", stamp.originXMM)), \(String(format: "%.1f", stamp.originYMM)) mm 路 灏哄 \(String(format: "%.1f", stamp.widthMM)) 脳 \(String(format: "%.1f", stamp.heightMM)) mm"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let signature = object.signaturePlacement {
            Text(
                "绛惧悕 路 绗琝(signature.pageIndex + 1)椤?路 浣嶇疆 \(String(format: "%.1f", signature.originXMM)), \(String(format: "%.1f", signature.originYMM)) mm 路 灏哄 \(String(format: "%.1f", signature.widthMM)) 脳 \(String(format: "%.1f", signature.heightMM)) mm"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}
