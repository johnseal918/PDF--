"""
assets_panel.py — 左侧印章/签名素材管理面板

M2阶段完全体：
实现左侧边栏列表，支持图标动态读取缩略显示，打通本地中台缓存存取功能；
实现外部面板到本列表的真实文件拖入识别系统的注册；
支持右键调用移除指令切断数据引用和物理存储。
"""

from pathlib import Path
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QTabWidget, QListWidget, QListWidgetItem,
    QMenu, QMessageBox, QPushButton, QSplitter
)
from PySide6.QtCore import Qt, Signal, QMimeData, QPoint, QSize
from PySide6.QtGui import QIcon, QPixmap, QDragEnterEvent, QDropEvent, QDrag

from src.core.assets_manager import AssetsManager


class DroppableListWidget(QListWidget):
    """支持从外部操作文件拖进列表，以及向外拖出印章项的自定义 ListWidget。"""
    
    file_dropped = Signal(str, str)  # 信号: category, file_path
    stamp_double_clicked = Signal(str, str) # 信号: category, asset_id

    def __init__(self, category_name: str, parent=None):
        super().__init__(parent)
        self.category_name = category_name
        self.setAcceptDrops(True)
        self.setDragEnabled(True)  # 支持向外拖拽
        self.setIconSize(__import__('PySide6').QtCore.QSize(64, 64))
        self.setSpacing(4)
        # 为图标列表形式布局打开大图查看支持
        self.setViewMode(QListWidget.ViewMode.IconMode)
        self.setResizeMode(QListWidget.ResizeMode.Adjust)
        
        # 双击 = 直接盖章到画布中央
        self.itemDoubleClicked.connect(self._on_item_double_clicked)

    def _on_item_double_clicked(self, item: QListWidgetItem):
        asset_id = item.data(Qt.ItemDataRole.UserRole)
        if asset_id:
            self.stamp_double_clicked.emit(self.category_name, asset_id)

    def startDrag(self, supportedActions):
        """重写 startDrag，将资产ID包装为 MimeData 传递给画布"""
        item = self.currentItem()
        if not item:
            return
            
        asset_id = item.data(Qt.ItemDataRole.UserRole)
        drag = QDrag(self)
        mime_data = QMimeData()
        
        # 传递自定义文本： 类别:UUID
        mime_data.setText(f"pdfseal:{self.category_name}:{asset_id}")
        drag.setMimeData(mime_data)
        
        pixmap = item.icon().pixmap(64, 64)
        drag.setPixmap(pixmap)
        drag.setHotSpot(QPoint(pixmap.width() // 2, pixmap.height() // 2))
        
        drag.exec(Qt.DropAction.CopyAction)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            urls = event.mimeData().urls()
            if urls:
                path = urls[0].toLocalFile()
                if Path(path).suffix.lower() in [".png", ".jpg", ".jpeg", ".bmp"]:
                    event.acceptProposedAction()
                    return
        event.ignore()
        
    def dragMoveEvent(self, event):
        event.acceptProposedAction()

    def dropEvent(self, event: QDropEvent):
        if event.mimeData().hasUrls():
            urls = event.mimeData().urls()
            if urls:
                path = urls[0].toLocalFile()
                self.file_dropped.emit(self.category_name, path)
                event.acceptProposedAction()


class DocumentTabsList(QListWidget):
    close_requested = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setVisible(False)
        self.setSpacing(2)
        self.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.setVerticalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        self.setMinimumHeight(120)

    def add_document(self, name: str, tooltip: str):
        item = QListWidgetItem()
        item.setToolTip(tooltip)
        item.setSizeHint(QSize(0, 34))
        self.addItem(item)

        row_widget = QWidget()
        row_layout = QHBoxLayout(row_widget)
        row_layout.setContentsMargins(6, 0, 2, 0)
        row_layout.setSpacing(2)

        label = QLabel(name)
        label.setToolTip(tooltip)
        label.setStyleSheet("font-size: 13px; padding: 2px 0;")
        label.setTextInteractionFlags(Qt.TextInteractionFlag.NoTextInteraction)
        close_btn = QPushButton("x")
        close_btn.setFixedSize(22, 22)
        close_btn.hide()
        close_btn.setToolTip("关闭此文件")
        close_btn.setStyleSheet("padding: 0px; font-weight: bold;")

        def select_row(_event=None, row_item=item):
            self.setCurrentRow(self.row(row_item))

        row_widget.mousePressEvent = select_row
        label.mousePressEvent = select_row
        row_widget.enterEvent = lambda _event, btn=close_btn: btn.show()
        row_widget.leaveEvent = lambda _event, btn=close_btn: btn.hide()
        close_btn.clicked.connect(lambda _=False, row_item=item: self.close_requested.emit(self.row(row_item)))

        row_layout.addWidget(label, 1)
        row_layout.addWidget(close_btn)
        self.setItemWidget(item, row_widget)
        self.setVisible(True)

    def remove_document(self, index: int):
        if 0 <= index < self.count():
            self.takeItem(index)
        self.setVisible(self.count() > 0)

    def request_close(self, index: int):
        if 0 <= index < self.count():
            self.close_requested.emit(index)


class AssetsPanel(QWidget):
    """左侧素材管理面板核心体。"""

    open_requested = Signal()
    export_pdf_requested = Signal()
    document_selected = Signal(int)
    document_close_requested = Signal(int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumWidth(210)
        self.setMaximumWidth(280)
        
        # 加载中间件业务
        self._manager = AssetsManager()

        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)

        shortcuts = QHBoxLayout()
        self.btn_open_file = QPushButton("打开文件")
        self.btn_export_pdf = QPushButton("导出 PDF")
        self.btn_export_pdf.setEnabled(False)
        self.btn_export_pdf.setToolTip("请先打开文件")
        self.btn_open_file.clicked.connect(self.open_requested.emit)
        self.btn_export_pdf.clicked.connect(self.export_pdf_requested.emit)
        shortcuts.addWidget(self.btn_open_file)
        shortcuts.addWidget(self.btn_export_pdf)
        layout.addLayout(shortcuts)

        self._document_tabs = DocumentTabsList()
        self._document_tabs.currentRowChanged.connect(self._on_document_selected)
        self._document_tabs.close_requested.connect(self.document_close_requested.emit)

        self._library_splitter = QSplitter(Qt.Orientation.Vertical)
        self._library_splitter.addWidget(self._document_tabs)

        asset_section = QWidget()
        asset_layout = QVBoxLayout(asset_section)
        asset_layout.setContentsMargins(0, 0, 0, 0)
        asset_layout.setSpacing(0)

        # 标签页构建
        self._tabs = QTabWidget()
        
        self._stamp_list = DroppableListWidget("stamps")
        self._tabs.addTab(self._stamp_list, "🔴 印章")
        
        self._signature_list = DroppableListWidget("signatures")
        self._tabs.addTab(self._signature_list, "✍ 签名")

        asset_layout.addWidget(self._tabs)

        hint = QLabel("双击盖章 | 拖拽定位 | 右键管理")
        hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hint.setStyleSheet("color: #888; font-size: 11px; padding: 4px;")
        asset_layout.addWidget(hint)

        self._library_splitter.addWidget(asset_section)
        self._library_splitter.setSizes([700, 360])
        layout.addWidget(self._library_splitter)
        
        # 激活信号
        self._stamp_list.file_dropped.connect(self._on_file_dropped)
        self._signature_list.file_dropped.connect(self._on_file_dropped)
        
        # 挂载右键
        self._stamp_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self._stamp_list.customContextMenuRequested.connect(lambda pos: self._show_context_menu(pos, "stamps"))
        self._signature_list.setContextMenuPolicy(Qt.ContextMenuPolicy.CustomContextMenu)
        self._signature_list.customContextMenuRequested.connect(lambda pos: self._show_context_menu(pos, "signatures"))

        # 开机刷新全量显示
        self._refresh_list("stamps")
        self._refresh_list("signatures")

    def set_export_enabled(self, enabled: bool):
        self.btn_export_pdf.setEnabled(enabled)
        self.btn_export_pdf.setToolTip("" if enabled else "请先打开文件")

    def add_document_tab(self, name: str, tooltip: str):
        self._document_tabs.add_document(name, tooltip)

    def remove_document_tab(self, index: int):
        self._document_tabs.remove_document(index)

    def set_current_document(self, index: int):
        if 0 <= index < self._document_tabs.count():
            self._document_tabs.setCurrentRow(index)

    def request_document_close(self, index: int):
        self._document_tabs.request_close(index)

    def _on_document_selected(self, index: int):
        if index >= 0:
            self.document_selected.emit(index)

    def _get_list_widget(self, category: str) -> DroppableListWidget:
        if category == "stamps":
            return self._stamp_list
        return self._signature_list

    def _refresh_list(self, category: str):
        """重载图层到前端。"""
        list_widget = self._get_list_widget(category)
        list_widget.clear()
        
        assets = self._manager.get_assets(category)
        for item in assets:
            abs_path = self._manager.get_absolute_path(item["path"])
            icon = QIcon(abs_path)
            # 配置 Item 及其内部潜藏数据
            qitem = QListWidgetItem(icon, item["name"])
            qitem.setData(Qt.ItemDataRole.UserRole, item["id"])
            list_widget.addItem(qitem)

    def _on_file_dropped(self, category: str, file_path: str):
        """响应拖入后，发送给控制器并更新界面。"""
        res = self._manager.add_asset(category, file_path)
        if res:
            self._refresh_list(category)
        else:
            QMessageBox.warning(self, "错误", "素材复制到环境库失败或发生冲突。")

    def _show_context_menu(self, pos, category: str):
        """右键菜单：重命名和删除"""
        from PySide6.QtWidgets import QInputDialog
        list_widget = self._get_list_widget(category)
        item = list_widget.itemAt(pos)
        if not item:
            return

        asset_id = item.data(Qt.ItemDataRole.UserRole)
        
        menu = QMenu(self)
        rename_action = menu.addAction("✏️ 重命名")
        delete_action = menu.addAction("❌ 删除此素材")
        action = menu.exec(list_widget.mapToGlobal(pos))
        
        if action == rename_action:
            new_name, ok = QInputDialog.getText(
                self, "重命名素材", "请输入新名称:", 
                text=item.text()
            )
            if ok and new_name.strip():
                if self._manager.rename_asset(category, asset_id, new_name.strip()):
                    self._refresh_list(category)
        elif action == delete_action:
            reply = QMessageBox.question(
                self, "移除素材", f"确定彻底移除这个{('印章' if category == 'stamps' else '签名')}记录吗？\n不可恢复。",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
            )
            if reply == QMessageBox.StandardButton.Yes:
                self._manager.remove_asset(category, asset_id)
                self._refresh_list(category)
