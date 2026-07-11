import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from src.ui.assets_panel import AssetsPanel
from src.ui.main_window import MainWindow


def _app():
    return QApplication.instance() or QApplication([])


def test_document_tabs_live_below_shortcuts_and_above_assets_title():
    _app()
    panel = AssetsPanel()

    assert panel.layout().itemAt(1).widget() is panel._document_tabs
    assert panel.layout().itemAt(2).widget().text() == "📦 素材库"


def test_document_tabs_emit_selection_and_close_requests():
    _app()
    panel = AssetsPanel()
    selected = []
    closed = []
    panel.document_selected.connect(selected.append)
    panel.document_close_requested.connect(closed.append)

    panel.add_document_tab("a.pdf", "C:/a.pdf")
    panel.add_document_tab("b.pdf", "C:/b.pdf")
    panel.set_current_document(1)
    panel.request_document_close(0)

    assert selected[-1] == 1
    assert closed == [0]


def test_main_window_hides_top_document_tabs():
    _app()
    window = MainWindow()

    assert window._doc_tabs.tabBar().isHidden()
