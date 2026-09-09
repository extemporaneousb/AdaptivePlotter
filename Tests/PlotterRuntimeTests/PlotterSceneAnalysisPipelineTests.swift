import Foundation
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

@Suite("Bounded plotter-scene analysis pipeline")
struct PlotterSceneAnalysisPipelineTests {
  @Test("one hundred frame-only updates do not publish semantic state")
  func diagnosticsOnlyTrafficDoesNotPublishSemantics() async throws {
    let gate = AnalysisGate()
    let pipeline = PlotterSceneAnalysisPipeline(clock: DeterministicRuntimeClock()) { frame in
      await gate.block(frame.sequence)
      return sceneMeasurement(for: frame)
    }
    let recorder = SemanticSnapshotRecorder()
    let updates = await pipeline.updates()
    let updateTask = Task {
      for await update in updates { await recorder.record(update) }
    }
    defer { updateTask.cancel() }
    try await waitUntil { await recorder.count == 1 }

    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    try await waitUntil { await recorder.count == 2 }
    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await gate.startedSequences == [1] }
    for sequence in 2...101 {
      await pipeline.submit(try displayedFrame(sequence: UInt64(sequence)))
    }
    try await waitUntil {
      let diagnostics = await pipeline.diagnostics()
      return diagnostics.submittedFrameCount == 101
        && diagnostics.activeFrameSequence == 1
        && diagnostics.pendingFrameSequence == 101
    }

    let diagnostics = await pipeline.diagnostics()
    #expect(diagnostics.supersededFrameCount == 99)
    #expect(diagnostics.semanticPublicationCount == 1)
    #expect(diagnostics.semanticSubscriptionStartCount == 1)
    #expect(await recorder.count == 2)

