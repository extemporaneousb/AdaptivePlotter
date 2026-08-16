import Testing

@testable import PlotterApp

@Suite("Learning workbench window state")
struct LearningWorkbenchLayoutTests {
  @Test("one state owns the combined pane, Motion, and exclusive inspector")
  func windowStateOwnership() {
    var state = WorkbenchWindowState()

    #expect(state.learningExerciseIsPresented)
    #expect(state.motionIsPresented)
    #expect(state.inspectorSelection == .none)

    state.toggle(.learningExercise)
    state.toggle(.motion)
    state.toggle(.video)
    #expect(!state.learningExerciseIsPresented)
    #expect(!state.motionIsPresented)
    #expect(state.inspectorSelection == .video)

    state.toggle(.diagnostics)
    #expect(state.inspectorSelection == .diagnostics)
    #expect(!state.isPresented(.video))
    #expect(state.isPresented(.diagnostics))

    state.closeInspector()
    #expect(state.inspectorSelection == .none)
  }

  @Test("native toolbar and View command titles derive from the same state")
  func stateDependentActionTitles() {
    var state = WorkbenchWindowState()
    #expect(state.actionTitle(for: .learningExercise) == "Hide Learning")
    #expect(state.actionTitle(for: .motion) == "Hide Motion")
    #expect(state.actionTitle(for: .video) == "Show Video Settings")
    #expect(state.actionTitle(for: .diagnostics) == "Show Diagnostics")

    state.toggle(.video)
    #expect(state.actionTitle(for: .video) == "Hide Video Settings")
    #expect(state.actionTitle(for: .diagnostics) == "Show Diagnostics")
  }

  @Test("window width has no state transition or auto-collapse policy")
  func resizingCannotMutateVisibility() {
    var state = WorkbenchWindowState()
    state.inspectorSelection = .diagnostics
    let before = state

    for availableWidth in [320.0, 800.0, 1_480.0, 3_000.0] {
      _ = availableWidth / LearningWorkbenchLayoutPolicy.minimumWindowWidth
      #expect(state == before)
    }
  }

  @Test("combined Learning pane reserves a narrow native-list rail")
  func combinedPaneLayout() {
    #expect(LearningWorkbenchLayoutPolicy.minimumWindowWidth == 1_480)
    #expect(LearningWorkbenchLayoutPolicy.minimumLearningExerciseWidth == 480)
    #expect(LearningWorkbenchLayoutPolicy.learningPathRailWidth == 188)
    #expect(
      LearningWorkbenchLayoutPolicy.learningPathRailWidth
        < LearningWorkbenchLayoutPolicy.minimumLearningExerciseWidth / 2
    )
  }

  @Test("exercise actions preserve readable button widths")
  func readableExerciseActionWidths() {
    #expect(ExerciseActionLayoutPolicy.minimumButtonWidth == 180)
    #expect(ExerciseActionLayoutPolicy.minimumButtonHeight == 32)
  }

}
