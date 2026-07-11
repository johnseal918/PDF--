import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtGui import QPixmap
from PySide6.QtWidgets import QApplication

from src.ui.canvas_view import CanvasView
from src.ui.stamp_item import StampItem


def test_export_data_includes_copied_stamp_and_undo_removes_it():
    QApplication.instance() or QApplication([])
    view = CanvasView()
    view._page_sizes = {0: (1000, 1500), 1: (1000, 1500)}
    source = StampItem(QPixmap(100, 50), "seal-1")
    source.category = "stamps"
    source.page_index = 0
    view._page_stamps = {0: [source], 1: []}

    view.copy_stamp_to_missing_pages(source, [1], {"angle_enabled": False, "position_enabled": False})

    data = view.get_all_stamps_data()
    assert 1 in data
    assert data[1][0]["asset_id"] == "seal-1"

    view.undo_stack.undo()
    assert 1 not in view.get_all_stamps_data()
    assert view._page_stamps[1] == []
