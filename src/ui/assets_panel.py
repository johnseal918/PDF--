"""
assets_panel.py — 左侧印章/签名素材管理面板

M2阶段完全体：
实现左侧边栏列表，支持图标动态读取缩略显示，打通本地中台缓存存取功能；
实现外部面板到本列表的真实文件拖入识别系统的注册；
支持右键调用移除指令切断数据引用和物理存储。
"""

from pathlib import Path
from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QLabel, QTabWidget, QListWidget, QListWidgetItem,
    QMenu, QMessageBox
)
from PySide6.QtCore import Qt, Signal, QMimeData, QPoint
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


class AssetsPanel(QWidget):
    """左侧素材管理面板核心体。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumWidth(210)
        self.setMaximumWidth(280)
        
        # 加载中间件业务
        self._manager = AssetsManager()

        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)

        title = QLabel("📦 素材库")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet("font-size: 14px; font-weight: bold; padding: 6px;")
        layout.addWidget(title)

        # 标签页构建
        self._tabs = QTabWidget()
        
        self._stamp_list = DroppableListWidget("stamps")
        self._tabs.addTab(self._stamp_list, "🔴 印章")
        
        self._signature_list = DroppableListWidget("signatures")
        self._tabs.addTab(self._signature_list, "✍ 签名")

        layout.addWidget(self._tabs)

        hint = QLabel("双击盖章 | 拖拽定位 | 右键管理")
        hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        hint.setStyleSheet("color: #888; font-size: 11px; padding: 4px;")
        layout.addWidget(hint)
        
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
