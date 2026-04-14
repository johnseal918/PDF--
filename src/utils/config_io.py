"""
config_io.py — JSON 配置文件统一读写工具
"""

import json
from pathlib import Path
from typing import Any, Dict


def read_json(file_path: str | Path, default_factory=dict) -> Dict[str, Any]:
    """读取 JSON 文件。如果不存在或出现错误，返回 default_factory() 提供的值。"""
    path = Path(file_path)
    if not path.is_file():
        return default_factory()
        
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"[config_io] 读取 JSON 失败 ({path}): {e}")
        return default_factory()


def write_json(file_path: str | Path, data: Dict[str, Any]) -> bool:
    """写入 JSON 文件，如果父级目录不存在会自动创建。"""
    path = Path(file_path)
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=4)
        return True
    except Exception as e:
        print(f"[config_io] 写入 JSON 失败 ({path}): {e}")
        return False
