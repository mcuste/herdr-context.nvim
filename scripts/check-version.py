#!/usr/bin/env python3
"""Validate a release tag against the changelog."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "CHANGELOG.md"
VERSION_PATTERN = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


def release_notes(changelog: str, version: str) -> str:
    heading = rf"^## \[{re.escape(version)}] - \d{{4}}-\d{{2}}-\d{{2}}$"
    match = re.search(heading, changelog, flags=re.MULTILINE)
    if match is None:
        raise SystemExit(f"CHANGELOG.md has no release heading for {version}")

    remaining = changelog[match.end() :]
    next_heading = re.search(r"^## ", remaining, flags=re.MULTILINE)
    notes = (remaining if next_heading is None else remaining[: next_heading.start()]).strip()
    if re.search(r"^\s*-\s+\S", notes, flags=re.MULTILINE) is None:
        raise SystemExit(f"CHANGELOG.md has no release notes for {version}")
    return notes


def main() -> None:
    if len(sys.argv) not in {2, 3} or (len(sys.argv) == 3 and sys.argv[2] != "--notes"):
        raise SystemExit("usage: check-version.py <tag> [--notes]")

    tag = sys.argv[1]
    match = VERSION_PATTERN.fullmatch(tag)
    if match is None:
        raise SystemExit(f"release tag must have the form vMAJOR.MINOR.PATCH, got {tag!r}")

    version = tag.removeprefix("v")
    notes = release_notes(CHANGELOG.read_text(), version)
    if len(sys.argv) == 3:
        print(notes)


if __name__ == "__main__":
    main()
