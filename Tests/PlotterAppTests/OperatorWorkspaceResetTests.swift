import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("Reset All LIVE Learning clears a quarantined durable tip checkpoint")
  func resetAllLiveLearningClearsTipCheckpoint() async throws {
    let checkpointBox = TipCheckpointBox()
    let actions = OperatorWorkspace.AcceptedTipCalibrationCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let seeded = makeSimulatedHarness()
    try await completeSimulatedBoundariesAndCenter(
      seeded.workspace,
      runtime: seeded.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(
      seeded.workspace,
      runtime: seeded.runtime
    )
    let registration = try #require(seeded.workspace.tipCameraRegistration)
    try checkpointBox.save(
      AcceptedTipCalibrationCheckpoint(
        registration: registration,
        acceptanceEvent: TipCalibrationAcceptanceEvent(
          acceptedRevisionID: registration.acceptedRevisionID,
          timestamp: registration.acceptedAt,
          actor: "test fixture"
        )
      )
    )

    let liveRestart = makeSimulatedHarness(tipCheckpointActions: actions)
    #expect(liveRestart.workspace.frameMode == .live)
    #expect(liveRestart.workspace.quarantinedTipCalibrationCheckpoint != nil)
    let plan = try #require(liveRestart.workspace.resetAllLearningPlan)
    #expect(plan.removesDurableTipCheckpoint)
    #expect(!plan.removesDurableMachineCheckpoint)
    #expect(liveRestart.workspace.performLearningVacate(plan))
    #expect(checkpointBox.checkpoint == nil)
    #expect(liveRestart.workspace.quarantinedTipCalibrationCheckpoint == nil)
  }

  @Test("Reset All LIVE Learning clears durable authority but retains session facts")
  func resetAllLiveLearningClearsCheckpointAndRetainsSessionFacts() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let checkpointBox = CheckpointBox()
    let checkpointActions = OperatorWorkspace.AcceptedArtifactCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      checkpointActions: checkpointActions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    let stalePlan = try #require(workspace.resetAllLearningPlan)
    await workspace.beginPairedBoundarySide(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    #expect(checkpointBox.checkpoint != nil)
    #expect(!workspace.performLearningVacate(stalePlan))
    #expect(workspace.boundarySideAggregates[.positiveX] != nil)
    #expect(
      workspace.learningAuthorityError?.contains("changed while the reset summary was open") == true
    )

    let plan = try #require(workspace.resetAllLearningPlan)
    #expect(plan.source == .live)
    #expect(plan.anchor == .humanGuidedDiscovery(.penInteraction))
    #expect(plan.removesDurableCheckpoint)
    #expect(plan.title == "Reset All Learning")
    #expect(workspace.performLearningVacate(plan))

    #expect(checkpointBox.checkpoint == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveX))
        == nil
    )
    #expect(workspace.penAttemptHistory.records.isEmpty)
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(
      workspace.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )
    #expect(workspace.acceptedArtifactCheckpointStatus == .cleared)
    await workspace.shutdown()
  }

  @Test("Reset from Boundary retains Pen and removes every later SIMULATED result")
  func resetBoundaryForwardRetainsEarlierLearning() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    let penRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let anchor = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let plan = try #require(workspace.learningVacatePlan(from: anchor))
    #expect(plan.source == .simulated)
    #expect(!plan.removesDurableCheckpoint)
    #expect(!plan.physicalInkMayRemain)
    #expect(plan.title == "Reset From This Step")
    #expect(workspace.performLearningVacate(plan))

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
        == penRevisionID
    )
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.estimatedMachineCenter == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.currentLearningPathItemID == anchor)
    await workspace.shutdown()
  }

  @Test("Reset comparison only preserves the observed line and performs no redraw")
  func resetComparisonOnlyPreservesObservedLine() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    try await completeSimulatedStageFour(workspace)
    let linePlan = try #require(
      workspace.learningArtifactGraph.revisions.first { revision in
        guard revision.state == .current else { return false }
        if case .linePlan = revision.kind { return true }
        return false
      })
    guard case .linePlan(let group) = linePlan.kind else {
      Issue.record("Expected the current line-plan revision to carry its attempt group.")
      return
    }
    let linePlanID = linePlan.id
    let inkID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .inkObservation(group))?.id
    )
    let inkBefore = await harness.runtime.persistentInk()
    let anchor = LearningPathItemID.observedDrawingTrial(
      .compareIntendedAndObservedGeometry
    )
    let plan = try #require(workspace.learningVacatePlan(from: anchor))
    #expect(plan.affectedItems == [anchor])
    #expect(plan.expectedCurrentRevisionIDs.count == 1)
    #expect(workspace.performLearningVacate(plan))

    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .comparison(group)) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .linePlan(group))?.id == linePlanID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .inkObservation(group))?.id == inkID
    )
    #expect(workspace.currentLearningPathItemID == anchor)
    #expect(await harness.runtime.persistentInk() == inkBefore)
    await workspace.shutdown()
  }

  @Test("Reset a completed transition row even when it owns no artifact revision")
  func resetCompletedTransitionWithoutArtifact() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    try await performPublicAction(
      .chooseIsolatedLinePlan(.positiveX),
      owner: .observedDrawingTrial(.chooseIsolatedLinePlan),
      workspace: workspace
    )
    try await performPublicAction(
      .captureLocalPreLineBaseline,
      owner: .observedDrawingTrial(.captureLocalPreLineBaseline),
      workspace: workspace
    )
    try await performPublicAction(
      .moveToLineStart,
      owner: .observedDrawingTrial(.moveToLineStart),
      workspace: workspace
    )
    #expect(workspace.lastProtocolPoseSettlement != nil)

    let anchor = LearningPathItemID.observedDrawingTrial(.moveToLineStart)
    let plan = try #require(workspace.learningVacatePlan(from: anchor))
    #expect(plan.expectedCurrentRevisionIDs.isEmpty)
    #expect(plan.affectedItems.first == anchor)
    #expect(plan.affectedItems.last == .observedDrawingTrial(.drawIsolatedLine))
    #expect(workspace.performLearningVacate(plan))

    #expect(workspace.currentLearningPathItemID == anchor)
    #expect(workspace.lastProtocolPoseSettlement == nil)
    #expect(workspace.localPreLineBaseline != nil)
    await workspace.shutdown()
  }
}
