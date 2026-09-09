import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Workbench selected camera lifecycle")
struct WorkbenchCameraLifecycleTests {
  @Test("real camera stream generations exclude stale sources while complete saved Learning survives unchanged optics")
  @MainActor
  func framesAndSavedLearningAcrossCameraSwitch() async throws {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(accepted)
    guard case .live(let deviceID) = accepted.frame.source else {
      Issue.record("The synthetic accepted artifact must name its exact test camera")
      return
    }
    let probe = WorkbenchCaptureProbe()
    await probe.setFrame(accepted.frame.frame)
    let live = CameraCapture(driver: WorkbenchCaptureDriver(role: .plotter, probe: probe, plotterID: deviceID))
    let portrait = PortraitStudioModel(camera: CameraCapture(
      driver: WorkbenchCaptureDriver(role: .portrait, probe: probe, plotterID: deviceID)))
    let vision = VisionWorker()
    let session = CameraSourceSession(live: live, vision: vision,
      analysisPipeline: PlotterSceneAnalysisPipeline(worker: vision), plannedDrawingObserver: vision)
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let app = plotterApplicationRuntime(machine: machine, observationSessionOverride: session,
      portraitStudio: portrait, statePersistencePort: stores.persistence, drawingEvidencePort: stores.evidencePort,
      tipCalibrationSemanticIdentities: accepted.identities, loadPenCapAppearanceSelection: { nil }, log: log)
    await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await submitObservationConfigurationForTest(app, .selectSource(.live, deviceID))
    try await applyCompleteSavedLearning(app)
    let checkpointID = try #require(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID)
    let tip = try #require(app.tipCameraRegistration)
    let first = try #require(app.displayedFrame)
    #expect(app.interactiveLearningIsComplete)
    let acceptedIDs = Set(app.learningArtifactGraph.revisions.map(\.id))

    for index in 0..<5 {
      let selectPortrait = app.observationConfigurationProjection.request(.selectCameraRole(.portrait))
      #expect(await app.submitObservationConfiguration(selectPortrait) == nil)
      let portraitTime = UInt64(10_000 + index * 10)
      await probe.emit(.plotter, timestamp: portraitTime - 1, sessionIndex: 0)
      await probe.emit(.portrait, timestamp: portraitTime)
      try await awaitCameraPublication { portrait.preview.frame?.frame.captureNanoseconds == portraitTime }
      #expect(app.actionSurfacePreview.displayedFrame == nil)
      #expect(app.displayedFrame == nil)
      #expect(await live.snapshot().state == .stopped)
      #expect(app.tipCameraRegistration == tip)
      #expect(app.interactiveLearningIsComplete)

      #expect(await app.submitObservationConfiguration(
        app.observationConfigurationProjection.request(.selectCameraRole(.plotter))) == nil)
      let plotterTime = portraitTime + 2
      await probe.emit(.portrait, timestamp: plotterTime - 1, sessionIndex: 0)
      await probe.emit(.plotter, timestamp: plotterTime)
      try await awaitCameraPublication { app.actionSurfacePreview.displayedFrame?.frame.captureNanoseconds == plotterTime }
      let returned = try #require(app.displayedFrame)
      #expect(returned.source == accepted.frame.source)
      #expect(returned.frame.cameraConfigurationID != first.frame.cameraConfigurationID)
      #expect(portrait.preview.frame == nil)
      #expect(app.tipCameraRegistration == tip)
      #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID == checkpointID)
      #expect(Set(app.learningArtifactGraph.revisions.map(\.id)) == acceptedIDs)
      #expect(app.interactiveLearningIsComplete)
    }
    #expect(await probe.maximumActiveCount == 1)
    await app.shutdown()
    #expect(await probe.activeRoles.isEmpty)
  }

  @Test("selecting the settled camera role preserves its capture and configuration revision")
  @MainActor
  func repeatedSettledRoleIsNoOp() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    let plotterReference = await fixture.runtime.reference()
    for _ in 0..<5 { _ = await fixture.select(.plotter) }
    #expect(await fixture.runtime.reference() == plotterReference)
    #expect(await fixture.probe.startedRoles == [.plotter])
    _ = await fixture.select(.portrait)
    let portraitReference = await fixture.runtime.reference()
    for _ in 0..<5 { _ = await fixture.select(.portrait) }
    #expect(await fixture.runtime.reference() == portraitReference)
    #expect(await fixture.probe.startedRoles == [.plotter, .portrait])
    fixture.portrait.selectedDeviceID = .init(rawValue: "portrait-secondary")
    _ = await fixture.select(.portrait)
    #expect(await fixture.portrait.cameraDiagnostics().selectedDeviceID == .init(rawValue: "portrait-secondary"))
    #expect(await fixture.runtime.reference() != portraitReference)
    #expect(await fixture.probe.startedRoles == [.plotter, .portrait, .portrait])
    #expect(await fixture.probe.maximumActiveCount == 1)
    await fixture.runtime.shutdown()
  }

  @Test("held plotter stop prevents portrait start, then twenty switches keep one capture")
  @MainActor
  func exclusiveCaptureAndReuse() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    await fixture.probe.hold("plotter.stop")
    let selection = Task { await fixture.select(.portrait) }
    try await fixture.probe.waitUntilHeld("plotter.stop")
    #expect(await fixture.runtime.workbenchCameraSnapshot().isTransitioning)
    #expect(await fixture.probe.activeRoles == [.plotter])
    #expect(!fixture.portrait.cameraIsRunning)
    #expect(await fixture.probe.startedRoles == [.plotter])
    await fixture.probe.release("plotter.stop")
    guard case .applied = await selection.value else {
      Issue.record("Portrait selection did not settle")
      return
    }
    #expect(await fixture.probe.activeRoles == [.portrait])
    #expect(await fixture.session.visionDiagnostics().requestedCadence == nil)
    for index in 0..<20 {
      let role: WorkbenchCameraRole = index.isMultiple(of: 2) ? .plotter : .portrait
      guard case .applied = await fixture.select(role) else {
        Issue.record("Repeated camera selection did not settle")
        return
      }
      #expect(await fixture.probe.activeRoles == [role])
    }
    #expect(await fixture.probe.maximumActiveCount == 1)
    await fixture.runtime.shutdown()
    #expect(await fixture.probe.activeRoles.isEmpty)
  }

  @Test("newer selection during a held face start settles the stale capture before return")
  @MainActor
  func supersededHeldStart() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    await fixture.probe.hold("portrait.start")
    let face = Task { await fixture.select(.portrait) }
    try await fixture.probe.waitUntilHeld("portrait.start")
    let plotter = Task { await fixture.select(.plotter) }
    try await awaitCameraTestState { await fixture.runtime.workbenchCameraSnapshot().role == .plotter }
    #expect(await fixture.probe.activeRoles.isEmpty)
    #expect(await fixture.probe.startedRoles == [.plotter])
    await fixture.probe.release("portrait.start")
    #expect(await face.value == .refused("Camera selection was replaced by a newer selection."))
    guard case .applied = await plotter.value else {
      Issue.record("Latest plotter selection did not settle")
      return
    }
    #expect(await fixture.runtime.workbenchCameraSnapshot() == .init(role: .plotter))
    #expect(await fixture.probe.activeRoles == [.plotter])
    #expect(await fixture.probe.maximumActiveCount == 1)
    #expect(!fixture.portrait.cameraIsRunning)
    #expect(fixture.portrait.preview.frame == nil)
    await fixture.runtime.shutdown()
  }

  @Test("shutdown joins noncooperative camera start and never starts its replacement")
  @MainActor
  func shutdownDuringHeldStart() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    let events = await fixture.runtime.updates()
    let publishedRoles = Task { () -> [PlotterWorkbenchCameraSnapshot] in
      var values: [PlotterWorkbenchCameraSnapshot] = []
      for await event in events {
        if case .cameraRole(let role) = event { values.append(role) }
      }
      return values
    }
    await fixture.probe.hold("portrait.start")
    let face = Task { await fixture.select(.portrait) }
    try await fixture.probe.waitUntilHeld("portrait.start")
    let reference = await fixture.runtime.reference()
    let shutdown = Task { await fixture.runtime.shutdown() }
    try await awaitCameraTestState { await fixture.runtime.reference().revision != reference.revision }
    #expect(await fixture.select(.plotter) == .refused("Observation configuration is shut down."))
    #expect(await fixture.probe.startedRoles == [.plotter])
    await fixture.probe.release("portrait.start")
    await shutdown.value
    #expect(await face.value == .refused("Observation configuration is shut down."))
    #expect(await fixture.probe.activeRoles.isEmpty)
    #expect(await fixture.probe.startedRoles == [.plotter, .portrait])
    #expect(!fixture.portrait.cameraIsRunning)
    #expect(await publishedRoles.value == [.init(role: .portrait, isTransitioning: true)])
  }

  @Test("newer Portrait selection survives an older source operation's held portrait settlement",
    arguments: [PlotterObservationConfigurationIntent.startLiveSource, .restartLiveSource,
      .stopLiveSource, .selectLiveSource(.init(rawValue: "plotter"))])
  @MainActor
  func latestRoleSurvivesHeldSourceSettlement(operation: PlotterObservationConfigurationIntent) async throws {
    let fixture = await WorkbenchCameraFixture.make()
    guard case .applied = await fixture.select(.portrait) else {
      await fixture.runtime.shutdown()
      Issue.record("Initial Portrait selection did not settle")
      return
    }
    let events = await fixture.runtime.updates()
    let publishedRoles = Task { () -> [PlotterWorkbenchCameraSnapshot] in
      var values: [PlotterWorkbenchCameraSnapshot] = []
      for await event in events {
        if case .cameraRole(let role) = event { values.append(role) }
      }
      return values
    }
    await fixture.probe.hold("portrait.stop")
    let sourceReference = await fixture.runtime.reference()
    let source = Task {
      await fixture.runtime.submit(.init(reference: sourceReference, intent: operation))
    }
    var portraitSelection: Task<PlotterObservationConfigurationDisposition, Never>?
    do {
      try await fixture.probe.waitUntilHeld("portrait.stop")
      #expect(await fixture.probe.activeRoles == [.portrait])
      #expect(await fixture.probe.startedRoles == [.plotter, .portrait])
      #expect(await fixture.runtime.workbenchCameraSnapshot() == .init(role: .portrait))

      portraitSelection = Task { await fixture.select(.portrait) }
      // This transition is published by accepting the newer request while the
      // older admitted source task is still inside the actual lower stop.
      try await awaitCameraTestState {
        await fixture.runtime.workbenchCameraSnapshot() == .init(role: .portrait, isTransitioning: true)
      }
      #expect(await fixture.probe.activeRoles == [.portrait])
      #expect(await fixture.probe.startedRoles == [.plotter, .portrait])
      await fixture.probe.hold("portrait.start")
      await fixture.probe.release("portrait.stop")
      #expect(await source.value == .applied(revision: sourceReference.revision + 1))
      // Hold the new drain's final start too, so an older settled role cannot
      // be hidden by a later correct publication before this assertion.
      #expect(await fixture.runtime.workbenchCameraSnapshot() == .init(role: .portrait, isTransitioning: true))
      try await fixture.probe.waitUntilHeld("portrait.start")
      #expect(await fixture.probe.activeRoles.isEmpty)
      await fixture.probe.release("portrait.start")
      #expect(await portraitSelection?.value == .applied(revision: sourceReference.revision + 2))
      #expect(await fixture.runtime.workbenchCameraSnapshot() == .init(role: .portrait))
      #expect(await fixture.probe.activeRoles == [.portrait])
      #expect(await fixture.probe.maximumActiveCount == 1)
      #expect(await fixture.session.snapshot().state == .stopped)
      #expect(fixture.portrait.cameraIsRunning)
      let expectedStarts: [WorkbenchCameraRole]
      switch operation {
      case .startLiveSource, .restartLiveSource:
        expectedStarts = [.plotter, .portrait, .plotter, .portrait]
      default:
        expectedStarts = [.plotter, .portrait, .portrait]
      }
      #expect(await fixture.probe.startedRoles == expectedStarts)
      await fixture.runtime.shutdown()
      #expect(await fixture.probe.activeRoles.isEmpty)
      // The old operation may settle its physical effect, but it must never
      // publish a settled Plotter choice over the accepted newer request.
      #expect(await publishedRoles.value == [
        .init(role: .portrait, isTransitioning: true), .init(role: .portrait)
      ])
    } catch {
      await fixture.probe.release("portrait.stop")
      await fixture.probe.release("portrait.start")
      _ = await source.value
      _ = await portraitSelection?.value
      await fixture.runtime.shutdown()
      _ = await publishedRoles.value
      throw error
    }
  }

  @Test("failed face startup supplies a remedy and the same owner can retry")
  @MainActor
  func startupFailureAndRetry() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    await fixture.probe.failNextPortraitStart()
    let failed = await fixture.select(.portrait)
    guard case .failed(let error) = failed else {
      Issue.record("Expected the camera startup failure")
      return
    }
    #expect(error.contains("Reconnect"))
    #expect(await fixture.probe.activeRoles.isEmpty)
    guard case .applied = await fixture.select(.portrait) else {
      Issue.record("Retry did not reuse the camera owner")
      return
    }
    #expect(await fixture.probe.activeRoles == [.portrait])
    #expect(await fixture.runtime.workbenchCameraSnapshot().error == nil)
    await fixture.runtime.shutdown()
  }

  @Test("a source request during a held role transition uses existing stale admission and cannot start another capture")
  @MainActor
  func sourceRequestDuringRoleTransitionDoesNotAdmit() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    guard case .applied = await fixture.select(.portrait) else {
      await fixture.runtime.shutdown()
      Issue.record("Initial Portrait selection did not settle")
      return
    }
    await fixture.probe.hold("portrait.stop")
    let plotter = Task { await fixture.select(.plotter) }
    var source: Task<PlotterObservationConfigurationDisposition, Never>?
    do {
      try await fixture.probe.waitUntilHeld("portrait.stop")
      #expect(await fixture.runtime.workbenchCameraSnapshot() == .init(role: .plotter, isTransitioning: true))
      #expect(await fixture.probe.activeRoles == [.portrait])
      let reference = await fixture.runtime.reference()
      var sourceEntered = false
      source = Task {
        sourceEntered = true
        return await fixture.runtime.submit(.init(reference: reference, intent: .startLiveSource))
      }
      try await awaitCameraPublication { sourceEntered }
      #expect(await fixture.probe.activeRoles == [.portrait])
      #expect(await fixture.probe.startedRoles == [.plotter, .portrait])
      await fixture.probe.release("portrait.stop")
      #expect(await plotter.value == .applied(revision: reference.revision + 1))
      #expect(await source?.value == .stale)
      #expect(await fixture.runtime.workbenchCameraSnapshot() == .init(role: .plotter))
      #expect(await fixture.probe.activeRoles == [.plotter])
      #expect(await fixture.probe.startedRoles == [.plotter, .portrait, .plotter])
      #expect(await fixture.probe.maximumActiveCount == 1)
      await fixture.runtime.shutdown()
      #expect(await fixture.probe.activeRoles.isEmpty)
    } catch {
      await fixture.probe.release("portrait.stop")
      _ = await plotter.value
      _ = await source?.value
      await fixture.runtime.shutdown()
      throw error
    }
  }
}

