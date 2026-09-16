import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@Suite("Retained detailed Learning presentation normalizer")
struct PlotterLearningPresentationCompilerTests {
  private let normalizer = PlotterLearningDetailedPresentationNormalizer()

  @Test("camera failure and retry progress are visible in the Learning instructions")
  func cameraFailureIsVisible() {
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let failure = PlotterCameraCalibrationFailure(
      code: .requiredStateMissing, detail: "No pen cap detected.", recovery: .resolveNamedFailure)
    let failed = project(postBoundarySnapshot(camera: .init(failure: failure)), selectedItemID: owner)
    #expect(failed.selectedAction.instructions.accessibilityText.contains("No pen cap detected."))
    #expect(failed.selectedAction.instructions.accessibilityText.contains("Reset All Learning"))
    let retrying = project(postBoundarySnapshot(camera: .init(phase: .preparing, failure: failure)), selectedItemID: owner)
    #expect(retrying.selectedAction.instructions.accessibilityText == "Preparing bounded calibration")
    let refused = project(postBoundarySnapshot(camera: .init(lastOutcome: .refused("Camera unavailable."))), selectedItemID: owner)
    #expect(refused.selectedAction.instructions.accessibilityText.contains("Camera unavailable."))
  }

  @Test("same snapshot and review selection are deterministic")
  func deterministicProjection() {
    let snapshot = PlotterLearningPresentationFacts()
    let first = project(
      snapshot,
      selectedItemID: .stage(.borderValidations)
    )
    let second = project(
      snapshot,
      selectedItemID: .stage(.borderValidations)
    )

    #expect(first == second)
    #expect(first.currentItemID == .humanGuidedDiscovery(.penInteraction))
    #expect(first.selectedAction.itemID == .stage(.borderValidations))
  }

  @Test("all navigator rows receive exact initial states")
  func everyNavigatorRowIsProjected() {
    let projection = project(
      PlotterLearningPresentationFacts(),
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
    )

    #expect(projection.items.map(\.id) == LearningPathItemID.navigationOrder)
    #expect(projection.items.count == 7)
    #expect(projection.items.first?.status == .current)
    #expect(projection.items[1].status == .current)
    #expect(projection.items.dropFirst(2).allSatisfy { $0.status == .next })
  }

  @Test("detailed App presentation cannot introduce an action absent from PlotterUI")
  func appNormalizerCannotIntroduceSemanticAction() {
    let snapshot = PlotterLearningPresentationFacts()
    let canonical = PlotterUILearningActionabilityCompiler().compile(
      PlotterUILearningActionabilityFacts(
        learning: PlotterUILearningFacts(
          isEnabled: false,
          activeOwnerID: nil,
          orderedMilestones: [.init(ownerID: "1.1-pen", isComplete: false)]
        ),
        selectedOwnerID: "1.1-pen",
        items: []
      )
    )
    let projection = normalizer.project(
      snapshot,
      selectedItemID: .humanGuidedDiscovery(.penInteraction),
      actionability: canonical
    )

    #expect(projection.currentActionStrip == nil)
    #expect(projection.selectedAction.actionStrip == nil)
  }

  @Test("Motion authorization cannot exist without a controller session")
  func motionAuthorizationDependsOnConnection() {
    let controller = PlotterLearningPresentationFacts.ControllerFacts(
      sessionEstablished: false,
      motionAuthorized: true
    )

    #expect(controller.sessionEstablished == false)
    #expect(controller.motionAuthorized == false)
  }

