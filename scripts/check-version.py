#!/usr/bin/env python3
"""Validate a release tag against the changelog."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "CHANGELOG.md"
VERSION_PATTERN = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: check-version.py <tag>")

    tag = sys.argv[1]
    match = VERSION_PATTERN.fullmatch(tag)
    if match is None:
        raise SystemExit(f"release tag must have the form vMAJOR.MINOR.PATCH, got {tag!r}")

    version = tag.removeprefix("v")
    changelog = CHANGELOG.read_text()
    heading = rf"^## \[{re.escape(version)}] - \d{{4}}-\d{{2}}-\d{{2}}$"
    if re.search(heading, changelog, flags=re.MULTILINE) is None:
        raise SystemExit(f"CHANGELOG.md has no release heading for {version}")


if __name__ == "__main__":
    main()
