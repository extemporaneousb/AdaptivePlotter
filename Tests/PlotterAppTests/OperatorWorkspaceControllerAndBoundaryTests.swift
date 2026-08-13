import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("production camera settling accepts bounded wobble without changing MPos authority")
  func fixedCameraSettlingPolicyIsOpticalOnly() {
    #expect(FixedCameraOpticalSettlingPolicy.alignmentSearchRadiusPixels == 3)
    #expect(FixedCameraOpticalSettlingPolicy.maximumAlignmentShiftPixels == 2)
    #expect(FixedCameraOpticalSettlingPolicy.maximumCentroidSpreadPixels == 2)
    #expect(ControllerPositionAcceptancePolicy.toleranceMM == 0.05)
  }

  @Test("selected scene overlays directly own bounded LIVE analysis")
  func selectedSceneOverlaysOwnAnalysis() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture(
      providesInspectionOverlay: true,
      providesAutomaticAnalysisResult: true
    )
    let workspace = workspace(machine: machine, camera: camera, log: log)

    await workspace.startCamera()
    #expect(!workspace.scopedVisionAnalysisActive)
    #expect(workspace.visibleLayers == Set(CanvasLayer.allCases))
    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS])
    #expect(workspace.actionSurfacePresentation.overlays.count == 1)

    for layer in CanvasLayer.allCases where layer.requiresSceneAnalysis {
      workspace.setLayer(layer, visible: false)
    }
    try await waitUntil { camera.recordedAutomaticInspectionRequests.last == .some(nil) }
    #expect(workspace.visibleLayers.contains(.intendedPath))
    #expect(workspace.actionSurfacePresentation.overlays.isEmpty)
    await workspace.shutdown()
  }

  @Test("locked viewport and selected cadence configure scene analysis")
  func lockedViewportConfiguresAnalysis() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.startCamera()
    let displayedFrame = try #require(workspace.actionSurfacePresentation.displayedFrame)
    let region = PixelRect(
      x: 0,
      y: 0,
      width: displayedFrame.frame.width,
      height: displayedFrame.frame.height
    )

    await workspace.setVideoAnalysisRegion(region, for: displayedFrame)
    await workspace.setVisionAnalysisCadence(.fiveFPS)

    #expect(workspace.videoAnalysisRegionLock?.region == region)
    #expect(camera.recordedSceneAnalysisRegionRequests.contains(region))
    #expect(camera.recordedAutomaticInspectionRequests.last == .fiveFPS)
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

  @Test("manual jog telemetry preserves operator intent and cannot be mistaken for calibration")
  func manualJogTelemetryNamesOperationAndDistance() async throws {
    let log = EventLog()
    let telemetry = WorkflowTelemetryFixture()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let workspace = workspace(
      machine: machine,
      workflowTelemetry: telemetry,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let request = RelativeJogRequest(
      delta: try Vector2(dx: -100, dy: 0),
      feedMMPerMinute: 500
    )
    let outcome = await workspace.requestRelativeJog(request)

    guard case .acceptedThenCompleted = outcome else {
      Issue.record("Expected the fixture's manual jog to complete.")
      return
    }
    let events = await telemetry.events
    #expect(events.map(\.operation) == [.manualJog, .manualJog])
    #expect(events.map(\.phase) == [.intentAccepted, .completed])
    #expect(events.allSatisfy { $0.motionIntent?.deltaXMM == -100 })
    #expect(events.allSatisfy { $0.operation != .currentCameraCalibration })
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
    let automaticBeforeBoundary = camera.recordedAutomaticInspectionRequests

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
    #expect(camera.recordedAutomaticInspectionRequests == automaticBeforeBoundary)
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

  @Test("Boundary Stop settles advisory Vision without disturbing overlay analysis")
  func boundaryStopSettlesAdvisoryWithoutDisturbingOverlayAnalysis() async throws {
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
    let automaticBeforeBoundary = camera.recordedAutomaticInspectionRequests

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await workspace.performExerciseAction(.start, for: owner)
    try await waitUntil {
      workspace.contextualStopPresentation != nil
    }
    #expect(camera.recordedAutomaticInspectionRequests == automaticBeforeBoundary)
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

    #expect(camera.recordedAutomaticInspectionRequests == automaticBeforeBoundary)
    await inspectionGate.release()
    await stopTask.value

    #expect(camera.recordedAutomaticInspectionRequests == automaticBeforeBoundary)
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

}
