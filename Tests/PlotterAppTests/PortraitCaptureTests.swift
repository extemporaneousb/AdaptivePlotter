import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Portrait photo capture and recent sources")
struct PortraitCaptureTests {
  @Test("short still capture samples unique post-settling frames and retains one original source")
  @MainActor
  func burstRetention() async throws {
    let clock = AdvancingPortraitClock()
    let source = try RepeatingPortraitFrames()
    let acquirer = BurstPhotoAcquirer()
    let renderer = BurstRenderer()
    let model = PortraitStudioModel(renderer: renderer, photoAcquirer: acquirer,
      frameSource: source, captureClock: clock,
      photoRetention: .init(maximumCount: 5, maximumBytes: 10))
    await model.capture(strokeStyle: try portraitTestStyle())
    #expect(abs(await clock.now() - 0.8) < 0.000_001)
    #expect(await clock.sleeps.first == 0.25)
    let metric = try PortraitSourceCropExtent(widthPixels: 901, heightPixels: 1600)
    #expect(model.recentPhotos.allSatisfy { $0.sourcePixelExtent == metric })
    #expect(await renderer.sourcePixelExtents.last == metric)
    #expect(model.recentPhotos.count == 1)
    #expect(model.retainedPhotoBytes == 2)
    let stamps = model.recentPhotos.compactMap(\.captureNanoseconds)
    #expect(stamps == [4])
    #expect(await acquirer.capturedTimestamps == [2, 3, 4])
    // The mock returns opaque bytes, so capture must disclose fallback selection.
    #expect(model.recentPhotos.first?.selectionProvenance?.method == .latestAvailable)
    #expect(model.recentPhotos.first?.selectionProvenance?.capturedFrameCount == 3)
    #expect(model.selectedPhotoID == model.recentPhotos.last?.id)
    #expect(!model.isCapturing)
    #expect(!model.screenIlluminationActive)
    #expect(model.captureProgress == 1)
    #expect(model.acquisitionDiagnostics.startedWorkerCount == 1)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.program != nil)
  }

