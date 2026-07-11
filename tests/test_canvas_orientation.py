import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from src.ui.canvas_view import CanvasWidget


def test_orientation_button_reflects_page_and_requests_opposite_direction():
    app = QApplication.instance() or QApplication([])
    widget = CanvasWidget()
    requested = []
    widget.orientation_requested.connect(requested.append)

    widget.set_page_landscape(True)
    assert widget._btn_orientation.text() == "▭ 横向"

    widget._btn_orientation.click()
    app.processEvents()
    assert requested == [False]

    widget.set_page_landscape(False)
    assert widget._btn_orientation.text() == "▯ 纵向"
