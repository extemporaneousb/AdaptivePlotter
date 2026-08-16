import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Learning Path presentation")
struct LearningPathPresentationTests {
  @Test("operator journey has the exact four implemented stages")
  func exactImplementedStageJourney() {
    #expect(LearningPathStage.allCases.map(\.number) == ["1", "2", "3", "4"])
    #expect(
      LearningPathStage.allCases.map(\.title) == [
        "Connect",
        "Enable Motion",
        "Human-Guided Discovery",
        "Observed Drawing Trials",
      ])
  }

  @Test("stage statuses are exact presentation terms without a percentage")
  func stageStatuses() {
    #expect(
      LearningPathStageStatus.allCases.map(\.rawValue) == [
        "Complete",
        "Current",
        "Next",
        "Needs Attention",
      ])
  }

  @Test("Human-Guided Discovery exposes the exact ordered substeps")
  func exactDiscoverySteps() {
    #expect(
      HumanGuidedDiscoveryStep.allCases.map(\.stepNumber)
        == ["3.1", "3.2", "3.3", "3.4"]
    )
    #expect(
      HumanGuidedDiscoveryStep.allCases.map(\.title) == [
        "Pen Interaction",
        "Paired Boundary Discovery and Centering",
        "Calibrate Camera and Visible Cap",
        "Calibrate Pen Contact from Sparse Marks",
      ])
  }

  @Test("Observed Drawing Trial retains six truthful internal phases")
  func exactDrawingTrialPhases() {
    #expect(
      ObservedDrawingTrialStep.allCases.map(\.rawValue) == [1, 2, 3, 4, 5, 6]
    )
    #expect(
      ObservedDrawingTrialStep.allCases.map(\.stepNumber) == Array(repeating: "4.1", count: 6)
    )
    #expect(
      ObservedDrawingTrialStep.allCases.map(\.title) == [
        "Plan Predicted Isolated Line",
        "Capture Local Pre-Line Baseline",
        "Move to Line Start",
        "Draw Isolated Line",
        "Reveal and Observe New Ink",
        "Compare Intended and Observed Geometry",
      ])
  }

  @Test("flat navigator exposes one Go-owned Stage 4 exercise")
  func exactNavigatorOrder() {
    #expect(
      LearningPathItemID.navigationOrder.map { "\($0.number) \($0.title)" } == [
        "1 Connect",
        "2 Enable Motion",
        "3 Human-Guided Discovery",
        "3.1 Pen Interaction",
        "3.2 Paired Boundary Discovery and Centering",
        "3.3 Calibrate Camera and Visible Cap",
        "3.4 Calibrate Pen Contact from Sparse Marks",
        "4 Observed Drawing Trials",
        "4.1 Run Predicted Isolated Line Trial",
      ])
  }

  @Test("selection and Return to Current mutate presentation state only")
  func inertSelection() {
    var selection = LearningPathSelectionState(current: .humanGuidedDiscovery(.penInteraction))

    selection.select(.stage(.observedDrawingTrials))
    #expect(selection.selected == .stage(.observedDrawingTrials))
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
    let stopCapability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    )
    let start = ExerciseActionDescriptor(
      kind: .start,
      title: "Start",
      role: .positive,
      unavailableReason: "A responsive controller session is required."
    )
    let stop = ExerciseActionDescriptor(
      kind: .stop(stopCapability),
      title: "Stop",
      role: .destructive
    )

    #expect(!start.isEnabled)
    #expect(start.unavailableReason == "A responsive controller session is required.")
    #expect(start.role == .positive)
    #expect(stop.isEnabled)
    #expect(stop.role == .destructive)
  }

  @Test("Stop carries the exact logical-owner capability")
  func stopCapabilityIdentity() {
    let first = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    )
    let successor = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    )

    #expect(ExerciseActionKind.stop(first) == .stop(first))
    #expect(ExerciseActionKind.stop(first) != .stop(successor))
  }

  @Test("focused questions retain their actual structured prompt and typed choices")
  func structuredQuestion() {
    let question = ExerciseQuestionPresentation(
      prompt: [.text("Is the pen physically"), .cue(.up), .text("?")],
      choices: [.yes, .no]
    )

    #expect(question.prompt.accessibilityText == "Is the pen physically Pen up ?")
    #expect(question.choices == [.yes, .no])
  }

  @Test("operation activity retains actor outcome detail and recovery")
  func operationActivity() {
    let activity = OperationActivityPresentation(
      actor: "Controller",
      action: "Boundary Discovery X+",
      outcome: .needsAttention,
      detail: [.text("Controller reported Alarm.")],
      recovery: [.text("Inspect the controller before restarting.")]
    )

    #expect(activity.actor == "Controller")
    #expect(activity.outcome.rawValue == "Needs Attention")
    #expect(activity.detail.accessibilityText == "Controller reported Alarm.")
    #expect(activity.recovery.accessibilityText == "Inspect the controller before restarting.")
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

  @Test("boundary direction presentation distinguishes available choices from a forced opposite")
  func boundaryDirectionChoices() {
    let available = ExerciseDirectionSelectionPresentation(
      purpose: .boundary,
      options: BoundaryDirection.allCases,
      selected: .positiveX
    )
    let forced = ExerciseDirectionSelectionPresentation(
      purpose: .boundary,
      options: [.negativeX],
      selected: .negativeX
    )

    #expect(available.purpose.label == "Boundary direction")
    #expect(available.options == [.positiveX, .negativeX, .positiveY, .negativeY])
    #expect(available.allowsSelection)
    #expect(forced.options == [.negativeX])
    #expect(forced.selected == .negativeX)
    #expect(!forced.allowsSelection)
  }

  @Test(
    "completed boundary repeat controls name one side and keep Redo distinct from another attempt")
  func sideSpecificBoundaryRepeatControls() {
    let strip = ExerciseActionStripPresentation(
      ownerID: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      actions: [
        ExerciseActionDescriptor(
          kind: .redoBoundary(.positiveX),
          title: "Redo X+ Boundary"
        ),
        ExerciseActionDescriptor(
          kind: .recordAnotherBoundaryAttempt(.positiveX),
          title: "Record Another X+ Attempt"
        ),
      ]
    )

    #expect(
      strip.actions.map(\.title) == [
        "Redo X+ Boundary",
        "Record Another X+ Attempt",
      ])
    #expect(strip.actions[0].kind != strip.actions[1].kind)
    #expect(strip.actions[0].kind == .redoBoundary(.positiveX))
    #expect(strip.actions[1].kind == .recordAnotherBoundaryAttempt(.positiveX))
  }
}
