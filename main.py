"""
PDF Seal Master 鈥?鍗扮珷澶勭悊澶у笀
================================
搴旂敤鍏ュ彛銆傚垵濮嬪寲 PySide6 搴旂敤銆佸姞杞界粺涓€鐨勬繁鐏板伐涓氶 QSS 涓婚锛屽惎鍔ㄤ富绐楀彛銆?"""

import os
import subprocess
import sys
import traceback
from pathlib import Path

# Ensure the project root is available on sys.path.
PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QFont


# 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€ 缁熶竴鐨勬繁鐏板伐涓氶 QSS 涓婚 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

DARK_INDUSTRIAL_QSS = """
/* ===== 鍏ㄥ眬鍩虹 ===== */
QWidget {
    background-color: #2b2b2b;
    color: #d4d4d4;
    font-size: 13px;
}

/* ===== 涓荤獥鍙?===== */
QMainWindow {
    background-color: #1e1e1e;
}

/* ===== 鑿滃崟鏍?===== */
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

/* ===== 鐘舵€佹爮 ===== */
QStatusBar {
    background-color: #007acc;
    color: white;
    font-size: 12px;
    padding: 2px 8px;
}

/* ===== 鍒嗗壊鍣?===== */
QSplitter::handle {
    background-color: #3c3c3c;
    width: 2px;
}
QSplitter::handle:hover {
    background-color: #0078d4;
}

/* ===== 鎸夐挳 ===== */
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

/* Zoom controls: override global button padding to prevent text clipping. */
#zoomOutBtn, #zoomInBtn {
    padding: 0px;
    min-width: 30px;
    max-width: 30px;
    font-size: 16px;
    font-weight: 700;
}
#zoomResetBtn {
    padding: 0px 6px;
    min-width: 75px;
    max-width: 90px;
    font-weight: 600;
}

/* ===== 鍒嗙粍妗?===== */
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

/* ===== 鏍囩椤?===== */
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

/* ===== 鍒楄〃鎺т欢 ===== */
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

/* ===== 婊氬姩鏉?===== */
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

/* ===== 婊戝姩鏉?(鍚庣画 M3 浣跨敤) ===== */
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

/* ===== 鍥惧舰瑙嗗浘锛堢敾甯冭儗鏅級===== */
QGraphicsView {
    background-color: #1a1a1a;
    border: none;
}

/* ===== 鏍囩 ===== */
QLabel {
    color: #d4d4d4;
}

/* ===== 琛ㄥ崟甯冨眬鏍囩 ===== */
QFormLayout QLabel {
    color: #aaa;
}

/* ===== 宸ュ叿鎻愮ず ===== */
QToolTip {
    background-color: #3c3c3c;
    color: #d4d4d4;
    border: 1px solid #555;
    padding: 4px;
    border-radius: 3px;
}
"""


def _maybe_relaunch_without_console() -> bool:
    """On Windows, re-launch with pythonw.exe so the console window does not stay visible."""
    if os.name != "nt":
        return False
    if getattr(sys, "frozen", False):
        return False
    if os.environ.get("PDF_SEAL_NO_RELAUNCH") == "1":
        return False

    exe = Path(sys.executable)
    if exe.name.lower() != "python.exe":
        return False

    pythonw = exe.with_name("pythonw.exe")
    if not pythonw.exists():
        return False

    try:
        import ctypes
        if not ctypes.windll.kernel32.GetConsoleWindow():
            return False
    except Exception:
        pass

    env = os.environ.copy()
    env["PDF_SEAL_NO_RELAUNCH"] = "1"
    subprocess.Popen(
        [str(pythonw), str(Path(__file__).resolve())],
        cwd=str(PROJECT_ROOT),
        env=env,
    )
    return True


def _show_startup_error(exc: Exception) -> None:
    """Surface startup failures even when the app is launched via pythonw.exe."""
    error_text = "".join(traceback.format_exception(exc))

    try:
        import ctypes

        ctypes.windll.user32.MessageBoxW(
            None,
            error_text,
            "PDF Seal Master Startup Error",
            0x10,
        )
        return
    except Exception:
        pass

    print(error_text, file=sys.stderr)


def main():
    if _maybe_relaunch_without_console():
        return

    from src.ui.main_window import MainWindow

    app = QApplication(sys.argv)

    # 璁剧疆鍏ㄥ眬瀛椾綋
    font = QFont("Microsoft YaHei UI", 10)
    font.setStyleStrategy(QFont.StyleStrategy.PreferAntialias)
    app.setFont(font)

    # Apply the shared application stylesheet.
    app.setStyleSheet(DARK_INDUSTRIAL_QSS)

    # 鍒涘缓骞舵樉绀轰富绐楀彛
    window = MainWindow()
    window.show()

    sys.exit(app.exec())


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        _show_startup_error(exc)
        raise
