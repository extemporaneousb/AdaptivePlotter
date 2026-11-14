import Foundation
import DrawingLibrary
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Flow authoring camera readiness and reuse", .serialized)
@MainActor
struct FlowAuthoringCameraTests {
  @Test("Delayed first frames and a second portfolio capture reuse one camera session and save distinct originals")
  func repeatedCapture() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let driver = AuthoringCameraDriver()
    let capture = CameraCapture(driver: driver)
    let camera = PortraitStudioModel(camera: capture, library: DrawingLibrary(directoryURL: directory.appendingPathComponent("camera")), photoAcquirer: AuthoringPhotoAcquirer())
    let authoring = FlowAuthoringModel(directory: directory.appendingPathComponent("portfolio"), purpose: .validationFixture)
    do {
      await camera.discover(excluding: nil)
      #expect(camera.selectedDeviceID == nil && !camera.cameraIsRunning)
      #expect(await driver.starts == 0)
      camera.selectedDeviceID = try #require(camera.devices.first?.id)
      await camera.startCamera()
      let pen = authoring.strokeStyle
      let first = try #require(await camera.captureForPortfolio(strokeStyle: pen))
      await authoring.open(); await authoring.addCapturedPhoto(first, title: authoring.nextPhotoTitle(capturedAt: first.capturedAt))
      await camera.startCamera() // Exact callback used by the standalone capture surface.
      let second = try #require(await camera.captureForPortfolio(strokeStyle: pen))
      await authoring.addCapturedPhoto(second, title: authoring.nextPhotoTitle(capturedAt: second.capturedAt))
      #expect(await driver.starts == 1)
      #expect(second.captureNanoseconds! > first.captureNanoseconds!)
      #expect(second.id != first.id && second.data != first.data)
      #expect(authoring.document?.sources.count == 2)
      let source = try #require(authoring.document?.sources.first)
      #expect(source.captureProvenance?.photoID == first.id)
      #expect(source.captureProvenance?.frameID == first.frameID)
      #expect(source.captureProvenance?.captureNanoseconds == first.captureNanoseconds)
      #expect(source.captureProvenance?.captureSessionID == first.captureSessionID)
      #expect(source.captureProvenance?.selectionProvenance == first.selectionProvenance)
      #expect(source.captureProvenance?.imageSHA256 == source.image.sha256)
      let firstID = try #require(authoring.document?.sources.first?.id)
      #expect(try await authoring.store?.sourceData(firstID) == first.data)
      let before = await capture.snapshot().diagnostics
      for _ in 0..<20 { _ = await capture.latestCaptureNanoseconds() }
      let after = await capture.snapshot().diagnostics
      #expect(after.returnOnlyExactRequestCount == before.returnOnlyExactRequestCount)
      #expect(after.exactContentHashComputationCount == before.exactContentHashComputationCount)
      await camera.stopCamera()
      #expect(!camera.cameraIsRunning && camera.preview.frame == nil && !camera.screenIlluminationActive)
      await camera.shutdown(); await authoring.shutdown()
    } catch { await camera.shutdown(); await authoring.shutdown(); throw error }
  }

  @Test("A stalled stream times out before illumination and cancellation can be retried")
  func stalledAndCancelled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let clock = AuthoringAdvancingClock(), frames = AuthoringMetadataFrames(stalled: true)
    let camera = PortraitStudioModel(library: DrawingLibrary(directoryURL: directory), photoAcquirer: AuthoringPhotoAcquirer(), frameSource: frames, captureClock: clock)
    let pen = FlowAuthoringModel(directory: directory.appendingPathComponent("unused")).strokeStyle
    #expect(await camera.captureForPortfolio(strokeStyle: pen) == nil)
    #expect(camera.cameraStatus?.contains("fresh video") == true)
    #expect(!camera.screenIlluminationActive && !camera.isCapturing)
    #expect(await frames.materializations == 0)
    await frames.resume()
    #expect(await camera.captureForPortfolio(strokeStyle: pen) != nil)
    #expect(camera.cameraStatus == nil)
    await camera.shutdown()

    let afterReady = AuthoringMetadataFrames(stalled: false, stallAfterReadiness: true)
    let interrupted = PortraitStudioModel(library: DrawingLibrary(directoryURL: directory.appendingPathComponent("interrupted")), photoAcquirer: AuthoringPhotoAcquirer(), frameSource: afterReady, captureClock: AuthoringAdvancingClock())
    #expect(await interrupted.captureForPortfolio(strokeStyle: pen) == nil)
    #expect(interrupted.cameraStatus?.contains("Restart Camera") == true)
    #expect(interrupted.cameraStatus?.contains("after the face video appears") != true)
    await interrupted.shutdown()

    let waiting = PortraitStudioModel(library: DrawingLibrary(directoryURL: directory.appendingPathComponent("cancelled")), frameSource: AuthoringMetadataFrames(stalled: true))
    let task = Task { await waiting.captureForPortfolio(strokeStyle: pen) }
    try await Task.sleep(for: .milliseconds(80))
    #expect(waiting.isCapturing && !waiting.screenIlluminationActive)
    await waiting.cancelRendering()
    #expect(await task.value == nil)
    #expect(!waiting.isCapturing && waiting.capturePhase == nil)
    await waiting.shutdown()
  }

  @Test("Exposure boundaries never materialize pixels and held encoding cannot extend illumination")
  func cheapBoundaryAndBoundedLight() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let frames = AuthoringMetadataFrames(stalled: false), acquirer = AuthoringHeldAcquirer()
    let camera = PortraitStudioModel(library: DrawingLibrary(directoryURL: directory), photoAcquirer: acquirer, frameSource: frames)
    let pen = FlowAuthoringModel(directory: directory.appendingPathComponent("unused")).strokeStyle
    let task = Task { await camera.captureForPortfolio(strokeStyle: pen) }
    for _ in 0..<100 {
      if await acquirer.entered { break }
      try await Task.sleep(for: .milliseconds(20))
    }
    #expect(await acquirer.entered)
    #expect(await frames.zeroBoundaryMaterializations == 0)
    try await Task.sleep(for: .milliseconds(850))
    #expect(camera.isCapturing && !camera.screenIlluminationActive)
    await acquirer.release()
    #expect(await task.value != nil)
    #expect(!camera.screenIlluminationActive)
    await camera.shutdown()
  }
}