  @Test("normal exercise entry buttons have no redundant initiation gate")
  func normalExerciseEntryButtons() throws {
    let pen = project(
      PlotterLearningPresentationFacts(),
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
    )
    let boundarySnapshot = PlotterLearningPresentationFacts(
      penInteractionCompleted: true,
      controller: .init(sessionEstablished: true, motionAuthorized: true)
    )
    let boundary = project(
      boundarySnapshot,
      selectedItemID: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    )
    let cameraCalibrationSnapshot = postBoundarySnapshot(camera: .init())
    let cameraCalibration = project(
      cameraCalibrationSnapshot,
      selectedItemID: .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    )
    let sparseCalibrationSnapshot = postBoundarySnapshot(
      camera: .init(acceptedIsCurrent: true),
      sparse: .init(acceptedIsCurrent: false)
    )
    let sparseCalibration = project(
      sparseCalibrationSnapshot,
      selectedItemID: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )
    let drawingOwner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    let drawing = project(
      postBoundarySnapshot(sparse: .init(acceptedIsCurrent: true)),
      selectedItemID: drawingOwner
    )

    #expect(try #require(pen.currentActionStrip).actions.map(\.title) == ["Identify Pen Cap"])
    #expect(try #require(boundary.currentActionStrip).actions.map(\.title) == ["Move Toward X+"])
    #expect(
      try #require(cameraCalibration.currentActionStrip).actions.map(\.title)
        == ["Run Five-Position Camera Calibration"]
    )
    #expect(
      try #require(sparseCalibration.currentActionStrip).actions.map(\.title)
        == ["Draw Four Calibration Circles"]
    )
    #expect(try #require(drawing.currentActionStrip).actions.map(\.title) == ["Draw and Validate Drawing Border"])
  }

  @Test("LIVE and SIMULATED use the same progression and action grammar")
  func liveSimulatedParity() {
    let current = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let live = project(
      connectedSnapshot(source: .live),
      selectedItemID: current
    )
    let simulated = project(
      connectedSnapshot(source: .simulated),
      selectedItemID: current
    )

    #expect(live.currentItemID == simulated.currentItemID)
    #expect(live.items.map(\.status) == simulated.items.map(\.status))
    #expect(live.selectedAction.actionStrip == simulated.selectedAction.actionStrip)
    #expect(live.currentItemID == .humanGuidedDiscovery(.penInteraction))
  }

  @Test("Stop remains bound to its exact typed owner capability")
  func stopOwnership() {
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    )
    let snapshot = connectedSnapshot(
      operations: .init(
        activeAttemptOwner: owner,
        stopOwner: .exercise(capability, .moveToDrawingBorderStart, boundaryOwner: false)
      )
    )
    let projection = project(
      snapshot,
      selectedItemID: owner
    )

    #expect(projection.contextualStop?.capabilityID == capability)
    #expect(projection.currentActionStrip?.actions.map { $0.kind } == [.stop(capability)])
    #expect(projection.currentActionStrip?.mustRemainVisible == true)
  }

  @Test("settled recovery does not replace the next unmet exercise")
  func restartableAttemptDoesNotTrapProgression() {
    let pen = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let boundary = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let snapshot = PlotterLearningPresentationFacts(
      penInteractionCompleted: true,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true,
        cameraStateText: "streaming"
      ),
      operations: .init(restartableItem: pen)
    )

    let projection = project(
      snapshot,
      selectedItemID: pen
    )

    #expect(projection.currentItemID == boundary)
    #expect(projection.currentActionStrip?.ownerID == "\(boundary.number)-\(boundary.title)")
    #expect(
      projection.currentActionStrip?.actions.map(\.kind)
        == [.boundary(.acquire(direction: .positiveX, mode: .normal))]
    )
    #expect(projection.selectedAction.actionStrip?.actions.map(\.kind) == [.restart])
  }

  @Test("reset and vacate inputs are projected but never executed")
  func resetSurface() {
    let anchor = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let plan = LearningVacatePlan(
      scope: .from(anchor),
      source: .live,
      anchor: anchor,
      affectedItems: [anchor],
      expectedCurrentRevisionIDs: [],
      expectedAcceptedAttemptSequence: 7,
      removesDurableMachineCheckpoint: false,
      removesDurableTipCheckpoint: false,
      physicalInkMayRemain: false
    )
    let snapshot = PlotterLearningPresentationFacts(
      reset: .init(
        plansByAnchor: [anchor: plan],
        unavailableReason: "An operation is active."
      )
    )
    let projection = project(
      snapshot,
      selectedItemID: anchor
    )

    #expect(projection.resetSurface.selectedPlan == plan)
    #expect(projection.resetSurface.unavailableReason == "An operation is active.")
    #expect(projection.currentItemID == .humanGuidedDiscovery(.penInteraction))
  }

  @Test("Reset All is projected only in the stable Learning Path menu")
  func resetAllMenuPlacement() {
    let anchor = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let resetAll = LearningVacatePlan(
      scope: .all,
      source: .live,
      anchor: anchor,
      affectedItems: LearningPathItemID.learningExerciseOrder,
      expectedCurrentRevisionIDs: [],
      expectedAcceptedAttemptSequence: 0,
      removesDurableMachineCheckpoint: true,
      removesDurableTipCheckpoint: true,
      physicalInkMayRemain: true
    )
    let snapshot = PlotterLearningPresentationFacts(
      reset: .init(resetAllPlan: resetAll, unavailableReason: "An operation is active.")
    )

    let projection = project(
      snapshot,
      selectedItemID: anchor
    )

    #expect(projection.menu.resetAllPlan == resetAll)
    #expect(projection.resetSurface.selectedPlan == nil)
    #expect(projection.resetSurface.unavailableReason == "An operation is active.")
  }

  @Test("sparse calibration phases select one coherent action path")
  func sparseCalibrationPhases() throws {
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let phases: [(PlotterTipCalibrationPhase, Int, [String])] = [
      (.idle, 0, ["Draw Four Calibration Circles", "Cancel Attempt"]),
      (.marking(PlotterTipCalibrationOperationID()), 0,
        ["Drawing Four Calibration Circles…", "Cancel Attempt"]),
      (.awaitingCompletedPointSelection(try expectedTipSelection(frameID: "frame-1")), 0,
        ["Capture New Click Frame", "Cancel Attempt"]),
      (.capturingNewClickFrame(
        PlotterTipCalibrationOperationID(),
        try expectedTipSelection(frameID: "frame-1")
      ), 0, ["Capturing New Click Frame…", "Cancel Attempt"]),
      (.awaitingCompletedPointSelection(try expectedTipSelection(frameID: "frame-1")), 2,
        [
          "Capture New Click Frame", "Undo Last Click", "Clear Clicks on This Frame",
          "Cancel Attempt",
        ]),
      (.fitting(PlotterTipCalibrationOperationID(), PlotterPointSelectionID()), 4,
        ["Fitting Tip Calibration…", "Cancel Attempt"]),
      (.reviewingProposal, 4,
        [
          "Accept Pen-Tip Calibration", "Undo Last Click", "Clear Clicks on This Frame",
          "Reject Pen-Tip Calibration",
          "Cancel Attempt",
        ]),
      (.committing(PlotterTipCalibrationOperationID(), isRetry: true),
        4, ["Saving or Revalidating Tip Calibration…", "Cancel Attempt"]),
    ]

    for (phase, collectedClickCount, titles) in phases {
      let snapshot = postBoundarySnapshot(
        sparse: .init(phase: phase, collectedClickCount: collectedClickCount),
        operations: .init(activeAttemptOwner: owner)
      )
      let strip = project(
        snapshot,
        selectedItemID: owner
      ).currentActionStrip
      #expect(strip?.actions.map(\.title) == titles)
      if case .committing = phase {
        #expect(!((strip?.actions ?? []).contains {
          $0.kind == .tipCalibration(.retryCommit)
        }))
      }
    }
  }

  @Test("possible ink shows the underlying failure beside paper recovery")
  func possibleInkExplainsCause() throws {
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    let location = BlacklistedToolContactLocation(
      calibrationPosition: .negativeX, machinePosition: try MachinePosition(x: 12, y: 34),
      markRadiusMM: 2, paperInstance: PaperInstanceRevision())
    let reason = "Pen-cap measurement found two equally supported candidates."
    let snapshot = postBoundarySnapshot(
      sparse: .init(phase: .possibleInkBlacklisted(location, reason), blacklistedPositionCount: 1),
      operations: .init(activeAttemptOwner: owner))
    let projection = project(snapshot, selectedItemID: owner)
    let instructions = projection.selectedAction.instructions.accessibilityText
    #expect(instructions.contains(reason))
    #expect(instructions.contains("Ink may already exist"))
    #expect(instructions.contains("Resolve the cause"))
    #expect(projection.currentActionStrip?.actions.map(\.title)
      == ["Record Paper Replacement", "Cancel Attempt"])
  }

  @Test("projected calibration and validation copy matches the four-corner frame workflow")
  func currentWorkflowCopy() {
    let drawingOwner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    let drawingProjection = project(
      postBoundarySnapshot(sparse: .init(acceptedIsCurrent: true)),
      selectedItemID: drawingOwner
    )
    let drawingInstructions = drawingProjection.selectedAction.instructions.accessibilityText
    #expect(drawingInstructions.contains("Draw and Validate Drawing Border"))
    #expect(drawingInstructions.contains("Drawing Border"))
    #expect(!drawingInstructions.contains("5 mm"))
    #expect(!drawingInstructions.contains("isolated line"))
  }

  @Test("drawing phases remain under one visible validation exercise")
  func borderValidationProgression() {
    let current = BorderValidationStep.drawDrawingBorder
    let owner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true),
      drawing: .init(
        currentStep: current
      )
    )
    let currentProjection = project(
      snapshot,
      selectedItemID: owner
    )

    #expect(currentProjection.currentItemID == owner)
    #expect(currentProjection.currentActionStrip?.actions.map(\.kind) == [.start])
    #expect(currentProjection.currentActionStrip?.actions.first?.title == "Resume Drawing Border Validation")
    #expect(currentProjection.selectedAction.itemID == owner)
  }

  @Test("Drawing Border comparison review exposes only explicit accept and reject")
  func borderValidationComparisonReviewActions() throws {
    let owner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true),
      drawing: .init(
        currentStep: .compareIntendedAndObservedGeometry,
        phase: .reviewingComparison(PlotterBorderValidationOperationID())
      ),
      operations: .init(activeAttemptOwner: owner)
    )

    let projection = project(snapshot, selectedItemID: owner)
    let action = projection.selectedAction
    #expect(action.actionStrip?.actions.map(\.kind) == [
      .borderValidation(.acceptObservedPrediction),
      .borderValidation(.reject("Operator rejected the observed Drawing Border comparison.")),
    ])
    #expect(action.actionStrip?.mustRemainVisible == true)
    #expect(action.instructions.accessibilityText.contains("automatically"))
    #expect(!action.instructions.accessibilityText.contains("without another approval"))
  }

  @Test("completed curriculum remains on the Drawing Border validation endpoint")
  func completedCurriculumHasNoFutureRoute() {
    let final = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true),
      drawing: .init(
        currentStep: .compareIntendedAndObservedGeometry,
        assessment: .predictionObserved
      )
    )

    let projection = project(
      snapshot,
      selectedItemID: final
    )

    #expect(projection.currentItemID == final)
    #expect(projection.items.last?.id == final)
    #expect(projection.items.last?.status == .complete)
    #expect(projection.currentActionStrip == nil)
  }

  private func project(
    _ snapshot: PlotterLearningPresentationFacts,
    selectedItemID: LearningPathItemID
  ) -> LearningPathProjection {
    let actionability = PlotterLearningActionabilityFactAdapter().compile(
      snapshot,
      selectedItemID: selectedItemID
    )
    return normalizer.project(
      snapshot,
      selectedItemID: selectedItemID,
      actionability: actionability
    )
  }

  private func connectedSnapshot(
    source: OperatorFrameMode = .live,
    operations: PlotterLearningPresentationFacts.OperationFacts = .init()
  ) -> PlotterLearningPresentationFacts {
    PlotterLearningPresentationFacts(
      source: source,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true,
        cameraStateText: source == .live ? "streaming" : "causal simulated frame"
      ),
      operations: operations
    )
  }

  private func postBoundarySnapshot(
    camera: PlotterLearningPresentationFacts.CameraCalibrationFacts = .init(
      acceptedIsCurrent: true
    ),
    sparse: PlotterLearningPresentationFacts.SparseCalibrationFacts = .init(),
    drawing: PlotterLearningPresentationFacts.DrawingFacts = .init(),
    operations: PlotterLearningPresentationFacts.OperationFacts = .init()
  ) -> PlotterLearningPresentationFacts {
    PlotterLearningPresentationFacts(
      penInteractionCompleted: true,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true
      ),
      boundary: .init(
        acceptedDirections: BoundaryDirection.allCases,
        allowedDirections: [],
        isComplete: true,
        centerArrival: try! MachinePosition(x: 0, y: 0)
      ),
      cameraCalibration: camera,
      sparseCalibration: sparse,
      drawing: drawing,
      operations: operations
    )
  }

  private func expectedTipSelection(
    frameID: String
  ) throws -> PlotterTipCalibrationExpectedPointSelection {
    PlotterTipCalibrationExpectedPointSelection(
      selectionID: PlotterPointSelectionID(),
      exactFrame: PlotterExactFrameReference(
        frameID: frameID,
        frameSHA256: String(repeating: "a", count: 64),
        source: .simulated,
        cameraConfigurationID: CameraConfigurationID(),
        captureNanoseconds: 1,
        sequence: 1,
        width: 640,
        height: 480,
        rowBytes: 2_560,
        pixelFormat: .rgba8
      ),
      presentationTransformRevision: PlotterPresentationTransformRevision()
    )
  }
}
