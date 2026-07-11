# Smart Enhancement Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add left-side shortcuts, two explicit stamp-size synchronization scopes, and a shared smart document enhancement pipeline with live controls.

**Architecture:** `CVProcessor.enhance_document()` is the only enhancement implementation used by preview and export. `AssetsPanel` owns visible shortcut buttons; `CanvasView` owns per-document stamp sizing and emits cross-document requests; `MainWindow` coordinates tabs and action state.

**Tech Stack:** Python, PySide6, OpenCV, NumPy, Pillow, pytest

---

### Task 1: Shared enhancement pipeline
- [ ] Add failing synthetic tests for fine lines, dark text, background removal, red restoration and determinism.
- [ ] Implement the minimum four-layer fusion in `src/core/cv_processor.py`.
- [ ] Replace duplicated preview/export processing with the shared call and verify focused tests.

### Task 2: Smart enhancement controls and compatibility
- [ ] Add failing property-panel tests for the renamed switch and two sliders.
- [ ] Replace algorithm/noise controls, migrate old template parameters on read, and keep 250ms preview behavior.
- [ ] Verify per-tab parameter restoration and preview/export parameter identity.

### Task 3: Two stamp sizing scopes
- [ ] Add failing tests for current-document all-stamp sizing and all-open-document same-asset sizing.
- [ ] Add two explicit context-menu actions and cross-context coordination.
- [ ] Verify signatures and binding stamps are excluded and page orientation uses A4 units.

### Task 4: Left shortcut buttons
- [ ] Add failing GUI tests for button location, enabled state and signals.
- [ ] Add the two buttons to `AssetsPanel`, connect existing actions, and expose disabled reason.
- [ ] Replay no-document, current-document and tab-switch states.

### Task 5: Closure
- [ ] Run focused tests, full suite, compile, encoding scan and `git diff --check`.
- [ ] Run local read-only regression on the two supplied PDFs and capture metrics/previews.
- [ ] Record requirement closure, operation/conversation/error evidence and remaining risks.
