#!/usr/bin/env python3
"""Deterministic fixtures for the fail-closed Pilot continuation checker."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check_episode_pilot_gate.py")
SPEC = importlib.util.spec_from_file_location("check_episode_pilot_gate", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
pilot = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pilot)


class PilotGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self._write_fixture()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def _write(self, path: str, text: str) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")

    def _write_fixture(self) -> None:
        gates = {
            package: ["DOC"] for package in pilot.REQUIRED_PACKAGES
        }
        gates.update({
            "EA-01": ["INVENTORY"], "EA-02A": ["CORE"],
            "EA-02B": ["PLOTTER-MODEL"], "EA-05A": ["RECORDING"],
            "EA-05B": ["REPLAY"], "EA-05C": ["INCIDENT"],
            "FIX-02": ["LINK-OBS", "LINK-SAFETY"], "EA-06": ["MOTION", "DELETE"],
            "EA-07": ["SIM", "DELETE"], "EA-04": ["DELETE"],
            "EA-08A": ["DELETE"], "EA-08B": ["DELETE"],
            "EA-09": ["UI", "DELETE"],
            "FIX-03": ["DRAW-RUN", "TASK-METRIC", "DELETE", "DOC", "DIFF", "QUICK", "STRICT"],
        })
        ledger = [
            "| ID | Status | Dependencies | Class | Atomic package outcome | Required gates |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for package in pilot.REQUIRED_PACKAGES:
            dependencies = "none" if package == "DOC-00" else "DOC-00"
            gate_cell = ", ".join(f"`{gate}`" for gate in gates[package])
            ledger.append(f"| {package} | complete | {dependencies} | software | outcome | {gate_cell} |")
        ledger.append("| GATE-01 | pending | FIX-03 | gate | decision only | `DOC`, `DIFF`, `PILOT` |")
        inventory = [
            "| Inventory ID | Category | Current source seams | Current owner and behavior | Disposition | Cutover | Focused command |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        scans = [
            "| Package | Scan class | Paths | Zero-match literal |",
            "| --- | --- | --- | --- |",
        ]
        for index, package in enumerate(pilot.MIGRATED_CUTOVERS, 1):
            inventory.append(f"| OWN-{index:03d} | authority-owner | `Seam{index}` | owner | delete | `{package}` | `focused` |")
            scans.append(f"| `{package}` | deleted-symbol | `Sources/PlotterApp/*.swift` | `obsolete-{package}` |")
        plan = "\n".join(ledger + [""] + inventory + [""] + scans) + "\n"
        self._write(str(pilot.PLAN), plan)

        completion = [
            "| Package | Blackdog task | Gate results | Evidence section |",
            "| --- | --- | --- | --- |",
        ]
        sections: list[str] = []
        for package in pilot.REQUIRED_PACKAGES:
            result = ", ".join(f"`{gate}=passed`" for gate in gates[package])
            title = f"Evidence {package}"
            completion.append(f"| {package} | `TASK-A1` | {result} | {title} |")
            sections.extend([
                f"## {title}", "", "| Validation | Result | Scope |",
                "| --- | --- | --- |",
                *(f"| `{gate}` | passed — deterministic fixture | scope |" for gate in gates[package]),
                "",
            ])
        predicates = [
            "| Pilot predicate | Result | Evidence |",
            "| --- | --- | --- |",
            *(f"| {name} | passed | {', '.join(f'`{token}`' for token in tokens)} |" for name, tokens in pilot.PREDICATES.items()),
        ]
        metrics = [
            "| Reduction metric | Baseline | Current | Requirement |",
            "| --- | --- | --- | --- |",
            *(f"| {name} | 2 | 1 | {requirement} |" for name, requirement in pilot.METRICS.items()),
        ]
        self._write(str(pilot.EVIDENCE), "\n".join(completion + [""] + predicates + [""] + metrics + [""] + sections))

        self._write("Sources/EpisodeCore/Core.swift", "public protocol EpisodeValue: Sendable {}\n")
        self._write(
            "Sources/PlotterEpisodeModel/Model.swift",
            "struct PlotterIntent {}\nenum Environment { case live; case simulated }\n"
            "enum Evidence { case livePhysical; case simulatedCausal }\n",
        )
        self._write("Sources/PlotterRuntime/MachineController.swift", "public actor MachineController {}\n")
        self._write("Sources/PlotterRuntime/CameraCapture.swift", "public actor CameraCapture {}\n")
        self._write("Sources/PlotterApp/App.swift", "let current = true\n")

    def _replace(self, path: Path, old: str, new: str) -> None:
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def test_complete_consistent_fixture_passes(self) -> None:
        pilot.evaluate(self.root)

    def test_pending_landed_package_fails_closed(self) -> None:
        self._replace(self.root / pilot.PLAN, "| EA-09 | complete |", "| EA-09 | pending |")
        with self.assertRaisesRegex(pilot.GateError, "not complete"):
            pilot.evaluate(self.root)

    def test_missing_completion_evidence_fails_closed(self) -> None:
        self._replace(self.root / pilot.EVIDENCE, "| EA-09 | `TASK-A1` |", "| OMITTED | `TASK-A1` |")
        with self.assertRaisesRegex(pilot.GateError, "Current Evidence rows are absent"):
            pilot.evaluate(self.root)

    def test_failed_detailed_gate_fails_closed(self) -> None:
        self._replace(
            self.root / pilot.EVIDENCE,
            "| `UI` | passed — deterministic fixture |",
            "| `UI` | failed — deterministic fixture |",
        )
        with self.assertRaisesRegex(pilot.GateError, "not final passed evidence"):
            pilot.evaluate(self.root)

    def test_mismatched_predicate_link_fails_closed(self) -> None:
        self._replace(self.root / pilot.EVIDENCE, "`EA-05B/REPLAY`", "`EA-05A/RECORDING`")
        with self.assertRaisesRegex(pilot.GateError, "evidence mismatch"):
            pilot.evaluate(self.root)

    def test_dirty_dual_authority_scan_fails_closed(self) -> None:
        self._write("Sources/PlotterApp/Dirty.swift", "obsolete-EA-09\n")
        with self.assertRaisesRegex(pilot.GateError, "dual-authority"):
            pilot.evaluate(self.root)

    def test_absent_inventory_row_fails_closed(self) -> None:
        plan = (self.root / pilot.PLAN).read_text(encoding="utf-8")
        line = next(line for line in plan.splitlines() if "| `EA-09` | `focused` |" in line)
        (self.root / pilot.PLAN).write_text(plan.replace(line + "\n", "", 1), encoding="utf-8")
        with self.assertRaisesRegex(pilot.GateError, "lack inventory rows"):
            pilot.evaluate(self.root)

    def test_non_decreasing_authority_metric_fails_closed(self) -> None:
        self._replace(
            self.root / pilot.EVIDENCE,
            "| independent-admission-sites | 2 | 1 | decreased |",
            "| independent-admission-sites | 2 | 2 | decreased |",
        )
        with self.assertRaisesRegex(pilot.GateError, "did not decrease"):
            pilot.evaluate(self.root)


if __name__ == "__main__":
    unittest.main()
