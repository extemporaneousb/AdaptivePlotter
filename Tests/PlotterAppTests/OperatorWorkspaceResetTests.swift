import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("declining saved training preserves the package and all inactive authority")
  func startNewLearningRetainsSavedPackageWithoutApplyingIt() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpoint = try AcceptedLearningPathCheckpoint(
      semanticIdentity: identities.learningPathIdentity
    )
    let box = LearningPathCheckpointBox(checkpoint: checkpoint)
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { box.load() },
      save: { box.save($0) },
      clear: { box.clear() }
    )
    let harness = makeCausalSimulatorAppFixture(
      learningPathCheckpointActions: actions,
      tipCalibrationSemanticIdentities: identities
    )
    let workspace = harness.workspace
    let originalPoseApplicability = workspace.controllerPoseApplicability

    #expect(workspace.learningArtifactGraph.revisions.isEmpty)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.map(\.kind)
        == [.useSavedTraining, .startNewLearning]
    )

    let owner = workspace.testCurrentLearningPathItemID
    await workspace.performTestExerciseAction(.startNewLearning, for: owner)

    #expect(workspace.learningArtifactGraph.revisions.isEmpty)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.controllerPoseApplicability == originalPoseApplicability)
    #expect(box.checkpoint?.checkpointID == checkpoint.checkpointID)
    #expect(box.operationCounts.clears == 0)
    if case .retainedForLater(sideCount: 0, hasTipCalibration: false) =
      workspace.acceptedArtifactCheckpointStatus
    {
      // Expected: the package remains durable but is no longer an active candidate.
    } else {
      Issue.record("Expected the declined package to remain retained for later.")
    }
    await workspace.shutdown()
    #expect(box.checkpoint?.checkpointID == checkpoint.checkpointID)
  }

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
      workspace.testCurrentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )
    await workspace.shutdown()
  }

  @Test(
    "Reset All cancels a pending Exercise 1.1 attempt and preserves controller Camera and Motion"
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

    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    #expect(workspace.activeExerciseAttemptID != nil)
    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest != nil)
    let plan = try #require(workspace.resetAllLearningPlan)
    let boundaryRequestsBeforeReset = await machine.requestedBoundaryRequests
    let drawingRequestsBeforeReset = await machine.requestedDrawingStrokes
    let penRequestsBeforeReset = await machine.requestedPenCommands
    let cancelCountBeforeReset = await machine.cancelCount

    let didReset = await workspace.performResetAllLearning(plan)

    #expect(didReset)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest == nil)
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
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)

    await workspace.submitManualMotionIntent(try manualEpisodeJog(RelativeJogRequest(
      delta: try Vector2(dx: 1, dy: 0),
      feedMMPerMinute: 100
    )))
    #expect(workspace.manualMotionEpisodeSnapshot?.projection.lastTerminalEffect?.disposition
      == .completed)
    await workspace.shutdown()
  }

  @Test("Reset All cancels and settles the active Learning-owned Boundary motion")
  func resetAllCancelsAndSettlesActiveBoundaryMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = LearningPathCheckpointBox(
      checkpoint: try acceptedPenLearningTestCheckpoint(identity: identities.learningPathIdentity)
    )
    let checkpointActions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let lowerGate = BoundaryRenewalMotionGate()
    let runtimeAccess = TestBoundaryRuntimeAccess()
    let workspace = workspace(
      machine: machine,
      boundaryMotionBegin: { request, planner in
        .admitted(BoundaryMotionOperation(
          ownerID: request.ownerID,
          task: Task { await lowerGate.run(request, renewalPlanner: planner) }
        ))
      },
      jogCancel: { intent in await lowerGate.cancel(intent) },
      learningPathCheckpointActions: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
      boundaryRuntimeAccess: runtimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.performTestExerciseAction(
      .useSavedTraining,
      for: workspace.testCurrentLearningPathItemID
    )
    #expect(workspace.penInteractionCompleted)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: owner,
      workspace: workspace
    )
    _ = await lowerGate.waitUntilRequested()
    let active = try #require(workspace.currentBoundarySnapshot?.projection)
    let operationID = try #require(active.reference.operationID)
    let capability = try #require(active.cancellationCapabilityID)
    let plan = try #require(workspace.resetAllLearningPlan)
    let resetting = Task { await workspace.performResetAllLearning(plan) }
    #expect(await lowerGate.waitUntilCancelled() == .cancelAttempt)
    let cancelling = await runtimeAccess.runtime?.snapshot(for: .live)
    #expect(cancelling?.projection.reference.operationID == operationID)
    #expect(cancelling?.projection.cancellationCapabilityID == capability)
    await lowerGate.releaseFirstSegment()
    let didReset = await resetting.value

    #expect(didReset)
    #expect(await lowerGate.requestCount == 1)
    #expect(await lowerGate.cancellationIntents == [.cancelAttempt])
    #expect(await machine.requestedBoundaryRequests.isEmpty)
    #expect(await machine.cancelCount == 0)
    #expect(
      (workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
        .contains { if case .boundary(.stop(_)) = $0.kind { return true }; return false } ?? false)
        == false
    )
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.testAcceptedBoundaryAggregates.isEmpty)
    #expect(workspace.currentBoundarySnapshot?.projection.reference.operationID == nil)
    #expect(workspace.currentBoundarySnapshot?.projection.cancellationCapabilityID == nil)
    #expect(workspace.learningArtifactGraph.revisions.allSatisfy { $0.state != .current })
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(
      workspace.testCurrentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
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
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)

    let request = RelativeJogRequest(
      delta: try Vector2(dx: 1, dy: 0),
      feedMMPerMinute: 100
    )
    let owner = Task {
      await workspace.submitManualMotionIntent(try! manualEpisodeJog(request))
    }
    try await waitUntil { workspace.testManualMotionEpisodePresentation.stopAction != nil }
    let capabilityID = try #require(
      workspace.testManualMotionEpisodePresentation.stopAction?.capabilityID
    )
    let plan = try #require(workspace.resetAllLearningPlan)

    let didReset = await workspace.performResetAllLearning(plan)

    #expect(didReset)
    #expect(await machine.cancelCount == 0)
    #expect(workspace.testManualMotionEpisodePresentation.stopAction?.capabilityID == capabilityID)
    #expect(workspace.learningArtifactGraph.revisions.allSatisfy { $0.state != .current })
    #expect(
      workspace.testCurrentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )

    await workspace.requestTestManualMotionStop(capabilityID: capabilityID)
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
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
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
    #expect(workspace.learningAuthorityError?.contains("no reset was applied") == true)
    await workspace.shutdown()
  }

  @Test("partial reset does not mutate memory when durable prefix replacement fails")
  func partialResetPersistenceFailureIsAtomic() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = LearningPathCheckpointBox(
      checkpoint: try acceptedPenLearningTestCheckpoint(
        identity: identities.learningPathIdentity
      )
    )
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { _ in throw ResetPersistenceFixtureError.refused },
      clear: { checkpointBox.clear() }
    )
    let runtimeAccess = TestBoundaryRuntimeAccess()
    let workspace = workspace(
      machine: machine,
      learningPathCheckpointActions: actions,
      tipCalibrationSemanticIdentities: identities,
      boundaryRuntimeAccess: runtimeAccess,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    let savedOwner = workspace.testCurrentLearningPathItemID
    let savedActions = workspace.currentExerciseActionStripPresentation?.actions.map(\.kind)
    guard savedActions?.contains(.useSavedTraining) == true else {
      Issue.record(
        "Saved Learning action is absent; current=\(savedOwner), status=\(workspace.acceptedArtifactCheckpointStatus), actions=\(String(describing: savedActions))"
      )
      return
    }
    await workspace.performTestExerciseAction(.useSavedTraining, for: savedOwner)
    #expect(workspace.penInteractionCompleted)
    let runtime = try #require(runtimeAccess.runtime)
    try await installAcceptedBoundaryTestProjection(
      runtime: runtime,
      workspace: workspace,
      environment: .live
    )
    let runtimeBefore = await runtime.snapshot(for: .live)
    let boundaryRevision = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveX))
    )
    let graphBefore = Set(workspace.learningArtifactGraph.revisions)
    let checkpointBefore = try #require(checkpointBox.checkpoint)
    let selectedDirectionBefore = workspace.testSelectedBoundaryDirection
    let plan = try #require(
      workspace.learningVacatePlan(
        from: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      )
    )

    let didVacate = await workspace.performLearningVacate(plan)
    let runtimeAfter = await runtime.snapshot(for: .live)
    #expect(!didVacate)
    #expect(runtimeAfter.projection.resetCapabilityID == nil)
    #expect(runtimeAfter.projection.phase == runtimeBefore.projection.phase)
    #expect(
      runtimeAfter.projection.reference.revision.rawValue
        == runtimeBefore.projection.reference.revision.rawValue + 2
    )
    #expect(runtimeAfter.acceptedEvidence == runtimeBefore.acceptedEvidence)
    #expect(runtimeAfter.acceptedAggregates == runtimeBefore.acceptedAggregates)
    #expect(runtimeAfter.pairedProgress == runtimeBefore.pairedProgress)
    #expect(runtimeAfter.estimatedCenter == runtimeBefore.estimatedCenter)
    #expect(runtimeAfter.localCoordinateFrame == runtimeBefore.localCoordinateFrame)
    #expect(runtimeAfter.centerArrivalPosition == runtimeBefore.centerArrivalPosition)
    #expect(runtimeAfter.attemptTerminals == runtimeBefore.attemptTerminals)
    #expect(runtimeAfter.currentRevisions == runtimeBefore.currentRevisions)
    #expect(runtimeAfter.acceptedMachineArtifacts == runtimeBefore.acceptedMachineArtifacts)
    #expect(
      runtimeAfter.projection.publicationRecoveryCapabilityID
        == runtimeBefore.projection.publicationRecoveryCapabilityID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveX))
        == boundaryRevision
    )
    #expect(Set(workspace.learningArtifactGraph.revisions) == graphBefore)
    #expect(workspace.testAcceptedBoundaryAggregates[.positiveX] != nil)
    #expect(workspace.testSelectedBoundaryDirection == selectedDirectionBefore)
    #expect(checkpointBox.checkpoint?.checkpointID == checkpointBefore.checkpointID)
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(workspace.learningAuthorityError?.contains("no reset was applied") == true)
    await workspace.shutdown()
  }

  @Test("Reset All LIVE Learning clears a preview-only durable tip package")
  func resetAllLiveLearningClearsTipCheckpoint() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = LearningPathCheckpointBox()
    let actions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let seeded = makeCausalSimulatorAppFixture(tipCalibrationSemanticIdentities: identities)
    try await completeSimulatedPenInteractionPrerequisite(seeded.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: seeded.boundaryRuntime,
      workspace: seeded.workspace,
      environment: .simulated
    )
    try await completeSimulatedSparseTipCalibration(
      seeded.workspace,
      simulator: seeded.simulator
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

    let liveRestart = makeCausalSimulatorAppFixture(
      learningPathCheckpointActions: actions,
      tipCalibrationSemanticIdentities: identities
    )
    #expect(liveRestart.workspace.frameMode == .live)
    #expect(liveRestart.workspace.recoverableTipCalibrationCheckpoint == nil)
    #expect(liveRestart.workspace.tipCameraRegistration == nil)
    #expect(liveRestart.workspace.learningArtifactGraph.revisions.isEmpty)
    if case .awaitingOperatorDecision(sideCount: 0, hasTipCalibration: true) =
      liveRestart.workspace.acceptedArtifactCheckpointStatus
    {
      // Expected: loading the package did not apply the tip map.
    } else {
      Issue.record("Expected the saved tip package to await operator choice.")
    }
    let plan = try #require(liveRestart.workspace.resetAllLearningPlan)
    #expect(plan.removesDurableTipCheckpoint)
    #expect(!plan.removesDurableMachineCheckpoint)
    let didReset = await liveRestart.workspace.performResetAllLearning(plan)
    #expect(didReset)
    #expect(checkpointBox.checkpoint == nil)
    #expect(liveRestart.workspace.recoverableTipCalibrationCheckpoint == nil)
    #expect(liveRestart.workspace.tipCameraRegistration == nil)
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
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    let stalePlan = try #require(workspace.resetAllLearningPlan)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: boundaryOwner,
      workspace: workspace
    )
    _ = await machine.waitForBoundaryRequest(count: 1)
    try await submitRenderedBoundaryStop(owner: boundaryOwner, workspace: workspace)
    #expect(checkpointBox.checkpoint != nil)
    let didVacate = await workspace.performLearningVacate(stalePlan)
    #expect(!didVacate)
    #expect(workspace.testAcceptedBoundaryAggregates[.positiveX] != nil)
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
    #expect(workspace.testAcceptedBoundaryAggregates.isEmpty)
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(
      workspace.testCurrentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
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
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await first.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(first.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(first.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(first, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { first.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await first.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(first.penInteractionCompleted)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: boundaryOwner,
      workspace: first
    )
    _ = await machine.waitForBoundaryRequest(count: 1)
    try await submitRenderedBoundaryStop(owner: boundaryOwner, workspace: first)
    #expect(checkpointBox.checkpoint?.machineArtifacts != nil)

    let relaunched = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: actions,
      tipCalibrationSemanticIdentities: identities,
      log: log
    )
    let savedOwner = relaunched.testCurrentLearningPathItemID
    #expect(relaunched.learningArtifactGraph.revisions.isEmpty)
    await relaunched.performTestExerciseAction(.useSavedTraining, for: savedOwner)
    #expect(relaunched.testSelectedBoundaryDirection == .negativeX)
    await relaunched.establishMachineSession(machine.descriptor)
    await relaunched.requestPassiveProbe()
    await relaunched.startCamera()
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    #expect(
      relaunched.currentExerciseActionStripPresentation?.directionSelection?.selected
        == .negativeX
    )
    #expect(relaunched.testCurrentLearningPathItemID == .humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    ))

    #expect(relaunched.motionAuthorizationEnabled)
    #expect(relaunched.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    await relaunched.submitManualMotionIntent(try manualEpisodeJog(RelativeJogRequest(
      delta: try Vector2(dx: 1, dy: 0),
      feedMMPerMinute: 100
    )))
    #expect(relaunched.manualMotionEpisodeSnapshot?.projection.lastTerminalEffect?.disposition
      == .completed)

    let plan = try #require(relaunched.resetAllLearningPlan)
    let didReset = await relaunched.performResetAllLearning(plan)
    #expect(didReset)
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    #expect(checkpointBox.checkpoint == nil)
    #expect(
      relaunched.testCurrentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )
    #expect(relaunched.discoveryStartUnavailableReason(for: .penInteraction) == nil)

    await relaunched.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    #expect(relaunched.activeExerciseAttemptID != nil)
    #expect(relaunched.testActionSurfacePresentation.pointSelectionRequest != nil)
    await first.shutdown()
    await relaunched.shutdown()
  }

  @Test("Reset from Boundary retains Pen and removes every later SIMULATED result")
  func resetBoundaryForwardRetainsEarlierLearning() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: workspace,
      environment: .simulated
    )
    try await completeSimulatedSparseTipCalibration(workspace, simulator: harness.simulator)
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
    let didVacate = await workspace.performLearningVacate(plan)
    #expect(didVacate)

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
        == penRevisionID
    )
    #expect(workspace.testAcceptedBoundaryAggregates.isEmpty)
    #expect(workspace.testEstimatedMachineCenter == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.testCurrentLearningPathItemID == anchor)
    await workspace.shutdown()
  }

  @Test("Reset Drawing Border validation atomically and perform no redraw")
  func resetObservedTrialAtomically() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: workspace,
      environment: .simulated
    )
    try await completeSimulatedSparseTipCalibration(workspace, simulator: harness.simulator)
    try await completeSimulatedStageFour(workspace)
    let framePlan = try #require(
      workspace.learningArtifactGraph.revisions.first { revision in
        guard revision.state == .current else { return false }
        if case .linePlan = revision.kind { return true }
        return false
      })
    guard case .linePlan(let group) = framePlan.kind else {
      Issue.record("Expected the current frame-plan revision to carry its attempt group.")
      return
    }
    let inkBefore = await harness.simulator.persistentInk()
    let anchor = LearningPathItemID.observedDrawingTrial(.chooseDrawingBorderPlan)
    let plan = try #require(workspace.learningVacatePlan(from: anchor))
    #expect(plan.affectedItems == [anchor])
    #expect(plan.expectedCurrentRevisionIDs.count == 7)
    let didVacate = await workspace.performLearningVacate(plan)
    #expect(didVacate)

    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.drawingBorderPlan == nil)
    #expect(workspace.localPreFrameBaseline == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .comparison(group)) == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .linePlan(group)) == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .inkObservation(group)) == nil)
    #expect(workspace.testCurrentLearningPathItemID == anchor)
    #expect(await harness.simulator.persistentInk() == inkBefore)
    await workspace.shutdown()
  }
}

private enum ResetPersistenceFixtureError: Error {
  case refused
}
