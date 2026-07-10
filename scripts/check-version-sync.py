#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def main() -> None:
    version = read("VERSION").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        fail(f"VERSION is not semantic x.y.z: {version!r}")

    required_markers = {
        "README.md": f"Current release: **{version}**",
        "README.el.md": f"Τρέχουσα έκδοση: **{version}**",
        "CHANGELOG.md": f"## [{version}] - ",
        "ROADMAP.md": f"Current stable release: **v{version}**",
        "ROADMAP.el.md": f"Τρέχουσα σταθερή έκδοση: **v{version}**",
    }

    for path, marker in required_markers.items():
        content = read(path)
        if marker not in content:
            fail(f"{path} does not contain expected version marker: {marker}")

    print(f"Release metadata is synchronized at {version}.")


if __name__ == "__main__":
    main()
