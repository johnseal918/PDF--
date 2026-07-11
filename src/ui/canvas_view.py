"""
Canvas view components.
"""

from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QDragEnterEvent, QDropEvent, QPainter, QPixmap, QUndoStack, QWheelEvent
from PySide6.QtWidgets import (
    QFrame,
    QGraphicsPixmapItem,
    QGraphicsScene,
    QGraphicsView,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)
from PIL import Image

from src.core.assets_manager import AssetsManager
from src.core.render_engine import RenderEngine
from src.ui.stamp_item import StampItem
from src.ui.undo_commands import AddStampCommand, ModifyStampCommand, RemoveStampCommand
from src.utils.image_utils import pil_to_qpixmap


class CanvasView(QGraphicsView):
    zoom_changed = Signal(float)
    binding_moved = Signal(int)
    stamp_size_unified = Signal(float)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._scene = QGraphicsScene(self)
        self.setScene(self._scene)

        self.setRenderHints(QPainter.RenderHint.Antialiasing | QPainter.RenderHint.SmoothPixmapTransform)
        self.setDragMode(QGraphicsView.DragMode.ScrollHandDrag)
        self.setTransformationAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)
        self.setResizeAnchor(QGraphicsView.ViewportAnchor.AnchorUnderMouse)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.setAcceptDrops(True)

        self._page_item: QGraphicsPixmapItem | None = None
        self._binding_preview_item: QGraphicsPixmapItem | None = None
        self._zoom_factor = 1.0
        self._page_stamps: dict[int, list[StampItem]] = {}
        self._page_sizes: dict[int, tuple[int, int]] = {}
        self._current_page = 0

        self.undo_stack = QUndoStack(self)
        self._assets_manager = AssetsManager()

    def set_page_image(self, pil_img: Image.Image, page_idx: int):
        self._current_page = page_idx

        pixmap = pil_to_qpixmap(pil_img)
        if self._page_item is not None:
            self._scene.removeItem(self._page_item)

        self._page_item = QGraphicsPixmapItem(pixmap)
        self._page_item.setZValue(0)
        self._scene.addItem(self._page_item)
        self._scene.setSceneRect(QRectF(pixmap.rect()))
        self._page_sizes[page_idx] = (pixmap.width(), pixmap.height())

        if self._zoom_factor == 1.0:
            self.fitInView(self._page_item, Qt.AspectRatioMode.KeepAspectRatio)

        self._refresh_stamps_visibility()

    def _refresh_stamps_visibility(self):
        for page, items in self._page_stamps.items():
            for item in items:
                item.setVisible(page == self._current_page)

    def remap_page_stamps(self, page_idx: int, scale_x: float, scale_y: float):
        for item in self._page_stamps.get(page_idx, []):
            item.setPos(item.x() * scale_x, item.y() * scale_y)

    def _page_size_for_index(self, page_idx: int) -> tuple[float, float]:
        size = self._page_sizes.get(page_idx)
        if size:
            return float(size[0]), float(size[1])
        if self._page_item is not None:
            rect = self._page_item.boundingRect()
            if rect.width() > 0 and rect.height() > 0:
                return float(rect.width()), float(rect.height())
        return float(RenderEngine.A4_WIDTH_PX), float(RenderEngine.A4_HEIGHT_PX)

    def _item_width_a4(self, item: StampItem) -> float:
        page_idx = getattr(item, "page_index", self._current_page)
        page_w, page_h = self._page_size_for_index(page_idx)
        page_to_a4 = RenderEngine.get_page_to_a4_scale(page_w, page_h)
        if page_to_a4 <= 0:
            return 0.0
        return float(item.w) * float(item.scale()) * page_to_a4

    def _unify_all_stamp_sizes_from_item(self, src_item: StampItem):
        target_width_a4 = self._item_width_a4(src_item)
        if target_width_a4 <= 1.0:
            return

        for page_idx, items in self._page_stamps.items():
            page_w, page_h = self._page_size_for_index(page_idx)
            target_width_on_page = RenderEngine.binding_units_on_page(page_w, page_h, target_width_a4)
            for item in items:
                if item.scene() != self._scene or item.w <= 0:
                    continue
                new_scale = max(0.05, min(float(target_width_on_page) / float(item.w), 20.0))
                item.setScale(new_scale)

        self.stamp_size_unified.emit(float(target_width_a4))
        self._update_binding_placement()

    def _find_binding_reference_width_a4(self, asset_id: str) -> float | None:
        if not asset_id:
            return None

        candidate_pages = [self._current_page] + [p for p in sorted(self._page_stamps.keys()) if p != self._current_page]
        for page_idx in candidate_pages:
            page_size = self._page_sizes.get(page_idx)
            if not page_size:
                continue
            page_to_a4 = RenderEngine.get_page_to_a4_scale(page_size[0], page_size[1])
            if page_to_a4 <= 0:
                continue

            for item in self._page_stamps.get(page_idx, []):
                if item.asset_id != asset_id:
                    continue
                if item.scene() != self._scene:
                    continue

                width_page = float(item.w) * float(item.scale())
                width_a4 = width_page * page_to_a4
                if width_a4 > 1.0:
                    return width_a4
        return None

    def set_binding_preview(self, asset_id: str, abs_path: str, params: dict):
        from PySide6.QtGui import QTransform
        import os

        self.binding_params = params
        start_p = int(params.get("start_page", 0))
        end_p = int(params.get("end_page", 0))
        total_pages = max(1, end_p - start_p + 1)
        page_size = (
            int(self._page_item.boundingRect().width()) if self._page_item else 0,
            int(self._page_item.boundingRect().height()) if self._page_item else 0,
        )
        ref_width_a4 = self._find_binding_reference_width_a4(asset_id)
        user_scale = max(0.01, float(params.get("scale", 1.0)))
        forced_target_width_a4 = float(params.get("target_width_a4", 0.0) or 0.0)
        if forced_target_width_a4 > 1.0:
            base_width_a4 = forced_target_width_a4
            user_scale = 1.0
        else:
            if ref_width_a4 is None:
                base_width_a4 = float(RenderEngine.binding_target_width_on_a4(1.0))
            else:
                base_width_a4 = ref_width_a4

        need_reslice = (
            not hasattr(self, "_binding_slices_a4")
            or getattr(self, "_binding_asset_id", None) != asset_id
            or getattr(self, "_binding_total_pages", 0) != total_pages
            or getattr(self, "_binding_user_scale", 1.0) != user_scale
            or getattr(self, "_binding_user_rot", 0.0) != float(params.get("rotation", 0.0))
            or getattr(self, "_binding_page_size", None) != page_size
            or getattr(self, "_binding_ref_width_a4", None) != int(round(base_width_a4))
        )

        if need_reslice and os.path.exists(abs_path):
            full_pixmap = QPixmap(abs_path)
            if full_pixmap.isNull():
                return

            user_rot = float(params.get("rotation", 0.0))
            if user_rot != 0.0:
                full_pixmap = full_pixmap.transformed(QTransform().rotate(user_rot), Qt.TransformationMode.SmoothTransformation)

            target_w_a4 = max(1, int(round(base_width_a4 * user_scale)))
            target_h_a4 = max(1, int(round(full_pixmap.height() * (target_w_a4 / max(1.0, float(full_pixmap.width()))))))
            scaled_pixmap = full_pixmap.scaled(
                target_w_a4,
                target_h_a4,
                aspectMode=Qt.AspectRatioMode.IgnoreAspectRatio,
                mode=Qt.TransformationMode.SmoothTransformation,
            )

            loss = max(0, int(params.get("loss", 4)))
            sw = scaled_pixmap.width()
            sh = scaled_pixmap.height()

            slices_a4 = []
            for i in range(total_pages):
                seg_x1 = int(round((i * sw) / float(total_pages)))
                seg_x2 = int(round(((i + 1) * sw) / float(total_pages)))
                if i == total_pages - 1:
                    seg_x2 = sw
                seg_w = max(1, seg_x2 - seg_x1)

                x1 = seg_x1
                x2 = seg_x2
                if i > 0:
                    x1 += loss
                if i < total_pages - 1:
                    x2 -= loss

                if x2 <= x1:
                    x1 = seg_x1
                    x2 = min(sw, seg_x1 + 1)

                ink = scaled_pixmap.copy(x1, 0, max(1, x2 - x1), sh)
                slc = QPixmap(seg_w, sh)
                slc.fill(Qt.GlobalColor.transparent)
                painter = QPainter(slc)
                paste_x = max(0, x1 - seg_x1)
                paste_x = min(paste_x, max(0, seg_w - ink.width()))
                painter.drawPixmap(paste_x, 0, ink)
                painter.end()
                slices_a4.append(slc)

            self._binding_slices_a4 = slices_a4
            self._binding_asset_id = asset_id
            self._binding_total_pages = total_pages
            self._binding_user_scale = user_scale
            self._binding_user_rot = float(params.get("rotation", 0.0))
            self._binding_page_size = page_size
            self._binding_scale = user_scale
            self._binding_ref_width_a4 = int(round(base_width_a4))

        self._show_current_binding_slice()

    def _show_current_binding_slice(self):
        import random

        if self._binding_preview_item:
            self._scene.removeItem(self._binding_preview_item)
            self._binding_preview_item = None

        if not hasattr(self, "_binding_slices_a4") or not self._binding_slices_a4:
            return
        if not self._page_item:
            return

        params = getattr(self, "binding_params", {})
        start_p = int(params.get("start_page", 0))
        end_p = int(params.get("end_page", 0))
        page = self._current_page
        if not (start_p <= page <= end_p):
            return

        idx = page - start_p
        if idx >= len(self._binding_slices_a4):
            return

        page_pos = self._page_item.pos()
        page_rect = self._page_item.boundingRect()
        page_to_a4 = RenderEngine.get_page_to_a4_scale(page_rect.width(), page_rect.height())
        if page_to_a4 <= 0:
            return

        slice_pixmap_a4 = self._binding_slices_a4[idx]
        slice_w = max(1, int(round(slice_pixmap_a4.width() / page_to_a4)))
        slice_h = max(1, int(round(slice_pixmap_a4.height() / page_to_a4)))
        slice_pixmap = slice_pixmap_a4.scaled(
            slice_w,
            slice_h,
            aspectMode=Qt.AspectRatioMode.IgnoreAspectRatio,
            mode=Qt.TransformationMode.SmoothTransformation,
        )

        item = QGraphicsPixmapItem(slice_pixmap)
        item.setZValue(999)

        margin_a4 = max(0, abs(int(params.get("margin", 15))))
        margin = int(round(RenderEngine.binding_units_on_page(page_rect.width(), page_rect.height(), margin_a4)))
        x = page_pos.x() + page_rect.width() - margin - slice_pixmap.width()
        min_x = page_pos.x()
        max_x = page_pos.x() + page_rect.width() - slice_pixmap.width()
        x = max(min_x, min(x, max_x))

        pure_center_y = page_pos.y() + (page_rect.height() - slice_pixmap.height()) / 2.0
        y_offset = int(params.get("y_offset", 0))
        if getattr(self, "_binding_last_received_y_offset", None) != y_offset:
            self._binding_y_offset = pure_center_y + y_offset
            self._binding_last_received_y_offset = y_offset
        elif not hasattr(self, "_binding_y_offset"):
            self._binding_y_offset = pure_center_y + y_offset

        displacement_a4 = float(params.get("displacement", 6.0))
        displacement = RenderEngine.binding_units_on_page(page_rect.width(), page_rect.height(), displacement_a4)
        rng = random.Random(page * 31 + 7)
        jitter_y = rng.uniform(-displacement, displacement)
        y = self._binding_y_offset + jitter_y

        item.setPos(x, y)
        item.setFlag(QGraphicsPixmapItem.GraphicsItemFlag.ItemIsMovable, True)
        item.setFlag(QGraphicsPixmapItem.GraphicsItemFlag.ItemIsSelectable, True)
        self._scene.addItem(item)
        self._binding_preview_item = item

    def _update_binding_placement(self):
        self._show_current_binding_slice()

    def get_binding_interactive_params(self) -> dict:
        if self._binding_preview_item:
            self._binding_y_offset = self._binding_preview_item.y()
        return {
            "scale": getattr(self, "_binding_scale", 1.0),
            "rotation": 0,
            "y": getattr(self, "_binding_y_offset", 0),
        }

    def clear_binding_preview(self):
        if self._binding_preview_item:
            self._scene.removeItem(self._binding_preview_item)
            self._binding_preview_item = None

        for key in (
            "_binding_slices_a4",
            "_binding_asset_id",
            "_binding_total_pages",
            "_binding_user_scale",
            "_binding_user_rot",
            "_binding_page_size",
            "_binding_ref_width_a4",
        ):
            if hasattr(self, key):
                delattr(self, key)

    def clear_canvas(self):
        self._scene.clear()
        self._page_item = None
        self._binding_preview_item = None
        self._page_stamps.clear()
        self._page_sizes.clear()
        self.undo_stack.clear()

    def wheelEvent(self, event: QWheelEvent):
        if event.modifiers() == Qt.KeyboardModifier.ControlModifier:
            delta = event.angleDelta().y()
            factor = 1.15 if delta > 0 else 1.0 / 1.15
            self._zoom_factor *= factor
            if 0.1 <= self._zoom_factor <= 10.0:
                self.scale(factor, factor)
                self.zoom_changed.emit(self._zoom_factor)
            else:
                self._zoom_factor /= factor
        else:
            super().wheelEvent(event)

    def mouseReleaseEvent(self, event):
        super().mouseReleaseEvent(event)
        if self._binding_preview_item and self._page_item:
            y = self._binding_preview_item.y()
            page = self._current_page
            rng = __import__("random").Random(page * 31 + 7)

            page_rect = self._page_item.boundingRect()
            displacement_a4 = float(getattr(self, "binding_params", {}).get("displacement", 6.0))
            displacement = RenderEngine.binding_units_on_page(page_rect.width(), page_rect.height(), displacement_a4)
            jitter_y = rng.uniform(-displacement, displacement)

            base_y = y - jitter_y
            self._binding_y_offset = base_y

            page_pos = self._page_item.pos()
            pure_center_y = page_pos.y() + (page_rect.height() - self._binding_preview_item.boundingRect().height()) / 2.0
            new_offset = int(base_y - pure_center_y)
            self._binding_last_received_y_offset = new_offset
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
        if not target:
            return

        abs_path = self._assets_manager.get_absolute_path(target["path"])
        pixmap = QPixmap(abs_path)
        item = StampItem(pixmap, asset_id)
        item.page_index = self._current_page
        scene_pos = self.mapToScene(view_pos)
        scene_pos = QPointF(scene_pos.x(), scene_pos.y())
        item.setZValue(10)
        item.setScale(self._calc_auto_scale(pixmap))

        self._page_stamps.setdefault(self._current_page, []).append(item)
        item.movement_finished.connect(self._on_stamp_modified)
        item.action_requested.connect(self._on_stamp_action)
        self.undo_stack.push(AddStampCommand(self._scene, item, scene_pos))

    def add_stamp_at_center(self, category: str, asset_id: str):
        assets = self._assets_manager.get_assets(category)
        target = next((a for a in assets if a["id"] == asset_id), None)
        if not target:
            return

        abs_path = self._assets_manager.get_absolute_path(target["path"])
        pixmap = QPixmap(abs_path)
        item = StampItem(pixmap, asset_id)
        item.page_index = self._current_page
        item.setZValue(10)

        viewport_center = self.viewport().rect().center()
        scene_center = self.mapToScene(viewport_center)
        item.setScale(self._calc_auto_scale(pixmap))

        self._page_stamps.setdefault(self._current_page, []).append(item)
        item.movement_finished.connect(self._on_stamp_modified)
        item.action_requested.connect(self._on_stamp_action)
        self.undo_stack.push(AddStampCommand(self._scene, item, scene_center))

    def _calc_auto_scale(self, pixmap: QPixmap) -> float:
        if self._page_item:
            page_w = self._page_item.boundingRect().width()
            if page_w > 0 and pixmap.width() > 0:
                target_w = page_w * 0.15
                return max(0.05, min(target_w / pixmap.width(), 5.0))
        return 0.2

    def _on_stamp_modified(self, item, states):
        self.undo_stack.push(ModifyStampCommand(item, states, states))

    def _on_stamp_action(self, item, action: str):
        if action == "bring_front":
            max_z = max((st.zValue() for st in self._page_stamps.get(self._current_page, [])), default=10)
            item.setZValue(max_z + 1)
        elif action == "send_back":
            min_z = min((st.zValue() for st in self._page_stamps.get(self._current_page, [])), default=10)
            item.setZValue(max(1, min_z - 1))
        elif action == "unify_size_all":
            self._unify_all_stamp_sizes_from_item(item)
        elif action == "delete":
            self.undo_stack.push(RemoveStampCommand(self._scene, item, self._page_stamps))

    def keyPressEvent(self, event):
        if event.key() in (Qt.Key.Key_Delete, Qt.Key.Key_Backspace):
            for item in self._scene.selectedItems():
                if isinstance(item, StampItem):
                    self.undo_stack.push(RemoveStampCommand(self._scene, item, self._page_stamps))
        super().keyPressEvent(event)

    def get_all_stamps_data(self) -> dict:
        data = {}
        for page_idx, items in self._page_stamps.items():
            page_data = []
            for item in items:
                if item.scene() == self._scene:
                    page_data.append(
                        {
                            "asset_id": item.asset_id,
                            "x": item.pos().x(),
                            "y": item.pos().y(),
                            "scale": item.scale(),
                            "rotation": item.rotation(),
                        }
                    )
            if page_data:
                data[page_idx] = page_data
        return data

    def clear_all_stamps(self):
        for items in self._page_stamps.values():
            for item in items:
                if item.scene() == self._scene:
                    self._scene.removeItem(item)
        self._page_stamps.clear()
        self.undo_stack.clear()

    def apply_stamps_data(self, stamps_dict: dict):
        self.clear_all_stamps()
        for page_idx_str, items in stamps_dict.items():
            page_idx = int(page_idx_str)
            self._page_stamps.setdefault(page_idx, [])
            for st in items:
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
    page_changed = Signal(int)
    orientation_requested = Signal(bool)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._current_page = 0
        self._total_pages = 0

        layout = QVBoxLayout(self)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.setSpacing(0)

        self.canvas_view = CanvasView()
        layout.addWidget(self.canvas_view, stretch=1)

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

        self._btn_zoom_out = QPushButton("-")
        self._btn_zoom_out.setObjectName("zoomOutBtn")
        self._btn_zoom_out.setFixedWidth(30)
        self._btn_zoom_out.setToolTip("缩小")
        self._btn_zoom_out.setStyleSheet("font-size: 16px; font-weight: 700; padding: 0px; min-height: 22px;")
        self._btn_zoom_out.clicked.connect(lambda: self._apply_zoom(1.0 / 1.15))

        self._btn_zoom_reset = QPushButton("100 %")
        self._btn_zoom_reset.setObjectName("zoomResetBtn")
        self._btn_zoom_reset.setFixedWidth(75)
        self._btn_zoom_reset.setToolTip("点击重置到100%")
        self._btn_zoom_reset.clicked.connect(self._reset_zoom)

        self._btn_zoom_in = QPushButton("+")
        self._btn_zoom_in.setObjectName("zoomInBtn")
        self._btn_zoom_in.setFixedWidth(30)
        self._btn_zoom_in.setToolTip("放大")
        self._btn_zoom_in.setStyleSheet("font-size: 16px; font-weight: 700; padding: 0px; min-height: 22px;")
        self._btn_zoom_in.clicked.connect(lambda: self._apply_zoom(1.15))

        nav_bar.addWidget(self._btn_zoom_out)
        nav_bar.addWidget(self._btn_zoom_reset)
        nav_bar.addWidget(self._btn_zoom_in)

        separator = QFrame()
        separator.setFrameShape(QFrame.Shape.VLine)
        separator.setFrameShadow(QFrame.Shadow.Sunken)
        nav_bar.addWidget(separator)

        self._page_landscape = False
        self._btn_orientation = QPushButton("▯ 纵向")
        self._btn_orientation.setFixedWidth(72)
        self._btn_orientation.setToolTip("切换当前页横向 / 纵向")
        self._btn_orientation.clicked.connect(
            lambda: self.orientation_requested.emit(not self._page_landscape)
        )
        nav_bar.addWidget(self._btn_orientation)

        nav_bar.addWidget(self._btn_prev)
        nav_bar.addWidget(self._page_spin)
        nav_bar.addWidget(self._label_total)
        nav_bar.addWidget(self._btn_next)

        self.btn_mgr = QPushButton("⚙ 管理此页")
        self.btn_mgr.setFixedWidth(90)
        self.btn_mgr.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self.btn_mgr.customContextMenuRequested.connect(self._show_page_menu)
        self.btn_mgr.clicked.connect(lambda: self._show_page_menu(QPointF(0, self.btn_mgr.height()).toPoint()))
        nav_bar.addWidget(self.btn_mgr)

        nav_bar.addStretch()
        layout.addLayout(nav_bar)

        self._update_nav_state()
        self.canvas_view.zoom_changed.connect(self._on_zoom_changed)

    def set_page_landscape(self, landscape: bool):
        self._page_landscape = bool(landscape)
        self._btn_orientation.setText("▭ 横向" if landscape else "▯ 纵向")

    def _apply_zoom(self, factor):
        self.canvas_view._zoom_factor *= factor
        if 0.1 <= self.canvas_view._zoom_factor <= 10.0:
            self.canvas_view.scale(factor, factor)
            self._on_zoom_changed(self.canvas_view._zoom_factor)
        else:
            self.canvas_view._zoom_factor /= factor

    def _on_zoom_changed(self, zoom_factor):
        self._btn_zoom_reset.setText(f"{int(zoom_factor * 100)} %")

    def _reset_zoom(self):
        if not self.canvas_view._page_item:
            return
        self.canvas_view.resetTransform()
        self.canvas_view._zoom_factor = 1.0
        self.canvas_view.fitInView(self.canvas_view._page_item, Qt.AspectRatioMode.KeepAspectRatio)
        self._on_zoom_changed(self.canvas_view._zoom_factor)

    def _show_page_menu(self, _pos):
        QMessageBox.information(self, "提示", "页面管理功能预留（需联动底层引擎）。")

    def set_total_pages(self, total: int):
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
