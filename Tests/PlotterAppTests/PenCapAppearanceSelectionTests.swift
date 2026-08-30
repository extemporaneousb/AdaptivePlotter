import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Identify Pen Cap", .serialized)
@MainActor
struct PenCapAppearanceSelectionTests {
  @Test("bounded sampler learns a blue cap and persists exact-frame provenance")
  func blueCapSamplingAndPersistence() throws {
    let displayed = try colorFrame(red: 20, green: 80, blue: 220)
    let selection = try pointSelection(frame: displayed, x: 4, y: 4)

    let sample = try PlotterPenCapPointSampler.sample(frame: displayed, submission: selection)
    let learned = PenCapAppearanceSelection(sample: sample, frame: displayed)

    #expect(learned.color == PenCapColor(red: 20, green: 80, blue: 220))
    #expect(learned.matches(displayed))
    #expect(learned.clickPoint == selection.point)
    #expect(learned.usableSampleCount == 81)
    #expect(learned.totalSampleCount == 81)
    #expect(learned.algorithmRevision == "pen-cap-click-9x9-median-v1")

    let data = try JSONEncoder().encode(learned)
    #expect(try JSONDecoder().decode(PenCapAppearanceSelection.self, from: data) == learned)
  }

  @Test("white gray and dark patches are rejected with concrete sample counts")
  func achromaticAndDarkRejection() throws {
    for channels: (UInt8, UInt8, UInt8) in [(255, 255, 255), (128, 128, 128), (8, 4, 2)] {
      let displayed = try colorFrame(red: channels.0, green: channels.1, blue: channels.2)
      let selection = try pointSelection(frame: displayed, x: 4, y: 4)
      do {
        _ = try PlotterPenCapPointSampler.sample(frame: displayed, submission: selection)
        Issue.record("Expected an achromatic or dark patch to be rejected")
      } catch let error as PlotterPointSelectionSamplingError {
        #expect(error == .insufficientChromaticPixels(usable: 0, required: 9, total: 81))
        #expect(error.localizedDescription.contains("usable chromatic pixels"))
      }
    }
  }

  @Test("9 by 9 sampling clips safely at a frame edge")
  func edgeClipping() throws {
    let displayed = try colorFrame(red: 40, green: 90, blue: 210, width: 9, height: 9)
    let selection = try pointSelection(frame: displayed, x: 0, y: 0)

    let sample = try PlotterPenCapPointSampler.sample(frame: displayed, submission: selection)

    #expect(sample.usableSampleCount == 25)
    #expect(sample.totalSampleCount == 25)
  }

  @Test("unsupported gray bytes and stale exact-frame clicks are refused")
  func unsupportedAndStaleRejection() throws {
    let gray = try colorFrame(
      red: 80, green: 80, blue: 80, pixelFormat: .gray8, frameID: "gray")
    let graySelection = try pointSelection(frame: gray, x: 4, y: 4)
    #expect(throws: PlotterPointSelectionSamplingError.unsupportedPixelFormat(.gray8)) {
      try PlotterPenCapPointSampler.sample(frame: gray, submission: graySelection)
    }

