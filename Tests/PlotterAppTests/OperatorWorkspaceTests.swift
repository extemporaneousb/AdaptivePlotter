import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace learning runtime")
@MainActor
struct OperatorWorkspaceTests {
  @Test("successful LIVE camera start and restart enable automatic overlays")
  func cameraStartEnablesAutomaticOverlays() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)

    await workspace.startCamera()
    #expect(workspace.automaticVisionEnabled)
    #expect(workspace.visibleLayers == Set(CanvasLayer.allCases))
    #expect(camera.recordedAutomaticCadences == [.fiveFPS])
    #expect(
      workspace.cameraUtilityPresentation.actions.first {
        $0.kind == .toggleAutomaticAnalysis
      }?.title == "Stop Auto Analysis"
    )

    await workspace.restartCamera()
    #expect(workspace.automaticVisionEnabled)
    #expect(camera.recordedAutomaticCadences == [.fiveFPS, .fiveFPS])
    await workspace.setAutomaticVisionAnalysis(false)
    #expect(!workspace.automaticVisionEnabled)
    #expect(
      workspace.cameraUtilityPresentation.actions.first {
        $0.kind == .toggleAutomaticAnalysis
      }?.title == "Start Auto Analysis"
    )
    await workspace.shutdown()
  }

  @Test("manual contextual Stop sends one cancel and creates no boundary evidence")
  func manualStopHasNoBoundaryEvidence() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let request = RelativeJogRequest(
      delta: try Vector2(dx: 1, dy: 0),
      feedMMPerMinute: 100
    )
    let owner = Task { await workspace.requestRelativeJog(request) }
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let capabilityID = try #require(workspace.manualMotionPresentation.stopAction?.capabilityID)
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    if case .busy = workspace.motionRequestStatusPresentation {
      // Expected: authorization remains enabled while transient availability is busy.
    } else {
      Issue.record("Expected a busy motion-request projection while the manual jog owns motion.")
    }
    async let first: Void = workspace.stopManualJog(capabilityID: capabilityID)
    async let repeated: Void = workspace.stopManualJog(capabilityID: capabilityID)
    _ = await (first, repeated)
    _ = await owner.value

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)

    let secondOwner = Task { await workspace.requestRelativeJog(request) }
    try await waitUntil { workspace.manualMotionPresentation.stopAction != nil }
    let secondCapabilityID = try #require(
      workspace.manualMotionPresentation.stopAction?.capabilityID
    )
    #expect(secondCapabilityID != capabilityID)
    await workspace.stopManualJog(capabilityID: capabilityID)
    #expect(await machine.cancelCount == 1)
    #expect(workspace.manualMotionPresentation.stopAction?.capabilityID == secondCapabilityID)
    await workspace.stopManualJog(capabilityID: secondCapabilityID)
    _ = await secondOwner.value
    #expect(await machine.cancelCount == 2)
    await workspace.shutdown()
  }

  @Test(
    "boundary Stop records Stop first, settles owner, captures fresh frame, and commits typed evidence")
  func boundaryStopCompletesTransaction() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      feedLimits: ControllerAxisFeedLimits(
        maximumXFeedMMPerMinute: 900,
        maximumYFeedMMPerMinute: 600
      )
    )
    let camera = try CameraFixture()
    let announcements = AnnouncementFixture(log: log, outcomes: [.failed("test failure")])
    let workspace = workspace(
      machine: machine,
      camera: camera,
      announcements: announcements,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    #expect(workspace.currentLearningPathItemID == owner)
    await workspace.performExerciseAction(.start, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let liveActions = try #require(workspace.currentExerciseActionStripPresentation).actions
    #expect(liveActions.filter { if case .stop = $0.kind { true } else { false } }.count == 1)
    #expect(liveActions.filter { $0.kind == .cancel }.isEmpty)
    #expect(!liveActions.contains(where: { if case .choice = $0.kind { true } else { false } }))
    let stopKind = try #require(
      liveActions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind)
    async let first: Void = workspace.performExerciseAction(stopKind, for: owner)
    async let repeated: Void = workspace.performExerciseAction(stopKind, for: owner)
    _ = await (first, repeated)

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(await machine.requestedFeeds.last == 900)
    #expect(workspace.discoveryTransactions[.boundaryPositiveX]?.state == .succeeded)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    #expect(workspace.boundarySideAggregates[.positiveX]?.validSampleCount == 1)
    #expect(workspace.boundaryAttemptEvidenceByAttemptID.count == 1)
    #expect(workspace.humanGuidedDiscoveryCurrentStep == .pairedBoundaryDiscoveryAndCentering)
    #expect(workspace.lastContextualStopAuditRecord?.actor == "Operator")
    #expect(workspace.lastContextualStopAuditRecord?.action == "Stop")
    #expect(workspace.lastContextualStopAuditRecord?.disposition == .operatorStop)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    let events = await log.values
    #expect(
      events.firstIndex(of: "announce:Moving toward X+ boundary.")! < events.firstIndex(
        of: "machine:boundary")!)
    await workspace.shutdown()
  }

  @Test("relaunch restores accepted boundaries only after fresh controller revalidation")
  func acceptedBoundariesSurviveSoftwareRelaunchWithoutReplayingMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let checkpointBox = CheckpointBox()
    let checkpointActions = OperatorWorkspace.AcceptedArtifactCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) }
    )
    let first = workspace(
      machine: machine,
      camera: try CameraFixture(),
      checkpointActions: checkpointActions,
      log: log
    )
    await first.establishMachineSession(machine.descriptor)
    await first.requestPassiveProbe()
    await first.startCamera()
    #expect(
      first.cameraIsLive,
      "state=\(first.cameraStateText) source=\(String(describing: first.latestLiveCameraFrame?.source)) age=\(first.frameAgeText)"
    )
    try await completePenInteraction(first)
    try await completeLiveBoundaries(first, machine: machine)

    let saved = try #require(checkpointBox.checkpoint)
    #expect(saved.boundarySideAggregates.count == 4)
    let cancelCountAtRelaunch = await machine.cancelCount
    let motionLogAtRelaunch = await log.values

    let relaunched = workspace(
      machine: machine,
      camera: try CameraFixture(),
      checkpointActions: checkpointActions,
      log: log
    )
    #expect(relaunched.boundarySideAggregates.isEmpty)
    if case .quarantined(sideCount: 4) = relaunched.acceptedArtifactCheckpointStatus {
      // Expected: disk data is not authority before fresh controller evidence.
    } else {
      Issue.record("Expected the loaded checkpoint to remain quarantined before probing.")
    }
    await relaunched.establishMachineSession(machine.descriptor)
    await relaunched.requestPassiveProbe()
    await relaunched.startCamera()

    #expect(relaunched.boundarySideAggregates == first.boundarySideAggregates)
    #expect(relaunched.estimatedMachineCenter == first.estimatedMachineCenter)
    #expect(relaunched.learnedLocalCoordinateFrame == first.learnedLocalCoordinateFrame)
    #expect(relaunched.activeExerciseAttemptID == nil)
    #expect(relaunched.contextualStopPresentation == nil)
    #expect(await machine.cancelCount == cancelCountAtRelaunch)
    #expect(await log.values == motionLogAtRelaunch)
    if case .restored(sideCount: 4, centerArrival: false, _) =
      relaunched.acceptedArtifactCheckpointStatus
    {
      // Expected: accepted artifacts only, after matching context and MPos.
    } else {
      Issue.record("Expected accepted boundaries to restore after fresh revalidation.")
    }
    #expect(
      relaunched.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction),
      "A relaunch still requires fresh physical Pen-state confirmation."
    )
    try await completePenInteraction(relaunched)
    #expect(
      relaunched.currentLearningPathItemID
        == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    )
    #expect(
      relaunched.currentExerciseActionStripPresentation?.actions.first?.kind
        == .moveToEstimatedCenter
    )
    #expect(relaunched.boundarySideAggregates == first.boundarySideAggregates)
    await first.shutdown()
    await relaunched.shutdown()
  }

  @Test("active Boundary motion exposes only Stop and rejects a programmatic Cancel")
  func activeBoundaryHasOnlyStop() async throws {
    let stopLog = EventLog()
    let stopMachine = try MachineFixture(log: stopLog, holdCancellationSettlement: true)
    let stopWorkspace = workspace(
      machine: stopMachine,
      camera: try CameraFixture(),
      log: stopLog
    )
    await stopWorkspace.establishMachineSession(stopMachine.descriptor)
    await stopWorkspace.requestPassiveProbe()
    await stopWorkspace.startCamera()
    try await completePenInteraction(stopWorkspace)
    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await stopWorkspace.performExerciseAction(.start, for: owner)
    try await waitUntil { stopWorkspace.contextualStopPresentation != nil }
    let stopKind = try #require(
      stopWorkspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind
    )
    await stopWorkspace.performExerciseAction(.cancel, for: owner)
    #expect(await stopMachine.cancelIntents.isEmpty)
    #expect(stopWorkspace.discoveryTransactions[.boundaryPositiveX]?.state == .active)
    let stopTask = Task { await stopWorkspace.performExerciseAction(stopKind, for: owner) }
    try await waitUntilAsync { await stopMachine.cancelCount == 1 }
    await stopMachine.settleHeldCancellation()
    await stopTask.value
    #expect(await stopMachine.cancelIntents == [.operatorStop])
    #expect(stopWorkspace.relevantBoundaryObservationCount == 1)
    await stopWorkspace.shutdown()
  }

  @Test(
    "SIMULATED public actions complete both paired-boundary orders through visibility registration",
    arguments: [
      [BoundaryDirection.positiveX, .negativeX, .positiveY, .negativeY],
      [BoundaryDirection.positiveY, .negativeY, .negativeX, .positiveX],
    ]
  )
  func simulatedLearningPathHasFullActionParity(
    boundaryOrder: [BoundaryDirection]
  ) async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: boundaryOrder
    )

    #expect(harness.workspace.visibilityRegistrationAccepted)
    #expect(harness.workspace.visibilityTargetObservation?.validSampleCount == 2)
    #expect(harness.workspace.visibilityTargetObservation?.includedFrameIDs.count == 2)
    #expect(harness.workspace.displayedFrame?.source == .simulated)
    #expect(
      await harness.runtime.persistentInk().count == VisibilityTargetPlanV1().drawingDeltas.count)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("SIMULATED public actions complete the target-anchored line comparison")
  func simulatedStageFourUsesPersistentCausalInk() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    let targetInkCount = await harness.runtime.persistentInk().count
    let lastTargetCapture = try #require(
      harness.workspace.visibilityTargetObservation?.samples.last?.frame.captureNanoseconds
    )

    try await completeSimulatedStageFour(harness.workspace)

    #expect(harness.workspace.currentLearningPathItemID == .stage(.adaptiveDrawing))
    #expect(harness.workspace.drawingTrialAssessment == .observedGeometryAccepted)
    #expect(await harness.runtime.persistentInk().count == targetInkCount + 1)
    #expect(
      harness.workspace.explorationPostLineFrame?.frame.captureNanoseconds ?? 0
        > lastTargetCapture
    )
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("Visibility Record Another aggregates two attempts without replacing target execution")
  func visibilityRecordAnotherAggregatesExistingTarget() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    let executionID = try #require(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
    )
    let acceptedRegistrationID = try #require(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
    )

    try await performPublicAction(.recordAnotherAttempt, owner: owner, workspace: harness.workspace)
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        == acceptedRegistrationID
    )
    try await performPublicAction(
      .observeExistingVisibilityTarget,
      owner: owner,
      workspace: harness.workspace
    )
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        == acceptedRegistrationID
    )
    try await performPublicAction(
      .acceptVisibilityRegistration,
      owner: owner,
      workspace: harness.workspace
    )

    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
        == executionID
    )
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        != acceptedRegistrationID
    )
    let history = try #require(
      harness.workspace.visibilityObservationAttemptHistories.values.first(where: {
        $0.includedSuccessfulAttempts.count == 2
      })
    )
    let aggregate = try VisibilityTargetAttemptAggregate(history: history)
    #expect(aggregate.validAttemptCount == 2)
    #expect(aggregate.includedAttemptIDs.count == 2)
    #expect(aggregate.includedObservations.flatMap(\.includedFrameIDs).count == 4)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("cancelled Visibility Redo restores accepted graph and requires relocation before capture")
  func cancelledVisibilityRedoIsAtomic() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX]
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    let acceptedRegistrationID = try #require(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
    )
    let acceptedExecutionID = try #require(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
    )
    let acceptedAreaID = harness.workspace.targetAreaIdentity
    let acceptedInk = await harness.runtime.persistentInk()

    try await performPublicAction(.redoThisStep, owner: owner, workspace: harness.workspace)
    let capture = try #require(
      harness.workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
        .first(where: { $0.kind == .captureTargetPoseRegistration })
    )
    #expect(!capture.isEnabled)
    #expect(capture.unavailableReason == "Move to a new target area first.")
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        == acceptedRegistrationID
    )
    try await performPublicAction(.cancel, owner: owner, workspace: harness.workspace)

    #expect(harness.workspace.visibilityRegistrationAccepted)
    #expect(harness.workspace.targetAreaIdentity == acceptedAreaID)
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        == acceptedRegistrationID
    )
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
        == acceptedExecutionID
    )
    #expect(await harness.runtime.persistentInk() == acceptedInk)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("successful Visibility Redo relocates and atomically replaces the accepted registration")
  func successfulVisibilityRedoUsesNewTargetArea() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    let oldAreaID = workspace.targetAreaIdentity
    let oldRegistrationID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
    )
    let oldInkCount = await harness.runtime.persistentInk().count

    try await performPublicAction(.redoThisStep, owner: owner, workspace: workspace)
    try await selectPublicDirection(
      .positiveY,
      purpose: .targetAreaRelocation,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .moveToNewTargetArea(
        ClearViewSearchMove(direction: .positiveY, distance: .tenMillimeters)
      ),
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .captureTargetPoseRegistration, owner: owner, workspace: workspace)
    try await performPublicAction(
      .acceptTargetContactPointAndROI, owner: owner, workspace: workspace)
    try await selectPublicDirection(
      .positiveX,
      purpose: .clearViewSearch,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .moveForClearView(
        ClearViewSearchMove(direction: .positiveX, distance: .tenMillimeters)
      ),
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .moveForClearView(
        ClearViewSearchMove(direction: .positiveX, distance: .twoMillimeters)
      ),
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(.recordClearViewLabel(.clear), owner: owner, workspace: workspace)
    try await performPublicAction(.acceptClearPose, owner: owner, workspace: workspace)
    try await performPublicAction(
      .capturePreTargetClearViewBaseline,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(.returnToRegisteredTargetPose, owner: owner, workspace: workspace)
    try await performPublicAction(.drawVisibilityTarget, owner: owner, workspace: workspace)
    try await performPublicAction(.returnToAcceptedClearPose, owner: owner, workspace: workspace)
    try await performPublicAction(
      .observeExistingVisibilityTarget,
      owner: owner,
      workspace: workspace
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        == oldRegistrationID
    )
    try await performPublicAction(.acceptVisibilityRegistration, owner: owner, workspace: workspace)

    #expect(workspace.targetAreaIdentity != oldAreaID)
    #expect(workspace.retiredTargetAreaDispositions[oldAreaID] == .targetObserved)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        != oldRegistrationID
    )
    #expect(
      workspace.learningArtifactGraph.revision(id: oldRegistrationID)?.state == .superseded
    )
    #expect(await harness.runtime.persistentInk().count > oldInkCount)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("stopped Visibility Redo preserves accepted registration and records attempted-area ink")
  func stoppedVisibilityRedoRetainsAttemptedAreaProvenance() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    let workspace = harness.workspace
    workspace.replaceSimulatedExecutionPacingForTesting(
      SimulatedLearningInteractivePacing(stepDelay: .milliseconds(150))
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    let acceptedAreaID = workspace.targetAreaIdentity
    let acceptedRegistrationID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
    )
    let acceptedInkCount = await harness.runtime.persistentInk().count

    try await performPublicAction(.redoThisStep, owner: owner, workspace: workspace)
    let attemptedAreaID = workspace.targetAreaIdentity
    #expect(attemptedAreaID != acceptedAreaID)
    try await selectPublicDirection(
      .positiveY,
      purpose: .targetAreaRelocation,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .moveToNewTargetArea(
        ClearViewSearchMove(direction: .positiveY, distance: .tenMillimeters)
      ),
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .captureTargetPoseRegistration, owner: owner, workspace: workspace)
    try await performPublicAction(
      .acceptTargetContactPointAndROI, owner: owner, workspace: workspace)
    try await selectPublicDirection(
      .positiveX,
      purpose: .clearViewSearch,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .moveForClearView(
        ClearViewSearchMove(direction: .positiveX, distance: .tenMillimeters)
      ),
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .moveForClearView(
        ClearViewSearchMove(direction: .positiveX, distance: .twoMillimeters)
      ),
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(.recordClearViewLabel(.clear), owner: owner, workspace: workspace)
    try await performPublicAction(.acceptClearPose, owner: owner, workspace: workspace)
    try await performPublicAction(
      .capturePreTargetClearViewBaseline,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(.returnToRegisteredTargetPose, owner: owner, workspace: workspace)

    let drawTask = Task {
      try await performPublicAction(.drawVisibilityTarget, owner: owner, workspace: workspace)
    }
    try await waitUntil {
      workspace.contextualStopPresentation != nil
    }
    try await Task.sleep(for: .milliseconds(550))
    #expect(await harness.runtime.persistentInk().count > acceptedInkCount)
    let stop = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
        .first(where: { if case .stop = $0.kind { true } else { false } })?.kind
    )
    await workspace.performExerciseAction(stop, for: owner)
    try await drawTask.value

    #expect(workspace.targetAreaIdentity == acceptedAreaID)
    #expect(workspace.visibilityRegistrationAccepted)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        == acceptedRegistrationID
    )
    #expect(
      workspace.retiredTargetAreaDispositions[attemptedAreaID] == .inkPossible
        || workspace.retiredTargetAreaDispositions[attemptedAreaID] == .targetUnusable
    )
    #expect(await harness.runtime.persistentInk().count > acceptedInkCount)
    let reviewActions =
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
      ?? []
    #expect(reviewActions.contains(where: { $0.kind == .drawVisibilityTarget }) == false)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("cancelled Visibility Record Another remains excluded provenance")
  func failedVisibilityRecordAnotherIsExcluded() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX]
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    let acceptedRegistrationID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
    )
    try await performPublicAction(.recordAnotherAttempt, owner: owner, workspace: workspace)
    try await performPublicAction(.cancel, owner: owner, workspace: workspace)

    let history = try #require(
      workspace.visibilityObservationAttemptHistories.values.first(where: {
        $0.records.count == 2
      })
    )
    #expect(history.records.first?.inclusionState == .included)
    #expect(history.records.last?.inclusionState == .excludedUnsuccessful)
    #expect(history.records.last?.attempt.disposition == .cancelled)
    #expect(try VisibilityTargetAttemptAggregate(history: history).validAttemptCount == 1)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        == acceptedRegistrationID
    )
    #expect(workspace.visibilityRegistrationAccepted)
  }

  @Test("camera configuration change preserves machine facts and local frame")
  func cameraChangePreservesMachineAuthority() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )
    let workspace = harness.workspace
    let penRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let sideAggregates = workspace.boundarySideAggregates
    let localFrame = try #require(workspace.learnedLocalCoordinateFrame)
    let center = try #require(workspace.estimatedMachineCenter)
    let centerRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .estimatedMachineCenter)?.id
    )
    let arrival = try #require(workspace.centerArrivalPosition)
    let arrivalRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .centerArrival)?.id
    )

    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performCameraUtilityAction(.refresh)

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == penRevisionID)
    #expect(workspace.boundarySideAggregates == sideAggregates)
    #expect(workspace.learnedLocalCoordinateFrame == localFrame)
    #expect(workspace.estimatedMachineCenter == center)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .estimatedMachineCenter)?.id
        == centerRevisionID
    )
    #expect(workspace.centerArrivalPosition == arrival)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .centerArrival)?.id == arrivalRevisionID)
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.visibilityTargetAndClearViewRegistration),
      "Camera restart must not rewind completed machine-space Boundary work."
    )
    #expect(workspace.pairedBoundaryProgress.isComplete)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("current-camera correspondence recovery is typed, explicit, and motion-free")
  func currentCameraEvidenceCollectionIsExplicitAndMotionFree() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )
    let aggregates = workspace.boundarySideAggregates
    let center = workspace.estimatedMachineCenter
    let localFrame = workspace.learnedLocalCoordinateFrame

    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performCameraUtilityAction(.refresh)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    try await performPublicAction(.start, owner: owner, workspace: workspace)
    try await performPublicAction(
      .captureTargetPoseRegistration,
      owner: owner,
      workspace: workspace
    )
    let actions = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(actions.contains(.collectCurrentCameraContactEvidence))
    try await performPublicAction(
      .collectCurrentCameraContactEvidence,
      owner: owner,
      workspace: workspace
    )

    let evidence = try #require(workspace.explicitRegistrationContactEvidence.last)
    #expect(evidence.cameraConfigurationID == workspace.displayedFrame?.frame.cameraConfigurationID)
    #expect(evidence.algorithmRevision == "explicit-current-camera-contact-v1")
    #expect(workspace.boundarySideAggregates == aggregates)
    #expect(workspace.estimatedMachineCenter == center)
    #expect(workspace.learnedLocalCoordinateFrame == localFrame)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("camera change preserves target-area ink provenance and exposes recovery only")
  func cameraChangeMakesExistingTargetUnusableWithoutRedraw() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX]
    )
    let workspace = harness.workspace
    let visibilityOwner = LearningPathItemID.humanGuidedDiscovery(
      .visibilityTargetAndClearViewRegistration
    )
    let targetAreaID = workspace.targetAreaIdentity
    let targetFrameID = workspace.targetPoseRegistrationFrame?.frame.id
    let targetObservation = workspace.visibilityTargetObservation
    let ink = await harness.runtime.persistentInk()

    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performCameraUtilityAction(.refresh)

    #expect(workspace.targetAreaIdentity == targetAreaID)
    #expect(workspace.targetPoseRegistrationFrame?.frame.id == targetFrameID)
    #expect(workspace.visibilityTargetObservation == targetObservation)
    #expect(workspace.visibilityTargetSceneDisposition == .targetUnusable)
    #expect(workspace.retiredTargetAreaDispositions[targetAreaID] == .targetUnusable)
    #expect(await harness.runtime.persistentInk() == ink)
    #expect(workspace.currentLearningPathItemID == visibilityOwner)
    try await performPublicAction(.start, owner: visibilityOwner, workspace: workspace)
    let actions = try #require(
      workspace.selectedOperatorActionPresentation(for: visibilityOwner).actionStrip?.actions
    )
    #expect(actions.contains(where: { $0.kind == .registerNewTargetArea }))
    #expect(actions.contains(where: { $0.kind == .paperReplaced }))
    #expect(actions.contains(where: { $0.kind == .drawVisibilityTarget }) == false)
    #expect(actions.contains(where: { $0.kind == .returnToRegisteredTargetPose }) == false)
    #expect(actions.contains(where: { $0.kind == .returnToAcceptedClearPose }) == false)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("SIMULATED supervised travel exposes a public Stop and accepts no arrival")
  func simulatedSupervisedTravelStopIsPublicAndNonprogressing() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false,
      moveToCenter: false
    )
    let workspace = harness.workspace
    let pacing = ManualJogStopPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let acceptedAggregates = workspace.boundarySideAggregates
    let moveTask = Task {
      try await performPublicAction(.moveToEstimatedCenter, owner: owner, workspace: workspace)
    }
    await pacing.waitUntilSuspended()
    try await waitUntil {
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
        .contains(where: { if case .stop = $0.kind { true } else { false } }) == true
    }
    let strip = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    )
    #expect(strip.mustRemainVisible)
    #expect(strip.actions.filter { if case .stop = $0.kind { true } else { false } }.count == 1)
    let stop = try #require(
      strip.actions.first(where: { if case .stop = $0.kind { true } else { false } })?.kind
    )
    let stopTask = Task {
      await workspace.performExerciseAction(stop, for: owner)
    }
    try await waitUntilAsync {
      await harness.runtime.snapshot().currentOperation == nil
    }
    await pacing.resume()
    await stopTask.value
    try await moveTask.value

    #expect(workspace.centerArrivalPosition == nil)
    #expect(workspace.boundarySideAggregates == acceptedAggregates)
    #expect(workspace.currentLearningPathItemID == owner)
    let recovery = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(recovery.actions.map(\.kind) == [.moveToEstimatedCenter])
    #expect(recovery.actions.map(\.title) == ["Retry Center Arrival"])
    #expect(workspace.centerArrivalRetryRequired)
    #expect(workspace.restartableExerciseItemID == nil)
    #expect(workspace.lastContextualStopAuditRecord?.actor == "Operator")
    #expect(workspace.lastContextualStopAuditRecord?.action == "Stop")
    #expect(workspace.lastContextualStopAuditRecord?.outcome.contains("stopped") == true)
    #expect(await harness.runtime.snapshot().currentOperation == nil)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("Center arrival accepts reproduced controller quantization residual")
  func centerArrivalAcceptsQuantizedSettlement() async throws {
    let target = try MachinePosition(x: -51.975, y: -73.684)
    let reproduced = try MachinePosition(x: -51.963, y: -73.673)
    #expect(CenterArrivalSettlementPolicy.defaultToleranceMM == 0.05)
    #expect(CenterArrivalSettlementPolicy.accepts(actual: reproduced, target: target))

    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0.012, dy: 0.011)
    )
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(.moveToEstimatedCenter, owner: owner, workspace: workspace)

    let expectedCenter = try MachinePosition(x: 0, y: 0)
    #expect(workspace.centerArrivalPosition == expectedCenter)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) != nil)
    #expect(!workspace.centerArrivalRetryRequired)
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.visibilityTargetAndClearViewRegistration)
    )
  }

  @Test("Out-of-tolerance center settlement offers center-only retry")
  func centerArrivalRejectsOutsideToleranceWithoutBoundaryRestart() async throws {
    let target = try MachinePosition(x: 0, y: 0)
    let outside = try MachinePosition(x: 0.04, y: 0.04)
    #expect(!CenterArrivalSettlementPolicy.accepts(actual: outside, target: target))

    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0.04, dy: 0.04)
    )
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    let acceptedAggregates = workspace.boundarySideAggregates
    let acceptedCenter = workspace.estimatedMachineCenter

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(.moveToEstimatedCenter, owner: owner, workspace: workspace)

    #expect(workspace.centerArrivalPosition == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .centerArrival) == nil)
    #expect(workspace.boundarySideAggregates == acceptedAggregates)
    #expect(workspace.estimatedMachineCenter == acceptedCenter)
    #expect(workspace.centerArrivalRetryRequired)
    #expect(workspace.restartableExerciseItemID == nil)
    let recovery = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(recovery.actions.map(\.kind) == [.moveToEstimatedCenter])
    #expect(recovery.actions.map(\.title) == ["Retry Center Arrival"])
    let activity = workspace.selectedOperatorActionPresentation(for: owner).activity
    #expect(activity?.action == "Move to Estimated Center")
    #expect(
      activity?.detail.accessibilityText.contains("outside the 0.050 mm tolerance") == true
    )
    #expect(
      activity?.acceptedResult.accessibilityText.contains("four accepted Boundary") == true
    )
  }

  @Test("SIMULATED learning is discarded and the parked LIVE authority is restored")
  func simulatedLearningDoesNotReplaceLiveAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginPairedBoundarySide(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let livePenRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let liveBoundaryRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
    )
    await workspace.switchFrameMode(.simulated)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY)) == nil
    )

    await workspace.switchFrameMode(.live)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == livePenRevisionID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?.id
        == liveBoundaryRevisionID
    )
    await workspace.shutdown()
  }

  @Test("logical boundary owner exposes Stop without a moving-state timer or natural success")
  func boundaryOwnerDoesNotAssumeMovingOrNaturalSuccess() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log, reportsBoundaryMoving: false)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    await workspace.beginPairedBoundarySide(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }

    #expect(workspace.machineSnapshot?.machine.connection == .connected)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundarySideAggregates.isEmpty)
    try await stopActiveOperation(workspace)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("invalid manual step text does not gate Boundary Discovery")
  func manualStepTextIsNotBoundaryAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    workspace.xStepText = "not-a-number"
    workspace.yStepText = ""

    #expect(workspace.motionUnavailableReason != nil)
    #expect(workspace.discoveryStartUnavailableReason(for: .boundaryPositiveX) == nil)
    await workspace.beginPairedBoundarySide(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("shutdown stops an active boundary before draining and erasing its authority")
  func authorityClearingStopsBeforeErasure() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()

    await workspace.beginPairedBoundarySide(.negativeY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.shutdown()

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.shutdown])
    #expect(await machine.requestedFeeds.last == 100)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.isShutdown)
  }

  @Test(
    "announcement failure is advisory and Pen Interaction preserves output-before-actuation order")
  func announcementFailureDoesNotGatePenInteraction() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let announcements = AnnouncementFixture(
      log: log,
      outcomes: [.failed("output unavailable"), .completed]
    )
    let workspace = workspace(
      machine: machine,
      camera: camera,
      announcements: announcements,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    #expect(workspace.penInteractionCompleted)
    let events = await log.values
    #expect(
      events.firstIndex(of: "announce:Lowering the pen.")! < events.firstIndex(
        of: "machine:pen-lower")!)
    #expect(
      events.firstIndex(of: "announce:Raising the pen.")! < events.firstIndex(
        of: "machine:pen-raise")!)
    #expect(workspace.lastAnnouncementResultText == "Announcement completed.")
    await workspace.shutdown()
  }

  @Test("review projections are inert and preserve the runtime current owner")
  func reviewProjectionIsInert() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let current = workspace.currentLearningPathItemID
    let transactionCount = workspace.discoveryTransactions.count
    let revisionCount = workspace.learningArtifactGraph.revisions.count
    let requestedFeedCount = await machine.requestedFeeds.count
    for itemID in LearningPathItemID.navigationOrder {
      _ = workspace.selectedOperatorActionPresentation(for: itemID)
    }

    #expect(workspace.currentLearningPathItemID == current)
    #expect(workspace.discoveryTransactions.count == transactionCount)
    #expect(workspace.learningArtifactGraph.revisions.count == revisionCount)
    #expect(await machine.requestedFeeds.count == requestedFeedCount)
    #expect(await machine.cancelCount == 0)
    #expect(
      workspace.learningPathItemPresentations.first {
        $0.id == .stage(.humanGuidedDiscovery)
      }?.status == .current
    )
    #expect(
      workspace.learningPathItemPresentations.first {
        $0.id == .humanGuidedDiscovery(.penInteraction)
      }?.status == .current
    )
    let adaptive = workspace.selectedOperatorActionPresentation(for: .stage(.adaptiveDrawing))
    #expect(adaptive.status == .future)
    #expect(adaptive.actionStrip == nil)
    await workspace.shutdown()
  }

  @Test("Start becomes typed choices and Cancel settles to a fresh Restart route")
  func exerciseActionTransitions() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    await workspace.performExerciseAction(.start, for: owner)
    let liveActions = workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) ?? []
    #expect(liveActions.contains(.choice(.yes)))
    #expect(liveActions.contains(.choice(.no)))
    #expect(liveActions.contains(.cancel))
    #expect(!liveActions.contains(.start))

    await workspace.performExerciseAction(.cancel, for: owner)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentLearningPathItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await workspace.shutdown()
  }

  @Test("Boundary Cancel is unavailable until its movement owner settles")
  func boundaryCancelUnavailableDuringMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await workspace.beginPairedBoundarySide(.negativeX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains(where: {
        $0.kind == .cancel
      }) == false
    )
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(await machine.cancelIntents.isEmpty)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.discoveryTransactions[.boundaryNegativeX]?.state == .active)
    try await stopActiveOperation(workspace)
    await workspace.shutdown()
  }

  @Test("Record Another Attempt preserves compatible boundary samples and recomputes N")
  func boundaryAdditionalAttemptAggregates() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let attemptsBeforeReview = workspace.boundaryAttemptHistories[.positiveX]?
      .values.first?.attempts.count
    let revisionsBeforeReview = workspace.learningArtifactGraph.revisions.count
    let machineActionsBeforeReview = await harness.machineActionLog.values.count
    let repeatActions = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(repeatActions.contains(.redoBoundary(.positiveX)))
    #expect(repeatActions.contains(.recordAnotherBoundaryAttempt(.positiveX)))
    #expect(
      attemptsBeforeReview
        == workspace.boundaryAttemptHistories[.positiveX]?
        .values.first?.attempts.count)
    #expect(revisionsBeforeReview == workspace.learningArtifactGraph.revisions.count)
    let machineActionsAfterReview = await harness.machineActionLog.values.count
    #expect(machineActionsBeforeReview == machineActionsAfterReview)
    for _ in 0..<2 {
      await workspace.performExerciseAction(.recordAnotherBoundaryAttempt(.positiveX), for: owner)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      try await stopActiveOperation(workspace)
    }

    let histories = try #require(workspace.boundaryAttemptHistories[.positiveX])
    let history = try #require(histories.values.first)
    let aggregate = try #require(workspace.boundarySideAggregates[.positiveX])
    #expect(aggregate.validSampleCount == 3)
    #expect(aggregate.includedAttemptIDs.count == 3)
    #expect(aggregate.estimator.revision == "boundary-machine-coordinate-v1")
    #expect(history.includedSuccessfulAttempts.count == 3)
    #expect(workspace.boundaryAttemptEvidenceByAttemptID.count == 6)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("Redo after N=3 replaces the whole accepted set at N=1")
  func boundaryRedoSupersedesWholeIncludedSet() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    for _ in 0..<2 {
      await workspace.performExerciseAction(.recordAnotherBoundaryAttempt(.positiveX), for: owner)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      try await stopActiveOperation(workspace)
    }
    let oldAttemptIDs = try #require(
      workspace.boundarySideAggregates[.positiveX]?.includedAttemptIDs
    )
    #expect(oldAttemptIDs.count == 3)

    await workspace.performExerciseAction(.redoBoundary(.positiveX), for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let history = try #require(workspace.boundaryAttemptHistories[.positiveX]?.values.first)
    let aggregate = try #require(workspace.boundarySideAggregates[.positiveX])
    let replacementID = try #require(history.attempts.last?.id)
    #expect(history.records.count == 4)
    #expect(history.records.dropLast().allSatisfy { $0.inclusionState == .superseded(by: replacementID) })
    #expect(history.records.last?.inclusionState == .included)
    #expect(aggregate.validSampleCount == 1)
    #expect(aggregate.includedAttemptIDs == [replacementID])
    #expect(Set(aggregate.supersededAttempts.map(\.attemptID)) == Set(oldAttemptIDs))
    #expect(oldAttemptIDs.allSatisfy { workspace.boundaryAttemptEvidenceByAttemptID[$0] != nil })
    #expect(workspace.boundaryAttemptEvidenceByAttemptID[replacementID] != nil)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("Cancel cannot abandon a Boundary Redo while its movement owner is active")
  func boundaryRedoCancelUnavailableDuringMotion() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY],
      throughVisibility: false
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let acceptedAttemptID = try #require(
      workspace.boundaryAttemptHistories[.negativeX]?.values.first?.attempts.first?.id
    )
    let acceptedAggregate = workspace.boundarySideAggregates[.negativeX]
    let acceptedCenter = workspace.estimatedMachineCenter
    let acceptedLocalFrame = workspace.learnedLocalCoordinateFrame

    await workspace.performExerciseAction(.redoBoundary(.negativeX), for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.performExerciseAction(.cancel, for: owner)

    let history = try #require(workspace.boundaryAttemptHistories[.negativeX]?.values.first)
    let aggregate = try #require(workspace.boundarySideAggregates[.negativeX])
    #expect(history.records.count == 1)
    #expect(history.records.first?.inclusionState == .included)
    #expect(aggregate.validSampleCount == 1)
    #expect(aggregate.includedAttemptIDs == [acceptedAttemptID])
    #expect(workspace.boundarySideAggregates[.negativeX] == acceptedAggregate)
    #expect(workspace.estimatedMachineCenter == acceptedCenter)
    #expect(workspace.learnedLocalCoordinateFrame == acceptedLocalFrame)
    #expect(await harness.machineActionLog.values.isEmpty)
    try await stopActiveOperation(workspace)
  }

  @Test("camera-changing Boundary Redo keeps numeric compatibility independent of camera")
  func cameraChangingBoundaryRedoKeepsOneNumericHistory() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX],
      throughVisibility: false
    )
    let acceptedAttemptID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?
        .attemptID
    )

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performExerciseAction(.redoBoundary(.positiveY), for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let replacementAttemptID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))?
        .attemptID
    )
    let histories = try #require(workspace.boundaryAttemptHistories[.positiveY])
    let history = try #require(histories.values.first)
    #expect(histories.count == 1)
    #expect(acceptedAttemptID != replacementAttemptID)
    #expect(history.records.first?.inclusionState == .superseded(by: replacementAttemptID))
    #expect(history.records.last?.inclusionState == .included)
    #expect(history.includedSuccessfulAttempts.map(\.id) == [replacementAttemptID])
    #expect(workspace.boundarySideAggregates[.positiveY]?.validSampleCount == 1)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("every injected Boundary commit failure preserves all accepted current authority")
  func boundaryAtomicFailurePreservesAcceptedAuthority() async throws {
    for failurePoint in BoundaryAtomicCommitFailurePoint.allCases {
      let harness = makeSimulatedHarness()
      let workspace = harness.workspace
      try await completeSimulatedVisibilityProtocol(
        workspace,
        runtime: harness.runtime,
        boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
        throughVisibility: false,
        moveToCenter: false
      )
      let aggregates = workspace.boundarySideAggregates
      let progress = workspace.pairedBoundaryProgress
      let center = workspace.estimatedMachineCenter
      let localFrame = workspace.learnedLocalCoordinateFrame
      let graphRevisions = Set(workspace.learningArtifactGraph.revisions)
      let boundaryEvidence = workspace.boundaryAttemptEvidenceByAttemptID
      workspace.replaceBoundaryAtomicCommitFailurePointsForTesting([failurePoint])
      let snapshot = await harness.runtime.snapshot()
      _ = await workspace.requestRelativeJog(
        RelativeJogRequest(
          delta: try Vector2(
            dx: snapshot.boundaryTruth.positiveXMM - snapshot.mpos.xMM,
            dy: 0
          ),
          feedMMPerMinute: 1_000
        )
      )

      let owner = LearningPathItemID.humanGuidedDiscovery(
        .pairedBoundaryDiscoveryAndCentering
      )
      await workspace.performExerciseAction(.redoBoundary(.positiveX), for: owner)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      try await stopActiveOperation(workspace)

      #expect(workspace.boundarySideAggregates == aggregates)
      #expect(workspace.pairedBoundaryProgress == progress)
      #expect(workspace.estimatedMachineCenter == center)
      #expect(workspace.learnedLocalCoordinateFrame == localFrame)
      #expect(workspace.centerArrivalPosition == nil)
      #expect(Set(workspace.learningArtifactGraph.revisions) == graphRevisions)
      #expect(workspace.boundaryAttemptEvidenceByAttemptID == boundaryEvidence)
      #expect(workspace.restartableExerciseItemID == nil)
      let recoveryActions = workspace.selectedOperatorActionPresentation(for: owner)
        .actionStrip?.actions.map(\.kind) ?? []
      #expect(recoveryActions.first == .moveToEstimatedCenter)
      #expect(recoveryActions.contains(.redoBoundary(.positiveX)))
      #expect(!recoveryActions.contains(.restart))
      #expect(!recoveryActions.contains(.cancel))
      #expect(await harness.machineActionLog.values.isEmpty)
    }
  }

  @Test("Redo Pen Interaction replaces only its revision and retains independent boundary evidence")
  func redoPenRetainsBoundary() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    await workspace.beginPairedBoundarySide(.positiveY)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let oldPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let oldBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await finishPenInteraction(workspace)

    let newPen = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let retainedBoundary = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
    )
    #expect(newPen.id != oldPen.id)
    #expect(workspace.learningArtifactGraph.revision(id: oldPen.id)?.state == .superseded)
    #expect(retainedBoundary.id == oldBoundary.id)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    await workspace.shutdown()
  }

  @Test("cancelled replacement leaves the accepted artifact current")
  func cancelledReplacementKeepsAcceptedArtifact() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    let accepted = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.performExerciseAction(.redoThisStep, for: owner)
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id == accepted.id
    )
    #expect(workspace.learningArtifactGraph.revision(id: accepted.id)?.state == .current)
    #expect(workspace.penAttemptHistory.attempts.last?.disposition == .cancelled)
    #expect(workspace.penAttemptHistory.records.first?.inclusionState == .included)
    #expect(workspace.penAttemptHistory.records.last?.inclusionState == .excludedUnsuccessful)
    #expect(workspace.currentPenStateAggregate?.validSampleCount == 1)
    #expect(workspace.currentPenStateAggregate?.includedAttemptIDs == [accepted.attemptID])
    await workspace.shutdown()
  }
}