@MainActor
private func awaitCameraPublication(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !condition(), ContinuousClock.now < deadline { await Task.yield() }
  try #require(condition(), "The current selected source must publish its exact test frame before the deadline.")
}

@MainActor
private func awaitCameraTestState(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !(await condition()) {
    try #require(ContinuousClock.now < deadline, "Camera lifecycle state did not settle before the deadline.")
    try await Task.sleep(for: .milliseconds(1))
  }
}

@MainActor
private struct WorkbenchCameraFixture {
  let probe: WorkbenchCaptureProbe
  let portrait: PortraitStudioModel
  let session: CameraSourceSession
  let runtime: PlotterObservationConfigurationRuntime

  static func make() async -> Self {
    let probe = WorkbenchCaptureProbe()
    let live = CameraCapture(driver: WorkbenchCaptureDriver(role: .plotter, probe: probe))
    let portrait = PortraitStudioModel(camera: CameraCapture(
      driver: WorkbenchCaptureDriver(role: .portrait, probe: probe)))
    let vision = VisionWorker()
    let session = CameraSourceSession(live: live, vision: vision,
      analysisPipeline: PlotterSceneAnalysisPipeline(worker: vision), plannedDrawingObserver: vision)
    let runtime = PlotterObservationConfigurationRuntime(lower: session, portrait: portrait)
    _ = await runtime.submit(.init(reference: await runtime.reference(), intent: .refreshSources))
    _ = await runtime.submit(.init(reference: await runtime.reference(),
                                  intent: .selectLiveSource(.init(rawValue: "plotter"))))
    _ = await runtime.submit(.init(reference: await runtime.reference(), intent: .startLiveSource))
    return Self(probe: probe, portrait: portrait, session: session, runtime: runtime)
  }

