"""
template_manager.py — 全域参数与印章排布模板管理器
将当前内存中漂浮的 QGraphicsItem 状态（坐标、缩放、选型）以及控制面板参数序列化为 JSON 供下次秒级加载还原。
"""

import os
import json
from pathlib import Path

class TemplateManager:
    """管理和操作存储在 config/templates/ 的模板。"""
    
    def __init__(self):
        self.templates_dir = Path("config/templates")
        self.templates_dir.mkdir(parents=True, exist_ok=True)
        
    def list_templates(self) -> list[str]:
        """列出所有已保存的模板名称（去后缀）"""
        results = []
        for f in self.templates_dir.glob("*.json"):
            results.append(f.stem)
        return sorted(results)
        
    def save_template(self, name: str, decolor_params: dict, binding_params: dict, stamps_data: dict) -> bool:
        """
        保存环境全状态为字典 JSON
        stamps_data: { "page_index": [ {"asset_id": "xxx", "x": 10.0, "y": 20.0, "scale": 1.0, "rotation": 0.0}, ... ] }
        """
        path = self.templates_dir / f"{name}.json"
        
        # 将所有非标准字面量的键值统一强制转标准
        clean_stamps = {}
        for page_idx, items in stamps_data.items():
            clean_stamps[str(page_idx)] = items
            
        payload = {
            "version": "1.0",
            "decolor_params": decolor_params,
            "binding_params": binding_params,
            "stamps": clean_stamps
        }
        
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"[TemplateManager] 保存模板失败: {e}")
            return False
            
    def load_template(self, name: str) -> dict | None:
        """提取指定的模板字典，如果异常则回吐 None"""
        path = self.templates_dir / f"{name}.json"
        if not path.exists():
            return None
            
        try:
            with open(path, "r", encoding="utf-8") as f:
                payload = json.load(f)
                
            # 重构 stamps key 回 integer 以便引擎调拔
            if "stamps" in payload:
                stamps = {}
                for k, v in payload["stamps"].items():
                    if k.isdigit():
                        stamps[int(k)] = v
                payload["stamps"] = stamps
                
            return payload
        except Exception as e:
            print(f"[TemplateManager] 加载模板失败: {e}")
            return None
            
    def delete_template(self, name: str) -> bool:
        """移除模板"""
        path = self.templates_dir / f"{name}.json"
        try:
            if path.exists():
                path.unlink()
            return True
        except:
            return False
