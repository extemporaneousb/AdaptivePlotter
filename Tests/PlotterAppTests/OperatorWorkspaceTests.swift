import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace learning runtime")
@MainActor
struct OperatorWorkspaceTests {
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
    async let first: Void = workspace.stopCurrentOperation()
    async let repeated: Void = workspace.stopCurrentOperation()
    _ = await (first, repeated)
    _ = await owner.value

    #expect(await machine.cancelCount == 1)
    #expect(workspace.relevantBoundaryObservationCount == 0)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)
    await workspace.shutdown()
  }

  @Test("boundary Stop records Stop first, settles owner, captures fresh frame, and updates posterior")
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

    await workspace.beginBoundaryDiscovery(.positiveX)
    await workspace.answerCurrentQuestion(.yes)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    async let first: Void = workspace.stopCurrentOperation()
    async let repeated: Void = workspace.stopCurrentOperation()
    _ = await (first, repeated)

    #expect(await machine.cancelCount == 1)
    #expect(await machine.requestedFeeds.last == 900)
    #expect(workspace.discoveryTransactions[.boundaryPositiveX]?.state == .succeeded)
    #expect(workspace.relevantBoundaryObservationCount == 1)
    #expect(workspace.drawingFramePosterior?.observationCount == 1)
    #expect(workspace.humanGuidedDiscoveryCurrentStep == .clearViewDiscovery)
    let events = await log.values
    #expect(events.firstIndex(of: "announce:Moving toward X+ boundary.")! < events.firstIndex(of: "machine:jog")!)
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

    await workspace.beginBoundaryDiscovery(.negativeY)
    await workspace.answerCurrentQuestion(.yes)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    await workspace.shutdown()

    #expect(await machine.cancelCount == 1)
    #expect(await machine.requestedFeeds.last == 100)
    #expect(workspace.discoveryTransactions.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.isShutdown)
  }

  @Test("announcement failure is advisory and Pen Interaction preserves output-before-actuation order")
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
    #expect(events.firstIndex(of: "announce:Lowering the pen.")! < events.firstIndex(of: "machine:pen-lower")!)
    #expect(events.firstIndex(of: "announce:Raising the pen.")! < events.firstIndex(of: "machine:pen-raise")!)
    #expect(workspace.lastAnnouncementResultText == "Announcement completed.")
    await workspace.shutdown()
  }
}

@MainActor
private func completePenInteraction(_ workspace: OperatorWorkspace) async throws {
  if let reason = workspace.discoveryStartUnavailableReason(for: .penInteraction) {
    throw StepMismatch(expected: "available", actual: reason)
  }
  await workspace.beginPenInteraction()
  try requireStep(workspace, "answer-initially-up")
  await workspace.answerCurrentQuestion(.yes)
  try requireStep(workspace, "answer-clear-to-lower")
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
  log _: EventLog
) -> OperatorWorkspace {
  let clock = TestClock()
  return OperatorWorkspace(
    machineActions: .init(
      select: { _ in await machine.snapshot() },
      snapshot: { await machine.snapshot() },
      requestPassiveProbe: {
        PassiveProbeResult(
          link: machine.descriptor,
          startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
          completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
          exchanges: [],
          blockers: []
        )
      },
      activateMotionGuard: { .activated },
      deactivateMotionGuard: {},
      requestRelativeJog: { await machine.requestRelativeJog($0) },
      requestDrawingStroke: { _ in fatalError("unused") },
      requestObservedJog: { _, _ in fatalError("unused") },
      requestPenActuation: { await machine.requestPen($0) },
      requestJogCancel: { await machine.cancel() },
      disconnect: {}
    ),
    cameraActions: camera.map(cameraActions),
    announcementActions: announcements.map { fixture in
      .init(
        announce: { await fixture.announce($0) },
        cancelForShutdown: { await fixture.cancelForShutdown() }
      )
    },
    serialDevices: [machine.descriptor],
    serialDeviceDiscovery: { [machine.descriptor] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in },
    nowNanoseconds: { clock.next() }
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
    setAutomaticInspection: { _ in .stopped },
    analysisUpdates: { AsyncStream { $0.finish() } },
    observeVisibleTool: { _, _ in fatalError("unused") },
    simulatedContent: { _ in fatalError("unused") },
    simulatedExplorationFrames: { fatalError("unused") },
    observeAnchorDot: { _ in fatalError("unused") },
    observeIsolatedInk: { _ in fatalError("unused") },
    exportLearningEpisode: { _, _ in fatalError("unused") }
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
  private(set) var cancelCount = 0
  private(set) var requestedFeeds: [Double] = []
  private var moving = false
  private var cancelPending = false
  private var continuation: CheckedContinuation<MotionOutcome, Never>?
  private var position: MachinePosition
  private var penState: PenState = .up
  private var lastMotion: MotionOutcome?
  private var lastPen: PenOutcome?
  private var lastCancel: JogCancelOutcome?
  private var activeRequest: RelativeJogRequest?

  init(log: EventLog, feedLimits: ControllerAxisFeedLimits? = nil) throws {
    self.log = log
    self.feedLimits = feedLimits
    position = try MachinePosition(x: 0, y: 0)
  }

  func snapshot() -> RunInterpreterSnapshot {
    RunInterpreterSnapshot(
      currentOperation: activeRequest.map(RunOperation.relativeJog) ?? .idle,
      machine: MachineSnapshot(
        connection: moving ? .moving : .connected,
        link: descriptor,
        lastProbe: nil,
        blockers: [],
        controllerState: moving ? .jog : .idle,
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

  func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome {
    requestedFeeds.append(request.feedMMPerMinute)
    activeRequest = request
    moving = true
    await log.append("machine:jog")
    if cancelPending {
      cancelPending = false
      return settleCancelled()
    }
    let outcome = await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
    lastMotion = outcome
    activeRequest = nil
    return outcome
  }

  func cancel() -> JogCancelOutcome {
    cancelCount += 1
    if let continuation {
      self.continuation = nil
      let outcome = settleCancelled()
      continuation.resume(returning: outcome)
    } else {
      cancelPending = true
    }
    lastCancel = .completed(finalPosition: position)
    return lastCancel!
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
}

private struct CameraFixture: Sendable {
  let device: CameraDevice
  let snapshot: CameraCaptureSnapshot
  private let configurationID: CameraConfigurationID

  init() throws {
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
    let capture = captureBoundary &+ 1
    let fresh = DisplayedFrame(
      source: .live(device.id),
      frame: try frame(
        id: "fresh-\(capture)",
        sequence: capture,
        capture: capture,
        configurationID: configurationID
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
      cameraConfigurationID: configurationID,
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
    await Task.yield()
  }
  throw TestTimeout()
}

private struct TestTimeout: Error {}
private struct StepMismatch: Error {
  let expected: String
  let actual: String
}
