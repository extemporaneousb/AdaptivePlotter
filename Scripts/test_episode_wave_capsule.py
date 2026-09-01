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
        self.task_shows: dict[str, dict[str, object]] = {}
        self.path = self.root / ".VE/run-multi-agent-wave/launch-capsule.json"

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def build_and_write(self, summary: dict[str, object] | None = None) -> dict[str, object]:
        value = capsule.build_capsule(
            self.root,
            self.summary if summary is None else summary,
            validate_live_gates=False,
            task_show_loader=self.task_show,
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
            task_show_loader=self.task_show,
        )

    def task_show(self, _root: Path, task: dict[str, object]) -> dict[str, object]:
        task_id = task.get("task_id")
        if not isinstance(task_id, str) or task_id not in self.task_shows:
            raise capsule.CapsuleError("fixture task show is unavailable")
        return self.task_shows[task_id]

    def terminal_task(
        self,
        task_id: str,
        package_id: str,
        *,
        replay_available: bool = True,
        dependency_ready: bool = False,
        retained_owner: bool = False,
    ) -> dict[str, object]:
        workset = f"fixture-{task_id.lower()}"
        digest = f"{len(self.task_shows) + 1:064x}"
        replay = f"prompts/sha256/{digest}.txt"
        if replay_available:
            path = self.root / ".git/blackdog" / replay
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(
                f"AdaptivePlotter episode WorkPackage: {package_id}\n",
                encoding="utf-8",
            )
        self.task_shows[task_id] = {
            "task_id": task_id,
            "attempt_status": "blocked",
            "active_attempt": False,
            "active_workspace_adoption": False,
            "worktree_exists": False,
            "branch_exists": False,
            "task_claim": {"owner": "retained"} if retained_owner else None,
            "workset_claim": None,
            "terminal_cleanup_complete": True,
            "stale_claim_release_pending": False,
            "close_transaction_pending": False,
            "runtime_transition_pending": False,
            "landing_transaction_incomplete": False,
            "target_stale_claim_release_pending": False,
            "execution_prompt_replay_artifact_path": replay,
        }
        return {
            "task_id": task_id,
            "task_ref": f"{workset}/{task_id}",
            "readiness": "blocked",
            "runtime_status": "blocked",
            "latest_attempt_status": "blocked",
            "claim_actor": None,
            "active_attempt_id": None,
            "dependency_ready": dependency_ready,
        }

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
        contract, rows, _gates, blockers = capsule.validated_contract(
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
        self.assertEqual("complete", rows["DOC-04"]["status"])
        self.assertEqual("complete", rows["EA-10A"]["status"])
        self.assertEqual("complete", rows["EA-10B"]["status"])
        self.assertEqual("complete", rows["FIX-05"]["status"])
        self.assertEqual("complete", rows["GATE-01"]["status"])
        self.assertEqual("pending", rows["VAL-01"]["status"])
        self.assertEqual({}, blockers)
        self.assertEqual("complete", rows["TRANCHE-LEARNING"]["status"])
        for slice_id in contract.TRANCHE_SLICES["TRANCHE-LEARNING"]:
            self.assertEqual("complete", rows[slice_id]["status"])
        self.assertEqual("complete", rows["TRANCHE-DEVICE-ENVIRONMENT"]["status"])
        for slice_id in contract.TRANCHE_SLICES["TRANCHE-DEVICE-ENVIRONMENT"]:
            self.assertEqual("complete", rows[slice_id]["status"])
        self.assertEqual("complete", rows["TRANCHE-FINAL-COMPOSITION"]["status"])
        self.assertEqual("complete", rows["EA-11C"]["status"])
        self.assertEqual("authority-slice", rows["EA-10G"]["class"])
        self.assertEqual("authority-slice", rows["EA-10C"]["class"])
        evidence = (self.root / "docs/CURRENT_EVIDENCE.md").read_text(encoding="utf-8")
        self.assertIn("Drawing Boundary episode cutover completion candidate", evidence)
        self.assertIn("TASK-6DAB256F", evidence)
        self.assertIn("18/18 passed; tests 0.125 seconds", evidence)
        self.assertIn("migrated Boundary operator-path filters; 13/13 passed", evidence)
        self.assertIn("boundaryStopCompletesTransaction`; 1/1 passed; tests 0.111 seconds", evidence)
        self.assertIn("activeBoundaryHasOnlyStop`; 1/1 passed; tests 0.116 seconds", evidence)
        self.assertIn("centerArrivalAcceptsQuantizedSettlement`; 1/1 passed; tests 0.105 seconds", evidence)
        self.assertIn("OperatorWorkspaceComputationDiagnosticsTests`; 9/9 passed", evidence)
        self.assertIn("OperatorWorkspaceSparseTipCalibrationTests`; 8/8 passed", evidence)
        self.assertIn("PlotterDrawingRunEpisodeTests`; 13/13 passed", evidence)
        self.assertIn("773/773 passed; tests 13.957 seconds; real 15.41 seconds", evidence)
        self.assertIn("5/5 passed; tests 4.916 seconds; real 6.05 seconds", evidence)
        self.assertIn("contracts plus 29/29 passed; tests 12.694 seconds; real 13.49 seconds", evidence)
        self.assertIn("778/778 Swift tests in 14.540 seconds plus docs 29/29 in 23.453 seconds", evidence)
        self.assertIn("EA-10B is semantically complete as a task-local landing candidate", evidence)
        self.assertIn("strict production build then passed in 29.97", evidence)
        self.assertIn("772/773 in\n`shutdownDoesNotReviveAcceptedClick`", evidence)
        self.assertIn("Pen-cap suite passed 17/17", evidence)
        self.assertIn("intermediate 771/773 nonpass", evidence)
        self.assertIn("same critic's bounded-delta pass", evidence)
        self.assertIn("composition-only `UI.announceBoundaryAdvisory` adapter", evidence)
        self.assertIn("adapter owns no\nannouncement, effect, Stop, settlement, evidence, controller, or UI authority", evidence)
        self.assertIn("EA-10B is semantically complete as a task-local landing candidate", evidence)
        self.assertIn("EA-10C is not selected or\ndispatched", evidence)
        self.assertIn("Pen Interaction episode cutover completion candidate", evidence)
        self.assertIn("TASK-539931AC-49f2e7307f76", evidence)
        self.assertIn("exit 0; 13/13 passed", evidence)
        self.assertIn("UNANIMOUS PASS — no material disagreement", evidence)
        self.assertIn("755 tests, 753 passed and 2 failed with 9 issues", evidence)
        self.assertIn(
            "Exact Pen Stop now settles the already-admitted\n"
            "EA-04 point-selection continuation before Pen terminal settlement",
            evidence,
        )
        self.assertIn("no generic Cancel fallback or parallel authority was added", evidence)
        self.assertIn("accepted-click filter built in 9.80 seconds", evidence)
        self.assertIn("recovery-transition filter built in\n0.28 seconds", evidence)
        self.assertIn(
            "The next final retry passed `DOC` 29/29, clean `DIFF`, `QUICK` 755/755",
            evidence,
        )
        self.assertIn(
            "after a 74.52-second build, 12/13 passed",
            evidence,
        )
        self.assertIn("Production Stop was not returning\nprematurely", evidence)
        self.assertIn("PenInteractionCancellationPublicationProbe", evidence)
        self.assertIn(
            "The exact test passes three\nserial repeats: 1/1 with build/test 12.36/0.004 seconds",
            evidence,
        )
        self.assertIn(
            "The full focused `PEN` suite passes\n13/13 with build 0.23 seconds and suite 0.763 seconds",
            evidence,
        )
        self.assertIn("documentation and architecture contracts plus 29/29 checker tests passed", evidence)
        self.assertIn("755/755 tests passed in 14.270 seconds", evidence)
        self.assertIn("full 762/762 tests passed in 16.462 seconds", evidence)
        self.assertIn("all 8 exact scans had zero matches in 0.109 seconds", evidence)
        self.assertIn("`.drainingSetpoint`", evidence)
        self.assertIn(
            "EA-10A is semantically complete as a task-local landing candidate",
            evidence,
        )
        self.assertIn("EA-10B is not selected or dispatched", evidence)
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
        self.assertEqual("authorization_boundary", consumed["launch"]["state"])
        self.assertEqual("authorization_boundary", consumed["contract"]["frontier"]["state"])
        self.assertEqual("VAL-01", consumed["contract"]["package"]["id"])
        self.assertEqual(0o600, stat.S_IMODE(self.path.stat().st_mode))
        purposes = {item["purpose"] for item in consumed["pointers"]}
        self.assertIn("required gate catalog row", purposes)
        self.assertIn("prompt compilation protocol", purposes)
        self.assertIn("target package topology", purposes)
        self.assertIn("observability authority", purposes)
        self.assertIn("package vocabulary authority", purposes)
        self.assertIn("preserved product boundary", purposes)
        self.assertIn("current package topology", purposes)
        boundary_rows = [
            item for item in consumed["pointers"]
            if item["purpose"] == "selected package contract row"
        ]
        ledger_rows = []
        for boundary in boundary_rows:
            boundary_text = (
                (self.root / boundary["path"])
                .read_text(encoding="utf-8")
                .splitlines()[boundary["start_line"] - 1]
            )
            row = [cell.strip() for cell in boundary_text.strip().strip("|").split("|")]
            if (
                len(row) == 6
                and row[:4] == ["VAL-01", "pending", "FIX-06", "attended-physical"]
                and row[4].startswith("On the exact migrated signed build")
                and "`PHYSICAL-FINAL`" in row[5]
            ):
                ledger_rows.append((boundary, row))
        self.assertEqual(1, len(ledger_rows))
        _boundary, boundary_row = ledger_rows[0]
        self.assertEqual("VAL-01", boundary_row[0])
        self.assertNotEqual("FIX-06", boundary_row[0])
        self.assertEqual([], consumed["contract"]["ordered_authority_slices"])
        self.assertNotIn("authority slice current-owner inventory row", purposes)
        self.assertNotIn("authority slice same-landing deletion scan row", purposes)
        view = capsule.canonical_bytes(capsule.consumption_view(consumed))
        self.assertLess(len(view), capsule.MAX_CONSUMPTION_BYTES)

    def test_completed_fix06_restores_val01_authorization_boundary(self) -> None:
        created = self.build_and_write()

        self.assertEqual("authorization_boundary", created["launch"]["state"])
        self.assertEqual("authorization_boundary", created["contract"]["frontier"]["state"])
        self.assertEqual("VAL-01", created["contract"]["frontier"]["package_id"])
        self.assertEqual([], created["contract"]["ordered_authority_slices"])
        self.assertNotEqual("FIX-06", created["contract"]["frontier"]["package_id"])

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

    def test_claimed_and_retained_terminal_owners_remain_live_blockers(self) -> None:
        claimed = {
            "tasks": [
                {
                    "task_id": "TASK-CLAIMED",
                    "task_ref": "fixture-claimed/TASK-CLAIMED",
                    "readiness": "blocked",
                    "runtime_status": "blocked",
                    "latest_attempt_status": "blocked",
                    "claim_actor": "codex",
                    "active_attempt_id": None,
                }
            ]
        }
        created = self.build_and_write(claimed)
        self.assertEqual("claim_resolution", created["launch"]["state"])
        self.assertEqual("TASK-CLAIMED", created["blackdog"]["live_blockers"][0]["task_id"])

        retained = self.terminal_task("TASK-RETAINED", "GATE-01", retained_owner=True)
        created = self.build_and_write({"tasks": [retained]})
        self.assertEqual("claim_resolution", created["launch"]["state"])
        self.assertEqual("TASK-RETAINED", created["blackdog"]["live_blockers"][0]["task_id"])

        finalization = self.terminal_task("TASK-FINALIZE", "GATE-01")
        self.task_shows["TASK-FINALIZE"]["close_transaction_pending"] = True
        created = self.build_and_write({"tasks": [finalization]})
        self.assertEqual("claim_resolution", created["launch"]["state"])
        self.assertEqual("TASK-FINALIZE", created["blackdog"]["live_blockers"][0]["task_id"])

    def test_removed_and_dependency_ineligible_terminal_history_is_visible_but_nonblocking(self) -> None:
        removed = self.terminal_task("TASK-REMOVED", "FIX-99")
        completed = self.terminal_task("TASK-COMPLETED", "FIX-05")
        ineligible = self.terminal_task("TASK-INELIGIBLE", "VAL-01")
        created = self.build_and_write({"tasks": [removed, completed, ineligible]})

        self.assertEqual("authorization_boundary", created["launch"]["state"])
        self.assertEqual("VAL-01", created["contract"]["frontier"]["package_id"])
        self.assertEqual([], created["blackdog"]["live_blockers"])
        self.assertEqual(
            [
                {"task_id": "TASK-COMPLETED", "package_id": "FIX-05", "disposition": "dependency-ineligible-package"},
                {"task_id": "TASK-INELIGIBLE", "package_id": "VAL-01", "disposition": "dependency-ineligible-package"},
                {"task_id": "TASK-REMOVED", "package_id": "FIX-99", "disposition": "removed-package"},
            ],
            created["blackdog"]["terminal_history"],
        )
        self.assertEqual(created, self.consume({"tasks": [removed, completed, ineligible]}))

    def test_current_eligible_or_unverifiable_terminal_history_fails_closed(self) -> None:
        recoverable = self.terminal_task("TASK-RECOVERABLE", "GATE-01")
        rows = {
            "FIX-05": {"status": "complete", "class": "repository", "dependencies": []},
            "GATE-01": {"status": "pending", "class": "gate", "dependencies": ["FIX-05"]},
        }
        live_blockers, terminal_history = capsule.classify_blackdog_claims(
            self.root,
            {"tasks": [recoverable]},
            rows,
            self.task_show,
        )
        self.assertEqual("TASK-RECOVERABLE", live_blockers[0]["task_id"])
        self.assertEqual([], terminal_history)

        unverifiable = self.terminal_task("TASK-UNKNOWN", "GATE-01", replay_available=False)
        created = self.build_and_write({"tasks": [unverifiable]})
        self.assertEqual("claim_resolution", created["launch"]["state"])
        self.assertEqual("TASK-UNKNOWN", created["blackdog"]["live_blockers"][0]["task_id"])

    def test_rehashed_terminal_history_tampering_is_rejected_against_live_classification(self) -> None:
        history = self.terminal_task("TASK-REMOVED", "FIX-99")
        created = self.build_and_write({"tasks": [history]})
        created["blackdog"]["terminal_history"][0]["package_id"] = "GATE-01"
        created.pop("payload_sha256")
        created["payload_sha256"] = capsule.sha256_bytes(capsule.canonical_bytes(created))
        self.rewrite(created)
        with self.assertRaisesRegex(capsule.CapsuleError, "capsule is stale"):
            self.consume({"tasks": [history]})

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

    def test_rehashed_selected_gate_tampering_is_rejected_against_current_contract(self) -> None:
        created = self.build_and_write()
        created["contract"]["expanded_gates"][0]["procedure"] = "tampered"
        created.pop("payload_sha256")
        created["payload_sha256"] = capsule.sha256_bytes(capsule.canonical_bytes(created))
        self.rewrite(created)
        with self.assertRaisesRegex(capsule.CapsuleError, "capsule is stale"):
            self.consume()

    def test_completed_tranche_requires_one_common_task_landing(self) -> None:
        contract = capsule.import_contract(self.root)
        plan = (self.root / "docs/EPISODE_ARCHITECTURE_EXECUTION_PLAN.md").read_text(encoding="utf-8")
        evidence = (self.root / "docs/CURRENT_EVIDENCE.md").read_text(encoding="utf-8")
        rows = contract.validate_plan(plan)
        rows = {package_id: dict(row) for package_id, row in rows.items()}
        tranche_id = "TRANCHE-DEVICE-ENVIRONMENT"
        slices = contract.TRANCHE_SLICES[tranche_id]
        rows[tranche_id]["status"] = "complete"
        for slice_id in slices:
            rows[slice_id]["status"] = "complete"
        contract.validate_tranche_landing_evidence(evidence, rows)

        mismatched = evidence.replace(
            "| EA-11B | `TASK-4C16F56F` |",
            "| EA-11B | `TASK-OTHER` |",
        )
        with self.assertRaisesRegex(ValueError, "one common Blackdog landing"):
            contract.validate_tranche_landing_evidence(mismatched, rows)

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
