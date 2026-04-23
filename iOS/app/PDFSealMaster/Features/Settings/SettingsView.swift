import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let purchaseService: PurchaseService
    let onOpenHelp: () -> Void
    let onClose: () -> Void

    private let releaseReadinessService = ReleaseReadinessService()

    @State private var entitlementState: EntitlementState = .unknown
    @State private var entitlementMessage = "正在同步权益状态..."
    @State private var isProcessingPurchaseAction = false
    @State private var releaseReadinessChecks: [ReleaseReadinessCheck] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("返回", action: onClose)
                Spacer()
                Text("设置")
                    .font(.headline)
                Spacer()
            }

            GroupBox("基础偏好") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("首页显示最近文件优先", isOn: $settings.prefersRecentFilesOnHome)
                    Toggle("自动保存草稿", isOn: $settings.autoSaveDrafts)

                    Picker("默认预览模式", selection: $settings.defaultPreviewMode) {
                        Text("原始预览").tag(PreviewMode.original)
                        Text("匹配低分辨率").tag(PreviewMode.matchedLowRes)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 4)
            }

            GroupBox("购买与权益") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当前权益：\(entitlementState.displayName)")
                        .font(.subheadline.weight(.medium))
                    Text(entitlementMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("刷新权益") {
                            Task {
                                await refreshEntitlementStatus()
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isProcessingPurchaseAction)

                        Button("恢复购买") {
                            Task {
                                await restorePurchases()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isProcessingPurchaseAction)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("帮助与支持") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("查看常见问题、隐私说明与提审信息。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("进入帮助页", action: onOpenHelp)
                        .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }

            GroupBox("提审准备（M5）") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("进度：\(releaseReadinessCompletedCount)/\(releaseReadinessTotalCount)")
                        .font(.subheadline.weight(.medium))

                    if releaseReadinessChecks.isEmpty {
                        Text("尚未加载提审检查结果。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(releaseReadinessChecks) { check in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: check.status == .pass ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(check.status == .pass ? .green : .orange)
                                    Text(check.title)
                                        .font(.caption.weight(.semibold))
                                }
                                Text(check.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if check.status != .pass {
                                    Text("建议：\(check.recommendation)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }

                    Divider()

                    Text("上架素材清单（手动）")
                        .font(.caption.weight(.semibold))
                    Toggle("1024x1024 App Icon 已完成", isOn: $settings.hasPreparedAppIcon1024)
                    Toggle("iPhone 6.1 英寸截图已完成", isOn: $settings.hasPreparedIPhone61Screenshots)
                    Toggle("iPhone 6.7 英寸截图已完成", isOn: $settings.hasPreparedIPhone67Screenshots)
                    Toggle("隐私政策 URL 已准备", isOn: $settings.hasPreparedPrivacyPolicyURL)

                    HStack(spacing: 10) {
                        Button("刷新提审检查") {
                            refreshReleaseReadinessChecks()
                        }
                        .buttonStyle(.bordered)

                        Text("建议在 TestFlight 前完成全部检查项。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            if isProcessingPurchaseAction {
                ProgressView("处理中...")
                    .font(.caption)
            }

            Spacer()
        }
        .padding(20)
        .task {
            await refreshEntitlementStatus()
            refreshReleaseReadinessChecks()
        }
    }

    private var autoReadinessPassCount: Int {
        releaseReadinessChecks.filter { $0.status == .pass }.count
    }

    private var manualReadinessPassCount: Int {
        [
            settings.hasPreparedAppIcon1024,
            settings.hasPreparedIPhone61Screenshots,
            settings.hasPreparedIPhone67Screenshots,
            settings.hasPreparedPrivacyPolicyURL
        ]
        .filter { $0 }
        .count
    }

    private var releaseReadinessCompletedCount: Int {
        autoReadinessPassCount + manualReadinessPassCount
    }

    private var releaseReadinessTotalCount: Int {
        releaseReadinessChecks.count + 4
    }

    private func refreshEntitlementStatus() async {
        let state = await purchaseService.currentEntitlements()
        entitlementState = state
        entitlementMessage = state == .pro
            ? "专业版已激活。"
            : "当前为免费版，导出/骑缝章/统一尺寸/扩展素材库需专业版。"
    }

    private func restorePurchases() async {
        isProcessingPurchaseAction = true
        defer { isProcessingPurchaseAction = false }

        do {
            try await purchaseService.restorePurchases()
            await refreshEntitlementStatus()
            if entitlementState == .pro {
                entitlementMessage = "恢复成功，专业版已激活。"
            } else {
                entitlementMessage = "未检测到可恢复的购买记录。"
            }
        } catch {
            entitlementMessage = "恢复购买失败，请稍后重试。"
        }
    }

    private func refreshReleaseReadinessChecks() {
        releaseReadinessChecks = releaseReadinessService.evaluateAutoChecks()
    }
}
