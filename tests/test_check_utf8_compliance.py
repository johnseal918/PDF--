import subprocess
import sys
from pathlib import Path


SCRIPT = Path("scripts/check_utf8_compliance.py")
TMP_DIR = Path("tmp/test_check_utf8_compliance")


def test_check_utf8_compliance_accepts_valid_utf8_file():
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    target = TMP_DIR / "ok.md"
    target.write_text("正常文本\n", encoding="utf-8")

    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--mode", "paths", str(target)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    assert result.returncode == 0
    assert "OK" in result.stdout


def test_check_utf8_compliance_rejects_invalid_utf8_file():
    TMP_DIR.mkdir(parents=True, exist_ok=True)
    target = TMP_DIR / "bad.md"
    target.write_bytes(b"\xff\xfe\x00\x00")

    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--mode", "paths", str(target)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    assert result.returncode == 1
    assert "DECODE_ERROR" in result.stdout
