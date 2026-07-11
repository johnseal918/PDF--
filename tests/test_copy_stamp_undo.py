import os

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF
from PySide6.QtGui import QPixmap, QUndoStack
from PySide6.QtWidgets import QApplication, QGraphicsScene

from src.ui.stamp_item import StampItem
from src.ui.undo_commands import AddStampsBatchCommand


def test_batch_add_command_keeps_scene_and_page_index_in_sync():
    QApplication.instance() or QApplication([])
    scene = QGraphicsScene()
    stack = QUndoStack()
    page_stamps = {1: []}
    item = StampItem(QPixmap(10, 10), "seal-1")
    item.page_index = 1

    stack.push(AddStampsBatchCommand(scene, [(item, QPointF(5, 6), 1)], page_stamps))

    assert item.scene() is scene
    assert item in page_stamps[1]

    stack.undo()
    assert item.scene() is None
    assert item not in page_stamps[1]

    stack.redo()
    assert item.scene() is scene
    assert item in page_stamps[1]
