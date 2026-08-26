#!/usr/bin/env python3
"""Behavioral tests for the hash-bound episode-wave launch capsule."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SOURCE_ROOT = Path(__file__).resolve().parent.parent
MODULE_PATH = SOURCE_ROOT / "Scripts/episode_wave_capsule.py"
SPEC = importlib.util.spec_from_file_location("episode_wave_capsule", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
capsule = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(capsule)


def git(root: Path, *arguments: str) -> str:
    result = subprocess.run(
        ["git", *arguments],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


class EpisodeWaveCapsuleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="episode-wave-capsule-test-")
        self.root = Path(self.temporary.name) / "repo"
        self.root.mkdir()
        for relative in capsule.AUTHORITY_PATHS:
            source = SOURCE_ROOT / relative
            destination = self.root / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
        git(self.root, "init", "-b", "main")
        git(self.root, "config", "user.email", "capsule-test@example.invalid")
        git(self.root, "config", "user.name", "Capsule Test")
        git(self.root, "add", ".")
        git(self.root, "commit", "-m", "fixture")
        git(self.root, "update-ref", "refs/remotes/origin/main", "HEAD")
        self.summary: dict[str, object] = {"tasks": []}
        self.path = self.root / ".VE/run-multi-agent-wave/launch-capsule.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def build_and_write(self, summary: dict[str, object] | None = None) -> dict[str, object]:
        value = capsule.build_capsule(
            self.root,
            self.summary if summary is None else summary,
            validate_live_gates=False,
        )
        capsule.atomic_write_capsule(self.path, value)
        return value

    def consume(self, summary: dict[str, object] | None = None) -> dict[str, object]:
        value = self.summary if summary is None else summary
        return capsule.consume_capsule(
            self.root,
            self.path,
            lambda _root: value,
            validate_live_gates=False,
        )

    def rewrite(self, value: dict[str, object]) -> None:
        self.path.write_bytes(capsule.canonical_bytes(value) + b"\n")
        os.chmod(self.path, 0o600)

    def commit_fixture_change(self, message: str) -> None:
        git(self.root, "add", ".")
        git(self.root, "commit", "-m", message)
        git(self.root, "update-ref", "refs/remotes/origin/main", "HEAD")

    def test_fresh_capsule_round_trip_is_bounded_and_points_to_exact_contract(self) -> None:
        created = self.build_and_write()
        consumed = self.consume()
        self.assertEqual(created, consumed)
        self.assertEqual("selected", consumed["contract"]["frontier"]["state"])
        self.assertEqual("EA-03A", consumed["contract"]["package"]["id"])
        self.assertEqual(0o600, stat.S_IMODE(self.path.stat().st_mode))
        purposes = {item["purpose"] for item in consumed["pointers"]}
        self.assertIn("required gate catalog row", purposes)
        self.assertIn("prompt compilation protocol", purposes)
        self.assertIn("target package topology", purposes)
        self.assertIn("observability authority", purposes)
        self.assertIn("package vocabulary authority", purposes)
        self.assertIn("preserved product boundary", purposes)
        self.assertIn("current package topology", purposes)
        selected_rows = [
            item for item in consumed["pointers"]
            if item["purpose"] == "selected package contract row"
        ]
        self.assertEqual(1, len(selected_rows))
        selected = selected_rows[0]
        selected_text = (self.root / selected["path"]).read_text(encoding="utf-8").splitlines()[
            selected["start_line"] - 1
        ]
        self.assertTrue(selected_text.startswith("| EA-03A |"))
        self.assertNotIn("| EA-03B |", selected_text)
        view = capsule.canonical_bytes(capsule.consumption_view(consumed))
        self.assertLess(len(view), capsule.MAX_CONSUMPTION_BYTES)

    def test_current_evidence_blocker_stops_at_first_eligible_package(self) -> None:
        evidence_path = self.root / "docs/CURRENT_EVIDENCE.md"
        evidence = evidence_path.read_text(encoding="utf-8")
        table = (
            "| Package | Blocker | Required input or canonical correction |\n"
            "| --- | --- | --- |\n"
        )
        blocked_table = table + (
            "| EA-03A | Required design authority is unresolved | "
            "Record the operator decision in canonical authority |\n"
        )
        self.assertIn(table, evidence)
        evidence_path.write_text(evidence.replace(table, blocked_table, 1), encoding="utf-8")
        self.commit_fixture_change("record evidence blocker")

        created = self.build_and_write()

        self.assertEqual("evidence_blocked", created["launch"]["state"])
        self.assertEqual("EA-03A", created["contract"]["frontier"]["package_id"])
        self.assertEqual(
            "Required design authority is unresolved",
            created["contract"]["frontier"]["blocker"]["blocker"],
        )
        self.assertNotEqual("EA-03B", created["contract"]["frontier"]["package_id"])

    def test_contract_import_does_not_emit_bytecode_into_clean_repository(self) -> None:
        cache_path = self.root / "Scripts/__pycache__"
        self.assertFalse(cache_path.exists())
        previous_bytecode_policy = sys.dont_write_bytecode
        try:
            sys.dont_write_bytecode = False
            capsule.import_contract(self.root)
        finally:
            sys.dont_write_bytecode = previous_bytecode_policy
        self.assertFalse(cache_path.exists())

    def test_active_claim_requires_claim_resolution_without_exposing_intent(self) -> None:
        summary = {
            "tasks": [
                {
                    "task_id": "TASK-ABC12345",
                    "task_ref": "workset/TASK-ABC12345",
                    "readiness": "in_progress",
                    "runtime_status": "in_progress",
                    "latest_attempt_status": "in_progress",
                    "claim_actor": "codex",
                    "intent": "must not be copied into the capsule",
                }
            ]
        }
        created = self.build_and_write(summary)
        self.assertEqual("claim_resolution", created["launch"]["state"])
        self.assertNotIn(b"must not be copied", capsule.canonical_bytes(created))
        self.assertEqual(created, self.consume(summary))

    def test_payload_tampering_is_rejected(self) -> None:
        created = self.build_and_write()
        created["contract"]["package"]["id"] = "EA-11C"
        self.rewrite(created)
        with self.assertRaisesRegex(capsule.CapsuleError, "payload digest mismatch"):
            self.consume()

    def test_rehashed_semantic_tampering_is_rejected_against_current_contract(self) -> None:
        created = self.build_and_write()
        created["contract"]["package"]["id"] = "EA-11C"
        created.pop("payload_sha256")
        created["payload_sha256"] = capsule.sha256_bytes(capsule.canonical_bytes(created))
        self.rewrite(created)
        with self.assertRaisesRegex(capsule.CapsuleError, "capsule is stale"):
            self.consume()

    def test_changed_head_is_rejected(self) -> None:
        self.build_and_write()
        marker = self.root / "head-marker.txt"
        marker.write_text("new head\n", encoding="utf-8")
        git(self.root, "add", "head-marker.txt")
        git(self.root, "commit", "-m", "advance head")
        with self.assertRaisesRegex(capsule.CapsuleError, "capsule is stale"):
            self.consume()

    def test_dirty_authority_is_rejected(self) -> None:
        self.build_and_write()
        with (self.root / "docs/INDEX.md").open("a", encoding="utf-8") as handle:
            handle.write("\nchanged\n")
        with self.assertRaisesRegex(capsule.CapsuleError, "empty git status"):
            self.consume()

    def test_schema_mismatch_is_rejected(self) -> None:
        created = self.build_and_write()
        created["schema"] = "unknown"
        created.pop("payload_sha256")
        created["payload_sha256"] = capsule.sha256_bytes(capsule.canonical_bytes(created))
        self.rewrite(created)
        with self.assertRaisesRegex(capsule.CapsuleError, "schema mismatch"):
            self.consume()

    def test_insecure_permissions_are_rejected(self) -> None:
        self.build_and_write()
        os.chmod(self.path, 0o644)
        with self.assertRaisesRegex(capsule.CapsuleError, "mode 0600"):
            self.consume()

    def test_symlink_capsule_is_rejected(self) -> None:
        self.build_and_write()
        target = self.root / "capsule-copy.json"
        shutil.copy2(self.path, target)
        self.path.unlink()
        self.path.symlink_to(target)
        with self.assertRaisesRegex(capsule.CapsuleError, "non-symlink"):
            self.consume()

    def test_changed_claim_set_is_rejected(self) -> None:
        self.build_and_write()
        summary = {
            "tasks": [
                {
                    "task_id": "TASK-ABC12345",
                    "task_ref": "workset/TASK-ABC12345",
                    "readiness": "in_progress",
                    "runtime_status": "in_progress",
                    "latest_attempt_status": "in_progress",
                    "claim_actor": "codex",
                }
            ]
        }
        with self.assertRaisesRegex(capsule.CapsuleError, "capsule is stale"):
            self.consume(summary)

    def test_oversized_claim_field_is_rejected(self) -> None:
        summary = {
            "tasks": [
                {
                    "task_id": "TASK-ABC12345",
                    "task_ref": "x" * (capsule.MAX_CLAIM_FIELD_CHARACTERS + 1),
                    "readiness": "in_progress",
                }
            ]
        }
        with self.assertRaisesRegex(capsule.CapsuleError, "unbounded field"):
            capsule.build_capsule(self.root, summary, validate_live_gates=False)

    def test_authorization_boundary_is_not_selected(self) -> None:
        rows = {
            "EA-11C": {"status": "complete", "class": "software", "dependencies": []},
            "VAL-01": {"status": "pending", "class": "attended-physical", "dependencies": ["EA-11C"]},
        }
        result = capsule.contract_frontier(rows, None)
        self.assertEqual({"state": "authorization_boundary", "package_id": "VAL-01", "incomplete_dependencies": []}, result)


if __name__ == "__main__":
    unittest.main()
