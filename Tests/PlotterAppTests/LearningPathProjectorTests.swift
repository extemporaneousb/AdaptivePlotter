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
    let first = projector.project(snapshot, selectedItemID: .stage(.adaptiveDrawing))
    let second = projector.project(snapshot, selectedItemID: .stage(.adaptiveDrawing))

    #expect(first == second)
    #expect(first.currentItemID == .stage(.connect))
    #expect(first.selectedAction.itemID == .stage(.adaptiveDrawing))
    #expect(first.selectedAction.status == .future)
  }

  @Test("all navigator rows receive exact initial states")
  func everyNavigatorRowIsProjected() {
    let projection = projector.project(
      LearningPathProjectionSnapshot(),
      selectedItemID: .stage(.connect)
    )

    #expect(projection.items.map(\.id) == LearningPathItemID.navigationOrder)
    #expect(projection.items.count == 15)
    #expect(projection.items.first?.status == .current)
    #expect(projection.items.dropFirst().dropLast().allSatisfy { $0.status == .next })
    #expect(projection.items.last?.status == .future)
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
    let phases: [(SparseTipCalibrationPhase, [String])] = [
      (.idle, ["Create Next 2 mm Circle", "Cancel Attempt"]),
      (.awaitingFrozenClick(.center, FrameID(rawValue: "frame-1")), ["Cancel Attempt"]),
      (.reviewingClick(.center, FrameID(rawValue: "frame-1")),
        ["Re-click This Exact Frame", "Accept Mark Center", "Cancel Attempt"]),
      (.fittingCandidates, ["Fitting Smallest Passing Model…", "Cancel Attempt"]),
      (.reviewingFinalProposal(.constantCameraPixelCorrection),
        ["Accept Tip Calibration", "Reject Tip Calibration", "Cancel Attempt"]),
    ]

    for (phase, titles) in phases {
      let snapshot = postBoundarySnapshot(
        sparse: .init(phase: phase),
        operations: .init(activeAttemptOwner: owner)
      )
      let strip = projector.project(snapshot, selectedItemID: owner).currentActionStrip
      #expect(strip?.actions.map(\.title) == titles)
    }
  }

  @Test("Drawing Trial progression and review are snapshot-local")
  func drawingTrialProgression() throws {
    let current = ObservedDrawingTrialStep.drawIsolatedLine
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true),
      drawing: .init(
        currentStep: current,
        completedArtifactSteps: [.chooseIsolatedLinePlan, .captureLocalPreLineBaseline]
      )
    )
    let currentProjection = projector.project(
      snapshot,
      selectedItemID: .observedDrawingTrial(current)
    )
    let reviewProjection = projector.project(
      snapshot,
      selectedItemID: .observedDrawingTrial(.chooseIsolatedLinePlan)
    )

    #expect(currentProjection.currentItemID == .observedDrawingTrial(current))
    #expect(currentProjection.currentActionStrip?.actions.map(\.kind) == [.drawIsolatedLine])
    #expect(reviewProjection.currentItemID == currentProjection.currentItemID)
    #expect(reviewProjection.selectedAction.itemID == .observedDrawingTrial(.chooseIsolatedLinePlan))
    #expect(reviewProjection.selectedAction.status == .complete)
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