@MainActor
private func stopActiveOperation(_ workspace: OperatorWorkspace) async throws {
  let capabilityID = try #require(workspace.contextualStopPresentation?.capabilityID)
  await workspace.stopCurrentOperation(capabilityID: capabilityID)
}

@MainActor
private func performStart(
  _ workspace: OperatorWorkspace,
  owner: LearningPathItemID
) async {
  let start = workspace.currentExerciseActionStripPresentation?.actions.first {
    $0.kind == .start
  }
  #expect(start?.isEnabled == true)
  await workspace.performExerciseAction(.start, for: owner)
}

private struct SimulatedWorkspaceHarness {
  let workspace: OperatorWorkspace
  let runtime: SimulatedLearningRuntime
  let machineActionLog: EventLog
}

private func sequenceIDForTest(_ direction: BoundaryDirection) -> DiscoverySequenceID {
  switch direction {
  case .negativeX: .boundaryNegativeX
  case .positiveX: .boundaryPositiveX
  case .negativeY: .boundaryNegativeY
  case .positiveY: .boundaryPositiveY
  }
}

@MainActor
private func makeSimulatedHarness(
  simulatedExecutionPacing: any SimulatedLearningExecutionPacing =
    SimulatedLearningImmediatePacing()
) -> SimulatedWorkspaceHarness {
  let machineActionLog = EventLog()
  let clock = TestClock()
  let runtime = SimulatedLearningRuntime()
  return SimulatedWorkspaceHarness(
    workspace: OperatorWorkspace(
      machineActions: isolatedMachineActions(log: machineActionLog),
      cameraActions: CameraComposition.actions,
      simulatedLearningRuntime: runtime,
      simulatedExecutionPacing: simulatedExecutionPacing,
      serialDevices: [],
      serialDeviceDiscovery: { [] },
      loadSelectedSerialIdentifier: { nil },
      persistSelectedSerialIdentifier: { _ in },
      nowNanoseconds: { clock.next() }
    ),
    runtime: runtime,
    machineActionLog: machineActionLog
  )
}

