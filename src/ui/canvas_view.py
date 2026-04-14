"""
canvas_view.py — 中央画布视图组件

基于 QGraphicsView/QGraphicsScene 构建的可缩放、可翻页的文档预览画布。
支持滚轮缩放、页面导航。后续 M5 阶段将扩展印章图元拖拽交互。
"""

from PySide6.QtWidgets import (
    QGraphicsView, QGraphicsScene, QGraphicsPixmapItem,
    QWidget, QVBoxLayout, QHBoxLayout, QPushButton, QLabel,
    QSpinBox, QFrame
)
from PySide6.QtCore import Qt, Signal, QRectF, QPointF
from PySide6.QtGui import QPixmap, QWheelEvent, QPainter, QDragEnterEvent, QDropEvent, QUndoStack
from PIL import Image

from src.utils.image_utils import pil_to_qpixmap
from src.core.assets_manager import AssetsManager
from src.ui.stamp_item import StampItem
from src.ui.undo_commands import AddStampCommand, RemoveStampCommand, ModifyStampCommand


class CanvasView(QGraphicsView):
    """可缩放的画布视图，显示当前页面的底图。同时支持图元操作与预览。"""
    zoom_changed = Signal(float)
    binding_moved = Signal(int)  # 当骑缝章被拖拽时，向外发出其最新 y_offset

    def __init__(self, parent=None):
        super().__init__(parent)
        self._scene = QGraphicsScene(self)
        self.setScene(self._scene)

        # 渲染优化
        self.setRenderHints(
            QPainter.RenderHint.Antialiasing |
            QPainter.RenderHint.SmoothPixmapTransform
        )
        self.setDragMode(QGraphicsView.DragMode.ScrollHandDrag)
        self.setTransformationAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.setAcceptDrops(True)

        # 底图层与预览层
        self._page_item: QGraphicsPixmapItem | None = None
        self._binding_preview_item: QGraphicsPixmapItem | None = None
        self._zoom_factor = 1.0
        
        # 记录每页拥有的图元集合：{ page_int: [StampItem, ...] }
        self._page_stamps = {}
        self._current_page = 0
        
        # 撤销栈
        self.undo_stack = QUndoStack(self)
        self._assets_manager = AssetsManager()

    def set_page_image(self, pil_img: Image.Image, page_idx: int):
        """将 PIL Image 设置为当前展示页的底图，并切换前方的戳阵图元。"""
        # 保存旧页面的图元引用 (如果需要，但QGraphicsScene的图元只要不 remove 就一直存在，
        # 为了单页展示，我们需要把不在 current_page 的图元隐藏)
        self._current_page = page_idx
        
        pixmap = pil_to_qpixmap(pil_img)
        if self._page_item is not None:
            self._scene.removeItem(self._page_item)

        self._page_item = QGraphicsPixmapItem(pixmap)
        self._page_item.setZValue(0)  # 底层
        self._scene.addItem(self._page_item)
        self._scene.setSceneRect(QRectF(pixmap.rect()))
        
        if self._zoom_factor == 1.0:
            self.fitInView(self._page_item, Qt.AspectRatioMode.KeepAspectRatio)

        # 切换图元的显示状态
        self._refresh_stamps_visibility()

    def _refresh_stamps_visibility(self):
        for page, items in self._page_stamps.items():
            for item in items:
                item.setVisible(page == self._current_page)

    def set_binding_preview(self, asset_id: str, abs_path: str, params: dict):
        """骑缝章预览：将原始印章切成N份，每页只显示属于该页的那一条切片。"""
        from PySide6.QtGui import QPixmap
        import os
        
        self.binding_params = params
        start_p = params.get("start_page", 0)
        end_p = params.get("end_page", 0)
        total_pages = max(1, end_p - start_p + 1)
        margin = params.get("margin", -15)
        
        # 如果资源变了或者高级参数变了，重置并重新切片
        need_reslice = (
            not hasattr(self, '_binding_slices') or
            getattr(self, '_binding_asset_id', None) != asset_id or
            getattr(self, '_binding_total_pages', 0) != total_pages or
            getattr(self, '_binding_user_scale', 1.0) != params.get("scale", 1.0) or
            getattr(self, '_binding_user_rot', 0.0) != params.get("rotation", 0.0)
        )
        
        if need_reslice and os.path.exists(abs_path):
            full_pixmap = QPixmap(abs_path)
            if full_pixmap.isNull():
                return
            
            # 计算合适的缩放比（与普通印章一样作为基准大小）
            auto_scale = self._calc_auto_scale(full_pixmap)
            
            # 依要求保留继承逻辑作为基准尺寸的初始锚点
            for stamps in self._page_stamps.values():
                for st in stamps:
                    if getattr(st, 'asset_id', None) == asset_id and not getattr(st, 'is_binding_stamp', False):
                        auto_scale = st.scale()
                        break
            
            # 叠加独立调参面板的用户设定
            user_scale = params.get("scale", 1.0)
            auto_scale *= user_scale
            
            # 应用高级旋转
            user_rot = params.get("rotation", 0.0)
            if user_rot != 0.0:
                from PySide6.QtGui import QTransform
                t = QTransform().rotate(user_rot)
                full_pixmap = full_pixmap.transformed(t, Qt.TransformationMode.SmoothTransformation)
            
            # 先缩放整张印章，再切片（保证颜色和质量）
            scaled_w = int(full_pixmap.width() * auto_scale)
            scaled_h = int(full_pixmap.height() * auto_scale)
            scaled_pixmap = full_pixmap.scaled(scaled_w, scaled_h, 
                aspectMode=Qt.AspectRatioMode.KeepAspectRatio,
                mode=Qt.TransformationMode.SmoothTransformation)
            
            # 切成 N 份竖条，并代入 loss 夹缝损耗做预览拟真
            loss = params.get("loss", 4)
            sw = scaled_pixmap.width()
            sh = scaled_pixmap.height()
            part_width = sw // total_pages
            
            slices = []
            for i in range(total_pages):
                x1 = i * part_width
                x2 = sw if i == total_pages - 1 else x1 + part_width
                
                # 剔除损耗边界（中间互相接合的刀口处）
                if i > 0:
                    x1 += loss
                if i < total_pages - 1:
                    x2 -= loss
                    
                w = max(1, x2 - x1)
                slc = scaled_pixmap.copy(x1, 0, w, sh)
                slices.append(slc)
            
            self._binding_slices = slices
            self._binding_asset_id = asset_id
            self._binding_total_pages = total_pages
            self._binding_scale = auto_scale
            self._binding_user_scale = params.get("scale", 1.0)
            self._binding_user_rot = params.get("rotation", 0.0)
            self._binding_full_pixmap = full_pixmap
        
        # 显示当前页的切片
        self._show_current_binding_slice()
    
    def _show_current_binding_slice(self):
        """根据当前页码，显示对应的骑缝章切片"""
        import random
        
        # 先清掉旧的预览
        if self._binding_preview_item:
            self._scene.removeItem(self._binding_preview_item)
            self._binding_preview_item = None
        
        if not hasattr(self, '_binding_slices') or not self._binding_slices:
            return
        if not self._page_item:
            return
            
        params = getattr(self, 'binding_params', {})
        start_p = params.get("start_page", 0)
        end_p = params.get("end_page", 0)
        margin = params.get("margin", 15)
        displacement = params.get("displacement", 6.0)
        page = self._current_page
        
        if not (start_p <= page <= end_p):
            return
            
        idx = page - start_p
        if idx >= len(self._binding_slices):
            return
        
        slice_pixmap = self._binding_slices[idx]
        
        # 用最简单的 QGraphicsPixmapItem 展示切片
        item = QGraphicsPixmapItem(slice_pixmap)
        item.setZValue(999)
        
        # 获取页面在场景中的实际位置
        page_pos = self._page_item.pos()
        page_rect = self._page_item.boundingRect()
        
        # X 坐标：切片右边缘贴在页面右边缘内侧 margin 处
        x = page_pos.x() + page_rect.width() - margin - slice_pixmap.width()
        
        # Y 坐标基准：居中对齐，并叠加面板内的 y_offset 设置
        pure_center_y = page_pos.y() + (page_rect.height() - slice_pixmap.height()) / 2.0
        y_offset = params.get("y_offset", 0)
        
        # 为了防抖和记忆，我们在内部维护一个 y_offset。若面板传来的不一样，说明用户动了面板。
        # 如果一样，说明我们在使用内部状态或者纯默认状态。
        if getattr(self, '_binding_last_received_y_offset', None) != y_offset:
            self._binding_y_offset = pure_center_y + y_offset
            self._binding_last_received_y_offset = y_offset
        else:
            # 面板输入值未变，检查是否有拖动物理缓存
            if not hasattr(self, '_binding_y_offset'):
                self._binding_y_offset = pure_center_y + y_offset
                
        base_y = self._binding_y_offset
        
        # 每页随机 Y 轴抖动，模拟手工盖章的不均匀性
        # 用页码作为种子，保证同一页的抖动值固定不变
        rng = random.Random(page * 31 + 7)
        jitter_y = rng.uniform(-displacement, displacement)
        y = base_y + jitter_y
        
        item.setPos(x, y)
        item.setFlag(QGraphicsPixmapItem.GraphicsItemFlag.ItemIsMovable, True)
        item.setFlag(QGraphicsPixmapItem.GraphicsItemFlag.ItemIsSelectable, True)
        
        self._scene.addItem(item)
        self._binding_preview_item = item
    
    def _update_binding_placement(self):
        """翻页时更新骑缝章切片"""
        self._show_current_binding_slice()
        
    def get_binding_interactive_params(self) -> dict:
        """收集骑缝图元的手动交互形变参数，供导出渲染时进行同步加工"""
        # 如果用户拖拽了切片位置，更新存储的 Y 值
        if self._binding_preview_item:
            self._binding_y_offset = self._binding_preview_item.y()
        return {
            "scale": getattr(self, '_binding_scale', 1.0),
            "rotation": 0,
            "y": getattr(self, '_binding_y_offset', 0)
        }

    def clear_binding_preview(self):
        if self._binding_preview_item:
            self._scene.removeItem(self._binding_preview_item)
            self._binding_preview_item = None
        if hasattr(self, '_binding_slices'):
            del self._binding_slices
        if hasattr(self, '_binding_asset_id'):
            del self._binding_asset_id

    def clear_canvas(self):
        self._scene.clear()
        self._page_item = None
        self._binding_preview_item = None
        self._page_stamps.clear()
        self.undo_stack.clear()

    def wheelEvent(self, event: QWheelEvent):
        """滚轮缩放。Ctrl+滚轮 缩放，普通滚轮 上下滚动。"""
        if event.modifiers() == Qt.KeyboardModifier.ControlModifier:
            delta = event.angleDelta().y()
            if delta > 0:
                factor = 1.15
            else:
                factor = 1.0 / 1.15

            self._zoom_factor *= factor
            # 限制缩放范围
            if 0.1 <= self._zoom_factor <= 10.0:
                self.scale(factor, factor)
                self.zoom_changed.emit(self._zoom_factor)
            else:
                self._zoom_factor /= factor  # 回退
        else:
            super().wheelEvent(event)

    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)
        # 如果存在骑缝章预览，就在按键释放时重新计算一次位置偏移并扔出去
        if self._binding_preview_item:
            y = self._binding_preview_item.y()
            # 需要剔除本来因为这页存在的随机抖动，获得基准位置
            page = self._current_page
            rng = __import__("random").Random(page * 31 + 7)
            displacement = self.binding_params.get("displacement", 6.0)
            jitter_y = rng.uniform(-displacement, displacement)
            
            base_y = y - jitter_y
            self._binding_y_offset = base_y  # 内部存一下实时物理量
            
            # 反算给 property panel 的 offset
            page_rect = self._page_item.boundingRect()
            page_pos = self._page_item.pos()
            pure_center_y = page_pos.y() + (page_rect.height() - self._binding_preview_item.boundingRect().height()) / 2.0
            
            new_offset = int(base_y - pure_center_y)
            self._binding_last_received_y_offset = new_offset # 自己同步一下，防循环
            self.binding_moved.emit(new_offset)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasText() and event.mimeData().text().startswith("pdfseal:"):
            event.acceptProposedAction()
        else:
            super().dragEnterEvent(event)

    def dragMoveEvent(self, event):
        if event.mimeData().hasText() and event.mimeData().text().startswith("pdfseal:"):
            event.acceptProposedAction()
        else:
            super().dragMoveEvent(event)

    def dropEvent(self, event: QDropEvent):
        if event.mimeData().hasText() and event.mimeData().text().startswith("pdfseal:"):
            parts = event.mimeData().text().split(":")
            if len(parts) == 3:
                category = parts[1]
                asset_id = parts[2]
                self._add_stamp_from_library(category, asset_id, event.position().toPoint())
            event.acceptProposedAction()
        else:
            super().dropEvent(event)

    def _add_stamp_from_library(self, category: str, asset_id: str, view_pos):
        assets = self._assets_manager.get_assets(category)
        target = next((a for a in assets if a["id"] == asset_id), None)
        if not target: return
        
        abs_path = self._assets_manager.get_absolute_path(target["path"])
        pixmap = QPixmap(abs_path)
        
        item = StampItem(pixmap, asset_id)
        item.page_index = self._current_page
        # 将屏幕视口坐标转为内部场景坐标
        scene_pos = self.mapToScene(view_pos)
        scene_pos = QPointF(scene_pos.x(), scene_pos.y())
        item.setZValue(10)
        
        # ── A4 自适应缩放：基于页面宽度计算合理初始比例 ──
        auto_scale = self._calc_auto_scale(pixmap)
        item.setScale(auto_scale)
        
        # 将 item 装载进当前页列表
        if self._current_page not in self._page_stamps:
            self._page_stamps[self._current_page] = []
        self._page_stamps[self._current_page].append(item)
        
        # 连接形变结束信号
        item.movement_finished.connect(self._on_stamp_modified)
        item.action_requested.connect(self._on_stamp_action)
        
        cmd = AddStampCommand(self._scene, item, scene_pos)
        self.undo_stack.push(cmd)

    def add_stamp_at_center(self, category: str, asset_id: str):
        """双击素材时，将印章添加到当前画布的视口中央"""
        assets = self._assets_manager.get_assets(category)
        target = next((a for a in assets if a["id"] == asset_id), None)
        if not target: return
        
        abs_path = self._assets_manager.get_absolute_path(target["path"])
        pixmap = QPixmap(abs_path)
        
        item = StampItem(pixmap, asset_id)
        item.page_index = self._current_page
        item.setZValue(10)
        
        # 计算当前视口中心对应的场景坐标
        viewport_center = self.viewport().rect().center()
        scene_center = self.mapToScene(viewport_center)
        
        # A4 自适应缩放
        auto_scale = self._calc_auto_scale(pixmap)
        item.setScale(auto_scale)
        
        if self._current_page not in self._page_stamps:
            self._page_stamps[self._current_page] = []
        self._page_stamps[self._current_page].append(item)
        
        item.movement_finished.connect(self._on_stamp_modified)
        item.action_requested.connect(self._on_stamp_action)
        
        cmd = AddStampCommand(self._scene, item, scene_center)
        self.undo_stack.push(cmd)

    def _calc_auto_scale(self, pixmap: QPixmap) -> float:
        """根据底图A4纸张宽度计算印章的合理初始缩放比。
        目标：印章宽度约为页面宽度的15%。
        """
        if self._page_item:
            page_w = self._page_item.boundingRect().width()
            if page_w > 0 and pixmap.width() > 0:
                # 目标宽度 = 页面宽度 * 15%
                target_w = page_w * 0.15
                scale = target_w / pixmap.width()
                # 限制在合理范围
                return max(0.05, min(scale, 5.0))
        return 0.2  # 无底图时的安全默认比例

    def _on_stamp_modified(self, item, states):
        # 封装到撤销栈
        cmd = ModifyStampCommand(item, states, states)
        self.undo_stack.push(cmd)

    def _on_stamp_action(self, item, action: str):
        if action == "bring_front":
            max_z = max([st.zValue() for st in self._page_stamps.get(self._current_page, [])], default=10)
            item.setZValue(max_z + 1)
        elif action == "send_back":
            min_z = min([st.zValue() for st in self._page_stamps.get(self._current_page, [])], default=10)
            new_z = max(1, min_z - 1)
            item.setZValue(new_z)
        elif action == "delete":
            from src.ui.undo_commands import RemoveStampCommand
            cmd = RemoveStampCommand(self._scene, item, self._page_stamps)
            self.undo_stack.push(cmd)

    def keyPressEvent(self, event):
        # 捕捉 Delete 键删除被选中的图元
        if event.key() == Qt.Key.Key_Delete or event.key() == Qt.Key.Key_Backspace:
            for item in self._scene.selectedItems():
                if isinstance(item, StampItem):
                    cmd = RemoveStampCommand(self._scene, item, self._page_stamps)
                    self.undo_stack.push(cmd)
        
        super().keyPressEvent(event)

    def get_all_stamps_data(self) -> dict:
        """抽取所有页面的 StampItem 状态用于序列化"""
        data = {}
        for page_idx, items in self._page_stamps.items():
            page_data = []
            for item in items:
                # 仅保留在画布里实际存活的印章（排除被撤销移除的）
                if item.scene() == self._scene:
                    page_data.append({
                        "asset_id": item.asset_id,
                        "x": item.pos().x(),
                        "y": item.pos().y(),
                        "scale": item.scale(),
                        "rotation": item.rotation()
                    })
            if page_data:
                data[page_idx] = page_data
        return data

    def clear_all_stamps(self):
        """清空所有的用户印章，不影响底图"""
        for items in self._page_stamps.values():
            for item in items:
                if item.scene() == self._scene:
                    self._scene.removeItem(item)
        self._page_stamps.clear()
        self.undo_stack.clear()

    def apply_stamps_data(self, stamps_dict: dict):
        """导入模板时重建图元"""
        self.clear_all_stamps()
        
        for page_idx_str, items in stamps_dict.items():
            page_idx = int(page_idx_str)
            if page_idx not in self._page_stamps:
                self._page_stamps[page_idx] = []
                
            for st in items:
                # 查原图
                assets = self._assets_manager.get_assets("stamps") + self._assets_manager.get_assets("signatures")
                target = next((a for a in assets if a["id"] == st["asset_id"]), None)
                if not target:
                    continue
                abs_path = self._assets_manager.get_absolute_path(target["path"])
                pixmap = QPixmap(abs_path)
                
                item = StampItem(pixmap, st["asset_id"])
                item.page_index = page_idx
                item.setPos(QPointF(st["x"], st["y"]))
                item.setScale(st["scale"])
                item.setRotation(st["rotation"])
                item.setZValue(10)
                
                self._scene.addItem(item)
                item.setVisible(page_idx == self._current_page)
                self._page_stamps[page_idx].append(item)
                item.movement_finished.connect(self._on_stamp_modified)
                item.action_requested.connect(self._on_stamp_action)