  func select(_ role: WorkbenchCameraRole) async -> PlotterObservationConfigurationDisposition {
    await runtime.submit(.init(reference: await runtime.reference(), intent: .selectCameraRole(role)))
  }
}

private struct WorkbenchCaptureDriver: CameraCaptureDriver {
  let role: WorkbenchCameraRole
  let probe: WorkbenchCaptureProbe
  var plotterID: CameraDeviceID = .init(rawValue: "plotter")
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] {
    [CameraDevice(id: plotterID, name: "Plotter"),
     CameraDevice(id: .init(rawValue: "portrait"), name: "FaceTime"),
     CameraDevice(id: .init(rawValue: "portrait-secondary"), name: "Portrait second camera")]
  }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?,
             eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws
    -> CameraCaptureDriverStartResult
  {
    try await probe.start(role, handler: eventHandler)
    return .init(appliedMaximumFramesPerSecond: maximumFramesPerSecond)
  }
  func stop() async { await probe.stop(role) }
}

private actor WorkbenchCaptureProbe {
  private var frame: StampedFrame?
  private var handlers: [WorkbenchCameraRole: [@Sendable (CameraDriverEvent) -> Void]] = [:]
  private(set) var activeRoles: Set<WorkbenchCameraRole> = []
  private(set) var startedRoles: [WorkbenchCameraRole] = []
  private(set) var maximumActiveCount = 0
  private var held: Set<String> = []
  private var entered: Set<String> = []
  private var releaseWaiters: [String: CheckedContinuation<Void, Never>] = [:]
  private var portraitShouldFail = false

  func setFrame(_ frame: StampedFrame) { self.frame = frame }
  func emit(_ role: WorkbenchCameraRole, timestamp: UInt64, sessionIndex: Int? = nil) {
    guard let frame, let sessions = handlers[role], !sessions.isEmpty else { return }
    let handler = sessions[sessionIndex ?? sessions.count - 1]
    handler(.frame(.init(width: frame.width, height: frame.height, rowBytes: frame.rowBytes,
      bytes: frame.bytes.data, captureNanoseconds: timestamp)))
  }
  func start(_ role: WorkbenchCameraRole, handler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws {
    await suspendIfHeld("\(role.rawValue).start")
    if role == .portrait, portraitShouldFail {
      portraitShouldFail = false
      throw CameraCaptureError.deviceDisconnected(.init(rawValue: "portrait"))
    }
    activeRoles.insert(role)
    startedRoles.append(role)
    handlers[role, default: []].append(handler)
    emit(role, timestamp: UInt64(startedRoles.count))
    maximumActiveCount = max(maximumActiveCount, activeRoles.count)
  }
  func stop(_ role: WorkbenchCameraRole) async {
    await suspendIfHeld("\(role.rawValue).stop")
    activeRoles.remove(role)
  }
  func failNextPortraitStart() { portraitShouldFail = true }
  func hold(_ operation: String) { held.insert(operation); entered.remove(operation) }
  func waitUntilHeld(_ operation: String) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !entered.contains(operation) {
      try #require(ContinuousClock.now < deadline, "Camera fixture never entered held operation \(operation).")
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release(_ operation: String) {
    held.remove(operation)
    releaseWaiters.removeValue(forKey: operation)?.resume()
  }
  private func suspendIfHeld(_ operation: String) async {
    guard held.contains(operation) else { return }
    entered.insert(operation)
    await withCheckedContinuation { releaseWaiters[operation] = $0 }
  }
}
