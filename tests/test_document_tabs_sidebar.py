import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication, QPushButton, QTabWidget

from src.ui.assets_panel import AssetsPanel
from src.ui.main_window import MainWindow


def _app():
    return QApplication.instance() or QApplication([])


def test_document_tabs_live_below_shortcuts_and_above_assets_tabs():
    _app()
    panel = AssetsPanel()
    panel.add_document_tab("a.pdf", "C:/a.pdf")

    assert panel.layout().itemAt(1).widget() is panel._library_splitter
    assert panel._library_splitter.widget(0) is panel._document_tabs
    assert isinstance(panel._library_splitter.widget(1).layout().itemAt(0).widget(), QTabWidget)
    assert 28 <= panel._document_tabs.sizeHintForRow(0) <= 36


def test_document_tab_close_button_is_hidden_until_hover():
    _app()
    panel = AssetsPanel()
    panel.add_document_tab("a.pdf", "C:/a.pdf")

    row = panel._document_tabs.itemWidget(panel._document_tabs.item(0))
    close_btn = row.findChild(QPushButton)

    assert close_btn.text() == "x"
    assert close_btn.isHidden()


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


def test_main_window_applies_light_and_dark_app_theme():
    app = _app()
    app.setProperty("dark_qss", "QWidget { color: red; }")
    window = MainWindow()

    window._apply_app_theme("dark")
    assert app.styleSheet() == "QWidget { color: red; }"

    window._apply_app_theme("light")
    assert app.styleSheet() == ""
