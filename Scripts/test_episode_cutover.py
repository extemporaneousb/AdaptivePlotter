#!/usr/bin/env python3
"""Pure deterministic fixtures for EA-09 Learning authority cutover checks."""

from __future__ import annotations

import unittest

from check_episode_cutover import ContractError, validate_ea09_learning_authority


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
    intent: .retainedLearningAction(.init(rawValue: "start"))
  )
}
""",
            "retained-candidate",
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


if __name__ == "__main__":
    unittest.main()
