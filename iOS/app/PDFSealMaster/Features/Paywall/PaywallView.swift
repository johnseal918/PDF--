import SwiftUI

struct PaywallView: View {
    let trigger: PaywallTrigger
    let entitlementState: EntitlementState
    let statusMessage: String
    let isProcessing: Bool
    let onPurchase: () -> Void
    let onRestore: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("解锁专业版")
                    .font(.title2.weight(.semibold))

                Text("触发能力：\(trigger.displayTitle)")
                    .font(.body.weight(.medium))

                Text(trigger.paywallDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("当前权益：\(entitlementState.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button("购买专业版") {
                    onPurchase()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isProcessing)

                Button("恢复购买") {
                    onRestore()
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)

                Button("暂不升级") {
                    onClose()
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                if isProcessing {
                    ProgressView("正在处理...")
                        .font(.caption)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("专业版")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        onClose()
                    }
                    .disabled(isProcessing)
                }
            }
        }
    }
}
