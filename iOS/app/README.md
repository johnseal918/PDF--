# iOS 工程区

这里已经从“目录预留”进入到第一阶段执行状态，当前重点是把 `iPhone` 首版的正确主链路先搭起来：

- `PDFSealMaster/`
  iOS 工程源码骨架
- `PDFSealMaster/App/`
  App 入口、路由、全局设置
- `PDFSealMaster/Features/`
  首页、主编辑页、印章导入等页面骨架
- `PDFSealMaster/Domain/`
  文档、印章、签名、编辑对象的核心模型与服务协议
- `PDFSealMaster/Infrastructure/`
  仓储与本地化落盘的占位实现
- `PDFSealMaster/Shared/`
  通用扩展与共享工具

当前这一轮已经落地的是：

- `M1` 所需的 App 壳层
- 文档模型与 `A4` 归一化模型
- 印章规范化模型
- 草稿恢复服务协议
- 首页与主编辑页的 SwiftUI 骨架
- 首页真实导入链路（PDF / 文件图片 / 相册图片）
- 印章导入主链路（导入 -> 自动规范化 -> 手动微调 -> 尺寸设置 -> 保存）
- 手动裁边参数面板与裁边预览框（M1 可用版）
- 导出后系统分享入口（`ShareLink`）
- 导出优先渲染真实文档内容（PDF页/图片页）与印章素材

当前仍在持续补齐：

- `PencilKit` 真机手写链路细节
- 提审签名与发布前完整回归链路
- 首发包后的增强能力（灰度 / 扫描风、最近文件增强）

当前已接入：

- `xcodeproj` 由 `XcodeGen` 自动生成
- `StoreKit 2` 专业版购买与恢复购买基础服务接线
- 骑缝章、签名复用、付费拦截、预览模式主链路
- 提审准备面板（自动配置检查 + 上架素材手动清单进度）

原因是当前环境是 Windows，本轮先把工程结构和业务骨架落地，等切到 macOS / Xcode 环境后继续接入原生能力。

## Runtime Logging

The iOS scaffold now includes a small runtime issue logger that records import, draft, stamp, and export feedback/errors under `Application Support/PDFSealMaster/Logs/Runtime/`.

## Export Feedback

The editor now exposes a three-layer export state: in-progress, success with share-ready file, and failure with a specific reason.