@MainActor
private func performPublicAction(
  _ kind: ExerciseActionKind,
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) async throws {
  let presentation = workspace.selectedOperatorActionPresentation(for: owner)
  let action = try #require(
    presentation.actionStrip?.actions.first(where: { $0.kind == kind }),
    "Missing public action \(kind); visible actions: \(String(describing: presentation.actionStrip?.actions.map(\.kind))); exploration error: \(workspace.explorationError ?? "nil")"
  )
  #expect(action.isEnabled)
  await workspace.performExerciseAction(kind, for: owner)
}

@MainActor
private func selectPublicDirection(
  _ direction: BoundaryDirection,
  purpose: ExerciseDirectionSelectionPurpose,
  owner: LearningPathItemID,
  workspace: OperatorWorkspace
) async throws {
  let selection = try #require(
    workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.directionSelection,
    "Missing direction selection; discovery error: \(workspace.discoveryError ?? "nil"); exploration error: \(workspace.explorationError ?? "nil"); activities: \(workspace.boundaryActivityRecords)"
  )
  #expect(selection.purpose == purpose)
  #expect(selection.options.contains(direction))
  await workspace.performExerciseAction(.selectDirection(purpose, direction), for: owner)
}

@MainActor
private func redoSimulatedBoundary(
  _ direction: BoundaryDirection,
  workspace: OperatorWorkspace
) async throws {
  let owner = LearningPathItemID.humanGuidedDiscovery(
    .pairedBoundaryDiscoveryAndCentering
  )
  try await performPublicAction(.redoBoundary(direction), owner: owner, workspace: workspace)
  try await waitUntil {
    workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
      .contains(where: { if case .stop = $0.kind { true } else { false } }) == true
  }
  let stop = try #require(
    workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
      .first(where: { if case .stop = $0.kind { true } else { false } })?.kind
  )
  await workspace.performExerciseAction(stop, for: owner)
  try await waitUntil { workspace.activeExerciseAttemptID == nil }
}

