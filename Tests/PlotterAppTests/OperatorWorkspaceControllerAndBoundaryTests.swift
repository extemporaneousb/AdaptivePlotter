import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("failed Connect exposes the typed alarm and explicit Clear Alarm reprobes without enabling motion")
  func alarmClearUIStateAndAuthority() async throws {
    let fixture = AlarmClearWorkspaceFixture()
    let descriptor = fixture.descriptor
    let workspace = OperatorWorkspace(
      machineActions: .init(
        select: { _ in await fixture.select() },
        snapshot: { await fixture.snapshot() },
        requestPassiveProbe: { await fixture.requestPassiveProbe() },
        requestControllerAlarmClear: { await fixture.requestAlarmClear() },
        activateMotionGuard: { .refused(.notConnected) },
        beginRelativeJog: { _ in .rejected(.refused(.notConnected)) },
        beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
        requestPenActuation: { _, _ in .refused(.notConnected) },
        beginBoundaryMotion: { request in
          .rejected(
            .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
          )
        },
        requestJogCancel: { _ in .refused(.noActiveJog) },
        disconnect: {}
      ),
      serialDevices: [descriptor],
      serialDeviceDiscovery: { [descriptor] },
      loadSelectedSerialIdentifier: { descriptor.identifier },
      persistSelectedSerialIdentifier: { _ in }
    )

    await workspace.performControllerConnectionAction()

    #expect(!workspace.controllerSessionEstablished)
    #expect(!workspace.motionAuthorizationEnabled)
    #expect(workspace.controllerAlarmEvidenceText == "ALARM:1")
    #expect(workspace.controllerAttentionText == "Controller alarm: ALARM:1")
    #expect(workspace.controllerLimitInputsText == "clear — sampled Pn has no X/Y/Z")
    #expect(
      workspace.controllerAlarmUnlockReadinessText == "armed — manual clear available"
    )
    #expect(workspace.controllerAlarmClearActionUnavailableReason == nil)
    let expectedRequestStatus = MotionRequestStatusPresentation.needsAttention(
      "Controller alarm: ALARM:1"
    )
    #expect(workspace.motionRequestStatusPresentation == expectedRequestStatus)
    let connectID = LearningPathItemID.stage(.connect)
    let failedProjection = workspace.learningPathProjection(
      selectedItemID: connectID
    )
    let connectStatus = failedProjection.items.first(where: { $0.id == connectID })?.status
    #expect(connectStatus == LearningPathStageStatus.needsAttention)
    #expect(await fixture.actions == ["select", "probe:alarm"])

    await workspace.clearControllerAlarm()

    #expect(await fixture.actions == ["select", "probe:alarm", "clear-alarm", "probe:ready"])
    #expect(workspace.controllerAlarmEvidenceText == nil)
    #expect(workspace.controllerAttentionText == nil)
    #expect(workspace.controllerSessionEstablished)
    #expect(!workspace.motionAuthorizationEnabled)
    #expect(workspace.motionGuardActivationUnavailableReason == nil)
    #expect(workspace.motionUnavailableReason == "Enable Motion before moving.")
    await workspace.shutdown()
  }

  @Test("asserted physical limit is visible and disarms Clear Alarm")
  func assertedLimitDisarmsAlarmClearUI() async throws {
    let fixture = AlarmClearWorkspaceFixture(alarmPins: "X")
    let descriptor = fixture.descriptor
    let workspace = OperatorWorkspace(
      machineActions: .init(
        select: { _ in await fixture.select() },
        snapshot: { await fixture.snapshot() },
        requestPassiveProbe: { await fixture.requestPassiveProbe() },
        requestControllerAlarmClear: { await fixture.requestAlarmClear() },
        activateMotionGuard: { .refused(.notConnected) },
        beginRelativeJog: { _ in .rejected(.refused(.notConnected)) },
        beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
        requestPenActuation: { _, _ in .refused(.notConnected) },
        beginBoundaryMotion: { request in
          .rejected(
            .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
          )
        },
        requestJogCancel: { _ in .refused(.noActiveJog) },
        disconnect: {}
      ),
      serialDevices: [descriptor],
      serialDeviceDiscovery: { [descriptor] },
      loadSelectedSerialIdentifier: { descriptor.identifier },
      persistSelectedSerialIdentifier: { _ in }
    )

    await workspace.performControllerConnectionAction()

    #expect(workspace.controllerLimitInputsText == "asserted — Pn:X")
    #expect(
      workspace.controllerAlarmUnlockReadinessText
        == "blocked — Pn:X is physically asserted"
    )
    #expect(
      workspace.controllerAlarmClearActionUnavailableReason
        == ControllerAlarmClearRefusal.axisLimitAsserted("X").actionableDescription
    )
    await workspace.clearControllerAlarm()
    #expect(await fixture.actions == ["select", "probe:alarm"])
    await workspace.shutdown()
  }

  @Test("manual motion fields start at 50 mm, 50 mm, and 500 mm/min")
  func manualMotionDefaults() throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)

    #expect(workspace.xStepText == "50")
    #expect(workspace.yStepText == "50")
    #expect(workspace.feedText == "500")
  }

  @Test("unknown pen still admits an operator-authored manual direction request")
  func unknownPenAllowsManualMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    await machine.setPenState(.unknown)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    #expect(workspace.motionUnavailableReason == nil)
    await workspace.requestJog(.xPositive)

    #expect(workspace.machinePositionText == "X 50.000   Y 0.000")
    #expect(await machine.requestedFeeds == [500])
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    await workspace.shutdown()
  }

  @Test("Pen Interaction sliders update current values and retain them in its existing attempt")
  func penInteractionRetainsMutableCurrentValues() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.beginPenInteraction()
    try await identifyPenCap(workspace)
    try requireStep(workspace, "answer-initially-up")
    var strip = try #require(workspace.selectedOperatorActionPresentation(for: owner).actionStrip)
    #expect(strip.penSetpointAdjustment?.command == .raise)
    #expect(strip.penSetpointAdjustment?.value == 40)
    #expect(strip.actions.map(\.title) == ["Next"])

    await workspace.performExerciseAction(.setPenSetpoint(.raise, 55), for: owner)
    try await waitUntilAsync {
      await machine.requestedPenProfiles.last?.raisedSpindleValue == 55
    }
    await workspace.answerCurrentQuestion(.yes)

    try requireStep(workspace, "answer-currently-down")
    strip = try #require(workspace.selectedOperatorActionPresentation(for: owner).actionStrip)
    #expect(strip.penSetpointAdjustment?.command == .lower)
    #expect(strip.penSetpointAdjustment?.value == 760)
    #expect(strip.actions.map(\.title) == ["Next"])

    await workspace.performExerciseAction(.setPenSetpoint(.lower, 805), for: owner)
    try await waitUntilAsync {
      await machine.requestedPenProfiles.last?.loweredSpindleValue == 805
    }
    await workspace.answerCurrentQuestion(.yes)

    try requireStep(workspace, "answer-finally-up")
    strip = try #require(workspace.selectedOperatorActionPresentation(for: owner).actionStrip)
    #expect(strip.penSetpointAdjustment?.command == .raise)
    #expect(strip.penSetpointAdjustment?.value == 55)
    await workspace.answerCurrentQuestion(.yes)

    let evidence = try #require(workspace.currentPenInteractionAggregate?.value)
    #expect(evidence.actuationProfile.raisedSpindleValue == 55)
    #expect(evidence.actuationProfile.loweredSpindleValue == 805)
    #expect(evidence.confirmedUpPositions.count == 2)
    #expect(evidence.confirmedUpSpindleValues == [55, 55])
    #expect(evidence.confirmedUpControllerOutcomes.count == 2)
    #expect(evidence.confirmedUpTimestamps.count == 2)
    #expect(evidence.confirmedDownPositions.count == 1)
    #expect(evidence.confirmedDownSpindleValues == [805])
    #expect(evidence.confirmedDownControllerOutcomes.count == 1)
    #expect(evidence.confirmedDownTimestamps.count == 1)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) != nil)
    await workspace.shutdown()
  }

  @Test("Pen Interaction coalesces drag values, Next waits, and Cancel drops an unaccepted value")
  func penInteractionLatestValueAndCancelSemantics() async throws {
    let log = EventLog()
    let gate = PenRequestGate()
    let machine = try MachineFixture(log: log, penRequestGate: gate)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.beginPenInteraction()
    try await identifyPenCap(workspace)
    await workspace.performExerciseAction(.setPenSetpoint(.raise, 55), for: owner)
    try await waitUntilAsync { await machine.requestedPenProfiles.count == 1 }
    await workspace.performExerciseAction(.setPenSetpoint(.raise, 56), for: owner)
    await workspace.performExerciseAction(.setPenSetpoint(.raise, 57), for: owner)

    let next = Task { await workspace.answerCurrentQuestion(.yes) }
    await Task.yield()
    try requireStep(workspace, "answer-initially-up")
    await gate.releaseFirstRequest()
    await next.value

    try requireStep(workspace, "answer-currently-down")
    let commands = await machine.requestedPenCommands
    let profiles = await machine.requestedPenProfiles
    let raisedValues = zip(commands, profiles).compactMap { command, profile in
      command == .raise ? profile.raisedSpindleValue : nil
    }
    #expect(raisedValues == [55, 57])
    #expect(workspace.currentPenActuationProfile.raisedSpindleValue == 40)

    await workspace.performExerciseAction(.setPenSetpoint(.lower, 820), for: owner)
    try await waitUntilAsync {
      await machine.requestedPenProfiles.last?.loweredSpindleValue == 820
    }
    await workspace.shutdown()
  }

  @Test("Next accepts the observed value and records a refused slider outcome")
  func penInteractionNextHasNoControllerOutcomeGuard() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    await machine.enqueuePenOutcome(.refused(.controllerRejected("fixture refusal")))
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.beginPenInteraction()
    try await identifyPenCap(workspace)
    await workspace.performExerciseAction(.setPenSetpoint(.raise, 65), for: owner)
    try await waitUntilAsync { await machine.requestedPenProfiles.count == 1 }
    await workspace.answerCurrentQuestion(.yes)
    #expect(workspace.currentPenActuationProfile.raisedSpindleValue == 40)

    await workspace.answerCurrentQuestion(.yes)
    await workspace.answerCurrentQuestion(.yes)
    let evidence = try #require(workspace.currentPenInteractionAggregate?.value)
    #expect(
      evidence.confirmedUpControllerOutcomes.first
        == .refused(.controllerRejected("fixture refusal"))
    )
    #expect(evidence.confirmedUpSpindleValues.first == 65)
    #expect(workspace.currentPenActuationProfile.raisedSpindleValue == 65)
    await workspace.shutdown()
  }

  @Test("manual direction controls draw a closed square while Pen Down")
  func manualPenDownSquare() async throws {
    let log = EventLog()
    let telemetry = WorkflowTelemetryFixture()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let workspace = workspace(machine: machine, workflowTelemetry: telemetry, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.requestPenActuation(.lower)

    #expect(workspace.motionUnavailableReason == nil)
    #expect(workspace.manualMotionModeText == "drawing — commanded Pen Down")

    workspace.xStepText = "2"
    workspace.yStepText = "2"
    await workspace.requestJog(.xPositive)
    await workspace.requestJog(.yPositive)
    await workspace.requestJog(.xNegative)
    await workspace.requestJog(.yNegative)

    let strokes = await machine.requestedDrawingStrokes
    #expect(strokes.count == 4)
    #expect(strokes.map(\.delta.dx) == [2, 0, -2, 0])
    #expect(strokes.map(\.delta.dy) == [0, 2, 0, -2])
    #expect(workspace.machinePositionText == "X 0.000   Y 0.000")
    #expect(workspace.penStateText.contains("commanded down"))
    #expect(workspace.lastMotionOutcomeText == "drawing completed at X 0.000 Y 0.000")
    let events = await telemetry.events
    #expect(events.count == 8)
    #expect(events.allSatisfy { $0.operation == .manualDrawingStroke })
    #expect(events.filter { $0.phase == .completed }.count == 4)
    await workspace.shutdown()
  }

  @Test("manual Pen Down Stop remains capability-bound and raises once after cancellation")
  func manualPenDownStop() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.requestPenActuation(.lower)

    let owner = Task { await workspace.requestJog(.xPositive) }
    try await waitUntil {
      workspace.manualMotionPresentation.stopAction?.title == "Stop Manual Drawing"
    }
    let capabilityID = try #require(
      workspace.manualMotionPresentation.stopAction?.capabilityID
    )
    await workspace.stopManualMotion(capabilityID: capabilityID)
    _ = await owner.value

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorInterruption])
    #expect(workspace.penStateText.contains("commanded up"))
    #expect(workspace.manualMotionPresentation.stopAction == nil)
    await workspace.shutdown()
  }

  @Test("Learning can be turned off without changing machine authorization or learned evidence")
  func learningOffPreservesDirectAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    let revisions = workspace.learningArtifactGraph.revisions

    workspace.toggleLearningMode()

    #expect(!workspace.learningIsEnabled)
    #expect(workspace.learningModeActionTitle == "Turn Learning On")
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(workspace.motionUnavailableReason == nil)
    #expect(workspace.learningArtifactGraph.revisions == revisions)
    await workspace.performExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    #expect(workspace.activeExerciseAttemptOwnerID == nil)

    await workspace.requestJog(.xPositive)
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    #expect(workspace.machinePositionText == "X 50.000   Y 0.000")

    workspace.toggleLearningMode()
    #expect(workspace.learningIsEnabled)

    await workspace.startCamera()

    await workspace.performExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    #expect(workspace.activeExerciseAttemptOwnerID != nil)
    #expect(workspace.learningModeChangeUnavailableReason != nil)
    workspace.toggleLearningMode()
    #expect(workspace.learningIsEnabled)
    await workspace.shutdown()
  }

  @Test("production camera settling accepts bounded wobble without changing MPos authority")
  func fixedCameraSettlingPolicyIsOpticalOnly() {
    #expect(FixedCameraOpticalSettlingPolicy.alignmentSearchRadiusPixels == 3)
    #expect(FixedCameraOpticalSettlingPolicy.maximumAlignmentShiftPixels == 2)
    #expect(FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount == 3)
    #expect(FixedCameraOpticalSettlingPolicy.maximumCentroidSpreadPixels == 2)
    #expect(ControllerPositionAcceptancePolicy.toleranceMM == 0.05)
  }

  @Test("cap settlement accepts bounded wobble and retains the newest exact frame")
  func capSettlementAcceptsNewestStableExactFrame() async throws {
    let log = EventLog()
    let camera = try CameraFixture(capCentroidXOffsets: [0, 1, 2])
    let workspace = workspace(machine: try MachineFixture(log: log), camera: camera, log: log)
    await workspace.startCamera()

    let accepted = try await workspace.captureStableWorkflowCap(newerThan: 50)
    #expect(accepted.inspection.displayedFrame.frame.captureNanoseconds == 53)
    #expect(accepted.inspection.displayedFrame.frame.id == FrameID(rawValue: "fresh-53"))
    #expect(accepted.cap.centroid.x == 101)
    #expect(camera.recordedWorkflowFeatureRequests == [[.penCap], [.penCap], [.penCap]])
    #expect(camera.recordedWorkflowAnalysisRegionRequests.allSatisfy { $0 == nil })
    await workspace.shutdown()
  }

  @Test("cap settlement refuses unstable multi-frame centroid evidence")
  func capSettlementRefusesUnstableCentroids() async throws {
    let log = EventLog()
    let camera = try CameraFixture(capCentroidXOffsets: [0, 3, 1])
    let workspace = workspace(machine: try MachineFixture(log: log), camera: camera, log: log)
    await workspace.startCamera()

    do {
      _ = try await workspace.captureStableWorkflowCap(newerThan: 50)
      Issue.record("unstable centroid evidence was accepted")
    } catch {
      #expect(error.localizedDescription.contains("3.00 px spread exceeds 2.00 px"))
    }
    await workspace.shutdown()
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
    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS])
    #expect(camera.recordedAutomaticFeatureRequests == [[.penCap, .armatureEnvelope]])
    #expect(workspace.actionSurfacePresentation.overlays.count == 1)

    for overlay in UserSceneOverlay.allCases {
      workspace.setOverlay(overlay, enabled: false)
    }
    try await waitUntil { camera.recordedAutomaticInspectionRequests.last == .some(nil) }
    #expect(workspace.overlayPreferenceState.enabled.isEmpty)
    #expect(camera.recordedAutomaticFeatureRequests.last == [])
    #expect(workspace.actionSurfacePresentation.overlays.isEmpty)
    await workspace.shutdown()
  }

  @Test("workspace cadence and ROI intents reconcile the shared preference and backend")
  func workspaceOwnsCadenceAndAnalysisRegionEffects() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.startCamera()
    let displayedFrame = try #require(workspace.actionSurfacePresentation.displayedFrame)
    let viewport = try #require(workspace.actionSurfacePresentation.viewportContext)
    workspace.videoPresentationPreferences.synchronize(with: viewport)
    workspace.videoPresentationPreferences.setZoom(1)
    let captured = try #require(
      workspace.videoPresentationPreferences.visibleRect(
        frameWidth: displayedFrame.frame.width,
        frameHeight: displayedFrame.frame.height
      )
    )

    await workspace.lockVideoAnalysisToCurrentView(for: displayedFrame)
    await workspace.setVisionAnalysisCadence(.fiveFPS)

    #expect(workspace.videoAnalysisRegionLock?.region == captured)
    #expect(camera.recordedSceneAnalysisRegionRequests.last! == captured)
    #expect(workspace.visionAnalysisCadence == .fiveFPS)
    #expect(camera.recordedAutomaticInspectionRequests.last == .fiveFPS)

    await workspace.unlockVideoAnalysisView(for: displayedFrame)
    #expect(workspace.videoAnalysisRegionLock == nil)
    #expect(camera.recordedSceneAnalysisRegionRequests.last! == nil)
    await workspace.shutdown()
  }

  @Test("persisted pen-cap appearance configures the camera Vision owner")
  func persistedPenCapAppearanceConfiguresVision() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let magenta = PenCapColor(red: 190, green: 30, blue: 170)
    let selection = testPenCapAppearanceSelection(color: magenta)
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { selection },
      log: log
    )

    await workspace.startCamera()

    #expect(workspace.penCapAppearanceSelection == selection)
    #expect(camera.recordedPenCapColorRequests.last == magenta)
    await workspace.shutdown()
  }

  @Test("failed source switch preserves simulated view lock and Learning authority")
  func failedFrameModeSwitchPreservesCommittedState() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()
    await workspace.activateMotionGuard()
    try await completePenInteraction(workspace)
    let beforeFrame = try #require(workspace.actionSurfacePresentation.displayedFrame)
    let viewport = try #require(workspace.actionSurfacePresentation.viewportContext)
    workspace.videoPresentationPreferences.synchronize(with: viewport)
    workspace.videoPresentationPreferences.setZoom(1)
    await workspace.lockVideoAnalysisToCurrentView(for: beforeFrame)
    let beforeLock = try #require(workspace.videoAnalysisRegionLock)
    let beforeGraph = Set(workspace.learningArtifactGraph.revisions)

    let failure = CameraCaptureError.captureFailed("injected source-switch failure")
    camera.setNextStartResponse(
      CameraCaptureSnapshot(
        devices: camera.snapshot.devices,
        selectedDeviceID: camera.snapshot.selectedDeviceID,
        state: .failed(failure),
        latestFrame: nil,
        error: failure
      )
    )
    await workspace.switchFrameMode(.live)

    #expect(workspace.frameMode == .simulated)
    #expect(workspace.displayedFrame == beforeFrame)
    #expect(workspace.frozenPointSelectionFrame == nil)
    #expect(workspace.actionSurfacePresentation.displayedFrame == beforeFrame)
    #expect(workspace.videoAnalysisRegionLock == beforeLock)
    #expect(Set(workspace.learningArtifactGraph.revisions) == beforeGraph)
    #expect(workspace.cameraError?.contains("injected source-switch failure") == true)
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
    async let first: Void = workspace.stopManualMotion(capabilityID: capabilityID)
    async let repeated: Void = workspace.stopManualMotion(capabilityID: capabilityID)
    _ = await (first, repeated)
    _ = await owner.value

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorInterruption])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)

    let secondOwner = Task { await workspace.requestRelativeJog(request) }
    try await waitUntil { workspace.manualMotionPresentation.stopAction != nil }
    let secondCapabilityID = try #require(
      workspace.manualMotionPresentation.stopAction?.capabilityID
    )
    #expect(secondCapabilityID != capabilityID)
    await workspace.stopManualMotion(capabilityID: capabilityID)
    #expect(await machine.cancelCount == 1)
    #expect(workspace.manualMotionPresentation.stopAction?.capabilityID == secondCapabilityID)
    await workspace.stopManualMotion(capabilityID: secondCapabilityID)
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
    #expect(liveActions.filter { if case .stopAndAcceptBoundary = $0.kind { true } else { false } }.count == 1)
    #expect(liveActions.filter { if case .stop = $0.kind { true } else { false } }.count == 1)
    #expect(liveActions.filter { if case .cancel = $0.kind { true } else { false } }.count == 1)
    #expect(!liveActions.contains(where: { if case .choice = $0.kind { true } else { false } }))
    let stopKind = try #require(
      liveActions.first(where: {
        if case .stopAndAcceptBoundary = $0.kind { true } else { false }
      })?.kind)
    async let first: Void = workspace.performExerciseAction(stopKind, for: owner)
    async let repeated: Void = workspace.performExerciseAction(stopKind, for: owner)
    _ = await (first, repeated)

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorInterruption])
    #expect(await machine.requestedFeeds.last == 900)
    #expect(workspace.discoveryTransactions[.boundaryPositiveX]?.state == .succeeded)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    #expect(workspace.boundarySideAggregates[.positiveX]?.validSampleCount == 1)
    #expect(workspace.boundaryAttemptEvidenceByAttemptID.count == 1)
    #expect(camera.inspectionCallCount == inspectionsBeforeBoundary)
    #expect(camera.recordedAutomaticInspectionRequests == automaticBeforeBoundary)
    #expect(workspace.humanGuidedDiscoveryCurrentStep == .pairedBoundaryDiscoveryAndCentering)
    #expect(workspace.lastContextualStopAuditRecord?.actor == "Operator")
    #expect(workspace.lastContextualStopAuditRecord?.action == "Stop & Accept")
    #expect(workspace.lastContextualStopAuditRecord?.boundaryIntent == .stopAndAccept)
    #expect(workspace.lastContextualStopAuditRecord?.mechanicalCancelIntent == .operatorInterruption)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    let events = await log.values
    #expect(
      events.firstIndex(of: "announce:Moving the plotter toward the positive X boundary.")!
        < events.firstIndex(of: "machine:boundary")!)
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
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    for (index, direction) in directions.enumerated() {
      let samplePosition: (x: Double, y: Double) = switch direction {
      case .positiveX: (10, 0)
      case .negativeX: (-10, 0)
      case .negativeY: (0, -10)
      case .positiveY: (0, 10)
      }
      try await machine.setPosition(x: samplePosition.x, y: samplePosition.y)
      #expect(workspace.discoveryStartUnavailableReason(for: sequenceIDForTest(direction)) == nil)
      await workspace.beginPairedBoundarySide(direction)
      do {
        try await waitUntil { workspace.contextualStopPresentation != nil }
      } catch {
        let admission =
          workspace.discoveryStartUnavailableReason(for: sequenceIDForTest(direction))
          ?? "no current admission blocker"
        let discovery = workspace.discoveryError ?? "none"
        Issue.record(
          "\(direction) did not expose Stop: \(admission); discovery error: \(discovery)"
        )
        throw error
      }
      let capability = try #require(workspace.contextualStopPresentation?.capabilityID)
      await workspace.performExerciseAction(.stopAndAcceptBoundary(capability), for: owner)
      do {
        try await waitUntil { workspace.relevantBoundaryObservationCount == index + 1 }
      } catch {
        let transaction = String(
          describing: workspace.discoveryTransactions[sequenceIDForTest(direction)]?.state
        )
        let discovery = workspace.discoveryError ?? "none"
        Issue.record(
          "\(direction) did not commit sample \(index + 1): transaction=\(transaction); discovery error: \(discovery)"
        )
        throw error
      }
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
    let checkpointBox = LearningAuthorityManifestBox()
    let checkpointActions = checkpointBox.actions
    let first = workspace(
      machine: machine,
      camera: try CameraFixture(),
      manifestActions: checkpointActions,
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
      manifestActions: checkpointActions,
      log: log
    )
    #expect(relaunched.boundarySideAggregates.isEmpty)
    #expect(checkpointBox.checkpoint == saved)
    #expect(
      BoundaryDirection.allCases.allSatisfy {
        relaunched.learningArtifactGraph.currentRevision(for: .boundarySideAggregate($0)) == nil
      }
    )
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
    #expect(relaunched.learningAuthorityError == nil)
    #expect(
      BoundaryDirection.allCases.allSatisfy {
        relaunched.learningArtifactGraph.currentRevision(for: .boundarySideAggregate($0)) != nil
      }
    )
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

  @Test("live Boundary Stop settles once without accepting evidence and remains restartable")
  func liveBoundaryStopPreservesStoppedDisposition() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log, holdCancellationSettlement: true)
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    await workspace.performExerciseAction(.start, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let stopKind = try #require(
      workspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind
    )

    let stopTask = Task { @MainActor in
      await workspace.performExerciseAction(stopKind, for: owner)
    }
    try await waitUntilAsync { await machine.cancelCount == 1 }

    #expect(await machine.cancelIntents == [.operatorInterruption])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundaryAttemptEvidenceByAttemptID.isEmpty)
    #expect(workspace.boundarySideAggregates[.positiveX] == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(
        for: .boundarySideAggregate(.positiveX)
      ) == nil
    )
    #expect(workspace.lastContextualStopAuditRecord?.boundaryIntent == .stop)

    await machine.settleHeldCancellation()
    await stopTask.value

    #expect(await machine.cancelCount == 1)
    #expect(
      workspace.boundaryAttemptHistories[.positiveX]?.values.first?.attempts.last?
        .disposition == .stopped
    )
    #expect(workspace.boundaryActivityRecords.last?.disposition == .stopped)
    #expect(workspace.boundaryActivityRecords.last?.disposition != .cancelled)
    #expect(workspace.restartableExerciseItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundaryAttemptEvidenceByAttemptID.isEmpty)
    #expect(workspace.boundarySideAggregates[.positiveX] == nil)
    await workspace.shutdown()
  }

  @Test("simulated Boundary Stop has stopped provenance and accepts no simulated sample")
  func simulatedBoundaryStopPreservesStoppedDisposition() async throws {
    let harness = makeSimulatedHarness(
      simulatedExecutionPacing: SimulatedLearningInteractivePacing(
        stepDelay: .milliseconds(100)
      )
    )
    let workspace = harness.workspace
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()
    await workspace.activateMotionGuard()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    await workspace.performExerciseAction(.start, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let stopKind = try #require(
      workspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind
    )
    await workspace.performExerciseAction(stopKind, for: owner)
    try await waitUntil { workspace.activeExerciseAttemptID == nil }

    #expect(workspace.lastContextualStopAuditRecord?.boundaryIntent == .stop)
    #expect(
      workspace.lastContextualStopAuditRecord?.mechanicalCancelIntent == .operatorInterruption
    )
    #expect(
      workspace.boundaryAttemptHistories[.positiveX]?.values.first?.attempts.last?
        .disposition == .stopped
    )
    #expect(workspace.boundaryActivityRecords.last?.disposition == .stopped)
    #expect(workspace.restartableExerciseItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.boundaryAttemptEvidenceByAttemptID.isEmpty)
    #expect(workspace.boundarySideAggregates[.positiveX] == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(
        for: .boundarySideAggregate(.positiveX)
      ) == nil
    )
    #expect((await harness.runtime.snapshot()).currentOperation == nil)
    #expect(await harness.machineActionLog.values == [])
    await workspace.shutdown()
  }

  @Test("racing Boundary termination controls retain the first semantic disposition")
  func boundaryTerminationRaceRetainsFirstWinner() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log, holdCancellationSettlement: true)
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)

    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    await workspace.performExerciseAction(.start, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let actions = try #require(workspace.currentExerciseActionStripPresentation).actions
    let stopAndAccept = try #require(
      actions.first(where: {
        if case .stopAndAcceptBoundary = $0.kind { true } else { false }
      })?.kind
    )
    let stop = try #require(
      actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind
    )
    let cancel = try #require(
      actions.first(where: {
        if case .cancel = $0.kind { true } else { false }
      })?.kind
    )

    let first = Task { @MainActor in
      await workspace.performExerciseAction(stopAndAccept, for: owner)
    }
    let second = Task { @MainActor in
      await workspace.performExerciseAction(stop, for: owner)
    }
    let third = Task { @MainActor in
      await workspace.performExerciseAction(cancel, for: owner)
    }
    try await waitUntilAsync { await machine.cancelCount == 1 }
    let firstWinner = try #require(workspace.lastContextualStopAuditRecord?.boundaryIntent)

    await machine.settleHeldCancellation()
    _ = await (first.value, second.value, third.value)

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorInterruption])
    #expect(workspace.lastContextualStopAuditRecord?.boundaryIntent == firstWinner)
    let attemptDisposition = workspace.boundaryAttemptHistories[.positiveX]?
      .values.first?.attempts.last?.disposition
    switch firstWinner {
    case .stopAndAccept:
      #expect(attemptDisposition == .succeeded)
      #expect(workspace.boundaryActivityRecords.last?.disposition == .succeeded)
      #expect(workspace.relevantBoundaryObservationCount == 1)
      #expect(workspace.boundarySideAggregates[.positiveX]?.validSampleCount == 1)
      #expect(workspace.restartableExerciseItemID == nil)
    case .stop:
      #expect(attemptDisposition == .stopped)
      #expect(workspace.boundaryActivityRecords.last?.disposition == .stopped)
      #expect(workspace.relevantBoundaryObservationCount == 0)
      #expect(workspace.boundarySideAggregates[.positiveX] == nil)
      #expect(workspace.restartableExerciseItemID == owner)
    case .cancelAttempt:
      #expect(attemptDisposition == .cancelled)
      #expect(workspace.boundaryActivityRecords.last?.disposition == .cancelled)
      #expect(workspace.relevantBoundaryObservationCount == 0)
      #expect(workspace.boundarySideAggregates[.positiveX] == nil)
      #expect(workspace.restartableExerciseItemID == nil)
    }
    await workspace.shutdown()
  }

  @Test("active Boundary Cancel is capability-bound and accepts no sample")
  func activeBoundaryCancel() async throws {
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
    let cancelKind = try #require(
      stopWorkspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .cancel = $0.kind { true } else { false }
      })?.kind
    )
    let stopTask = Task { await stopWorkspace.performExerciseAction(cancelKind, for: owner) }
    try await waitUntilAsync { await stopMachine.cancelCount == 1 }
    await stopMachine.settleHeldCancellation()
    await stopTask.value
    #expect(await stopMachine.cancelIntents == [.operatorInterruption])
    #expect(stopWorkspace.relevantBoundaryObservationCount == 0)
    #expect(stopWorkspace.boundaryAttemptEvidenceByAttemptID.isEmpty)
    #expect(stopWorkspace.boundarySideAggregates[.positiveX] == nil)
    #expect(
      stopWorkspace.boundaryAttemptHistories[.positiveX]?.values.first?.attempts.last?
        .disposition == .cancelled
    )
    #expect(stopWorkspace.boundaryActivityRecords.last?.disposition == .cancelled)
    #expect(stopWorkspace.lastContextualStopAuditRecord?.boundaryIntent == .cancelAttempt)
    #expect(stopWorkspace.restartableExerciseItemID == nil)
    #expect(stopWorkspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.start])
    await stopWorkspace.shutdown()
  }

}

