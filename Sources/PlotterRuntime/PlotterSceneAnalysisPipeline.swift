import Foundation
import PlotterModel

public enum VisionAnalysisCadence: Double, Codable, CaseIterable, Hashable, Sendable {
  case zeroPointZeroFiveFPS = 0.05
  case oneFPS = 1
  case twoFPS = 2
  case twoPointFiveEightFPS = 2.58
  case threeFPS = 3
  case fourFPS = 4
  case fiveFPS = 5

  public var displayValue: String {
    switch self {
    case .zeroPointZeroFiveFPS: "0.05"
    case .oneFPS: "1"
    case .twoFPS: "2"
    case .twoPointFiveEightFPS: "2.58"
    case .threeFPS: "3"
    case .fourFPS: "4"
    case .fiveFPS: "5"
    }
  }

  public var minimumIntervalNanoseconds: UInt64 {
    UInt64((1_000_000_000 / rawValue).rounded(.up))
  }
}
public typealias PlotterSceneAnalysisActivityHandler = @Sendable (Bool) async -> Void

public enum PlotterSceneAnalysisState: Codable, Hashable, Sendable {
  case stopped
  case running(VisionAnalysisCadence)
}

/// Small, value-comparable state for semantic subscribers. Per-frame sequence,
/// throughput, and pending-work facts intentionally live only in diagnostics.
public struct PlotterSceneAnalysisPhase: Codable, Hashable, Sendable {
  public let state: PlotterSceneAnalysisState
  public let requestedFeatures: SceneFeatureSet
  public let analysisRegion: PixelRect?
  public let penCapColor: PenCapColor
  public let penCapReference: PenCapVisualReference?

  public init(
    state: PlotterSceneAnalysisState,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?,
    penCapColor: PenCapColor,
    penCapReference: PenCapVisualReference? = nil
  ) {
    self.state = state
    self.requestedFeatures = requestedFeatures
    self.analysisRegion = analysisRegion
    self.penCapColor = penCapColor
    self.penCapReference = penCapReference
  }

  public static let stopped = PlotterSceneAnalysisPhase(
    state: .stopped,
    requestedFeatures: [],
    analysisRegion: nil,
    penCapColor: .green
  )
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
  public let revision: UInt64
  public let phase: PlotterSceneAnalysisPhase
  public let latestResult: PlotterSceneAnalysisResult?
  public let lastError: String?

  public init(
    revision: UInt64,
    phase: PlotterSceneAnalysisPhase,
    latestResult: PlotterSceneAnalysisResult?,
    lastError: String?
  ) {
    self.revision = revision
    self.phase = phase
    self.latestResult = latestResult
    self.lastError = lastError
  }

  public var state: PlotterSceneAnalysisState { phase.state }

  public static let stopped = PlotterSceneAnalysisSnapshot(
    revision: 0,
    phase: .stopped,
    latestResult: nil,
    lastError: nil
  )
}

public struct PlotterSceneAnalysisResultDiagnostics: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let frameSequence: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let analysisDurationNanoseconds: UInt64
  public let completedNanoseconds: UInt64
  public let computation: SceneVisionComputationDiagnostics

  public init(
    frameID: FrameID,
    frameSequence: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    analysisDurationNanoseconds: UInt64,
    completedNanoseconds: UInt64,
    computation: SceneVisionComputationDiagnostics
  ) {
    self.frameID = frameID
    self.frameSequence = frameSequence
    self.cameraConfigurationID = cameraConfigurationID
    self.analysisDurationNanoseconds = analysisDurationNanoseconds
    self.completedNanoseconds = completedNanoseconds
    self.computation = computation
  }
}

/// Pull-only operational facts. Reading this value does not subscribe the UI
/// or create another camera/Vision publication path.
public struct PlotterSceneAnalysisDiagnostics: Codable, Hashable, Sendable {
  public let phase: PlotterSceneAnalysisPhase
  public let submittedFrameCount: UInt64
  public let analyzedFrameCount: UInt64
  public let supersededFrameCount: UInt64
  public let failedFrameCount: UInt64
  public let activeFrameSequence: UInt64?
  public let pendingFrameSequence: UInt64?
  public let latestResult: PlotterSceneAnalysisResultDiagnostics?
  public let lastError: String?
  public let configurationRevision: UInt64
  public let semanticPublicationCount: UInt64
  public let semanticSubscriptionStartCount: UInt64

  public init(
    phase: PlotterSceneAnalysisPhase,
    submittedFrameCount: UInt64,
    analyzedFrameCount: UInt64,
    supersededFrameCount: UInt64,
    failedFrameCount: UInt64,
    activeFrameSequence: UInt64?,
    pendingFrameSequence: UInt64?,
    latestResult: PlotterSceneAnalysisResultDiagnostics?,
    lastError: String?,
    configurationRevision: UInt64,
    semanticPublicationCount: UInt64,
    semanticSubscriptionStartCount: UInt64
  ) {
    self.phase = phase
    self.submittedFrameCount = submittedFrameCount
    self.analyzedFrameCount = analyzedFrameCount
    self.supersededFrameCount = supersededFrameCount
    self.failedFrameCount = failedFrameCount
    self.activeFrameSequence = activeFrameSequence
    self.pendingFrameSequence = pendingFrameSequence
    self.latestResult = latestResult
    self.lastError = lastError
    self.configurationRevision = configurationRevision
    self.semanticPublicationCount = semanticPublicationCount
    self.semanticSubscriptionStartCount = semanticSubscriptionStartCount
  }
}

