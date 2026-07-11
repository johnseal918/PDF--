"""
Main window for PDF Seal Master.

Supports multi-document editing via browser-like tabs.
Each tab keeps its own document model, canvas state, parameters, and undo stack.
"""

from pathlib import Path

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QAction, QDragEnterEvent, QDropEvent
from PySide6.QtWidgets import (
    QApplication,
    QDialog,
    QDialogButtonBox,
    QDoubleSpinBox,
    QFileDialog,
    QFormLayout,
    QMainWindow,
    QMessageBox,
    QProgressDialog,
    QSplitter,
    QStatusBar,
    QTabWidget,
)

from src.core.cv_processor import CVProcessor
from src.core.pdf_engine import DocumentModel, SUPPORTED_ALL
from src.core.render_engine import RenderEngine
from src.core.template_manager import TemplateManager
from src.ui.assets_panel import AssetsPanel
from src.ui.canvas_view import CanvasWidget
from src.ui.property_panel import PropertyPanel
from src.utils.image_utils import numpy_to_pil, pil_to_numpy
from src.utils.user_settings import load_user_settings, save_user_settings


class MainWindow(QMainWindow):
    APP_TITLE = "PDF Seal Master - 印章处理大师"

    def __init__(self):
        super().__init__()
        self.setWindowTitle(self.APP_TITLE)
        self.setMinimumSize(1200, 750)
        self.resize(1400, 850)
        self.setAcceptDrops(True)

        self._contexts = {}
        self._bound_undo_stack = None
        self._tpl_manager = TemplateManager()
        self._random_copy_settings = load_user_settings()
        self._pending_decolor_preview_ctx = None
        self._decolor_preview_timer = QTimer(self)
        self._decolor_preview_timer.setSingleShot(True)
        self._decolor_preview_timer.setInterval(250)
        self._decolor_preview_timer.timeout.connect(self._render_pending_decolor_preview)

        self._setup_menu_bar()
        self._setup_central_area()
        self._setup_status_bar()

        self._property_panel._emit_decolor_params()
        self._property_panel._emit_binding_params()

    # ---------------------- UI setup ----------------------
    def _setup_menu_bar(self):
        menu_bar = self.menuBar()
        file_menu = menu_bar.addMenu("文件(&F)")

        open_action = QAction("打开文件(&O)...", self)
        open_action.setShortcut("Ctrl+O")
        open_action.triggered.connect(self._on_open_file)
        file_menu.addAction(open_action)

        file_menu.addSeparator()

        export_pdf_action = QAction("导出为 PDF(&P)...", self)
        export_pdf_action.setShortcut("Ctrl+Shift+S")
        export_pdf_action.triggered.connect(self._on_export_pdf)
        file_menu.addAction(export_pdf_action)

        export_img_action = QAction("导出为图片(&I)...", self)
        export_img_action.triggered.connect(self._on_export_image)
        file_menu.addAction(export_img_action)

        file_menu.addSeparator()
        close_tab_action = QAction("关闭当前标签(&W)", self)
        close_tab_action.setShortcut("Ctrl+W")
        close_tab_action.triggered.connect(self._close_current_tab)
        file_menu.addAction(close_tab_action)

        file_menu.addSeparator()
        exit_action = QAction("退出(&X)", self)
        exit_action.setShortcut("Ctrl+Q")
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

        edit_menu = menu_bar.addMenu("编辑(&E)")
        self.undo_action = QAction("撤销(&Z)", self)
        self.undo_action.setShortcut("Ctrl+Z")
        self.undo_action.setEnabled(False)
        self.undo_action.triggered.connect(self._on_undo)
        edit_menu.addAction(self.undo_action)

        self.redo_action = QAction("重做(&Y)", self)
        self.redo_action.setShortcut("Ctrl+Y")
        self.redo_action.setEnabled(False)
        self.redo_action.triggered.connect(self._on_redo)
        edit_menu.addAction(self.redo_action)

        edit_menu.addSeparator()
        random_copy_action = QAction("随机复制设置...", self)
        random_copy_action.triggered.connect(self._on_random_copy_settings)
        edit_menu.addAction(random_copy_action)

        help_menu = menu_bar.addMenu("帮助(&H)")
        about_action = QAction("关于(&A)", self)
        about_action.triggered.connect(self._on_about)
        help_menu.addAction(about_action)

    def _setup_central_area(self):
        splitter = QSplitter(Qt.Orientation.Horizontal)

        self._assets_panel = AssetsPanel()
        splitter.addWidget(self._assets_panel)

        self._doc_tabs = QTabWidget()
        self._doc_tabs.setTabsClosable(False)
        self._doc_tabs.setMovable(False)
        self._doc_tabs.setDocumentMode(True)
        self._doc_tabs.tabBar().hide()
        self._doc_tabs.currentChanged.connect(self._on_tab_changed)
        self._doc_tabs.tabCloseRequested.connect(self._on_tab_close_requested)
        splitter.addWidget(self._doc_tabs)

        self._property_panel = PropertyPanel()
        self._property_panel.decolor_params_changed.connect(self._on_decolor_params_changed)
        self._property_panel.decolor_apply_requested.connect(self._apply_cv_pipeline)
        self._property_panel.binding_params_changed.connect(self._on_binding_params_changed)
        self._property_panel.template_action.connect(self._on_template_action)
        splitter.addWidget(self._property_panel)

        self._assets_panel._stamp_list.file_dropped.connect(self._sync_binding_assets)
        self._assets_panel._signature_list.file_dropped.connect(self._sync_binding_assets)
        self._sync_binding_assets()
        self._on_template_action("refresh", "")

        self._assets_panel._stamp_list.stamp_double_clicked.connect(self._on_stamp_double_clicked)
        self._assets_panel._signature_list.stamp_double_clicked.connect(self._on_stamp_double_clicked)
        self._assets_panel.open_requested.connect(self._on_open_file)
        self._assets_panel.export_pdf_requested.connect(self._on_export_pdf)
        self._assets_panel.document_selected.connect(self._doc_tabs.setCurrentIndex)
        self._assets_panel.document_close_requested.connect(self._on_tab_close_requested)

        splitter.setSizes([220, 860, 280])
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setStretchFactor(2, 0)
        self.setCentralWidget(splitter)

    def _setup_status_bar(self):
        self._status_bar = QStatusBar()
        # Keep status API available, but remove the visual bar area entirely.
        self._status_bar.setSizeGripEnabled(False)
        self._status_bar.setContentsMargins(0, 0, 0, 0)
        self._status_bar.setStyleSheet(
            "QStatusBar { border: 0; margin: 0; padding: 0; min-height: 0px; max-height: 0px; }"
        )
        self._status_bar.setFixedHeight(0)
        self._status_bar.setVisible(False)
        self.setStatusBar(self._status_bar)
        self._status_bar.showMessage("就绪 - 可同时打开多个文件（标签页）")

    # ---------------------- context helpers ----------------------
    def _current_ctx(self):
        widget = self._doc_tabs.currentWidget()
        if widget is None:
            return None
        return self._contexts.get(widget)

    def _bind_undo_stack(self, undo_stack):
        if self._bound_undo_stack is undo_stack:
            self._update_undo_redo_enabled()
            return
        if self._bound_undo_stack is not None:
            try:
                self._bound_undo_stack.canUndoChanged.disconnect(self.undo_action.setEnabled)
            except Exception:
                pass
            try:
                self._bound_undo_stack.canRedoChanged.disconnect(self.redo_action.setEnabled)
            except Exception:
                pass
        self._bound_undo_stack = undo_stack
        if undo_stack is None:
            self.undo_action.setEnabled(False)
            self.redo_action.setEnabled(False)
            return
        undo_stack.canUndoChanged.connect(self.undo_action.setEnabled)
        undo_stack.canRedoChanged.connect(self.redo_action.setEnabled)
        self.undo_action.setEnabled(undo_stack.canUndo())
        self.redo_action.setEnabled(undo_stack.canRedo())

    def _update_undo_redo_enabled(self):
        ctx = self._current_ctx()
        if not ctx:
            self.undo_action.setEnabled(False)
            self.redo_action.setEnabled(False)
            return
        stack = ctx["canvas_widget"].canvas_view.undo_stack
        self.undo_action.setEnabled(stack.canUndo())
        self.redo_action.setEnabled(stack.canRedo())

    def _read_panel_decolor_params(self):
        return {
            "enabled": self._property_panel.chk_enable_decolor.isChecked(),
            "background_cleanup": self._property_panel.slider_background_cleanup.value(),
            "fine_line_preservation": self._property_panel.slider_fine_line.value(),
        }

    def _read_panel_binding_params(self):
        asset_id = self._property_panel.combo_binding_asset.currentData() or ""
        enabled = self._property_panel.chk_enable_binding.isChecked()
        return {
            "preview": enabled,
            "enabled": enabled,
            "asset_id": asset_id,
            "start_page": self._property_panel.spin_binding_start.value() - 1,
            "end_page": self._property_panel.spin_binding_end.value() - 1,
            "margin": self._property_panel.spin_binding_margin.value(),
            "loss": self._property_panel.slider_binding_loss.value(),
            "scale": self._property_panel.spin_binding_scale.value(),
            "rotation": self._property_panel.spin_binding_rotation.value(),
            "y_offset": self._property_panel.spin_binding_y.value(),
            "displacement": 6.0,
        }

    def _normalize_binding_params(self, params: dict | None, page_count: int, force_full_range: bool = False) -> dict:
        """Keep binding params valid for the current document and migrate legacy values."""
        normalized = dict(params or {})
        enabled = bool(normalized.get("enabled", normalized.get("preview", False)))
        normalized["enabled"] = enabled
        normalized["preview"] = enabled
        normalized["asset_id"] = normalized.get("asset_id", "") or ""
        normalized["margin"] = max(0, abs(int(normalized.get("margin", 15))))
        normalized["loss"] = max(0, int(normalized.get("loss", 4)))
        normalized["scale"] = float(normalized.get("scale", 1.0))
        normalized["rotation"] = int(normalized.get("rotation", 0))
        normalized["y_offset"] = int(normalized.get("y_offset", 0))
        normalized["displacement"] = float(normalized.get("displacement", 6.0))

        if page_count <= 0:
            normalized["start_page"] = 0
            normalized["end_page"] = 0
            return normalized

        if force_full_range and page_count >= 2:
            normalized["start_page"] = 0
            normalized["end_page"] = page_count - 1
            return normalized

        start_page = int(normalized.get("start_page", 0))
        end_page = int(normalized.get("end_page", page_count - 1))
        start_page = max(0, min(start_page, page_count - 1))
        end_page = max(0, min(end_page, page_count - 1))
        if end_page < start_page:
            start_page, end_page = end_page, start_page

        normalized["start_page"] = start_page
        normalized["end_page"] = end_page
        return normalized

    def _decolor_signature(self, params: dict):
        """Build a stable signature for lazy per-page CV cache."""
        return (
            bool(params.get("enabled")),
            int(params.get("background_cleanup", 50)),
            int(params.get("fine_line_preservation", 70)),
        )

    def _invalidate_render_cache(self, ctx: dict):
        ctx["render_sig"] = None
        ctx["rendered_pages"] = set()
        ctx["prefetch_pending"] = False

    def _schedule_decolor_preview_render(self, ctx: dict):
        self._pending_decolor_preview_ctx = ctx
        self._decolor_preview_timer.start()

    def _render_pending_decolor_preview(self):
        ctx = self._pending_decolor_preview_ctx
        self._pending_decolor_preview_ctx = None
        if not ctx or ctx not in self._contexts.values():
            return
        if ctx is not self._current_ctx():
            return
        current_page = ctx["canvas_widget"].get_current_page()
        self._render_ctx_page(ctx, current_page)

    # ---------------------- tab/document lifecycle ----------------------
    def _open_document_as_tab(self, file_path: str):
        path = Path(file_path)
        if path.suffix.lower() not in SUPPORTED_ALL:
            QMessageBox.warning(self, "不支持的格式", f"无法打开文件:\n{file_path}")
            return

        doc_model = DocumentModel()
        if not doc_model.load(file_path):
            QMessageBox.warning(self, "加载失败", f"无法加载文件:\n{file_path}")
            return

        canvas_widget = CanvasWidget()
        canvas_widget.set_total_pages(doc_model.page_count)

        initial_binding_params = self._normalize_binding_params(
            self._read_panel_binding_params(),
            doc_model.page_count,
            force_full_range=True,
        )

        ctx = {
            "file_path": file_path,
            "doc_model": doc_model,
            "canvas_widget": canvas_widget,
            "decolor_params": self._read_panel_decolor_params(),
            "binding_params": initial_binding_params,
            "render_sig": None,
            "rendered_pages": set(),
            "prefetch_pending": False,
        }

        canvas_widget.page_changed.connect(lambda idx, c=ctx: self._on_page_changed(c, idx))
        canvas_widget.orientation_requested.connect(lambda landscape, c=ctx: self._on_orientation_requested(c, landscape))
        canvas_widget.canvas_view.binding_moved.connect(lambda y, c=ctx: self._on_binding_moved(c, y))
        canvas_widget.canvas_view.stamp_size_unified.connect(lambda w, c=ctx: self._on_stamp_size_unified(c, w))
        canvas_widget.canvas_view.same_stamp_size_unified.connect(self._on_same_stamp_size_unified)
        canvas_widget.canvas_view.copy_stamp_to_document_requested.connect(
            lambda item, options, c=ctx: self._on_copy_stamp_to_document(c, item, options)
        )
        canvas_widget.canvas_view.copy_stamp_to_open_documents_requested.connect(
            lambda spec, options, c=ctx: self._on_copy_stamp_to_open_documents(c, spec, options)
        )
        canvas_widget.canvas_view.random_copy_settings_changed.connect(self._on_random_copy_settings_changed)
        canvas_widget.canvas_view.set_random_copy_settings(self._random_copy_settings)

        self._render_ctx_page(ctx, 0)

        tab_index = self._doc_tabs.addTab(canvas_widget, path.name)
        self._doc_tabs.setTabToolTip(tab_index, file_path)
        self._assets_panel.add_document_tab(path.name, file_path)
        self._contexts[canvas_widget] = ctx
        self._doc_tabs.setCurrentIndex(tab_index)
        self._on_tab_changed(tab_index)
        self._status_bar.showMessage(f"已打开: {path.name} ({doc_model.page_count} 页)", 3000)

    def _on_tab_changed(self, _index: int):
        ctx = self._current_ctx()
        self._assets_panel.set_current_document(_index)
        if not ctx:
            self._bind_undo_stack(None)
            self.setWindowTitle(self.APP_TITLE)
            self._property_panel.update_file_info("未加载", 0, 0, 0)
            self._assets_panel.set_export_enabled(False)
            return

        self._assets_panel.set_export_enabled(True)

        self._bind_undo_stack(ctx["canvas_widget"].canvas_view.undo_stack)

        model = ctx["doc_model"]
        page_idx = ctx["canvas_widget"].get_current_page()
        page_img = model.get_page(page_idx)
        if page_img:
            self._property_panel.update_file_info(
                filename=Path(ctx["file_path"]).name,
                pages=model.page_count,
                width=page_img.width,
                height=page_img.height,
                reset_binding_range=False,
            )
        self._property_panel.set_decolor_params(ctx["decolor_params"], emit_signal=False)
        normalized_binding = self._normalize_binding_params(ctx["binding_params"], model.page_count)
        ctx["binding_params"] = normalized_binding
        self._property_panel.set_binding_params(normalized_binding, emit_signal=False)
        self._show_ctx_page(ctx, page_idx)
        self.setWindowTitle(f"{self.APP_TITLE} - {Path(ctx['file_path']).name}")

    def _on_tab_close_requested(self, index: int):
        widget = self._doc_tabs.widget(index)
        if widget is None:
            return
        ctx = self._contexts.pop(widget, None)
        self._assets_panel.remove_document_tab(index)
        self._doc_tabs.removeTab(index)
        widget.deleteLater()
        if ctx:
            self._status_bar.showMessage(f"已关闭: {Path(ctx['file_path']).name}", 2000)
        if self._doc_tabs.count() == 0:
            self._bind_undo_stack(None)
            self.setWindowTitle(self.APP_TITLE)
            self._property_panel.update_file_info("未加载", 0, 0, 0)
            self._assets_panel.set_export_enabled(False)

    def _close_current_tab(self):
        idx = self._doc_tabs.currentIndex()
        if idx >= 0:
            self._on_tab_close_requested(idx)

    # ---------------------- rendering helpers ----------------------
    def _show_ctx_page(self, ctx: dict, page_index: int):
        page_img = ctx["doc_model"].get_page(page_index)
        if page_img:
            ctx["canvas_widget"].set_page_landscape(page_img.width > page_img.height)
            ctx["canvas_widget"].canvas_view.set_page_image(page_img, page_index)
            self._update_binding_preview_for_ctx(ctx)
            if ctx is self._current_ctx():
                self._property_panel.update_file_info(
                    Path(ctx["file_path"]).name,
                    ctx["doc_model"].page_count,
                    page_img.width,
                    page_img.height,
                )

    def _render_ctx_page(self, ctx: dict, page_index: int):
        params = ctx["decolor_params"]
        model = ctx["doc_model"]

        if not model.page_count:
            return
        if page_index < 0 or page_index >= model.page_count:
            return

        orig_pil = model.get_original_page(page_index)
        if not orig_pil:
            return

        if not params.get("enabled"):
            model.reset_page(page_index)
            self._show_ctx_page(ctx, page_index)
            return

        sig = self._decolor_signature(params)
        if ctx.get("render_sig") != sig:
            ctx["render_sig"] = sig
            ctx["rendered_pages"] = set()

        if page_index in ctx["rendered_pages"]:
            self._show_ctx_page(ctx, page_index)
            return

        cv_img = pil_to_numpy(orig_pil)
        cv_img = CVProcessor.enhance_document(cv_img, params.get("background_cleanup", 50), params.get("fine_line_preservation", 70))
        result_pil = numpy_to_pil(cv_img)
        model.set_page(page_index, result_pil)
        ctx["rendered_pages"].add(page_index)
        self._show_ctx_page(ctx, page_index)

        # Warm up next page in next event-loop turn to reduce click-to-render delay.
        next_page = page_index + 1
        if next_page < model.page_count and not ctx.get("prefetch_pending"):
            ctx["prefetch_pending"] = True
            QTimer.singleShot(0, lambda c=ctx, p=next_page, s=sig: self._prefetch_page(c, p, s))

    def _prefetch_page(self, ctx: dict, page_index: int, expected_sig):
        ctx["prefetch_pending"] = False
        model = ctx["doc_model"]
        params = ctx["decolor_params"]
        if not params.get("enabled"):
            return
        if page_index < 0 or page_index >= model.page_count:
            return

        sig = self._decolor_signature(params)
        if sig != expected_sig or ctx.get("render_sig") != expected_sig:
            return
        if page_index in ctx["rendered_pages"]:
            return

        orig_pil = model.get_original_page(page_index)
        if not orig_pil:
            return

        cv_img = pil_to_numpy(orig_pil)
        cv_img = CVProcessor.enhance_document(cv_img, params.get("background_cleanup", 50), params.get("fine_line_preservation", 70))
        model.set_page(page_index, numpy_to_pil(cv_img))
        ctx["rendered_pages"].add(page_index)

    # ---------------------- interaction handlers ----------------------
    def _sync_binding_assets(self, *args):
        assets = self._assets_panel._manager.get_assets("stamps")
        self._property_panel.update_binding_assets(assets)

    def _on_binding_moved(self, ctx: dict, y_offset: int):
        if ctx is self._current_ctx():
            self._property_panel.spin_binding_y.setValue(y_offset)

    def _on_page_changed(self, ctx: dict, page_index: int):
        self._show_ctx_page(ctx, page_index)
        if ctx is self._current_ctx():
            self._status_bar.showMessage(f"第 {page_index + 1} / {ctx['doc_model'].page_count} 页")

    def _on_orientation_requested(self, ctx: dict, landscape: bool):
        page_index = ctx["canvas_widget"].get_current_page()
        old_page = ctx["doc_model"].get_page(page_index)
        if not old_page or not ctx["doc_model"].set_page_landscape(page_index, landscape):
            return

        new_page = ctx["doc_model"].get_page(page_index)
        ctx["canvas_widget"].canvas_view.remap_page_stamps(
            page_index,
            new_page.width / old_page.width,
            new_page.height / old_page.height,
        )
        ctx["rendered_pages"].discard(page_index)
        self._render_ctx_page(ctx, page_index)

    def _on_stamp_size_unified(self, ctx: dict, target_width_a4: float):
        if not ctx:
            return

        binding_params = dict(ctx.get("binding_params", {}))
        binding_params["target_width_a4"] = max(1.0, float(target_width_a4))
        binding_params["scale"] = 1.0
        normalized = self._normalize_binding_params(binding_params, ctx["doc_model"].page_count)
        ctx["binding_params"] = normalized

        if ctx is self._current_ctx():
            self._property_panel.set_binding_params(normalized, emit_signal=False)
            self._status_bar.showMessage("已统一所有印章与骑缝章尺寸", 3000)

        self._update_binding_preview_for_ctx(ctx)

    def _on_same_stamp_size_unified(self, asset_id: str, target_width_a4: float):
        changed = 0
        for ctx in self._contexts.values():
            changed += ctx["canvas_widget"].canvas_view.unify_asset_size(asset_id, target_width_a4)
        self._status_bar.showMessage(f"已同步所有打开文档中的同款印章：{changed} 个", 3000)

    def _sync_ctx_page_sizes(self, ctx: dict):
        model = ctx["doc_model"]
        canvas_view = ctx["canvas_widget"].canvas_view
        for page_idx in range(model.page_count):
            page = model.get_page(page_idx)
            if page:
                canvas_view._page_sizes[page_idx] = (page.width, page.height)

    def _on_copy_stamp_to_document(self, ctx: dict, item, options: dict):
        self._sync_ctx_page_sizes(ctx)
        pages = range(ctx["doc_model"].page_count)
        result = ctx["canvas_widget"].canvas_view.copy_stamp_to_missing_pages(item, pages, options)
        if result["added"] == 0:
            QMessageBox.information(self, "提示", "当前文档没有可复制的缺失页面。")
        self._status_bar.showMessage(
            f"已复制到当前文档：新增 {result['added']} 个，跳过 {result['skipped']} 页",
            3000,
        )

    def _on_copy_stamp_to_open_documents(self, source_ctx: dict, spec: dict, options: dict):
        total_added = 0
        total_skipped = 0
        for ctx in self._contexts.values():
            if ctx is source_ctx:
                continue
            self._sync_ctx_page_sizes(ctx)
            pages = range(ctx["doc_model"].page_count)
            result = ctx["canvas_widget"].canvas_view.copy_stamp_spec_to_missing_pages(spec, pages, options)
            total_added += result["added"]
            total_skipped += result["skipped"]
        if total_added == 0:
            QMessageBox.information(self, "提示", "其余已打开文档没有可复制的缺失页面。")
        self._status_bar.showMessage(
            f"已复制到其余文档：新增 {total_added} 个，跳过 {total_skipped} 页",
            3000,
        )

    def _on_random_copy_settings_changed(self, settings: dict):
        self._random_copy_settings.update(settings)
        save_user_settings(self._random_copy_settings)
        for ctx in self._contexts.values():
            ctx["canvas_widget"].canvas_view.set_random_copy_settings(self._random_copy_settings)

    def _on_binding_params_changed(self, params: dict):
        ctx = self._current_ctx()
        if not ctx:
            return
        params = self._normalize_binding_params(params, ctx["doc_model"].page_count)
        if params.get("enabled") and ctx["doc_model"].page_count >= 2:
            start_page = int(params.get("start_page", 0))
            end_page = int(params.get("end_page", 0))
            if (end_page - start_page + 1) < 2:
                params = params.copy()
                params["start_page"] = 0
                params["end_page"] = ctx["doc_model"].page_count - 1
                self._property_panel.set_binding_params(params, emit_signal=False)
        ctx["binding_params"] = params
        self._update_binding_preview_for_ctx(ctx)

    def _on_decolor_params_changed(self, params: dict):
        ctx = self._current_ctx()
        if not ctx:
            return
        ctx["decolor_params"] = params
        self._invalidate_render_cache(ctx)
        if params.get("enabled"):
            self._schedule_decolor_preview_render(ctx)
            return

        current_page = ctx["canvas_widget"].get_current_page()
        ctx["doc_model"].reset_page(current_page)
        self._show_ctx_page(ctx, current_page)

    def _apply_cv_pipeline(self, params: dict):
        ctx = self._current_ctx()
        if not ctx:
            return

        ctx["decolor_params"] = params
        model = ctx["doc_model"]
        total = model.page_count
        if total <= 0:
            return

        applying = bool(params.get("enabled"))
        title = "批量灰度处理" if applying else "恢复原图"
        text = "正在对全文件执行灰度渲染..." if applying else "正在恢复全文件原图..."
        progress = QProgressDialog(text, "取消", 0, total, self)
        progress.setWindowTitle(title)
        progress.setWindowModality(Qt.WindowModality.WindowModal)
        progress.setMinimumDuration(0)
        progress.show()

        for i in range(total):
            if progress.wasCanceled():
                break
            if applying:
                orig_pil = model.get_original_page(i)
                if orig_pil:
                    cv_img = pil_to_numpy(orig_pil)
                    cv_img = CVProcessor.enhance_document(cv_img, params.get("background_cleanup", 50), params.get("fine_line_preservation", 70))
                    model.set_page(i, numpy_to_pil(cv_img))
            else:
                model.reset_page(i)
            progress.setValue(i + 1)
            QApplication.processEvents()

        progress.close()
        if progress.wasCanceled():
            self._status_bar.showMessage("灰度处理已取消", 3000)
        else:
            self._status_bar.showMessage("全文件灰度处理完成" if applying else "已恢复全文件原图", 4000)

        self._invalidate_render_cache(ctx)
        if applying:
            ctx["render_sig"] = self._decolor_signature(params)
            ctx["rendered_pages"] = set(range(total))
        else:
            ctx["render_sig"] = None
            ctx["rendered_pages"] = set()

        current_page = ctx["canvas_widget"].get_current_page()
        self._show_ctx_page(ctx, current_page)

    def _update_binding_preview_for_ctx(self, ctx: dict):
        params = ctx["binding_params"]
        canvas_view = ctx["canvas_widget"].canvas_view
        if not params or not params.get("preview") or not params.get("asset_id"):
            canvas_view.clear_binding_preview()
            return

        start_p = params["start_page"]
        end_p = params["end_page"]
        if start_p > end_p or (end_p - start_p + 1) < 2:
            canvas_view.clear_binding_preview()
            return

        assets = self._assets_panel._manager.get_assets("stamps")
        target = next((a for a in assets if a["id"] == params["asset_id"]), None)
        if not target:
            canvas_view.clear_binding_preview()
            return

        abs_path = self._assets_panel._manager.get_absolute_path(target["path"])
        canvas_view.set_binding_preview(params["asset_id"], abs_path, params)

    def _on_stamp_double_clicked(self, category: str, asset_id: str):
        ctx = self._current_ctx()
        if not ctx:
            QMessageBox.information(self, "提示", "请先打开一个文件。")
            return
        if ctx["doc_model"].page_count == 0:
            QMessageBox.information(self, "提示", "请先加载一个文件再盖章。")
            return
        ctx["canvas_widget"].canvas_view.add_stamp_at_center(category, asset_id)
        self._status_bar.showMessage(
            f"已盖章到第 {ctx['canvas_widget'].get_current_page() + 1} 页",
            3000,
        )

    # ---------------------- template actions ----------------------
    def _on_template_action(self, action: str, value: str):
        if action == "refresh":
            self._property_panel.populate_templates(self._tpl_manager.list_templates())
            return

        if action == "delete":
            self._tpl_manager.delete_template(value)
            self._on_template_action("refresh", "")
            return

        ctx = self._current_ctx()
        if not ctx:
            QMessageBox.information(self, "提示", "请先打开一个文件。")
            return

        if action == "save":
            stamps_data = ctx["canvas_widget"].canvas_view.get_all_stamps_data()
            if self._tpl_manager.save_template(value, ctx["decolor_params"], ctx["binding_params"], stamps_data):
                self._status_bar.showMessage(f"模板 '{value}' 保存成功", 3000)
                self._on_template_action("refresh", "")
            else:
                QMessageBox.warning(self, "失败", "模板保存失败。")
            return

        if action == "load":
            data = self._tpl_manager.load_template(value)
            if not data:
                QMessageBox.warning(self, "失败", "模板加载失败。")
                return
            if "stamps" in data:
                ctx["canvas_widget"].canvas_view.apply_stamps_data(data["stamps"])
            if "decolor_params" in data:
                self._property_panel.set_decolor_params(data["decolor_params"], emit_signal=True)
            if "binding_params" in data:
                binding_params = self._normalize_binding_params(
                    data["binding_params"],
                    ctx["doc_model"].page_count,
                    force_full_range=True,
                )
                self._property_panel.set_binding_params(binding_params, emit_signal=True)
            self._status_bar.showMessage(f"模板 '{value}' 已加载", 3000)

    # ---------------------- menu actions ----------------------
    def _on_open_file(self):
        filter_str = (
            "支持的文件 (*.pdf *.png *.jpg *.jpeg *.bmp *.tiff *.tif);;"
            "PDF 文件 (*.pdf);;"
            "图片文件 (*.png *.jpg *.jpeg *.bmp *.tiff *.tif)"
        )
        file_paths, _ = QFileDialog.getOpenFileNames(self, "选择文件（可多选）", "", filter_str)
        for fp in file_paths:
            self._open_document_as_tab(fp)

    def _on_export_pdf(self):
        ctx = self._current_ctx()
        if not ctx or ctx["doc_model"].page_count == 0:
            QMessageBox.information(self, "提示", "请先打开一个文件。")
            return

        model = ctx["doc_model"]
        canvas = ctx["canvas_widget"]
        try:
            default_name = f"{Path(model.source_path).stem}-盖章.pdf"
        except Exception:
            default_name = "导出.pdf"

        file_path, _ = QFileDialog.getSaveFileName(self, "导出 PDF", default_name, "PDF 文件 (*.pdf)")
        if not file_path:
            return

        progress = QProgressDialog("正在进行底层合成...", "取消", 0, model.page_count, self)
        progress.setWindowModality(Qt.WindowModality.WindowModal)
        progress.show()

        def update_progress(current, total):
            progress.setValue(current)
            QApplication.processEvents()

        binding = ctx["binding_params"].copy()
        interact = canvas.canvas_view.get_binding_interactive_params()
        if interact:
            binding["interactive"] = interact

        try:
            images = RenderEngine.synthesize_export(
                model,
                canvas.canvas_view.get_all_stamps_data(),
                binding,
                self._assets_panel._manager,
                decolor_params=ctx["decolor_params"],
                progress_callback=update_progress,
            )
            if not progress.wasCanceled():
                progress.setLabelText("正在写入 PDF 文件...")
                QApplication.processEvents()
                DocumentModel.export_pdf_from_images(images, file_path)
                self._status_bar.showMessage(f"已导出: {file_path}", 5000)
            else:
                self._status_bar.showMessage("导出已取消", 3000)
        except Exception as e:
            QMessageBox.critical(self, "导出错误", f"发生报错:\n{e}")
        finally:
            progress.close()

    def _on_export_image(self):
        ctx = self._current_ctx()
        if not ctx or ctx["doc_model"].page_count == 0:
            QMessageBox.information(self, "提示", "请先打开一个文件。")
            return

        model = ctx["doc_model"]
        canvas = ctx["canvas_widget"]
        try:
            default_name = f"{Path(model.source_path).stem}-盖章.png"
        except Exception:
            default_name = "导出.png"

        file_path, _ = QFileDialog.getSaveFileName(
            self,
            "导出图片",
            default_name,
            "PNG 文件 (*.png);;JPEG 文件 (*.jpg)",
        )
        if not file_path:
            return

        current_page = canvas.get_current_page()
        QApplication.setOverrideCursor(Qt.CursorShape.WaitCursor)
        binding = ctx["binding_params"].copy()
        interact = canvas.canvas_view.get_binding_interactive_params()
        if interact:
            binding["interactive"] = interact
        try:
            images = RenderEngine.synthesize_export(
                model,
                canvas.canvas_view.get_all_stamps_data(),
                binding,
                self._assets_panel._manager,
                decolor_params=ctx["decolor_params"],
            )
            if current_page < len(images):
                images[current_page].save(file_path)
                self._status_bar.showMessage(f"已导出第 {current_page + 1} 页: {file_path}", 5000)
        finally:
            QApplication.restoreOverrideCursor()

    def _on_undo(self):
        ctx = self._current_ctx()
        if not ctx:
            return
        ctx["canvas_widget"].canvas_view.undo_stack.undo()
        self._update_undo_redo_enabled()

    def _on_redo(self):
        ctx = self._current_ctx()
        if not ctx:
            return
        ctx["canvas_widget"].canvas_view.undo_stack.redo()
        self._update_undo_redo_enabled()

    def _on_random_copy_settings(self):
        dialog = QDialog(self)
        dialog.setWindowTitle("随机复制设置")
        layout = QFormLayout(dialog)

        angle_spin = QDoubleSpinBox(dialog)
        angle_spin.setRange(0.0, 15.0)
        angle_spin.setDecimals(1)
        angle_spin.setSuffix(" °")
        angle_spin.setValue(float(self._random_copy_settings.get("copy_random_angle_range", 3.0)))

        position_spin = QDoubleSpinBox(dialog)
        position_spin.setRange(0.0, 30.0)
        position_spin.setDecimals(1)
        position_spin.setSuffix(" mm")
        position_spin.setValue(float(self._random_copy_settings.get("copy_random_position_mm", 5.0)))

        layout.addRow("随机角度范围:", angle_spin)
        layout.addRow("随机位置范围:", position_spin)

        buttons = QDialogButtonBox(QDialogButtonBox.StandardButton.Ok | QDialogButtonBox.StandardButton.Cancel)
        buttons.accepted.connect(dialog.accept)
        buttons.rejected.connect(dialog.reject)
        layout.addWidget(buttons)

        if dialog.exec() != QDialog.DialogCode.Accepted:
            return

        self._random_copy_settings["copy_random_angle_range"] = angle_spin.value()
        self._random_copy_settings["copy_random_position_mm"] = position_spin.value()
        save_user_settings(self._random_copy_settings)
        for ctx in self._contexts.values():
            ctx["canvas_widget"].canvas_view.set_random_copy_settings(self._random_copy_settings)
        self._status_bar.showMessage("随机复制设置已保存", 3000)

    def _on_about(self):
        QMessageBox.about(
            self,
            "关于 PDF Seal Master",
            "<h2>PDF Seal Master</h2>"
            "<p><b>印章处理大师 v1.0</b></p>"
            "<p>支持多标签打开多个文件，分别编辑、分别导出。</p>",
        )

    # ---------------------- drag/drop ----------------------
    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            for url in event.mimeData().urls():
                file_path = url.toLocalFile()
                if file_path and Path(file_path).suffix.lower() in SUPPORTED_ALL:
                    event.acceptProposedAction()
                    self._status_bar.showMessage(f"松开以打开: {Path(file_path).name}")
                    return
        event.ignore()

    def dragLeaveEvent(self, event):
        self._status_bar.showMessage("就绪 - 可同时打开多个文件（标签页）")

    def dropEvent(self, event: QDropEvent):
        if not event.mimeData().hasUrls():
            return
        opened = 0
        for url in event.mimeData().urls():
            file_path = url.toLocalFile()
            if file_path and Path(file_path).suffix.lower() in SUPPORTED_ALL:
                self._open_document_as_tab(file_path)
                opened += 1
        if opened:
            event.acceptProposedAction()
