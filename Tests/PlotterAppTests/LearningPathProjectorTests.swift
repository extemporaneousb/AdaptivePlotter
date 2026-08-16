import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Pure Learning Path projector")
struct LearningPathProjectorTests {
  private let projector = LearningPathProjector()

  @Test("same snapshot and review selection are deterministic")
  func deterministicProjection() {
    let snapshot = LearningPathProjectionSnapshot()
    let first = projector.project(snapshot, selectedItemID: .stage(.observedDrawingTrials))
    let second = projector.project(snapshot, selectedItemID: .stage(.observedDrawingTrials))

    #expect(first == second)
    #expect(first.currentItemID == .stage(.connect))
    #expect(first.selectedAction.itemID == .stage(.observedDrawingTrials))
    #expect(first.selectedAction.status == .next)
  }

  @Test("all navigator rows receive exact initial states")
  func everyNavigatorRowIsProjected() {
    let projection = projector.project(
      LearningPathProjectionSnapshot(),
      selectedItemID: .stage(.connect)
    )

    #expect(projection.items.map(\.id) == LearningPathItemID.navigationOrder)
    #expect(projection.items.count == 9)
    #expect(projection.items.first?.status == .current)
    #expect(projection.items.dropFirst().allSatisfy { $0.status == .next })
  }

  @Test("LIVE and SIMULATED use the same progression and action grammar")
  func liveSimulatedParity() {
    let live = projector.project(
      connectedSnapshot(source: .live),
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
    )
    let simulated = projector.project(
      connectedSnapshot(source: .simulated),
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
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
        stopOwner: .exercise(capability, .moveToEstimatedCenter, boundaryOwner: false)
      )
    )
    let projection = projector.project(snapshot, selectedItemID: owner)

