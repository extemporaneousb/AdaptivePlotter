import Foundation
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitStudioUI
import Testing

@Suite("Current capture cancellation and illumination lifetime", .serialized)
struct PortraitCaptureTests {
  @Test("cancelling a lit burst discards held encoding and turns off illumination before it settles")
  @MainActor
  func cancelHeldBurst() async throws {
    let acquirer = PausedBurstAcquirer()
    let model = PortraitStudioModel(library: DrawingFirstTestStorage.library(), photoAcquirer: acquirer,
      frameSource: try RepeatingPortraitFrames(), captureClock: AdvancingPortraitClock())
    let capture = Task { await model.captureForPortfolio(strokeStyle: try! portraitTestStyle()) }
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
    #expect(model.portfolioPhoto == nil)
    #expect(model.currentProgram == nil)
  }

  @Test("capture light expires while encoding is held and later worker progress cannot relight it")
  @MainActor
  func lightDeadlineDuringHeldEncoding() async throws {
    let acquirer = PausedBurstAcquirer()
    let model = PortraitStudioModel(library: DrawingFirstTestStorage.library(), photoAcquirer: acquirer,
      frameSource: try RepeatingPortraitFrames(), captureClock: AdvancingPortraitClock())
    let style = try portraitTestStyle()
    let capture = Task { await model.captureForPortfolio(strokeStyle: style) }
    try await acquirer.waitUntilEntered()
    #expect(model.screenIlluminationActive)
    try await waitForBurstState { !model.screenIlluminationActive }
    #expect(model.isCapturing)
    #expect(model.captureProgress == 1)
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
    #expect(model.portfolioPhoto == nil)
    #expect(!model.screenIlluminationActive)
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
