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


def test_cross_document_sync_changes_only_same_stamp_asset():
    app = QApplication.instance() or QApplication([])
    widget = CanvasWidget()
    view = widget.canvas_view
    view._page_sizes[0] = (2480, 3508)

    class Item:
        def __init__(self, asset_id, category="stamps"):
            self.asset_id = asset_id
            self.category = category
            self.w = 100
            self.scale_value = 1.0

        def setScale(self, value):
            self.scale_value = value

    same = Item("seal-a")
    other = Item("seal-b")
    signature = Item("seal-a", "signatures")
    view._page_stamps = {0: [same, other, signature]}

    assert view.unify_asset_size("seal-a", 500) == 1
    assert same.scale_value == 5.0
    assert other.scale_value == 1.0
    assert signature.scale_value == 1.0
