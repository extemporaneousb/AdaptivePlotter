import Foundation
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
        "Paired Boundary Discovery and Centering",
        "Visibility Target and Clear-View Registration",
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
        "Choose Isolated Line Plan",
        "Capture Target-Anchored Baseline",
        "Move to Line Start",
        "Draw Isolated Line",
        "Return to Clear Pose and Observe New Ink",
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
        "3.2 Paired Boundary Discovery and Centering",
        "3.3 Visibility Target and Clear-View Registration",
        "4 Observed Drawing Trials",
        "4.1 Choose Isolated Line Plan",
        "4.2 Capture Target-Anchored Baseline",
        "4.3 Move to Line Start",
        "4.4 Draw Isolated Line",
        "4.5 Return to Clear Pose and Observe New Ink",
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
    #expect(forced.options == [.negativeX])
    #expect(forced.selected == .negativeX)
  }

  @Test("Clear-view search exposes only exact operator-selected 10 5 2 and 1 millimeter moves")
  func exactClearViewSearchMoves() {
    let direction = BoundaryDirection.positiveY
    let moves = ClearViewSearchDistance.allCases.map {
      ClearViewSearchMove(direction: direction, distance: $0)
    }
    let descriptors = moves.map {
      ExerciseActionDescriptor(
        kind: .moveForClearView($0),
        title: "Move \($0.direction.displayName) \($0.distance.displayName)"
      )
    }

    #expect(
      moves.map(\.distance) == [
        .tenMillimeters,
        .fiveMillimeters,
        .twoMillimeters,
        .oneMillimeter,
      ])
    #expect(
      descriptors.map(\.title) == [
        "Move Y+ 10 mm",
        "Move Y+ 5 mm",
        "Move Y+ 2 mm",
        "Move Y+ 1 mm",
      ])
    #expect(descriptors.map(\.isEnabled) == [true, true, true, true])
  }

  @Test("visibility workflow actions are typed and remain owned by one pinned strip")
  func typedVisibilityWorkflowActions() {
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    let strip = ExerciseActionStripPresentation(
      ownerID: owner,
      actions: [
        ExerciseActionDescriptor(
          kind: .captureTargetPoseRegistration,
          title: "Capture Target-Pose Registration"
        ),
        ExerciseActionDescriptor(
          kind: .calibrateCurrentCameraAndAcceptROI,
          title: "Calibrate Current Camera and Accept ROI",
          role: .positive
        ),
        ExerciseActionDescriptor(
          kind: .rejectTargetContactPointAndROI,
          title: "Reject Contact Point and ROI"
        ),
        ExerciseActionDescriptor(
          kind: .registerNewTargetArea,
          title: "Register New Target Area"
        ),
        ExerciseActionDescriptor(
          kind: .moveToNewTargetArea(
            ClearViewSearchMove(direction: .negativeY, distance: .tenMillimeters)
          ),
          title: "Move New Target Area Y− 10 mm"
        ),
        ExerciseActionDescriptor(
          kind: .paperReplaced,
          title: "Paper Replaced",
          role: .destructive
        ),
      ],
      mustRemainVisible: true
    )

    #expect(strip.ownerID == owner)
    #expect(strip.mustRemainVisible)
    #expect(
      strip.actions.map(\.kind) == [
        .captureTargetPoseRegistration,
        .calibrateCurrentCameraAndAcceptROI,
        .rejectTargetContactPointAndROI,
        .registerNewTargetArea,
        .moveToNewTargetArea(
          ClearViewSearchMove(direction: .negativeY, distance: .tenMillimeters)
        ),
        .paperReplaced,
      ])
    #expect(
      strip.actions.count { $0.kind == .calibrateCurrentCameraAndAcceptROI } == 1
    )
  }

  @Test("visibility recovery distinguishes observing ink from relocating or replacing paper")
  func typedVisibilityRecovery() {
    #expect(
      ExerciseActionKind.observeExistingVisibilityTarget
        != .registerNewTargetArea
    )
    #expect(ExerciseActionKind.registerNewTargetArea != .paperReplaced)
    #expect(ExerciseActionKind.drawVisibilityTarget != .observeExistingVisibilityTarget)
  }

  @Test("new target-area recovery requires typed relocation before an explicit new registration")
  func typedTargetAreaRelocation() {
    let selection = ExerciseDirectionSelectionPresentation(
      purpose: .targetAreaRelocation,
      selected: .positiveX
    )
    let moves = ClearViewSearchDistance.allCases.map {
      ExerciseActionKind.moveToNewTargetArea(
        ClearViewSearchMove(direction: selection.selected, distance: $0)
      )
    }
    let captureBeforeMove = ExerciseActionDescriptor(
      kind: .captureTargetPoseRegistration,
      title: "Capture Target-Pose Registration",
      role: .positive,
      unavailableReason: "Move to a new target area first."
    )
    let captureAfterMove = ExerciseActionDescriptor(
      kind: .captureTargetPoseRegistration,
      title: "Capture Target-Pose Registration",
      role: .positive
    )

    #expect(selection.purpose.label == "New target-area direction")
    #expect(moves.count == 4)
    #expect(
      moves.first
        == .moveToNewTargetArea(
          ClearViewSearchMove(direction: .positiveX, distance: .tenMillimeters)
        )
    )
    #expect(ExerciseActionKind.captureTargetPoseRegistration != .registerNewTargetArea)
    #expect(!captureBeforeMove.isEnabled)
    #expect(captureBeforeMove.unavailableReason == "Move to a new target area first.")
    #expect(captureAfterMove.isEnabled)
    #expect(
      ExerciseActionKind.moveToNewTargetArea(
        ClearViewSearchMove(direction: .positiveX, distance: .twoMillimeters)
      )
        != .moveForClearView(
          ClearViewSearchMove(direction: .positiveX, distance: .twoMillimeters)
        )
    )
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
