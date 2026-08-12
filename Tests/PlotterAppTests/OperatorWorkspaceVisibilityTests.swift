import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("Visibility-target search circle is exact-frame anchored and resolution normalized")
  func visibilityTargetSearchCircleUsesExactCapAnchor() throws {
    let frame = try StampedFrame(
      id: FrameID(rawValue: "cap-anchor-frame"),
      sequence: 7,
      captureNanoseconds: 700,
      cameraConfigurationID: CameraConfigurationID(),
      width: 640,
      height: 480,
      rowBytes: 640,
      pixelFormat: .gray8,
      bytes: OwnedFrameBytes(Array(repeating: 0, count: 640 * 480))
    )
    let displayed = DisplayedFrame(source: .simulated, frame: frame)
    let capAnchor = try Point2<CameraPixelSpace>(x: 320, y: 240)

    let proposal = try #require(
      VisibilityTargetSearchCirclePolicy.proposal(
        capAnchor: capAnchor,
        anchorFrame: displayed
      )
    )

    #expect(proposal.center == capAnchor)
    #expect(proposal.radiusPixels == 240)
    #expect(proposal.boundingROI == PixelRect(x: 80, y: 0, width: 481, height: 480))
    #expect(proposal.anchorFrame.frameID == frame.id)
    #expect(proposal.anchorFrame.frameSHA256 == frame.contentSHA256)
    #expect(proposal.algorithmRevision == "visibility-target-cap-tip-search-circle-v2")
    #expect(VisibilityTargetSearchCirclePolicy.acquisitionRadius(
      frameWidth: 320,
      frameHeight: 240
    ) == 120)
    #expect(VisibilityTargetSearchCirclePolicy.acquisitionRadius(
      frameWidth: 1_920,
      frameHeight: 1_080
    ) == 540)
  }

  @Test("Live-frame search scale contains the observed cap-to-tip displacement")
  func liveFrameSearchCircleContainsObservedOffset() throws {
    let frame = try StampedFrame(
      id: FrameID(rawValue: "live-scale-cap-anchor-frame"),
      sequence: 8,
      captureNanoseconds: 800,
      cameraConfigurationID: CameraConfigurationID(),
      width: 1_920,
      height: 1_080,
      rowBytes: 1_920,
      pixelFormat: .gray8,
      bytes: OwnedFrameBytes(Array(repeating: 0, count: 1_920 * 1_080))
    )
    let displayed = DisplayedFrame(source: .simulated, frame: frame)
    let proposal = try #require(VisibilityTargetSearchCirclePolicy.proposal(
      capAnchor: Point2(x: 1_490, y: 525),
      anchorFrame: displayed
    ))

    #expect(proposal.contains(x: 1_000, y: 575))
    #expect(!proposal.contains(x: 900, y: 575))
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
    let offsetRegistration = try #require(harness.workspace.penTipOffsetRegistration)
    let simulatorTruth = await harness.runtime.capToTipPixelOffsetTruth()
    #expect(abs(offsetRegistration.capToTipOffset.dx - simulatorTruth.dx) <= 1)
    #expect(abs(offsetRegistration.capToTipOffset.dy - simulatorTruth.dy) <= 1)
    #expect(offsetRegistration.capToTipOffset.magnitude > 100)
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(
        for: .penTipOffsetRegistration
      ) != nil
    )
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
    let residual = try #require(harness.workspace.lastInkObservation?.residual)
    #expect(residual.maximumEndpointPixels <= 2)
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
    let telemetry = WorkflowTelemetryFixture()
    let harness = makeSimulatedHarness(workflowTelemetry: telemetry)
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
    let evidence = workspace.explicitRegistrationCapAnchorEvidence.filter {
      $0.cameraConfigurationID == cameraConfigurationID
        && $0.algorithmRevision == "automatic-current-camera-cap-anchor-v3"
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
    #expect(!workspace.targetCapAnchorAndSearchCircleAccepted)
    #expect(workspace.targetSearchCircle == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.proposedTargetSearchCircle != nil)
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
    #expect(workspace.targetCapAnchorAndSearchCircleAccepted)
    #expect(workspace.targetSearchCircle != nil)
    #expect(workspace.machineCameraRegistration != nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) != nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .targetROIRegistration) != nil)
    #expect(workspace.explorationError == nil)
    #expect(workspace.boundarySideAggregates == aggregates)
    #expect(workspace.estimatedMachineCenter == center)
    #expect(workspace.learnedLocalCoordinateFrame == localFrame)
    #expect(await harness.machineActionLog.values.isEmpty)
    let recordedTelemetry = await telemetry.events
    let calibrationEvents = recordedTelemetry.filter {
      $0.operation == .currentCameraCalibration
    }
    #expect(calibrationEvents.first?.phase == .intentAccepted)
    #expect(calibrationEvents.last?.phase == .completed)
    #expect(calibrationEvents.contains { $0.phase == .phaseChanged })
  }

  @Test(
    "automatic current-camera calibration refusal preserves machine authority and exposes retry"
  )
  func automaticCurrentCameraCalibrationRefusalPreservesMachineAuthority() async throws {
    let telemetry = WorkflowTelemetryFixture()
    let harness = makeSimulatedHarness(workflowTelemetry: telemetry)
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

    #expect(workspace.targetCapAnchorAndSearchCircleAccepted == false)
    #expect(workspace.targetSearchCircle == nil)
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
    #expect(workspace.explorationError?.contains("controllerOutcome(") == false)
    #expect(workspace.explicitRegistrationCapAnchorEvidence.isEmpty)

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
    #expect(recovery.activity?.recovery.accessibilityText.contains("still at") == true)
    #expect(recovery.activity?.recovery.accessibilityText.contains("Return") == false)
    #expect(recovery.activity?.recovery.accessibilityText.contains("retry") == true)
    #expect(await harness.machineActionLog.values.isEmpty)
    let recordedTelemetry = await telemetry.events
    let failedEvent = recordedTelemetry.last {
      $0.operation == .currentCameraCalibration && $0.phase == .failed
    }
    #expect(failedEvent?.failureCode == "controller_outcome")
    #expect(failedEvent?.recovery == .retryCalibration)

    try await performPublicAction(
      .captureTargetPoseAndBuildGeometryProposal,
      owner: owner,
      workspace: workspace
    )
    #expect(workspace.explorationError == nil)
    #expect(workspace.proposedMachineCameraRegistration != nil)
    #expect(workspace.proposedTargetSearchCircle != nil)
  }

  @Test("LIVE calibration ignores the stale pre-pen probe and establishes a local baseline")
  func liveCalibrationUsesOperationScopedControllerBaseline() async throws {
    let log = EventLog()
    let telemetry = WorkflowTelemetryFixture()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      workflowTelemetry: telemetry,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    #expect(
      workspace.passiveProbeResult?.exchanges
        .first(where: { $0.query == .parserState })?.lines
        .contains(where: { $0.text.contains("M5") && $0.text.contains("S0") }) == true
    )
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(.moveToEstimatedCenter, owner: boundaryOwner, workspace: workspace)

    let registrationOwner = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    try await performPublicAction(
      .captureTargetPoseAndBuildGeometryProposal,
      owner: registrationOwner,
      workspace: workspace
    )

    #expect(workspace.explorationError?.contains("controller_context_changed") != true)
    #expect(workspace.explorationError?.contains("controllerOutcome(") != true)
    #expect(
      workspace.passiveProbeResult?.exchanges
        .first(where: { $0.query == .parserState })?.lines
        .contains(where: { $0.text.contains("M3") && $0.text.contains("S40") }) == true
    )
    let recordedTelemetry = await telemetry.events
    let events = recordedTelemetry.filter {
      $0.operation == .currentCameraCalibration
    }
    #expect(events.contains { $0.phase == .controllerContextEstablished })
    let comparisons = events.compactMap(\.controllerContext?.comparison)
    #expect(!comparisons.isEmpty)
    #expect(comparisons.allSatisfy { $0.isCompatible })
    await workspace.shutdown()
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
    #expect(workspace.targetCapAnchorAndSearchCircleAccepted == false)
    #expect(workspace.targetSearchCircle == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.explicitRegistrationCapAnchorEvidence.isEmpty)
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

    #expect(workspace.targetCapAnchorAndSearchCircleAccepted == false)
    #expect(workspace.targetSearchCircle == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.explicitRegistrationCapAnchorEvidence.isEmpty)
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
    #expect(workspace.targetCapAnchorAndSearchCircleAccepted == false)
    #expect(workspace.targetSearchCircle == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.explicitRegistrationCapAnchorEvidence.isEmpty)
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
        "Exact target-pose capture", "Accepted cap anchor, fit, and search circle",
      ],
      .discoverAndAcceptClearView: ["Target search-circle input", "Clear-pose decision"],
      .confirmBlankTargetBaseline: ["Blank-baseline candidate", "Accepted blank baseline"],
      .returnToRegisteredTargetPose: ["Registered-target settlement"],
      .drawVisibilityTarget: ["Accepted drawing inputs", "One-shot target execution"],
      .returnAndObserveExistingTarget: [
        "Accepted-Clear return settlement", "Existing-target observation",
      ],
      .acceptVisibilityRegistration: [
        "Registration candidate", "Target attempt aggregate",
        "Cap-to-tip registration",
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
}
