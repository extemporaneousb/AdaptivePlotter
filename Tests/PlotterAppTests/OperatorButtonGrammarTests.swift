import Testing
@testable import PlotterApp

struct OperatorButtonGrammarTests {
  @Test
  func enabledRolesHaveDistinctSemanticChrome() {
    #expect(OperatorButtonRole.affirmative.chrome(isEnabled: true) == .affirmative)
    #expect(OperatorButtonRole.negative.chrome(isEnabled: true) == .negative)
    #expect(OperatorButtonRole.neutral.chrome(isEnabled: true) == .neutralEnabled)
  }

  @Test
  func everyDisabledRoleUsesTheSameDarkNoninteractiveChrome() {
    for role in OperatorButtonRole.allCases {
      #expect(role.chrome(isEnabled: false) == .disabled)
    }
  }

  @Test
  func exerciseChoicesUseGreenYesAndRedNo() {
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
