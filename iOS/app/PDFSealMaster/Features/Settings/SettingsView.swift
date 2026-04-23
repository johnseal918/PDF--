import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let purchaseService: PurchaseService
    let onOpenHelp: () -> Void
    let onClose: () -> Void

    @State private var entitlementState: EntitlementState = .unknown
    @State private var entitlementMessage = "正在同步权益状态..."
    @State private var isProcessingPurchaseAction = false

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

            if isProcessingPurchaseAction {
                ProgressView("处理中...")
                    .font(.caption)
            }

            Spacer()
        }
        .padding(20)
        .task {
            await refreshEntitlementStatus()
        }
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
}