private actor AuthoringCameraDriver: CameraCaptureDriver {
  private(set) var starts = 0
  private var frames: Task<Void, Never>?
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] { [.init(id: .init(rawValue: "authoring-camera"), name: "Delayed test camera")] }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?, eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws -> CameraCaptureDriverStartResult {
    starts += 1
    frames = Task {
      do { try await Task.sleep(for: .milliseconds(900)) } catch { return }
      var stamp: UInt64 = 1
      while !Task.isCancelled {
        eventHandler(.frame(.init(width: 2, height: 2, rowBytes: 8,
          bytes: Data(repeating: UInt8(stamp % 255), count: 16), captureNanoseconds: stamp)))
        stamp += 1
        do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
      }
    }
    return .init(appliedMaximumFramesPerSecond: maximumFramesPerSecond)
  }
  func stop() async { let old = frames; frames = nil; old?.cancel(); await old?.value }
}
private actor AuthoringPhotoAcquirer: PortraitPhotoAcquiring {
  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto {
    guard case .frame(let frame) = input else { throw CocoaError(.fileReadUnsupportedScheme) }
    return .init(data: FlowAuthoringFixture.image(Int(frame.captureNanoseconds % 250)), sourcePixelExtent: nil)
  }
}
private actor AuthoringAdvancingClock: PortraitCaptureClock {
  var time = 0.0
  func now() -> TimeInterval { time }
  func sleep(seconds: TimeInterval) async throws { try Task.checkCancellation(); time = max(time.nextUp, time + seconds); await Task.yield() }
}
private actor AuthoringMetadataFrames: PortraitFrameAcquiring {
  var stalled: Bool
  var timestamp: UInt64 = 1
  private(set) var materializations = 0
  private(set) var zeroBoundaryMaterializations = 0
  private let stallAfterReadiness: Bool
  private var metadataReads = 0
  init(stalled: Bool, stallAfterReadiness: Bool = false) { self.stalled = stalled; self.stallAfterReadiness = stallAfterReadiness }
  func resume() { stalled = false }
  func latestCaptureNanoseconds() -> UInt64? {
    metadataReads += 1
    if stallAfterReadiness && metadataReads >= 3 { stalled = true }
    if !stalled { timestamp += 1 }
    return timestamp
  }
  func latestFrame(newerThanNanoseconds boundary: UInt64) throws -> StampedFrame? {
    materializations += 1
    if boundary == 0 { zeroBoundaryMaterializations += 1 }
    guard !stalled else { return nil }
    timestamp = max(timestamp + 1, boundary + 1)
    return try StampedFrame(sequence: timestamp, captureNanoseconds: timestamp,
      cameraConfigurationID: CameraConfigurationID(), width: 2, height: 2, rowBytes: 8,
      pixelFormat: .bgra8, bytes: OwnedFrameBytes(copying: Data(repeating: UInt8(timestamp % 255), count: 16)))
  }
}
private actor AuthoringHeldAcquirer: PortraitPhotoAcquiring {
  private(set) var entered = false
  private var continuation: CheckedContinuation<Void, Never>?
  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto {
    entered = true
    await withCheckedContinuation { continuation = $0 }
    return .init(data: FlowAuthoringFixture.image(7), sourcePixelExtent: nil)
  }
  func release() { continuation?.resume(); continuation = nil }
}
