"""
stamp_item.py — 承载印章拖拽、缩放、旋转的可交互自定义图元节点。
基于 QGraphicsObject 获得强大的交互响应与信号功能，同时绘制边角缩放节点和顶部旋转手柄。
当发生操作结束（鼠标Release）时抛出结束动作的信号，交由调用层进入撤销历史栈。
"""

import math
from PySide6.QtWidgets import QGraphicsObject, QStyleOptionGraphicsItem, QWidget, QGraphicsSceneMouseEvent, QGraphicsSceneHoverEvent, QMenu, QGraphicsSceneContextMenuEvent
from PySide6.QtCore import Qt, QRectF, QPointF, Signal
from PySide6.QtGui import QPixmap, QPainter, QCursor, QColor, QBrush, QPen

class StampItem(QGraphicsObject):
    
    # 定义交互完成后的信号，用于撤销栈
    movement_finished = Signal(object, tuple) # (self, ((old_p, new_p), (old_s, new_s), (old_r, new_r)))
    action_requested = Signal(object, str)

    def __init__(self, pixmap: QPixmap, asset_id: str, parent=None):
        super().__init__(parent)
        self.setAcceptHoverEvents(True)
        self.setFlags(
            QGraphicsObject.GraphicsItemFlag.ItemIsSelectable |
            QGraphicsObject.GraphicsItemFlag.ItemIsMovable |
            QGraphicsObject.GraphicsItemFlag.ItemSendsGeometryChanges
        )
        
        self.pixmap = pixmap
        self.asset_id = asset_id # 保存图片ID方便后续溯源
        self.copy_random_angle_enabled = False
        self.copy_random_position_enabled = False
        
        # 尺寸
        self.w = pixmap.width()
        self.h = pixmap.height()
        
        # 为了使旋转中心自动落在图元正中心，我们将中心映射为 (0,0)
        # 绘制区域落在 (-w/2, -h/2) 到 (w/2, h/2)
        # 交互手柄尺寸的基准大小
        self.handle_size = 18.0
        self.rotate_length = 45.0
        
        # 当前进行的交互态
        self.action_state = None  # None, 'moving', 'scaling', 'rotating'
        self.mouse_press_pos: QPointF = QPointF()
        
        # 保存按下瞬间的状态以产生 delta 指令
        self.init_pos = self.pos()
        self.init_scale = self.scale()
        self.init_rotation = self.rotation()
        self.init_mouse_angle = 0.0

    def setScale(self, scale: float):
        self.prepareGeometryChange()
        super().setScale(scale)

    @property
    def current_handle_size(self):
        s = self.scale()
        return self.handle_size / s if s > 0.05 else self.handle_size

    @property
    def current_rotate_length(self):
        s = self.scale()
        return self.rotate_length / s if s > 0.05 else self.rotate_length

    def boundingRect(self) -> QRectF:
        # 画框囊括控制块和旋转手柄
        bound = QRectF(-self.w/2, -self.h/2, self.w, self.h)
        hsize = self.current_handle_size
        padding = hsize / 2.0
        bound.adjust(-padding, -(padding + self.current_rotate_length + hsize), padding, padding)
        return bound


    def paint(self, painter: QPainter, option: QStyleOptionGraphicsItem, widget: QWidget = None):
        painter.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)
        painter.drawPixmap(int(-self.w/2), int(-self.h/2), self.pixmap)
            
        if self.isSelected():
            pen = QPen(QColor(0, 120, 215))
            pen.setStyle(Qt.PenStyle.DashLine)
            pen.setWidth(1)
            pen.setCosmetic(True) # 抵消自身缩放
            painter.setPen(pen)
            
            painter.drawRect(QRectF(-self.w/2, -self.h/2, self.w, self.h))
            
            painter.setBrush(QBrush(QColor(0, 120, 215)))
            painter.setPen(QPen(Qt.GlobalColor.white))
            
            hsize = self.current_handle_size
            h2 = hsize / 2.0
            r_len = self.current_rotate_length
            
            handles = self._get_handle_rects()
            for key in ['tl', 'tr', 'bl', 'br']:
                rect = handles[key]
                painter.drawRect(rect)
            
            # 取消线段绘制的缩放
            painter.setPen(pen)
            painter.drawLine(QPointF(0, -self.h/2), QPointF(0, -self.h/2 - r_len))
            
            painter.setPen(QPen(Qt.GlobalColor.white))
            painter.drawEllipse(handles['rotate'])

    def _get_handle_rects(self):
        hsize = self.current_handle_size
        h2 = hsize / 2.0
        r_len = self.current_rotate_length
        return {
            'tl': QRectF(-self.w/2 - h2, -self.h/2 - h2, hsize, hsize),
            'tr': QRectF(self.w/2 - h2, -self.h/2 - h2, hsize, hsize),
            'bl': QRectF(-self.w/2 - h2, self.h/2 - h2, hsize, hsize),
            'br': QRectF(self.w/2 - h2, self.h/2 - h2, hsize, hsize),
            'rotate': QRectF(-h2, -self.h/2 - r_len - h2, hsize, hsize)
        }
        
    def _get_hit_handle_rects(self):
        """给实际碰撞测试扩大捕捉范围（通过数倍扩充 margin），让其极其容易被鼠标选中"""
        handles = self._get_handle_rects()
        # 继续扩大2倍边距（即原先是额外扩容1倍，现在扩容到3倍于视觉尺寸以外的位置）
        margin = self.current_handle_size * 2.5 
        expanded = {}
        for k, v in handles.items():
            expanded[k] = v.adjusted(-margin, -margin, margin, margin)
        return expanded

    def hoverMoveEvent(self, event: QGraphicsSceneHoverEvent):
        if self.isSelected():
            pos = event.pos()
            hit_handles = self._get_hit_handle_rects()
            if hit_handles['tl'].contains(pos) or hit_handles['br'].contains(pos):
                self.setCursor(Qt.CursorShape.SizeFDiagCursor)
            elif hit_handles['tr'].contains(pos) or hit_handles['bl'].contains(pos):
                self.setCursor(Qt.CursorShape.SizeBDiagCursor)
            elif hit_handles['rotate'].contains(pos):
                self.setCursor(Qt.CursorShape.PointingHandCursor)
            else:
                self.setCursor(Qt.CursorShape.SizeAllCursor)
        else:
            self.setCursor(Qt.CursorShape.ArrowCursor)
        super().hoverMoveEvent(event)

    def mousePressEvent(self, event: QGraphicsSceneMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton and self.isSelected():
            pos = event.pos()
            hit_handles = self._get_hit_handle_rects()
            
            if (hit_handles['tl'].contains(pos) or hit_handles['tr'].contains(pos) or 
                hit_handles['bl'].contains(pos) or hit_handles['br'].contains(pos)):
                self.action_state = 'scaling'
            elif hit_handles['rotate'].contains(pos): 
                self.action_state = 'rotating'
                scene_pos = event.scenePos()
                my_scene_pos = self.scenePos()
                dx = scene_pos.x() - my_scene_pos.x()
                dy = scene_pos.y() - my_scene_pos.y()
                self.init_mouse_angle = math.degrees(math.atan2(dy, dx))
            else:
                self.action_state = 'moving'
                
            self.mouse_press_pos = event.scenePos()
            self.init_pos = self.pos()
            self.init_scale = self.scale()
            self.init_rotation = self.rotation()
            
            if self.action_state != 'moving':
                event.accept()
                return
                
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event: QGraphicsSceneMouseEvent):
        if self.action_state == 'scaling':
            curr_pos = event.scenePos()
            dist_initial = math.hypot(self.mouse_press_pos.x() - self.scenePos().x(), 
                                      self.mouse_press_pos.y() - self.scenePos().y())
            dist_current = math.hypot(curr_pos.x() - self.scenePos().x(), 
                                      curr_pos.y() - self.scenePos().y())
            if dist_initial > 0:
                scale_factor = dist_current / dist_initial
                new_scale = self.init_scale * scale_factor
                self.setScale(max(0.05, min(new_scale, 20.0)))

        elif self.action_state == 'rotating':
            curr_pos = event.scenePos()
            my_scene_pos = self.scenePos()
            dx = curr_pos.x() - my_scene_pos.x()
            dy = curr_pos.y() - my_scene_pos.y()
            curr_angle = math.degrees(math.atan2(dy, dx))
            
            angle_diff = curr_angle - self.init_mouse_angle
            new_rotation = self.init_rotation + angle_diff
            self.setRotation(new_rotation)

        else:
            super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event: QGraphicsSceneMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton:
            final_pos = self.pos()
            final_scale = self.scale()
            final_rotation = self.rotation()
            
            if (math.hypot(final_pos.x()-self.init_pos.x(), final_pos.y()-self.init_pos.y()) > 0.1 or 
                abs(final_scale - self.init_scale) > 0.001 or
                abs(final_rotation - self.init_rotation) > 0.05):
                
                self.movement_finished.emit(self, ( 
                    (self.init_pos, final_pos), 
                    (self.init_scale, final_scale), 
                    (self.init_rotation, final_rotation) 
                ))
            self.action_state = None
        super().mouseReleaseEvent(event)

    def contextMenuEvent(self, event: "QGraphicsSceneContextMenuEvent"):
        if getattr(self, "is_binding_stamp", False):
            # 骑缝章不支持独立的层级删除交互
            return
            
        menu = QMenu()
        bring_front = menu.addAction("移到顶层")
        send_back = menu.addAction("移到底层")
        unify_document = None
        unify_open_documents = None
        copy_document = None
        copy_open_documents = None
        random_angle = None
        random_position = None
        if getattr(self, "category", "stamps") == "stamps":
            unify_document = menu.addAction("统一当前文档全部页面的印章尺寸")
            unify_open_documents = menu.addAction("统一所有已打开文档中的同款印章尺寸")
            menu.addSeparator()
            copy_document = menu.addAction("将此印章复制到当前文档的其余页面")
            copy_open_documents = menu.addAction("将此印章复制到其余已打开文档")
            random_angle = menu.addAction("复制时使用随机角度")
            random_angle.setCheckable(True)
            random_angle.setChecked(bool(self.copy_random_angle_enabled))
            random_position = menu.addAction("复制时使用随机位置")
            random_position.setCheckable(True)
            random_position.setChecked(bool(self.copy_random_position_enabled))
        menu.addSeparator()
        delete_item = menu.addAction("删除")
        
        action = menu.exec(event.screenPos())
        if action == bring_front:
            self.action_requested.emit(self, "bring_front")
        elif action == send_back:
            self.action_requested.emit(self, "send_back")
        elif action == unify_document:
            self.action_requested.emit(self, "unify_size_document")
        elif action == unify_open_documents:
            self.action_requested.emit(self, "unify_size_open_documents")
        elif action == copy_document:
            self.action_requested.emit(self, "copy_to_document")
        elif action == copy_open_documents:
            self.action_requested.emit(self, "copy_to_open_documents")
        elif action == random_angle:
            self.copy_random_angle_enabled = random_angle.isChecked()
            self.action_requested.emit(self, "toggle_copy_random_angle")
        elif action == random_position:
            self.copy_random_position_enabled = random_position.isChecked()
            self.action_requested.emit(self, "toggle_copy_random_position")
        elif action == delete_item:
            self.action_requested.emit(self, "delete")
