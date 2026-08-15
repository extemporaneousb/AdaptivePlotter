import Foundation
import PlotterModel
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

    let learned = try PenCapAppearanceSampler.sample(frame: displayed, selection: selection)

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
        _ = try PenCapAppearanceSampler.sample(frame: displayed, selection: selection)
        Issue.record("Expected an achromatic or dark patch to be rejected")
      } catch let error as PenCapAppearanceSamplingError {
        #expect(error == .insufficientChromaticPixels(usable: 0, required: 9, total: 81))
        #expect(error.localizedDescription.contains("usable chromatic pixels"))
      }
    }
  }

  @Test("9 by 9 sampling clips safely at a frame edge")
  func edgeClipping() throws {
    let displayed = try colorFrame(red: 40, green: 90, blue: 210, width: 9, height: 9)
    let selection = try pointSelection(frame: displayed, x: 0, y: 0)

    let learned = try PenCapAppearanceSampler.sample(frame: displayed, selection: selection)

    #expect(learned.usableSampleCount == 25)
    #expect(learned.totalSampleCount == 25)
  }

  @Test("unsupported gray bytes and stale exact-frame clicks are refused")
  func unsupportedAndStaleRejection() throws {
    let gray = try colorFrame(
      red: 80, green: 80, blue: 80, pixelFormat: .gray8, frameID: "gray")
    let graySelection = try pointSelection(frame: gray, x: 4, y: 4)
    #expect(throws: PenCapAppearanceSamplingError.unsupportedPixelFormat(.gray8)) {
      try PenCapAppearanceSampler.sample(frame: gray, selection: graySelection)
    }

    let current = try colorFrame(red: 20, green: 80, blue: 220, frameID: "current")
    let stale = try colorFrame(
      red: 20,
      green: 80,
      blue: 220,
      configurationID: current.frame.cameraConfigurationID,
      frameID: "stale")
    let staleSelection = try pointSelection(frame: stale, x: 4, y: 4)
    #expect(throws: PenCapAppearanceSamplingError.staleExactFrame) {
      try PenCapAppearanceSampler.sample(frame: current, selection: staleSelection)
    }
  }

  @Test("Pen Interaction cannot ask a question or actuate before an accepted cap click")
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

    await workspace.beginPenInteraction()

    let presentation = workspace.actionSurfacePresentation
    let request = try #require(presentation.pointSelectionRequest)
    let frozenFrame = try #require(presentation.displayedFrame)
    #expect(request.purpose == .penCapAppearance)
    #expect(request.prompt == "Click the pen cap body—not the tip—on the current camera frame.")
    #expect(request.matches(frozenFrame))
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)

    let accepted = ActionSurfacePointSelection(
      frame: request.frame,
      point: try Point2(x: 4, y: 4),
      presentationTransformRevision: request.presentationTransformRevision
    )
    workspace.selectToolContactPoint(accepted)
    await workspace.awaitPenCapAcceptedClickTransition()
    try requireStep(workspace, "answer-initially-up")

    let learned = try #require(persisted.value)
    #expect(learned.matches(frozenFrame))
    #expect(workspace.penCapAppearanceSelection == learned)
    #expect(camera.recordedPenCapColorRequests.last == learned.color)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)
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
    await workspace.beginPenInteraction()
    let request = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)
    let staleFrame = try colorFrame(red: 20, green: 80, blue: 220, frameID: "other-frame")
    let stale = try pointSelection(frame: staleFrame, x: 4, y: 4)

    workspace.selectToolContactPoint(stale)

    #expect(workspace.actionSurfacePresentation.pointSelectionRequest == request)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.discoveryError?.contains("did not belong to the frozen exact frame") == true)
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
    await workspace.beginPenInteraction()
    let request = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)
    let displayed = try #require(workspace.actionSurfacePresentation.displayedFrame)
    let fallbackPoint = try Point2<CameraPixelSpace>(
      x: Double(displayed.frame.width - 1) / 2,
      y: Double(displayed.frame.height - 1) / 2
    )
    let point = workspace.actionSurfacePresentation.overlays.compactMap {
      overlay -> Point2<CameraPixelSpace>? in
      guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
      else { return nil }
      return point
    }.first ?? fallbackPoint
    workspace.selectToolContactPoint(
      ActionSurfacePointSelection(
        frame: request.frame,
        point: point,
        presentationTransformRevision: request.presentationTransformRevision
      )
    )
    await workspace.awaitPenCapAcceptedClickTransition()

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

  @Test("accepted click then immediate Cancel cannot revive Pen Interaction")
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

    await workspace.performExerciseAction(.start, for: owner)
    let cancelledAttemptID = try #require(workspace.activeExerciseAttemptID)
    try submitPenCapClick(workspace)
    let acceptedAppearance = try #require(workspace.penCapAppearanceSelection)
    await workspace.performExerciseAction(.cancel, for: owner)

    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.selectedOperatorActionPresentation(for: owner).question == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await log.values.isEmpty)
    #expect(workspace.penCapAppearanceSelection == acceptedAppearance)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(workspace.penAttemptHistory.attempts.count == 1)
    #expect(workspace.penAttemptHistory.attempts.first?.id == cancelledAttemptID)
    #expect(workspace.penAttemptHistory.attempts.first?.disposition == .cancelled)
    #expect(workspace.restartableExerciseItemID == owner)
    #expect(workspace.currentExerciseActionStripPresentation?.actions.map(\.kind) == [.restart])
    await workspace.shutdown()
  }

  @Test("Restart, Learning Off, reset, and source switch cannot revive a cancelled click")
  func recoveryTransitionsDoNotReviveCancelledClick() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)

    await workspace.performExerciseAction(.start, for: owner)
    let cancelledAttemptID = try #require(workspace.activeExerciseAttemptID)
    try submitPenCapClick(workspace)
    await workspace.performExerciseAction(.cancel, for: owner)
    await workspace.performExerciseAction(.restart, for: owner)

    let restartedAttemptID = try #require(workspace.activeExerciseAttemptID)
    #expect(restartedAttemptID != cancelledAttemptID)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.actionSurfacePresentation.pointSelectionRequest?.purpose == .penCapAppearance)
    await workspace.performExerciseAction(.cancel, for: owner)
    workspace.toggleLearningMode()
    #expect(!workspace.learningIsEnabled)

    let plan = try #require(workspace.resetAllLearningPlan)
    #expect(workspace.performLearningVacate(plan))
    await workspace.switchFrameMode(.simulated)

    #expect(workspace.frameMode == .simulated)
    #expect(workspace.discoveryTransactions[.penInteraction] == nil)
    #expect(workspace.selectedOperatorActionPresentation(for: owner).question == nil)
    #expect(await machine.requestedPenCommands.isEmpty)
    await workspace.shutdown()
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

    await workspace.performExerciseAction(.start, for: owner)
    try submitPenCapClick(workspace)
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
) throws -> ActionSurfacePointSelection {
  let optical = try CameraOpticalConfigurationIdentity(
    source: frame.source,
    sensorFormat: "pen-cap-selection-test",
    width: frame.frame.width,
    height: frame.frame.height,
    pixelFormat: frame.frame.pixelFormat,
    orientation: .up,
    mirrored: false,
    digitalZoomFactor: 1,
    lensIdentity: "test-lens",
    focusConfiguration: "test-focus",
    mountRevision: UUID(),
    reframingRevision: UUID()
  )
  let exact = try ExactTipCalibrationFrame(
    frameID: frame.frame.id,
    frameSHA256: frame.frame.contentSHA256,
    source: frame.source,
    captureSessionID: CameraCaptureSessionID(),
    opticalConfiguration: optical,
    cameraConfigurationID: frame.frame.cameraConfigurationID,
    captureNanoseconds: frame.frame.captureNanoseconds,
    width: frame.frame.width,
    height: frame.frame.height,
    pixelFormat: frame.frame.pixelFormat
  )
  return ActionSurfacePointSelection(
    frame: exact,
    point: try Point2(x: x, y: y),
    presentationTransformRevision: PresentationTransformRevision()
  )
}