    let current = try colorFrame(red: 20, green: 80, blue: 220, frameID: "current")
    let stale = try colorFrame(
      red: 20,
      green: 80,
      blue: 220,
      configurationID: current.frame.cameraConfigurationID,
      frameID: "stale")
    let staleSelection = try pointSelection(frame: stale, x: 4, y: 4)
    #expect(throws: PlotterPointSelectionSamplingError.staleExactFrame) {
      try PlotterPenCapPointSampler.sample(frame: current, submission: staleSelection)
    }
  }

  @Test("Exercise 1.1 cannot ask a question or actuate before an accepted cap click")
  func clickPrecedesSequenceAndMachineActions() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let persisted = PenCapSelectionBox()
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      persistPenCapAppearanceSelection: { persisted.value = $0 },
      log: log
    )
    await workspace.startCamera()
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await log.clear()

    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )

    let presentation = workspace.testActionSurfacePresentation
    let request = try #require(presentation.pointSelectionRequest)
    let frozenFrame = try #require(presentation.displayedFrame)
    #expect(request.purpose == .penCapAppearance)
    #expect(request.prompt == "Click the pen cap body—not the tip—on the current camera frame.")
    #expect(request.frame.frameID == frozenFrame.frame.id.rawValue)
    #expect(request.frame.frameSHA256 == frozenFrame.frame.contentSHA256)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)

    submitPointSelection(
      workspace,
      request: request,
      point: try Point2(x: 4, y: 4)
    )
    try await waitUntil {
      workspace.activeDiscoverySequenceID == .penInteraction
        || workspace.discoveryError != nil
    }
    try requireStep(workspace, "answer-initially-up")
    try await waitForExecutorTurns {
      camera.recordedPenCapColorRequests.last != nil
    }

    let learned = try #require(workspace.penCapAppearanceSelection)
    #expect(learned.matches(frozenFrame))
    #expect(workspace.penCapAppearanceSelection == learned)
    #expect(persisted.value == nil)
    #expect(camera.recordedPenCapColorRequests.last == learned.color)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)
    await workspace.shutdown()
  }

  @Test("cap identification survives external controller and Motion setup")
  func capIdentificationPrecedesControllerSetup() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log, motionGuardInitiallyActive: false)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let connectionBlocker =
      "Blocked by controller connection. Use Connect for the selected plotter in the workbench toolbar; Enable Motion depends on a connected session."
    let motionBlocker =
      "Blocked by Motion authorization. Use Enable Motion in the workbench toolbar for this connected session."

    await workspace.startCamera()

    let identifyAction = try #require(
      workspace.currentExerciseActionStripPresentation?.actions.first
    )
    #expect(identifyAction.title == "Identify Pen Cap")
    #expect(identifyAction.unavailableReason == nil)

    await workspace.performTestExerciseAction(.start, for: owner)
    let penRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let penFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: penRequest, point: try Point2(
      x: Double(penFrame.frame.width - 1) / 2,
      y: Double(penFrame.frame.height - 1) / 2
    ))
    try await waitUntil {
      workspace.activeDiscoverySequenceID == .penInteraction || workspace.discoveryError != nil
    }
    try requireStep(workspace, "answer-initially-up")

    let disconnectedStrip = try #require(workspace.currentExerciseActionStripPresentation)
    let disconnectedNext = try #require(
      disconnectedStrip.actions.first { $0.kind == .choice(.yes) }
    )
    let disconnectedAdjustment = try #require(disconnectedStrip.penSetpointAdjustment)
    #expect(disconnectedNext.title == "Confirm Pen Up")
    #expect(disconnectedNext.unavailableReason == connectionBlocker)
    #expect(disconnectedAdjustment.unavailableReason == connectionBlocker)
    #expect(disconnectedAdjustment.isEnabled == false)
    #expect(workspace.controllerSelectionUnavailableReason == nil)
    #expect(workspace.controllerConnectionActionUnavailableReason == "Select one serial device first.")

    let blockedSetpointID = PlotterAppUIActionID.penInteractionSetpoint(
      disconnectedAdjustment.command,
      value: disconnectedAdjustment.value + 1,
      owner: owner
    )
    let blockedProjection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let blockedSetpoint = try #require(blockedProjection.action(id: blockedSetpointID))
    #expect(!blockedSetpoint.isAvailable)
    #expect(blockedProjection.request(for: blockedSetpointID) == nil)
    #expect(await machine.requestedPenCommands.isEmpty)

    await workspace.selectSerialDevice(machine.descriptor)
    #expect(workspace.controllerConnectionActionUnavailableReason == nil)
    await workspace.performControllerConnectionAction()

    let connectedStrip = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(
      connectedStrip.actions.first { $0.kind == .choice(.yes) }?.unavailableReason
        == motionBlocker
    )
    #expect(connectedStrip.penSetpointAdjustment?.unavailableReason == motionBlocker)
    try requireStep(workspace, "answer-initially-up")

    await workspace.activateMotionGuard()

    let readyStrip = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(readyStrip.actions.first { $0.kind == .choice(.yes) }?.unavailableReason == nil)
    #expect(readyStrip.penSetpointAdjustment?.isEnabled == true)
    try requireStep(workspace, "answer-initially-up")
    await workspace.shutdown()
  }

  @Test("first Pen question does not wait for held or failing Vision reconfiguration")
  func firstQuestionPrecedesVisionReconfiguration() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture(
      automaticAnalysisError: "Injected automatic Vision reconfiguration failure."
    )
    let reconfigurationGate = CameraReconfigurationGate()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(
        camera,
        reconfigurationGate: reconfigurationGate
      ),
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    await reconfigurationGate.arm()

    let penRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let penFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: penRequest, point: try Point2(
      x: Double(penFrame.frame.width - 1) / 2,
      y: Double(penFrame.frame.height - 1) / 2
    ))
    try await waitUntil {
      workspace.activeDiscoverySequenceID == .penInteraction || workspace.discoveryError != nil
    }
    try requireStep(workspace, "answer-initially-up")

    try requireStep(workspace, "answer-initially-up")
    try await waitForExecutorTurnsAsync(
      conditionDescription: "held Pen-cap Vision reconfiguration"
    ) {
      await reconfigurationGate.isWaiting
    }
    #expect(
      workspace.selectedOperatorActionPresentation(
        for: .humanGuidedDiscovery(.penInteraction)
      ).question != nil
    )

    await reconfigurationGate.release()
    try await waitForExecutorTurns {
      workspace.visionError == "Injected automatic Vision reconfiguration failure."
    }
    try requireStep(workspace, "answer-initially-up")
    #expect(await machine.requestedPenCommands.isEmpty)
    await workspace.shutdown()
  }

  @Test("re-entering Exercise 1.1 retains exact scene overlays on its frozen frame")
  func learnedAppearanceProducesFrozenFrameOverlays() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture(providesInspectionOverlay: true)
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.startCamera()
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()

    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )

    let presentation = workspace.testActionSurfacePresentation
    let frozen = try #require(presentation.displayedFrame)
    let request = try #require(presentation.pointSelectionRequest)
    #expect(request.frame.frameID == frozen.frame.id.rawValue)
    #expect(request.frame.frameSHA256 == frozen.frame.contentSHA256)
    #expect(presentation.overlays.map(\.provenance.kind) == [.penCap])
    #expect(presentation.overlays.allSatisfy { $0.matches(frozen) })
    #expect(camera.inspectionCallCount >= 1)
    await workspace.shutdown()
  }

  @Test("stale click remains pending and performs no machine action")
  func staleClickRemainsPending() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    await workspace.startCamera()
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await log.clear()
    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let staleFrame = try colorFrame(red: 20, green: 80, blue: 220, frameID: "other-frame")
    let stale = PlotterPointSelectionSubmission(
      selectionID: request.id,
      frame: exactPointSelectionFrame(staleFrame),
      point: try Point2(x: 4, y: 4),
      presentationTransformRevision: request.presentationTransformRevision
    )

    workspace.submitPointSelection(stale)
    try await waitUntil { workspace.discoveryError != nil }

    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest == request)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(
      workspace.discoveryError?.contains(
        "Submit the point against the exact frozen frame currently presented."
      ) == true
    )
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)
    await workspace.shutdown()
  }

  @Test("LIVE overlay preference remains On while learned color is unavailable")
  func unlearnedLiveOverlayStatus() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )

    await workspace.startCamera()

    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(workspace.overlayStatus(for: .penCap).state == .unavailable)
    #expect(workspace.overlayStatus(for: .penCap).message.contains("use Identify Pen Cap"))
    #expect(camera.recordedPenCapColorRequests.isEmpty)
    await workspace.shutdown()
  }

  @Test("persisted SIMULATED appearance cannot authorize LIVE Vision or exact workflow")
  func persistedSimulatedAppearanceIsRefusedForLive() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let simulated = testPenCapAppearanceSelection(source: .simulated)
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { simulated },
      log: log
    )

    await workspace.startCamera()

    #expect(workspace.livePenCapAppearanceSelection == nil)
    #expect(workspace.simulatedPenCapAppearanceSelection == nil)
    guard case .refused(let reason) = workspace.persistedPenCapAppearanceLoadState else {
      Issue.record("Expected persisted SIMULATED appearance to be refused")
      await workspace.shutdown()
      return
    }
    #expect(reason.contains("source is SIMULATED"))
    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(workspace.overlayStatus(for: .penCap).state == .unavailable)
    #expect(workspace.overlayStatus(for: .penCap).message == reason)
    #expect(camera.recordedPenCapColorRequests.isEmpty)
    #expect(camera.recordedAutomaticCadences.isEmpty)
    do {
      _ = try await workspace.captureStableWorkflowCap(newerThan: 0)
      Issue.record("Expected LIVE exact-workflow Vision to require a LIVE appearance")
    } catch {
      #expect(String(describing: error).contains("Identify Pen Cap"))
    }
    #expect(camera.inspectionCallCount == 0)
    await workspace.shutdown()
  }

  @Test("SIMULATED identification has a separate owner and cannot erase LIVE appearance")
  func simulatedIdentificationDoesNotReplaceLiveAppearance() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let live = testPenCapAppearanceSelection(
      color: PenCapColor(red: 20, green: 80, blue: 220)
    )
    let persisted = PenCapSelectionBox()
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { live },
      persistPenCapAppearanceSelection: { persisted.value = $0 },
      log: log
    )

    await workspace.switchFrameMode(.simulated)
    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let displayed = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    let fallbackPoint = try Point2<CameraPixelSpace>(
      x: Double(displayed.frame.width - 1) / 2,
      y: Double(displayed.frame.height - 1) / 2
    )
    let point = workspace.testActionSurfacePresentation.overlays.compactMap {
      overlay -> Point2<CameraPixelSpace>? in
      guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
      else { return nil }
      return point
    }.first ?? fallbackPoint
    submitPointSelection(workspace, request: request, point: point)
    try await waitUntil { workspace.penCapAppearanceSelection != nil }

    let simulated = try #require(workspace.simulatedPenCapAppearanceSelection)
    #expect(simulated.source == .simulated)
    #expect(workspace.penCapAppearanceSelection == simulated)
    #expect(workspace.livePenCapAppearanceSelection == live)
    #expect(persisted.value == nil)
    #expect(camera.recordedPenCapColorRequests.isEmpty)
    await workspace.shutdown()
  }

  @Test("valid persisted LIVE appearance survives relaunch and camera configuration change")
  func persistedLiveAppearanceSurvivesCameraLifecycle() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let live = testPenCapAppearanceSelection(
      color: PenCapColor(red: 20, green: 80, blue: 220),
      cameraConfigurationID: CameraConfigurationID()
    )
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { live },
      log: log
    )

    await workspace.startCamera()
    #expect(workspace.livePenCapAppearanceSelection == live)
    #expect(camera.recordedPenCapColorRequests.last == live.color)

    await workspace.restartCamera()
    #expect(workspace.livePenCapAppearanceSelection == live)
    #expect(workspace.persistedPenCapAppearanceLoadState == .accepted)
    #expect(camera.recordedPenCapColorRequests.last == live.color)
    #expect(camera.recordedPenCapColorRequests.count >= 2)
    await workspace.shutdown()
  }

  @Test("invalid persisted LIVE appearance is ignored without changing overlay preference")
  func invalidPersistedLiveAppearanceIsRefused() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let invalid = testPenCapAppearanceSelection(color: PenCapColor(red: 4, green: 4, blue: 4))
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { invalid },
      log: log
    )

    await workspace.startCamera()

    #expect(workspace.livePenCapAppearanceSelection == nil)
    guard case .refused(let reason) = workspace.persistedPenCapAppearanceLoadState else {
      Issue.record("Expected invalid LIVE appearance to be refused")
      await workspace.shutdown()
      return
    }
    #expect(reason.contains("sample provenance is invalid"))
    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(workspace.overlayStatus(for: .penCap).message == reason)
    #expect(camera.recordedPenCapColorRequests.isEmpty)
    await workspace.shutdown()
  }

  @Test("accepted click then exact Pen Stop cannot revive Exercise 1.1")
  func acceptedClickImmediateCancelDoesNotRevive() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    await log.clear()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.performTestExerciseAction(.start, for: owner)
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let displayed = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(
      workspace,
      request: request,
      point: try Point2(
        x: Double(displayed.frame.width - 1) / 2,
        y: Double(displayed.frame.height - 1) / 2
      )
    )
    try await waitUntil { workspace.penCapAppearanceSelection != nil }
    let acceptedAppearance = try #require(workspace.penCapAppearanceSelection)
    try await performExactPenStop(workspace, owner: owner)

    #expect(workspace.activeExerciseAttemptID == nil)
    if let cancelledTransaction = workspace.discoveryTransactions[.penInteraction] {
      #expect(cancelledTransaction.state == .cancelled)
      #expect(cancelledTransaction.completedStepCount == 1)
    }
    #expect(workspace.activeDiscoverySequenceID == nil)
    #expect(workspace.selectedOperatorActionPresentation(for: owner).question == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)
    #expect(workspace.penCapAppearanceSelection == acceptedAppearance)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(workspace.restartableExerciseItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await workspace.shutdown()
  }

  @Test("Restart, Learning Off, reset, and source switch cannot revive a stopped click")
  func recoveryTransitionsDoNotReviveCancelledClick() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.performTestExerciseAction(.start, for: owner)
    let cancelledAttemptID = try #require(workspace.activeExerciseAttemptID)
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let displayed = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(
      workspace,
      request: request,
      point: try Point2(
        x: Double(displayed.frame.width - 1) / 2,
        y: Double(displayed.frame.height - 1) / 2
      )
    )
    try await waitUntil { workspace.penCapAppearanceSelection != nil }
    try await performExactPenStop(workspace, owner: owner)
    await workspace.performTestExerciseAction(.restart, for: owner)

    let restartedAttemptID = try #require(workspace.activeExerciseAttemptID)
    #expect(restartedAttemptID != cancelledAttemptID)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest?.purpose == .penCapAppearance)
    try await performExactPenStop(workspace, owner: owner)
    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { !workspace.testLearningIsEnabled }
    #expect(!workspace.testLearningIsEnabled)

    let plan = try #require(workspace.resetAllLearningPlan)
    let didVacate = await workspace.performLearningVacate(plan)
    #expect(didVacate)
    await workspace.switchFrameMode(.simulated)

    #expect(workspace.frameMode == .simulated)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.selectedOperatorActionPresentation(for: owner).question == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    await workspace.shutdown()
  }

  private func performExactPenStop(
    _ workspace: OperatorWorkspace,
    owner: LearningPathItemID
  ) async throws {
    let strip = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    )
    let stop = try #require(strip.actions.first { action in
      guard case .stop = action.kind else { return false }
      return action.isEnabled
    })
    guard case .stop(let presentedCapability) = stop.kind else {
      Issue.record("Expected the rendered Pen Stop capability.")
      return
    }
    let actionID = PlotterAppUIActionID.retainedLearning(stop.kind, owner: owner)
    let projection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let request = try #require(projection.request(for: actionID))
    guard case .penInteraction(.stop(let runtimeCapability)) = request.intent else {
      Issue.record("Expected the rendered Stop to bind the typed Pen runtime intent.")
      return
    }
    #expect(runtimeCapability.rawValue == presentedCapability.rawValue)
    let sink: any PlotterUIIntentSink = workspace
    #expect(await sink.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
  }

  @Test("shutdown settles an accepted-click continuation without starting a sequence")
  func shutdownDoesNotReviveAcceptedClick() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.performTestExerciseAction(.start, for: owner)
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let displayed = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(
      workspace,
      request: request,
      point: try Point2(
        x: Double(displayed.frame.width - 1) / 2,
        y: Double(displayed.frame.height - 1) / 2
      )
    )
    try await waitUntil { workspace.penCapAppearanceSelection != nil }
    await workspace.shutdown()

    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.selectedOperatorActionPresentation(for: owner).question == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
  }
}