  @Test("photo deletion retains a separate import and the saved drawing's source")
  @MainActor
  func groupedBurstDeletion() async throws {
    let model = PortraitStudioModel(renderer: BurstRenderer(), photoAcquirer: BurstPhotoAcquirer(),
      frameSource: try RepeatingPortraitFrames(), captureClock: AdvancingPortraitClock())
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    await model.importPhoto(URL(fileURLWithPath: "/tmp/99"), strokeStyle: pen)
    let imported = try #require(model.recentPhotos.first)
    await model.capture(strokeStyle: pen)
    let burst = try #require(model.recentPhotos.last?.captureSessionID)
    #expect(model.recentPhotos.filter { $0.captureSessionID == burst }.count == 1)
    let retained = try #require(model.selectedCandidate)
    #expect(model.keepSelection() == nil)
    model.removePhoto(try #require(model.selectedPhotoID), strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.recentPhotos.map(\.id) == [imported.id])
    #expect(model.selectedPhotoID == imported.id)
    #expect(model.algorithmCandidates.allSatisfy { $0.photoID == imported.id })
    #expect(model.sketches.sketches.map(\.id) == [retained.id])
    #expect(model.sketches.sketches.first?.candidate.sourceData == retained.sourceData)
    await model.shutdown()
  }

  @Test("recent imports are bounded by both count and bytes and deletion selects a surviving source")
  @MainActor
  func importRetentionAndSelection() async throws {
    let model = PortraitStudioModel(renderer: BurstRenderer(), photoAcquirer: BurstPhotoAcquirer(),
      photoRetention: .init(maximumCount: 3, maximumBytes: 4))
    let style = try portraitTestStyle()
    for value in 1...4 {
      await model.importPhoto(URL(fileURLWithPath: "/tmp/\(value)"), strokeStyle: style)
    }
    #expect(model.recentPhotos.map(\.data) == [Data([3, 3]), Data([4, 4])])
    #expect(model.retainedPhotoBytes == 4)
    let first = try #require(model.recentPhotos.first?.id)
    model.selectPhoto(first, strokeStyle: style)
    await model.awaitRendering()
    #expect(model.selectedPhoto == Data([3, 3]))
    model.removePhoto(first, strokeStyle: style)
    #expect(model.selectedPhoto == Data([4, 4]))
    // The exact cached drawing is prepared asynchronously before publication.
    #expect(model.program == nil)
    #expect(model.isProcessing)
    await model.awaitRendering()
    #expect(model.program != nil)
    #expect(!model.isProcessing)
    let last = try #require(model.selectedPhotoID)
    model.removePhoto(last, strokeStyle: style)
    #expect(model.selectedPhoto == nil)
    #expect(model.program == nil)
    #expect(model.recentPhotos.isEmpty)
  }

  @Test("deleting a source during uninterruptible rendering cannot resurrect its image or vectors")
  @MainActor
  func deleteDuringRender() async throws {
    let renderer = try PausedBurstRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let style = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: style)
    try await renderer.waitUntilEntered()
    model.removePhoto(try #require(model.selectedPhotoID), strokeStyle: style)
    #expect(model.program == nil)
    #expect(!model.isProcessing)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.recentPhotos.isEmpty)
    #expect(model.selectedPhoto == nil)
    #expect(model.program == nil)
    #expect(model.renderDiagnostics.activeWorkerCount == 0)
  }

  @Test("cancelling a lit burst discards held encoding and turns off illumination before it settles")
  @MainActor
  func cancelHeldBurst() async throws {
    let acquirer = PausedBurstAcquirer()
    let model = PortraitStudioModel(renderer: BurstRenderer(), photoAcquirer: acquirer,
      frameSource: try RepeatingPortraitFrames(), captureClock: AdvancingPortraitClock())
    let capture = Task { await model.capture(strokeStyle: try! portraitTestStyle()) }
    try await acquirer.waitUntilEntered()
    #expect(model.isCapturing)
    #expect(model.screenIlluminationActive)
    var cancellationReturned = false
    let cancel = Task { await model.cancelRendering(); cancellationReturned = true }
    try await waitForBurstState { !model.isCapturing }
    #expect(!model.screenIlluminationActive)
    #expect(!cancellationReturned)
    await acquirer.release()
    await cancel.value
    await capture.value
    #expect(model.recentPhotos.isEmpty)
    #expect(model.program == nil)
    #expect(model.acquisitionDiagnostics.activeWorkerCount == 0)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
  }

  @Test("capture light expires while encoding is held and later worker progress cannot relight it")
  @MainActor
  func lightDeadlineDuringHeldEncoding() async throws {
    let acquirer = PausedBurstAcquirer()
    let model = PortraitStudioModel(renderer: BurstRenderer(), photoAcquirer: acquirer,
      frameSource: try RepeatingPortraitFrames(), captureClock: AdvancingPortraitClock())
    let style = try portraitTestStyle()
    let capture = Task { await model.capture(strokeStyle: style) }
    try await acquirer.waitUntilEntered()
    #expect(model.screenIlluminationActive)
    try await waitForBurstState { !model.screenIlluminationActive }
    #expect(model.isCapturing)
    #expect(model.captureProgress == 1)
    #expect(model.acquisitionDiagnostics.activeWorkerCount == 1)
    // Resume one sample, then hold the next. Progress from the resumed sample
    // must leave the expired light off while the capture worker remains active.
    await acquirer.release()
    try await acquirer.waitUntilEntered(after: 1)
    #expect(!model.screenIlluminationActive)
    #expect(model.captureProgress == 1)
    let cancellation = Task { await model.cancelRendering() }
    try await waitForBurstState { !model.isCapturing }
    await acquirer.release()
    await cancellation.value
    await capture.value
    #expect(model.recentPhotos.isEmpty)
    #expect(model.acquisitionDiagnostics.activeWorkerCount == 0)
    #expect(!model.screenIlluminationActive)
  }

  @Test("capture remains short while oversized photos cannot evict retained sources")
  @MainActor
  func captureAndMemoryBounds() async throws {
    let clock = AdvancingPortraitClock()
    let model = PortraitStudioModel(renderer: BurstRenderer(), photoAcquirer: BurstPhotoAcquirer(),
      frameSource: try RepeatingPortraitFrames(), captureClock: clock,
      photoRetention: .init(maximumCount: 3, maximumBytes: 4))
    await model.capture(strokeStyle: try portraitTestStyle())
    #expect(abs(await clock.now() - 0.8) < 0.000_001)
    let selected = model.selectedPhotoID
    model.setPhoto(Data(repeating: 0, count: 100), for: .front, strokeStyle: try portraitTestStyle())
    #expect(model.selectedPhotoID == selected)
    #expect(model.retainedPhotoBytes <= 4)
  }

  @Test("folded vector edits reuse the selected raster while analysis edits invalidate it")
  @MainActor
  func selectedRasterCache() async throws {
    let renderer = BurstRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let style = try portraitTestStyle()
    #expect(!model.isStyleComparisonExpanded)
    model.setPhoto(Data([1]), for: .front, strokeStyle: style)
    await model.awaitRendering()
    #expect(await renderer.cacheHits == [false])
    model.vectorOptions.contourLevels = 10
    model.render(strokeStyle: style)
    await model.awaitRendering()
    #expect(await renderer.cacheHits == [false, true])
    let tunedProgram = try #require(model.currentProgram)
    model.options.cropToFace.toggle()
    model.renderIfNeeded(strokeStyle: style)
    await model.awaitRendering()
    #expect(await renderer.cacheHits == [false, true, false])
    model.options.cropToFace.toggle()
    model.renderIfNeeded(strokeStyle: style)
    #expect(model.isProcessing)
    #expect(model.currentProgram == nil)
    await model.awaitRendering()
    #expect(model.currentProgram == tunedProgram)
    #expect(!model.isProcessing)
    #expect(await renderer.cacheHits == [false, true, false])
    await model.shutdown()
  }
}

private actor AdvancingPortraitClock: PortraitCaptureClock {
  private var time = 0.0
  private(set) var sleeps: [Double] = []
  func now() -> TimeInterval { time }
  func sleep(seconds: TimeInterval) async throws {
    try Task.checkCancellation()
    sleeps.append(seconds)
    time += seconds
    await Task.yield()
  }
}

private actor RepeatingPortraitFrames: PortraitFrameAcquiring {
  private let frames: [StampedFrame]
  private var requestCount = 0
  init() throws {
    frames = try (1...30).map { value in
      try StampedFrame(sequence: UInt64(value), captureNanoseconds: UInt64(value),
        cameraConfigurationID: CameraConfigurationID(), width: 2, height: 2, rowBytes: 8,
        pixelFormat: .bgra8, bytes: OwnedFrameBytes(copying: Data(repeating: UInt8(value), count: 16)))
    }
  }
  // Deliberately returns each frame twice even when the caller asks for a newer
  // one; the studio must independently reject duplicate identities/timestamps.
  func latestFrame(newerThanNanoseconds: UInt64) -> StampedFrame? {
    defer { requestCount += 1 }
    return frames[min(requestCount / 2, frames.count - 1)]
  }
}

private actor BurstPhotoAcquirer: PortraitPhotoAcquiring {
  private(set) var capturedTimestamps: [UInt64] = []
  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto {
    let value: UInt8
    switch input {
    case .frame(let frame):
      capturedTimestamps.append(frame.captureNanoseconds)
      value = UInt8(frame.captureNanoseconds)
    case .file(let url): value = UInt8(url.lastPathComponent) ?? 0
    }
    return PortraitAcquiredPhoto(data: Data([value, value]),
      sourcePixelExtent: try PortraitSourceCropExtent(widthPixels: 901, heightPixels: 1600))
  }
}

private actor BurstRenderer: PortraitRendering {
  private(set) var cacheHits: [Bool] = []
  private(set) var sourcePixelExtents: [PortraitSourceCropExtent?] = []
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    cacheHits.append(request.cachedRaster != nil)
    sourcePixelExtents.append(request.sourcePixelExtent)
    let raster = request.cachedRaster ?? portraitTestRaster()
    return PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}

private actor PausedBurstRenderer: PortraitRendering {
  private var waiter: CheckedContinuation<Void, Never>?
  private var entered = false
  private let result: PortraitRenderResult
  init() throws {
    let raster = portraitTestRaster()
    result = PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: .front, style: .contours, strokeStyle: portraitTestStyle()))
  }
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    entered = true
    await withCheckedContinuation { waiter = $0 }
    // Deliberately returns a completed result despite task cancellation.
    return result
  }
  func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !entered {
      try #require(ContinuousClock.now < deadline)
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { waiter?.resume(); waiter = nil }
}

private actor PausedBurstAcquirer: PortraitPhotoAcquiring {
  private var waiter: CheckedContinuation<Void, Never>?
  private var enteredCount = 0
  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto {
    enteredCount += 1
    await withCheckedContinuation { waiter = $0 }
    return PortraitAcquiredPhoto(data: Data([1]))
  }
  func waitUntilEntered(after count: Int = 0) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while enteredCount <= count {
      try #require(ContinuousClock.now < deadline)
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { waiter?.resume(); waiter = nil }
}

@MainActor
private func waitForBurstState(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !condition() {
    try #require(ContinuousClock.now < deadline)
    try await Task.sleep(for: .milliseconds(1))
  }
}
