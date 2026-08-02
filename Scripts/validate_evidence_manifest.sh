#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest_path="$repo_root/Fixtures/LegacyEvidence/manifest.json"
verify_source=0

if [[ "${1:-}" == "--verify-source" ]]; then
  verify_source=1
  shift
fi
if [[ "$#" -ne 0 ]]; then
  printf 'usage: %s [--verify-source]\n' "$0" >&2
  exit 2
fi

python3 - "$repo_root" "$manifest_path" "$verify_source" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

repo_root = Path(sys.argv[1]).resolve()
manifest_path = Path(sys.argv[2]).resolve()
verify_source = sys.argv[3] == "1"


def fail(message: str) -> None:
    raise SystemExit(f"evidence manifest validation failed: {message}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


try:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    fail(f"cannot read {manifest_path}: {error}")

if manifest.get("schema_version") != 1:
    fail("schema_version must be 1")
if manifest.get("status") != "historical_not_current":
    fail("top-level status must be historical_not_current")
if manifest.get("hash_algorithm") != "sha256":
    fail("hash_algorithm must be sha256")

entries = manifest.get("entries")
if not isinstance(entries, list) or not entries:
    fail("entries must be a non-empty array")

seen_ids: set[str] = set()
seen_paths: set[str] = set()
for entry in entries:
    entry_id = entry.get("id")
    relative_path = entry.get("fixture_path")
    if not isinstance(entry_id, str) or not entry_id:
        fail("every entry needs a non-empty id")
    if entry_id in seen_ids:
        fail(f"duplicate id {entry_id}")
    seen_ids.add(entry_id)
    if not isinstance(relative_path, str) or not relative_path.startswith("Fixtures/LegacyEvidence/"):
        fail(f"{entry_id} has an invalid fixture_path")
    if relative_path in seen_paths:
        fail(f"duplicate fixture_path {relative_path}")
    seen_paths.add(relative_path)

    fixture_path = (repo_root / relative_path).resolve()
    try:
        fixture_path.relative_to(repo_root)
    except ValueError:
        fail(f"{entry_id} fixture escapes the repository")
    if not fixture_path.is_file():
        fail(f"{entry_id} fixture is missing: {fixture_path}")
    actual_size = fixture_path.stat().st_size
    if actual_size != entry.get("fixture_size_bytes"):
        fail(f"{entry_id} size is {actual_size}, expected {entry.get('fixture_size_bytes')}")
    actual_hash = sha256(fixture_path)
    if actual_hash != entry.get("fixture_sha256"):
        fail(f"{entry_id} hash is {actual_hash}, expected {entry.get('fixture_sha256')}")
    if not str(entry.get("authority_status", "")).startswith("historical_non_authoritative"):
        fail(f"{entry_id} must be explicitly historical and non-authoritative")

    for line_number, line in enumerate(fixture_path.read_text(encoding="utf-8").splitlines(), start=1):
        try:
            record = json.loads(line)
        except json.JSONDecodeError as error:
            fail(f"{entry_id} line {line_number} is not JSON: {error}")
        if record.get("direction") not in {"TX", "RX"}:
            fail(f"{entry_id} line {line_number} has invalid direction")
        for field in ("timestamp", "payload", "source"):
            if not isinstance(record.get(field), str) or not record[field]:
                fail(f"{entry_id} line {line_number} has invalid {field}")

    if not verify_source:
        continue
    source_root = Path(os.environ.get("LEGACY_PLOTTER_ROOT", manifest["source_repository"]["path"])).resolve()
    source_relative = entry.get("source_path")
    if not isinstance(source_relative, str) or Path(source_relative).is_absolute():
        fail(f"{entry_id} source_path must be repository-relative")
    source_path = (source_root / source_relative).resolve()
    try:
        source_path.relative_to(source_root)
    except ValueError:
        fail(f"{entry_id} source escapes the legacy repository")
    if not source_path.is_file():
        fail(f"{entry_id} source is missing: {source_path}")
    source_hash = sha256(source_path)
    if source_hash != entry.get("source_sha256"):
        fail(f"{entry_id} source hash is {source_hash}, expected {entry.get('source_sha256')}")

    derivation = entry.get("derivation")
    fixture_bytes = fixture_path.read_bytes()
    source_bytes = source_path.read_bytes()
    if derivation == "exact_copy" and fixture_bytes != source_bytes:
        fail(f"{entry_id} is declared exact_copy but differs from its source")
    if derivation == "exact_source_lines_1_through_15":
        expected = b"\n".join(source_bytes.splitlines()[:15]) + b"\n"
        if fixture_bytes != expected:
            fail(f"{entry_id} does not equal source lines 1 through 15")
    if str(derivation).startswith("exact_records_in_source_order_"):
        source_lines = source_bytes.splitlines()
        cursor = 0
        for fixture_line in fixture_bytes.splitlines():
            while cursor < len(source_lines) and source_lines[cursor] != fixture_line:
                cursor += 1
            if cursor == len(source_lines):
                fail(f"{entry_id} contains a record absent from the source in declared order")
            cursor += 1

mode = "fixtures and legacy sources" if verify_source else "fixtures"
print(f"validated {len(entries)} historical evidence entries ({mode})")
PY
