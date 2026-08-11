import Foundation

public enum VisionAnalysisCadence: Int, Codable, CaseIterable, Hashable, Sendable {
  case twoFPS = 2
  case fiveFPS = 5
  case tenFPS = 10

  public var minimumIntervalNanoseconds: UInt64 {
    1_000_000_000 / UInt64(rawValue)
  }
}

public typealias PlotterSceneAnalysisActivityHandler = @Sendable (Bool) async -> Void

public enum PlotterSceneAnalysisState: Codable, Hashable, Sendable {
  case stopped
  case running(VisionAnalysisCadence)
}

public struct PlotterSceneAnalysisResult: Hashable, Sendable {
  public let displayedFrame: DisplayedFrame
  public let measurement: PlotterSceneMeasurement
  public let analysisDurationNanoseconds: UInt64
  public let completedNanoseconds: UInt64

  public init(
    displayedFrame: DisplayedFrame,
    measurement: PlotterSceneMeasurement,
    analysisDurationNanoseconds: UInt64,
    completedNanoseconds: UInt64
  ) {
    self.displayedFrame = displayedFrame
    self.measurement = measurement
    self.analysisDurationNanoseconds = analysisDurationNanoseconds
    self.completedNanoseconds = completedNanoseconds
  }
}

public struct PlotterSceneAnalysisSnapshot: Hashable, Sendable {
  public let state: PlotterSceneAnalysisState
  public let submittedFrameCount: UInt64
  public let analyzedFrameCount: UInt64
  public let supersededFrameCount: UInt64
  public let failedFrameCount: UInt64
  public let activeFrameSequence: UInt64?
  public let pendingFrameSequence: UInt64?
  public let latestResult: PlotterSceneAnalysisResult?
  public let lastError: String?

  public init(
    state: PlotterSceneAnalysisState,
    submittedFrameCount: UInt64,
    analyzedFrameCount: UInt64,
    supersededFrameCount: UInt64,
    failedFrameCount: UInt64,
    activeFrameSequence: UInt64?,
    pendingFrameSequence: UInt64?,
    latestResult: PlotterSceneAnalysisResult?,
    lastError: String?
  ) {
    self.state = state
    self.submittedFrameCount = submittedFrameCount
    self.analyzedFrameCount = analyzedFrameCount
    self.supersededFrameCount = supersededFrameCount
    self.failedFrameCount = failedFrameCount
    self.activeFrameSequence = activeFrameSequence
    self.pendingFrameSequence = pendingFrameSequence
    self.latestResult = latestResult
    self.lastError = lastError
  }

  public static let stopped = PlotterSceneAnalysisSnapshot(
    state: .stopped,
    submittedFrameCount: 0,
    analyzedFrameCount: 0,
    supersededFrameCount: 0,
    failedFrameCount: 0,
    activeFrameSequence: nil,
    pendingFrameSequence: nil,
    latestResult: nil,
    lastError: nil
  )
}

