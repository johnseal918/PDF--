# PDF Seal Master

PDF Seal Master 是一个本地运行的 PDF / 图片盖章与签名处理工具。项目包含桌面端原型和 iOS 端工程骨架，重点面向常见办公场景中的文档导入、印章/签名素材管理、可视化排版和导出处理。

> 请只在你有权处理的文档和素材上使用本项目。印章、签名和合同类文件通常具有法律和隐私风险，使用前请确认授权和合规边界。

## 功能概览

- 导入 PDF、PNG、JPG、BMP、TIFF 等常见文件格式。
- 在画布中预览页面并拖拽放置印章或签名素材。
- 支持印章/签名素材的本地分类管理。
- 支持缩放、旋转、移动等基础编辑操作。
- 支持撤销/重做和多页文档浏览。
- 支持骑缝章相关排版与导出渲染。
- 支持去色、二值化、纸面噪声、印迹磨损等扫描风格处理。
- 支持导出 PDF 或图片结果。

## 技术栈

桌面端：

- Python 3
- PySide6
- PyMuPDF
- Pillow
- OpenCV
- NumPy

iOS 端：

- Swift
- SwiftUI
- XcodeGen 工程配置
- StoreKit 2 基础接入

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/johnseal918/PDF--.git
cd PDF--
```

### 2. 创建虚拟环境

```bash
python -m venv .venv
```

Windows PowerShell:

```powershell
.\.venv\Scripts\Activate.ps1
```

macOS / Linux:

```bash
source .venv/bin/activate
```

### 3. 安装依赖

```bash
pip install -r requirements.txt
```

### 4. 启动桌面端

```bash
python main.py
```

## 目录结构

```text
.
├── main.py                 # 桌面端入口
├── requirements.txt        # Python 依赖
├── src/
│   ├── core/               # PDF、图像、渲染、素材、模板等核心逻辑
│   ├── ui/                 # PySide6 界面组件
│   └── utils/              # 图像格式转换和配置读写工具
├── iOS/
│   ├── app/                # iOS 工程代码与 XcodeGen 配置
│   └── resources/          # iOS 资源占位目录
└── codemagic.yaml          # 云端构建配置
```

## 桌面端模块说明

- `src/core/pdf_engine.py`：PDF / 图片加载、页面渲染、A4 归一化和导出封装。
- `src/core/render_engine.py`：印章合成、骑缝章切分、扫描风格渲染和图像混合。
- `src/core/cv_processor.py`：去色、二值化和纸面噪声处理。
- `src/core/assets_manager.py`：印章与签名素材的本地管理。
- `src/ui/main_window.py`：主窗口、菜单、拖拽导入和导出流程。
- `src/ui/canvas_view.py`：文档预览画布和盖章交互。
- `src/ui/stamp_item.py`：可移动、缩放、旋转的印章图元。

## iOS 工程状态

`iOS/app/` 中包含 PDFSealMaster 的 SwiftUI 工程骨架，已覆盖应用入口、路由、核心模型、文档服务、印章服务、编辑页、首页、设置页、付费页和部分单元测试。

iOS 端仍处于持续开发阶段，部分原生能力需要在 macOS / Xcode 环境中继续验证和完善。

## 仓库说明

为了避免上传私人素材和内部记录，仓库不会包含：

- 个人印章或签名图片。
- 本地素材配置和模板配置。
- 开发过程日志、内部计划和治理文档。
- 本地构建产物、虚拟环境和签名材料。

如果你需要测试印章或签名功能，请自行准备具备使用授权的 PNG 素材。

## 许可证

当前仓库尚未附带开源许可证。未经作者明确授权，请不要将本项目用于再分发或商业用途。
