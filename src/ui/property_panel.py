"""
property_panel.py — 右侧属性/参数/模板操作面板（M1阶段骨架，后续分阶段扩充）

M1: 基础框架 + 文件信息展示
M3: 加入去色参数区
M5: 加入骑缝章配置区
M6: 加入模板管理区
"""

from PySide6.QtWidgets import (
    QWidget, QVBoxLayout, QHBoxLayout, QLabel, QGroupBox, QFormLayout, 
    QCheckBox, QComboBox, QSlider, QSpinBox, QPushButton, QDoubleSpinBox
)
from PySide6.QtCore import Qt, Signal
import math
from pathlib import Path


class PropertyPanel(QWidget):
    """右侧属性面板。"""

    # 信号必须定义为类属性
    decolor_params_changed = Signal(dict)
    decolor_apply_requested = Signal(dict)
    binding_params_changed = Signal(dict)
    template_action = Signal(str, str) # action: "refresh", "load", "save", "delete" -> name

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setMinimumWidth(220)
        self.setMaximumWidth(300)

        layout = QVBoxLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)

        # 标题
        title = QLabel("⚙ 属性面板")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        title.setStyleSheet("font-size: 14px; font-weight: bold; padding: 6px;")
        layout.addWidget(title)

        # ── 文件信息区 ──
        file_group = QGroupBox("📄 文件信息")
        file_layout = QFormLayout()
        self._label_filename = QLabel("未加载")
        self._label_pages = QLabel("-")
        self._label_size = QLabel("-")
        file_layout.addRow("文件名:", self._label_filename)
        file_layout.addRow("页数:", self._label_pages)
        file_layout.addRow("尺寸:", self._label_size)
        file_group.setLayout(file_layout)
        layout.addWidget(file_group)

        # ── 去色参数区（M3 阶段实装）──
        decolor_group = QGroupBox("✨ 智能增强")
        decolor_layout = QVBoxLayout()

        self.chk_enable_decolor = QCheckBox("智能增强文档")
        self.chk_enable_decolor.setChecked(True)
        self.chk_enable_decolor.toggled.connect(self._emit_decolor_params)
        decolor_layout.addWidget(self.chk_enable_decolor)

        controls = QFormLayout()
        self.slider_background_cleanup = QSlider(Qt.Orientation.Horizontal)
        self.slider_background_cleanup.setRange(0, 100)
        self.slider_background_cleanup.setValue(50)
        self.label_background_cleanup = QLabel("50 %")
        self.slider_background_cleanup.valueChanged.connect(self._emit_decolor_params)
        background_row = QHBoxLayout()
        background_row.addWidget(self.slider_background_cleanup)
        background_row.addWidget(self.label_background_cleanup)
        controls.addRow("背景清理强度:", background_row)

        self.slider_fine_line = QSlider(Qt.Orientation.Horizontal)
        self.slider_fine_line.setRange(0, 100)
        self.slider_fine_line.setValue(70)
        self.label_fine_line = QLabel("70 %")
        self.slider_fine_line.valueChanged.connect(self._emit_decolor_params)
        fine_row = QHBoxLayout()
        fine_row.addWidget(self.slider_fine_line)
        fine_row.addWidget(self.label_fine_line)
        controls.addRow("细线保留强度:", fine_row)
        decolor_layout.addLayout(controls)

        decolor_group.setLayout(decolor_layout)
        layout.addWidget(decolor_group)

        # 初始化依赖防抖与状态锁
        self._set_decolor_ui_enabled(self.chk_enable_decolor.isChecked())
        self.chk_enable_decolor.toggled.connect(self._set_decolor_ui_enabled)

        # ── 骑缝章配置区（M5 阶段填充）──
        binding_group = QGroupBox("📐 骑缝章")
        binding_layout = QFormLayout()
        
        # 总开关
        self.chk_enable_binding = QCheckBox("启用骑缝章")
        self.chk_enable_binding.toggled.connect(self._set_binding_ui_enabled)
        self.chk_enable_binding.toggled.connect(self._emit_binding_params)
        binding_layout.addRow(self.chk_enable_binding)
        
        self.combo_binding_asset = QComboBox()
        self.combo_binding_asset.addItem("无可用印章", "")
        
        self.spin_binding_start = QSpinBox()
        self.spin_binding_start.setMinimum(1)
        self.spin_binding_start.setValue(1)
        self.spin_binding_end = QSpinBox()
        self.spin_binding_end.setMinimum(1)
        self.spin_binding_end.setValue(1)
        
        box_pages = QHBoxLayout()
        box_pages.addWidget(self.spin_binding_start)
        box_pages.addWidget(QLabel("-"))
        box_pages.addWidget(self.spin_binding_end)
        
        self.spin_binding_margin = QSpinBox()
        self.spin_binding_margin.setRange(0, 100)
        self.spin_binding_margin.setValue(15)
        self.spin_binding_margin.setSuffix(" px")
        
        self.slider_binding_loss = QSlider(Qt.Orientation.Horizontal)
        self.slider_binding_loss.setRange(0, 15)
        self.slider_binding_loss.setValue(4)
        self.label_binding_loss_val = QLabel("4 px")
        self.slider_binding_loss.valueChanged.connect(
            lambda v: self.label_binding_loss_val.setText(f"{v} px"))
        
        box_loss = QHBoxLayout()
        box_loss.addWidget(self.slider_binding_loss)
        box_loss.addWidget(self.label_binding_loss_val)
        
        # 新增的细节参数
        self.spin_binding_scale = QDoubleSpinBox()
        self.spin_binding_scale.setRange(0.1, 5.0)
        self.spin_binding_scale.setSingleStep(0.1)
        self.spin_binding_scale.setValue(1.0)
        self.spin_binding_scale.setSuffix(" x")
        
        self.spin_binding_rotation = QSpinBox()
        self.spin_binding_rotation.setRange(-180, 180)
        self.spin_binding_rotation.setValue(0)
        self.spin_binding_rotation.setSuffix(" °")
        
        self.spin_binding_y = QSpinBox()
        self.spin_binding_y.setRange(-5000, 5000)
        self.spin_binding_y.setValue(0)
        self.spin_binding_y.setSuffix(" px")
        
        binding_layout.addRow("所用印章:", self.combo_binding_asset)
        binding_layout.addRow("页码区间:", box_pages)
        binding_layout.addRow("边缘缝隙:", self.spin_binding_margin)
        binding_layout.addRow("夹缝损耗:", box_loss)
        binding_layout.addRow("缩放调节:", self.spin_binding_scale)
        binding_layout.addRow("微调角度:", self.spin_binding_rotation)
        binding_layout.addRow("垂直偏移:", self.spin_binding_y)
        
        # 将参数变化绑定到发射器
        self.combo_binding_asset.currentIndexChanged.connect(self._emit_binding_params)
        self.spin_binding_start.valueChanged.connect(self._emit_binding_params)
        self.spin_binding_end.valueChanged.connect(self._emit_binding_params)
        self.spin_binding_margin.valueChanged.connect(self._emit_binding_params)
        self.slider_binding_loss.valueChanged.connect(self._emit_binding_params)
        self.spin_binding_scale.valueChanged.connect(self._emit_binding_params)
        self.spin_binding_rotation.valueChanged.connect(self._emit_binding_params)
        self.spin_binding_y.valueChanged.connect(self._emit_binding_params)

        binding_group.setLayout(binding_layout)
        layout.addWidget(binding_group)
        
        # 初始化骑缝章区域为禁用状态
        self._set_binding_ui_enabled(False)

        # ── 模板管理区（M6 阶段填充）──
        template_group = QGroupBox("📋 模板")
        template_layout = QVBoxLayout()
        
        box_tpl_top = QHBoxLayout()
        self.combo_templates = QComboBox()
        self.btn_refresh_tpl = QPushButton("刷新")
        self.btn_refresh_tpl.setToolTip("刷新模板列表")
        self.btn_refresh_tpl.setFixedWidth(56)
        box_tpl_top.addWidget(self.combo_templates)
        box_tpl_top.addWidget(self.btn_refresh_tpl)
        
        self.btn_load_tpl = QPushButton("📥 套用此模板覆盖全文")
        self.btn_save_tpl = QPushButton("💾 将当前排版保存为模板")
        self.btn_delete_tpl = QPushButton("❌ 删除选中模板")
        
        template_layout.addLayout(box_tpl_top)
        template_layout.addWidget(self.btn_load_tpl)
        template_layout.addWidget(self.btn_save_tpl)
        template_layout.addWidget(self.btn_delete_tpl)
        
        template_group.setLayout(template_layout)
        layout.addWidget(template_group)
        
        # 模板交互连接信号在 main_window 处理

        self.btn_refresh_tpl.clicked.connect(self._emit_refresh_templates)
        self.btn_load_tpl.clicked.connect(self._emit_load_template)
        self.btn_save_tpl.clicked.connect(self._emit_save_template)
        self.btn_delete_tpl.clicked.connect(self._emit_delete_template)

        # 弹性空间
        layout.addStretch()

    def update_binding_assets(self, assets_list):
        """主窗口传递素材列表以供下拉框选择: list of dict {'id':..., 'name': ...}"""
        self.combo_binding_asset.blockSignals(True)
        self.combo_binding_asset.clear()
        if not assets_list:
            self.combo_binding_asset.addItem("无可用印章", "")
        else:
            for ast in assets_list:
                self.combo_binding_asset.addItem(ast['name'], ast['id'])
        self.combo_binding_asset.blockSignals(False)
        self._emit_binding_params()

    def _emit_binding_params(self):
        asset_id = self.combo_binding_asset.currentData()
        if not asset_id:
            asset_id = ""
        enabled = self.chk_enable_binding.isChecked()
        params = {
            "preview": enabled,
            "enabled": enabled,
            "asset_id": asset_id,
            "start_page": self.spin_binding_start.value() - 1,
            "end_page": self.spin_binding_end.value() - 1,
            "margin": self.spin_binding_margin.value(),
            "loss": self.slider_binding_loss.value(),
            "scale": self.spin_binding_scale.value(),
            "rotation": self.spin_binding_rotation.value(),
            "y_offset": self.spin_binding_y.value(),
            "displacement": 6.0
        }
        self.binding_params_changed.emit(params)

    def _set_binding_ui_enabled(self, checked: bool):
        """骑缝章区域的整体启用/禁用控制"""
        self.combo_binding_asset.setEnabled(checked)
        self.spin_binding_start.setEnabled(checked)
        self.spin_binding_end.setEnabled(checked)
        self.spin_binding_margin.setEnabled(checked)
        self.slider_binding_loss.setEnabled(checked)
        self.spin_binding_scale.setEnabled(checked)
        self.spin_binding_rotation.setEnabled(checked)
        self.spin_binding_y.setEnabled(checked)

    def _set_decolor_ui_enabled(self, checked: bool):
        self.slider_background_cleanup.setEnabled(checked)
        self.slider_fine_line.setEnabled(checked)

    def _emit_decolor_params(self):
        """发送配置字典供挂载点提取处理并触发 CVEngine 运算"""
        self.label_background_cleanup.setText(f"{self.slider_background_cleanup.value()} %")
        self.label_fine_line.setText(f"{self.slider_fine_line.value()} %")
        params = self._collect_decolor_params()
        self.decolor_params_changed.emit(params)

    def _collect_decolor_params(self):
        return {
            "enabled": self.chk_enable_decolor.isChecked(),
            "background_cleanup": self.slider_background_cleanup.value(),
            "fine_line_preservation": self.slider_fine_line.value(),
        }

    def _emit_apply_decolor(self):
        # "应用灰度"是显式执行动作，应强制进入 enabled=True 状态，
        # 避免用户刚点过"取消灰度"后再次应用时仍被当成恢复原图分支。
        self.chk_enable_decolor.blockSignals(True)
        self.chk_enable_decolor.setChecked(True)
        self.chk_enable_decolor.blockSignals(False)
        self._set_decolor_ui_enabled(True)
        params = self._collect_decolor_params()
        self.decolor_params_changed.emit(params)
        self.decolor_apply_requested.emit(params)

    def _emit_cancel_decolor(self):
        self.chk_enable_decolor.blockSignals(True)
        self.chk_enable_decolor.setChecked(False)
        self.chk_enable_decolor.blockSignals(False)
        self._set_decolor_ui_enabled(False)
        params = self._collect_decolor_params()
        self.decolor_params_changed.emit(params)
        self.decolor_apply_requested.emit(params)


    def update_file_info(self, filename: str, pages: int, width: int, height: int, reset_binding_range: bool = False):
        """更新文件信息展示，并同步骑缝章页码区间边界。"""
        self._label_filename.setText(filename)
        self._label_filename.setToolTip(filename)
        self._label_pages.setText(str(pages))
        self._label_size.setText(f"{width} × {height} px")

        self.spin_binding_start.setMaximum(max(1, pages))
        self.spin_binding_end.setMaximum(max(1, pages))
        if reset_binding_range:
            self.spin_binding_start.setValue(1)
            self.spin_binding_end.setValue(max(1, pages))
        else:
            self.spin_binding_start.setValue(
                max(self.spin_binding_start.minimum(), min(self.spin_binding_start.maximum(), self.spin_binding_start.value()))
            )
            self.spin_binding_end.setValue(
                max(self.spin_binding_end.minimum(), min(self.spin_binding_end.maximum(), self.spin_binding_end.value()))
            )
        
    def _emit_refresh_templates(self):
        self.template_action.emit("refresh", "")
        
    def _emit_load_template(self):
        name = self.combo_templates.currentText()
        if name:
            self.template_action.emit("load", name)
            
    def _emit_save_template(self):
        from PySide6.QtWidgets import QInputDialog
        name, ok = QInputDialog.getText(self, "保存模板", "请输入模板名称（如: 合同预设1）:")
        if ok and name.strip():
            self.template_action.emit("save", name.strip())
            
    def _emit_delete_template(self):
        name = self.combo_templates.currentText()
        if name:
            self.template_action.emit("delete", name)

    def populate_templates(self, names: list[str]):
        self.combo_templates.clear()
        self.combo_templates.addItems(names)

    def set_decolor_params(self, params: dict, emit_signal: bool = True):
        """Apply decolor params from template/config to UI."""
        if not params:
            return

        widgets = [self.chk_enable_decolor, self.slider_background_cleanup, self.slider_fine_line]
        for w in widgets:
            w.blockSignals(True)

        enabled = bool(params.get("enabled", self.chk_enable_decolor.isChecked()))
        background_cleanup = int(params.get("background_cleanup", 50))
        fine_line = int(params.get("fine_line_preservation", 70))

        self.chk_enable_decolor.setChecked(enabled)
        self.slider_background_cleanup.setValue(max(0, min(100, background_cleanup)))
        self.slider_fine_line.setValue(max(0, min(100, fine_line)))
        self.label_background_cleanup.setText(f"{self.slider_background_cleanup.value()} %")
        self.label_fine_line.setText(f"{self.slider_fine_line.value()} %")

        for w in widgets:
            w.blockSignals(False)

        self._set_decolor_ui_enabled(self.chk_enable_decolor.isChecked())
        if emit_signal:
            self._emit_decolor_params()

    def set_binding_params(self, params: dict, emit_signal: bool = True):
        """Apply binding params from template/config to UI."""
        if not params:
            return

        widgets = [
            self.chk_enable_binding,
            self.combo_binding_asset,
            self.spin_binding_start,
            self.spin_binding_end,
            self.spin_binding_margin,
            self.slider_binding_loss,
            self.spin_binding_scale,
            self.spin_binding_rotation,
            self.spin_binding_y,
        ]
        for w in widgets:
            w.blockSignals(True)

        enabled = bool(params.get("enabled", params.get("preview", self.chk_enable_binding.isChecked())))
        self.chk_enable_binding.setChecked(enabled)

        asset_id = params.get("asset_id", "")
        if asset_id:
            asset_idx = self.combo_binding_asset.findData(asset_id)
            if asset_idx >= 0:
                self.combo_binding_asset.setCurrentIndex(asset_idx)

        start_page = int(params.get("start_page", self.spin_binding_start.value() - 1)) + 1
        end_page = int(params.get("end_page", self.spin_binding_end.value() - 1)) + 1
        self.spin_binding_start.setValue(max(self.spin_binding_start.minimum(), min(self.spin_binding_start.maximum(), start_page)))
        self.spin_binding_end.setValue(max(self.spin_binding_end.minimum(), min(self.spin_binding_end.maximum(), end_page)))
        # Backward compatibility: older templates used negative margin to mean
        # "move inward by this many pixels", so normalize to a non-negative gap.
        margin = abs(int(params.get("margin", self.spin_binding_margin.value())))
        self.spin_binding_margin.setValue(margin)
        self.slider_binding_loss.setValue(int(params.get("loss", self.slider_binding_loss.value())))
        self.spin_binding_scale.setValue(float(params.get("scale", self.spin_binding_scale.value())))
        self.spin_binding_rotation.setValue(int(params.get("rotation", self.spin_binding_rotation.value())))
        self.spin_binding_y.setValue(int(params.get("y_offset", self.spin_binding_y.value())))

        for w in widgets:
            w.blockSignals(False)

        self._set_binding_ui_enabled(self.chk_enable_binding.isChecked())
        if emit_signal:
            self._emit_binding_params()