private final class PenCapSelectionBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: PenCapAppearanceSelection?

  var value: PenCapAppearanceSelection? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return stored
    }
    set {
      lock.lock()
      stored = newValue
      lock.unlock()
    }
  }
}

private func colorFrame(
  red: UInt8,
  green: UInt8,
  blue: UInt8,
  width: Int = 9,
  height: Int = 9,
  pixelFormat: FramePixelFormat = .rgba8,
  configurationID: CameraConfigurationID = CameraConfigurationID(),
  frameID: String = "pen-cap-color"
) throws -> DisplayedFrame {
  let pixel: [UInt8]
  switch pixelFormat {
  case .rgba8:
    pixel = [red, green, blue, 255]
  case .bgra8:
    pixel = [blue, green, red, 255]
  case .gray8:
    pixel = [red]
  }
  return DisplayedFrame(
    source: .simulated,
    frame: try StampedFrame(
      id: FrameID(rawValue: frameID),
      sequence: 7,
      captureNanoseconds: 70,
      cameraConfigurationID: configurationID,
      width: width,
      height: height,
      rowBytes: width * pixelFormat.bytesPerPixel,
      pixelFormat: pixelFormat,
      bytes: OwnedFrameBytes(Array(repeating: pixel, count: width * height).flatMap { $0 })
    )
  )
}

private func pointSelection(
  frame: DisplayedFrame,
  x: Double,
  y: Double
) throws -> PlotterPointSelectionSubmission {
  PlotterPointSelectionSubmission(
    selectionID: PlotterPointSelectionID(),
    frame: exactPointSelectionFrame(frame),
    point: try Point2(x: x, y: y),
    presentationTransformRevision: PlotterPresentationTransformRevision()
  )
}
