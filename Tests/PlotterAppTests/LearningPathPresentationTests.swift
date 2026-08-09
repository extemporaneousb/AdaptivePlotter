import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Learning Path presentation")
struct LearningPathPresentationTests {
  @Test("operator journey has the exact five numbered stages")
  func exactFiveStageJourney() {
    #expect(LearningPathStage.allCases.map(\.number) == ["1", "2", "3", "4", "5"])
    #expect(
      LearningPathStage.allCases.map(\.title) == [
        "Connect",
        "Enable Motion",
        "Human-Guided Discovery",
        "Observed Drawing Trials",
        "Adaptive Drawing",
      ])
  }

  @Test("stage statuses are exact presentation terms without a percentage")
  func stageStatuses() {
    #expect(
      LearningPathStageStatus.allCases.map(\.rawValue) == [
        "Complete",
        "Current",
        "Next",
        "Future",
        "Needs Attention",
      ])
  }

  @Test("Human-Guided Discovery exposes the exact ordered substeps")
  func exactDiscoverySteps() {
    #expect(HumanGuidedDiscoveryStep.allCases.map(\.stepNumber) == ["3.1", "3.2", "3.3"])
    #expect(
      HumanGuidedDiscoveryStep.allCases.map(\.title) == [
        "Pen Interaction",
        "Boundary Discovery",
        "Clear-View Discovery",
      ])
  }

  @Test("Observed Drawing Trials exposes the exact six-step sequence")
  func exactDrawingTrialSteps() {
    #expect(
      ObservedDrawingTrialStep.allCases.map(\.stepNumber) == [
        "4.1", "4.2", "4.3", "4.4", "4.5", "4.6",
      ])
    #expect(
      ObservedDrawingTrialStep.allCases.map(\.title) == [
        "Capture Clean Reference",
        "Choose Line Start",
        "Create Anchor Mark",
        "Draw Isolated Line",
        "Clear Tool and Observe Ink",
        "Compare Intended and Observed Geometry",
      ])
  }

  @Test("flat navigator order preserves every stage and numbered exercise")
  func exactNavigatorOrder() {
    #expect(
      LearningPathItemID.navigationOrder.map { "\($0.number) \($0.title)" } == [
        "1 Connect",
        "2 Enable Motion",
        "3 Human-Guided Discovery",
        "3.1 Pen Interaction",
        "3.2 Boundary Discovery",
        "3.3 Clear-View Discovery",
        "4 Observed Drawing Trials",
        "4.1 Capture Clean Reference",
        "4.2 Choose Line Start",
        "4.3 Create Anchor Mark",
        "4.4 Draw Isolated Line",
        "4.5 Clear Tool and Observe Ink",
        "4.6 Compare Intended and Observed Geometry",
        "5 Adaptive Drawing",
      ])
  }

  @Test("selection and Return to Current mutate presentation state only")
  func inertSelection() {
    var selection = LearningPathSelectionState(current: .humanGuidedDiscovery(.penInteraction))

    selection.select(.stage(.adaptiveDrawing))
    #expect(selection.selected == .stage(.adaptiveDrawing))
    #expect(selection.current == .humanGuidedDiscovery(.penInteraction))
    #expect(selection.isReviewingAnotherItem)

    selection.returnToCurrent()
    #expect(selection.selected == .humanGuidedDiscovery(.penInteraction))
    #expect(selection.current == .humanGuidedDiscovery(.penInteraction))
    #expect(!selection.isReviewingAnotherItem)
  }

  @Test("runtime progression follows only when the operator is not reviewing")
  func selectionFollowsCurrentWithoutOverridingReview() {
    var selection = LearningPathSelectionState(current: .stage(.connect))
    selection.updateCurrent(.stage(.enableMotion))
    #expect(selection.selected == .stage(.enableMotion))

    selection.select(.stage(.connect))
    selection.updateCurrent(.humanGuidedDiscovery(.penInteraction))
    #expect(selection.current == .humanGuidedDiscovery(.penInteraction))
    #expect(selection.selected == .stage(.connect))
  }

  @Test("critical cues carry explicit visible and accessible values")
  func typedCues() {
    #expect(PresentationCue.up.visibleText == "UP")
    #expect(PresentationCue.down.visibleText == "DOWN")
    #expect(PresentationCue.yes.visibleText == "YES")
    #expect(PresentationCue.no.visibleText == "NO")
    #expect(PresentationCue.stop.visibleText == "STOP")
    #expect(PresentationCue.direction(.negativeX).visibleText == "X−")
    #expect(
      PresentationCue.direction(.negativeX).accessibilityValue
        == "Move in the negative X direction"
    )
  }

  @Test("action descriptors keep semantic role and exact unavailable reason")
  func typedActionDescriptor() {
    let start = ExerciseActionDescriptor(
      kind: .start,
      title: "Start",
      role: .positive,
      unavailableReason: "A responsive controller session is required."
    )
    let stop = ExerciseActionDescriptor(kind: .stop, title: "Stop", role: .destructive)

    #expect(!start.isEnabled)
    #expect(start.unavailableReason == "A responsive controller session is required.")
    #expect(start.role == .positive)
    #expect(stop.isEnabled)
    #expect(stop.role == .destructive)
  }

  @Test("one action strip has one owner and distinct repeat actions")
  func singleTypedActionStrip() {
    let strip = ExerciseActionStripPresentation(
      ownerID: .humanGuidedDiscovery(.penInteraction),
      actions: [
        ExerciseActionDescriptor(kind: .redoThisStep, title: "Redo This Step"),
        ExerciseActionDescriptor(
          kind: .recordAnotherAttempt,
          title: "Record Another Attempt"
        ),
      ]
    )

    #expect(strip.actions.map(\.kind) == [.redoThisStep, .recordAnotherAttempt])
    #expect(strip.ownerID == .humanGuidedDiscovery(.penInteraction))
  }
}
