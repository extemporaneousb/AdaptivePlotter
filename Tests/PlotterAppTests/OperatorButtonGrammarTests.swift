import Foundation
import Testing
import PlotterUI
import PlotterEpisodeModel
@testable import PlotterApp

struct OperatorButtonGrammarTests {
  @Test @MainActor
  func submissionFeedbackLatchesUntilCompletion() {
    let feedback = OperatorRequestFeedback()
    #expect(feedback.begin())
    #expect(feedback.isPending)
    #expect(!feedback.begin())
    feedback.finish(.accepted(requestID: .init(rawValue: UUID())))
    #expect(!feedback.isPending)
    #expect(feedback.wasAccepted)
    #expect(feedback.result == "Accepted")
    #expect(feedback.begin())
  }

  @Test
  func stopIdentitySurvivesCapabilityRefresh() {
    let first = PlotterUILearningActionDecision(itemID: "boundary", action: .boundary(.stop(.init())))
    let second = PlotterUILearningActionDecision(itemID: "boundary", action: .boundary(.stop(.init())))
    #expect(first.request != second.request)
    #expect(first.controlIdentity == second.controlIdentity)
    #expect(first.buttonRole == .stop)
    #expect(first.buttonRole.chrome(isEnabled: true) == .stop)
  }

  @Test
  func servoDragCommitsOnlyTheFinalValue() {
    var draft = PenSetpointDraft()
    for value in 40...85 { draft.change(to: value) }
    #expect(draft.commit() == 85)
    #expect(draft.commit() == nil)
  }

  @Test
  func enabledRolesHaveDistinctSemanticChrome() {
    #expect(OperatorButtonRole.affirmative.chrome(isEnabled: true) == .neutralEnabled)
    #expect(OperatorButtonRole.negative.chrome(isEnabled: true) == .neutralEnabled)
    #expect(OperatorButtonRole.neutral.chrome(isEnabled: true) == .neutralEnabled)
  }

  @Test
  func everyDisabledRoleUsesTheSameNoninteractiveChrome() {
    for role in OperatorButtonRole.allCases {
      #expect(role.chrome(isEnabled: false) == .disabled)
    }
  }

  @Test
  func exerciseChoicesUseWordsWithNeutralChrome() {
    let yes = ExerciseActionDescriptor(kind: .choice(.yes), title: "YES")
    let no = ExerciseActionDescriptor(kind: .choice(.no), title: "NO")

    #expect(yes.buttonRole == .affirmative)
    #expect(no.buttonRole == .negative)
  }

  @Test
  func exerciseActionRolesMapToTheSharedGrammar() {
    let start = ExerciseActionDescriptor(kind: .start, title: "Start", role: .positive)
    let stop = ExerciseActionDescriptor(kind: .cancel, title: "Cancel", role: .destructive)
    let retry = ExerciseActionDescriptor(kind: .restart, title: "Restart")

    #expect(start.buttonRole == .affirmative)
    #expect(stop.buttonRole == .negative)
    #expect(retry.buttonRole == .neutral)
  }

  @Test
  func unavailableExerciseActionCannotRetainEnabledChrome() {
    let unavailable = ExerciseActionDescriptor(
      kind: .start,
      title: "Start",
      role: .positive,
      unavailableReason: "Controller unavailable."
    )

    #expect(!unavailable.isEnabled)
    #expect(unavailable.buttonRole.chrome(isEnabled: unavailable.isEnabled) == .disabled)
  }
}
