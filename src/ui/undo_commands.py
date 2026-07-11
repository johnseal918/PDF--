"""
undo_commands.py - Undo/redo commands for stamp operations.
"""

from PySide6.QtCore import QPointF
from PySide6.QtGui import QUndoCommand


class AddStampCommand(QUndoCommand):
    def __init__(self, scene, item, position: QPointF, text="添加印章"):
        super().__init__(text)
        self.scene = scene
        self.item = item
        self.position = position

    def undo(self):
        self.scene.removeItem(self.item)

    def redo(self):
        self.scene.addItem(self.item)
        self.item.setPos(self.position)


class AddStampsBatchCommand(QUndoCommand):
    def __init__(self, scene, entries, page_stamps, text="复制印章"):
        super().__init__(text)
        self.scene = scene
        self.entries = list(entries)
        self.page_stamps = page_stamps

    def undo(self):
        for item, _position, page_index in self.entries:
            self.scene.removeItem(item)
            page_items = self.page_stamps.get(page_index, [])
            if item in page_items:
                page_items.remove(item)

    def redo(self):
        for item, position, page_index in self.entries:
            if item.scene() is not self.scene:
                self.scene.addItem(item)
            item.page_index = page_index
            item.setPos(position)
            page_items = self.page_stamps.setdefault(page_index, [])
            if item not in page_items:
                page_items.append(item)


class RemoveStampCommand(QUndoCommand):
    def __init__(self, scene, item, page_stamps=None, text="删除印章"):
        super().__init__(text)
        self.scene = scene
        self.item = item
        self.page_stamps = page_stamps
        self.page_index = getattr(item, "page_index", None)
        self.position = item.pos()
        self.scale = item.scale()
        self.rotation = item.rotation()

    def undo(self):
        self.scene.addItem(self.item)
        self.item.setPos(self.position)
        self.item.setScale(self.scale)
        self.item.setRotation(self.rotation)
        if self.page_stamps is not None and self.page_index is not None:
            page_items = self.page_stamps.setdefault(self.page_index, [])
            if self.item not in page_items:
                page_items.append(self.item)

    def redo(self):
        self.scene.removeItem(self.item)
        if self.page_stamps is not None and self.page_index is not None:
            page_items = self.page_stamps.get(self.page_index, [])
            if self.item in page_items:
                page_items.remove(self.item)


class ModifyStampCommand(QUndoCommand):
    def __init__(self, item, old_state, new_state, text="调整印章"):
        """
        old_state/new_state:
        ((old_pos, new_pos), (old_scale, new_scale), (old_rotation, new_rotation))
        """
        super().__init__(text)
        self.item = item
        self.old_pos = old_state[0][0]
        self.new_pos = new_state[0][1]
        self.old_scale = old_state[1][0]
        self.new_scale = new_state[1][1]
        self.old_rotation = old_state[2][0]
        self.new_rotation = new_state[2][1]

    def undo(self):
        self.item.setPos(self.old_pos)
        self.item.setScale(self.old_scale)
        self.item.setRotation(self.old_rotation)

    def redo(self):
        self.item.setPos(self.new_pos)
        self.item.setScale(self.new_scale)
        self.item.setRotation(self.new_rotation)
