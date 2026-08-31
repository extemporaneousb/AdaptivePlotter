#!/usr/bin/env python3
"""Regression fixtures for the fail-closed Pilot source metric manifests."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check_episode_pilot_metrics.py")
SPEC = importlib.util.spec_from_file_location("check_episode_pilot_metrics", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
metrics = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = metrics
SPEC.loader.exec_module(metrics)


def render(symbols: list[metrics.Symbol]) -> dict[str, str]:
    grouped: dict[str, dict[str, dict[str, set[str]]]] = {}
    for symbol in symbols:
        grouped.setdefault(symbol.path, {}).setdefault(
            symbol.container, {"func": set(), "case": set(), "property": set(), "closure": set()}
        )[symbol.kind].add(symbol.member)
    files: dict[str, str] = {}
    for path, containers in grouped.items():
        declarations: list[str] = []
        for container, members in containers.items():
            if container == "PlotterUIIntentSink":
                kind = "protocol"
            elif members["case"]:
                kind = "enum"
            else:
                kind = "final class" if container in {
                    "OperatorWorkspace", "PlotterApplicationRuntime"
                } else "struct"
            lines = [f"{kind} {container} {{"]
            for name in sorted(members["case"]):
                lines.append(f"  case {name}")
            for name in sorted(members["func"]):
                lines.append(f"  func {name}() {{}}")
            for name in sorted(members["property"]):
                if name.endswith("Task"):
                    lines.append(f"  private var {name}: Task<Void, Never>?")
                else:
                    lines.append(f"  private let {name}: FixtureValue")
            for name in sorted(members["closure"]):
                if name == "captureStableWorkflowCap":
                    lines.append(f"  let {name}: StableWorkflowCapCaptureRunner")
                else:
                    lines.append(f"  let {name}: @Sendable () async -> Void")
            lines.append("}")
            declarations.append("\n".join(lines))
        files[path] = "\n\n".join(declarations) + "\n"
    return files


def all_baseline_symbols() -> list[metrics.Symbol]:
    return [
        *(symbol for family in metrics.BASELINE_ADMISSION_FAMILIES for symbol in family.members),
        *metrics.BASELINE_TASKS,
        *(symbol for family in metrics.BASELINE_ENVIRONMENT_FAMILIES for symbol in family.members),
        *metrics.BASELINE_DIRECT_EFFECTS,
        *metrics.BASELINE_POLICY_STATE,
        *metrics.BASELINE_ADAPTERS,
    ]


def all_current_symbols() -> list[metrics.Symbol]:
    return [
        *(symbol for family in metrics.CURRENT_ADMISSION_FAMILIES for symbol in family.members),
        *metrics.CURRENT_POLICY_STATE,
        *metrics.CURRENT_ADAPTERS,
    ]


def exact_fixtures() -> tuple[dict[str, str], dict[str, str]]:
    baseline = render(all_baseline_symbols())
    current = render(all_current_symbols())
    # The real root retains a projection selector, but it is not a parallel
    # workflow/effect-owner family and therefore is explicitly excluded.
    current[metrics.OPERATOR] = current[metrics.OPERATOR].replace(
        "final class PlotterApplicationRuntime {",
        "final class PlotterApplicationRuntime {\n  var frameMode: FixtureValue",
        1,
    )
    return baseline, current


class PilotMetricManifestTests(unittest.TestCase):
    def test_exact_source_identity_manifests_pass(self) -> None:
        baseline, current = exact_fixtures()
        results = metrics.evaluate_bundles(baseline, current)
        self.assertEqual(
            {name: (len(value.baseline), len(value.current)) for name, value in results.items()},
            {name: values[:2] for name, values in metrics.EXPECTED_COUNTS.items()},
        )

    def test_pinned_family_member_removal_fails(self) -> None:
        baseline, current = exact_fixtures()
        baseline[metrics.OPERATOR] = baseline[metrics.OPERATOR].replace(
            "  func requestJog() {}\n", "", 1
        )
        with self.assertRaisesRegex(metrics.MetricError, "source identity is absent"):
            metrics.evaluate_bundles(baseline, current)

    def test_public_sink_capability_addition_and_removal_fail(self) -> None:
        baseline, current = exact_fixtures()
        added = dict(current)
        added[metrics.UI_SINK] = added[metrics.UI_SINK].replace(
            "protocol PlotterUIIntentSink {",
            "protocol PlotterUIIntentSink {\n  func submitCompatibilityRequest() {}",
            1,
        )
        with self.assertRaisesRegex(metrics.MetricError, "capability set changed"):
            metrics.evaluate_bundles(baseline, added)

        removed = dict(current)
        removed[metrics.UI_SINK] = removed[metrics.UI_SINK].replace(
            "  func submitPlotterUIRequest() {}\n", "", 1
        )
        with self.assertRaisesRegex(metrics.MetricError, "source identity is absent"):
            metrics.evaluate_bundles(baseline, removed)

    def test_replacement_workspace_task_fails(self) -> None:
        baseline, current = exact_fixtures()
        current["Sources/PlotterApp/LegacyEscape.swift"] = (
            "final class OperatorWorkspace {\n"
            "  private var replacementTask: Task<Void, Never>?\n"
            "}\n"
        )
        with self.assertRaisesRegex(metrics.MetricError, "workspace-task-owners identity/count drift"):
            metrics.evaluate_bundles(baseline, current)

    def test_environment_family_reintroduction_fails(self) -> None:
        baseline, current = exact_fixtures()
        current[metrics.OPERATOR] = current[metrics.OPERATOR].replace(
            "final class PlotterApplicationRuntime {",
            "final class PlotterApplicationRuntime {\n  func requestSimulatedRelativeJog() {}",
            1,
        )
        with self.assertRaisesRegex(metrics.MetricError, "environment-mode-branches identity/count drift"):
            metrics.evaluate_bundles(baseline, current)

    def test_stored_closure_effect_addition_fails(self) -> None:
        baseline, current = exact_fixtures()
        current[metrics.OPERATOR] += (
            "struct ReplacementClosureEffects {\n"
            "  let execute: @Sendable () async -> Void\n"
            "}\n"
        )
        with self.assertRaisesRegex(metrics.MetricError, "direct-effect-calls identity/count drift"):
            metrics.evaluate_bundles(baseline, current)

    def test_policy_state_addition_fails(self) -> None:
        baseline, current = exact_fixtures()
        current[metrics.OPERATOR] = current[metrics.OPERATOR].replace(
            "final class PlotterApplicationRuntime {",
            "final class PlotterApplicationRuntime {\n  private let backupApplicationState: FixtureValue",
            1,
        )
        with self.assertRaisesRegex(metrics.MetricError, "policy-state manifest mismatch"):
            metrics.evaluate_bundles(baseline, current)

    def test_adapter_addition_and_removal_fail(self) -> None:
        baseline, current = exact_fixtures()
        added = dict(current)
        added[metrics.OPERATOR] = added[metrics.OPERATOR].replace(
            "final class PlotterApplicationRuntime {",
            "final class PlotterApplicationRuntime {\n  private let compatibilityFacade: FixtureValue",
            1,
        )
        with self.assertRaisesRegex(metrics.MetricError, "adapter manifest mismatch"):
            metrics.evaluate_bundles(baseline, added)

        removed = dict(current)
        removed[metrics.OPERATOR] = removed[metrics.OPERATOR].replace(
            "  private let drawingEvidencePort: FixtureValue\n", "", 1
        )
        with self.assertRaisesRegex(metrics.MetricError, "source identity is absent"):
            metrics.evaluate_bundles(baseline, removed)

    def test_threshold_drift_fails_even_when_sources_match(self) -> None:
        baseline, current = exact_fixtures()
        results = metrics.evaluate_bundles(baseline, current)
        drifted = dict(metrics.EXPECTED_COUNTS)
        drifted["operator-workspace-adapters"] = (7, 8, "not-increased")
        with self.assertRaisesRegex(metrics.MetricError, "identity/count drift"):
            metrics.enforce_thresholds(results, drifted)


if __name__ == "__main__":
    unittest.main()
