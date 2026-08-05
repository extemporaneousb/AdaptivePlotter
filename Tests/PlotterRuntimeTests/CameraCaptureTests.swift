import Foundation
import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Camera capture policy and frame delivery")
struct CameraCaptureTests {
  @Test("zero, one, and multiple devices have explicit selection behavior")
  func deviceSelection() async throws {
    let none = TestCameraDriver(devices: [])
    let noCameraCapture = CameraCapture(driver: none)
    await noCameraCapture.discoverDevices()
    #expect(await noCameraCapture.snapshot().error == .noDevices)

    let only = CameraDevice(id: CameraDeviceID(rawValue: "only"), name: "Only Camera")
    let one = TestCameraDriver(devices: [only])
    let oneCameraCapture = CameraCapture(driver: one)
    await oneCameraCapture.discoverDevices()
    #expect(await oneCameraCapture.snapshot().selectedDeviceID == only.id)

    let second = CameraDevice(id: CameraDeviceID(rawValue: "second"), name: "Second Camera")
    let multiple = TestCameraDriver(devices: [second, only])
    let multiCameraCapture = CameraCapture(driver: multiple)
    await multiCameraCapture.discoverDevices()
    #expect(await multiCameraCapture.snapshot().selectedDeviceID == nil)
    await multiCameraCapture.start()
    #expect(
      await multiCameraCapture.snapshot().error == .selectionRequired(availableDeviceCount: 2))
    try await multiCameraCapture.select(second.id)
    #expect(await multiCameraCapture.snapshot().selectedDeviceID == second.id)
  }

  @Test("permission denial is direct and starts no session")
  func permissionDenied() async {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(authorization: .denied, devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    #expect(await capture.snapshot().state == .failed(.permissionDenied))
    #expect(await driver.startCount == 0)
  }

  @Test("interruption, disconnect, and restart remain recoverable and change configuration")
  func lifecycleAndReconfiguration() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let otherDevice = CameraDevice(
      id: CameraDeviceID(rawValue: "other-camera"), name: "Other Camera")
    let driver = TestCameraDriver(devices: [device, otherDevice])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    try await capture.select(device.id)
    await capture.start()
    await driver.emit(sample(value: 10, time: 10))
    try await waitUntil { await capture.snapshot().latestFrame != nil }
    let firstConfiguration = try #require(
      await capture.snapshot().latestFrame?.frame.cameraConfigurationID)

    await capture.stop()
    #expect(await capture.snapshot().state == .stopped)
    await capture.restart()
    await driver.emit(sample(value: 20, time: 20))
    try await waitUntil { await capture.snapshot().latestFrame != nil }
    let restartedConfiguration = try #require(
      await capture.snapshot().latestFrame?.frame.cameraConfigurationID)
    #expect(firstConfiguration != restartedConfiguration)
    #expect(await driver.stopCount >= 1)

    await driver.emit(.interrupted("device busy"))
    try await waitUntil { await capture.snapshot().state == .interrupted("device busy") }
    await driver.emit(.interruptionEnded)
    try await waitUntil { await capture.snapshot().state == .running }
    await driver.emit(.interrupted("device busy again"))
    try await waitUntil { await capture.snapshot().state == .interrupted("device busy again") }
    await capture.restart()
    #expect(await capture.snapshot().state == .running)

    try await capture.select(otherDevice.id)
    await capture.start()
    await driver.emit(sample(value: 30, time: 30))
    try await waitUntil { await capture.snapshot().latestFrame != nil }
    let selectedConfiguration = try #require(
      await capture.snapshot().latestFrame?.frame.cameraConfigurationID)
    #expect(selectedConfiguration != restartedConfiguration)
    #expect(await capture.snapshot().latestFrame?.source == .live(otherDevice.id))

    await driver.emit(.disconnected(otherDevice.id))
    try await waitUntil { await capture.snapshot().error == .deviceDisconnected(otherDevice.id) }
    #expect(await capture.snapshot().latestFrame == nil)
    await capture.restart()
    #expect(await capture.snapshot().state == .running)
  }

  @Test("captured bytes are copied and sequence and timestamps increase")
  func ownedMonotonicFrames() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()

    var bytes = Data(repeating: 7, count: 12)
    await driver.emit(
      .frame(
        CapturedBGRAFrame(
          width: 2, height: 1, rowBytes: 12, bytes: bytes, captureNanoseconds: 50)))
    try await waitUntil { await capture.snapshot().latestFrame?.frame.sequence == 1 }
    bytes[0] = 99
    let first = try #require(await capture.snapshot().latestFrame?.frame)
    #expect(first.bytes[0] == 7)
    #expect(first.rowBytes == 12)

    await driver.emit(sample(value: 8, time: 50))
    try await waitUntil { await capture.snapshot().latestFrame?.frame.sequence == 2 }
    let second = try #require(await capture.snapshot().latestFrame?.frame)
    #expect(second.sequence > first.sequence)
    #expect(second.captureNanoseconds > first.captureNanoseconds)
  }

  @Test("delayed interruption end cannot revive an explicitly stopped generation")
  func delayedInterruptionEndAfterStop() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    await driver.emit(.interrupted("device busy"))
    try await waitUntil { await capture.snapshot().state == .interrupted("device busy") }

    await capture.stop()
    await driver.emitFromStart(0, .interruptionEnded)
    try await settleEvents()
    #expect(await capture.snapshot().state == .stopped)
  }

  @Test("delayed events cannot alter a terminally failed generation")
  func delayedEventsAfterFailure() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    await driver.emit(.failed("capture transport failed"))
    let expected = CameraCaptureState.failed(.captureFailed("capture transport failed"))
    try await waitUntil { await capture.snapshot().state == expected }

    await driver.emitFromStart(0, sample(value: 99, time: 99))
    await driver.emitFromStart(0, .interruptionEnded)
    try await settleEvents()
    #expect(await capture.snapshot().state == expected)
    #expect(await capture.snapshot().latestFrame == nil)
  }

  @Test("a delayed discovery cannot overwrite a newer running generation")
  func delayedDiscoveryDuringStart() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device], delayedDiscoveryCalls: [1])
    let capture = CameraCapture(driver: driver)

    let staleDiscovery = Task { await capture.discoverDevices() }
    try await waitUntil { await driver.discoveryCount == 1 }
    let start = Task { await capture.start() }
    try await waitUntil {
      let snapshot = await capture.snapshot()
      let isActive = await driver.isActive
      return snapshot.state == .running && isActive
    }

    await driver.resumeDiscovery(call: 1)
    await staleDiscovery.value
    await start.value
    #expect(await capture.snapshot().state == .running)
    #expect(await driver.isActive)
  }

  @Test("stop waits out a delayed start and cannot later report running")
  func stopDuringDelayedStart() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device], delayedStartCalls: [1])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()

    let start = Task { await capture.start() }
    try await waitUntil { await driver.startCount == 1 }
    let stop = Task { await capture.stop() }
    try await settleEvents()
    #expect(await capture.snapshot().state == .starting)

    await driver.resumeStart(call: 1)
    await stop.value
    await start.value
    #expect(await capture.snapshot().state == .stopped)
    let isActive = await driver.isActive
    #expect(!isActive)
  }

  @Test("driver events are consumed in callback yield order")
  func orderedDriverEvents() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()

    await driver.emitBatch([
      sample(value: 1, time: 1),
      .interrupted("device busy"),
      sample(value: 2, time: 2),
      .interruptionEnded,
      sample(value: 3, time: 3),
    ])
    try await waitUntil {
      let snapshot = await capture.snapshot()
      return snapshot.state == .running && snapshot.latestFrame?.frame.bytes[0] == 3
    }
    #expect(await capture.snapshot().latestFrame?.frame.sequence == 2)

    await driver.emitBatch([
      .interruptionEnded,
      .interrupted("late interruption"),
      sample(value: 4, time: 4),
    ])
    try await waitUntil {
      await capture.snapshot().state == .interrupted("late interruption")
    }
    #expect(await capture.snapshot().latestFrame?.frame.bytes[0] == 3)
    #expect(await capture.snapshot().latestFrame?.frame.sequence == 2)

    await driver.emitBatch([.interruptionEnded, sample(value: 5, time: 5)])
    try await waitUntil {
      let snapshot = await capture.snapshot()
      return snapshot.state == .running && snapshot.latestFrame?.frame.bytes[0] == 5
    }
    #expect(await capture.snapshot().latestFrame?.frame.sequence == 3)
  }

  @Test("blocked event consumption coalesces frame bursts without dropping controls")
  func boundedOrderedEventMailbox() async throws {
    let mailbox = CameraDriverEventMailbox()

    for value in UInt8(1)...UInt8(100) {
      mailbox.yield(sample(value: value, time: UInt64(value)))
    }
    mailbox.yield(.interrupted("device busy"))
    for value in UInt8(101)...UInt8(200) {
      mailbox.yield(sample(value: value, time: UInt64(value)))
    }
    mailbox.yield(.interruptionEnded)
    for value in UInt8(201)...UInt8(250) {
      mailbox.yield(sample(value: value, time: UInt64(value)))
    }
    mailbox.yield(.failed("terminal capture failure"))

    let blocked = mailbox.diagnostics()
    #expect(blocked.pendingEventCount == 6)
    #expect(blocked.pendingFrameCount == 3)
    #expect(blocked.maximumPendingFrameCount == 3)

    guard case .frame(let first)? = await mailbox.next() else {
      Issue.record("Expected newest frame from the first burst")
      return
    }
    #expect(try first.materializedBytes()[0] == 100)
    guard case .interrupted(let interruption)? = await mailbox.next() else {
      Issue.record("Expected interruption after the first frame burst")
      return
    }
    #expect(interruption == "device busy")
    guard case .frame(let second)? = await mailbox.next() else {
      Issue.record("Expected newest frame from the interrupted burst")
      return
    }
    #expect(try second.materializedBytes()[0] == 200)
    guard case .interruptionEnded? = await mailbox.next() else {
      Issue.record("Expected interruption end in callback order")
      return
    }
    guard case .frame(let third)? = await mailbox.next() else {
      Issue.record("Expected newest frame from the final burst")
      return
    }
    #expect(try third.materializedBytes()[0] == 250)
    guard case .failed(let failure)? = await mailbox.next() else {
      Issue.record("Expected terminal failure after the final frame burst")
      return
    }
    #expect(failure == "terminal capture failure")

    #expect(mailbox.diagnostics().pendingEventCount == 0)
    mailbox.finish()
    if await mailbox.next() != nil {
      Issue.record("Expected a finished mailbox to return nil")
    }
  }

  @Test("slow frame consumer receives only the newest buffered frame")
  func newestFrameBackpressure() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(driver: driver)
    await capture.discoverDevices()
    await capture.start()
    let stream = await capture.frames()

    for value in UInt8(1)...UInt8(3) {
      await driver.emit(sample(value: value, time: UInt64(value)))
      try await waitUntil {
        await capture.snapshot().latestFrame?.frame.sequence == UInt64(value)
      }
    }
    var iterator = stream.makeAsyncIterator()
    let newest = await iterator.next()
    #expect(newest?.frame.sequence == 3)
    #expect(newest?.frame.bytes[0] == 3)
  }

  @Test("preview materialization is bounded while exact latest-frame capture remains available")
  func boundedPreviewAndExactMaterialization() async throws {
    let device = CameraDevice(id: CameraDeviceID(rawValue: "camera"), name: "Camera")
    let driver = TestCameraDriver(devices: [device])
    let capture = CameraCapture(
      driver: driver,
      materializationPolicy: LiveFrameMaterializationPolicy(
        minimumPreviewIntervalNanoseconds: 100
      )
    )
    await capture.discoverDevices()
    await capture.start()

    await driver.emit(sample(value: 1, time: 100))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 1 }
    let firstPreview = try #require(await capture.snapshot().latestFrame)
    #expect(firstPreview.frame.sequence == 1)
    #expect(await capture.diagnostics().materializedFrameCount == 1)

    await driver.emit(sample(value: 2, time: 120))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 2 }
    await driver.emit(sample(value: 3, time: 150))
    try await waitUntil { await capture.diagnostics().receivedFrameCount == 3 }
    #expect(await capture.snapshot().latestFrame?.frame.id == firstPreview.frame.id)
    #expect(await capture.diagnostics().materializedFrameCount == 1)

    let exact = try #require(
      try await capture.materializeLatestFrame(newerThanNanoseconds: 100)
    )
    #expect(exact.frame.sequence == 3)
    #expect(exact.frame.captureNanoseconds == 150)
    #expect(exact.frame.bytes[0] == 3)
    #expect(await capture.diagnostics().materializedFrameCount == 2)

    let repeated = try #require(try await capture.materializeLatestFrame())
    #expect(repeated.frame.id == exact.frame.id)
    #expect(await capture.diagnostics().materializedFrameCount == 2)
    #expect(try await capture.materializeLatestFrame(newerThanNanoseconds: 150) == nil)
  }

  @Test("simulator emits the same displayed-frame contract with a known transform")
  func simulatorContract() throws {
    let transform = try AffineTransform2<FieldSpace, CameraPixelSpace>(
      m11: 2, m12: 0, m21: 0, m22: 2, tx: 1, ty: 3)
    var simulator = try SimulatedFrameSource(
      width: 20,
      height: 20,
      fieldToCamera: transform
    )
    let fieldLine = try Polyline<FieldSpace>(
      points: [try Point2(x: 1, y: 1), try Point2(x: 4, y: 1)])
    let cameraLine = try simulator.cameraPolyline(from: fieldLine)
    let displayed = try simulator.render(
      strokes: [SimulatedCameraStroke(start: cameraLine.start, end: cameraLine.end)],
      captureNanoseconds: 10
    )
    #expect(displayed.source == .simulated)
    #expect(displayed.frame.pixelFormat == .bgra8)
    #expect(cameraLine.start == (try Point2<CameraPixelSpace>(x: 3, y: 5)))
  }
}

