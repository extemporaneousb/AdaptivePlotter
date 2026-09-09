import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@Suite("Learning Path presentation")
struct LearningPathPresentationTests {
  @Test("Learning Path has only the two implemented curriculum stages")
  func exactImplementedStageJourney() {
    #expect(LearningPathStage.allCases.map(\.number) == ["1", "2"])
    #expect(
      LearningPathStage.allCases.map(\.title) == [
        "Plotter Calibration",
        "Drawing Validation",
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

  @Test("Plotter Calibration exposes the exact ordered exercises")
  func exactDiscoverySteps() {
    #expect(
      HumanGuidedDiscoveryStep.allCases.map(\.stepNumber)
        == ["1.1", "1.2", "1.3", "1.4"]
    )
    #expect(
      HumanGuidedDiscoveryStep.allCases.map(\.title) == [
        "Identify and Calibrate the Pen",
        "Measure and Center the Drawing Boundary",
        "Calibrate Camera from Pen Cap Positions",
        "Calibrate Pen Tip from Corner Marks",
      ])
  }

  @Test("Drawing Validation retains six truthful internal phases")
  func exactBorderValidationPhases() {
    #expect(
      BorderValidationStep.allCases.map(\.rawValue) == [1, 2, 3, 4, 5, 6]
    )
    #expect(
      BorderValidationStep.allCases.map(\.stepNumber) == Array(repeating: "2.1", count: 6)
    )
    #expect(
      BorderValidationStep.allCases.map(\.title) == [
        "Plan Drawing Border",
        "Capture Baseline Frame",
        "Move to Drawing Border Start",
        "Draw Drawing Border",
        "Reveal Drawing",
        "Compare Plan with Observed Ink",
      ])
  }

  @Test("flat navigator starts at Stage 1 and exposes one Stage 2 exercise")
  func exactNavigatorOrder() {
    #expect(
      LearningPathItemID.navigationOrder.map { "\($0.number) \($0.title)" } == [
        "1 Plotter Calibration",
        "1.1 Identify and Calibrate the Pen",
        "1.2 Measure and Center the Drawing Boundary",
        "1.3 Calibrate Camera from Pen Cap Positions",
        "1.4 Calibrate Pen Tip from Corner Marks",
        "2 Drawing Validation",
        "2.1 Draw and Validate the Drawing Border",
      ])
  }

  @Test("shared Learning Path vocabulary excludes obsolete numbering and implementation jargon")
  func strictLearningPathVocabulary() {
    let visibleTerms = LearningPathStage.allCases.map(\.title)
      + HumanGuidedDiscoveryStep.allCases.map(\.title)
      + [LearningPathItemID.borderValidation(.chooseDrawingBorderPlan).title]
      + [
        LearningPathTerminology.Action.identifyPenCap,
        LearningPathTerminology.Action.confirmPenUp,
        LearningPathTerminology.Action.confirmPenDown,
        LearningPathTerminology.Action.runCameraCalibration,
        LearningPathTerminology.Action.acceptCameraCalibration,
        LearningPathTerminology.Action.drawCalibrationCircles,
        LearningPathTerminology.Action.acceptPenTipCalibration,
        LearningPathTerminology.Action.drawAndValidateDrawingBorder,
      ]
    let forbidden = [
      "3.1", "3.2", "3.3", "3.4", "4.1", "Human-Guided", "Observed Drawing Trial",
      "admitted", "logical owner", "workflow coordinator", "tip map", "Go", "Next",
    ]

    for term in visibleTerms {
      for word in forbidden {
        #expect(!term.localizedCaseInsensitiveContains(word))
      }
    }
    #expect(DiscoverySequenceCatalog.title == LearningPathTerminology.Stage.plotterCalibration)
    #expect(
      DiscoverySequenceCatalog.definition(for: .penInteraction).title
        == LearningPathTerminology.Exercise.identifyAndCalibratePen
    )
  }

  @Test("selection and Return to Current mutate presentation state only")
  func inertSelection() {
    var selection = LearningPathSelectionState(current: .humanGuidedDiscovery(.penInteraction))

    selection.select(.stage(.borderValidations))
    #expect(selection.selected == .stage(.borderValidations))
    #expect(selection.current == .humanGuidedDiscovery(.penInteraction))
    #expect(selection.isReviewingAnotherItem)

    selection.returnToCurrent()
    #expect(selection.selected == .humanGuidedDiscovery(.penInteraction))
    #expect(selection.current == .humanGuidedDiscovery(.penInteraction))
    #expect(!selection.isReviewingAnotherItem)
  }

  @Test("runtime progression follows only when the operator is not reviewing")
  func selectionFollowsCurrentWithoutOverridingReview() {
    var selection = LearningPathSelectionState(
      current: .humanGuidedDiscovery(.penInteraction)
    )
    selection.updateCurrent(.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering))
    #expect(
      selection.selected == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    )

    selection.select(.stage(.humanGuidedDiscovery))
    selection.updateCurrent(.humanGuidedDiscovery(.calibrateCameraAndVisibleCap))
    #expect(selection.current == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap))
    #expect(selection.selected == .stage(.humanGuidedDiscovery))
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

    #expect(start.unavailableReason != nil)
    #expect(start.unavailableReason == "A responsive controller session is required.")
    #expect(start.role == .positive)
    #expect(stop.unavailableReason == nil)
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

    #expect(PlotterLearningAction.stop(first) == .stop(first))
    #expect(PlotterLearningAction.stop(first) != .stop(successor))
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

  @Test("exercise detail carries only prompt, instruction, and effect-bearing controls")
  func minimalExerciseDetailPresentation() {
    let presentation = OperatorActionPresentation(
      itemID: .humanGuidedDiscovery(.penInteraction),
      instructions: [.text("Confirm the physical pen pose.")],
      question: ExerciseQuestionPresentation(
        prompt: [.text("Is the pen physically"), .cue(.up), .text("?")],
        choices: [.yes, .no]
      )
    )

    #expect(
      Set(Mirror(reflecting: presentation).children.compactMap(\.label))
        == Set(["itemID", "instructions", "question", "actionStrip"])
    )
    #expect(presentation.instructions.accessibilityText == "Confirm the physical pen pose.")
    #expect(presentation.question?.choices == [.yes, .no])
  }

  @Test("removed Exercise detail chrome and presentation types have zero source matches")
  func removedExerciseDetailSourceIsDeleted() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sourcePaths = [
      "Sources/PlotterApp/LearningPathView.swift",
      "Sources/PlotterApp/LearningPathPresentation.swift",
      "Sources/PlotterApp/LearningPathProjector.swift",
    ]
    let source = try sourcePaths.map {
      try String(contentsOf: repositoryRoot.appendingPathComponent($0), encoding: .utf8)
    }.joined(separator: "\n")
    let removedTerms = [
      "SELECTED EXERCISE",
      "CURRENT TIMELINE POSITION",
      "FOCUSED QUESTION",
      "Expected observation",
      "Requested feed",
      "Feed source",
      "OPERATION ACTIVITY",
      "SYSTEM STATUS",
      "RESET LEARNING",
      "EXERCISE ACTIONS",
      "ExerciseTimelinePresentation",
      "ExerciseEvidencePresentation",
      "OperationActivityPresentation",
      "SubsystemStatusPresentation",
    ]

    for term in removedTerms {
      #expect(!source.contains(term), "Removed Exercise detail source remains: \(term)")
    }

    #expect(source.contains("fragmentText(question.prompt)"))
    #expect(source.contains("fragmentText(presentation.instructions)"))
    #expect(source.contains("presentation.penAdjustment"))
    #expect(source.contains("presentation.directionSelection"))
    #expect(source.contains("submitPlotterUIRequest(request)"))
    #expect(source.contains("projection.menu.resetAllPlan"))
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
    #expect(strip.ownerID == "1.1-Identify and Calibrate the Pen")
  }

  @Test(
    "completed boundary repeat controls name one side and keep Redo distinct from another attempt")
  func sideSpecificBoundaryRepeatControls() {
    let strip = ExerciseActionStripPresentation(
      ownerID: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      actions: [
        ExerciseActionDescriptor(
          kind: .boundary(.acquire(direction: .positiveX, mode: .replacement)),
          title: "Redo X+ Boundary"
        ),
        ExerciseActionDescriptor(
          kind: .boundary(.acquire(direction: .positiveX, mode: .additional)),
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
    #expect(
      strip.actions[0].kind == .boundary(.acquire(direction: .positiveX, mode: .replacement))
    )
    #expect(
      strip.actions[1].kind == .boundary(.acquire(direction: .positiveX, mode: .additional))
    )
  }
}
