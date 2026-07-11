from src.utils.user_settings import (
    clamp_random_copy_settings,
    load_user_settings,
    normalize_random_copy_settings,
    save_user_settings,
)


def test_normalize_random_copy_settings_uses_defaults_for_missing_and_bad_values():
    settings = normalize_random_copy_settings(
        {"copy_random_angle_range": "bad", "copy_random_position_mm": 99, "mouse_wheel_mode": "bad"}
    )

    assert settings["copy_random_angle_enabled"] is False
    assert settings["copy_random_position_enabled"] is False
    assert settings["copy_random_angle_range"] == 3.0
    assert settings["copy_random_position_mm"] == 30.0
    assert settings["mouse_wheel_mode"] == "scroll"
    assert settings["mouse_wheel_inverted"] is False


def test_clamp_random_copy_settings_keeps_values_in_allowed_ranges():
    settings = clamp_random_copy_settings(
        {
            "copy_random_angle_enabled": True,
            "copy_random_position_enabled": True,
            "copy_random_angle_range": -2,
            "copy_random_position_mm": 40,
            "mouse_wheel_mode": "zoom",
            "mouse_wheel_inverted": True,
        }
    )

    assert settings["copy_random_angle_enabled"] is True
    assert settings["copy_random_position_enabled"] is True
    assert settings["copy_random_angle_range"] == 0.0
    assert settings["copy_random_position_mm"] == 30.0
    assert settings["mouse_wheel_mode"] == "zoom"
    assert settings["mouse_wheel_inverted"] is True


def test_save_and_load_user_settings_round_trip():
    path = "tmp/test_user_settings.json"

    save_user_settings(
        {
            "copy_random_angle_enabled": True,
            "copy_random_position_enabled": True,
            "copy_random_angle_range": 8,
            "copy_random_position_mm": 12,
        },
        path,
    )

    assert load_user_settings(path)["copy_random_angle_range"] == 8.0
    assert load_user_settings(path)["copy_random_position_mm"] == 12.0
