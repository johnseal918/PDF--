import SwiftUI

struct HelpView: View {
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("返回", action: onClose)
                    Spacer()
                    Text("帮助")
                        .font(.headline)
                    Spacer()
                }

                GroupBox("常见问题") {
                    VStack(alignment: .leading, spacing: 8) {
                        faqItem(
                            question: "为什么导出会提示需要专业版？",
                            answer: "正式导出、骑缝章和统一尺寸属于专业版能力。免费版可先试用编辑与预览。"
                        )
                        faqItem(
                            question: "预览模式会影响导出结果吗？",
                            answer: "不会。预览模式只影响屏幕判断，导出始终按真实坐标与真实尺寸计算。"
                        )
                        faqItem(
                            question: "怎么恢复购买？",
                            answer: "在设置页中点击“恢复购买”，系统会同步当前 Apple ID 的有效权益。"
                        )
                        faqItem(
                            question: "什么时候可以提审 TestFlight？",
                            answer: "建议先在“设置 > 提审准备（M5）”里完成自动检查与上架素材清单，再进入提审。"
                        )
                    }
                    .padding(.top, 4)
                }

                GroupBox("隐私与本地处理") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. 文档处理默认在本地完成。")
                        Text("2. 非必要不上传文档内容。")
                        Text("3. 运行日志只记录问题定位所需的最小信息。")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }

                GroupBox("版本信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("产品：PDF Seal Master（iPhone）")
                        Text("阶段：M5.4（提审准备）")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
            .padding(20)
        }
    }

    private func faqItem(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.subheadline.weight(.semibold))
            Text(answer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
