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
    #expect(camera.recordedAutomaticCadences == [.twoFPS])
    #expect(
      workspace.cameraUtilityPresentation.actions.first {
        $0.kind == .toggleAutomaticAnalysis
      }?.title == "Stop Auto Analysis"
    )

    await workspace.restartCamera()
    #expect(workspace.automaticVisionEnabled)
    #expect(camera.recordedAutomaticCadences == [.twoFPS, .twoFPS])
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
    "boundary Stop commits controller evidence without consulting Camera or Vision")
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
    let inspectionsBeforeBoundary = camera.inspectionCallCount

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
    #expect(camera.inspectionCallCount == inspectionsBeforeBoundary)
    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS, nil, .twoFPS])
    #expect(workspace.humanGuidedDiscoveryCurrentStep == .pairedBoundaryDiscoveryAndCentering)
    #expect(workspace.lastContextualStopAuditRecord?.actor == "Operator")
    #expect(workspace.lastContextualStopAuditRecord?.action == "Stop")
    #expect(workspace.lastContextualStopAuditRecord?.disposition == .operatorStop)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    let authority = workspace.selectedOperatorActionPresentation(for: owner).subsystemStatuses
    #expect(authority.first(where: { $0.id == "camera" })?.blocksNewMotion == false)
    #expect(authority.first(where: { $0.id == "vision" })?.blocksNewMotion == false)
    #expect(
      authority.first(where: { $0.id == "vision" })?.detail.accessibilityText
        .contains("boundary acceptance never calls Camera or Vision") == true
    )
    let events = await log.values
    #expect(
      events.firstIndex(of: "announce:Moving the plotter toward the positive X boundary.")!
        < events.firstIndex(of: "machine:boundary")!)
    await workspace.shutdown()
  }

  @Test("Boundary Stop settles advisory Vision before automatic analysis resumes")
  func boundaryStopSettlesAdvisoryBeforeAutomaticVisionResumes() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let inspectionGate = BoundaryInspectionGate()
    let motionGate = BoundaryRenewalMotionGate()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: boundaryGatedCameraActions(camera, gate: inspectionGate),
      boundaryMotionBegin: { request, renewalPlanner in
        .admitted(
          BoundaryMotionOperation(
            ownerID: request.ownerID,
            task: Task { await motionGate.run(request, renewalPlanner: renewalPlanner) }
          )
        )
      },
      jogCancel: { await motionGate.cancel($0) },
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await workspace.performExerciseAction(.start, for: owner)
    try await waitUntil {
      workspace.contextualStopPresentation != nil
        && camera.recordedAutomaticInspectionRequests == [.twoFPS, nil]
    }
    let pendingRequest = await motionGate.request
    let admittedRequest = try #require(pendingRequest)
    #expect(admittedRequest.segment.delta.magnitude == 20)
    #expect(admittedRequest.renewalBounds.fallbackMM == 20)
    #expect(admittedRequest.renewalBounds.maximumMM == 50)

    try await machine.setPosition(x: 20, y: 0)
    await motionGate.releaseFirstSegment()
    try await waitUntilAsync { await inspectionGate.isStarted }
    let stopKind = try #require(
      workspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind)
    let stopTask = Task { @MainActor in
      await workspace.performExerciseAction(stopKind, for: owner)
    }
    try await waitUntilAsync { await inspectionGate.isCancelled }

    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS, nil])
    #expect(!workspace.automaticVisionEnabled)
    await inspectionGate.release()
    await stopTask.value

    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS, nil, .twoFPS])
    #expect(workspace.automaticVisionEnabled)
    #expect(workspace.boundarySideAggregates[.positiveX]?.validSampleCount == 1)
    await workspace.shutdown()
  }

  @Test("all four typed boundaries commit with no Camera composition")
  func allBoundaryDirectionsNeedNoCamera() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let directions: [BoundaryDirection] = [.positiveX, .negativeX, .negativeY, .positiveY]
    for (index, direction) in directions.enumerated() {
      #expect(workspace.discoveryStartUnavailableReason(for: sequenceIDForTest(direction)) == nil)
      await workspace.beginPairedBoundarySide(direction)
      try await waitUntil { workspace.contextualStopPresentation != nil }
      let capability = try #require(workspace.contextualStopPresentation?.capabilityID)
      await workspace.stopCurrentOperation(capabilityID: capability)
      try await waitUntil { workspace.relevantBoundaryObservationCount == index + 1 }
      #expect(workspace.discoveryTransactions[sequenceIDForTest(direction)]?.state == .succeeded)
      #expect(workspace.boundarySideAggregates[direction] != nil)
    }

    #expect(workspace.pairedBoundaryProgress.isComplete)
    #expect(workspace.boundarySideAggregates.count == 4)
    await workspace.shutdown()
  }

  @Test("relaunch restores accepted boundaries only after fresh controller revalidation")
  func acceptedBoundariesSurviveSoftwareRelaunchWithoutReplayingMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let checkpointBox = CheckpointBox()
    let checkpointActions = OperatorWorkspace.AcceptedArtifactCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
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
      await harness.runtime.persistentInk().count == VisibilityTargetPlanV2().drawingStepCount)
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

  @Test("Visibility cancellation replacement and additional attempt are atomic")
  func visibilityAttemptMutationsAreAtomic() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    let workspace = harness.workspace
    let executionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
    )
    let registrationID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
    )
    let inkCount = await harness.runtime.persistentInk().count
    let observationOwner = LearningPathItemID.humanGuidedDiscovery(
      .returnAndObserveExistingTarget
    )
    try await performPublicAction(
      .recordAnotherAttempt,
      owner: observationOwner,
      workspace: workspace
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
        == executionID
    )
    try await performPublicAction(
      .observeExistingVisibilityTarget,
      owner: observationOwner,
      workspace: workspace
    )
    #expect(workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration) == nil)

    let acceptanceOwner = LearningPathItemID.humanGuidedDiscovery(
      .acceptVisibilityRegistration
    )
    try await performPublicAction(.start, owner: acceptanceOwner, workspace: workspace)
    try await performPublicAction(
      .acceptVisibilityRegistration,
      owner: acceptanceOwner,
      workspace: workspace
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
        == executionID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id
        != registrationID
    )
    #expect(await harness.runtime.persistentInk().count == inkCount)
    let aggregateHistory = try #require(
      workspace.visibilityObservationAttemptHistories.values.first(where: {
        $0.includedSuccessfulAttempts.count == 2
      })
    )
    let aggregate = try VisibilityTargetAttemptAggregate(history: aggregateHistory)
    #expect(aggregate.validAttemptCount == 2)
    #expect(aggregate.includedAttemptIDs.count == 2)
    #expect(aggregate.includedObservations.flatMap(\.includedFrameIDs).count == 4)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("foreground Vision refuses every competing mutation and ignores a late stale result")
  func foregroundVisionIsExclusiveAndCancellationIsStaleSafe() async throws {
    let gate = VisibilityObservationGate(cancellationDisposition: .staleRejection)
    let harness = makeSimulatedHarness(cameraActions: gatedCameraActions(gate: gate))
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      observeVisibility: false
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .returnAndObserveExistingTarget
    )
    let attemptID = try #require(workspace.activeExerciseAttemptID)
    let baselineID = try #require(workspace.preTargetClearViewBaseline?.frame.id)
    let executionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
    )
    let ink = await harness.runtime.persistentInk()
    let visibleLayers = workspace.visibleLayers

    let observe = Task {
      await workspace.performExerciseAction(.observeExistingVisibilityTarget, for: owner)
    }
    try await waitUntilAsync { await gate.callCount == 1 }
    let runtimeBefore = await harness.runtime.snapshot()
    let operation = try #require(workspace.visibilityObservationOperation)
    #expect(operation.phase == .analyzingFirstFrame)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.map(\.kind)
        == [.cancelVisibilityObservation(operation.cancelCapabilityID)]
    )

    await workspace.performExerciseAction(.observeExistingVisibilityTarget, for: owner)
    await workspace.performExerciseAction(.cancel, for: owner)
    await workspace.performExerciseAction(.acceptVisibilityRegistration, for: owner)
    await workspace.performControllerConnectionAction()
    await workspace.requestPassiveProbe()
    await workspace.activateMotionGuard()
    await workspace.requestJog(.xPositive)
    await workspace.requestPenActuation(.lower)
    await workspace.beginPenInteraction()
    await workspace.recordClearViewLabel(.blocked)
    await workspace.acceptClearPose()
    workspace.setLayer(.observedInk, visible: false)
    await workspace.performCameraUtilityAction(.refresh)
    await workspace.setAutomaticVisionAnalysis(true)
    await workspace.switchFrameMode(.live)

    #expect(await gate.callCount == 1)
    let runtimeAfterCompetingActions = await harness.runtime.snapshot()
    #expect(runtimeAfterCompetingActions.session == runtimeBefore.session)
    #expect(runtimeAfterCompetingActions.motionAuthorization == runtimeBefore.motionAuthorization)
    #expect(runtimeAfterCompetingActions.penPose == runtimeBefore.penPose)
    #expect(runtimeAfterCompetingActions.mpos == runtimeBefore.mpos)
    #expect(runtimeAfterCompetingActions.currentOperation == runtimeBefore.currentOperation)
    #expect(runtimeAfterCompetingActions.stickyAmbiguity == runtimeBefore.stickyAmbiguity)
    #expect(
      runtimeAfterCompetingActions.cameraConfigurationID == runtimeBefore.cameraConfigurationID)
    #expect(runtimeAfterCompetingActions.viewportID == runtimeBefore.viewportID)
    #expect(
      runtimeAfterCompetingActions.persistentInkSegmentCount
        == runtimeBefore.persistentInkSegmentCount
    )
    #expect(runtimeAfterCompetingActions.toolPaperRevision == runtimeBefore.toolPaperRevision)
    #expect(await harness.runtime.persistentInk() == ink)
    #expect(await harness.machineActionLog.values.isEmpty)
    #expect(workspace.visibleLayers == visibleLayers)
    #expect(workspace.activeExerciseAttemptID == attemptID)
    #expect(workspace.preTargetClearViewBaseline?.frame.id == baselineID)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
        == executionID
    )
    #expect(workspace.visibilityTargetSceneDisposition == .inkPossible)

    await workspace.performExerciseAction(
      .cancelVisibilityObservation(operation.cancelCapabilityID),
      for: owner
    )
    await observe.value

    #expect(await gate.cancelRequestCount == 1)
    #expect(workspace.visibilityObservationOperation == nil)
    #expect(workspace.activeExerciseAttemptID == attemptID)
    #expect(workspace.preTargetClearViewBaseline?.frame.id == baselineID)
    #expect(workspace.visibilityTargetSceneDisposition == .inkPossible)
    #expect(workspace.visibilityTargetObservation == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id
        == executionID
    )
    #expect(await harness.runtime.persistentInk() == ink)
    #expect(workspace.explorationError?.contains("cancelled") == true)
    await workspace.shutdown()
  }

  @Test("shutdown cancels and settles foreground Vision before camera and controller teardown")
  func shutdownOrdersForegroundVisionSettlement() async throws {
    let log = EventLog()
    let gate = VisibilityObservationGate(
      cancellationDisposition: .cancelled,
      log: log
    )
    let harness = makeSimulatedHarness(
      cameraActions: gatedCameraActions(gate: gate, log: log),
      eventLog: log
    )
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX],
      observeVisibility: false
    )
    await log.clear()
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .returnAndObserveExistingTarget
    )
    let observe = Task {
      await harness.workspace.performExerciseAction(
        .observeExistingVisibilityTarget,
        for: owner
      )
    }
    try await waitUntilAsync { await gate.callCount == 1 }
    await log.clear()

    await harness.workspace.shutdown()
    await observe.value

    #expect(harness.workspace.isShutdown)
    #expect(harness.workspace.visibilityObservationOperation == nil)
    #expect(await gate.cancelRequestCount == 1)
    #expect(
      await log.values == [
        "vision-cancel-requested",
        "vision-returned",
        "camera-stop",
        "disconnect",
      ])
  }

  @Test("camera recovery preserves machine facts and stages ROI for explicit acceptance")
  func cameraRecoveryPreservesMachineAuthorityAndStagesROIProposal() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )
    let penRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let aggregates = workspace.boundarySideAggregates
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
    #expect(workspace.boundarySideAggregates == aggregates)
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
        == .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry),
      "Camera restart must not rewind completed machine-space Boundary work."
    )
    #expect(workspace.pairedBoundaryProgress.isComplete)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    let initialActions = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions
    #expect(initialActions.map(\.kind) == [.captureTargetPoseAndBuildGeometryProposal])
    try await performPublicAction(
      .captureTargetPoseAndBuildGeometryProposal,
      owner: owner,
      workspace: workspace
    )

    let cameraConfigurationID = try #require(
      workspace.targetPoseRegistrationFrame?.frame.cameraConfigurationID
    )
    let evidence = workspace.explicitRegistrationContactEvidence.filter {
      $0.cameraConfigurationID == cameraConfigurationID
        && $0.algorithmRevision == "automatic-current-camera-contact-v2"
    }
    #expect(evidence.count == 3)
    let first = try #require(evidence.first?.machinePoint)
    let second = try #require(evidence.dropFirst().first?.machinePoint)
    let third = try #require(evidence.last?.machinePoint)
    let signedDoubleArea =
      (second.x - first.x) * (third.y - first.y)
      - (second.y - first.y) * (third.x - first.x)
    #expect(abs(signedDoubleArea) > 0.001)
    let targetPosition = try #require(workspace.registeredTargetMachinePosition)
    let runtimePosition = await harness.runtime.snapshot().mpos
    #expect(abs(runtimePosition.xMM - targetPosition.point.x) <= 0.001)
    #expect(abs(runtimePosition.yMM - targetPosition.point.y) <= 0.001)
    #expect(!workspace.targetContactPointAndROIAccepted)
    #expect(workspace.targetObservationRegion == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.proposedTargetObservationRegion != nil)
    #expect(workspace.proposedMachineCameraRegistration != nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) == nil
    )
    #expect(workspace.learningArtifactGraph.currentRevision(for: .targetROIRegistration) == nil)
    let reviewActions = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(
      Array(reviewActions.prefix(2)) == [
        .acceptTargetGeometryProposal, .rejectTargetGeometryProposal,
      ])
    try await performPublicAction(
      .acceptTargetGeometryProposal,
      owner: owner,
      workspace: workspace
    )
    #expect(workspace.targetContactPointAndROIAccepted)
    #expect(workspace.targetObservationRegion != nil)
    #expect(workspace.machineCameraRegistration != nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) != nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .targetROIRegistration) != nil)
    #expect(workspace.explorationError == nil)
    #expect(workspace.boundarySideAggregates == aggregates)
    #expect(workspace.estimatedMachineCenter == center)
    #expect(workspace.learnedLocalCoordinateFrame == localFrame)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test(
    "automatic current-camera calibration refusal preserves machine authority and exposes retry"
  )
  func automaticCurrentCameraCalibrationRefusalPreservesMachineAuthority() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )
    let aggregates = workspace.boundarySideAggregates
    let localFrame = try #require(workspace.learnedLocalCoordinateFrame)
    let center = try #require(workspace.estimatedMachineCenter)
    let centerArrival = try #require(workspace.centerArrivalPosition)

    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performCameraUtilityAction(.refresh)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    await harness.runtime.injectFault(.refuseNextOperation)

    try await performPublicAction(
      .captureTargetPoseAndBuildGeometryProposal,
      owner: owner,
      workspace: workspace
    )
    let targetPosition = try #require(workspace.registeredTargetMachinePosition)

    #expect(workspace.targetContactPointAndROIAccepted == false)
    #expect(workspace.targetObservationRegion == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) == nil
    )
    #expect(workspace.boundarySideAggregates == aggregates)
    #expect(workspace.learnedLocalCoordinateFrame == localFrame)
    #expect(workspace.estimatedMachineCenter == center)
    #expect(workspace.centerArrivalPosition == centerArrival)
    #expect(workspace.pairedBoundaryProgress.isComplete)
    #expect(workspace.explorationError?.contains("injectedRefusal") == true)
    #expect(workspace.explicitRegistrationContactEvidence.isEmpty)

    let runtimeSnapshot = await harness.runtime.snapshot()
    #expect(runtimeSnapshot.currentOperation == nil)
    #expect(abs(runtimeSnapshot.mpos.xMM - targetPosition.point.x) <= 0.001)
    #expect(abs(runtimeSnapshot.mpos.yMM - targetPosition.point.y) <= 0.001)
    let recovery = workspace.selectedOperatorActionPresentation(for: owner)
    #expect(
      recovery.actionStrip?.actions.map(\.kind) == [
        .captureTargetPoseAndBuildGeometryProposal,
        .rejectTargetGeometryProposal,
        .cancel,
      ]
    )
    #expect(recovery.activity?.outcome == .needsAttention)
    #expect(recovery.activity?.recovery.accessibilityText.contains("Return") == true)
    #expect(recovery.activity?.recovery.accessibilityText.contains("retry") == true)
    #expect(await harness.machineActionLog.values.isEmpty)

    try await performPublicAction(
      .captureTargetPoseAndBuildGeometryProposal,
      owner: owner,
      workspace: workspace
    )
    #expect(workspace.explorationError == nil)
    #expect(workspace.proposedMachineCameraRegistration != nil)
    #expect(workspace.proposedTargetObservationRegion != nil)
  }

  @Test("Stop during automatic camera calibration preserves the active 3.3 attempt")
  func automaticCurrentCameraCalibrationStopPreservesAttempt() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )
    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performCameraUtilityAction(.refresh)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    let pacing = CalibrationStopPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)

    let calibration = Task { @MainActor in
      await workspace.performExerciseAction(
        .captureTargetPoseAndBuildGeometryProposal,
        for: owner
      )
    }
    await pacing.waitUntilSuspended()
    let attemptID = try #require(workspace.activeExerciseAttemptID)
    let stopKind = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions
        .first(where: { if case .stop = $0.kind { true } else { false } })?.kind
    )
    let stop = Task { @MainActor in
      await workspace.performExerciseAction(stopKind, for: owner)
    }
    try await waitUntilAsync { await harness.runtime.snapshot().currentOperation == nil }

    #expect(workspace.activeExerciseAttemptID == attemptID)
    #expect(workspace.restartableExerciseItemID == nil)
    let unwindingKinds =
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions.map(\.kind)
      ?? []
    #expect(unwindingKinds.contains(.restart) == false)
    #expect(unwindingKinds.contains(.cancel) == false)

    await pacing.resume()
    await stop.value
    await calibration.value

    #expect(workspace.activeExerciseAttemptID == attemptID)
    #expect(workspace.restartableExerciseItemID == nil)
    #expect(workspace.targetContactPointAndROIAccepted == false)
    #expect(workspace.targetObservationRegion == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.explicitRegistrationContactEvidence.isEmpty)
    #expect(await harness.runtime.snapshot().currentOperation == nil)
    let recovery = workspace.selectedOperatorActionPresentation(for: owner)
    #expect(
      recovery.actionStrip?.actions.map(\.kind) == [
        .captureTargetPoseAndBuildGeometryProposal,
        .rejectTargetGeometryProposal,
        .cancel,
      ]
    )
    #expect(recovery.actionStrip?.actions.contains(where: { $0.kind == .restart }) == false)
    #expect(recovery.activity?.outcome == .needsAttention)
    #expect(recovery.activity?.recovery.accessibilityText.contains("retry") == true)
  }

  @Test("shutdown settles a suspended automatic camera calibration without continuation")
  func shutdownSettlesSuspendedAutomaticCameraCalibration() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      throughVisibility: false
    )
    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performCameraUtilityAction(.refresh)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    let pacing = CalibrationStopPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let completions = EventLog()

    let calibration = Task { @MainActor in
      await workspace.performExerciseAction(
        .captureTargetPoseAndBuildGeometryProposal,
        for: owner
      )
      await completions.append("calibration-returned")
    }
    await pacing.waitUntilSuspended()
    let targetPosition = try #require(workspace.registeredTargetMachinePosition)
    let shutdown = Task { @MainActor in
      await workspace.shutdown()
      await completions.append("shutdown-returned")
    }
    try await waitUntilAsync {
      guard workspace.isShutdown else { return false }
      return await harness.runtime.snapshot().currentOperation == nil
    }

    #expect(workspace.targetContactPointAndROIAccepted == false)
    #expect(workspace.targetObservationRegion == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.explicitRegistrationContactEvidence.isEmpty)
    #expect(await completions.values.isEmpty)

    await pacing.resume()
    try await waitUntilAsync { await completions.values.count == 2 }
    await calibration.value
    await shutdown.value

    let runtimeSnapshot = await harness.runtime.snapshot()
    #expect(runtimeSnapshot.currentOperation == nil)
    #expect(abs(runtimeSnapshot.mpos.xMM - targetPosition.point.x) <= 0.001)
    #expect(abs(runtimeSnapshot.mpos.yMM - targetPosition.point.y) <= 0.001)
    #expect(workspace.isShutdown)
    #expect(workspace.targetContactPointAndROIAccepted == false)
    #expect(workspace.targetObservationRegion == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.explicitRegistrationContactEvidence.isEmpty)
    #expect(
      await completions.values.sorted() == ["calibration-returned", "shutdown-returned"]
    )
  }

  @Test("used targets expose recovery instead of Redo on every pre-draw Stage 3 row")
  func usedTargetCannotBeMadePristineByRedo() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    let workspace = harness.workspace
    let rows: [HumanGuidedDiscoveryStep] = [
      .registerTargetPoseAndCameraGeometry,
      .discoverAndAcceptClearView,
      .confirmBlankTargetBaseline,
      .returnToRegisteredTargetPose,
    ]
    for row in rows {
      let owner = LearningPathItemID.humanGuidedDiscovery(row)
      let kinds = try #require(
        workspace.selectedOperatorActionPresentation(for: owner).actionStrip
      ).actions.map(\.kind)
      #expect(kinds == [.registerNewTargetArea, .paperReplaced])
      #expect(kinds.contains(.redoThisStep) == false)
      #expect(kinds.contains(.drawVisibilityTarget) == false)
    }
    let expectedEvidenceLabels: [HumanGuidedDiscoveryStep: [String]] = [
      .registerTargetPoseAndCameraGeometry: [
        "Exact target-pose capture", "Accepted contact, fit, and ROI",
      ],
      .discoverAndAcceptClearView: ["Target ROI input", "Clear-pose decision"],
      .confirmBlankTargetBaseline: ["Blank-baseline candidate", "Accepted blank baseline"],
      .returnToRegisteredTargetPose: ["Registered-target settlement"],
      .drawVisibilityTarget: ["Accepted drawing inputs", "One-shot target execution"],
      .returnAndObserveExistingTarget: [
        "Accepted-Clear return settlement", "Existing-target observation",
      ],
      .acceptVisibilityRegistration: [
        "Registration candidate", "Target attempt aggregate",
        "Visibility-registration authority",
      ],
    ]
    for (row, expectedLabels) in expectedEvidenceLabels {
      let presentation = workspace.selectedOperatorActionPresentation(
        for: .humanGuidedDiscovery(row)
      )
      #expect(presentation.evidence.map(\.label) == expectedLabels)
    }
    #expect(workspace.visibilityTargetSceneDisposition == .targetObserved)
  }

  @Test("3.6 requires a current Pen-Up Idle target settlement after later manual motion")
  func targetReturnReadinessUsesCurrentControllerFacts() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      drawVisibility: false
    )
    let workspace = harness.workspace
    #expect(workspace.registeredTargetReturnSettlement != nil)
    _ = await workspace.requestRelativeJog(
      try RelativeJogRequest(
        delta: Vector2(dx: 1, dy: 0),
        feedMMPerMinute: 100
      )
    )

    let returnOwner = LearningPathItemID.humanGuidedDiscovery(.returnToRegisteredTargetPose)
    let drawOwner = LearningPathItemID.humanGuidedDiscovery(.drawVisibilityTarget)
    #expect(workspace.currentLearningPathItemID == returnOwner)
    #expect(
      workspace.learningPathItemPresentations.first(where: { $0.id == returnOwner })?.status
        == .current)
    #expect(workspace.selectedOperatorActionPresentation(for: drawOwner).actionStrip == nil)

    try await performPublicAction(.start, owner: returnOwner, workspace: workspace)
    try await performPublicAction(
      .returnToRegisteredTargetPose,
      owner: returnOwner,
      workspace: workspace
    )
    #expect(workspace.currentLearningPathItemID == drawOwner)
  }

  @Test("3.8 requires its retained Clear settlement even when a manual jog reaches Clear")
  func observationCannotBypassClearReturnSettlement() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX],
      returnToClear: false
    )
    let workspace = harness.workspace
    let clear = try #require(workspace.armatureGuidanceState?.acceptedClearPose?.position)
    let current = await harness.runtime.snapshot().mpos
    _ = await workspace.requestRelativeJog(
      try RelativeJogRequest(
        delta: Vector2(
          dx: clear.point.x - current.xMM,
          dy: clear.point.y - current.yMM
        ),
        feedMMPerMinute: 100
      )
    )
    #expect(workspace.acceptedClearReturnSettlement == nil)

    let owner = LearningPathItemID.humanGuidedDiscovery(.returnAndObserveExistingTarget)
    try await performPublicAction(.start, owner: owner, workspace: workspace)
    let beforeSettlement = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(beforeSettlement.contains(.returnToAcceptedClearPose))
    #expect(beforeSettlement.contains(.observeExistingVisibilityTarget) == false)

    try await performPublicAction(.returnToAcceptedClearPose, owner: owner, workspace: workspace)
    #expect(workspace.acceptedClearReturnSettlement != nil)
    let afterSettlement = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    ).actions.map(\.kind)
    #expect(afterSettlement.contains(.observeExistingVisibilityTarget))
  }

  @Test("manual motion after observation routes through 3.8 Return without re-observing")
  func preAcceptanceMotionHasDirectReturnRecovery() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX],
      acceptVisibility: false
    )
    let workspace = harness.workspace
    let existingObservation = try #require(workspace.visibilityTargetObservation)
    _ = await workspace.requestRelativeJog(
      try RelativeJogRequest(
        delta: Vector2(dx: 1, dy: 0),
        feedMMPerMinute: 100
      )
    )

    let observationOwner = LearningPathItemID.humanGuidedDiscovery(
      .returnAndObserveExistingTarget
    )
    let acceptanceOwner = LearningPathItemID.humanGuidedDiscovery(
      .acceptVisibilityRegistration
    )
    #expect(workspace.currentLearningPathItemID == observationOwner)
    try await performPublicAction(.start, owner: observationOwner, workspace: workspace)
    let recoveryKinds = try #require(
      workspace.selectedOperatorActionPresentation(for: observationOwner).actionStrip
    ).actions.map(\.kind)
    #expect(recoveryKinds.contains(.returnToAcceptedClearPose))
    #expect(recoveryKinds.contains(.observeExistingVisibilityTarget) == false)
    try await performPublicAction(
      .returnToAcceptedClearPose,
      owner: observationOwner,
      workspace: workspace
    )

    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.visibilityTargetObservation == existingObservation)
    #expect(workspace.currentLearningPathItemID == acceptanceOwner)
    try await performPublicAction(.start, owner: acceptanceOwner, workspace: workspace)
    try await performPublicAction(
      .acceptVisibilityRegistration,
      owner: acceptanceOwner,
      workspace: workspace
    )
    #expect(workspace.visibilityRegistrationAccepted)
  }

  @Test("visibility final-MPos mismatch settles 3.7 and advances to existing-target observation")
  func visibilityFinalMPosMismatchCannotExposeRedraw() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      drawVisibility: false
    )
    let workspace = harness.workspace
    workspace.replaceSimulatedVisibilityTargetFinalMPosOffsetForTesting(
      try Vector2(dx: 1, dy: 0)
    )
    let drawOwner = LearningPathItemID.humanGuidedDiscovery(.drawVisibilityTarget)
    try await performPublicAction(.start, owner: drawOwner, workspace: workspace)
    try await performPublicAction(.drawVisibilityTarget, owner: drawOwner, workspace: workspace)

    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.visibilityTargetSceneDisposition == .inkPossible)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution) != nil
    )
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.returnAndObserveExistingTarget)
    )
    #expect(workspace.selectedOperatorActionPresentation(for: drawOwner).actionStrip == nil)
    #expect(workspace.explorationError?.contains("no redraw") == true)
  }

  @Test("late target Stop retains execution provenance and reaches explicit 3.9 acceptance")
  func lateVisibilityStopCanObserveButNeverRedraw() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      drawVisibility: false
    )
    let workspace = harness.workspace
    let pacing = LateVisibilityStopPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let drawOwner = LearningPathItemID.humanGuidedDiscovery(.drawVisibilityTarget)
    try await performPublicAction(.start, owner: drawOwner, workspace: workspace)
    let draw = Task { @MainActor in
      await workspace.performExerciseAction(.drawVisibilityTarget, for: drawOwner)
    }
    await pacing.waitUntilLateStopPoint()
    let stopKind = try #require(
      workspace.selectedOperatorActionPresentation(for: drawOwner).actionStrip?.actions
        .first(where: { if case .stop = $0.kind { true } else { false } })?.kind
    )
    let stop = Task { @MainActor in
      await workspace.performExerciseAction(stopKind, for: drawOwner)
    }
    try await waitUntilAsync { await harness.runtime.snapshot().currentOperation == nil }
    await pacing.resume()
    await stop.value
    await draw.value

    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.visibilityTargetSceneDisposition == .inkPossible)
    #expect(workspace.visibilityTargetExecutionAttemptEvidence?.disposition == .stopped)
    #expect(
      workspace.visibilityTargetExecutionAttemptEvidence?.completedTraversalStepCount
        == VisibilityTargetPlanV2().drawingStepCount
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetExecution) != nil
    )
    #expect(workspace.selectedOperatorActionPresentation(for: drawOwner).actionStrip == nil)

    let observationOwner = LearningPathItemID.humanGuidedDiscovery(
      .returnAndObserveExistingTarget
    )
    try await performPublicAction(.start, owner: observationOwner, workspace: workspace)
    try await performPublicAction(
      .returnToAcceptedClearPose,
      owner: observationOwner,
      workspace: workspace
    )
    try await performPublicAction(
      .observeExistingVisibilityTarget,
      owner: observationOwner,
      workspace: workspace
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .visibilityTargetObservation) != nil
    )

    let acceptanceOwner = LearningPathItemID.humanGuidedDiscovery(
      .acceptVisibilityRegistration
    )
    try await performPublicAction(.start, owner: acceptanceOwner, workspace: workspace)
    try await performPublicAction(
      .acceptVisibilityRegistration,
      owner: acceptanceOwner,
      workspace: workspace
    )
    #expect(workspace.visibilityRegistrationAccepted)
  }

  @Test("3.3 Redo supersedes accepted roots and invalidates only their consumers")
  func targetGeometryRedoSupersedesAllThreeRootRevisions() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY],
      drawVisibility: false
    )
    let workspace = harness.workspace
    let graph = workspace.learningArtifactGraph
    let oldTarget = try #require(graph.currentRevision(for: .targetPoseRegistration)?.id)
    let oldMachine = try #require(graph.currentRevision(for: .machineCameraRegistration)?.id)
    let oldROI = try #require(graph.currentRevision(for: .targetROIRegistration)?.id)
    let oldClear = try #require(graph.currentRevision(for: .clearPose)?.id)
    let oldBaseline = try #require(graph.currentRevision(for: .preTargetClearViewBaseline)?.id)
    let owner = LearningPathItemID.humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)

    try await performPublicAction(.redoThisStep, owner: owner, workspace: workspace)
    try await performPublicAction(
      .captureTargetPoseAndBuildGeometryProposal,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(.acceptTargetGeometryProposal, owner: owner, workspace: workspace)

    #expect(workspace.learningArtifactGraph.revision(id: oldTarget)?.state == .superseded)
    #expect(workspace.learningArtifactGraph.revision(id: oldMachine)?.state == .superseded)
    #expect(workspace.learningArtifactGraph.revision(id: oldROI)?.state == .superseded)
    #expect(workspace.learningArtifactGraph.revision(id: oldClear)?.state == .invalidated)
    #expect(workspace.learningArtifactGraph.revision(id: oldBaseline)?.state == .invalidated)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .targetPoseRegistration) != nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) != nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .targetROIRegistration) != nil)
  }

  @Test("Paper Replaced is atomic on refusal and clears authority only after success")
  func paperReplacementRefusalPreservesAcceptedState() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveY, .negativeY, .positiveX, .negativeX]
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)
    let oldArea = workspace.targetAreaIdentity
    let oldToolPaper = (await harness.runtime.snapshot()).toolPaperRevision
    let oldTarget = workspace.learningArtifactGraph.currentRevision(for: .targetPoseRegistration)?
      .id
    let oldFrame = workspace.targetPoseRegistrationFrame
    let active = try acceptedSimulated(
      await harness.runtime.beginManualJog(
        delta: try SimulatedLearningMotionVector(dxMM: 1, dyMM: 0)
      )
    )

    try await performPublicAction(.paperReplaced, owner: owner, workspace: workspace)
    #expect(workspace.targetAreaIdentity == oldArea)
    #expect(workspace.targetPoseRegistrationFrame == oldFrame)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .targetPoseRegistration)?.id
        == oldTarget
    )
    #expect((await harness.runtime.snapshot()).toolPaperRevision == oldToolPaper)
    #expect(workspace.explorationError?.contains("refused") == true)

    _ = try acceptedSimulated(await harness.runtime.cancel(active.id))
    try await performPublicAction(.paperReplaced, owner: owner, workspace: workspace)
    #expect(workspace.targetAreaIdentity != oldArea)
    #expect(workspace.targetPoseRegistrationFrame == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .targetPoseRegistration) == nil)
    #expect((await harness.runtime.snapshot()).toolPaperRevision != oldToolPaper)
    #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == 0)
    #expect(workspace.explorationError == nil)
  }

  @Test("Register New Target Area transitively invalidates Stage 3 and Stage 4 authority")
  func registerNewTargetAreaInvalidatesAllConsumers() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedVisibilityProtocol(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedStageFour(harness.workspace)
    let workspace = harness.workspace
    let oldArea = workspace.targetAreaIdentity
    let oldInkCount = (await harness.runtime.snapshot()).persistentInkSegmentCount
    let oldTarget = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .targetPoseRegistration)?.id
    )
    let oldStageFourRevisionIDs = workspace.learningArtifactGraph.revisions.compactMap {
      revision -> LearningArtifactRevisionID? in
      guard revision.state == .current else { return nil }
      switch revision.kind {
      case .linePlan, .targetAnchoredTrialBaseline, .lineExecution, .postLineFrame,
        .inkObservation, .residual, .comparison:
        return revision.id
      default:
        return nil
      }
    }
    let owner = LearningPathItemID.humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)

    try await performPublicAction(.registerNewTargetArea, owner: owner, workspace: workspace)

    #expect(workspace.targetAreaIdentity != oldArea)
    #expect(workspace.targetAreaRelocationRequired)
    #expect(workspace.retiredTargetAreaDispositions[oldArea] == .targetObserved)
    #expect(workspace.learningArtifactGraph.revision(id: oldTarget)?.state == .invalidated)
    for kind in [
      LearningArtifactKind.targetPoseRegistration,
      .machineCameraRegistration,
      .targetROIRegistration,
      .clearPose,
      .preTargetClearViewBaseline,
      .visibilityTargetExecution,
      .visibilityTargetObservation,
      .visibilityRegistration,
    ] {
      #expect(workspace.learningArtifactGraph.currentRevision(for: kind) == nil)
    }
    for revisionID in oldStageFourRevisionIDs {
      #expect(workspace.learningArtifactGraph.revision(id: revisionID)?.state == .invalidated)
    }
    #expect(workspace.drawingTrialAssessment == nil)
    #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == oldInkCount)
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)
    )
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
      .registerTargetPoseAndCameraGeometry
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

  @Test("Center arrival accepts reproduced controller quantization residual")
  func centerArrivalAcceptsQuantizedSettlement() async throws {
    let target = try MachinePosition(x: -51.975, y: -73.684)
    let reproduced = try MachinePosition(x: -51.963, y: -73.673)
    #expect(ControllerPositionAcceptancePolicy.toleranceMM == 0.05)
    #expect(ControllerPositionAcceptancePolicy.accepts(reproduced, target: target))

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
        == .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)
    )
  }

  @Test("Out-of-tolerance center settlement offers center-only retry")
  func centerArrivalRejectsOutsideToleranceWithoutBoundaryRestart() async throws {
    let target = try MachinePosition(x: 0, y: 0)
    let outside = try MachinePosition(x: 0.04, y: 0.04)
    #expect(!ControllerPositionAcceptancePolicy.accepts(outside, target: target))

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
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveY))
        == nil
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

  @Test("Boundary repeat actions aggregate and replace the accepted set atomically")
  func boundaryRepeatActionsAggregateAndReplaceAcceptedSet() async throws {
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
    #expect(histories.count == 1)
    #expect(aggregate.validSampleCount == 3)
    #expect(aggregate.includedAttemptIDs.count == 3)
    #expect(aggregate.estimator.revision == "boundary-machine-coordinate-v1")
    #expect(history.includedSuccessfulAttempts.count == 3)
    let oldAttemptIDs = aggregate.includedAttemptIDs
    #expect(oldAttemptIDs.count == 3)

    await harness.runtime.injectFault(.cameraConfigurationChangeBeforeNextFrame)
    await workspace.performExerciseAction(.redoBoundary(.positiveX), for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)

    let finalHistories = try #require(workspace.boundaryAttemptHistories[.positiveX])
    let finalHistory = try #require(finalHistories.values.first)
    let finalAggregate = try #require(workspace.boundarySideAggregates[.positiveX])
    let replacementID = try #require(finalHistory.attempts.last?.id)
    #expect(finalHistories.count == 1)
    #expect(finalHistory.records.count == 4)
    #expect(
      finalHistory.records.filter { oldAttemptIDs.contains($0.attempt.id) }
        .allSatisfy { $0.inclusionState == .superseded(by: replacementID) }
    )
    #expect(finalHistory.records.last?.inclusionState == .included)
    #expect(finalHistory.includedSuccessfulAttempts.map(\.id) == [replacementID])
    #expect(finalAggregate.validSampleCount == 1)
    #expect(finalAggregate.includedAttemptIDs == [replacementID])
    #expect(Set(finalAggregate.supersededAttempts.map(\.attemptID)) == Set(oldAttemptIDs))
    #expect(oldAttemptIDs.allSatisfy { workspace.boundaryAttemptEvidenceByAttemptID[$0] != nil })
    #expect(workspace.boundaryAttemptEvidenceByAttemptID[replacementID] != nil)
    #expect(await harness.machineActionLog.values.isEmpty)
  }

  @Test("every injected Boundary commit failure preserves all accepted current authority")
  func boundaryAtomicFailurePreservesAcceptedAuthority() async throws {
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
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )

    for failurePoint in BoundaryAtomicCommitFailurePoint.allCases {
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
      let recoveryActions =
        workspace.selectedOperatorActionPresentation(for: owner)
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
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    let penRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let anchor = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let plan = try #require(workspace.learningVacatePlan(from: anchor))
    #expect(plan.source == .simulated)
    #expect(!plan.removesDurableCheckpoint)
    #expect(plan.physicalInkMayRemain)
    #expect(plan.title == "Reset From This Step")
    #expect(workspace.performLearningVacate(plan))

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
        == penRevisionID
    )
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.estimatedMachineCenter == nil)
    #expect(!workspace.visibilityRegistrationAccepted)
    #expect(workspace.visibilityTargetSceneDisposition == .targetUnusable)
    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.currentLearningPathItemID == anchor)
    await workspace.shutdown()
  }

  @Test("Reset comparison only preserves the observed line and performs no redraw")
  func resetComparisonOnlyPreservesObservedLine() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
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
    try await completeSimulatedVisibilityProtocol(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await performPublicAction(
      .chooseIsolatedLinePlan(.positiveX),
      owner: .observedDrawingTrial(.chooseIsolatedLinePlan),
      workspace: workspace
    )
    try await performPublicAction(
      .captureTargetAnchoredBaseline,
      owner: .observedDrawingTrial(.captureTargetAnchoredBaseline),
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
    #expect(workspace.targetAnchoredTrialBaseline != nil)
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
  cameraActions: OperatorWorkspace.CameraActions? = nil,
  eventLog: EventLog? = nil,
  simulatedExecutionPacing: any SimulatedLearningExecutionPacing =
    SimulatedLearningImmediatePacing()
) -> SimulatedWorkspaceHarness {
  let machineActionLog = eventLog ?? EventLog()
  let clock = TestClock()
  // Workspace state-machine tests need causal pixels and viable vision
  // geometry, not the production simulator's default presentation footprint.
  // Dedicated runtime/renderer tests retain exact 640x480 coverage.
  let runtime = SimulatedLearningRuntime(
    frameWidth: 320,
    frameHeight: 240,
    paddingPixels: 14
  )
  return SimulatedWorkspaceHarness(
    workspace: OperatorWorkspace(
      machineActions: isolatedMachineActions(log: machineActionLog),
      cameraActions: cameraActions ?? CameraComposition.makeIsolatedActionsForTesting(),
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

private func acceptedSimulated<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) throws -> Value {
  try response.result.get()
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
  moveToCenter: Bool = true,
  observeVisibility: Bool = true,
  drawVisibility: Bool = true,
  returnToClear: Bool = true,
  acceptVisibility: Bool = true
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
  let boundaryReviewActions =
    workspace.selectedOperatorActionPresentation(for: boundaryOwner)
    .actionStrip?.actions.map(\.kind) ?? []
  #expect(boundaryReviewActions.first == .moveToEstimatedCenter)
  #expect(boundaryReviewActions.contains(.redoBoundary(boundaryOrder[0])))
  if !moveToCenter { return }
  try await performPublicAction(.moveToEstimatedCenter, owner: boundaryOwner, workspace: workspace)
  if !throughVisibility { return }

  let registrationOwner = LearningPathItemID.humanGuidedDiscovery(
    .registerTargetPoseAndCameraGeometry
  )
  try await performPublicAction(
    .captureTargetPoseAndBuildGeometryProposal,
    owner: registrationOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .acceptTargetGeometryProposal,
    owner: registrationOwner,
    workspace: workspace
  )

  let clearOwner = LearningPathItemID.humanGuidedDiscovery(.discoverAndAcceptClearView)
  try await performPublicAction(.start, owner: clearOwner, workspace: workspace)
  let clearAttemptID = try #require(workspace.activeExerciseAttemptID)
  try await performPublicAction(
    .recordClearViewLabel(.blocked),
    owner: clearOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == clearAttemptID)
  #expect(
    workspace.selectedOperatorActionPresentation(for: clearOwner).actionStrip?.actions
      .first(where: { $0.kind == .acceptClearPose })?.isEnabled == false
  )
  try await selectPublicDirection(
    .positiveX,
    purpose: .clearViewSearch,
    owner: clearOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .moveForClearView(ClearViewSearchMove(direction: .positiveX, distance: .tenMillimeters)),
    owner: clearOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .recordClearViewLabel(.partial),
    owner: clearOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == clearAttemptID)
  #expect(
    workspace.selectedOperatorActionPresentation(for: clearOwner).actionStrip?.actions
      .first(where: { $0.kind == .acceptClearPose })?.isEnabled == false
  )
  try await performPublicAction(
    .moveForClearView(ClearViewSearchMove(direction: .positiveX, distance: .twoMillimeters)),
    owner: clearOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .recordClearViewLabel(.clear),
    owner: clearOwner,
    workspace: workspace
  )
  #expect(workspace.activeExerciseAttemptID == clearAttemptID)
  try await performPublicAction(.acceptClearPose, owner: clearOwner, workspace: workspace)

  let baselineOwner = LearningPathItemID.humanGuidedDiscovery(.confirmBlankTargetBaseline)
  try await performPublicAction(.start, owner: baselineOwner, workspace: workspace)
  try await performPublicAction(
    .captureBlankTargetBaselineCandidate,
    owner: baselineOwner,
    workspace: workspace
  )
  try await performPublicAction(
    .confirmBlankTargetBaseline,
    owner: baselineOwner,
    workspace: workspace
  )

  let targetReturnOwner = LearningPathItemID.humanGuidedDiscovery(.returnToRegisteredTargetPose)
  try await performPublicAction(.start, owner: targetReturnOwner, workspace: workspace)
  try await performPublicAction(
    .returnToRegisteredTargetPose,
    owner: targetReturnOwner,
    workspace: workspace
  )
  if !drawVisibility { return }

  let drawOwner = LearningPathItemID.humanGuidedDiscovery(.drawVisibilityTarget)
  try await performPublicAction(.start, owner: drawOwner, workspace: workspace)
  try await performPublicAction(.drawVisibilityTarget, owner: drawOwner, workspace: workspace)
  if !returnToClear { return }

  let observationOwner = LearningPathItemID.humanGuidedDiscovery(.returnAndObserveExistingTarget)
  try await performPublicAction(.start, owner: observationOwner, workspace: workspace)
  try await performPublicAction(
    .returnToAcceptedClearPose,
    owner: observationOwner,
    workspace: workspace
  )
  if !observeVisibility { return }
  try await performPublicAction(
    .observeExistingVisibilityTarget,
    owner: observationOwner,
    workspace: workspace
  )
  if !acceptVisibility { return }

  let acceptanceOwner = LearningPathItemID.humanGuidedDiscovery(.acceptVisibilityRegistration)
  try await performPublicAction(.start, owner: acceptanceOwner, workspace: workspace)
  try await performPublicAction(
    .acceptVisibilityRegistration,
    owner: acceptanceOwner,
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
  cameraActionsOverride: OperatorWorkspace.CameraActions? = nil,
  boundaryMotionBegin:
    (@Sendable (BoundaryMotionRequest, BoundaryMotionRenewalPlanner?) async
      -> BoundaryMotionAdmission)? = nil,
  jogCancel: (@Sendable (JogCancelIntent) async -> JogCancelOutcome)? = nil,
  announcements: AnnouncementFixture? = nil,
  checkpointActions: OperatorWorkspace.AcceptedArtifactCheckpointActions? = nil,
  log _: EventLog
) -> OperatorWorkspace {
  let clock = TestClock()
  let beginBoundaryMotion = boundaryMotionBegin ?? { @Sendable request, _ in
    BoundaryMotionAdmission.admitted(
      BoundaryMotionOperation(
        ownerID: request.ownerID,
        task: Task { await machine.requestBoundaryMotion(request) }
      )
    )
  }
  let requestJogCancel = jogCancel ?? { @Sendable intent in
    await machine.cancel(intent: intent)
  }
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
      beginBoundaryMotion: beginBoundaryMotion,
      requestJogCancel: requestJogCancel,
      disconnect: {}
    ),
    cameraActions: cameraActionsOverride ?? camera.map(cameraActions),
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
    beginVisibilityTarget: { request in
      await log.append("beginVisibilityTarget")
      return .rejected(
        .needsAttention(
          phase: .approach,
          scene: .pristine,
          failure: .approach(.refused(.notConnected)),
          progress: VisibilityTargetOperationProgress(
            planRevision: request.plan.algorithmRevision,
            phase: .approach,
            completedTraversalStepCount: 0,
            lastCompletedTraversalStep: nil
          )
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
    beginBoundaryMotion: { request, _ in
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
    observeVisibilityTarget: { _, _ in fatalError("unused") },
  )
}

private actor EventLog {
  private(set) var values: [String] = []
  func append(_ value: String) { values.append(value) }
  func clear() { values.removeAll(keepingCapacity: true) }
}

private actor VisibilityObservationGate {
  enum CancellationDisposition: Sendable {
    case cancelled
    case staleRejection
  }

  private let cancellationDisposition: CancellationDisposition
  private let log: EventLog?
  private var continuation: CheckedContinuation<VisibilityTargetObservationOutcome, Never>?
  private var cancellationFrameID: FrameID?
  private(set) var callCount = 0
  private(set) var cancelRequestCount = 0

  init(
    cancellationDisposition: CancellationDisposition,
    log: EventLog? = nil
  ) {
    self.cancellationDisposition = cancellationDisposition
    self.log = log
  }

  func observe(
    _ request: VisibilityTargetObservationRequest,
    progress: @escaping @Sendable (VisibilityTargetObservationProgress) -> Void
  ) async -> VisibilityTargetObservationOutcome {
    callCount += 1
    cancellationFrameID = request.targetSamples.first?.frame.id
    progress(VisibilityTargetObservationProgress(sampleIndex: 1, sampleCount: 2))
    let outcome = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled {
          continuation.resume(returning: cancellationOutcome())
        } else {
          self.continuation = continuation
        }
      }
    } onCancel: {
      Task { await self.requestCancellation() }
    }
    await log?.append("vision-returned")
    return outcome
  }

  private func requestCancellation() async {
    cancelRequestCount += 1
    await log?.append("vision-cancel-requested")
    continuation?.resume(returning: cancellationOutcome())
    continuation = nil
  }

  private func cancellationOutcome() -> VisibilityTargetObservationOutcome {
    switch cancellationDisposition {
    case .cancelled:
      return .cancelled
    case .staleRejection:
      return .rejected(
        .targetMissing(
          frameID: cancellationFrameID ?? FrameID(rawValue: "late-stale-frame")
        ))
    }
  }
}

private func gatedCameraActions(
  gate: VisibilityObservationGate,
  log: EventLog? = nil
) -> OperatorWorkspace.CameraActions {
  let base = CameraComposition.makeIsolatedActionsForTesting()
  return OperatorWorkspace.CameraActions(
    discover: base.discover,
    select: base.select,
    start: base.start,
    stop: {
      await log?.append("camera-stop")
      return await base.stop()
    },
    restart: base.restart,
    snapshot: base.snapshot,
    frames: base.frames,
    inspectScene: base.inspectScene,
    captureFrame: base.captureFrame,
    captureSnapshot: base.captureSnapshot,
    setAutomaticInspection: base.setAutomaticInspection,
    analysisUpdates: base.analysisUpdates,
    observeIsolatedInk: base.observeIsolatedInk,
    observeVisibilityTarget: { request, progress in
      await gate.observe(request, progress: progress)
    }
  )
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

  func clear() {
    lock.lock()
    stored = nil
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
  private var automaticInspectionRequests: [VisionAnalysisCadence?] = []

  var inspectionCallCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return inspectionCount
  }

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
    return automaticInspectionRequests.compactMap { $0 }
  }

  var recordedAutomaticInspectionRequests: [VisionAnalysisCadence?] {
    lock.lock()
    defer { lock.unlock() }
    return automaticInspectionRequests
  }

  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?
  ) -> PlotterSceneAnalysisSnapshot {
    lock.lock()
    automaticInspectionRequests.append(cadence)
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

private actor BoundaryRenewalMotionGate {
  private var segmentReleased = false
  private var segmentContinuation: CheckedContinuation<Void, Never>?
  private var pendingCancelIntent: JogCancelIntent?
  private var cancelContinuation: CheckedContinuation<JogCancelIntent, Never>?
  private var finalPosition: MachinePosition?
  private(set) var request: BoundaryMotionRequest?

  func run(
    _ request: BoundaryMotionRequest,
    renewalPlanner: BoundaryMotionRenewalPlanner?
  ) async -> BoundaryMotionOutcome {
    self.request = request
    await waitForFirstSegmentRelease()
    let finalPosition = try! MachinePosition(
      x: request.segment.delta.dx,
      y: request.segment.delta.dy
    )
    self.finalPosition = finalPosition
    if let renewalPlanner {
      _ = await renewalPlanner.nextSegmentLength(
        after: BoundaryMotionSegmentProgress(
          ownerID: request.ownerID,
          direction: request.direction,
          completedSegmentCount: 1,
          completedSegment: request.segment,
          startPosition: try! MachinePosition(x: 0, y: 0),
          finalPosition: finalPosition
        )
      )
    }
    let intent = await waitForCancelIntent()
    return .settled(
      BoundaryMotionSettlement(
        ownerID: request.ownerID,
        intent: intent,
        completedSegmentCount: 1,
        finalPosition: finalPosition,
        jogCancelOutcome: .completed(finalPosition: finalPosition)
      )
    )
  }

  func releaseFirstSegment() {
    segmentReleased = true
    segmentContinuation?.resume()
    segmentContinuation = nil
  }

  func cancel(_ intent: JogCancelIntent) -> JogCancelOutcome {
    if let cancelContinuation {
      self.cancelContinuation = nil
      cancelContinuation.resume(returning: intent)
    } else {
      pendingCancelIntent = intent
    }
    return .completed(finalPosition: finalPosition ?? (try! MachinePosition(x: 0, y: 0)))
  }

  private func waitForFirstSegmentRelease() async {
    guard !segmentReleased else { return }
    await withCheckedContinuation { segmentContinuation = $0 }
  }

  private func waitForCancelIntent() async -> JogCancelIntent {
    if let pendingCancelIntent {
      self.pendingCancelIntent = nil
      return pendingCancelIntent
    }
    return await withCheckedContinuation { cancelContinuation = $0 }
  }
}

private actor BoundaryInspectionGate {
  private var started = false
  private var cancelled = false
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?

  var isStarted: Bool { started }
  var isCancelled: Bool { cancelled }

  func inspect(_ inspection: LiveSceneInspection) async throws -> LiveSceneInspection {
    started = true
    await withTaskCancellationHandler {
      if !released {
        await withCheckedContinuation { continuation = $0 }
      }
    } onCancel: {
      Task { await self.recordCancellation() }
    }
    try Task.checkCancellation()
    return inspection
  }

  func release() {
    released = true
    continuation?.resume()
    continuation = nil
  }

  private func recordCancellation() {
    cancelled = true
  }
}

private func boundaryGatedCameraActions(
  _ fixture: CameraFixture,
  gate: BoundaryInspectionGate
) -> OperatorWorkspace.CameraActions {
  let base = cameraActions(fixture)
  return OperatorWorkspace.CameraActions(
    discover: base.discover,
    select: base.select,
    start: base.start,
    stop: base.stop,
    restart: base.restart,
    snapshot: base.snapshot,
    frames: base.frames,
    inspectScene: { boundary in
      try await gate.inspect(fixture.inspection(after: boundary))
    },
    captureFrame: base.captureFrame,
    captureSnapshot: base.captureSnapshot,
    setAutomaticInspection: base.setAutomaticInspection,
    analysisUpdates: base.analysisUpdates,
    observeIsolatedInk: base.observeIsolatedInk,
    observeVisibilityTarget: base.observeVisibilityTarget
  )
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

private actor LateVisibilityStopPacing: SimulatedLearningExecutionPacing {
  private let lateStopSuspension = VisibilityTargetPlanV2().drawingStepCount + 3
  private var suspensionCount = 0
  private var suspension: CheckedContinuation<Void, Never>?
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func suspendBetweenSteps() async {
    suspensionCount += 1
    guard suspensionCount == lateStopSuspension else { return }
    await withCheckedContinuation { continuation in
      suspension = continuation
      let pending = waiters
      waiters.removeAll()
      for waiter in pending { waiter.resume() }
    }
  }

  func waitUntilLateStopPoint() async {
    if suspensionCount >= lateStopSuspension { return }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  func resume() {
    let continuation = suspension
    suspension = nil
    continuation?.resume()
  }
}

private actor CalibrationStopPacing: SimulatedLearningExecutionPacing {
  private var suspended = false
  private var suspension: CheckedContinuation<Void, Never>?
  private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []

  func suspendBetweenSteps() async {
    await withCheckedContinuation { continuation in
      suspension = continuation
      suspended = true
      let waiters = suspensionWaiters
      suspensionWaiters.removeAll()
      for waiter in waiters { waiter.resume() }
    }
  }

  func waitUntilSuspended() async {
    if suspended { return }
    await withCheckedContinuation { continuation in
      suspensionWaiters.append(continuation)
    }
  }

  func resume() {
    let continuation = suspension
    suspension = nil
    continuation?.resume()
  }
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

private struct TestTimeout: Error {}
private struct StepMismatch: Error {
  let expected: String
  let actual: String
}
