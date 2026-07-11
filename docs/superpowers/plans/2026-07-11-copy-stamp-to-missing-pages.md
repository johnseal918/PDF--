# Copy Stamp To Missing Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add batch copy actions for ordinary stamps, with skip-existing behavior, configurable random angle/position offsets, persistent UI preferences, and undo/export consistency.

**Architecture:** Keep the behavior inside the existing desktop UI flow. `StampItem` owns the right-click menu labels, `CanvasView` owns per-document copy mechanics and page coordinate conversion, `MainWindow` coordinates cross-document copy and settings UI, and a tiny settings helper persists random copy preferences in `config/user_settings.json`.

**Tech Stack:** Python, PySide6, QGraphicsScene/QUndoStack, existing JSON config helpers, pytest.

---

### Task 1: User Settings Persistence

**Files:**
- Create: `src/utils/user_settings.py`
- Test: `tests/test_user_settings.py`

- [ ] **Step 1: Write failing tests**

```python
from src.utils.user_settings import clamp_random_copy_settings, normalize_random_copy_settings


def test_normalize_random_copy_settings_uses_defaults_for_missing_and_bad_values():
    settings = normalize_random_copy_settings({"copy_random_angle_range": "bad", "copy_random_position_mm": 99})

    assert settings["copy_random_angle_enabled"] is False
    assert settings["copy_random_position_enabled"] is False
    assert settings["copy_random_angle_range"] == 3.0
    assert settings["copy_random_position_mm"] == 30.0


def test_clamp_random_copy_settings_keeps_values_in_allowed_ranges():
    settings = clamp_random_copy_settings(
        {
            "copy_random_angle_enabled": True,
            "copy_random_position_enabled": True,
            "copy_random_angle_range": -2,
            "copy_random_position_mm": 40,
        }
    )

    assert settings["copy_random_angle_enabled"] is True
    assert settings["copy_random_position_enabled"] is True
    assert settings["copy_random_angle_range"] == 0.0
    assert settings["copy_random_position_mm"] == 30.0
```

- [ ] **Step 2: Verify tests fail**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_user_settings.py`
Expected: FAIL because `src.utils.user_settings` does not exist.

- [ ] **Step 3: Implement settings helper**

Create `src/utils/user_settings.py` with constants for defaults/ranges, `normalize_random_copy_settings()`, `clamp_random_copy_settings()`, `load_user_settings()`, and `save_user_settings()` using existing `read_json`/`write_json`.

- [ ] **Step 4: Verify tests pass**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_user_settings.py`
Expected: PASS.

### Task 2: Page-Aware Batch Add Command

**Files:**
- Modify: `src/ui/undo_commands.py`
- Test: `tests/test_copy_stamp_undo.py`

- [ ] **Step 1: Write failing test**

```python
from PySide6.QtCore import QPointF
from PySide6.QtGui import QPixmap
from PySide6.QtWidgets import QGraphicsScene, QUndoStack

from src.ui.stamp_item import StampItem
from src.ui.undo_commands import AddStampsBatchCommand


def test_batch_add_command_keeps_scene_and_page_index_in_sync(qapp):
    scene = QGraphicsScene()
    stack = QUndoStack()
    page_stamps = {1: []}
    item = StampItem(QPixmap(10, 10), "seal-1")
    item.page_index = 1

    stack.push(AddStampsBatchCommand(scene, [(item, QPointF(5, 6), 1)], page_stamps))

    assert item.scene() is scene
    assert item in page_stamps[1]

    stack.undo()
    assert item.scene() is None
    assert item not in page_stamps[1]

    stack.redo()
    assert item.scene() is scene
    assert item in page_stamps[1]
```

- [ ] **Step 2: Verify test fails**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_copy_stamp_undo.py`
Expected: FAIL because `AddStampsBatchCommand` does not exist.

- [ ] **Step 3: Implement batch command**

Add `AddStampsBatchCommand` to `src/ui/undo_commands.py`. It stores `(item, position, page_index)` tuples, adds/removes scene items, and adds/removes each item from `page_stamps[page_index]` without duplicates.

- [ ] **Step 4: Verify test passes**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_copy_stamp_undo.py`
Expected: PASS.

### Task 3: Canvas Copy Mechanics

**Files:**
- Modify: `src/ui/canvas_view.py`
- Modify: `src/ui/stamp_item.py`
- Test: `tests/test_copy_stamp_to_missing_pages.py`

- [ ] **Step 1: Write failing tests**

