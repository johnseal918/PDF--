from __future__ import annotations

import argparse
import sys
from pathlib import Path


def _check_path(path: Path) -> tuple[bool, str]:
    if not path.is_file():
        return False, f"MISSING {path}"

    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as exc:
        return False, f"DECODE_ERROR {path} {exc.start}:{exc.end}"

    if "\ufffd" in text:
        return False, f"REPLACEMENT_CHAR {path}"

    return True, f"OK {path}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Check UTF-8 compliance for project files.")
    parser.add_argument("--mode", choices=["paths"], required=True)
    parser.add_argument("paths", nargs="+")
    args = parser.parse_args(argv)

    has_error = False
    for raw_path in args.paths:
        ok, message = _check_path(Path(raw_path))
        print(message)
        if not ok:
            has_error = True

    return 1 if has_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
