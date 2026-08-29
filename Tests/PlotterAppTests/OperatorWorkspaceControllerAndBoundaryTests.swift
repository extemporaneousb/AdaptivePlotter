import EpisodeCore
import Foundation
import PlotterEpisodeModel
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
        deactivateMotionGuard: {},
        beginRelativeJog: { _ in .rejected(.refused(.notConnected)) },
        beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
        beginPenActuation: { _, _ in .rejected(.refused(.notConnected)) },
        beginBoundaryMotion: { request, _ in
          .rejected(
            .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
          )
        },
        requestJogCancel: { _ in .refused(.noActiveJog) },
        disconnect: {}
      ),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
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
    let penInteractionID = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let failedProjection = workspace.testLearningPathProjection(
      selectedItemID: penInteractionID
    )
    #expect(failedProjection.currentItemID == penInteractionID)
    #expect(failedProjection.items.map(\.id) == LearningPathItemID.navigationOrder)
    #expect(
      failedProjection.items.filter { !$0.id.isExercise }.map(\.id)
        == [.stage(.humanGuidedDiscovery), .stage(.observedDrawingTrials)]
    )
    let controllerStatus = try #require(
      failedProjection.selectedAction.subsystemStatuses.first(where: { $0.id == "controller" })
    )
    #expect(controllerStatus.detail == [PresentationFragment.text("Controller alarm: ALARM:1")])
    #expect(await fixture.actions == ["select", "probe:alarm"])

    await workspace.clearControllerAlarm()

    #expect(await fixture.actions == ["select", "probe:alarm", "clear-alarm", "probe:ready"])
    #expect(workspace.controllerAlarmEvidenceText == nil)
    #expect(workspace.controllerAttentionText == nil)
    #expect(workspace.controllerSessionEstablished)
    #expect(!workspace.motionAuthorizationEnabled)
    #expect(workspace.motionGuardActivationUnavailableReason == nil)
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason
      == "Enable Motion before requesting movement.")
    #expect(
      workspace.testManualMotionEpisodePresentation.penDownUnavailableReason
        == "Enable Motion before actuating the pen."
    )
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
        deactivateMotionGuard: {},
        beginRelativeJog: { _ in .rejected(.refused(.notConnected)) },
        beginDrawingStroke: { _ in .rejected(.refused(.notConnected)) },
        beginPenActuation: { _, _ in .rejected(.refused(.notConnected)) },
        beginBoundaryMotion: { request, _ in
          .rejected(
            .needsAttention(ownerID: request.ownerID, terminal: .refusal(.notConnected))
          )
        },
        requestJogCancel: { _ in .refused(.noActiveJog) },
        disconnect: {}
      ),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
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
  func manualMotionDefaults() {
    let manualDraft = ManualMotionDraft()

    #expect(manualDraft.xDistanceMM == "50")
    #expect(manualDraft.yDistanceMM == "50")
    #expect(manualDraft.feedMMPerMinute == "500")
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

    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    await workspace.submitTestManualJog(.xPositive)

    #expect(workspace.machinePositionText == "X 50.000   Y 0.000")
    #expect(await machine.requestedFeeds == [500])
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    await workspace.shutdown()
  }

  @Test("pen calibration sliders update current values and retain them in the attempt")
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
    #expect(strip.actions.map(\.title) == ["Confirm Pen Up", "Cancel Attempt"])

    await workspace.performTestExerciseAction(.setPenSetpoint(.raise, 55), for: owner)
    try await waitUntilAsync {
      await machine.requestedPenProfiles.last?.raisedSpindleValue == 55
    }
    await workspace.answerCurrentQuestion(.yes)

    try requireStep(workspace, "answer-currently-down")
    strip = try #require(workspace.selectedOperatorActionPresentation(for: owner).actionStrip)
    #expect(strip.penSetpointAdjustment?.command == .lower)
    #expect(strip.penSetpointAdjustment?.value == 760)
    #expect(strip.actions.map(\.title) == ["Confirm Pen Down", "Cancel Attempt"])

    await workspace.performTestExerciseAction(.setPenSetpoint(.lower, 805), for: owner)
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

  @Test("pen calibration coalesces drag values, confirmation waits, and Cancel drops an unaccepted value")
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
    await workspace.performTestExerciseAction(.setPenSetpoint(.raise, 55), for: owner)
    try await waitUntilAsync { await machine.requestedPenProfiles.count == 1 }
    await workspace.performTestExerciseAction(.setPenSetpoint(.raise, 56), for: owner)
    await workspace.performTestExerciseAction(.setPenSetpoint(.raise, 57), for: owner)

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
    #expect(workspace.currentPenActuationProfile.raisedSpindleValue == 57)

    await workspace.performTestExerciseAction(.setPenSetpoint(.lower, 820), for: owner)
    try await waitUntilAsync {
      await machine.requestedPenProfiles.last?.loweredSpindleValue == 820
    }
    await workspace.performTestExerciseAction(.cancel, for: owner)
    #expect(workspace.currentPenActuationProfile.loweredSpindleValue == 760)
    #expect(workspace.activeExerciseAttemptOwnerID == nil)
    await workspace.shutdown()
  }

  @Test("pen-position confirmation records a refused slider outcome")
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
    await workspace.performTestExerciseAction(.setPenSetpoint(.raise, 65), for: owner)
    try await waitUntilAsync { await machine.requestedPenProfiles.count == 1 }
    await workspace.answerCurrentQuestion(.yes)
    #expect(workspace.currentPenActuationProfile.raisedSpindleValue == 65)

    await workspace.answerCurrentQuestion(.yes)
    await workspace.answerCurrentQuestion(.yes)
    let evidence = try #require(workspace.currentPenInteractionAggregate?.value)
    #expect(
      evidence.confirmedUpControllerOutcomes.first
        == .refused(.controllerRejected("fixture refusal"))
    )
    #expect(evidence.confirmedUpSpindleValues.first == 65)
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
    await workspace.submitTestManualPen(.lower)

    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    #expect(workspace.testManualMotionEpisodePresentation.modeText
      == "drawing — commanded Pen Down")

    var manualDraft = ManualMotionDraft()
    manualDraft.xDistanceMM = "2"
    manualDraft.yDistanceMM = "2"
    await workspace.submitTestManualJog(.xPositive, manualDraft: manualDraft)
    await workspace.submitTestManualJog(.yPositive, manualDraft: manualDraft)
    await workspace.submitTestManualJog(.xNegative, manualDraft: manualDraft)
    await workspace.submitTestManualJog(.yNegative, manualDraft: manualDraft)

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
    await workspace.submitTestManualPen(.lower)

    let owner = Task { await workspace.submitTestManualJog(.xPositive) }
    try await waitUntil {
      workspace.testManualMotionEpisodePresentation.stopAction?.title == "Stop Manual Drawing"
    }
    let capabilityID = try #require(
      workspace.testManualMotionEpisodePresentation.stopAction?.capabilityID
    )
    await workspace.requestTestManualMotionStop(capabilityID: capabilityID)
    _ = await owner.value

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(workspace.penStateText.contains("commanded up"))
    #expect(workspace.testManualMotionEpisodePresentation.stopAction == nil)
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
    let reconfigurationGate = CameraReconfigurationGate()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(
        camera,
        reconfigurationGate: reconfigurationGate
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    let revisions = workspace.learningArtifactGraph.revisions
    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { !workspace.testLearningIsEnabled }

    #expect(!workspace.testLearningIsEnabled)
    #expect(workspace.pointSelectionEpisodeProjection.currentReason == nil)
    #expect(workspace.learningAuthorityError == nil)
    #expect(workspace.testLearningModePresentation.actionTitle == "Turn Learning On")
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    #expect(workspace.learningArtifactGraph.revisions == revisions)
    let disabledOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let disabledActionID = PlotterAppUIActionID.retainedLearning(.start, owner: disabledOwner)
    let disabledProjection = workspace.testPlotterUIProjection(
      selectedItemID: disabledOwner,
      includesLearningPath: true
    ).semantic
    #expect(disabledProjection.action(id: disabledActionID) == nil)
    #expect(disabledProjection.request(for: disabledActionID) == nil)
    #expect(workspace.activeExerciseAttemptOwnerID == nil)

    await workspace.submitTestManualJog(.xPositive)
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    #expect(workspace.machinePositionText == "X 50.000   Y 0.000")

    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { workspace.testLearningIsEnabled }
    #expect(workspace.testLearningIsEnabled)

    await workspace.startCamera()

    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    #expect(workspace.activeExerciseAttemptOwnerID != nil)
    let exactRequestID = try #require(
      workspace.pointSelectionEpisodeProjection.exactPointSelection.request?.id
    )
    let pointRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let displayedFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    await reconfigurationGate.arm()
    submitPointSelection(
      workspace,
      request: pointRequest,
      point: try Point2(
        x: Double(displayedFrame.frame.width - 1) / 2,
        y: Double(displayedFrame.frame.height - 1) / 2
      )
    )
    do {
      try await waitUntilAsync {
        let reconfigurationIsWaiting = await reconfigurationGate.isWaiting
        let exactSelection = workspace.pointSelectionEpisodeProjection.exactPointSelection
        return reconfigurationIsWaiting
          && exactSelection.phase == .continuing
          && exactSelection.continuationIsActive
      }
    } catch {
      await reconfigurationGate.release()
      throw error
    }
    #expect(workspace.penCapAppearanceSelection != nil)
    let activePresentation = workspace.testLearningModePresentation
    #expect(activePresentation.refusalRequirement == nil)
    #expect(activePresentation.refusalOwner == nil)
    #expect(activePresentation.remedy == nil)
    let disableLearning = Task {
      await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    }
    await Task.yield()
    await reconfigurationGate.release()
    _ = await disableLearning.value
    try await waitUntil {
      !workspace.testLearningIsEnabled && workspace.activeExerciseAttemptOwnerID == nil
    }
    #expect(!workspace.testLearningIsEnabled)
    #expect(workspace.pointSelectionEpisodeProjection.exactPointSelection.request == nil)
    #expect(!workspace.pointSelectionEpisodeProjection.exactPointSelection.continuationIsActive)
    #expect(workspace.activeExerciseAttemptOwnerID == nil)
    #expect(
      workspace.pointSelectionEpisodeProjection.exactPointSelection.request?.id != exactRequestID
    )
    #expect(!workspace.testLearningIsEnabled)
    #expect(workspace.activeDiscoverySequenceID == nil)
    await workspace.shutdown()
  }

  @Test("production camera settling accepts bounded wobble without changing MPos authority")
  func fixedCameraSettlingPolicyIsOpticalOnly() {
    #expect(FixedCameraOpticalSettlingPolicy.alignmentSearchRadiusPixels == 3)
    #expect(FixedCameraOpticalSettlingPolicy.maximumAlignmentShiftPixels == 2)
    #expect(FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount == 3)
    #expect(FixedCameraOpticalSettlingPolicy.maximumCentroidSpreadPixels == 2)
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 0.5)
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

  @Test("cap settlement refuses a camera configuration change across exact frames")
  func capSettlementRefusesConfigurationChange() async throws {
    let log = EventLog()
    let camera = try CameraFixture(rotatesConfiguration: true)
    let workspace = workspace(machine: try MachineFixture(log: log), camera: camera, log: log)
    await workspace.startCamera()

    do {
      _ = try await workspace.captureStableWorkflowCap(newerThan: 50)
      Issue.record("cross-configuration cap evidence was accepted")
    } catch {
      #expect(error.localizedDescription.contains("configuration changed"))
    }
    await workspace.shutdown()
  }

  @Test("cap settlement refuses measurement provenance from another exact frame")
  func capSettlementRefusesMismatchedExactFrameProvenance() async throws {
    let log = EventLog()
    let camera = try CameraFixture(corruptsMeasurementFrameHash: true)
    let workspace = workspace(machine: try MachineFixture(log: log), camera: camera, log: log)
    await workspace.startCamera()

    do {
      _ = try await workspace.captureStableWorkflowCap(newerThan: 50)
      Issue.record("mismatched exact-frame cap evidence was accepted")
    } catch {
      #expect(error.localizedDescription.contains("exact displayed frame"))
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
    #expect(workspace.exactWorkflowVisionOwner == nil)
    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS])
    #expect(camera.recordedAutomaticFeatureRequests == [[.penCap, .armatureEnvelope]])
    #expect(workspace.testActionSurfacePresentation.overlays.count == 1)

    for overlay in UserSceneOverlay.allCases {
      workspace.setOverlay(overlay, enabled: false)
    }
    try await waitUntil { camera.recordedAutomaticInspectionRequests.last == .some(nil) }
    #expect(workspace.overlayPreferenceState.enabled.isEmpty)
    #expect(camera.recordedAutomaticFeatureRequests.last == [])
    #expect(workspace.testActionSurfacePresentation.overlays.isEmpty)
    await workspace.shutdown()
  }

  @Test("full-frame viewport canonicalizes to unlocked default analysis")
  func fullFrameViewportCanonicalizesToDefaultAnalysis() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.startCamera()
    let displayedFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    let region = PixelRect(
      x: 0,
      y: 0,
      width: displayedFrame.frame.width,
      height: displayedFrame.frame.height
    )

    await workspace.setVideoAnalysisRegion(region, for: displayedFrame)
    await workspace.setVisionAnalysisCadence(.fiveFPS)

    #expect(workspace.videoAnalysisRegionLock == nil)
    #expect(camera.recordedSceneAnalysisRegionRequests.contains { $0 == nil })
    #expect(camera.recordedAutomaticInspectionRequests.last == .fiveFPS)
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
    let intent = try manualEpisodeJog(request)
    let owner = Task { await workspace.submitManualMotionIntent(intent) }
    try await waitUntil { workspace.testManualMotionEpisodePresentation.stopAction != nil }
    let capabilityID = try #require(
      workspace.testManualMotionEpisodePresentation.stopAction?.capabilityID
    )
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    if case .busy = workspace.motionRequestStatusPresentation {
      // Expected: authorization remains enabled while transient availability is busy.
    } else {
      Issue.record("Expected a busy motion-request projection while the manual jog owns motion.")
    }
    async let first: Void = workspace.requestTestManualMotionStop(capabilityID: capabilityID)
    async let repeated: Void = workspace.requestTestManualMotionStop(capabilityID: capabilityID)
    _ = await (first, repeated)
    _ = await owner.value

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)

    let secondOwner = Task { await workspace.submitManualMotionIntent(intent) }
    try await waitUntil { workspace.testManualMotionEpisodePresentation.stopAction != nil }
    let secondCapabilityID = try #require(
      workspace.testManualMotionEpisodePresentation.stopAction?.capabilityID
    )
    #expect(secondCapabilityID != capabilityID)
    await workspace.requestTestManualMotionStop(capabilityID: capabilityID)
    #expect(await machine.cancelCount == 1)
    #expect(workspace.testManualMotionEpisodePresentation.stopAction?.capabilityID
      == secondCapabilityID)
    await workspace.requestTestManualMotionStop(capabilityID: secondCapabilityID)
    _ = await secondOwner.value
    #expect(await machine.cancelCount == 2)
    await workspace.shutdown()
  }

  @Test("manual jog terminal projection preserves the typed operator intent")
  func manualJogTelemetryNamesOperationAndDistance() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let workspace = workspace(
      machine: machine,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    let request = RelativeJogRequest(
      delta: try Vector2(dx: -100, dy: 0),
      feedMMPerMinute: 500
    )
    let intent = try manualEpisodeJog(request)
    await workspace.submitManualMotionIntent(intent)
    guard case let .completed(context, _)? =
      workspace.manualMotionEpisodeSnapshot?.projection.lastTerminalEffect?.result
    else {
      Issue.record("Expected a completed typed manual-motion terminal result.")
      return
    }
    #expect(context.intent == .manualMotion(intent))
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
    #expect(workspace.testCurrentLearningPathItemID == owner)
    await workspace.performTestExerciseAction(.start, for: owner)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    let liveActions = try #require(workspace.currentExerciseActionStripPresentation).actions
    #expect(liveActions.filter { if case .stop = $0.kind { true } else { false } }.count == 1)
    #expect(liveActions.filter { $0.kind == .cancel }.isEmpty)
    #expect(!liveActions.contains(where: { if case .choice = $0.kind { true } else { false } }))
    let stopKind = try #require(
      liveActions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind)
    let stopActionID = PlotterAppUIActionID.retainedLearning(stopKind, owner: owner)
    let stopProjection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let stopRequest = try #require(stopProjection.request(for: stopActionID))
    async let first = workspace.submitPlotterUIRequest(stopRequest)
    async let repeated = workspace.submitPlotterUIRequest(stopRequest)
    _ = await (first, repeated)

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(await machine.requestedFeeds.last == 500)
    #expect(await machine.requestedBoundaryRequests.last?.segment.delta.magnitude == 50)
    #expect(await machine.requestedBoundaryRequests.last?.renewalBounds == .fixed(50))
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
        .contains("Drawing Boundary measurements do not use Camera or Vision") == true
    )
    let events = await log.values
    #expect(
      events.firstIndex(of: "announce:Moving the plotter toward the positive X drawing boundary.")!
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
    #expect(
      await machine.requestedBoundaryRequests.map(\.segment.delta.magnitude) == [50, 50, 50, 50]
    )
    #expect(
      await machine.requestedBoundaryRequests.map(\.segment.feedMMPerMinute)
        == [500, 500, 500, 500]
    )
    await workspace.shutdown()
  }

  @Test(
    "restored Learning pose does not gate manual Pen actuation"
  )
  func acceptedBoundariesSurviveSoftwareRelaunchWithoutReplayingMotion() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = LearningPathCheckpointBox()
    let checkpointActions = OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let first = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
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

    let saved = try #require(checkpointBox.checkpoint?.machineArtifacts)
    #expect(saved.boundarySideAggregates.count == 4)
    let cancelCountAtRelaunch = await machine.cancelCount
    let motionLogAtRelaunch = await log.values

    let relaunched = workspace(
      machine: machine,
      camera: try CameraFixture(),
      learningPathCheckpointActions: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
      log: log
    )
    #expect(relaunched.boundarySideAggregates.isEmpty)
    #expect(relaunched.learningArtifactGraph.revisions.isEmpty)
    #expect(relaunched.machineCameraRegistration == nil)
    #expect(relaunched.tipCameraRegistration == nil)
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    if case .awaitingOperatorDecision(sideCount: 4, hasTipCalibration: false) =
      relaunched.acceptedArtifactCheckpointStatus
    {
      // Expected: loading is presentation only.
    } else {
      Issue.record("Expected the loaded checkpoint to await the operator decision.")
    }
    let savedOwner = relaunched.testCurrentLearningPathItemID
    #expect(
      relaunched.currentExerciseActionStripPresentation?.actions.map(\.kind)
        == [.useSavedTraining, .startNewLearning]
    )
    await relaunched.performTestExerciseAction(.useSavedTraining, for: savedOwner)
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    #expect(relaunched.boundarySideAggregates == first.boundarySideAggregates)
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
    if case .appliedByOperator(sideCount: 4, hasTipCalibration: false) =
      relaunched.acceptedArtifactCheckpointStatus
    {
      // Expected: exact revisions were applied only by the explicit action.
    } else {
      Issue.record("Expected accepted boundaries to apply after the operator decision.")
    }
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    let restoredRevisions = relaunched.learningArtifactGraph.revisions
    #expect(relaunched.motionAuthorizationEnabled)
    #expect(relaunched.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    #expect(relaunched.testManualMotionEpisodePresentation.penDownUnavailableReason == nil)

    await relaunched.submitTestManualPen(.lower)
    #expect(await machine.requestedPenCommands.last == .lower)
    #expect(relaunched.learningArtifactGraph.revisions == restoredRevisions)

    await relaunched.submitTestManualPen(.raise)
    #expect(await machine.requestedPenCommands.last == .raise)
    #expect(relaunched.learningArtifactGraph.revisions == restoredRevisions)
    #expect(
      relaunched.testCurrentLearningPathItemID
        == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    )
    #expect(
      relaunched.learningArtifactGraph.currentRevision(for: .penInteraction)
        == first.learningArtifactGraph.currentRevision(for: .penInteraction)
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
    await stopWorkspace.performTestExerciseAction(.start, for: owner)
    try await waitUntil { stopWorkspace.contextualStopPresentation != nil }
    let stopKind = try #require(
      stopWorkspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .stop = $0.kind { true } else { false }
      })?.kind
    )
    let unavailableCancelID = PlotterAppUIActionID.retainedLearning(.cancel, owner: owner)
    let activeProjection = stopWorkspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(activeProjection.action(id: unavailableCancelID) == nil)
    #expect(activeProjection.request(for: unavailableCancelID) == nil)
    #expect(await stopMachine.cancelIntents.isEmpty)
    #expect(stopWorkspace.discoveryTransactions[.boundaryPositiveX]?.state == .active)
    let stopTask = Task { await stopWorkspace.performTestExerciseAction(stopKind, for: owner) }
    try await waitUntilAsync { await stopMachine.cancelCount == 1 }
    await stopMachine.settleHeldCancellation()
    await stopTask.value
    #expect(await stopMachine.cancelIntents == [.operatorStop])
    #expect(stopWorkspace.relevantBoundaryObservationCount == 1)
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
