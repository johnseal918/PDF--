import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from src.ui.assets_panel import AssetsPanel


def test_left_shortcuts_are_visible_and_export_starts_disabled():
    app = QApplication.instance() or QApplication([])
    panel = AssetsPanel()
    opened = []
    exported = []
    panel.open_requested.connect(lambda: opened.append(True))
    panel.export_pdf_requested.connect(lambda: exported.append(True))

    assert panel.btn_open_file.text() == "打开文件"
    assert panel.btn_export_pdf.text() == "导出 PDF"
    assert not panel.btn_export_pdf.isEnabled()
    assert panel.btn_export_pdf.toolTip() == "请先打开文件"

    panel.btn_open_file.click()
    panel.set_export_enabled(True)
    panel.btn_export_pdf.click()
    app.processEvents()
    assert opened == [True]
    assert exported == [True]
