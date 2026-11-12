@testable import PortraitStudioUI
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Plotter camera lifecycle without embedded authoring")
@MainActor
struct WorkbenchCameraLifecycleTests {
  @Test("Portrait requests refuse before touching the selected Plotter capture")
  func portraitRequestsPreservePlotter() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    let before = await fixture.runtime.reference()
    for _ in 0..<20 {
      #expect(await fixture.select(.portrait) == .refused("Photo capture belongs to Portrait Studio."))
    }
    #expect(await fixture.runtime.reference() == before)
    #expect(await fixture.probe.startedRoles == [.plotter])
    #expect(await fixture.probe.activeRoles == [.plotter])
    #expect(await fixture.runtime.workbenchCameraSnapshot() == .init(role: .plotter))
    await fixture.runtime.shutdown()
    #expect(await fixture.probe.activeRoles.isEmpty)
  }

  @Test("Selecting the settled Plotter capture preserves its configuration")
  func repeatedSettledRoleIsNoOp() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    let before = await fixture.runtime.reference()
    for _ in 0..<5 { _ = await fixture.select(.plotter) }
    #expect(await fixture.runtime.reference() == before)
    #expect(await fixture.probe.startedRoles == [.plotter])
    await fixture.runtime.shutdown()
  }

  @Test("Shutdown joins a noncooperative Plotter restart and closes later source requests")
  func shutdownDuringHeldRestart() async throws {
    let fixture = await WorkbenchCameraFixture.make()
    await fixture.probe.hold("plotter.start")
    let restart = Task { await fixture.runtime.submit(.init(reference: await fixture.runtime.reference(), intent: .restartLiveSource)) }
    try await fixture.probe.waitUntilHeld("plotter.start")
    let before = await fixture.runtime.reference()
    let shutdown = Task { await fixture.runtime.shutdown() }
    try await awaitCameraTestState { await fixture.runtime.reference().revision != before.revision }
    #expect(await fixture.select(.plotter) == .refused("Observation configuration is shut down."))
    await fixture.probe.release("plotter.start")
    _ = await restart.value
    await shutdown.value
    #expect(await fixture.probe.activeRoles.isEmpty)
    #expect(await fixture.probe.maximumActiveCount == 1)
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
  let session: CameraSourceSession
  let runtime: PlotterObservationConfigurationRuntime

  static func make() async -> Self {
    let probe = WorkbenchCaptureProbe()
    let live = CameraCapture(driver: WorkbenchCaptureDriver(role: .plotter, probe: probe))
    let vision = VisionWorker()
    let session = CameraSourceSession(live: live, vision: vision,
      analysisPipeline: PlotterSceneAnalysisPipeline(worker: vision), plannedDrawingObserver: vision)
    let runtime = PlotterObservationConfigurationRuntime(lower: session)
    _ = await runtime.submit(.init(reference: await runtime.reference(), intent: .refreshSources))
    _ = await runtime.submit(.init(reference: await runtime.reference(),
                                  intent: .selectLiveSource(.init(rawValue: "plotter"))))
    _ = await runtime.submit(.init(reference: await runtime.reference(), intent: .startLiveSource))
    return Self(probe: probe, session: session, runtime: runtime)
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
