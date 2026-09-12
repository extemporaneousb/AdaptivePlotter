import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension PlotterApplicationRuntimeTests {
  @Test("failed Connect exposes the typed alarm and explicit Clear Alarm reprobes without enabling motion")
  func alarmClearUIStateAndAuthority() async throws {
    let fixture = AlarmClearWorkspaceFixture()
    let descriptor = fixture.descriptor
    let workspace = PlotterApplicationRuntime(
      machineSession: ClosurePlotterMachineSession(
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
      penInteractionRuntime: nominalPenInteractionRuntime(),
      boundaryRuntime: nominalBoundaryRuntime(),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
      residualEffectPort: ControllerBoundaryResidualEffectPort(devices: [descriptor]),
      serialDevices: [descriptor],
    )

    await submitControllerSession(workspace, .selectSerialDevice(controllerDevice(descriptor)))
    await submitControllerSession(workspace, .toggleConnection)

    #expect(!workspace.controllerSessionProjection.sessionEstablished)
    #expect(!workspace.controllerSessionProjection.motionAuthorized)
    #expect(workspace.controllerSessionProjection.controllerAlarmEvidenceText == "ALARM:1")
    #expect(workspace.controllerSessionProjection.controllerAttentionText == "Controller alarm: ALARM:1")
    let alarmUI = workspace.testPlotterUIProjection()
    #expect(alarmUI.manualMotion.controllerAlertText(
      alarmUI.controllerSession.controllerAttentionText) == "Controller alarm: ALARM:1")
    #expect(alarmUI.semantic.request(for: PlotterAppUIActionID.controllerClearAlarm) != nil)
    #expect(workspace.controllerSessionProjection.controllerLimitInputsText == "clear — sampled Pn has no X/Y/Z")
    #expect(
      workspace.controllerSessionProjection.controllerAlarmUnlockReadinessText == "armed — manual clear available"
    )
    #expect(workspace.controllerSessionProjection.alarmClearUnavailableReason == nil)
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
        == [.stage(.humanGuidedDiscovery), .stage(.borderValidations)]
    )
    #expect(await fixture.actions == ["select", "probe:alarm"])

    await submitControllerSession(workspace, .clearAlarm)

    #expect(await fixture.actions == ["select", "probe:alarm", "clear-alarm", "probe:ready"])
    #expect(workspace.controllerSessionProjection.controllerAlarmEvidenceText == nil)
    #expect(workspace.controllerSessionProjection.controllerAttentionText == nil)
    #expect(workspace.controllerSessionProjection.sessionEstablished)
    #expect(!workspace.controllerSessionProjection.motionAuthorized)
    #expect(workspace.controllerSessionProjection.motionAuthorizationUnavailableReason == nil)
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
    let workspace = PlotterApplicationRuntime(
      machineSession: ClosurePlotterMachineSession(
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
      penInteractionRuntime: nominalPenInteractionRuntime(),
      boundaryRuntime: nominalBoundaryRuntime(),
      drawingDraftRuntime: nominalDrawingDraftRuntime(),
      drawingRunComposition: nominalDrawingRunComposition(),
      incidentPackageUIService: nominalIncidentPackageUIService(),
      residualEffectPort: ControllerBoundaryResidualEffectPort(devices: [descriptor]),
      serialDevices: [descriptor],
    )

    await submitControllerSession(workspace, .selectSerialDevice(controllerDevice(descriptor)))
    await submitControllerSession(workspace, .toggleConnection)

    #expect(workspace.controllerSessionProjection.controllerLimitInputsText == "asserted — Pn:X")
    #expect(
      workspace.controllerSessionProjection.controllerAlarmUnlockReadinessText
        == "blocked — Pn:X is physically asserted"
    )
    #expect(
      workspace.controllerSessionProjection.alarmClearUnavailableReason
        == ControllerAlarmClearRefusal.axisLimitAsserted("X").actionableDescription
    )
    await submitControllerSession(workspace, .clearAlarm)
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
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    await machine.setPenState(.unknown)
    let workspace = plotterApplicationRuntime(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)

    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    await workspace.submitTestManualJog(.xPositive)

    #expect(workspace.controllerSessionProjection.machinePositionText == "X 50.000   Y 0.000")
    #expect(await machine.requestedFeeds == [500])
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    await workspace.shutdown()
  }

  @Test("manual direction controls draw a closed square while Pen Down")
  func manualPenDownSquare() async throws {
    let log = EventLog()
    let telemetry = WorkflowTelemetryFixture()
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let workspace = plotterApplicationRuntime(
      machine: machine,
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [machine.descriptor] },
        readNanoseconds: { 1 },
        recordTelemetry: { await telemetry.record($0) }
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
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
    #expect(workspace.controllerSessionProjection.machinePositionText == "X 0.000   Y 0.000")
    #expect(workspace.penStateText.contains("commanded down"))
    #expect(workspace.controllerSessionProjection.lastMotionOutcomeText == "drawing completed at X 0.000 Y 0.000")
    let events = await telemetry.events
    #expect(events.count == 8)
    #expect(events.allSatisfy { $0.operation == .manualDrawingStroke })
    #expect(events.filter { $0.phase == .completed }.count == 4)
    await workspace.shutdown()
  }

  @Test("manual Pen Down Stop remains capability-bound and raises once after cancellation")
  func manualPenDownStop() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let workspace = plotterApplicationRuntime(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
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
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let camera = try TestObservationCameraSession()
    let reconfigurationGate = TestConfigurationSuspension()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: resolvedObservationSession(
        camera,
        reconfigurationGate: reconfigurationGate
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    let revisions = workspace.learningArtifactGraph.revisions
    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { !workspace.testLearningIsEnabled }

    #expect(!workspace.testLearningIsEnabled)
    #expect(workspace.pointSelectionEpisodeProjection.currentReason == nil)
    #expect(workspace.learningAuthorityError == nil)
    #expect(workspace.testLearningModePresentation.actionTitle == "Turn Learning On")
    #expect(workspace.controllerSessionProjection.sessionEstablished)
    #expect(workspace.controllerSessionProjection.motionAuthorized)
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason == nil)
    #expect(workspace.learningArtifactGraph.revisions == revisions)
    let disabledOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let disabledActionID = learningActionID(.start, owner: disabledOwner)
    let disabledProjection = workspace.testPlotterUIProjection(
      selectedItemID: disabledOwner,
      includesLearningPath: true
    ).semantic
    #expect(disabledProjection.action(id: disabledActionID) == nil)
    #expect(disabledProjection.request(for: disabledActionID) == nil)
    #expect(workspace.activeExerciseAttemptOwnerID == nil)

    await workspace.submitTestManualJog(.xPositive)
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    #expect(workspace.controllerSessionProjection.machinePositionText == "X 50.000   Y 0.000")

    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { workspace.testLearningIsEnabled }
    #expect(workspace.testLearningIsEnabled)

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

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
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 1.0)
  }

  @Test("cap settlement accepts bounded wobble and retains the newest exact frame")
  func capSettlementAcceptsNewestStableExactFrame() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession(capCentroidXOffsets: [0, 1, 2])
    let workspace = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), camera: camera, log: log)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

    let accepted = try await workspace.captureStableWorkflowCap(newerThan: 50)
    #expect(accepted.inspection.displayedFrame.frame.captureNanoseconds == 53)
    #expect(accepted.inspection.displayedFrame.frame.id == FrameID(rawValue: "fresh-53"))
    #expect(accepted.cap.centroid.x == 101)
    #expect(camera.recordedWorkflowFeatureRequests == [[.penCap], [.penCap], [.penCap]])
    #expect(camera.recordedWorkflowAnalysisRegionRequests.allSatisfy { $0 == nil })
    await workspace.shutdown()
  }

  @Test("cap variation remains diagnostic and preserves the newest measured coordinates")
  func capSettlementRetainsObservedVariation() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession(capCentroidXOffsets: [0, 3, 1])
    let workspace = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), camera: camera, log: log)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

    let observed = try await workspace.captureStableWorkflowCap(newerThan: 50)
    #expect(observed.centroidSpreadPixels == 3)
    #expect(observed.cap.centroid.x == 100)
    #expect(observed.inspection.displayedFrame.frame.id == FrameID(rawValue: "fresh-53"))
    await workspace.shutdown()
  }

  @Test("cap settlement refuses a camera configuration change across exact frames")
  func capSettlementRefusesConfigurationChange() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession(rotatesConfiguration: true)
    let workspace = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), camera: camera, log: log)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

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
    let camera = try TestObservationCameraSession(corruptsMeasurementFrameHash: true)
    let workspace = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), camera: camera, log: log)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

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
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession(
      providesInspectionOverlay: true,
      providesAutomaticAnalysisResult: true
    )
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    #expect(workspace.exactWorkflowVisionOwner == nil)
    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(camera.recordedAutomaticInspectionRequests == [.twoFPS])
    #expect(camera.recordedAutomaticFeatureRequests == [[.penCap, .armatureEnvelope]])
    #expect(workspace.testActionSurfacePresentation.overlays.count == 1)

    for overlay in UserSceneOverlay.allCases {
      await submitObservationConfigurationForTest(workspace, .setOverlay(overlay, enabled: false))
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
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let displayedFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    let region = PixelRect(
      x: 0,
      y: 0,
      width: displayedFrame.frame.width,
      height: displayedFrame.frame.height
    )

    await submitObservationConfigurationForTest(workspace, .setRegion(region, displayedFrame: displayedFrame))
    await submitObservationConfigurationForTest(workspace, .setCadence(.fiveFPS))

    #expect(workspace.videoAnalysisRegionLock == nil)
    #expect(camera.recordedSceneAnalysisRegionRequests.contains { $0 == nil })
    #expect(camera.recordedAutomaticInspectionRequests.last == .fiveFPS)
    await workspace.shutdown()
  }

  @Test("persisted pen-cap appearance configures the camera Vision owner")
  func persistedPenCapAppearanceConfiguresVision() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let magenta = PenCapColor(red: 190, green: 30, blue: 170)
    let selection = testPenCapAppearanceSelection(color: magenta)
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { selection },
      log: log
    )

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

    #expect(workspace.penCapAppearanceSelection == selection)
    #expect(camera.recordedPenCapColorRequests.last == magenta)
    await workspace.shutdown()
  }

  @Test("manual contextual Stop sends one cancel and creates no boundary evidence")
  func manualStopHasNoBoundaryEvidence() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let workspace = plotterApplicationRuntime(machine: machine, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)

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
    #expect(workspace.controllerSessionProjection.sessionEstablished)
    #expect(workspace.controllerSessionProjection.motionAuthorized)
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
    #expect(workspace.testAcceptedBoundaryEvidence.isEmpty)
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
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0)
    )
    let workspace = plotterApplicationRuntime(
      machine: machine,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)

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
    "button and Voice Stop commit controller evidence without consulting Camera or Vision",
    arguments: [false, true])
  func boundaryStopCompletesTransaction(useVoice: Bool) async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(
      log: log,
      feedLimits: ControllerAxisFeedLimits(
        maximumXFeedMMPerMinute: 900,
        maximumYFeedMMPerMinute: 600
      )
    )
    let camera = try TestObservationCameraSession()
    let speechAnnouncer = ScriptedSpeechAnnouncer(log: log, outcomes: [.failed("test failure")])
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      speechAnnouncer: speechAnnouncer,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(
      workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(
      workspace,
      request: prerequisitePenRequest,
      point: try Point2(
        x: Double(prerequisitePenFrame.frame.width - 1) / 2,
        y: Double(prerequisitePenFrame.frame.height - 1) / 2
      )
    )
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 {
      await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner)
    }
    #expect(workspace.penInteractionCompleted)
    let inspectionsBeforeBoundary = camera.inspectionCallCount
    let automaticBeforeBoundary = camera.recordedAutomaticInspectionRequests

    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    #expect(workspace.testCurrentLearningPathItemID == owner)
    try await selectPublicDirection(
      .positiveX,
      owner: owner,
      workspace: workspace
    )
    let boundaryStart = try #require(
      workspace.currentExerciseActionStripPresentation?.actions.first(where: {
        $0.kind == .boundary(.acquire(direction: .positiveX, mode: .normal))
      })
    )
    #expect(boundaryStart.isEnabled)
    await workspace.performTestExerciseAction(boundaryStart.kind, for: owner)
    try await waitUntil {
      workspace.currentExerciseActionStripPresentation?.actions.contains(where: {
        if case .boundary(.stop(_)) = $0.kind { true } else { false }
      }) == true
    }
    let liveActions = try #require(workspace.currentExerciseActionStripPresentation).actions
    #expect(
      liveActions.filter { if case .boundary(.stop(_)) = $0.kind { true } else { false } }.count
        == 1
    )
    #expect(liveActions.filter { $0.kind == .cancel }.isEmpty)
    #expect(!liveActions.contains(where: { if case .choice = $0.kind { true } else { false } }))
    let stopKind = try #require(
      liveActions.first(where: {
        if case .boundary(.stop(_)) = $0.kind { true } else { false }
      })?.kind)
    try await waitUntilAsync { await machine.boundaryMotionIsAwaitingSettlement }
    let stopActionID = learningActionID(stopKind, owner: owner)
    let stopProjection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let stopRequest = try #require(stopProjection.request(for: stopActionID))
    if useVoice {
      let listener = TestVoiceListener()
      var settled = false
      let voice = WorkbenchVoiceController(speech: workspace.speechEffectRuntime, listener: listener) {
        let disposition = await workspace.submitPlotterUIRequest($0)
        settled = true
        return disposition
      }
      voice.update(WorkbenchVoiceContext(
        presentation: workspace.learningPathProjection(selectedItemID: owner).selectedAction,
        projection: stopProjection))
      voice.setEnabled(true)
      try await waitUntil { voice.isListening }
      listener.send(.transcript("Stop", isFinal: false))
      listener.send(.transcript("Stop", isFinal: true))
      try await waitUntil { settled }
      voice.stop()
    } else {
      async let first = workspace.submitPlotterUIRequest(stopRequest)
      async let repeated = workspace.submitPlotterUIRequest(stopRequest)
      _ = await (first, repeated)
    }

    #expect(await machine.cancelCount == 1)
    #expect(await machine.cancelIntents == [.operatorStop])
    #expect(await machine.requestedFeeds.last == 500)
    #expect(await machine.requestedBoundaryRequests.last?.segment.delta.magnitude == 50)
    #expect(await machine.requestedBoundaryRequests.last?.renewalBounds == .fixed(50))
    let terminal = try #require(workspace.testBoundaryTerminals.last)
    #expect(terminal.activity == .sideAcquisition)
    #expect(terminal.direction == .positiveX)
    #expect(terminal.disposition == .accepted)
    #expect(!terminal.physicalEvidenceClaimed)
    #expect(workspace.testAcceptedBoundaryEvidence.count == 1)
    #expect(workspace.testAcceptedBoundaryAggregates[.positiveX]?.validSampleCount == 1)
    #expect(workspace.testBoundaryEvidenceByAttemptID.count == 1)
    #expect(camera.inspectionCallCount == inspectionsBeforeBoundary)
    #expect(camera.recordedAutomaticInspectionRequests == automaticBeforeBoundary)
    #expect(workspace.humanGuidedDiscoveryCurrentStep == .pairedBoundaryDiscoveryAndCentering)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [
        .boundary(.acquire(direction: .negativeX, mode: .normal))
      ]
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
    let machine = try LowerMachineSessionFixture(log: log)
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = ArtifactResetCheckpointStoreFixture(
      checkpoint: try acceptedPenLearningTestCheckpoint(identity: identities.learningPathIdentity)
    )
    let checkpointActions = ControllerBoundaryStatePersistencePort(
      checkpointStore: checkpointBox
    )
    let workspace = plotterApplicationRuntime(
      machine: machine,
      statePersistencePort: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await workspace.performTestExerciseAction(
      .applySavedLearning,
      for: workspace.testCurrentLearningPathItemID
    )
    #expect(workspace.penInteractionCompleted)

    let directions: [BoundaryDirection] = [.positiveX, .negativeX, .negativeY, .positiveY]
    for (index, direction) in directions.enumerated() {
      #expect(workspace.discoveryStartUnavailableReason(for: sequenceIDForTest(direction)) == nil)
      try await submitRenderedBoundaryAcquisition(
        direction,
        owner: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
        workspace: workspace
      )
      _ = await machine.waitForBoundaryRequest(count: index + 1)
      switch direction {
      case .positiveX:
        try await machine.setPosition(x: 100, y: 0)
      case .negativeX:
        try await machine.setPosition(x: -100, y: 0)
      case .negativeY:
        try await machine.setPosition(x: 0, y: -50)
      case .positiveY:
        try await machine.setPosition(x: 0, y: 50)
      }
      try await submitRenderedBoundaryStop(
        owner: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
        workspace: workspace
      )
      try await waitUntil { workspace.testAcceptedBoundaryEvidence.count == index + 1 }
      #expect(
        workspace.testBoundaryTerminals.last?.direction == boundaryEpisodeDirection(direction)
      )
      #expect(workspace.testBoundaryTerminals.last?.disposition == .accepted)
      #expect(workspace.testAcceptedBoundaryAggregates[direction] != nil)
    }

    #expect(workspace.testPairedBoundaryProgress.isComplete)
    #expect(workspace.testAcceptedBoundaryAggregates.count == 4)
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
    "saved Learning restores accepted milestones with Unknown or Down pen without replaying cap clicks",
    arguments: [PenState.unknown, .down]
  )
  func acceptedBoundariesSurviveSoftwareRelaunchWithoutReplayingMotion(_ penState: PenState) async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpointBox = ArtifactResetCheckpointStoreFixture()
    let checkpointActions = ControllerBoundaryStatePersistencePort(
      checkpointStore: checkpointBox
    )
    let boundaryRuntimeAccess = TestBoundaryRuntimeAccess()
    let firstCamera = try TestObservationCameraSession()
    let first = plotterApplicationRuntime(
      machine: machine,
      camera: firstCamera,
      statePersistencePort: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
      boundaryRuntimeAccess: boundaryRuntimeAccess,
      log: log
    )
    await first.establishMachineSession(machine.descriptor)
    await submitControllerSession(first, .requestPassiveProbe)
    await submitObservationConfigurationForTest(
      first,
      .selectSource(.live, firstCamera.device.id)
    )
    #expect(
      first.cameraIsLive,
      "state=\(first.cameraStateText) source=\(String(describing: first.latestLiveCameraFrame?.source)) age=\(first.frameAgeText)"
    )
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await first.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(first.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(first.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(
      first,
      request: prerequisitePenRequest,
      point: try Point2(
        x: Double(prerequisitePenFrame.frame.width - 1) / 2,
        y: Double(prerequisitePenFrame.frame.height - 1) / 2
      )
    )
    try await waitUntil { first.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 {
      await first.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner)
    }
    #expect(first.penInteractionCompleted)
    let retained = try #require(checkpointBox.checkpoint)
    let acceptedMachine = try acceptedBoundaryTestCheckpoint(
      centerArrivalIsAccepted: false,
      controllerProbe: await machine.passiveProbeResult()
    )
    let accepted = try AcceptedLearningPathCheckpoint(
      semanticIdentity: retained.semanticIdentity,
      penInteraction: retained.penInteraction,
      machineArtifacts: acceptedMachine,
      penCapAppearance: retained.penCapAppearance,
      referenceFrame: retained.referenceFrame
    )
    checkpointBox.save(accepted)
    let boundaryRuntime = try #require(boundaryRuntimeAccess.runtime)
    try await boundaryRuntime.restore(acceptedMachine, environment: .live)
    first.installBoundarySnapshot(await boundaryRuntime.snapshot(for: .live))

    let saved = try #require(checkpointBox.checkpoint?.machineArtifacts)
    #expect(saved.boundarySideAggregates.count == 4)
    let cancelCountAtRelaunch = await machine.cancelCount
    let motionLogAtRelaunch = await log.values
    await machine.setPenState(penState)

    let relaunchedCamera = try TestObservationCameraSession()
    let relaunched = plotterApplicationRuntime(
      machine: machine,
      camera: relaunchedCamera,
      statePersistencePort: checkpointActions,
      tipCalibrationSemanticIdentities: identities,
      log: log
    )
    #expect(relaunched.testAcceptedBoundaryAggregates.isEmpty)
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
        == [.applySavedLearning, .startNewLearning]
    )
    await relaunched.performTestExerciseAction(.applySavedLearning, for: savedOwner)
    #expect(relaunched.penInteractionCompleted)
    #expect(relaunched.activeExerciseAttemptID == nil)
    #expect(relaunched.testActionSurfacePresentation.pointSelectionRequest == nil)
    #expect(relaunched.controllerPoseApplicability == .currentSession)
    #expect(relaunched.testAcceptedBoundaryAggregates == first.testAcceptedBoundaryAggregates)
    await relaunched.establishMachineSession(machine.descriptor)
    await submitControllerSession(relaunched, .requestPassiveProbe)
    await submitObservationConfigurationForTest(
      relaunched,
      .selectSource(.live, relaunchedCamera.device.id)
    )

    #expect(relaunched.testAcceptedBoundaryAggregates == first.testAcceptedBoundaryAggregates)
    #expect(relaunched.testEstimatedMachineCenter == first.testEstimatedMachineCenter)
    #expect(relaunched.testLearnedLocalCoordinateFrame == first.testLearnedLocalCoordinateFrame)
    #expect(relaunched.activeExerciseAttemptID == nil)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    #expect(
      !relaunched.testPlotterUIProjection(
        selectedItemID: boundaryOwner,
        includesLearningPath: true
      ).semantic.actions.contains {
        if case .boundary(.stop(_)) = $0.intent { return true }
        return false
      }
    )
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
    #expect(relaunched.controllerSessionProjection.motionAuthorized)
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
        == .boundary(.moveToEstimatedCenter(retry: false))
    )
    #expect(relaunched.testAcceptedBoundaryAggregates == first.testAcceptedBoundaryAggregates)
    await first.shutdown()
    await relaunched.shutdown()
  }

  @Test("active Boundary motion exposes only Stop and rejects a programmatic Cancel")
  func activeBoundaryHasOnlyStop() async throws {
    let stopLog = EventLog()
    let stopMachine = try LowerMachineSessionFixture(log: stopLog, holdCancellationSettlement: true)
    let stopCamera = try TestObservationCameraSession()
    let stopWorkspace = plotterApplicationRuntime(
      machine: stopMachine,
      camera: stopCamera,
      log: stopLog
    )
    await stopWorkspace.establishMachineSession(stopMachine.descriptor)
    await submitControllerSession(stopWorkspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(
      stopWorkspace,
      .selectSource(.live, stopCamera.device.id)
    )
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await stopWorkspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(
      stopWorkspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(
      stopWorkspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(
      stopWorkspace,
      request: prerequisitePenRequest,
      point: try Point2(
        x: Double(prerequisitePenFrame.frame.width - 1) / 2,
        y: Double(prerequisitePenFrame.frame.height - 1) / 2
      )
    )
    try await waitUntil { stopWorkspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 {
      await stopWorkspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner)
    }
    #expect(stopWorkspace.penInteractionCompleted)
    let owner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    try await selectPublicDirection(
      .positiveX,
      owner: owner,
      workspace: stopWorkspace
    )
    let boundaryStart = try #require(
      stopWorkspace.currentExerciseActionStripPresentation?.actions.first(where: {
        $0.kind == .boundary(.acquire(direction: .positiveX, mode: .normal))
      })
    )
    #expect(boundaryStart.isEnabled)
    await stopWorkspace.performTestExerciseAction(boundaryStart.kind, for: owner)
    try await waitUntil {
      stopWorkspace.currentExerciseActionStripPresentation?.actions.contains(where: {
        if case .boundary(.stop(_)) = $0.kind { true } else { false }
      }) == true
    }
    let stopKind = try #require(
      stopWorkspace.currentExerciseActionStripPresentation?.actions.first(where: {
        if case .boundary(.stop(_)) = $0.kind { true } else { false }
      })?.kind
    )
    let unavailableCancelID = learningActionID(.cancel, owner: owner)
    let activeProjection = stopWorkspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(activeProjection.action(id: unavailableCancelID) == nil)
    #expect(activeProjection.request(for: unavailableCancelID) == nil)
    #expect(await stopMachine.cancelIntents.isEmpty)
    #expect(stopWorkspace.testBoundaryTerminals.isEmpty)
    try await waitUntilAsync { await stopMachine.boundaryMotionIsAwaitingSettlement }
    let stopTask = Task { await stopWorkspace.performTestExerciseAction(stopKind, for: owner) }
    try await waitUntilAsync { await stopMachine.cancelCount == 1 }
    await stopMachine.settleHeldCancellation()
    await stopTask.value
    #expect(await stopMachine.cancelIntents == [.operatorStop])
    #expect(stopWorkspace.testAcceptedBoundaryEvidence.count == 1)
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

private struct ControllerBoundaryResidualEffectPort: PlotterApplicationResidualEffectPort {
  let discovery: PlotterFixedSerialDeviceDiscoveryAdapter

  init(devices: [MachineLinkDescriptor]) {
    discovery = PlotterFixedSerialDeviceDiscoveryAdapter(devices: devices)
  }

  func discoverSerialDevices() -> [MachineLinkDescriptor] {
    discovery.discoverSerialDevices()
  }
}

private struct ControllerBoundaryStatePersistencePort: PlotterApplicationStatePersistencePort {
  let checkpointStore: ArtifactResetCheckpointStoreFixture

  func loadAcceptedLearningPathCheckpoint() -> AcceptedLearningPathCheckpointLoadResult {
    checkpointStore.load()
  }

  func saveAcceptedLearningPathCheckpoint(
    _ checkpoint: AcceptedLearningPathCheckpoint
  ) throws {
    checkpointStore.save(checkpoint)
  }

  func clearAcceptedLearningPathCheckpoint() throws {
    checkpointStore.clear()
  }

  func persistPaperRevisionContext(_ context: PaperRevisionContext) throws {}
}
