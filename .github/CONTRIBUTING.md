# Contributing

Thanks for considering a contribution to PDF Seal Master.

## What Helps

- Bug reports with a small PDF or image sample that can be shared publicly.
- Reproducible export, rendering, or layout issues.
- Tests for PDF loading, stamp placement, image processing, and iOS domain services.
- Documentation improvements for setup, packaging, and platform-specific behavior.

## Local Setup

```bash
python -m venv .venv
pip install -r requirements.txt
python main.py
```

On Windows PowerShell, activate the environment with:

```powershell
.\.venv\Scripts\Activate.ps1
```

## Pull Request Guidelines

- Keep changes focused on one feature or fix.
- Do not include private stamps, signatures, contracts, logs, or local configuration.
- Add or update tests when changing document loading, rendering, export, or persistence behavior.
- Include screenshots only when they use safe public sample files.
- Explain user impact and validation steps in the PR description.

## Reporting Security or Privacy Issues

Please do not open a public issue for sensitive files, private documents, signatures, or credential exposure. Follow the policy in `.github/SECURITY.md`.
