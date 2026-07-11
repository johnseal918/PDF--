# PDF Page Orientation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve each imported page's source orientation and add a bottom-canvas button that toggles the current page between portrait and landscape.

**Architecture:** Keep orientation in the page image dimensions instead of introducing duplicate state. `DocumentModel` owns A4 normalization and page direction changes; `CanvasWidget` exposes the existing bottom-bar control; `MainWindow` coordinates the current page image and stamp-position remapping.

**Tech Stack:** Python 3, PySide6, PyMuPDF, Pillow, pytest

---

### Task 1: Orientation-aware A4 pages

**Files:**
- Modify: `src/core/pdf_engine.py`
- Test: `tests/test_pdf_engine.py`

- [ ] Write tests proving a landscape image normalizes to `3508 × 2480`, portrait remains `2480 × 3508`, and switching direction preserves content within the target canvas.
- [ ] Run `python -m pytest tests/test_pdf_engine.py -q` with plugin autoload disabled and confirm the landscape test fails because normalization is portrait-only.
- [ ] Make `_normalize_to_a4_canvas()` select its canvas from source width/height and add the minimum current-page direction toggle method.
- [ ] Re-run the focused tests and confirm they pass.

### Task 2: Current-page GUI control

**Files:**
- Modify: `src/ui/canvas_view.py`
- Modify: `src/ui/main_window.py`
- Test: `tests/test_canvas_orientation.py`

- [ ] Write a Qt test proving the direction button sits between zoom and page navigation, reflects the current page, and emits the requested direction.
- [ ] Run the focused test and confirm it fails because the button/signal do not exist.
- [ ] Add one existing-style `QPushButton` to the canvas bottom bar and connect it through `MainWindow` to the current document page.
- [ ] Remap current-page stamp positions by old/new page width and height ratios, refresh the canvas, and update the file-size label/button state.
- [ ] Re-run the focused tests and confirm they pass.

### Task 3: Regression and runtime verification

**Files:**
- Modify only if required by a failing test in the accepted scope.

- [ ] Run `$env:PYTEST_DISABLE_PLUGIN_AUTOLOAD='1'; python -m pytest -q` and require zero failures.
- [ ] Launch `python main.py`, load portrait and landscape synthetic PDFs, verify default direction, toggle behavior, bottom-bar placement, stamp visibility, and export page dimensions.
- [ ] Scan touched UTF-8 files for mojibake and inspect `git diff --check`.
- [ ] Record operation, conversation, correction, and verification evidence in the existing dated log structure.