/// Bounded newest-only scene analysis. At most one frame is being analyzed and
/// one newer frame is pending; submitting another frame replaces that pending
/// frame. Camera delivery never waits for vision work; clients may use the
/// activity callback to hold preview publication while the immutable frame is
/// being analyzed.
public actor PlotterSceneAnalysisPipeline {
  typealias Analyzer = @Sendable (StampedFrame) async throws -> PlotterSceneMeasurement

  private let clock: any RuntimeClock
  private let analyzer: Analyzer
  private let activityHandler: PlotterSceneAnalysisActivityHandler
  private var state: PlotterSceneAnalysisState = .stopped
  private var pendingFrame: DisplayedFrame?
  private var activeFrameSequence: UInt64?
  private var submittedFrameCount: UInt64 = 0
  private var analyzedFrameCount: UInt64 = 0
  private var supersededFrameCount: UInt64 = 0
  private var failedFrameCount: UInt64 = 0
  private var latestResult: PlotterSceneAnalysisResult?
  private var lastError: String?
  private var lastAnalysisCompletionNanoseconds: UInt64?
  private var drainTask: Task<Void, Never>?
  private var generation: UInt64 = 0
  private var continuations:
    [UUID: AsyncStream<PlotterSceneAnalysisSnapshot>.Continuation] = [:]

  public init(
    worker: VisionWorker = VisionWorker(),
    clock: any RuntimeClock = SystemRuntimeClock(),
    activityHandler: @escaping PlotterSceneAnalysisActivityHandler = { _ in }
  ) {
    self.clock = clock
    self.activityHandler = activityHandler
    analyzer = { frame in try await worker.inspectPlotterScene(in: frame) }
  }

  init(
    clock: any RuntimeClock,
    activityHandler: @escaping PlotterSceneAnalysisActivityHandler = { _ in },
    analyzer: @escaping Analyzer
  ) {
    self.clock = clock
    self.activityHandler = activityHandler
    self.analyzer = analyzer
  }

  public func start(cadence: VisionAnalysisCadence) {
    if case .stopped = state {
      generation &+= 1
      lastAnalysisCompletionNanoseconds = nil
    }
    state = .running(cadence)
    lastError = nil
    publishSnapshot()
    scheduleDrainIfNeeded()
  }

  public func stop() async {
    let analysisWasActive = activeFrameSequence != nil
    generation &+= 1
    drainTask?.cancel()
    drainTask = nil
    pendingFrame = nil
    activeFrameSequence = nil
    latestResult = nil
    lastError = nil
    lastAnalysisCompletionNanoseconds = nil
    state = .stopped
    if analysisWasActive { await activityHandler(false) }
    publishSnapshot()
  }

  public func submit(_ displayedFrame: DisplayedFrame) {
    guard case .running = state else { return }
    submittedFrameCount &+= 1
    if pendingFrame != nil { supersededFrameCount &+= 1 }
    pendingFrame = displayedFrame
    publishSnapshot()
    scheduleDrainIfNeeded()
  }

  public func snapshot() -> PlotterSceneAnalysisSnapshot {
    makeSnapshot()
  }

  public func updates() -> AsyncStream<PlotterSceneAnalysisSnapshot> {
    let identifier = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      continuations[identifier] = continuation
      continuation.yield(makeSnapshot())
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        Task { await self.removeContinuation(identifier) }
      }
    }
  }

  private func scheduleDrainIfNeeded() {
    guard drainTask == nil, pendingFrame != nil, case .running = state else { return }
    let taskGeneration = generation
    drainTask = Task { [weak self] in
      await self?.drain(generation: taskGeneration)
    }
  }

  private func drain(generation taskGeneration: UInt64) async {
    while !Task.isCancelled, taskGeneration == generation {
      guard case .running(let cadence) = state else { break }
      if let lastAnalysisCompletionNanoseconds {
        let earliest = addingClamped(
          lastAnalysisCompletionNanoseconds,
          cadence.minimumIntervalNanoseconds
        )
        let now = clock.nowNanoseconds()
        if now < earliest {
          do {
            try await clock.sleep(nanoseconds: earliest - now)
          } catch {
            break
          }
        }
      }
      guard !Task.isCancelled, taskGeneration == generation,
        case .running = state, let frame = pendingFrame
      else { break }
      pendingFrame = nil
      activeFrameSequence = frame.frame.sequence
      let started = clock.nowNanoseconds()
      await activityHandler(true)
      guard !Task.isCancelled, taskGeneration == generation else { break }
      publishSnapshot()
      let result: Result<PlotterSceneMeasurement, Error>
      do {
        result = .success(try await analyzer(frame.frame))
      } catch {
        result = .failure(error)
      }
      guard !Task.isCancelled, taskGeneration == generation else { break }
      let completed = clock.nowNanoseconds()
      lastAnalysisCompletionNanoseconds = completed
      await activityHandler(false)
      guard !Task.isCancelled, taskGeneration == generation else { break }
      switch result {
      case .success(let measurement):
        analyzedFrameCount &+= 1
        activeFrameSequence = nil
        lastError = nil
        latestResult = PlotterSceneAnalysisResult(
          displayedFrame: frame,
          measurement: measurement,
          analysisDurationNanoseconds: completed >= started ? completed - started : 0,
          completedNanoseconds: completed
        )
      case .failure(let error):
        failedFrameCount &+= 1
        activeFrameSequence = nil
        lastError = String(describing: error)
      }
      publishSnapshot()
      if pendingFrame == nil { break }
    }
    guard taskGeneration == generation else { return }
    drainTask = nil
    if pendingFrame != nil { scheduleDrainIfNeeded() }
  }

  private func makeSnapshot() -> PlotterSceneAnalysisSnapshot {
    PlotterSceneAnalysisSnapshot(
      state: state,
      submittedFrameCount: submittedFrameCount,
      analyzedFrameCount: analyzedFrameCount,
      supersededFrameCount: supersededFrameCount,
      failedFrameCount: failedFrameCount,
      activeFrameSequence: activeFrameSequence,
      pendingFrameSequence: pendingFrame?.frame.sequence,
      latestResult: latestResult,
      lastError: lastError
    )
  }

  private func publishSnapshot() {
    let snapshot = makeSnapshot()
    for continuation in continuations.values { continuation.yield(snapshot) }
  }

  private func removeContinuation(_ identifier: UUID) {
    continuations.removeValue(forKey: identifier)
  }
}

private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
  let (result, overflow) = lhs.addingReportingOverflow(rhs)
  return overflow ? UInt64.max : result
}