@MainActor
private func completeSimulatedVisibilityProtocol(
  _ workspace: OperatorWorkspace,
  runtime: SimulatedLearningRuntime,
  boundaryOrder: [BoundaryDirection],
  throughVisibility: Bool = true,
  moveToCenter: Bool = true
) async throws {
  await workspace.switchFrameMode(.simulated)
  #expect(workspace.frameMode == .simulated)
  #expect(workspace.simulatorEvidenceLabel == "SIMULATED — NOT PHYSICAL EVIDENCE")
  await workspace.performControllerConnectionAction()
  await workspace.activateMotionGuard()

  let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  try await performPublicAction(.start, owner: penOwner, workspace: workspace)
  var physicalPoseQuestionCount = 0
  for _ in 0..<8 where !workspace.penInteractionCompleted {
    let presentation = workspace.selectedOperatorActionPresentation(for: penOwner)
    #expect(presentation.question?.prompt.isEmpty == false)
    #expect(presentation.question?.choices == [.yes, .no])
    #expect(presentation.actionStrip?.actions.contains(where: { $0.kind == .start }) == false)
    physicalPoseQuestionCount += 1
    try await performPublicAction(.choice(.yes), owner: penOwner, workspace: workspace)
  }
  #expect(workspace.penInteractionCompleted)
  #expect(physicalPoseQuestionCount == 3)

  let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
    .pairedBoundaryDiscoveryAndCentering
  )
  for direction in boundaryOrder {
    try await selectPublicDirection(
      direction,
      purpose: .boundary,
      owner: boundaryOwner,
      workspace: workspace
    )
    try await performPublicAction(.start, owner: boundaryOwner, workspace: workspace)
    try await waitUntil {
      workspace.selectedOperatorActionPresentation(for: boundaryOwner).actionStrip?.actions
        .contains(where: { if case .stop = $0.kind { true } else { false } }) == true
    }
    try await waitUntilAsync {
      let snapshot = await runtime.snapshot()
      let limit = snapshot.boundaryTruth.limit(for: direction)
      return switch direction {
      case .negativeX, .positiveX: snapshot.mpos.xMM == limit
      case .negativeY, .positiveY: snapshot.mpos.yMM == limit
      }
    }
    let stop = try #require(
      workspace.selectedOperatorActionPresentation(for: boundaryOwner).actionStrip?.actions
        .first(where: { if case .stop = $0.kind { true } else { false } })?.kind
    )
    await workspace.performExerciseAction(stop, for: boundaryOwner)
    #expect(
      workspace.activeExerciseAttemptID == nil,
      "transaction=\(String(describing: workspace.discoveryTransactions[sequenceIDForTest(direction)]?.state)) error=\(workspace.discoveryError ?? "nil") count=\(workspace.relevantBoundaryObservationCount)"
    )
    try await waitUntil { workspace.activeExerciseAttemptID == nil }
  }
  #expect(
    workspace.pairedBoundaryProgress.isComplete,
    "discovery error: \(workspace.discoveryError ?? "nil"); activities: \(workspace.boundaryActivityRecords)"
  )
  #expect(workspace.boundarySideAggregates.count == 4)
  #expect(workspace.currentLearningPathItemID == boundaryOwner)
  let boundaryReviewActions = workspace.selectedOperatorActionPresentation(for: boundaryOwner)
    .actionStrip?.actions.map(\.kind) ?? []
  #expect(boundaryReviewActions.first == .moveToEstimatedCenter)
  #expect(boundaryReviewActions.contains(.redoBoundary(boundaryOrder[0])))
  if !moveToCenter { return }
  try await performPublicAction(.moveToEstimatedCenter, owner: boundaryOwner, workspace: workspace)
  if !throughVisibility { return }

  let visibilityOwner = LearningPathItemID.humanGuidedDiscovery(
    .visibilityTargetAndClearViewRegistration
  )
  try await performPublicAction(.start, owner: visibilityOwner, workspace: workspace)
  try await performPublicAction(
    .captureTargetPoseRegistration,
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .acceptTargetContactPointAndROI,
    owner: visibilityOwner,
    workspace: workspace
  )
  let visibilityAttemptID = try #require(workspace.activeExerciseAttemptID)
  try await performPublicAction(
    .recordClearViewLabel(.blocked),
    owner: visibilityOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == visibilityAttemptID)
  #expect(
    workspace.selectedOperatorActionPresentation(for: visibilityOwner).actionStrip?.actions
      .first(where: { $0.kind == .acceptClearPose })?.isEnabled == false
  )
  try await selectPublicDirection(
    .positiveX,
    purpose: .clearViewSearch,
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .moveForClearView(ClearViewSearchMove(direction: .positiveX, distance: .tenMillimeters)),
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .recordClearViewLabel(.partial),
    owner: visibilityOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == visibilityAttemptID)
  #expect(
    workspace.selectedOperatorActionPresentation(for: visibilityOwner).actionStrip?.actions
      .first(where: { $0.kind == .acceptClearPose })?.isEnabled == false
  )
  try await performPublicAction(
    .moveForClearView(ClearViewSearchMove(direction: .positiveX, distance: .twoMillimeters)),
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .recordClearViewLabel(.clear),
    owner: visibilityOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == visibilityAttemptID)
  try await performPublicAction(.acceptClearPose, owner: visibilityOwner, workspace: workspace)
  try await performPublicAction(
    .capturePreTargetClearViewBaseline,
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .returnToRegisteredTargetPose,
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(.drawVisibilityTarget, owner: visibilityOwner, workspace: workspace)
  try await performPublicAction(
    .returnToAcceptedClearPose,
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .observeExistingVisibilityTarget,
    owner: visibilityOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .acceptVisibilityRegistration,
    owner: visibilityOwner,
    workspace: workspace
  )
}

