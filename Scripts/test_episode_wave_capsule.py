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

    def replace_completed_result(
        self,
        result: str,
        *,
        section: str = "Episode incident package foundation",
        gate: str = "INCIDENT",
    ) -> None:
        evidence_path = self.root / "docs/CURRENT_EVIDENCE.md"
        lines = evidence_path.read_text(encoding="utf-8").splitlines()
        heading = f"## {section}"
        try:
            section_start = lines.index(heading)
        except ValueError as error:
            raise AssertionError(f"missing fixture section {heading}") from error
        for index in range(section_start + 1, len(lines)):
            line = lines[index]
            if line.startswith("## "):
                break
            if not line.startswith(f"| `{gate}` | "):
                continue
            cells = line.split("|")
            if len(cells) != 5:
                raise AssertionError(f"malformed fixture validation row: {line}")
            scope = cells[3].strip()
            lines[index] = f"| `{gate}` | {result} | {scope} |"
            evidence_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return
        raise AssertionError(f"missing fixture validation row for {gate}")

    def assert_completed_result_rejected(self, result: str, message: str) -> None:
        self.replace_completed_result(result)
        with self.assertRaisesRegex(ValueError, message):
            capsule.validated_contract(self.root, validate_live_gates=False)

    def test_real_current_evidence_is_accepted_by_production_contract(self) -> None:
        _contract, rows, _gates, blockers = capsule.validated_contract(
            self.root,
            validate_live_gates=False,
        )
        self.assertEqual("complete", rows["EA-05C"]["status"])
        self.assertEqual("complete", rows["EA-04"]["status"])
        self.assertEqual("complete", rows["FIX-02"]["status"])
        self.assertEqual("complete", rows["EA-06"]["status"])
        self.assertEqual("complete", rows["EA-07"]["status"])
        self.assertEqual("complete", rows["EA-08A"]["status"])
        self.assertEqual("complete", rows["EA-08B"]["status"])
        self.assertEqual("complete", rows["EA-09"]["status"])
        self.assertEqual("complete", rows["FIX-03"]["status"])
        self.assertEqual("complete", rows["DOC-03"]["status"])
        self.assertEqual("pending", rows["EA-10A"]["status"])
        self.assertEqual("pending", rows["GATE-01"]["status"])
        self.assertEqual({}, blockers)
        evidence = (self.root / "docs/CURRENT_EVIDENCE.md").read_text(encoding="utf-8")
        self.assertIn("Pilot dependency-cycle correction", evidence)
        self.assertIn("TASK-B7C9E592-3408edcef715", evidence)
        self.assertIn("Pre-GATE-01 Drawing Run task-owner correction", evidence)
        self.assertIn("exactly `drawingRunTask` removed", evidence)
        self.assertIn("TASK-0A7AB3EE-80f88f4a41d8", evidence)

    def test_completed_incident_evidence_missing_is_rejected(self) -> None:
        evidence_path = self.root / "docs/CURRENT_EVIDENCE.md"
        lines = evidence_path.read_text(encoding="utf-8").splitlines()
        lines = [
            line
            for line in lines
            if not line.startswith("| EA-05C | `TASK-1DDBA6F2` |")
        ]
        evidence_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        with self.assertRaisesRegex(
            ValueError,
            r"complete-package evidence mismatch; missing=\['EA-05C'\]",
        ):
            capsule.validated_contract(self.root, validate_live_gates=False)

    def test_completed_result_rejects_candidate_measurement(self) -> None:
        self.assert_completed_result_rejected(
            "passed — candidate measurement",
            "uncertain or deferred evidence word 'candidate'",
        )

    def test_completed_result_rejects_pending_validation(self) -> None:
        self.assert_completed_result_rejected(
            "passed — validation pending",
            "uncertain or deferred evidence word 'pending'",
        )

    def test_completed_result_rejects_other_uncertain_evidence(self) -> None:
        for result, word in (
            ("passed — provisional measurement", "provisional"),
            ("passed — validation deferred", "deferred"),
            ("passed — future validation", "future"),
        ):
            with self.subTest(result=result):
                self.assert_completed_result_rejected(
                    result,
                    f"uncertain or deferred evidence word '{word}'",
                )

    def test_completed_result_rejects_rerun_variants(self) -> None:
        for result in ("passed — rerun required", "passed — re-run required"):
            with self.subTest(result=result):
                self.replace_completed_result(result)
                with self.assertRaisesRegex(ValueError, "defers validation to a rerun"):
                    capsule.validated_contract(self.root, validate_live_gates=False)

    def test_completed_result_rejects_skipped(self) -> None:
        self.assert_completed_result_rejected(
            "passed — skipped",
            "reports skipped evidence as passed",
        )

    def test_completed_result_rejects_incomplete_states(self) -> None:
        for result in (
            "passed — validation incomplete",
            "passed — work unfinished",
            "passed — validation unverified",
            "passed — validation unvalidated",
            "passed — work blocked",
            "passed — work unresolved",
            "passed — validation not run",
            "passed — validation not-run",
            "passed — work not executed",
            "passed — work not-executed",
            "passed — work not performed",
            "passed — work not-performed",
        ):
            with self.subTest(result=result):
                self.assert_completed_result_rejected(
                    result,
                    "reports incomplete evidence state",
                )

    def test_completed_result_rejects_failed_forms(self) -> None:
        for result in (
            "passed — command failed",
            "passed — 1 failed",
            "passed — command 1.0 failed",
            "passed — command 0.0 failed",
            "passed — command 10 failed",
            "passed — command +0 failed",
            "passed — command -0 failed",
        ):
            with self.subTest(result=result):
                self.replace_completed_result(result)
                with self.assertRaisesRegex(ValueError, "explicit zero form `0 failed`"):
                    capsule.validated_contract(self.root, validate_live_gates=False)

    def test_completed_result_accepts_explicit_zero_failed(self) -> None:
        self.replace_completed_result("passed — command completed; 0 failed")
        _contract, rows, _gates, _blockers = capsule.validated_contract(
            self.root,
            validate_live_gates=False,
        )
        self.assertEqual("complete", rows["EA-05C"]["status"])

    def test_completed_result_rejects_nonzero_rc(self) -> None:
        self.assert_completed_result_rejected(
            "passed — rc=1",
            "reports nonzero rc 1 as passed",
        )

    def test_completed_result_rejects_standard_nonzero_forms(self) -> None:
        for result in (
            "passed — exit 1",
            "passed — exit code=1",
            "passed — exit code +1",
            "passed — status: 2",
            "passed — status +2",
            "passed — return code -1",
            "passed — rc=+1",
            "passed — explicit nonzero result",
            "passed — explicit non-zero result",
        ):
            with self.subTest(result=result):
                self.replace_completed_result(result)
                with self.assertRaisesRegex(ValueError, "nonzero"):
                    capsule.validated_contract(self.root, validate_live_gates=False)

    def test_completed_result_accepts_zero_result_codes(self) -> None:
        for result in (
            "passed — exit code 0",
            "passed — exit code +0",
            "passed — status -0",
            "passed — rc=+0",
            "passed — exit +0, no output",
            "passed — status -0; command completed",
            "passed — return code +0.",
            "passed — rc=-0) command completed",
        ):
            with self.subTest(result=result):
                self.replace_completed_result(result)
                _contract, rows, _gates, _blockers = capsule.validated_contract(
                    self.root,
                    validate_live_gates=False,
                )
                self.assertEqual("complete", rows["EA-05C"]["status"])

    def test_completed_result_rejects_malformed_numeric_tokens(self) -> None:
        for result in (
            "passed — status +0.1",
            "passed — return code -0.5",
            "passed — exit 0.0",
            "passed — rc=0e1",
            "passed — exit code 0x0",
            "passed — status 0done",
        ):
            with self.subTest(result=result):
                self.assert_completed_result_rejected(
                    result,
                    "malformed numeric .* token",
                )

    def test_uncertain_historical_prose_outside_result_cells_is_accepted(self) -> None:
        evidence_path = self.root / "docs/CURRENT_EVIDENCE.md"
        evidence = evidence_path.read_text(encoding="utf-8")
        marker = "# AdaptivePlotter Current Evidence\n"
        historical_prose = (
            "\nHistorical prose outside a detailed Result cell may say candidate, "
            "provisional, pending, awaiting, awaits, deferred, defers, future, "
            "follows, will follow, not yet, not happened, exit code=9, status: 2, "
            "return code -1, exit code +1, status +2, rc=+1, nonzero, non-zero, "
            "rerun, re-run, skipped, incomplete, unfinished, unverified, "
            "unvalidated, blocked, unresolved, not run, not-run, not executed, "
            "not-executed, not performed, not-performed, command failed, "
            "1 failed, 0 failed, status +0.1, return code -0.5, exit 0.0, "
            "rc=0e1, exit code 0x0, or status 0done without certifying a gate.\n"
        )
        self.assertIn(marker, evidence)
        evidence_path.write_text(
            evidence.replace(marker, marker + historical_prose, 1),
            encoding="utf-8",
        )
        _contract, rows, _gates, _blockers = capsule.validated_contract(
            self.root,
            validate_live_gates=False,
        )
        self.assertEqual("complete", rows["EA-05C"]["status"])

    def test_fresh_capsule_round_trip_is_bounded_and_points_to_exact_contract(self) -> None:
        created = self.build_and_write()
        consumed = self.consume()
        self.assertEqual(created, consumed)
        self.assertEqual("selected", consumed["contract"]["frontier"]["state"])
        self.assertEqual("EA-10A", consumed["contract"]["package"]["id"])
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
        ledger_rows = []
        for selected in selected_rows:
            selected_text = (
                (self.root / selected["path"])
                .read_text(encoding="utf-8")
                .splitlines()[selected["start_line"] - 1]
            )
            row = [cell.strip() for cell in selected_text.strip().strip("|").split("|")]
            if (
                len(row) == 6
                and row[:4] == ["EA-10A", "pending", "DOC-03", "software"]
                and row[4].startswith("Cutover: transfer Pen Interaction")
                and row[5] == "`DOC`, `DIFF`, `QUICK`, `STRICT`, `PEN`, `DELETE`"
            ):
                ledger_rows.append((selected, row))
        self.assertEqual(1, len(ledger_rows))
        selected, selected_row = ledger_rows[0]
        self.assertEqual("EA-10A", selected_row[0])
        self.assertNotEqual("FIX-02", selected_row[0])
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
            "| EA-10A | DOC-03 landing is not reconciled | "
            "Land DOC-03 and generate the canonical successor capsule |\n"
        )
        self.assertIn(table, evidence)
        evidence_path.write_text(evidence.replace(table, blocked_table, 1), encoding="utf-8")
        self.commit_fixture_change("record evidence blocker")

        created = self.build_and_write()

        self.assertEqual("evidence_blocked", created["launch"]["state"])
        self.assertEqual("EA-10A", created["contract"]["frontier"]["package_id"])
        self.assertEqual(
            "DOC-03 landing is not reconciled",
            created["contract"]["frontier"]["blocker"]["blocker"],
        )
        self.assertNotEqual("GATE-01", created["contract"]["frontier"]["package_id"])

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
            "GATE-01": {"status": "complete", "class": "gate", "dependencies": ["EA-11C"]},
            "VAL-01": {"status": "pending", "class": "attended-physical", "dependencies": ["GATE-01"]},
        }
        result = capsule.contract_frontier(rows, None)
        self.assertEqual({"state": "authorization_boundary", "package_id": "VAL-01", "incomplete_dependencies": []}, result)


if __name__ == "__main__":
    unittest.main()
