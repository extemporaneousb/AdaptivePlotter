import Foundation
import PlotterModel
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Holder reference across actual camera generations")
struct HolderCameraSessionTests {
  @Test("restored reference reaches real exact, stable and ambient matchers after CameraCapture restart")
  func actualRestart() async throws {
    let device = CameraDevice(id: .init(rawValue: "holder-session-camera"), name: "Holder fixture")
    let driver = HolderSessionDriver(device: device)
    let capture = CameraCapture(driver: driver)
    let worker = VisionWorker()
    let pipeline = PlotterSceneAnalysisPipeline(worker: worker)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("holder-acquisition-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = TrackingAcquisitionEvidenceRecorder(directory: directory)
    let session = CameraSourceSession(live: capture, vision: worker, analysisPipeline: pipeline,
      plannedDrawingObserver: worker, trackingEvidenceRecorder: recorder)
    _ = await session.discover()
    _ = await session.start()
    await driver.emit(origin: 12, time: 100)
    try await waitFor { await capture.snapshot().latestFrame?.frame.captureNanoseconds == 100 }
    let acquisition = try #require(try await session.captureFrame(newerThanNanoseconds: 0))
    let optical = try CameraOpticalConfigurationIdentity(source: acquisition.source,
      sensorFormat: "144x96-BGRA", width: 144, height: 96, pixelFormat: .bgra8,
      orientation: .up, mirrored: false, digitalZoomFactor: 1, lensIdentity: "fixed",
      focusConfiguration: "fixed", mountRevision: UUID(), reframingRevision: UUID())
    let reference = try PenCapVisualReference.capture(frame: acquisition.frame,
      region: PixelRect(x: 12, y: 16, width: 28, height: 24), anchor: Point2(x: 16, y: 35),
      purpose: .rigidHolder, opticalConfiguration: optical)
    let saved = try JSONEncoder().encode(reference)
    let restored = try JSONDecoder().decode(PenCapVisualReference.self, from: saved)
    await session.setTrackingOpticalConfiguration(optical)
    await session.setPenCapReference(restored)
    let first = try #require(try await session.inspectWorkflowScene(newerThanNanoseconds: 0,
      requestedFeatures: [.penCap], analysisRegion: nil))
    #expect(first.measurement.penCap.measurement != nil)

    _ = await session.restart()
    await driver.emit(origin: 100, time: 200)
    try await waitFor { await capture.snapshot().latestFrame?.frame.captureNanoseconds == 200 }
    let restarted = try #require(try await session.inspectWorkflowScene(newerThanNanoseconds: 100,
      requestedFeatures: [.penCap], analysisRegion: nil))
    #expect(restarted.displayedFrame.frame.cameraConfigurationID != acquisition.frame.cameraConfigurationID)
    let observed = try #require(restarted.measurement.penCap.measurement)
    #expect(abs(observed.trackingPoint.x - 104) < 1.5)
    #expect(restored.identity == reference.identity)
    #expect(restored.cameraConfigurationID == acquisition.frame.cameraConfigurationID)

    // The production pipeline receives the same semantic optics through the
    // session setter, and performs its own binding against this exact frame.
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    await pipeline.submit(restarted.displayedFrame)
    try await waitFor { await pipeline.snapshot().latestResult != nil }
    let ambient = try #require(await pipeline.snapshot().latestResult)
    #expect(ambient.measurement.penCap.measurement != nil)
    #expect(ambient.measurement.cameraConfigurationID == restarted.measurement.cameraConfigurationID)
    await pipeline.stop()

    let stableTask = Task { try await session.captureStableWorkflowCap(.init(newerThanNanoseconds: 200)) }
    try await waitFor { await session.visionDiagnostics().activeExclusiveLeaseCount == 1 }
    for time in [UInt64(300), 400, 500] {
      let before = await capture.diagnostics().returnOnlyExactRequestCount
      await driver.emit(origin: 100, time: time)
      try await waitFor { await capture.diagnostics().returnOnlyExactRequestCount > before }
    }
    let stable = try await stableTask.value
    #expect(stable.inspection.displayedFrame.frame.captureNanoseconds == 500)
    #expect(await session.visionDiagnostics().activeExclusiveLeaseCount == 0)
    try await waitFor {
      let entries = (try? FileManager.default.contentsOfDirectory(at: directory,
        includingPropertiesForKeys: nil)) ?? []
      return entries.contains { $0.lastPathComponent.hasPrefix("acquisition-") }
    }
    let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    let manifestURL = try #require(entries.first { $0.lastPathComponent.hasPrefix("acquisition-") })
      .appendingPathComponent("manifest.json")
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(TrackingAcquisitionEvidence.self, from: Data(contentsOf: manifestURL))
    #expect(manifest.referenceIdentity == restored.identity)
    #expect(manifest.phase == .success)
    #expect(manifest.camera.frameID == stable.inspection.displayedFrame.frame.id)

    let changed = try CameraOpticalConfigurationIdentity(source: optical.source,
      sensorFormat: optical.sensorFormat, width: 144, height: 96, pixelFormat: .bgra8,
      orientation: .up, mirrored: true, digitalZoomFactor: 1, lensIdentity: "fixed",
      focusConfiguration: "fixed", mountRevision: optical.mountRevision, reframingRevision: optical.reframingRevision)
    await session.setTrackingOpticalConfiguration(changed)
    let rejected = try #require(try await session.inspectWorkflowScene(newerThanNanoseconds: 0,
      requestedFeatures: [.penCap], analysisRegion: nil))
    #expect(rejected.measurement.penCap.measurement == nil)
    _ = await session.stop()
  }

  private func waitFor(_ predicate: @escaping @Sendable () async -> Bool) async throws {
    for _ in 0..<300 {
      if await predicate() { return }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for the real camera/matcher pipeline")
    throw HolderSessionTestError.timeout
  }
}

private enum HolderSessionTestError: Error { case timeout }

private actor HolderSessionDriver: CameraCaptureDriver {
  let device: CameraDevice
  private var handler: (@Sendable (CameraDriverEvent) -> Void)?
  init(device: CameraDevice) { self.device = device }
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] { [device] }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws -> CameraCaptureDriverStartResult {
    handler = eventHandler
    return .init(appliedMaximumFramesPerSecond: nil)
  }
  func stop() async { handler = nil }
  func emit(origin: Int, time: UInt64) {
    let width = 144, height = 96
    var bytes = [UInt8](repeating: 220, count: width * height * 4)
    for y in 0..<24 { for x in 0..<28 {
      let rgb: [UInt8]
      if x < 7 && y > 8 { rgb = [135, 15, 20] }
      else if x > 17 && y < 17 { rgb = [25, 65, 145] }
      else if (x > 10 && x < 14) || y < 3 { rgb = [170, 165, 160] }
      else { rgb = [12, 12, 14] }
      let i = ((16 + y) * width + origin + x) * 4
      bytes[i] = rgb[2]; bytes[i + 1] = rgb[1]; bytes[i + 2] = rgb[0]; bytes[i + 3] = 255
    } }
    handler?(.frame(.init(width: width, height: height, rowBytes: width * 4,
      bytes: Data(bytes), captureNanoseconds: time)))
  }
}
