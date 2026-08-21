import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("Reset All remains available and succeeds when LIVE Learning is already fresh")
  func resetAllFreshLiveLearningIsStable() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let checkpointBox = LearningPathCheckpointBox()
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()

    let plan = try #require(workspace.resetAllLearningPlan)
    let didReset = await workspace.performResetAllLearning(plan)

    #expect(didReset)
    #expect(plan.source == .live)
    #expect(plan.anchor == .humanGuidedDiscovery(.penInteraction))
    #expect(checkpointBox.checkpoint == nil)
    #expect(checkpointBox.operationCounts.clears == 1)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.learningArtifactGraph.revisions.isEmpty)
    #expect(
      workspace.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )
    await workspace.shutdown()
  }

  @Test(
    "Reset All cancels a pending Pen Interaction and preserves controller Camera and Motion"
  )
  func resetAllCancelsPendingPenInteractionAndPreservesSessionFacts() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let camera = try CameraFixture()
    let checkpointBox = LearningPathCheckpointBox()
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let workspace = workspace(
      machine: machine,
      camera: camera,
      learningPathCheckpointActions: actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let selectedCameraID = try #require(workspace.selectedCameraID)

    await workspace.beginPenInteraction()
    #expect(workspace.activeExerciseAttemptID != nil)
    #expect(workspace.actionSurfacePresentation.pointSelectionRequest != nil)
    let plan = try #require(workspace.resetAllLearningPlan)
    let boundaryRequestsBeforeReset = await machine.requestedBoundaryRequests
    let drawingRequestsBeforeReset = await machine.requestedDrawingStrokes
    let penRequestsBeforeReset = await machine.requestedPenCommands
    let cancelCountBeforeReset = await machine.cancelCount

    let didReset = await workspace.performResetAllLearning(plan)

    #expect(didReset)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.actionSurfacePresentation.pointSelectionRequest == nil)
    #expect(checkpointBox.checkpoint == nil)
    #expect(workspace.learningArtifactGraph.revisions.isEmpty)
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(workspace.selectedCameraID == selectedCameraID)
    #expect(workspace.cameraIsLive)
    #expect(await machine.requestedBoundaryRequests == boundaryRequestsBeforeReset)
    #expect(await machine.requestedDrawingStrokes == drawingRequestsBeforeReset)
    #expect(await machine.requestedPenCommands == penRequestsBeforeReset)
    #expect(await machine.cancelCount == cancelCountBeforeReset)
    #expect(workspace.motionUnavailableReason == nil)

    let manualJog = await workspace.requestRelativeJog(
      RelativeJogRequest(
        delta: try Vector2(dx: 1, dy: 0),
        feedMMPerMinute: 100
      )
    )
    guard case .acceptedThenCompleted = manualJog else {
      Issue.record("Expected manual motion to remain admitted after Reset All.")
      await workspace.shutdown()
      return
    }
    await workspace.shutdown()
  }

  @Test("Reset All cancels and settles the active Learning-owned Boundary motion")
  func resetAllCancelsAndSettlesActiveBoundaryMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginPairedBoundarySide(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let plan = try #require(workspace.resetAllLearningPlan)
    let didReset = await workspace.performResetAllLearning(plan)

    #expect(didReset)
    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.cancelAttempt])
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.learningArtifactGraph.revisions.allSatisfy { $0.state != .current })
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(
      workspace.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )
    await workspace.shutdown()
  }

  @Test("Reset All leaves an independent manual motion owner running")
  func resetAllDoesNotCancelManualMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let request = RelativeJogRequest(
      delta: try Vector2(dx: 1, dy: 0),
      feedMMPerMinute: 100
    )
    let owner = Task { await workspace.requestRelativeJog(request) }
    try await waitUntil { workspace.manualMotionPresentation.stopAction != nil }
    let capabilityID = try #require(
      workspace.manualMotionPresentation.stopAction?.capabilityID
    )
    let plan = try #require(workspace.resetAllLearningPlan)

    let didReset = await workspace.performResetAllLearning(plan)

    #expect(didReset)
    #expect(await machine.cancelCount == 0)
    #expect(workspace.manualMotionPresentation.stopAction?.capabilityID == capabilityID)
    #expect(workspace.learningArtifactGraph.revisions.allSatisfy { $0.state != .current })
    #expect(
      workspace.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )

    await workspace.stopManualMotion(capabilityID: capabilityID)
    _ = await owner.value
    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    await workspace.shutdown()
  }

  @Test("Reset All reports durable-clear failure without invalidating accepted Learning")
  func resetAllDurableClearFailureIsAtomic() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let checkpointBox = LearningPathCheckpointBox()
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { throw ResetPersistenceFixtureError.refused }
    )
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    let penRevision = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    #expect(checkpointBox.checkpoint != nil)

    let plan = try #require(workspace.resetAllLearningPlan)
    let didReset = await workspace.performResetAllLearning(plan)

    #expect(!didReset)
    #expect(checkpointBox.checkpoint != nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == penRevision
    )
    #expect(!workspace.penAttemptHistory.records.isEmpty)
    #expect(workspace.learningAuthorityError?.contains("no reset was applied") == true)
    await workspace.shutdown()
  }

  @Test("partial reset does not mutate memory when durable prefix replacement fails")
  func partialResetPersistenceFailureIsAtomic() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { .absent },
      save: { _ in throw ResetPersistenceFixtureError.refused },
      clear: {}
    )
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginPairedBoundarySide(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    let boundaryRevision = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveX))
    )
    let plan = try #require(
      workspace.learningVacatePlan(
        from: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      )
    )

    #expect(!workspace.performLearningVacate(plan))
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveX))
        == boundaryRevision
    )
    #expect(workspace.boundarySideAggregates[.positiveX] != nil)
    #expect(workspace.learningAuthorityError?.contains("no reset was applied") == true)
    await workspace.shutdown()
  }

  @Test("Reset All LIVE Learning clears a quarantined durable tip checkpoint")
  func resetAllLiveLearningClearsTipCheckpoint() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = LearningPathCheckpointBox()
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let seeded = makeSimulatedHarness(tipCalibrationSemanticIdentities: identities)
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
    let tipCheckpoint = try AcceptedTipCalibrationCheckpoint(
        registration: registration,
        acceptanceEvent: TipCalibrationAcceptanceEvent(
          acceptedRevisionID: registration.acceptedRevisionID,
          timestamp: registration.acceptedAt,
          actor: "test fixture"
        )
      )
    checkpointBox.save(
      try AcceptedLearningPathCheckpoint(
        semanticIdentity: identities.learningPathIdentity,
        tipCalibration: tipCheckpoint
      )
    )

    let liveRestart = makeSimulatedHarness(
      learningPathCheckpointActions: actions,
      tipCalibrationSemanticIdentities: identities
    )
    #expect(liveRestart.workspace.frameMode == .live)
    #expect(liveRestart.workspace.quarantinedTipCalibrationCheckpoint != nil)
    let plan = try #require(liveRestart.workspace.resetAllLearningPlan)
    #expect(plan.removesDurableTipCheckpoint)
    #expect(!plan.removesDurableMachineCheckpoint)
    let didReset = await liveRestart.workspace.performResetAllLearning(plan)
    #expect(didReset)
    #expect(checkpointBox.checkpoint == nil)
    #expect(liveRestart.workspace.quarantinedTipCalibrationCheckpoint == nil)
  }

  @Test("Reset All LIVE Learning clears durable authority but retains session facts")
  func resetAllLiveLearningClearsCheckpointAndRetainsSessionFacts() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let checkpointBox = LearningPathCheckpointBox()
    let checkpointActions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: checkpointActions,
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
    let didReset = await workspace.performResetAllLearning(plan)
    #expect(didReset)

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

  @Test(
    "unchanged restart keeps restored Learning current and Reset All clears it"
  )
  func resetAllClearsRestoredPoseApplicabilityWithoutGatingManualMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = LearningPathCheckpointBox()
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let first = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: actions,
      tipCalibrationSemanticIdentities: identities,
      log: log
    )
    await first.establishMachineSession(machine.descriptor)
    await first.requestPassiveProbe()
    await first.startCamera()
    try await completePenInteraction(first)
    await first.beginPairedBoundarySide(.positiveX)
    try await waitUntil { first.contextualStopPresentation != nil }
    try await stopActiveOperation(first)
    #expect(checkpointBox.checkpoint?.machineArtifacts != nil)

    let relaunched = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: actions,
      tipCalibrationSemanticIdentities: identities,
      log: log
    )
    await relaunched.establishMachineSession(machine.descriptor)
    await relaunched.requestPassiveProbe()
    await relaunched.startCamera()
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    #expect(relaunched.currentLearningPathItemID == .humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    ))

    #expect(relaunched.motionAuthorizationEnabled)
    #expect(relaunched.motionUnavailableReason == nil)
    let manualJog = await relaunched.requestRelativeJog(
      RelativeJogRequest(
        delta: try Vector2(dx: 1, dy: 0),
        feedMMPerMinute: 100
      )
    )
    guard case .acceptedThenCompleted = manualJog else {
      Issue.record(
        "Expected restored Learning to remain outside manual-motion admission."
      )
      await first.shutdown()
      await relaunched.shutdown()
      return
    }

    let plan = try #require(relaunched.resetAllLearningPlan)
    let didReset = await relaunched.performResetAllLearning(plan)
    #expect(didReset)
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    #expect(checkpointBox.checkpoint == nil)
    #expect(
      relaunched.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )
    #expect(relaunched.discoveryStartUnavailableReason(for: .penInteraction) == nil)

    await relaunched.beginPenInteraction()
    #expect(relaunched.activeExerciseAttemptID != nil)
    #expect(relaunched.actionSurfacePresentation.pointSelectionRequest != nil)
    await first.shutdown()
    await relaunched.shutdown()
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

  @Test("Reset the one-Go observed trial atomically and perform no redraw")
  func resetObservedTrialAtomically() async throws {
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
    let inkBefore = await harness.runtime.persistentInk()
    let anchor = LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    let plan = try #require(workspace.learningVacatePlan(from: anchor))
    #expect(plan.affectedItems == [anchor])
    #expect(plan.expectedCurrentRevisionIDs.count == 7)
    #expect(workspace.performLearningVacate(plan))

    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.drawingTrialLineStart == nil)
    #expect(workspace.localPreLineBaseline == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .comparison(group)) == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .linePlan(group)) == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .inkObservation(group)) == nil)
    #expect(workspace.currentLearningPathItemID == anchor)
    #expect(await harness.runtime.persistentInk() == inkBefore)
    await workspace.shutdown()
  }
}

private enum ResetPersistenceFixtureError: Error {
  case refused
}