/// Bounded newest-only scene analysis. At most one frame is being analyzed and
/// one newer frame is pending; submitting another frame replaces that pending
/// frame. Camera delivery never waits for vision work; clients may use the
/// activity callback to hold preview publication while the immutable frame is
/// being analyzed.
public actor PlotterSceneAnalysisPipeline {
  typealias Analyzer = @Sendable (StampedFrame) async throws -> PlotterSceneMeasurement
  typealias RegionAnalyzer =
    @Sendable (StampedFrame, SceneFeatureSet, PixelRect?, PenCapColor, PenCapVisualReference?) async throws
    -> PlotterSceneMeasurement

  private let clock: any RuntimeClock
  private let analyzer: RegionAnalyzer
  private let activityHandler: PlotterSceneAnalysisActivityHandler
  private var state: PlotterSceneAnalysisState = .stopped
  private var requestedFeatures: SceneFeatureSet = []
  private var analysisRegion: PixelRect?
  private var penCapColor: PenCapColor = .green
  private var penCapReference: PenCapVisualReference?
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
  private var configurationRevision: UInt64 = 0
  private var semanticPublicationCount: UInt64 = 0
  private var semanticSubscriptionStartCount: UInt64 = 0
  private var continuations: [UUID: AsyncStream<PlotterSceneAnalysisSnapshot>.Continuation] = [:]

  public init(
    worker: VisionWorker = VisionWorker(),
    clock: any RuntimeClock = SystemRuntimeClock(),
    activityHandler: @escaping PlotterSceneAnalysisActivityHandler = { _ in }
  ) {
    self.clock = clock
    self.activityHandler = activityHandler
    analyzer = { frame, features, region, penCapColor, penCapReference in
      try await worker.inspectPlotterScene(
        in: frame,
        requestedFeatures: features,
        analysisRegion: region,
        penCapColor: penCapColor,
        penCapReference: penCapReference
      )
    }
  }

  init(
    clock: any RuntimeClock,
    activityHandler: @escaping PlotterSceneAnalysisActivityHandler = { _ in },
    analyzer: @escaping Analyzer
  ) {
    self.clock = clock
    self.activityHandler = activityHandler
    self.analyzer = { frame, _, _, _, _ in try await analyzer(frame) }
  }

  public func setAnalysisRegion(_ region: PixelRect?) async {
    guard analysisRegion != region else { return }
    let analysisWasActive = cancelCurrentAnalysis()
    analysisRegion = region
    configurationRevision &+= 1
    if analysisWasActive { await activityHandler(false) }
    publishSemanticSnapshot()
  }

  public func setPenCapReference(_ reference: PenCapVisualReference?) async {
    guard penCapReference != reference else { return }
    let active = cancelCurrentAnalysis()
    penCapReference = reference
    configurationRevision &+= 1
    if active { await activityHandler(false) }
    publishSemanticSnapshot()
  }

  public func setPenCapColor(_ color: PenCapColor) async {
    guard penCapColor != color else { return }
    let analysisWasActive = cancelCurrentAnalysis()
    penCapColor = color
    configurationRevision &+= 1
    if analysisWasActive { await activityHandler(false) }
    publishSemanticSnapshot()
  }

  public func start(cadence: VisionAnalysisCadence, requestedFeatures: SceneFeatureSet) async {
    guard state != .running(cadence) || self.requestedFeatures != requestedFeatures else {
      return
    }
    let featuresChanged = self.requestedFeatures != requestedFeatures
    let wasStopped = state == .stopped
    var analysisWasActive = false
    if featuresChanged {
      analysisWasActive = cancelCurrentAnalysis()
      self.requestedFeatures = requestedFeatures
    } else if wasStopped {
      generation &+= 1
      lastAnalysisCompletionNanoseconds = nil
    }
    state = .running(cadence)
    lastError = nil
    configurationRevision &+= 1
    if analysisWasActive { await activityHandler(false) }
    publishSemanticSnapshot()
    scheduleDrainIfNeeded()
  }

  public func stop() async {
    let drain = drainTask
    guard state != .stopped else {
      await drain?.value
      return
    }
    let analysisWasActive = cancelCurrentAnalysis()
    state = .stopped
    requestedFeatures = []
    configurationRevision &+= 1
    if analysisWasActive { await activityHandler(false) }
    publishSemanticSnapshot()
    await drain?.value
  }

  public func submit(_ displayedFrame: DisplayedFrame) {
    guard case .running = state else { return }
    submittedFrameCount &+= 1
    if pendingFrame != nil { supersededFrameCount &+= 1 }
    pendingFrame = displayedFrame
    scheduleDrainIfNeeded()
  }

  public func snapshot() -> PlotterSceneAnalysisSnapshot {
    makeSemanticSnapshot()
  }

  public func diagnostics() -> PlotterSceneAnalysisDiagnostics {
    PlotterSceneAnalysisDiagnostics(
      phase: makePhase(),
      submittedFrameCount: submittedFrameCount,
      analyzedFrameCount: analyzedFrameCount,
      supersededFrameCount: supersededFrameCount,
      failedFrameCount: failedFrameCount,
      activeFrameSequence: activeFrameSequence,
      pendingFrameSequence: pendingFrame?.frame.sequence,
      latestResult: latestResult.map {
        PlotterSceneAnalysisResultDiagnostics(
          frameID: $0.displayedFrame.frame.id,
          frameSequence: $0.displayedFrame.frame.sequence,
          cameraConfigurationID: $0.displayedFrame.frame.cameraConfigurationID,
          analysisDurationNanoseconds: $0.analysisDurationNanoseconds,
          completedNanoseconds: $0.completedNanoseconds,
          computation: $0.measurement.computation
        )
      },
      lastError: lastError,
      configurationRevision: configurationRevision,
      semanticPublicationCount: semanticPublicationCount,
      semanticSubscriptionStartCount: semanticSubscriptionStartCount
    )
  }

  /// The only push channel. It emits the current semantic snapshot once when a
  /// subscriber attaches, then only configuration/state, completed-result, or
  /// error-state changes. Frame traffic and throughput remain pull-only.
  public func updates() -> AsyncStream<PlotterSceneAnalysisSnapshot> {
    let identifier = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      semanticSubscriptionStartCount &+= 1
      continuations[identifier] = continuation
      continuation.yield(makeSemanticSnapshot())
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
      // Analysis is the deliberate evidence-identity boundary. The digest is
      // memoized in the shared immutable frame value, so Vision, its result,
      // and overlay matching reuse one SHA-256 computation.
      let analysisFrame = DisplayedFrame(
        source: frame.source,
        frame: frame.frame.materializingContentHash(for: .analysis)
      )
      activeFrameSequence = analysisFrame.frame.sequence
      let started = clock.nowNanoseconds()
      await activityHandler(true)
      guard !Task.isCancelled, taskGeneration == generation else { break }
      let result: Result<PlotterSceneMeasurement, Error>
      do {
        result = .success(
          try await analyzer(
            analysisFrame.frame,
            requestedFeatures,
            analysisRegion,
            penCapColor,
            penCapReference
          )
        )
      } catch {
        result = .failure(error)
      }
      guard !Task.isCancelled, taskGeneration == generation else { break }
      let completed = clock.nowNanoseconds()
      lastAnalysisCompletionNanoseconds = completed
      await activityHandler(false)
      guard !Task.isCancelled, taskGeneration == generation else { break }
      var shouldPublishSemanticChange = false
      switch result {
      case .success(let measurement):
        analyzedFrameCount &+= 1
        activeFrameSequence = nil
        lastError = nil
        latestResult = PlotterSceneAnalysisResult(
          displayedFrame: analysisFrame,
          measurement: measurement,
          analysisDurationNanoseconds: completed >= started ? completed - started : 0,
          completedNanoseconds: completed
        )
        shouldPublishSemanticChange = true
      case .failure(let error):
        failedFrameCount &+= 1
        activeFrameSequence = nil
        let message = String(describing: error)
        shouldPublishSemanticChange = lastError != message
        lastError = message
      }
      if shouldPublishSemanticChange { publishSemanticSnapshot() }
      if pendingFrame == nil { break }
    }
    activeFrameSequence = nil
    drainTask = nil
    if pendingFrame != nil { scheduleDrainIfNeeded() }
  }

  private func makePhase() -> PlotterSceneAnalysisPhase {
    PlotterSceneAnalysisPhase(
      state: state,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion,
      penCapColor: penCapColor,
      penCapReference: penCapReference
    )
  }

  private func makeSemanticSnapshot() -> PlotterSceneAnalysisSnapshot {
    PlotterSceneAnalysisSnapshot(
      revision: semanticPublicationCount,
      phase: makePhase(),
      latestResult: latestResult,
      lastError: lastError
    )
  }

  private func publishSemanticSnapshot() {
    semanticPublicationCount &+= 1
    let snapshot = makeSemanticSnapshot()
    for continuation in continuations.values { continuation.yield(snapshot) }
  }

  @discardableResult
  private func cancelCurrentAnalysis() -> Bool {
    let analysisWasActive = activeFrameSequence != nil
    generation &+= 1
    drainTask?.cancel()
    pendingFrame = nil
    latestResult = nil
    lastError = nil
    lastAnalysisCompletionNanoseconds = nil
    return analysisWasActive
  }

  private func removeContinuation(_ identifier: UUID) {
    continuations.removeValue(forKey: identifier)
  }
}

private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
  let (result, overflow) = lhs.addingReportingOverflow(rhs)
  return overflow ? UInt64.max : result
}
