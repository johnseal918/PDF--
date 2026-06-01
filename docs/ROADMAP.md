# Roadmap

This roadmap describes public, non-sensitive work planned for PDF Seal Master. It is intentionally lightweight and may change as the project evolves.

## Near Term

- Improve setup documentation for Windows and macOS.
- Add safe sample documents and synthetic stamp assets for demos and tests.
- Add focused tests for PDF import, A4 normalization, stamp placement, and export rendering.
- Add screenshots or short demo media using synthetic documents only.
- Package the desktop app for easier local evaluation.

## Desktop

- Stabilize preview and export consistency.
- Improve binding stamp controls and edge-case handling.
- Add more deterministic rendering tests for image-processing filters.
- Improve error messages for unsupported or damaged files.

## iOS

- Validate the SwiftUI scaffold in Xcode.
- Expand PDFKit preview and export flows.
- Continue testing domain services and editor state transitions.
- Keep StoreKit-related code isolated from core document workflows.

## OSS Maintenance

- Use GitHub issues to track bugs, feature requests, and release tasks.
- Keep private assets, logs, and local configuration out of the repository.
- Tag small releases with clear validation notes.
- Prefer reproducible sample files and synthetic test data in bug reports.
