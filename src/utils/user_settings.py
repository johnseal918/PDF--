"""
Small JSON-backed user preferences for UI behavior.
"""

from pathlib import Path
from typing import Any

from src.utils.config_io import read_json, write_json


USER_SETTINGS_PATH = Path("config/user_settings.json")

DEFAULT_RANDOM_COPY_SETTINGS = {
    "copy_random_angle_enabled": False,
    "copy_random_position_enabled": False,
    "copy_random_angle_range": 3.0,
    "copy_random_position_mm": 5.0,
    "mouse_wheel_mode": "scroll",
    "mouse_wheel_inverted": False,
}


def _float_or_default(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(float(value), high))


def clamp_random_copy_settings(settings: dict[str, Any]) -> dict[str, Any]:
    wheel_mode = settings.get("mouse_wheel_mode", "scroll")
    if wheel_mode not in ("scroll", "zoom"):
        wheel_mode = "scroll"
    return {
        "copy_random_angle_enabled": bool(settings.get("copy_random_angle_enabled", False)),
        "copy_random_position_enabled": bool(settings.get("copy_random_position_enabled", False)),
        "copy_random_angle_range": _clamp(
            _float_or_default(settings.get("copy_random_angle_range"), 3.0), 0.0, 15.0
        ),
        "copy_random_position_mm": _clamp(
            _float_or_default(settings.get("copy_random_position_mm"), 5.0), 0.0, 30.0
        ),
        "mouse_wheel_mode": wheel_mode,
        "mouse_wheel_inverted": bool(settings.get("mouse_wheel_inverted", False)),
    }


def normalize_random_copy_settings(settings: dict[str, Any] | None) -> dict[str, Any]:
    merged = dict(DEFAULT_RANDOM_COPY_SETTINGS)
    if isinstance(settings, dict):
        merged.update(settings)
    return clamp_random_copy_settings(merged)


def load_user_settings(path: str | Path = USER_SETTINGS_PATH) -> dict[str, Any]:
    return normalize_random_copy_settings(read_json(path, dict))


def save_user_settings(settings: dict[str, Any], path: str | Path = USER_SETTINGS_PATH) -> bool:
    return write_json(path, normalize_random_copy_settings(settings))
