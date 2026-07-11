import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF
from PySide6.QtGui import QPixmap
from PySide6.QtWidgets import QApplication

from src.ui.canvas_view import CanvasView
from src.ui.stamp_item import StampItem


def _app():
    return QApplication.instance() or QApplication([])


def _stamp(asset_id="seal-1", page=0):
    item = StampItem(QPixmap(100, 50), asset_id)
    item.category = "stamps"
    item.page_index = page
    item.setPos(QPointF(200, 300))
    item.setScale(0.5)
    item.setRotation(7)
    return item


def test_copy_stamp_to_current_document_skips_pages_that_already_have_same_asset():
    _app()
    view = CanvasView()
    view._page_sizes = {0: (1000, 1500), 1: (1000, 1500), 2: (1000, 1500)}
    source = _stamp(page=0)
    existing = _stamp(page=1)
    view._page_stamps = {0: [source], 1: [existing], 2: []}

    result = view.copy_stamp_to_missing_pages(
        source, [1, 2], {"angle_enabled": False, "position_enabled": False}
    )

    assert result == {"added": 1, "skipped": 1}
    assert len(view._page_stamps[1]) == 1
    assert len(view._page_stamps[2]) == 1
    copied = view._page_stamps[2][0]
    assert copied.asset_id == source.asset_id
    assert copied.rotation() == source.rotation()
    assert copied.scale() == source.scale()


def test_copy_stamp_random_offsets_are_applied_inside_configured_ranges(monkeypatch):
    _app()
    view = CanvasView()
    view._page_sizes = {0: (1000, 1500), 1: (1000, 1500)}
    source = _stamp(page=0)
    view._page_stamps = {0: [source], 1: []}
    values = iter([2.5, 3.0, -4.0])
    monkeypatch.setattr("src.ui.canvas_view.random.uniform", lambda _a, _b: next(values))

    view.copy_stamp_to_missing_pages(
        source,
        [1],
        {"angle_enabled": True, "angle_range": 3.0, "position_enabled": True, "position_mm": 5.0},
    )

    copied = view._page_stamps[1][0]
    assert copied.rotation() == 9.5
    assert copied.pos() != source.pos()


def test_copy_stamp_spec_uses_source_page_size_for_other_documents():
    _app()
    source_view = CanvasView()
    source_view._page_sizes = {0: (2000, 1000)}
    source = _stamp(page=0)
    source.setPos(QPointF(1000, 250))

    target_view = CanvasView()
    target_view._page_sizes = {0: (1000, 2000)}

    spec = source_view.build_stamp_copy_spec(source)
    target_view.copy_stamp_spec_to_missing_pages(
        spec, [0], {"angle_enabled": False, "position_enabled": False}
    )

    copied = target_view._page_stamps[0][0]
    assert copied.pos() == QPointF(500, 500)


def test_canvas_view_wheel_settings_are_applied_and_clamped():
    _app()
    view = CanvasView()

    view.set_wheel_settings({"mouse_wheel_mode": "zoom", "mouse_wheel_inverted": True})
    assert view._mouse_wheel_mode == "zoom"
    assert view._mouse_wheel_inverted is True

    view.set_wheel_settings({"mouse_wheel_mode": "bad", "mouse_wheel_inverted": False})
    assert view._mouse_wheel_mode == "scroll"
    assert view._mouse_wheel_inverted is False
