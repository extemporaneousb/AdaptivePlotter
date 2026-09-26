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
  @Test("initial Identify ignores successful late capture after exact Pen Stop")
  func lateInitialCaptureCannotRepublishAfterStop() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let gate = TestInspectionSuspension()
    let workspace = plotterApplicationRuntime(machine: machine,
      observationSessionOverride: resolvedObservationSession(camera, captureProvider: { boundary in
        await gate.waitIfArmed()
        // Deliberately return pixels even if the owning task was cancelled.
        return try camera.inspection(after: boundary).displayedFrame
      }), loadPenCapAppearanceSelection: { nil }, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let priorFrameID = workspace.testActionSurfacePresentation.displayedFrame?.frame.id
    await gate.arm()
    let identify = Task { await workspace.performTestExerciseAction(.start, for: owner) }
    try await waitForExecutorTurnsAsync(conditionDescription: "initial Identify held capture") {
      await gate.isWaiting
    }
    try await performExactPenStop(workspace, owner: owner)
    #expect(workspace.activeExerciseAttemptID == nil)
    await gate.release()
    await identify.value
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.pointSelectionEpisodeProjection.exactPointSelection.request == nil)
    #expect(workspace.frozenPointSelectionFrame == nil)
    #expect(workspace.testActionSurfacePresentation.displayedFrame?.frame.id == priorFrameID)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(workspace.learningSelectionDiagnosticSnapshot.canvasHasSelection == false)
    await workspace.shutdown()
  }

  @Test("reference sampling preserves dark pixels, independent anchor and exact provenance")
  func visualSamplingAndPersistence() throws {
    let displayed = try DisplayedFrame(source: .live(CameraDeviceID(rawValue: "cap-reference-fixture")),
      frame: colorFrame(red: 190, green: 25, blue: 20).frame)
    let selection = try pointSelection(frame: displayed, x: 3, y: 8)
    let sample = try PlotterPenCapPointSampler.sample(frame: displayed, submission: selection)
    let learned = PenCapAppearanceSelection(sample: sample, frame: displayed)
    let reference = try #require(learned.visualReference)
    #expect(reference.rgb.contains(12))
    #expect(reference.anchor == selection.point)
    #expect(reference.region == PixelRect(x: 0, y: 0, width: 12, height: 12))
    #expect(learned.matches(displayed))
    #expect(learned.algorithmRevision == PenCapVisualReference.revision)
    #expect(try JSONDecoder().decode(PenCapAppearanceSelection.self,
      from: JSONEncoder().encode(learned)) == learned)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AcceptedLearningPathCheckpointStore(fileURL: directory.appendingPathComponent("accepted.json"))
    let package = try AcceptedLearningPathCheckpoint(
      semanticIdentity: TipCalibrationSemanticIdentityState.ephemeral().learningPathIdentity,
      penCapAppearance: learned.acceptedCheckpoint())
    try store.save(package)
    guard case .loaded(let loaded) = store.load() else {
      Issue.record("The complete saved Learning package must retain the visual reference.")
      return
    }
    #expect(loaded.penCapAppearance?.visualReference == reference)
  }

  @Test("missing rectangle and cap anchor outside the rectangle are refused")
  func invalidReferenceSelection() throws {
    let displayed = try colorFrame(red: 180, green: 25, blue: 20)
    let outside = try pointSelection(frame: displayed, x: 15, y: 8)
    #expect(throws: PenCapReferenceError.self) {
      try PlotterPenCapPointSampler.sample(frame: displayed, submission: outside)
    }
    let missing = PlotterPointSelectionSubmission(selectionID: outside.selectionID,
      frame: outside.frame, point: try Point2(x: 4, y: 4),
      presentationTransformRevision: outside.presentationTransformRevision)
    #expect(throws: PenCapReferenceError.self) {
      try PlotterPenCapPointSampler.sample(frame: displayed, submission: missing)
    }
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
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let persisted = PenCapSelectionBox()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      persistPenCapAppearanceSelection: { persisted.value = $0 },
      log: log
    )
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await log.clear()

    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )

    let presentation = workspace.testActionSurfacePresentation
    let request = try #require(presentation.pointSelectionRequest)
    let frozenFrame = try #require(presentation.displayedFrame)
    #expect(request.purpose == .penCapAppearance)
    #expect(request.prompt == "Click the pen cap or its distinct tape marker. Its center will be tracked; no rectangle is needed.")
    #expect(request.referenceMode == .sampledColorMarker)
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
      camera.recordedPenCapColorRequests.last != nil && !camera.recordedPenCapReferenceRequests.isEmpty
    }

    let learned = try #require(workspace.penCapAppearanceSelection)
    #expect(learned.matches(frozenFrame))
    #expect(workspace.penCapAppearanceSelection == learned)
    #expect(persisted.value == nil)
    #expect(camera.recordedPenCapColorRequests.last == learned.color)
    #expect(camera.recordedPenCapReferenceRequests.last == learned.visualReference)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)
    await workspace.shutdown()
  }

  @Test("cap identification survives external controller and Motion setup")
  func capIdentificationPrecedesControllerSetup() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log, motionGuardInitiallyActive: false)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(
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

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

    let identifyAction = try #require(
      workspace.currentExerciseActionStripPresentation?.actions.first
    )
    #expect(identifyAction.title == "Capture Pen Cap")
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
    #expect(workspace.controllerSessionProjection.selectionUnavailableReason == nil)
    #expect(workspace.controllerSessionProjection.connectionUnavailableReason == "Select one serial device first.")

    let blockedSetpointID = learningSetpointActionID(
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

    await submitControllerSession(
      workspace,
      .selectSerialDevice(controllerDevice(machine.descriptor))
    )
    #expect(workspace.controllerSessionProjection.connectionUnavailableReason == nil)
    await submitControllerSession(workspace, .toggleConnection)

    let connectedStrip = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(
      connectedStrip.actions.first { $0.kind == .choice(.yes) }?.unavailableReason
        == motionBlocker
    )
    #expect(connectedStrip.penSetpointAdjustment?.unavailableReason == motionBlocker)
    try requireStep(workspace, "answer-initially-up")

    await submitControllerSession(workspace, .toggleMotionAuthorization)

    let readyStrip = try #require(workspace.currentExerciseActionStripPresentation)
    #expect(readyStrip.actions.first { $0.kind == .choice(.yes) }?.unavailableReason == nil)
    #expect(readyStrip.penSetpointAdjustment?.isEnabled == true)
    try requireStep(workspace, "answer-initially-up")
    await workspace.shutdown()
  }

  @Test("first Pen question does not wait for held or failing Vision reconfiguration")
  func firstQuestionPrecedesVisionReconfiguration() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession(
      automaticAnalysisError: "Injected automatic Vision reconfiguration failure."
    )
    let reconfigurationGate = TestConfigurationSuspension()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: resolvedObservationSession(
        camera,
        reconfigurationGate: reconfigurationGate
      ),
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
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

  @Test("re-entering identification freezes directly without waiting for the old tracker")
  func learnedAppearanceFreezesWithoutOldTracker() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession(providesInspectionOverlay: true)
    let initial = try #require(camera.snapshot.latestFrame)
    let priorAppearance = testPenCapAppearanceSelection(source: initial.source,
      cameraConfigurationID: initial.frame.cameraConfigurationID)
    let workspace = plotterApplicationRuntime(machine: machine,
      observationSessionOverride: resolvedObservationSession(camera, captureProvider: { boundary in
        // Raw acquisition must remain independent of the old matcher spy.
        DisplayedFrame(source: initial.source, frame: try frame(
          id: "identification-raw-capture", sequence: 2, capture: boundary + 1,
          configurationID: initial.frame.cameraConfigurationID))
      }), loadPenCapAppearanceSelection: { priorAppearance }, log: log)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)

    #expect(workspace.livePenCapAppearanceSelection == priorAppearance)
    let inspectionCountBeforeIdentification = camera.inspectionCallCount
    await workspace.performTestExerciseAction(
      .start,
      for: .humanGuidedDiscovery(.penInteraction)
    )

    let presentation = workspace.testActionSurfacePresentation
    let frozen = try #require(presentation.displayedFrame)
    let request = try #require(presentation.pointSelectionRequest)
    #expect(request.frame.frameID == frozen.frame.id.rawValue)
    #expect(request.frame.frameSHA256 == frozen.frame.contentSHA256)
    #expect(request.referenceMode == .sampledColorMarker)
    #expect(presentation.overlays.allSatisfy { $0.matches(frozen) })
    #expect(frozen.frame.id.rawValue == "identification-raw-capture")
    #expect(camera.inspectionCallCount == inspectionCountBeforeIdentification)
    #expect(await machine.requestedPenCommands.isEmpty)
    await workspace.shutdown()
  }

  @Test("stale click remains pending and performs no machine action")
  func staleClickRemainsPending() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
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
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(workspace.overlayStatus(for: .penCap).state == .unavailable)
    #expect(workspace.overlayStatus(for: .penCap).message.contains("click the pen cap"))
    #expect(camera.recordedPenCapColorRequests.isEmpty)
    await workspace.shutdown()
  }

  @Test("persisted SIMULATED appearance cannot authorize LIVE Vision or exact workflow")
  func persistedSimulatedAppearanceIsRefusedForLive() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let simulated = testPenCapAppearanceSelection(source: .simulated)
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { simulated },
      log: log
    )

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

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
      #expect(String(describing: error).contains("Capture Pen Cap"))
    }
    #expect(camera.inspectionCallCount == 0)
    await workspace.shutdown()
  }

  @Test("SIMULATED identification has a separate owner and cannot erase LIVE appearance")
  func simulatedIdentificationDoesNotReplaceLiveAppearance() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let live = testPenCapAppearanceSelection(
      color: PenCapColor(red: 20, green: 80, blue: 220)
    )
    let persisted = PenCapSelectionBox()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { live },
      persistPenCapAppearanceSelection: { persisted.value = $0 },
      log: log
    )

    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    let liveRequestsBeforeSelection = camera.recordedPenCapColorRequests
    #expect(liveRequestsBeforeSelection.allSatisfy { $0 == live.color })
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
    // Source/startup reconciliation may replay the retained LIVE color. The
    // SIM selection must never configure that camera with its own color.
    #expect(simulated.color != live.color)
    let requestsDuringSelection = camera.recordedPenCapColorRequests
      .dropFirst(liveRequestsBeforeSelection.count)
    #expect(requestsDuringSelection.allSatisfy { $0 == live.color })
    await workspace.shutdown()
  }

  @Test("valid persisted LIVE appearance survives relaunch and camera configuration change")
  func persistedLiveAppearanceSurvivesCameraLifecycle() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let live = testPenCapAppearanceSelection(
      color: PenCapColor(red: 20, green: 80, blue: 220),
      cameraConfigurationID: CameraConfigurationID()
    )
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { live },
      log: log
    )

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    #expect(workspace.livePenCapAppearanceSelection == live)
    #expect(camera.recordedPenCapColorRequests.last == live.color)

    await submitObservationConfigurationForTest(workspace, .restartLiveSource)
    #expect(workspace.livePenCapAppearanceSelection == live)
    #expect(workspace.persistedPenCapAppearanceLoadState == .accepted)
    #expect(camera.recordedPenCapColorRequests.last == live.color)
    #expect(camera.recordedPenCapColorRequests.count >= 2)
    await workspace.shutdown()
  }

  @Test("invalid persisted LIVE appearance is ignored without changing overlay preference")
  func invalidPersistedLiveAppearanceIsRefused() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let invalid: PenCapAppearanceSelection = {
      var selection = testPenCapAppearanceSelection()
      selection.visualReference = nil
      return selection
    }()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { invalid },
      log: log
    )

    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))

    #expect(workspace.livePenCapAppearanceSelection == nil)
    guard case .refused(let reason) = workspace.persistedPenCapAppearanceLoadState else {
      Issue.record("Expected invalid LIVE appearance to be refused")
      await workspace.shutdown()
      return
    }
    #expect(reason.contains("needs a new capture"))
    #expect(workspace.overlayPreferenceState.enabled == Set(UserSceneOverlay.allCases))
    #expect(workspace.overlayStatus(for: .penCap).message == reason)
    #expect(camera.recordedPenCapColorRequests.isEmpty)
    await workspace.shutdown()
  }

  @Test("accepted click then exact Pen Stop cannot revive Exercise 1.1")
  func acceptedClickImmediateCancelDoesNotRevive() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      loadPenCapAppearanceSelection: { nil },
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
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
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    // The wait below must observe this click, not a preloaded fixture reference.
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera,
      loadPenCapAppearanceSelection: { nil }, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
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
    // The question may have started before Stop. Its cancelled history is
    // retained by the owner; Restart must not revive or replace that history.
    let stoppedTransaction = workspace.discoveryTransactions[.penInteraction]
    if let stoppedTransaction {
      #expect(stoppedTransaction.state == .cancelled)
      #expect(stoppedTransaction.completedStepCount == 1)
    }
    await workspace.performTestExerciseAction(.restart, for: owner)

    let restartedAttemptID = try #require(workspace.activeExerciseAttemptID)
    #expect(restartedAttemptID != cancelledAttemptID)
    #expect(workspace.discoveryTransactions[.penInteraction] == stoppedTransaction)
    #expect(workspace.activeDiscoverySequenceID == nil)
    #expect(workspace.selectedOperatorActionPresentation(for: owner).question == nil)
    let restartedRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    #expect(restartedRequest.purpose == .penCapAppearance)
    #expect(restartedRequest.id != request.id)
    try await performExactPenStop(workspace, owner: owner)
    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { !workspace.testLearningIsEnabled }
    #expect(!workspace.testLearningIsEnabled)

    let plan = try #require(workspace.resetAllLearningPlan)
    let didVacate = await workspace.performLearningVacate(plan)
    #expect(didVacate)
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))

    #expect(workspace.frameMode == .simulated)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.selectedOperatorActionPresentation(for: owner).question == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    await workspace.shutdown()
  }

  private func performExactPenStop(
    _ workspace: PlotterApplicationRuntime,
    owner: LearningPathItemID
  ) async throws {
    let strip = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip
    )
    let stop = try #require(strip.actions.first { action in
      guard case .stopPenInteraction = action.kind else { return false }
      return action.isEnabled
    })
    guard case .stopPenInteraction(let presentedCapability) = stop.kind else {
      Issue.record("Expected the rendered Pen Stop capability.")
      return
    }
    let actionID = learningActionID(stop.kind, owner: owner)
    let projection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let request = try #require(projection.request(for: actionID))
    guard case .learningAction(let learningRequest) = request.intent,
      case .stopPenInteraction(let runtimeCapability) = learningRequest.action
    else {
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
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
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
  width: Int = 24,
  height: Int = 24,
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
      bytes: OwnedFrameBytes((0..<(width * height)).flatMap { i in
        i % width < 6 ? Array(repeating: UInt8(12), count: pixel.count) : pixel
      })
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
    presentationTransformRevision: PlotterPresentationTransformRevision(),
    referenceRegion: try AxisAlignedBounds(minX: 0, minY: 0, maxX: 12, maxY: 12)
  )
}
