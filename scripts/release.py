#!/usr/bin/env python3
"""Prepare, verify, commit, tag, and optionally push a release."""

from __future__ import annotations

import re
import subprocess
import sys
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CHANGELOG = ROOT / "CHANGELOG.md"
RELEASE_BRANCH = "main"
UNRELEASED_HEADING = "## [Unreleased]"
VERSION_PATTERN = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


def fail(message: str) -> None:
    raise SystemExit(f"release: {message}")


def git(*args: str, capture: bool = True) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if result.stdout is not None else ""


def parse_version(value: str, label: str) -> tuple[int, int, int]:
    match = VERSION_PATTERN.fullmatch(value)
    if match is None:
        fail(f"{label} is not a three-part version: {value!r}.")
    return tuple(int(part) for part in match.groups())


def unreleased_section(changelog: str) -> str:
    start = changelog.find(UNRELEASED_HEADING)
    if start == -1:
        fail(f"CHANGELOG.md has no {UNRELEASED_HEADING} section.")
    rest = changelog[start + len(UNRELEASED_HEADING) :]
    next_heading = re.search(r"^## ", rest, flags=re.MULTILINE)
    return rest if next_heading is None else rest[: next_heading.start()]


def released_versions(changelog: str) -> list[tuple[int, int, int]]:
    versions = re.findall(r"^## \[(\d+\.\d+\.\d+)] - \d{4}-\d{2}-\d{2}$", changelog, flags=re.MULTILINE)
    return [parse_version(version, "a changelog version") for version in versions]


def restore_changelog() -> None:
    git("checkout", "--", CHANGELOG.name)


def main() -> None:
    args = sys.argv[1:]
    push = "--push" in args
    requested = next((argument for argument in args if not argument.startswith("-")), None)
    unknown = [argument for argument in args if argument.startswith("-") and argument != "--push"]
    if requested is None or unknown or len(args) != 1 + int(push):
        fail("usage: just release <version> [--push]")

    requested_parts = parse_version(requested, "the requested version")
    tag = f"v{requested}"

    if git("status", "--porcelain", "--untracked-files=no"):
        fail("tracked files have uncommitted changes. Commit or stash them first.")
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if branch != RELEASE_BRANCH:
        fail(f"releases run from {RELEASE_BRANCH}, but {branch} is checked out.")
    if git("tag", "--list", tag):
        fail(f"{tag} already exists.")

    changelog = CHANGELOG.read_text()
    if re.search(r"^\s*-\s+\S", unreleased_section(changelog), flags=re.MULTILINE) is None:
        fail(f"{UNRELEASED_HEADING} has no entries, so there is nothing to release.")
    if re.search(rf"^## \[{re.escape(requested)}]", changelog, flags=re.MULTILINE):
        fail(f"CHANGELOG.md already contains a {requested} release.")

    previous_versions = released_versions(changelog)
    if previous_versions and requested_parts <= max(previous_versions):
        current = ".".join(str(part) for part in max(previous_versions))
        fail(f"{requested} must be greater than the latest release {current}.")

    release_heading = f"{UNRELEASED_HEADING}\n\n## [{requested}] - {date.today().isoformat()}"
    CHANGELOG.write_text(changelog.replace(UNRELEASED_HEADING, release_heading, 1))
    print(f"release: prepared {requested}, running the full gate.")

    try:
        subprocess.run(["just", "verify"], cwd=ROOT, check=True)
    except (OSError, subprocess.CalledProcessError):
        restore_changelog()
        fail("verification failed. CHANGELOG.md was restored.")

    git("add", CHANGELOG.name)
    git("commit", "-m", f"chore: release {requested}", capture=False)
    git("tag", tag)

    if not push:
        print(f"release: committed and tagged {tag}. Publish it with:")
        print(f"\n  git push origin {RELEASE_BRANCH} && git push origin {tag}\n")
        print(f"Undo it before pushing with:\n\n  git tag -d {tag} && git reset --hard HEAD~1\n")
        return

    git("push", "origin", RELEASE_BRANCH, capture=False)
    git("push", "origin", tag, capture=False)
    print(f"release: pushed {tag}. The release workflow publishes from here.")


if __name__ == "__main__":
    main()