@MainActor
private func completeSimulatedStageFour(_ workspace: OperatorWorkspace) async throws {
  let actions: [(LearningPathItemID, ExerciseActionKind)] = [
    (.observedDrawingTrial(.chooseIsolatedLinePlan), .chooseIsolatedLinePlan(.positiveX)),
    (.observedDrawingTrial(.captureTargetAnchoredBaseline), .captureTargetAnchoredBaseline),
    (.observedDrawingTrial(.moveToLineStart), .moveToLineStart),
    (.observedDrawingTrial(.drawIsolatedLine), .drawIsolatedLine),
    (
      .observedDrawingTrial(.returnToClearPoseAndObserveNewInk),
      .returnToClearPoseAndObserveNewInk
    ),
  ]
  for (owner, kind) in actions {
    try await performPublicAction(kind, owner: owner, workspace: workspace)
  }
  let comparison = LearningPathItemID.observedDrawingTrial(
    .compareIntendedAndObservedGeometry
  )
  try await performPublicAction(.start, owner: comparison, workspace: workspace)
  try await performPublicAction(
    .recordDrawingTrialAssessment(.observedGeometryAccepted),
    owner: comparison,
    workspace: workspace
  )
}

@MainActor
private func completeLiveBoundaries(
  _ workspace: OperatorWorkspace,
  machine: MachineFixture
) async throws {
  let samples: [(BoundaryDirection, Double, Double)] = [
    (.negativeX, -100, 0),
    (.positiveX, 100, 0),
    (.negativeY, 100, -50),
    (.positiveY, 100, 50),
  ]
  for (direction, x, y) in samples {
    await workspace.beginPairedBoundarySide(direction)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await machine.setPosition(x: x, y: y)
    try await stopActiveOperation(workspace)
  }
  #expect(workspace.pairedBoundaryProgress.isComplete)
  #expect(workspace.boundarySideAggregates.count == BoundaryDirection.allCases.count)
}

