import Foundation
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

@Suite("Bounded plotter-scene analysis pipeline")
struct PlotterSceneAnalysisPipelineTests {
  @Test("one active analysis coalesces all queued work to the newest frame")
  func newestPendingFrameWins() async throws {
    let gate = AnalysisGate()
    let clock = DeterministicRuntimeClock()
    let pipeline = PlotterSceneAnalysisPipeline(clock: clock) { frame in
      await gate.block(frame.sequence)
      return sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .tenFPS)

    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await gate.startedSequences == [1] }
    await pipeline.submit(try displayedFrame(sequence: 2))
    await pipeline.submit(try displayedFrame(sequence: 3))
    await pipeline.submit(try displayedFrame(sequence: 4))

    var snapshot = await pipeline.snapshot()
    #expect(snapshot.activeFrameSequence == 1)
    #expect(snapshot.pendingFrameSequence == 4)
    #expect(snapshot.supersededFrameCount == 2)

    await gate.releaseNext()
    try await waitUntil { await gate.startedSequences == [1, 4] }
    await gate.releaseNext()
    try await waitUntil { await pipeline.snapshot().analyzedFrameCount == 2 }

    snapshot = await pipeline.snapshot()
    #expect(snapshot.submittedFrameCount == 4)
    #expect(snapshot.analyzedFrameCount == 2)
    #expect(snapshot.latestResult?.displayedFrame.frame.sequence == 4)
    #expect(await gate.startedSequences == [1, 4])
    await pipeline.stop()
  }

  @Test("selected cadence spaces analysis starts without delaying submitters")
  func cadenceBoundsAnalysisStarts() async throws {
    let clock = DeterministicRuntimeClock(startNanoseconds: 10)
    let starts = StartRecorder()
    let pipeline = PlotterSceneAnalysisPipeline(clock: clock) { frame in
      await starts.record(clock.nowNanoseconds())
      return sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .fiveFPS)
    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await pipeline.snapshot().analyzedFrameCount == 1 }
    await pipeline.submit(try displayedFrame(sequence: 2))
    try await waitUntil { await pipeline.snapshot().analyzedFrameCount == 2 }

    let values = await starts.values
    #expect(values.count == 2)
    #expect(values[1] - values[0] >= VisionAnalysisCadence.fiveFPS.minimumIntervalNanoseconds)
    await pipeline.stop()
  }

  @Test("stopping discards a late result from an already active analyzer")
  func stopRejectsLateResult() async throws {
    let gate = AnalysisGate()
    let pipeline = PlotterSceneAnalysisPipeline(
      clock: DeterministicRuntimeClock()
    ) { frame in
      await gate.block(frame.sequence)
      return sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .twoFPS)
    await pipeline.submit(try displayedFrame(sequence: 7))
    try await waitUntil { await gate.startedSequences == [7] }

    await pipeline.stop()
    await gate.releaseNext()
    await Task.yield()
    let snapshot = await pipeline.snapshot()
    #expect(snapshot.state == .stopped)
    #expect(snapshot.analyzedFrameCount == 0)
    #expect(snapshot.latestResult == nil)
  }

  @Test("stop and restart never expose a result from the prior camera lifecycle")
  func restartClearsPriorResult() async throws {
    let pipeline = PlotterSceneAnalysisPipeline(
      clock: DeterministicRuntimeClock()
    ) { frame in
      sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .fiveFPS)
    await pipeline.submit(try displayedFrame(sequence: 11))
    try await waitUntil { await pipeline.snapshot().analyzedFrameCount == 1 }
    #expect(await pipeline.snapshot().latestResult?.displayedFrame.frame.sequence == 11)

    await pipeline.stop()
    #expect(await pipeline.snapshot().latestResult == nil)
    await pipeline.start(cadence: .fiveFPS)
    let restarted = await pipeline.snapshot()
    #expect(restarted.latestResult == nil)
    #expect(restarted.activeFrameSequence == nil)
    #expect(restarted.pendingFrameSequence == nil)
    await pipeline.stop()
  }
}

private actor AnalysisGate {
  private(set) var startedSequences: [UInt64] = []
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func block(_ sequence: UInt64) async {
    startedSequences.append(sequence)
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func releaseNext() {
    guard !continuations.isEmpty else { return }
    continuations.removeFirst().resume()
  }
}

private actor StartRecorder {
  private(set) var values: [UInt64] = []

  func record(_ value: UInt64) {
    values.append(value)
  }
}

private func displayedFrame(sequence: UInt64) throws -> DisplayedFrame {
  DisplayedFrame(
    source: .simulated,
    frame: try StampedFrame(
      id: FrameID(rawValue: "analysis-\(sequence)"),
      sequence: sequence,
      captureNanoseconds: sequence,
      cameraConfigurationID: CameraConfigurationID(),
      width: 1,
      height: 1,
      rowBytes: 4,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes([255, 255, 255, 255])
    )
  )
}

private func sceneMeasurement(for frame: StampedFrame) -> PlotterSceneMeasurement {
  PlotterSceneMeasurement(
    frameID: frame.id,
    frameSHA256: frame.contentSHA256,
    cameraConfigurationID: frame.cameraConfigurationID,
    greenComponentCount: 0,
    cap: nil,
    topFrameSide: nil,
    rightFrameSide: nil,
    drawingFrame: nil,
    armature: nil,
    overlays: [],
    algorithmRevision: "pipeline-test-v1",
    diagnosticSHA256: frame.contentSHA256
  )
}

private func waitUntil(
  attempts: Int = 2_000,
  condition: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<attempts {
    if await condition() { return }
    await Task.yield()
  }
  throw PipelineTestError.timedOut
}

private enum PipelineTestError: Error {
  case timedOut
}