class CanvasWidget(QWidget):
    """画布容器组件：包含画布视图 + 底部页码导航栏。"""

    page_changed = Signal(int)  # 页码变化信号

    def __init__(self, parent=None):
        super().__init__(parent)
        self._current_page = 0
        self._total_pages = 0

        # 布局
        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        # 画布
        self.canvas_view = CanvasView()
        layout.addWidget(self.canvas_view, stretch=1)

        # 底部页码导航栏
        nav_bar = QHBoxLayout()
        nav_bar.setContentsMargins(8, 4, 8, 4)

        self._btn_prev = QPushButton("◀ 上一页")
        self._btn_prev.setFixedWidth(90)
        self._btn_prev.clicked.connect(self._go_prev)

        self._page_spin = QSpinBox()
        self._page_spin.setMinimum(1)
        self._page_spin.setMaximum(1)
        self._page_spin.setFixedWidth(60)
        self._page_spin.valueChanged.connect(self._on_spin_changed)

        self._label_total = QLabel(" / 0 页")

        self._btn_next = QPushButton("下一页 ▶")
        self._btn_next.setFixedWidth(90)
        self._btn_next.clicked.connect(self._go_next)

        nav_bar.addStretch()
        
        # 缩放控件
        self._btn_zoom_out = QPushButton("-")
        self._btn_zoom_out.setFixedWidth(30)
        self._btn_zoom_out.setToolTip("缩小")
        self._btn_zoom_out.setStyleSheet("font-size: 16px; font-weight: 700;")
        self._btn_zoom_out.clicked.connect(lambda: self._apply_zoom(1.0 / 1.15))
        
        self._btn_zoom_reset = QPushButton("100 %")
        self._btn_zoom_reset.setFixedWidth(75)
        self._btn_zoom_reset.setToolTip("点击重置到 100%")
        self._btn_zoom_reset.clicked.connect(self._reset_zoom)
        
        self._btn_zoom_in = QPushButton("+")
        self._btn_zoom_in.setFixedWidth(30)
        self._btn_zoom_in.setToolTip("放大")
        self._btn_zoom_in.setStyleSheet("font-size: 16px; font-weight: 700;")
        self._btn_zoom_in.clicked.connect(lambda: self._apply_zoom(1.15))
        
        nav_bar.addWidget(self._btn_zoom_out)
        nav_bar.addWidget(self._btn_zoom_reset)
        nav_bar.addWidget(self._btn_zoom_in)
        
        # 添加分隔线
        separator = QFrame()
        separator.setFrameShape(QFrame.Shape.VLine)
        separator.setFrameShadow(QFrame.Shadow.Sunken)
        nav_bar.addWidget(separator)

        nav_bar.addWidget(self._btn_prev)
        nav_bar.addWidget(self._page_spin)
        nav_bar.addWidget(self._label_total)
        nav_bar.addWidget(self._btn_next)
        
        self.btn_mgr = QPushButton("⚙️ 管理此页")
        self.btn_mgr.setFixedWidth(90)
        self.btn_mgr.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.btn_mgr.customContextMenuRequested.connect(self._show_page_menu)
        self.btn_mgr.clicked.connect(lambda: self._show_page_menu(QPointF(0,self.btn_mgr.height()).toPoint()))
        nav_bar.addWidget(self.btn_mgr)
        
        nav_bar.addStretch()

        layout.addLayout(nav_bar)
        self._update_nav_state()
        
        self.canvas_view.zoom_changed.connect(self._on_zoom_changed)

    def _apply_zoom(self, factor):
        self.canvas_view._zoom_factor *= factor
        if 0.1 <= self.canvas_view._zoom_factor <= 10.0:
            self.canvas_view.scale(factor, factor)
            self._on_zoom_changed(self.canvas_view._zoom_factor)
        else:
            self.canvas_view._zoom_factor /= factor

    def _on_zoom_changed(self, zoom_factor):
        percent = int(zoom_factor * 100)
        self._btn_zoom_reset.setText(f"{percent} %")

    def _reset_zoom(self):
        """Reset zoom to baseline 100% view for current page."""
        if not self.canvas_view._page_item:
            return
        self.canvas_view.resetTransform()
        self.canvas_view._zoom_factor = 1.0
        self.canvas_view.fitInView(self.canvas_view._page_item, Qt.AspectRatioMode.KeepAspectRatio)
        self._on_zoom_changed(self.canvas_view._zoom_factor)
        
    def _show_page_menu(self, pos):
        from PySide6.QtWidgets import QMenu, QMessageBox
        QMessageBox.information(self, "提示", "页面管理功能预留（需深入联通底层引擎）。\n若需删减 PDF 页请在保存为底层前完成预处理。")

    def set_total_pages(self, total: int):
        """设置总页数并更新导航控件。"""
        self._total_pages = total
        self._current_page = 0
        self._page_spin.setMaximum(max(1, total))
        self._page_spin.setValue(1)
        self._label_total.setText(f" / {total} 页")
        self._update_nav_state()

    def get_current_page(self) -> int:
        return self._current_page

    def _go_prev(self):
        if self._current_page > 0:
            self._current_page -= 1
            self._page_spin.setValue(self._current_page + 1)
            self.page_changed.emit(self._current_page)
            self._update_nav_state()
            self.canvas_view._update_binding_placement()

    def _go_next(self):
        if self._current_page < self._total_pages - 1:
            self._current_page += 1
            self._page_spin.setValue(self._current_page + 1)
            self.page_changed.emit(self._current_page)
            self._update_nav_state()
            self.canvas_view._update_binding_placement()

    def _on_spin_changed(self, value: int):
        new_page = value - 1
        if 0 <= new_page < self._total_pages and new_page != self._current_page:
            self._current_page = new_page
            self.page_changed.emit(self._current_page)
            self._update_nav_state()
            self.canvas_view._update_binding_placement()

    def _update_nav_state(self):
        self._btn_prev.setEnabled(self._current_page > 0)
        self._btn_next.setEnabled(self._current_page < self._total_pages - 1)