@MainActor
private func completePenInteraction(_ workspace: OperatorWorkspace) async throws {
  if let reason = workspace.discoveryStartUnavailableReason(for: .penInteraction) {
    throw StepMismatch(expected: "available", actual: reason)
  }
  await workspace.beginPenInteraction()
  try await finishPenInteraction(workspace)
}

@MainActor
private func finishPenInteraction(_ workspace: OperatorWorkspace) async throws {
  try requireStep(workspace, "answer-initially-up")
  await workspace.answerCurrentQuestion(.yes)
  try requireStep(workspace, "answer-currently-down")
  await workspace.answerCurrentQuestion(.yes)
  try requireStep(workspace, "answer-finally-up")
  await workspace.answerCurrentQuestion(.yes)
  guard workspace.discoveryTransactions[.penInteraction]?.state == .succeeded else {
    throw StepMismatch(
      expected: "succeeded",
      actual: String(describing: workspace.discoveryTransactions[.penInteraction]?.state)
    )
  }
}

@MainActor
private func requireStep(_ workspace: OperatorWorkspace, _ expected: String) throws {
  let actual = workspace.discoveryTransactions[.penInteraction]?.currentStep?.id
  guard actual == expected else {
    throw StepMismatch(expected: expected, actual: actual ?? "nil")
  }
}