    #expect(projection.contextualStop?.capabilityID == capability)
    #expect(projection.currentActionStrip?.actions.map(\.kind) == [.stop(capability)])
    #expect(projection.currentActionStrip?.mustRemainVisible == true)
  }

  @Test("typed failure kind renders without changing progression authority")
  func typedFailureRendering() {
    let failure = WorkflowFailure(
      kind: .ambiguous,
      detail: "Controller settlement is ambiguous.",
      recovery: .resolveNamedFailure
    )
    let snapshot = connectedSnapshot(
      operations: .init(explorationFailure: failure)
    )
    let projection = projector.project(
      snapshot,
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
    )

    #expect(projection.currentItemID == .humanGuidedDiscovery(.penInteraction))
    #expect(projection.selectedAction.status == .needsAttention)
    #expect(projection.selectedAction.activity?.detail.accessibilityText == failure.detail)
    #expect(projection.selectedAction.activity?.outcome == .needsAttention)
  }

  @Test("settled recovery does not replace the next unmet exercise")
  func restartableAttemptDoesNotTrapProgression() {
    let pen = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let boundary = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let snapshot = LearningPathProjectionSnapshot(
      penInteractionCompleted: true,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true,
        connectionText: "connected",
        motionGuardStateText: "active"
      ),
      operations: .init(restartableItem: pen)
    )

    let projection = projector.project(snapshot, selectedItemID: pen)

    #expect(projection.currentItemID == boundary)
    #expect(projection.currentActionStrip?.ownerID == boundary)
    #expect(projection.currentActionStrip?.actions.map(\.kind) == [.start])
    #expect(projection.selectedAction.status == .needsAttention)
    #expect(projection.selectedAction.actionStrip?.actions.map(\.kind) == [.restart])
  }

  @Test("current-camera calibration does not project a manual-motion gate")
  func currentCameraCalibrationDoesNotGateManualMotion() {
    let snapshot = LearningPathProjectionSnapshot(
      source: .live,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true,
        connectionText: "connected",
        cameraStateText: "streaming",
        motionGuardStateText: "active"
      ),
      cameraCalibration: .init(phase: .capturing(sample: 2, total: 5, role: "fit"))
    )
    let projection = projector.project(
      snapshot,
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
    )
    let controller = projection.selectedAction.subsystemStatuses.first { $0.id == "controller" }
    let vision = projection.selectedAction.subsystemStatuses.first { $0.id == "vision" }

    #expect(controller?.state == "Calibration active / manual controls independent")
    #expect(controller?.blocksNewMotion == false)
    #expect(vision?.blocksNewMotion == false)
    #expect(vision?.detail.accessibilityText.contains("does not gate direct manual controls") == true)
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
    let snapshot = LearningPathProjectionSnapshot(
      reset: .init(
        plansByAnchor: [anchor: plan],
        unavailableReason: "An operation is active."
      )
    )
    let projection = projector.project(snapshot, selectedItemID: anchor)

    #expect(projection.resetSurface.selectedPlan == plan)
    #expect(projection.resetSurface.unavailableReason == "An operation is active.")
    #expect(projection.currentItemID == .stage(.connect))
  }

  @Test("sparse calibration phases select one coherent action path")
  func sparseCalibrationPhases() throws {
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let phases: [(SparseTipCalibrationPhase, Int, [String])] = [
      (.idle, 0, ["Draw Five 2 mm Circles", "Cancel Attempt"]),
      (.drawingBatch, 0, ["Drawing Five 2 mm Circles…", "Cancel Attempt"]),
      (.revealingBatch, 0, ["Revealing Five Circles…", "Cancel Attempt"]),
      (.awaitingFrozenClicks(FrameID(rawValue: "frame-1")), 0, ["Cancel Attempt"]),
      (.awaitingFrozenClicks(FrameID(rawValue: "frame-1")), 2,
        ["Undo Last Click", "Clear Clicks on This Frame", "Cancel Attempt"]),
      (.fittingModel, 5, ["Fitting and Committing Tip Calibration…", "Cancel Attempt"]),
      (.committingModel(.constantCameraPixelCorrection),
        5, ["Retry Calibration Commit", "Cancel Attempt"]),
    ]

    for (phase, collectedClickCount, titles) in phases {
      let snapshot = postBoundarySnapshot(
        sparse: .init(phase: phase, collectedClickCount: collectedClickCount),
        operations: .init(activeAttemptOwner: owner)
      )
      let strip = projector.project(snapshot, selectedItemID: owner).currentActionStrip
      #expect(strip?.actions.map(\.title) == titles)
    }
  }

  @Test("Drawing Trial phases remain under one visible Go-owned exercise")
  func drawingTrialProgression() throws {
    let current = ObservedDrawingTrialStep.drawIsolatedLine
    let owner = LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true),
      drawing: .init(
        currentStep: current
      )
    )
    let currentProjection = projector.project(
      snapshot,
      selectedItemID: owner
    )

    #expect(currentProjection.currentItemID == owner)
    #expect(currentProjection.currentActionStrip?.actions.map(\.kind) == [.start])
    #expect(currentProjection.currentActionStrip?.actions.first?.title == "Continue Trial")
    #expect(currentProjection.selectedAction.itemID == owner)
    #expect(currentProjection.selectedAction.timeline?.position == current.rawValue)
    #expect(currentProjection.selectedAction.status == .current)
  }

  @Test("foreground trial Vision is visible as the operation owner")
  func foregroundTrialVisionIsVisible() throws {
    let owner = LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true),
      drawing: .init(currentStep: .revealAndObserveNewInk),
      operations: .init(
        activeAttemptOwner: owner,
        workflowVisionActive: true
      )
    )

    let projection = projector.project(snapshot, selectedItemID: owner)
    let vision = try #require(
      projection.selectedAction.subsystemStatuses.first { $0.id == "vision" }
    )

    #expect(vision.state == "Trial ink analysis · active")
    #expect(vision.role == .operationOwner)
    #expect(projection.selectedAction.activity?.phase == "Phase 5 of 6")
    #expect(
      projection.selectedAction.activity?.detail.accessibilityText.contains(
        "Vision is comparing"
      ) == true
    )
  }

  @Test("completed curriculum remains on the one-Go observed-trial endpoint")
  func completedCurriculumHasNoFutureRoute() {
    let final = LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true),
      drawing: .init(
        currentStep: .compareIntendedAndObservedGeometry,
        assessment: .predictionObserved
      )
    )

    let projection = projector.project(snapshot, selectedItemID: final)

    #expect(projection.currentItemID == final)
    #expect(projection.items.last?.id == final)
    #expect(projection.items.last?.status == .complete)
    #expect(projection.currentActionStrip == nil)
  }

  private func connectedSnapshot(
    source: OperatorFrameMode = .live,
    operations: LearningPathProjectionSnapshot.OperationFacts = .init()
  ) -> LearningPathProjectionSnapshot {
    LearningPathProjectionSnapshot(
      source: source,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true,
        connectionText: source == .live ? "connected" : "simulator connected",
        motionGuardStateText: "active"
      ),
      operations: operations
    )
  }

  private func postBoundarySnapshot(
    sparse: LearningPathProjectionSnapshot.SparseCalibrationFacts = .init(),
    drawing: LearningPathProjectionSnapshot.DrawingFacts = .init(),
    operations: LearningPathProjectionSnapshot.OperationFacts = .init()
  ) -> LearningPathProjectionSnapshot {
    LearningPathProjectionSnapshot(
      penInteractionCompleted: true,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true,
        connectionText: "connected",
        motionGuardStateText: "active"
      ),
      boundary: .init(
        acceptedDirections: BoundaryDirection.allCases,
        allowedDirections: [],
        isComplete: true,
        centerArrival: try! MachinePosition(x: 0, y: 0)
      ),
      cameraCalibration: .init(acceptedIsCurrent: true),
      sparseCalibration: sparse,
      drawing: drawing,
      operations: operations
    )
  }
}