private actor AlarmClearWorkspaceFixture {
  enum Phase {
    case selected
    case alarmed
    case unlocked
    case ready
  }

  nonisolated let descriptor = MachineLinkDescriptor(
    identifier: "alarm-fixture",
    displayName: "Alarm Fixture",
    bsdPath: nil,
    transport: .simulated
  )
  private(set) var actions: [String] = []
  private let alarmPins: String
  private var phase: Phase = .selected
  private var lastProbe: PassiveProbeResult?
  private var lastClearOutcome: ControllerAlarmClearOutcome?

  init(alarmPins: String = "") {
    self.alarmPins = alarmPins
  }

  func select() -> RunInterpreterSnapshot {
    actions.append("select")
    phase = .selected
    return snapshot()
  }

  func requestPassiveProbe() -> PassiveProbeResult {
    switch phase {
    case .selected, .alarmed:
      actions.append("probe:alarm")
      phase = .alarmed
      let blocker = MachineBlocker.controllerAlarm("ALARM:1")
      let pinField = alarmPins.isEmpty ? "" : "|Pn:\(alarmPins)"
      let result = PassiveProbeResult(
        link: descriptor,
        startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
        completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
        exchanges: [
          PassiveProbeExchange(
            query: .status,
            commandID: UUID(),
            rawIO: [],
            lines: [
              GRBLParser.parseLine(
                Data("<Alarm|MPos:0.000,0.000,0.000\(pinField)>".utf8)
              )
            ],
            completed: false,
            blocker: blocker
          )
        ],
        blockers: [blocker]
      )
      lastProbe = result
      return result
    case .unlocked, .ready:
      actions.append("probe:ready")
      phase = .ready
      let result = PassiveProbeResult(
        link: descriptor,
        startedAt: RuntimeTimestamp(monotonicNanoseconds: 3),
        completedAt: RuntimeTimestamp(monotonicNanoseconds: 4),
        exchanges: [],
        blockers: []
      )
      lastProbe = result
      return result
    }
  }

  func requestAlarmClear() -> ControllerAlarmClearOutcome {
    guard phase == .alarmed else { return .refused(.noCurrentAlarmEvidence) }
    actions.append("clear-alarm")
    phase = .unlocked
    lastClearOutcome = .acknowledged
    return .acknowledged
  }

  func snapshot() -> RunInterpreterSnapshot {
    let isReady = phase == .ready
    let hasAlarmEvidence = phase == .alarmed || phase == .unlocked
    return RunInterpreterSnapshot(
      currentOperation: .idle,
      machine: MachineSnapshot(
        connection: phase == .selected || phase == .alarmed ? .disconnected : .connected,
        link: descriptor,
        lastProbe: lastProbe,
        blockers: hasAlarmEvidence ? [.controllerAlarm("ALARM:1")] : [],
        controllerState: isReady ? .idle : nil,
        position: isReady ? try! MachinePosition(x: 0, y: 0) : nil,
        motionGuardState: .inactive,
        lastAlarmClearOutcome: lastClearOutcome
      ),
      lastMotionOutcome: nil,
      lastProbe: lastProbe
    )
  }
}
