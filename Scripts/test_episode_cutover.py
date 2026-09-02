#!/usr/bin/env python3
"""Pure deterministic fixtures for episode cutover checks."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from check_episode_cutover import ContractError, validate_ea09_learning_authority


ROOT = Path(__file__).resolve().parent.parent


CANONICAL_UI = """
public enum PlotterUIActionReachability {
  case global
  case learningOwner(String)
}
public struct PlotterUILearningProjection {
  public let currentOwnerID: String?
}
public struct PlotterUILearningActionabilityProjection {
  public let strips: [PlotterUILearningActionStripDecision]
  public let selectedResetPlanIsReachable: Bool
}
public struct PlotterUILearningActionabilityCompiler {
  public struct Limits { public let maximumItemVisitCount: Int }
  private func isReachable(_ value: PlotterUIActionReachability) -> Bool {
    switch value {
    case .global: true
    case .learningOwner(let owner): !owner.isEmpty
    }
  }
}
"""

ALLOWED_APP = """
struct PlotterLearningActionabilityFactAdapter {
  func facts(activeOwnerID: String?) -> PlotterUILearningActionabilityFacts {
    PlotterUILearningActionabilityFacts(activeOwnerID: activeOwnerID)
  }
  func compile(_ source: RuntimeLearningFacts) -> PlotterUILearningActionabilityProjection {
    PlotterUILearningActionabilityCompiler().compile(facts(activeOwnerID: source.owner))
  }
}
struct PlotterLearningDetailedPresentationNormalizer {
  func status(
    _ decision: PlotterUILearningItemDecision,
    actionability: PlotterUILearningActionabilityProjection
  ) -> LearningPathStageStatus {
    switch decision.status {
    case .complete: .complete
    case .current: .current
    case .next: .next
    case .needsAttention: .needsAttention
    }
  }
}
"""


class EpisodeCutoverLearningAuthorityTests(unittest.TestCase):
    def validate(self, extra_app: str = "", ui: str = CANONICAL_UI) -> None:
        validate_ea09_learning_authority(
            ui,
            {"Sources/PlotterApp/Fixture.swift": ALLOWED_APP + "\n" + extra_app},
        )

    def assert_bypass(self, source: str, category: str) -> None:
        with self.assertRaisesRegex(
            ContractError,
            rf"EA-09 App Learning authority bypass.*{category}",
        ):
            self.validate(source)

    def test_cosmetic_renderer_and_exact_fact_translation_pass(self) -> None:
        self.validate()

    def test_renamed_action_mapper_fails(self) -> None:
        self.assert_bypass(
            """
func alternateButtons(activeOwnerID: String?) -> [ExerciseActionDescriptor] {
  activeOwnerID == nil ? [] : [ExerciseActionDescriptor(kind: .start)]
}
""",
            "action",
        )

    def test_renamed_status_mapper_fails(self) -> None:
        self.assert_bypass(
            """
func alternateProgress(isComplete: Bool) -> LearningPathStageStatus {
  isComplete ? .complete : .current
}
""",
            "status",
        )

    def test_renamed_availability_mapper_fails(self) -> None:
        self.assert_bypass(
            """
func alternateAvailability(startUnavailableReasons: [String: String]) -> String? {
  startUnavailableReasons.values.first
}
""",
            "availability",
        )

    def test_renamed_retained_candidate_mapper_fails(self) -> None:
        self.assert_bypass(
            """
func alternateCandidate(activeOwnerID: String?) -> PlotterUIActionCandidate {
  PlotterUIActionCandidate(
    id: .init(rawValue: activeOwnerID ?? "none"),
    intent: .learningAction(.init(item: activeOwnerID ?? "none", action: .start))
  )
}
""",
            "model-candidate",
        )

    def test_renamed_reachability_mapper_fails(self) -> None:
        self.assert_bypass(
            """
func alternateReach(activeOwnerID: String?) -> PlotterUIActionReachability {
  .learningOwner(activeOwnerID ?? "none")
}
""",
            "reachability",
        )

    def test_split_raw_mapper_and_status_mapper_fail(self) -> None:
        self.assert_bypass(
            """
