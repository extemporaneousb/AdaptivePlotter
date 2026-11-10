#!/usr/bin/env python3
"""Pure deterministic fixtures for episode cutover checks."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from check_episode_cutover import ContractError, validate_ea09_learning_authority, validate_drawing_issuance, ISSUANCE_REQUIRED_FILES, ISSUANCE_FOCUSED_SUITES


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


class DrawingIssuanceCutoverTests(unittest.TestCase):
    """Scanner fixtures, never an alternate execution or staging implementation."""
    def fixture(self) -> dict[str, str]:
        sources = {path: "struct RetainedOwner {}" for path in ISSUANCE_REQUIRED_FILES}
        sources["Sources/PortraitCore/DrawingDestination.swift"] = "struct DrawingJobIssuance { let job: JobRef }"
        sources["Sources/PlotterRuntime/DrawingRunIntent.swift"] = "struct DrawingRunIntentBody {} struct DrawingRunIssuanceProposal {}"
        sources["Sources/PlotterRuntime/DrawingRunEvidenceStore.swift"] = "actor DrawingRunEvidenceStore { func stageIntent(_ proposal: DrawingRunIssuanceProposal) { let run = RunID(); let intent = DrawingRunIntent() } }"
        sources["Sources/PlotterApp/OperatorWorkspace.swift"] = "func submitUnrecordedPlotterUIRequest(_ request: PlotterUIRequest) { let original = PlotterDrawingRunSubmission(requestID: ID(rawValue: request.id.rawValue), projection: reviewed, intent: .start) }"
        sources["Sources/PlotterApp/DrawingRunEvidenceComposition.swift"] = "var stagedPortraitBinding: Intent?; func loadForPortraitBinding() {} func finishPortraitBinding() {}"
        sources["Sources/PortraitLibrary/PortraitEvidenceSource.swift"] = "func proveStagedAttempt() {}"
        for suite in ISSUANCE_FOCUSED_SUITES:
            sources[f"Tests/PlotterAppTests/{suite}.swift"] = f"struct {suite} {{}}"
        return sources

    def test_canonical_owner_fixture_and_consumers(self) -> None:
        for consumer_only in (False, True):
            validate_drawing_issuance(self.fixture(), consumer_only=consumer_only)

    def test_retained_border_and_terminal_controls_are_not_global_deletions(self) -> None:
        sources = self.fixture()
        sources["Sources/PlotterApp/DrawingBorderEvidence.swift"] = "let id = RunID(attemptID.rawValue); let action = Action.start; let next = Action.beginNewRun(id)"
        sources["Sources/PlotterApp/OperatorWorkspace.swift"] += "\nfunc terminalControl() { let id = RunID(); let request = PlotterDrawingRunSubmission(projection: reviewed, intent: .beginNewRun(id)) }"
        sources["Sources/OtherCalibration/Fixture.swift"] = "func calibrate() { let nonjob = RunID() }"
        validate_drawing_issuance(sources)

    def test_forbidden_consumer_mutations_fail_both_scopes(self) -> None:
        mutations = (
            ("Sources/PortraitLibrary/DrawingDestinationService.swift", "protocol DrawingDestinationNonDeviceOwner {}"),
            ("Sources/PortraitLibrary/DrawingDestinationService.swift", "let nonDeviceOwner: Owner?"),
            ("Sources/PortraitCore/DrawingDestination.swift", "import PlotterUI"),
            ("Sources/PortraitLibrary/DrawingDestinationService.swift", "import PlotterUI"),
            ("Sources/PlotterEpisodeRuntime/PlotterDrawingRunRuntime.swift", "func start() { let id = RunID() }"),
            ("Sources/PlotterEpisodeRuntime/PlotterDrawingRunRuntime.swift", "func run() { let intent = DrawingRunIntent() }"),
            ("Sources/PlotterApp/OperatorWorkspace.swift", "let request = PlotterDrawingRunSubmission(projection: reviewed, intent: .start)"),
            ("Sources/PlotterApp/OperatorWorkspace.swift", "let request = PlotterDrawingRunSubmission(requestID: PlotterDrawingRunRequestID(), projection: reviewed, intent: .start)"),
            ("Sources/PlotterApp/OperatorWorkspace.swift", "let request = PlotterDrawingRunSubmission(requestID: ID(rawValue: UUID()), projection: reviewed, intent: .start)"),
        )
        for path, mutation in mutations:
            for consumer_only in (False, True):
                with self.subTest(path=path, mutation=mutation, consumer_only=consumer_only):
                    sources = self.fixture()
                    if "PlotterDrawingRunSubmission" in mutation:
                        sources[path] = "func submitUnrecordedPlotterUIRequest(_ request: PlotterUIRequest) { " + mutation + " }"
                    else:
                        sources[path] += "\n" + mutation
                    with self.assertRaises(ContractError):
                        validate_drawing_issuance(sources, consumer_only=consumer_only)

    def test_unbound_authored_start_forwarding_fails_but_nonstart_route_remains(self) -> None:
        sources = self.fixture()
        sources["Sources/PlotterApp/OperatorWorkspace.swift"] += "\nfunc submitDrawingRun(_ submission: Submission) { if submission.intent == .start { return await drawingRunRuntime.submit(submission) } }"
        with self.assertRaisesRegex(ContractError, "unbound authored Start"):
            validate_drawing_issuance(sources)
        sources["Sources/PlotterApp/OperatorWorkspace.swift"] = sources["Sources/PlotterApp/OperatorWorkspace.swift"].replace("if submission.intent == .start { return await drawingRunRuntime.submit(submission) }", "if submission.intent == .start { return await drawingDestination.handle(.submit(key, ticket)) }; return await drawingRunRuntime.submit(submission)")
        validate_drawing_issuance(sources)

    def test_other_raw_file_cannot_substitute_for_store_stage_owner(self) -> None:
        sources = self.fixture()
        sources["Sources/PlotterRuntime/Other.swift"] = sources["Sources/PlotterRuntime/DrawingRunEvidenceStore.swift"]
        sources["Sources/PlotterRuntime/DrawingRunEvidenceStore.swift"] = "actor DrawingRunEvidenceStore {}"
        with self.assertRaisesRegex(ContractError, "existing raw store/stage owner"):
            validate_drawing_issuance(sources)

    def test_missing_owner_proof_type_or_suite_fails(self) -> None:
        for path in ISSUANCE_REQUIRED_FILES:
            sources = self.fixture()
            del sources[path]
            with self.subTest(path=path), self.assertRaises(ContractError):
                validate_drawing_issuance(sources)
        for path in ("Sources/PlotterRuntime/DrawingRunIntent.swift", "Sources/PlotterApp/DrawingRunEvidenceComposition.swift", "Sources/PortraitLibrary/PortraitEvidenceSource.swift", "Tests/PlotterAppTests/DrawingIssuanceServiceTests.swift"):
            sources = self.fixture()
            sources[path] = "// Required symbols only in comments must not pass."
            with self.subTest(path=path), self.assertRaises(ContractError):
                validate_drawing_issuance(sources)

    def test_pre_receipt_binding_is_not_circular(self) -> None:
        sources = self.fixture()
        sources["Sources/PortraitCore/DrawingDestination.swift"] = "struct DrawingJobIssuance { let finalReceiptDigest: Digest }"
        with self.assertRaisesRegex(ContractError, "circular"):
            validate_drawing_issuance(sources)


if __name__ == "__main__":
    unittest.main()