@MainActor
private func workspace(
  machine: MachineFixture,
  camera: CameraFixture? = nil,
  announcements: AnnouncementFixture? = nil,
  checkpointActions: OperatorWorkspace.AcceptedArtifactCheckpointActions? = nil,
  log _: EventLog
) -> OperatorWorkspace {
  let clock = TestClock()
  return OperatorWorkspace(
    machineActions: .init(
      select: { _ in await machine.snapshot() },
      snapshot: { await machine.snapshot() },
      requestPassiveProbe: {
        await machine.passiveProbeResult()
      },
      activateMotionGuard: { .activated },
      deactivateMotionGuard: {},
      requestRelativeJog: { await machine.requestRelativeJog($0) },
      beginRelativeJog: { request in
        .admitted(
          RelativeJogOperation(
            id: UUID(),
            task: Task { await machine.requestRelativeJog(request) }
          )
        )
      },
      requestDrawingStroke: { _ in fatalError("unused") },
      beginDrawingStroke: { _ in fatalError("unused") },
      beginVisibilityTarget: { _ in fatalError("unused") },
      requestVisibilityTargetIntent: { _, _ in fatalError("unused") },
      requestPenActuation: { await machine.requestPen($0) },
      requestBoundaryMotion: { await machine.requestBoundaryMotion($0) },
      beginBoundaryMotion: { request in
        .admitted(
          BoundaryMotionOperation(
            ownerID: request.ownerID,
            task: Task { await machine.requestBoundaryMotion(request) }
          )
        )
      },
      requestJogCancel: { await machine.cancel(intent: $0) },
      disconnect: {}
    ),
    cameraActions: camera.map(cameraActions),
    announcementActions: announcements.map { fixture in
      .init(
        announce: { await fixture.announce($0) },
        cancelForShutdown: { await fixture.cancelForShutdown() }
      )
    },
    acceptedArtifactCheckpointActions: checkpointActions,
    serialDevices: [machine.descriptor],
    serialDeviceDiscovery: { [machine.descriptor] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in },
    nowNanoseconds: { clock.next() }
  )
}

private enum SimulatorIsolationViolation: Error {
  case machineAction(String)
}

private func isolatedMachineActions(log: EventLog) -> OperatorWorkspace.MachineActions {
  .init(
    select: { _ in
      await log.append("select")
      throw SimulatorIsolationViolation.machineAction("select")
    },
    snapshot: {
      await log.append("snapshot")
      return nil
    },
    requestPassiveProbe: {
      await log.append("requestPassiveProbe")
      throw SimulatorIsolationViolation.machineAction("requestPassiveProbe")
    },
    activateMotionGuard: {
      await log.append("activateMotionGuard")
      return .refused(.notConnected)
    },
    deactivateMotionGuard: {
      await log.append("deactivateMotionGuard")
    },
    requestRelativeJog: { _ in
      await log.append("requestRelativeJog")
      return .refused(.notConnected)
    },
    beginRelativeJog: { _ in
      await log.append("beginRelativeJog")
      return .rejected(.refused(.notConnected))
    },
    requestDrawingStroke: { _ in
      await log.append("requestDrawingStroke")
      return .refused(.notConnected)
    },
    beginDrawingStroke: { _ in
      await log.append("beginDrawingStroke")
      return .rejected(.refused(.notConnected))
    },
    beginVisibilityTarget: { _ in
      await log.append("beginVisibilityTarget")
      return .rejected(
        .needsAttention(
          phase: .approach,
          scene: .pristine,
          failure: .approach(.refused(.notConnected))
        )
      )
    },
    requestVisibilityTargetIntent: { _, _ in
      await log.append("requestVisibilityTargetIntent")
      return .staleOperation
    },
    requestPenActuation: { _ in
      await log.append("requestPenActuation")
      return .refused(.notConnected)
    },
    requestBoundaryMotion: { request in
      await log.append("requestBoundaryMotion")
      return .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
    },
    beginBoundaryMotion: { request in
      await log.append("beginBoundaryMotion")
      return .rejected(
        .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
      )
    },
    requestJogCancel: { _ in
      await log.append("requestJogCancel")
      return .refused(.noActiveJog)
    },
    disconnect: {
      await log.append("disconnect")
    }
  )
}

private func cameraActions(_ fixture: CameraFixture) -> OperatorWorkspace.CameraActions {
  .init(
    discover: { fixture.snapshot },
    select: { _ in fixture.snapshot },
    start: { fixture.snapshot },
    stop: { fixture.snapshot },
    restart: { fixture.snapshot },
    snapshot: { fixture.snapshot },
    frames: { AsyncStream { $0.finish() } },
    inspectScene: { try fixture.inspection(after: $0) },
    captureFrame: { try fixture.inspection(after: $0).displayedFrame },
    captureSnapshot: { "unused" },
    setAutomaticInspection: { fixture.setAutomaticInspection($0) },
    analysisUpdates: { AsyncStream { $0.finish() } },
    observeIsolatedInk: { _ in fatalError("unused") },
    observeVisibilityTarget: { _ in fatalError("unused") },
  )
}

private actor EventLog {
  private(set) var values: [String] = []
  func append(_ value: String) { values.append(value) }
}

private final class TestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: UInt64 = 100

  func next() -> UInt64 {
    lock.lock()
    defer { lock.unlock() }
    let result = value
    value &+= 10
    return result
  }
}

private final class CheckpointBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: AcceptedMachineArtifactCheckpoint?

  var checkpoint: AcceptedMachineArtifactCheckpoint? {
    lock.lock()
    defer { lock.unlock() }
    return stored
  }

  func load() -> AcceptedArtifactCheckpointLoadResult {
    lock.lock()
    defer { lock.unlock() }
    return stored.map(AcceptedArtifactCheckpointLoadResult.loaded) ?? .absent
  }

  func save(_ checkpoint: AcceptedMachineArtifactCheckpoint) {
    lock.lock()
    stored = checkpoint
    lock.unlock()
  }
}

private actor AnnouncementFixture {
  let log: EventLog
  var outcomes: [SpeechAnnouncementOutcome]

  init(log: EventLog, outcomes: [SpeechAnnouncementOutcome]) {
    self.log = log
    self.outcomes = outcomes
  }

  func announce(_ message: String) async -> SpeechAnnouncementOutcome {
    await log.append("announce:\(message)")
    return outcomes.isEmpty ? .completed : outcomes.removeFirst()
  }

  func cancelForShutdown() {}
}

