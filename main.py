"""
PDF Seal Master — 印章处理大师
================================
应用入口。初始化 PySide6 应用、加载统一的深灰工业风 QSS 主题，启动主窗口。
"""

import sys
from pathlib import Path

# 确保项目根目录在 sys.path 中
PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QFont
from src.ui.main_window import MainWindow


# ───────────────────────── 统一的深灰工业风 QSS 主题 ─────────────────────────

DARK_INDUSTRIAL_QSS = """
/* ===== 全局基础 ===== */
QWidget {
    background-color: #2b2b2b;
    color: #d4d4d4;
    font-size: 13px;
}

/* ===== 主窗口 ===== */
QMainWindow {
    background-color: #1e1e1e;
}

/* ===== 菜单栏 ===== */
QMenuBar {
    background-color: #333333;
    color: #d4d4d4;
    border-bottom: 1px solid #444;
    padding: 2px;
}
QMenuBar::item {
    padding: 5px 12px;
    background: transparent;
}
QMenuBar::item:selected {
    background-color: #0078d4;
    border-radius: 3px;
}
QMenu {
    background-color: #2d2d2d;
    border: 1px solid #444;
    padding: 4px;
}
QMenu::item {
    padding: 6px 28px;
}
QMenu::item:selected {
    background-color: #0078d4;
    border-radius: 3px;
}
QMenu::separator {
    height: 1px;
    background: #444;
    margin: 4px 8px;
}

/* ===== 状态栏 ===== */
QStatusBar {
    background-color: #007acc;
    color: white;
    font-size: 12px;
    padding: 2px 8px;
}

/* ===== 分割器 ===== */
QSplitter::handle {
    background-color: #3c3c3c;
    width: 2px;
}
QSplitter::handle:hover {
    background-color: #0078d4;
}

/* ===== 按钮 ===== */
QPushButton {
    background-color: #3c3c3c;
    color: #d4d4d4;
    border: 1px solid #555;
    border-radius: 4px;
    padding: 5px 14px;
    min-height: 22px;
}
QPushButton:hover {
    background-color: #4a4a4a;
    border-color: #0078d4;
}
QPushButton:pressed {
    background-color: #0078d4;
    color: white;
}
QPushButton:disabled {
    background-color: #2b2b2b;
    color: #666;
    border-color: #444;
}

/* ===== 分组框 ===== */
QGroupBox {
    border: 1px solid #555;
    border-radius: 5px;
    margin-top: 12px;
    padding-top: 16px;
    font-weight: bold;
}
QGroupBox::title {
    subcontrol-origin: margin;
    subcontrol-position: top left;
    padding: 0 8px;
    color: #80c8ff;
}

/* ===== 标签页 ===== */
QTabWidget::pane {
    border: 1px solid #444;
    border-radius: 3px;
    background-color: #2b2b2b;
}
QTabBar::tab {
    background-color: #333;
    color: #aaa;
    border: 1px solid #444;
    border-bottom: none;
    padding: 6px 16px;
    margin-right: 2px;
    border-top-left-radius: 4px;
    border-top-right-radius: 4px;
}
QTabBar::tab:selected {
    background-color: #2b2b2b;
    color: #fff;
    border-bottom: 2px solid #0078d4;
}
QTabBar::tab:hover:!selected {
    background-color: #3a3a3a;
}

/* ===== 列表控件 ===== */
QListWidget {
    background-color: #252525;
    border: 1px solid #444;
    border-radius: 3px;
    padding: 4px;
}
QListWidget::item {
    padding: 4px;
    border-radius: 3px;
}
QListWidget::item:selected {
    background-color: #0078d4;
    color: white;
}
QListWidget::item:hover:!selected {
    background-color: #333;
}

/* ===== 滚动条 ===== */
QScrollBar:vertical {
    background-color: #2b2b2b;
    width: 10px;
    margin: 0;
}
QScrollBar::handle:vertical {
    background-color: #555;
    min-height: 30px;
    border-radius: 5px;
}
QScrollBar::handle:vertical:hover {
    background-color: #777;
}
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0;
}
QScrollBar:horizontal {
    background-color: #2b2b2b;
    height: 10px;
    margin: 0;
}
QScrollBar::handle:horizontal {
    background-color: #555;
    min-width: 30px;
    border-radius: 5px;
}
QScrollBar::handle:horizontal:hover {
    background-color: #777;
}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
    width: 0;
}

/* ===== SpinBox ===== */
QSpinBox {
    background-color: #333;
    border: 1px solid #555;
    border-radius: 3px;
    padding: 2px 4px;
    color: #d4d4d4;
}
QSpinBox::up-button, QSpinBox::down-button {
    background-color: #3c3c3c;
    border: none;
    width: 16px;
}
QSpinBox::up-button:hover, QSpinBox::down-button:hover {
    background-color: #555;
}

/* ===== 滑动条 (后续 M3 使用) ===== */
QSlider::groove:horizontal {
    border: none;
    background-color: #444;
    height: 4px;
    border-radius: 2px;
}
QSlider::handle:horizontal {
    background-color: #0078d4;
    width: 14px;
    height: 14px;
    margin: -5px 0;
    border-radius: 7px;
}
QSlider::handle:horizontal:hover {
    background-color: #1e90ff;
}

/* ===== 图形视图（画布背景）===== */
QGraphicsView {
    background-color: #1a1a1a;
    border: none;
}

/* ===== 标签 ===== */
QLabel {
    color: #d4d4d4;
}

/* ===== 表单布局标签 ===== */
QFormLayout QLabel {
    color: #aaa;
}

/* ===== 工具提示 ===== */
QToolTip {
    background-color: #3c3c3c;
    color: #d4d4d4;
    border: 1px solid #555;
    padding: 4px;
    border-radius: 3px;
}
"""


def main():
    """应用程序入口。"""
    app = QApplication(sys.argv)

    # 设置全局字体
    font = QFont("Microsoft YaHei UI", 10)
    font.setStyleStrategy(QFont.StyleStrategy.PreferAntialias)
    app.setFont(font)

    # 应用工业风主题
    app.setStyleSheet(DARK_INDUSTRIAL_QSS)

    # 创建并显示主窗口
    window = MainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