    let stop = Task { await pipeline.stop() }
    try await waitUntil { await pipeline.snapshot().state == .stopped }
    await gate.releaseNext()
    await stop.value
  }

  @Test("identical configuration and lifecycle reconciliation is a complete no-op")
  func identicalReconciliationIsNoOp() async {
    let pipeline = PlotterSceneAnalysisPipeline(clock: DeterministicRuntimeClock()) { frame in
      sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    let running = await pipeline.diagnostics()
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    await pipeline.setAnalysisRegion(nil)
    await pipeline.setPenCapColor(.green)
    #expect(await pipeline.diagnostics() == running)

    await pipeline.stop()
    let stopped = await pipeline.diagnostics()
    await pipeline.stop()
    #expect(await pipeline.diagnostics() == stopped)
  }

  @Test("real configuration result error and clearance transitions publish once")
  func semanticTransitionsPublishExactlyOnce() async throws {
    let pipeline = PlotterSceneAnalysisPipeline(clock: DeterministicRuntimeClock()) { frame in
      if frame.sequence == 2 || frame.sequence == 3 {
        throw PipelineTestError.syntheticFailure
      }
      return sceneMeasurement(for: frame)
    }
    let recorder = SemanticSnapshotRecorder()
    let updates = await pipeline.updates()
    let updateTask = Task {
      for await update in updates { await recorder.record(update) }
    }
    defer { updateTask.cancel() }
    try await waitUntil { await recorder.count == 1 }

    await pipeline.start(cadence: .fourFPS, requestedFeatures: [.penCap])
    #expect(await pipeline.diagnostics().semanticPublicationCount == 1)
    try await waitUntil { await recorder.count == 2 }
    let region = PixelRect(x: 0, y: 0, width: 1, height: 1)
    await pipeline.setAnalysisRegion(region)
    await pipeline.setAnalysisRegion(region)
    #expect(await pipeline.diagnostics().semanticPublicationCount == 2)
    try await waitUntil { await recorder.count == 3 }

    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }
    #expect(await pipeline.diagnostics().semanticPublicationCount == 3)
    try await waitUntil { await recorder.count == 4 }

    await pipeline.submit(try displayedFrame(sequence: 2))
    try await waitUntil { await pipeline.diagnostics().failedFrameCount == 1 }
    #expect(await pipeline.diagnostics().semanticPublicationCount == 4)
    #expect(await pipeline.snapshot().lastError != nil)
    try await waitUntil { await recorder.count == 5 }

    await pipeline.submit(try displayedFrame(sequence: 3))
    try await waitUntil { await pipeline.diagnostics().failedFrameCount == 2 }
    #expect(await pipeline.diagnostics().semanticPublicationCount == 4)
    #expect(await recorder.count == 5)

    await pipeline.submit(try displayedFrame(sequence: 4))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 2 }
    #expect(await pipeline.diagnostics().semanticPublicationCount == 5)
    #expect(await pipeline.snapshot().lastError == nil)
    try await waitUntil { await recorder.count == 6 }

    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    #expect(await pipeline.diagnostics().semanticPublicationCount == 6)
    try await waitUntil { await recorder.count == 7 }
    await pipeline.stop()
    await pipeline.stop()
    #expect(await pipeline.diagnostics().semanticPublicationCount == 7)
    try await waitUntil { await recorder.count == 8 }
    #expect(await recorder.revisions == (0...7).map(UInt64.init))
  }

  @Test("pipeline propagates requested features and clears results when selection changes")
  func featureSelectionPropagates() async throws {
    let pipeline = PlotterSceneAnalysisPipeline(clock: DeterministicRuntimeClock())
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.armatureEnvelope])
    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }

    let armatureResult = try #require(await pipeline.snapshot().latestResult)
    #expect(armatureResult.measurement.computation.requestedFeatures == [.armatureEnvelope])
    #expect(
      armatureResult.measurement.computation.expandedFeatures
        == [.penCap, .armatureEnvelope]
    )
    #expect(
      armatureResult.measurement.computation.executionCounts
        == [.penCap: 1, .armatureEnvelope: 1]
    )

    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    #expect(await pipeline.snapshot().latestResult == nil)
    await pipeline.submit(try displayedFrame(sequence: 2))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 2 }
    let capResult = try #require(await pipeline.snapshot().latestResult)
    #expect(capResult.measurement.computation.requestedFeatures == [.penCap])
    #expect(capResult.measurement.computation.expandedFeatures == [.penCap])
    #expect(capResult.measurement.computation.executionCounts == [.penCap: 1])
    await pipeline.stop()
  }

  @Test("one active analysis coalesces all queued work to the newest frame")
  func newestPendingFrameWins() async throws {
    let gate = AnalysisGate()
    let clock = DeterministicRuntimeClock()
    let pipeline = PlotterSceneAnalysisPipeline(clock: clock) { frame in
      await gate.block(frame.sequence)
      return sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])

    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await gate.startedSequences == [1] }
    await pipeline.submit(try displayedFrame(sequence: 2))
    await pipeline.submit(try displayedFrame(sequence: 3))
    await pipeline.submit(try displayedFrame(sequence: 4))

    var diagnostics = await pipeline.diagnostics()
    #expect(diagnostics.activeFrameSequence == 1)
    #expect(diagnostics.pendingFrameSequence == 4)
    #expect(diagnostics.supersededFrameCount == 2)

    await gate.releaseNext()
    try await waitUntil { await gate.startedSequences == [1, 4] }
    await gate.releaseNext()
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 2 }

    diagnostics = await pipeline.diagnostics()
    #expect(diagnostics.submittedFrameCount == 4)
    #expect(diagnostics.analyzedFrameCount == 2)
    #expect(diagnostics.latestResult?.frameSequence == 4)
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
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }
    await pipeline.submit(try displayedFrame(sequence: 2))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 2 }

    let values = await starts.values
    #expect(values.count == 2)
    #expect(values[1] - values[0] >= VisionAnalysisCadence.fiveFPS.minimumIntervalNanoseconds)
    await pipeline.stop()
  }

  @Test("cadence reserves a live-preview recovery interval after slow analysis completes")
  func cadenceStartsAfterCompletionRecovery() async throws {
    let clock = DeterministicRuntimeClock(startNanoseconds: 10)
    let starts = StartRecorder()
    let activity = ActivityRecorder()
    let pipeline = PlotterSceneAnalysisPipeline(
      clock: clock,
      activityHandler: { active in await activity.record(active) }
    ) { frame in
      await starts.record(clock.nowNanoseconds())
      clock.advance(nanoseconds: 900_000_000)
      return sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .twoFPS, requestedFeatures: [.penCap])
    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }
    await pipeline.submit(try displayedFrame(sequence: 2))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 2 }

    let values = await starts.values
    #expect(values == [10, 1_400_000_010])
    #expect(await activity.values == [true, false, true, false])
    await pipeline.stop()
  }

  @Test("stopping settles held analysis and discards its late result before reuse")
  func stopRejectsLateResult() async throws {
    let gate = AnalysisGate()
    let activity = ActivityRecorder()
    let pipeline = PlotterSceneAnalysisPipeline(
      clock: DeterministicRuntimeClock(),
      activityHandler: { active in await activity.record(active) }
    ) { frame in
      await gate.block(frame.sequence)
      return sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .twoFPS, requestedFeatures: [.penCap])
    await pipeline.submit(try displayedFrame(sequence: 7))
    try await waitUntil { await gate.startedSequences == [7] }

    let stop = Task { await pipeline.stop() }
    try await waitUntil { await pipeline.snapshot().state == .stopped }
    #expect(await pipeline.diagnostics().activeFrameSequence == 7)
    #expect(await pipeline.diagnostics().analyzedFrameCount == 0)
    await gate.releaseNext()
    await stop.value
    let snapshot = await pipeline.snapshot()
    #expect(snapshot.state == .stopped)
    #expect(await pipeline.diagnostics().analyzedFrameCount == 0)
    #expect(snapshot.latestResult == nil)
    #expect(await activity.values == [true, false])
    await pipeline.start(cadence: .twoFPS, requestedFeatures: [.penCap])
    await pipeline.submit(try displayedFrame(sequence: 8))
    try await waitUntil { await gate.startedSequences == [7, 8] }
    await gate.releaseNext()
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }
    #expect(await pipeline.snapshot().latestResult?.displayedFrame.frame.sequence == 8)
    await pipeline.stop()
  }

  @Test("configuration changes retain one held worker and coalesce replacement analysis")
  func reconfigurationWaitsForPriorWorker() async throws {
    let gate = AnalysisGate()
    let pipeline = PlotterSceneAnalysisPipeline(clock: DeterministicRuntimeClock()) { frame in
      await gate.block(frame.sequence)
      return sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .twoFPS, requestedFeatures: [.penCap])
    await pipeline.submit(try displayedFrame(sequence: 1))
    try await waitUntil { await gate.startedSequences == [1] }
    for index in 2...20 {
      await pipeline.setAnalysisRegion(PixelRect(x: index, y: 0, width: 1, height: 1))
      await pipeline.submit(try displayedFrame(sequence: UInt64(index)))
    }
    #expect(await gate.startedSequences == [1])
    #expect(await pipeline.diagnostics().activeFrameSequence == 1)
    #expect(await pipeline.diagnostics().pendingFrameSequence == 20)
    await gate.releaseNext()
    try await waitUntil { await gate.startedSequences == [1, 20] }
    await gate.releaseNext()
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }
    #expect(await gate.maximumActiveCount == 1)
    #expect(await pipeline.snapshot().latestResult?.displayedFrame.frame.sequence == 20)
    await pipeline.stop()
  }

  @Test("failed analysis always releases its preview owner")
  func failureReleasesActivity() async throws {
    let activity = ActivityRecorder()
    let pipeline = PlotterSceneAnalysisPipeline(
      clock: DeterministicRuntimeClock(),
      activityHandler: { active in await activity.record(active) }
    ) { _ in
      throw PipelineTestError.syntheticFailure
    }
    await pipeline.start(cadence: .twoFPS, requestedFeatures: [.penCap])
    await pipeline.submit(try displayedFrame(sequence: 9))
    try await waitUntil { await pipeline.diagnostics().failedFrameCount == 1 }
    #expect(await activity.values == [true, false])
    #expect(await pipeline.diagnostics().activeFrameSequence == nil)
    await pipeline.stop()
  }

  @Test("stop and restart never expose a result from the prior camera lifecycle")
  func restartClearsPriorResult() async throws {
    let pipeline = PlotterSceneAnalysisPipeline(
      clock: DeterministicRuntimeClock()
    ) { frame in
      sceneMeasurement(for: frame)
    }
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    await pipeline.submit(try displayedFrame(sequence: 11))
    try await waitUntil { await pipeline.diagnostics().analyzedFrameCount == 1 }
    #expect(await pipeline.snapshot().latestResult?.displayedFrame.frame.sequence == 11)

    await pipeline.stop()
    #expect(await pipeline.snapshot().latestResult == nil)
    await pipeline.start(cadence: .fiveFPS, requestedFeatures: [.penCap])
    let restarted = await pipeline.snapshot()
    #expect(restarted.latestResult == nil)
    #expect(await pipeline.diagnostics().activeFrameSequence == nil)
    #expect(await pipeline.diagnostics().pendingFrameSequence == nil)
    await pipeline.stop()
  }
}
private actor AnalysisGate {
  private(set) var startedSequences: [UInt64] = []
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var activeCount = 0
  private(set) var maximumActiveCount = 0

  func block(_ sequence: UInt64) async {
    startedSequences.append(sequence)
    activeCount += 1
    maximumActiveCount = max(maximumActiveCount, activeCount)
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
    activeCount -= 1
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

private actor ActivityRecorder {
  private(set) var values: [Bool] = []

  func record(_ value: Bool) {
    values.append(value)
  }
}

private actor SemanticSnapshotRecorder {
  private(set) var revisions: [UInt64] = []

  var count: Int { revisions.count }

  func record(_ snapshot: PlotterSceneAnalysisSnapshot) {
    revisions.append(snapshot.revision)
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
    penCap: .notRequested,
    armatureEnvelope: .notRequested,
    overlays: [],
    algorithmRevision: "pipeline-test-v1",
    diagnosticSHA256: frame.contentSHA256,
    computation: SceneVisionComputationDiagnostics(
      requestedFeatures: [],
      expandedFeatures: [],
      executionCounts: [:],
      inspectedPixelCounts: [:]
    )
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
  case syntheticFailure
}