private actor MachineFixture {
  nonisolated let descriptor = MachineLinkDescriptor(
    identifier: "fixture",
    displayName: "Fixture",
    bsdPath: nil,
    transport: .simulated
  )
  let log: EventLog
  let feedLimits: ControllerAxisFeedLimits?
  let reportsBoundaryMoving: Bool
  let holdCancellationSettlement: Bool
  let relativeJogSettlementOffset: Vector2<MachineSpace>?
  private(set) var cancelCount = 0
  private(set) var cancelIntents: [JogCancelIntent] = []
  private(set) var requestedFeeds: [Double] = []
  private var moving = false
  private var cancelPending = false
  private var pendingCancelIntent: JogCancelIntent?
  private var continuation: CheckedContinuation<MotionOutcome, Never>?
  private var boundaryContinuation: CheckedContinuation<BoundaryMotionOutcome, Never>?
  private var position: MachinePosition
  private var penState: PenState = .up
  private var lastMotion: MotionOutcome?
  private var lastPen: PenOutcome?
  private var lastCancel: JogCancelOutcome?
  private var activeRequest: RelativeJogRequest?
  private var activeBoundaryRequest: BoundaryMotionRequest?
  private var heldBoundaryCancelIntent: JogCancelIntent?

  init(
    log: EventLog,
    feedLimits: ControllerAxisFeedLimits? = nil,
    reportsBoundaryMoving: Bool = true,
    holdCancellationSettlement: Bool = false,
    relativeJogSettlementOffset: Vector2<MachineSpace>? = nil
  ) throws {
    self.log = log
    self.feedLimits = feedLimits
    self.reportsBoundaryMoving = reportsBoundaryMoving
    self.holdCancellationSettlement = holdCancellationSettlement
    self.relativeJogSettlementOffset = relativeJogSettlementOffset
    position = try MachinePosition(x: 0, y: 0)
  }

  func setPosition(x: Double, y: Double) throws {
    position = try MachinePosition(x: x, y: y)
  }

  func snapshot() -> RunInterpreterSnapshot {
    RunInterpreterSnapshot(
      currentOperation: activeBoundaryRequest.map(RunOperation.boundaryMotion)
        ?? activeRequest.map(RunOperation.relativeJog) ?? .idle,
      machine: MachineSnapshot(
        connection: moving && (activeBoundaryRequest == nil || reportsBoundaryMoving)
          ? .moving : .connected,
        link: descriptor,
        lastProbe: nil,
        blockers: [],
        controllerState: moving && (activeBoundaryRequest == nil || reportsBoundaryMoving)
          ? .jog : .idle,
        position: position,
        penState: penState,
        motionGuardState: .active,
        operationInFlight: moving,
        lastMotionOutcome: lastMotion,
        lastPenOutcome: lastPen,
        lastJogCancelOutcome: lastCancel,
        controllerAxisFeedLimits: feedLimits
      ),
      lastMotionOutcome: lastMotion,
      lastPenOutcome: lastPen,
      lastProbe: nil,
      lastJogCancelOutcome: lastCancel
    )
  }

  func passiveProbeResult() -> PassiveProbeResult {
    let reports: [(PassiveQuery, [String])] = [
      (.buildInfo, ["[VER:1.1h.20200101:workspace-fixture]"]),
      (.parserState, ["[GC:G0 G54 G17 G21 G90 G94 M5 M9 T0 F0 S0]"]),
      (
        .status,
        [String(format: "<Idle|MPos:%.3f,%.3f,0.000>", position.point.x, position.point.y)]
      ),
      (.configuration, ["$100=80.000", "$101=80.000", "$110=900.000"]),
      (.coordinateOffsets, ["[G54:0.000,0.000,0.000]", "[G92:0.000,0.000,0.000]"]),
    ]
    return PassiveProbeResult(
      link: descriptor,
      startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
      completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
      exchanges: reports.map { query, report in
        let text = query == .status ? report : report + ["ok"]
        return PassiveProbeExchange(
          query: query,
          commandID: UUID(),
          rawIO: [],
          lines: text.map { GRBLParser.parseLine(Data($0.utf8)) },
          completed: true,
          blocker: nil
        )
      },
      blockers: []
    )
  }

  func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    requestedFeeds.append(request.feedMMPerMinute)
    activeRequest = request
    moving = true
    await log.append("machine:jog")
    if cancelPending {
      cancelPending = false
      return settleCancelled()
    }
    if let relativeJogSettlementOffset {
      position = try! MachinePosition(
        x: position.point.x + request.delta.dx + relativeJogSettlementOffset.dx,
        y: position.point.y + request.delta.dy + relativeJogSettlementOffset.dy
      )
      moving = false
      activeRequest = nil
      let outcome = MotionOutcome.acceptedThenCompleted(finalPosition: position)
      lastMotion = outcome
      return outcome
    }
    let outcome = await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    lastMotion = outcome
    activeRequest = nil
    return outcome
  }

  func requestBoundaryMotion(_ request: BoundaryMotionRequest) async -> BoundaryMotionOutcome {
    requestedFeeds.append(request.segment.feedMMPerMinute)
    activeBoundaryRequest = request
    moving = true
    await log.append("machine:boundary")
    if let pendingCancelIntent {
      self.pendingCancelIntent = nil
      return settleBoundary(request: request, intent: pendingCancelIntent)
    }
    let outcome = await withCheckedContinuation { continuation in
      boundaryContinuation = continuation
    }
    activeBoundaryRequest = nil
    return outcome
  }

  func cancel(intent: JogCancelIntent) -> JogCancelOutcome {
    cancelCount += 1
    cancelIntents.append(intent)
    let cancelOutcome = JogCancelOutcome.completed(finalPosition: position)
    if let boundaryContinuation, let request = activeBoundaryRequest {
      if holdCancellationSettlement {
        heldBoundaryCancelIntent = intent
      } else {
        self.boundaryContinuation = nil
        let outcome = settleBoundary(request: request, intent: intent)
        boundaryContinuation.resume(returning: outcome)
      }
    } else if let continuation {
      self.continuation = nil
      let outcome = settleCancelled()
      continuation.resume(returning: outcome)
    } else {
      cancelPending = true
      pendingCancelIntent = intent
    }
    lastCancel = cancelOutcome
    return cancelOutcome
  }

  func settleHeldCancellation() {
    guard let boundaryContinuation, let request = activeBoundaryRequest,
      let intent = heldBoundaryCancelIntent
    else { return }
    self.boundaryContinuation = nil
    heldBoundaryCancelIntent = nil
    let outcome = settleBoundary(request: request, intent: intent)
    boundaryContinuation.resume(returning: outcome)
  }

  func requestPen(_ command: PenCommand) async -> PenOutcome {
    await log.append("machine:pen-\(command.rawValue)")
    penState = command.commandedState
    let outcome = PenOutcome.commandedAndSettled(command: command, commandedState: penState)
    lastPen = outcome
    return outcome
  }

  private func settleCancelled() -> MotionOutcome {
    moving = false
    let outcome = MotionOutcome.cancelled(finalPosition: position)
    lastMotion = outcome
    activeRequest = nil
    return outcome
  }

  private func settleBoundary(
    request: BoundaryMotionRequest,
    intent: JogCancelIntent
  ) -> BoundaryMotionOutcome {
    moving = false
    activeBoundaryRequest = nil
    return .settled(
      BoundaryMotionSettlement(
        ownerID: request.ownerID,
        intent: intent,
        completedSegmentCount: 0,
        finalPosition: position,
        jogCancelOutcome: .completed(finalPosition: position)
      )
    )
  }
}

private final class CameraFixture: @unchecked Sendable {
  let device: CameraDevice
  let snapshot: CameraCaptureSnapshot
  private let configurationID: CameraConfigurationID
  private let rotatesConfiguration: Bool
  private let lock = NSLock()
  private var inspectionCount = 0
  private var automaticCadences: [VisionAnalysisCadence] = []

  init(rotatesConfiguration: Bool = false) throws {
    self.rotatesConfiguration = rotatesConfiguration
    configurationID = CameraConfigurationID()
    device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Fixture camera")
    let initial = DisplayedFrame(
      source: .live(device.id),
      frame: try frame(id: "initial", sequence: 1, capture: 50, configurationID: configurationID)
    )
    snapshot = CameraCaptureSnapshot(
      devices: [device],
      selectedDeviceID: device.id,
      state: .running,
      latestFrame: initial,
      error: nil
    )
  }

  func inspection(after captureBoundary: UInt64) throws -> LiveSceneInspection {
    lock.lock()
    inspectionCount += 1
    let inspectionConfigurationID =
      rotatesConfiguration
      ? CameraConfigurationID()
      : configurationID
    lock.unlock()
    let capture = captureBoundary &+ 1
    let fresh = DisplayedFrame(
      source: .live(device.id),
      frame: try frame(
        id: "fresh-\(capture)",
        sequence: capture,
        capture: capture,
        configurationID: inspectionConfigurationID
      )
    )
    let geometry = try Polyline<CameraPixelSpace>(points: [
      try Point2(x: 0, y: 0),
      try Point2(x: 100, y: 0),
      try Point2(x: 100, y: 100),
      try Point2(x: 0, y: 100),
      try Point2(x: 0, y: 0),
    ])
    let measurement = PlotterSceneMeasurement(
      frameID: fresh.frame.id,
      frameSHA256: fresh.frame.contentSHA256,
      cameraConfigurationID: inspectionConfigurationID,
      greenComponentCount: 1,
      cap: GreenCapMeasurement(
        pixelCount: 10,
        boundingBox: PixelRect(x: 98, y: 48, width: 2, height: 4),
        centroid: try Point2(x: 99, y: 50),
        confidence: 0.9
      ),
      topFrameSide: nil,
      rightFrameSide: nil,
      drawingFrame: DrawingFrameEstimate(
        geometry: geometry,
        confidence: 0.9,
        basis: "test exact frame"
      ),
      armature: nil,
      overlays: [],
      algorithmRevision: "workspace-test-v1",
      diagnosticSHA256: fresh.frame.contentSHA256
    )
    return LiveSceneInspection(displayedFrame: fresh, measurement: measurement)
  }

  var recordedAutomaticCadences: [VisionAnalysisCadence] {
    lock.lock()
    defer { lock.unlock() }
    return automaticCadences
  }

  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?
  ) -> PlotterSceneAnalysisSnapshot {
    lock.lock()
    if let cadence { automaticCadences.append(cadence) }
    lock.unlock()
    return PlotterSceneAnalysisSnapshot(
      state: cadence.map(PlotterSceneAnalysisState.running) ?? .stopped,
      submittedFrameCount: 0,
      analyzedFrameCount: 0,
      supersededFrameCount: 0,
      failedFrameCount: 0,
      activeFrameSequence: nil,
      pendingFrameSequence: nil,
      latestResult: nil,
      lastError: nil
    )
  }
}

private func frame(
  id: String,
  sequence: UInt64,
  capture: UInt64,
  configurationID: CameraConfigurationID
) throws -> StampedFrame {
  try StampedFrame(
    id: FrameID(rawValue: id),
    sequence: sequence,
    captureNanoseconds: capture,
    cameraConfigurationID: configurationID,
    width: 1,
    height: 1,
    rowBytes: 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes([255, 255, 255, 255])
  )
}

@MainActor
private func waitUntil(
  attempts: Int = 2_000,
  condition: () -> Bool
) async throws {
  for _ in 0..<attempts {
    if condition() { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw TestTimeout()
}

@MainActor
private func waitUntilAsync(
  attempts: Int = 2_000,
  condition: () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw TestTimeout()
}

private actor ManualJogStopPacing: SimulatedLearningExecutionPacing {
  private var didSuspend = false
  private var resumeRequested = false
  private var suspendedContinuation: CheckedContinuation<Void, Never>?
  private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

  func suspendBetweenSteps() async {
    didSuspend = true
    let waiters = suspensionWaiters
    suspensionWaiters.removeAll()
    for waiter in waiters {
      waiter.resume()
    }
    if resumeRequested { return }
    await withCheckedContinuation { continuation in
      suspendedContinuation = continuation
    }
  }

  func waitUntilSuspended() async {
    if didSuspend { return }
    await withCheckedContinuation { continuation in
      suspensionWaiters.append(continuation)
    }
  }

  func resume() {
    resumeRequested = true
    let continuation = suspendedContinuation
    suspendedContinuation = nil
    continuation?.resume()
  }
}

private struct TestTimeout: Error {}
private struct StepMismatch: Error {
  let expected: String
  let actual: String
}