```python
from PySide6.QtCore import QPointF
from PySide6.QtGui import QPixmap

from src.ui.canvas_view import CanvasView
from src.ui.stamp_item import StampItem


def _stamp(asset_id="seal-1", page=0):
    item = StampItem(QPixmap(100, 50), asset_id)
    item.category = "stamps"
    item.page_index = page
    item.setPos(QPointF(200, 300))
    item.setScale(0.5)
    item.setRotation(7)
    return item


def test_copy_stamp_to_current_document_skips_pages_that_already_have_same_asset(qapp):
    view = CanvasView()
    view._page_sizes = {0: (1000, 1500), 1: (1000, 1500), 2: (1000, 1500)}
    source = _stamp(page=0)
    existing = _stamp(page=1)
    view._page_stamps = {0: [source], 1: [existing], 2: []}

    result = view.copy_stamp_to_missing_pages(source, [1, 2], {"angle_enabled": False, "position_enabled": False})

    assert result == {"added": 1, "skipped": 1}
    assert len(view._page_stamps[1]) == 1
    assert len(view._page_stamps[2]) == 1
    copied = view._page_stamps[2][0]
    assert copied.asset_id == source.asset_id
    assert copied.rotation() == source.rotation()


def test_copy_stamp_random_offsets_are_applied_inside_configured_ranges(qapp, monkeypatch):
    view = CanvasView()
    view._page_sizes = {0: (1000, 1500), 1: (1000, 1500)}
    source = _stamp(page=0)
    view._page_stamps = {0: [source], 1: []}
    values = iter([2.5, 3.0, -4.0])
    monkeypatch.setattr("src.ui.canvas_view.random.uniform", lambda a, b: next(values))

    view.copy_stamp_to_missing_pages(
        source,
        [1],
        {"angle_enabled": True, "angle_range": 3.0, "position_enabled": True, "position_mm": 5.0},
    )

    copied = view._page_stamps[1][0]
    assert copied.rotation() == 9.5
    assert copied.pos() != source.pos()
```

- [ ] **Step 2: Verify tests fail**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_copy_stamp_to_missing_pages.py`
Expected: FAIL because `copy_stamp_to_missing_pages` does not exist.

- [ ] **Step 3: Implement minimal copy mechanics**

Add copy methods to `CanvasView`: source spec extraction, existing same-asset check, page-size conversion, A4-mm random position conversion, page-bound clamping, item creation, signal wiring, and `AddStampsBatchCommand` push.

- [ ] **Step 4: Add right-click menu actions**

Update `StampItem.contextMenuEvent()` to show ordinary-stamp copy actions and checkable random toggles. Store toggle state on the item before emitting copy actions.

- [ ] **Step 5: Verify tests pass**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_copy_stamp_to_missing_pages.py`
Expected: PASS.

### Task 4: Main Window Settings And Cross-Document Coordination

**Files:**
- Modify: `src/ui/main_window.py`
- Modify: `src/ui/canvas_view.py`
- Test: `tests/test_copy_stamp_integration.py`

- [ ] **Step 1: Write failing tests**

```python
from PySide6.QtGui import QPixmap

from src.ui.canvas_view import CanvasView
from src.ui.stamp_item import StampItem


def test_export_data_includes_copied_stamp_and_undo_removes_it(qapp):
    view = CanvasView()
    view._page_sizes = {0: (1000, 1500), 1: (1000, 1500)}
    source = StampItem(QPixmap(100, 50), "seal-1")
    source.category = "stamps"
    source.page_index = 0
    view._page_stamps = {0: [source], 1: []}

    view.copy_stamp_to_missing_pages(source, [1], {"angle_enabled": False, "position_enabled": False})

    data = view.get_all_stamps_data()
    assert 1 in data
    assert data[1][0]["asset_id"] == "seal-1"

    view.undo_stack.undo()
    assert 1 not in view.get_all_stamps_data()
```

- [ ] **Step 2: Verify test fails**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_copy_stamp_integration.py`
Expected: FAIL until copy mechanics and export data are correct.

- [ ] **Step 3: Implement UI coordination**

Load settings in `MainWindow`, add `编辑 -> 随机复制设置...`, show a small `QDialog` with two spin boxes, save settings on OK, pass settings into each active `CanvasView`, and handle a new cross-document copy signal by skipping the source canvas.

- [ ] **Step 4: Verify test passes**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_copy_stamp_integration.py`
Expected: PASS.

### Task 5: Full Verification And Commit

**Files:**
- Verify all touched files.

- [ ] **Step 1: Run targeted tests**

Run:
`$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q tests/test_user_settings.py tests/test_copy_stamp_undo.py tests/test_copy_stamp_to_missing_pages.py tests/test_copy_stamp_integration.py`
Expected: PASS.

- [ ] **Step 2: Run full tests**

Run: `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q`
Expected: PASS.

- [ ] **Step 3: Run syntax compile**

Run: `python -m compileall src tests`
Expected: PASS.

- [ ] **Step 4: Run diff and encoding checks**

Run: `git diff --check`
Expected: no output.

Run a UTF-8 byte check over touched `.py` and `.md` files.
Expected: valid UTF-8, no BOM, no U+FFFD.

- [ ] **Step 5: Commit**

Run:
`git add src tests docs/superpowers/plans/2026-07-11-copy-stamp-to-missing-pages.md`
`git commit -m "feat: copy stamps to missing pages"`

---

## Self-Review

- Spec coverage: copy scopes, skip-existing, random toggles, configurable ranges, settings persistence, undo/index consistency, export data, and edge cases are covered by tasks.
- Placeholder scan: no TBD/TODO placeholders.
- Type consistency: settings keys use `copy_random_*` in persistence and shorter runtime keys only in copy calls.