struct AlternateLearningInputs { let complete: Bool }
func collectAlternateInputs(isComplete: Bool) -> AlternateLearningInputs {
  AlternateLearningInputs(complete: isComplete)
}
func alternateSplitStatus(_ input: AlternateLearningInputs) -> LearningPathStageStatus {
  input.complete ? .complete : .next
}
""",
            "split App decision mapping",
        )

    def test_missing_canonical_compiler_fails(self) -> None:
        with self.assertRaisesRegex(
            ContractError,
            "canonical PlotterUI Learning authority missing",
        ):
            self.validate(ui=CANONICAL_UI.replace(
                "public struct PlotterUILearningActionabilityCompiler",
                "public struct MissingLearningCompiler",
            ))


class EpisodeCutoverEA12AManifestTests(unittest.TestCase):
    def test_border_sole_owner_manifest_is_exact_and_fail_closed(self) -> None:
        checker = (ROOT / "Scripts/check_episode_cutover.sh").read_text(encoding="utf-8")
        self.assertIn('if [ "$1" = "EA-12A" ]; then', checker)
        for literal in (
            "currentEnvironmentState.borderValidation",
            "applicationState.environmentStates[source]?.borderValidation",
            "borderValidationRuntime.replaceSnapshot",
            "activeBorderValidationOperation",
            "workspace.borderValidationStep",
            "workspace.borderValidationAssessment",
            "workspace.drawingBorderPlan",
            "var borderValidation: PlotterBorderValidationSnapshot",
            "func replaceSnapshot(",
            "public func advanceAfterSuccess(",
            "public func markExecutionState(",
            "public func submitStep(",
            "public func submitAcceptComparison(",
            "public func submitReject(",
            "case retryFrom(",
            "ContextualStopActionPresentation",
            "StableWorkflowCapCaptureRunner",
            "PlotterSystemSerialDeviceDiscoveryAdapter",
            "borderValidationPayloadSnapshot",
            "restoreBorderValidationPayload",
        ):
            self.assertIn(literal, checker)
        self.assertIn('if [ "$failures" -ne 0 ]; then', checker)
        self.assertIn("scan error", checker)

    def test_border_sole_owner_checker_rejects_duplicate_ingress(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            scripts = root / "Scripts"
            app_sources = root / "Sources/PlotterApp"
            runtime_sources = root / "Sources/PlotterEpisodeRuntime"
            tests = root / "Tests"
            scripts.mkdir()
            app_sources.mkdir(parents=True)
            runtime_sources.mkdir(parents=True)
            tests.mkdir()
            checker = scripts / "check_episode_cutover.sh"
            checker.write_text(
                (ROOT / "Scripts/check_episode_cutover.sh").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            (app_sources / "Fixture.swift").write_text(
                "currentEnvironmentState.borderValidation = snapshot\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                ["sh", str(checker), "EA-12A", "--consumer-only"],
                cwd=root,
                capture_output=True,
                check=False,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("duplicate-ingress remains", result.stderr)


class EpisodeCutoverEA12BManifestTests(unittest.TestCase):
    def test_typed_learning_route_manifest_is_exact_and_fail_closed(self) -> None:
        checker = (ROOT / "Scripts/check_episode_cutover.sh").read_text(encoding="utf-8")
        self.assertIn('if [ "$1" = "EA-12B" ]; then', checker)
        for literal in (
            "PlotterApplicationBoundAction",
            "currentApplicationActions",
            "currentPlotterUIResetPlans",
            "applicationAction",
            "retainedLearningAction",
            "retainedLearningReset",
            "ExerciseActionKind",
            "PlotterUILearningSemanticAction",
            "static let controllerProbe",
            "static let observationStop",
            "static let observationRestart",
            "ActionSurfaceOverlayStyleToken",
            "styleToken(for:",
            ".discardCameraSamples",
            "Discard Camera Samples",
            "String(describing: action",
            "String(describing: kind",
            "PlotterLearningActionRequest",
            "PlotterLearningUIAuthorityTests",
            "public protocol PlotterUIIntentSink",
        ):
            self.assertIn(literal, checker)
        self.assertIn('if [ "$failures" -ne 0 ]; then', checker)
        self.assertIn("scan error", checker)

    def test_typed_learning_route_rejects_side_registry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            scripts = root / "Scripts"
            app_sources = root / "Sources/PlotterApp"
            tests = root / "Tests"
            scripts.mkdir()
            app_sources.mkdir(parents=True)
            tests.mkdir()
            checker = scripts / "check_episode_cutover.sh"
            checker.write_text(
                (ROOT / "Scripts/check_episode_cutover.sh").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            (app_sources / "Fixture.swift").write_text(
                "let currentApplicationActions: [String: String] = [:]\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                ["sh", str(checker), "EA-12B", "--consumer-only"],
                cwd=root,
                capture_output=True,
                check=False,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("deleted-symbol remains", result.stderr)


class EpisodeCutoverEA12CManifestTests(unittest.TestCase):
    def test_learning_episode_manifest_is_exact_and_fail_closed(self) -> None:
        checker = (ROOT / "Scripts/check_episode_cutover.sh").read_text(encoding="utf-8")
        self.assertIn('if [ "$1" = "EA-12C" ]; then', checker)
        for literal in (
            "residualLearningAdmissionID",
            "PlotterApplicationResidualIntent",
            "PlotterApplicationResidualOperationAdapter",
            "runResidualLearningAction",
            "PlotterUIController",
            "PlotterUIObservation",
            "plotterUIControllerRequest",
            "plotterUIObservationRequest",
            "observationSubmission",
            "identityComponent",
            "ownerID.id):",
            "application-residual-",
            "public struct PlotterLearningEpisodeID",
            "public struct PlotterLearningTransitionID",
            "PlotterLearningEpisodeRecord",
            "learningEpisodeRecord.reserve(",
            "learningEpisodeRecord.publish(",
            "public protocol PlotterUIIntentSink",
            "expected reviewed Sources +1631/-1600 safety exception",
        ):
            self.assertIn(literal, checker)
        self.assertIn('if [ "$failures" -ne 0 ]; then', checker)
        self.assertIn("scan error", checker)

    def test_learning_episode_checker_rejects_residual_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            scripts = root / "Scripts"
            app_sources = root / "Sources/PlotterApp"
            tests = root / "Tests"
            scripts.mkdir()
            app_sources.mkdir(parents=True)
            tests.mkdir()
            checker = scripts / "check_episode_cutover.sh"
            checker.write_text(
                (ROOT / "Scripts/check_episode_cutover.sh").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            (app_sources / "Fixture.swift").write_text(
                "let residualLearningAdmissionID = UUID()\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                ["sh", str(checker), "EA-12C", "--consumer-only"],
                cwd=root,
                capture_output=True,
                check=False,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("deleted-symbol remains", result.stderr)


if __name__ == "__main__":
    unittest.main()
