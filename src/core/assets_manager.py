"""
assets_manager.py — 图章与签名的素材库底层控制器

管理资产的元数据，将导入的素材拷贝入项目目录以便解耦源文件，并持久化缓存。
"""

import uuid
import shutil
from pathlib import Path
from typing import Dict, List, Optional
import sys

PROJECT_ROOT = Path(__file__).resolve().parents[2]
from src.utils.config_io import read_json, write_json

# 资产根目录设定
ASSETS_DIR = PROJECT_ROOT / "assets" / "stamps"
CONFIG_PATH = PROJECT_ROOT / "config" / "assets.json"


class AssetsManager:
    """管理系统的本印章与签名。"""

    def __init__(self):
        # 初始化创建真实目录体系
        ASSETS_DIR.mkdir(parents=True, exist_ok=True)
        
        # 缓存配置字典: {'stamps': [{'id': '..', 'path': '...', 'name': '...'}], 'signatures': [...]}
        self._db = self._load()

    def _load(self) -> Dict[str, List[dict]]:
        """从 JSON 读取缓存。"""
        db = read_json(CONFIG_PATH, lambda: {"stamps": [], "signatures": []})
        # 安全性补全结构保护
        if "stamps" not in db: db["stamps"] = []
        if "signatures" not in db: db["signatures"] = []
        return db

    def _save(self) -> bool:
        """写回到 JSON。"""
        return write_json(CONFIG_PATH, self._db)

    def get_assets(self, category: str) -> List[dict]:
        """获取某分类的所有资产列表。
        category 必须是 'stamps' 或 'signatures'
        """
        return self._db.get(category, [])

    def add_asset(self, category: str, external_file_path: str) -> Optional[dict]:
        """将外部文件注册为资产（拷贝进内库，发配 UUID）。"""
        if category not in ["stamps", "signatures"]:
            return None

        src_path = Path(external_file_path)
        if not src_path.is_file():
            return None

        # 生成内部持久化 ID 及路径
        asset_id = str(uuid.uuid4())[:8]
        new_filename = f"{category}_{asset_id}{src_path.suffix}"
        dest_path = ASSETS_DIR / new_filename

        try:
            shutil.copy2(src_path, dest_path)
            
            # 使用基于 assets/stamps 的相对路径进行注册
            rel_path = f"assets/stamps/{new_filename}"
            asset_info = {
                "id": asset_id,
                "name": src_path.stem,
                "path": rel_path
            }
            self._db[category].append(asset_info)
            self._save()
            return asset_info
            
        except Exception as e:
            print(f"[AssetsManager] 拷贝导入文件失败 {e}")
            return None

    def remove_asset(self, category: str, asset_id: str) -> bool:
        """根据 ID 移除某资材，并试图销毁实体图库片。"""
        if category not in self._db:
            return False

        target_info = None
        for item in self._db[category]:
            if item["id"] == asset_id:
                target_info = item
                break

        if not target_info:
            return False

        # 1. 数组删去
        self._db[category].remove(target_info)
        self._save()

        # 2. 物理删去图库
        try:
            absolute_path = PROJECT_ROOT / target_info["path"]
            if absolute_path.exists():
                absolute_path.unlink()
        except Exception as e:
            print(f"删除物理文件异常: {e}")
            
        return True

    def rename_asset(self, category: str, asset_id: str, new_name: str) -> bool:
        """重命名现存的印章/签名资产。"""
        if category not in self._db:
            return False
        for item in self._db[category]:
            if item["id"] == asset_id:
                item["name"] = new_name
                self._save()
                return True
        return False

    def get_absolute_path(self, rel_path: str) -> str:
        """从 JSON 内存储的相对路径还原为系统级绝对地址（供 PySide6 和 PyMuPDF 读）。"""
        return str(PROJECT_ROOT / rel_path)
