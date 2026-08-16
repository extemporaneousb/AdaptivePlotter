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
    #expect(first.selectedAction.item.id == .stage(.observedDrawingTrials))
    #expect(first.selectedAction.item.status == .next)
    #expect(first.selectedAction.heading == "4 - Observed Drawing Trials")
  }

  @Test("the projector consumes the canonical tree order")
  func everyNavigatorRowIsProjected() {
    let projection = projector.project(
      LearningPathProjectionSnapshot(),
      selectedItemID: .stage(.connect)
    )

    #expect(projection.items.map(\.id) == LearningPathTree.curriculum.flattenedItems)
    #expect(projection.items.count == 14)
    #expect(projection.items.first?.status == .current)
    #expect(projection.items.dropFirst().allSatisfy { $0.status == .next })
    #expect(projection.selectedAction.actionStrip == nil)
  }

  @Test("LIVE and SIMULATED use the same progression and control grammar")
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
    #expect(live.selectedAction.script == simulated.selectedAction.script)
  }

  @Test("active Boundary projects Stop & Accept, Stop, and Cancel under one capability")
  func boundaryTerminationControls() {
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    )
    let snapshot = connectedSnapshot(
      operations: .init(
        activeAttemptOwner: owner,
        stopOwner: .pairedBoundary(capability, .positiveX)
      )
    )
    let projection = projector.project(snapshot, selectedItemID: owner)
    let actions = projection.selectedAction.actionStrip?.actions

    #expect(projection.contextualStop?.capabilityID == capability)
    #expect(actions?.map(\.kind) == [
      .stopAndAcceptBoundary(capability),
      .stop(capability),
      .cancel(capability),
    ])
    #expect(actions?.map(\.title) == ["Stop & Accept", "Stop", "Cancel"])
    #expect(actions?.map(\.buttonRole) == [.commit, .interrupt, .interrupt])
    #expect(actions?.map(\.keyboardShortcut) == [nil, .escape, nil])
    #expect(projection.selectedAction.actionStrip?.mustRemainVisible == true)
    #expect(
      projection.selectedAction.question?.prompt.accessibilityText
        == "How should this Boundary motion end?"
    )
  }

  @Test("non-Boundary Stop remains capability-bound and red")
  func nonBoundaryStopOwnership() {
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let capability = ContextualStopCapabilityID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
    )
    let snapshot = connectedSnapshot(
      operations: .init(
        activeAttemptOwner: owner,
        stopOwner: .exercise(capability, .moveToEstimatedCenter, boundaryOwner: false)
      )
    )
    let action = projector.project(snapshot, selectedItemID: owner)
      .selectedAction.actionStrip?.actions.first

    #expect(action?.kind == .stop(capability))
    #expect(action?.buttonRole == .interrupt)
    #expect(action?.keyboardShortcut == .escape)
  }

  @Test("operational failure changes status but is not printed into the Exercise script")
  func diagnosticsStayOutOfPrimaryExercise() {
    let failure = WorkflowFailure(
      kind: .ambiguous,
      detail: "Controller settlement is ambiguous.",
      recovery: .resolveNamedFailure
    )
    let projection = projector.project(
      connectedSnapshot(operations: .init(explorationFailure: failure)),
      selectedItemID: .humanGuidedDiscovery(.penInteraction)
    )
    let visibleScript = projection.selectedAction.script
      .map { $0.fragments.accessibilityText }
      .joined(separator: " ")

    #expect(projection.selectedAction.item.status == .needsAttention)
    #expect(!visibleScript.contains(failure.detail))
  }

  @Test("selected leaf or branch invalidation is compactly projected, never executed")
  func invalidationPresentation() {
    let branch = LearningPathItemID.stage(.humanGuidedDiscovery)
    let affected = LearningPathTree.curriculum.descendantLeaves(of: branch)
    let plan = LearningInvalidationPlan(
      scope: .subtree(root: branch),
      source: .live,
      affectedItemIDs: affected,
      expectedCurrentRevisionIDs: [],
      expectedGraphRevision: 7,
      expectedAcceptedAttemptSequence: 9,
      expectedAuthorityManifestRevision: .valid(
        generation: 8,
        payloadSHA256: String(repeating: "8", count: 64)
      ),
      removesDurableMachineRegistration: true,
      removesDurableTipRegistration: true,
      physicalInkMayRemain: true
    )
    let snapshot = LearningPathProjectionSnapshot(
      invalidation: .init(
        plansByRoot: [branch: plan],
        unavailableReason: "An operation is active."
      )
    )
    let projection = projector.project(snapshot, selectedItemID: branch)

    #expect(projection.selectedAction.invalidation.selectedPlan == plan)
    #expect(projection.selectedAction.invalidation.unavailableReason == "An operation is active.")
    #expect(projection.selectedAction.invalidation.selectedPlan?.scope == .subtree(root: branch))
  }

  @Test("review selection has no duplicate current action strip")
  func reviewIsInert() {
    let current = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let reviewed = LearningPathItemID.stage(.observedDrawingTrials)
    let projection = projector.project(
      connectedSnapshot(),
      selectedItemID: reviewed
    )

    #expect(projection.currentItemID == current)
    #expect(projection.selectedAction.item.id == reviewed)
    #expect(projection.selectedAction.actionStrip == nil)
  }

  @Test("Drawing Trial current and review presentations remain snapshot-local")
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
    #expect(currentProjection.selectedAction.actionStrip?.actions.map(\.kind) == [.drawIsolatedLine])
    #expect(reviewProjection.currentItemID == currentProjection.currentItemID)
    #expect(reviewProjection.selectedAction.item.status == .complete)
  }

  @Test("accepted sparse calibration offers only explicit Paper Replacement")
  func acceptedSparseRepeatRequiresPaperReplacement() {
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let snapshot = postBoundarySnapshot(
      sparse: .init(acceptedIsCurrent: true, phase: .accepted)
    )
    let projection = projector.project(snapshot, selectedItemID: owner)

    #expect(
      projection.selectedAction.actionStrip?.actions.map(\.kind)
        == [.paperReplaced]
    )

    let unavailable = projector.project(
      postBoundarySnapshot(
        sparse: .init(
          acceptedIsCurrent: true,
          phase: .accepted,
          paperReplacementUnavailableReason: "Safety history is unavailable."
        )
      ),
      selectedItemID: owner
    )
    #expect(
      unavailable.selectedAction.actionStrip?.actions.first?.isEnabled == false
    )
  }

  @Test("completed Boundary and generic repeat controls preserve current admission blockers")
  func completedRepeatAdmissionReasons() {
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let blocker = "Enable Motion before repeating this exercise."
    let snapshot = postBoundarySnapshot(
      startUnavailableReasons: [
        boundaryOwner: blocker,
        penOwner: blocker,
      ]
    )

    let boundaryActions = projector.project(snapshot, selectedItemID: boundaryOwner)
      .selectedAction.actionStrip?.actions ?? []
    #expect(boundaryActions.count == BoundaryDirection.allCases.count * 2)
    #expect(
      boundaryActions.allSatisfy {
        !$0.isEnabled && $0.unavailableReason == blocker
      }
    )
    #expect(
      boundaryActions.contains {
        if case .redoBoundary = $0.kind { true } else { false }
      }
    )
    #expect(
      boundaryActions.contains {
        if case .recordAnotherBoundaryAttempt = $0.kind { true } else { false }
      }
    )

    let penActions = projector.project(snapshot, selectedItemID: penOwner)
      .selectedAction.actionStrip?.actions ?? []
    #expect(penActions.map(\.kind) == [.redoThisStep, .recordAnotherAttempt])
    #expect(
      penActions.allSatisfy {
        !$0.isEnabled && $0.unavailableReason == blocker
      }
    )
  }

  @Test("current sparse calibration projects the typed manifest admission blocker")
  func sparseStartAdmissionReason() {
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let blocker = "LIVE contact is blocked by the Learning-authority manifest."
    let projection = projector.project(
      postBoundarySnapshot(startUnavailableReasons: [owner: blocker]),
      selectedItemID: owner
    )
    let start = projection.selectedAction.actionStrip?.actions.first

    #expect(projection.currentItemID == owner)
    #expect(start?.kind == .start)
    #expect(start?.isEnabled == false)
    #expect(start?.unavailableReason == blocker)
  }

  @Test("human decision actions include one explicit question")
  func humanDecisionQuestions() {
    let camera = projector.project(
      postBoundarySnapshot(
        camera: .init(hasProposal: true)
      ),
      selectedItemID: .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    )
    let tip = projector.project(
      postBoundarySnapshot(
        sparse: .init(phase: .reviewingFinalProposal(.constantCameraPixelCorrection))
      ),
      selectedItemID: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )
    let comparison = projector.project(
      postBoundarySnapshot(
        sparse: .init(acceptedIsCurrent: true),
        drawing: .init(currentStep: .compareIntendedAndObservedGeometry)
      ),
      selectedItemID: .observedDrawingTrial(.compareIntendedAndObservedGeometry)
    )
    let completedComparison = projector.project(
      postBoundarySnapshot(
        sparse: .init(acceptedIsCurrent: true),
        drawing: .init(
          currentStep: .compareIntendedAndObservedGeometry,
          assessment: .observedGeometryAccepted
        )
      ),
      selectedItemID: .observedDrawingTrial(.compareIntendedAndObservedGeometry)
    )

    #expect(
      camera.selectedAction.question?.prompt.accessibilityText
        == "Should this camera and visible-cap fit become current?"
    )
    #expect(
      tip.selectedAction.question?.prompt.accessibilityText
        == "Should this tip calibration become current?"
    )
    #expect(
      comparison.selectedAction.question?.prompt.accessibilityText
        == "Does the observed ink geometry match the intended line?"
    )
    #expect(completedComparison.selectedAction.question == nil)
  }

  @Test("typed safety recovery makes Paper Replacement the sole action before checkpoint revalidation")
  func paperReplacementPrecedesCheckpointRevalidation() {
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let projection = projector.project(
      postBoundarySnapshot(
        sparse: .init(
          savedCheckpointMatchesPaper: true,
          requiresPaperReplacement: true
        )
      ),
      selectedItemID: owner
    )

    #expect(projection.selectedAction.actionStrip?.actions.map(\.kind) == [.paperReplaced])
    #expect(projection.selectedAction.actionStrip?.actions.first?.isEnabled == true)
  }

  private func connectedSnapshot(
    source: OperatorFrameMode = .live,
    operations: LearningPathProjectionSnapshot.OperationFacts = .init()
  ) -> LearningPathProjectionSnapshot {
    LearningPathProjectionSnapshot(
      source: source,
      controller: .init(
        sessionEstablished: true,
        motionAuthorized: true
      ),
      operations: operations
    )
  }

  private func postBoundarySnapshot(
    camera: LearningPathProjectionSnapshot.CameraCalibrationFacts = .init(
      acceptedIsCurrent: true
    ),
    sparse: LearningPathProjectionSnapshot.SparseCalibrationFacts = .init(),
    drawing: LearningPathProjectionSnapshot.DrawingFacts = .init(),
    operations: LearningPathProjectionSnapshot.OperationFacts = .init(),
    startUnavailableReasons: [LearningPathItemID: String] = [:]
  ) -> LearningPathProjectionSnapshot {
    LearningPathProjectionSnapshot(
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
      operations: operations,
      startUnavailableReasons: startUnavailableReasons
    )
  }
}