private typealias TestCameraEventHandler = @Sendable (CameraDriverEvent) -> Void

private actor TestCameraDriver: CameraCaptureDriver {
  var authorization: CameraAuthorizationState
  var devices: [CameraDevice]
  var requestAccessResult: Bool
  private let delayedDiscoveryCalls: Set<Int>
  private let delayedStartCalls: Set<Int>
  private var discoveryContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var startContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var eventHandler: TestCameraEventHandler?
  private var startHandlers: [TestCameraEventHandler] = []
  private(set) var discoveryCount = 0
  private(set) var startCount = 0
  private(set) var stopCount = 0
  private(set) var isActive = false

  init(
    authorization: CameraAuthorizationState = .authorized,
    devices: [CameraDevice],
    requestAccessResult: Bool = true,
    delayedDiscoveryCalls: Set<Int> = [],
    delayedStartCalls: Set<Int> = []
  ) {
    self.authorization = authorization
    self.devices = devices
    self.requestAccessResult = requestAccessResult
    self.delayedDiscoveryCalls = delayedDiscoveryCalls
    self.delayedStartCalls = delayedStartCalls
  }

  func authorizationState() async -> CameraAuthorizationState { authorization }
  func requestAccess() async -> Bool { requestAccessResult }
  func discoverDevices() async -> [CameraDevice] {
    discoveryCount += 1
    let call = discoveryCount
    if delayedDiscoveryCalls.contains(call) {
      await withCheckedContinuation { continuation in
        discoveryContinuations[call] = continuation
      }
    }
    return devices
  }

  func start(
    deviceID: CameraDeviceID,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void
  ) async throws {
    guard devices.contains(where: { $0.id == deviceID }) else {
      throw CameraCaptureError.unknownDevice(deviceID)
    }
    startCount += 1
    let call = startCount
    startHandlers.append(eventHandler)
    if delayedStartCalls.contains(call) {
      await withCheckedContinuation { continuation in
        startContinuations[call] = continuation
      }
    }
    self.eventHandler = eventHandler
    isActive = true
  }

  func stop() async {
    stopCount += 1
    eventHandler = nil
    isActive = false
  }

  func emit(_ event: CameraDriverEvent) {
    eventHandler?(event)
  }

  func emitFromStart(_ index: Int, _ event: CameraDriverEvent) {
    guard startHandlers.indices.contains(index) else { return }
    startHandlers[index](event)
  }

  func emitBatch(_ events: [CameraDriverEvent]) {
    guard let eventHandler else { return }
    for event in events { eventHandler(event) }
  }

  func resumeDiscovery(call: Int) {
    discoveryContinuations.removeValue(forKey: call)?.resume()
  }

  func resumeStart(call: Int) {
    startContinuations.removeValue(forKey: call)?.resume()
  }
}

private func sample(value: UInt8, time: UInt64) -> CameraDriverEvent {
  .frame(
    CapturedBGRAFrame(
      width: 1,
      height: 1,
      rowBytes: 4,
      bytes: Data(repeating: value, count: 4),
      captureNanoseconds: time
    ))
}

private func waitUntil(
  attempts: Int = 200,
  condition: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    try await Task.sleep(nanoseconds: 1_000_000)
  }
  Issue.record("condition was not satisfied before the test deadline")
}

private func settleEvents() async throws {
  try await Task.sleep(nanoseconds: 10_000_000)
}
