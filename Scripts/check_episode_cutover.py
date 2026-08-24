#!/usr/bin/env python3
"""Run the exact EA-01 zero-match scan set for one cutover package."""

from __future__ import annotations

import sys
from pathlib import Path

from check_episode_inventory import CUTOVER_PACKAGES, ROOT, ContractError, validate_manifest


def matching_paths(specification: str) -> list[Path]:
    paths: set[Path] = set()
    for part in specification.split(","):
        part = part.strip()
        if not part:
            continue
        paths.update(path for path in ROOT.glob(part) if path.is_file())
    return sorted(paths)


def main(argv: list[str]) -> int:
    try:
        _rows, scans = validate_manifest()
    except (OSError, ContractError) as error:
        print(f"episode cutover: invalid EA-01 manifest: {error}", file=sys.stderr)
        return 1
    if argv == ["--validate-manifest"]:
        print("episode cutover manifest passed")
        return 0
    if len(argv) != 1 or argv[0] not in CUTOVER_PACKAGES:
        allowed = ", ".join(sorted(CUTOVER_PACKAGES))
        print(f"usage: check_episode_cutover.py <PACKAGE-ID>; allowed: {allowed}", file=sys.stderr)
        return 2
    package = argv[0]
    failures: list[str] = []
    package_scans = [row for row in scans if row["package"] == package]
    for scan in package_scans:
        literal = scan["literal"]
        for path in matching_paths(scan["paths"]):
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
            ):
                if literal in line:
                    failures.append(
                        f"{scan['class']} {path.relative_to(ROOT)}:{line_number}: {literal}"
                    )
    if failures:
        print(f"episode cutover {package}: superseded paths remain", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1
    print(f"episode cutover {package} passed: {len(package_scans)} zero-match scans")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
