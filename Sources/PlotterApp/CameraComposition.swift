import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

struct OperatorWorkspaceDrawingRunCameraPort:
  PlotterDrawingRunCameraPort, PlotterDrawingRunVisionPort
{
  let actions: OperatorWorkspace.CameraActions

  func captureFrame(newerThan captureNanoseconds: UInt64) async throws -> DisplayedFrame {
    guard let frame = try await actions.captureFrame(captureNanoseconds),
      frame.frame.captureNanoseconds > captureNanoseconds
    else { throw LearningPathOperationError.freshFrameUnavailable }
    return frame
  }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    guard let observe = actions.observePlannedDrawingInk else {
      preconditionFailure("The production Drawing Run composition requires Vision observation.")
    }
    return await observe(request)
  }
}

enum CameraComposition {
  private static let session = CameraSourceSession()

  static let actions = makeActions(session: session)

  /// Produces an independently owned camera/vision composition for tests that
  /// exercise multiple workspaces concurrently in one process. Production uses
  /// `actions`, whose single session remains the application-wide hardware
  /// authority.
  static func makeIsolatedActionsForTesting() -> OperatorWorkspace.CameraActions {
    makeActions(session: CameraSourceSession())
  }

  private static func makeActions(session: CameraSourceSession) -> OperatorWorkspace.CameraActions {
    OperatorWorkspace.CameraActions(
      discover: {
        await session.discover()
      },
      select: { id in
        try await session.select(id)
      },
      start: {
        await session.start()
      },
      stop: {
        await session.stop()
      },
      restart: {
        await session.restart()
      },
      snapshot: {
        await session.snapshot()
      },
      frames: {
        await session.frames()
      },
      inspectWorkflowScene: { boundary, features, region in
        try await session.inspectWorkflowScene(
          newerThanNanoseconds: boundary,
          requestedFeatures: features,
          analysisRegion: region
        )
      },
      captureFrame: { boundary in
        try await session.captureFrame(newerThanNanoseconds: boundary)
      },
      captureStableWorkflowCap: StableWorkflowCapCaptureRunner { request in
        try await session.captureStableWorkflowCap(request)
      },
      setSceneAnalysisRegion: { region in
        await session.setSceneAnalysisRegion(region)
      },
      setPenCapColor: { color in
        await session.setPenCapColor(color)
      },
      setAutomaticInspection: { cadence, features in
        await session.setAutomaticInspection(cadence, requestedFeatures: features)
      },
      analysisUpdates: {
        await session.analysisUpdates()
      },
      visionDiagnostics: {
        await session.visionDiagnostics()
      },
      observePlannedDrawingInk: { request in
        await session.observePlannedDrawingInk(request)
      },
    )
  }
}
func boundedlyAwaitNewestCameraValue<Value: Sendable>(
  maximumAttempts: Int = 40,
  pollIntervalNanoseconds: UInt64 = 25_000_000,
  load: @Sendable () async throws -> Value?
) async throws -> Value? {
  precondition(maximumAttempts > 0)
  for attempt in 0..<maximumAttempts {
    if let value = try await load() { return value }
    guard attempt + 1 < maximumAttempts else { return nil }
    try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
  }
  return nil
}

struct CameraSourceSessionVisionDiagnostics: Sendable {
  let automaticInspectionConfigurationRevision: UInt64
  let automaticPipelineStartCallCount: UInt64
  let automaticFrameSubscriptionStartCount: UInt64
  let automaticPauseCallCount: UInt64
  let automaticFrameSubscriptionCancellationCount: UInt64
  let exclusiveLeaseBeginCount: UInt64
  let exclusiveLeaseEndCount: UInt64
  let exclusiveLeaseSuccessCount: UInt64
  let exclusiveLeaseFailureCount: UInt64
  let exclusiveLeaseCancellationCount: UInt64
  let automaticResumeAfterExclusiveCount: UInt64
  let activeExclusiveLeaseCount: Int
  let requestedCadence: VisionAnalysisCadence?
  let requestedFeatures: SceneFeatureSet
  let capture: CameraCaptureDiagnostics
  let pipeline: PlotterSceneAnalysisDiagnostics

  init(
    automaticInspectionConfigurationRevision: UInt64,
    automaticPipelineStartCallCount: UInt64,
    automaticFrameSubscriptionStartCount: UInt64,
    automaticPauseCallCount: UInt64,
    automaticFrameSubscriptionCancellationCount: UInt64,
    exclusiveLeaseBeginCount: UInt64,
    exclusiveLeaseEndCount: UInt64,
    exclusiveLeaseSuccessCount: UInt64 = 0,
    exclusiveLeaseFailureCount: UInt64 = 0,
    exclusiveLeaseCancellationCount: UInt64 = 0,
    automaticResumeAfterExclusiveCount: UInt64,
    activeExclusiveLeaseCount: Int,
    requestedCadence: VisionAnalysisCadence?,
    requestedFeatures: SceneFeatureSet,
    capture: CameraCaptureDiagnostics,
    pipeline: PlotterSceneAnalysisDiagnostics
  ) {
    self.automaticInspectionConfigurationRevision = automaticInspectionConfigurationRevision
    self.automaticPipelineStartCallCount = automaticPipelineStartCallCount
    self.automaticFrameSubscriptionStartCount = automaticFrameSubscriptionStartCount
    self.automaticPauseCallCount = automaticPauseCallCount
    self.automaticFrameSubscriptionCancellationCount =
      automaticFrameSubscriptionCancellationCount
    self.exclusiveLeaseBeginCount = exclusiveLeaseBeginCount
    self.exclusiveLeaseEndCount = exclusiveLeaseEndCount
    self.exclusiveLeaseSuccessCount = exclusiveLeaseSuccessCount
    self.exclusiveLeaseFailureCount = exclusiveLeaseFailureCount
    self.exclusiveLeaseCancellationCount = exclusiveLeaseCancellationCount
    self.automaticResumeAfterExclusiveCount = automaticResumeAfterExclusiveCount
    self.activeExclusiveLeaseCount = activeExclusiveLeaseCount
    self.requestedCadence = requestedCadence
    self.requestedFeatures = requestedFeatures
    self.capture = capture
    self.pipeline = pipeline
  }
}

enum CameraSourceSessionVisionLeaseError: Error, Equatable, Sendable {
  case inactiveLease
}

/// An owner-scoped capability for a caller-supplied exact Vision batch. Its
/// operations reuse the one CameraSourceSession lease that created it; an
/// escaped scope cannot operate after that lease settles.
struct CameraSourceSessionVisionLeaseScope: Sendable {
  fileprivate let session: CameraSourceSession
  fileprivate let leaseID: UUID

  func inspectWorkflowScene(
    newerThanNanoseconds boundary: UInt64 = 0,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws -> LiveSceneInspection? {
    try await session.inspectWorkflowSceneHoldingLease(
      leaseID: leaseID,
      newerThanNanoseconds: boundary,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion
    )
  }

  func captureFrame(
    newerThanNanoseconds boundary: UInt64 = 0
  ) async throws -> DisplayedFrame? {
    try await session.captureFrameHoldingLease(
      leaseID: leaseID,
      newerThanNanoseconds: boundary
    )
  }

  func publishValidatedFrame(
    _ displayedFrame: DisplayedFrame
  ) async throws -> ExactFramePublicationDisposition {
    try await session.publishValidatedFrameHoldingLease(
      leaseID: leaseID,
      displayedFrame
    )
  }
}

actor CameraSourceSession {
  private struct VisionComputationLease: Sendable {
    let id: UUID
    let previewPauseToken: CameraPreviewPauseToken
  }

  private enum VisionComputationLeaseDisposition {
    case succeeded
    case failed
    case cancelled
  }

  private let live: CameraCapture
  private let vision: VisionWorker
  private let analysisPipeline: PlotterSceneAnalysisPipeline
  private let plannedDrawingObserver:
    @Sendable (PlannedDrawingObservationRequest) async -> PlannedDrawingObservationOutcome
  private var automaticInspectionFrameTask: Task<Void, Never>?
  private var automaticInspectionCadence: VisionAnalysisCadence?
  private var automaticInspectionFeatures: SceneFeatureSet = []
  private var activeVisionComputationLeaseIDs: Set<UUID> = []
  private var sceneAnalysisRegion: PixelRect?
  private var penCapColor: PenCapColor = .green
  private var automaticInspectionConfigurationRevision: UInt64 = 0
  private var automaticPipelineStartCallCount: UInt64 = 0
  private var automaticFrameSubscriptionStartCount: UInt64 = 0
  private var automaticPauseCallCount: UInt64 = 0
  private var automaticFrameSubscriptionCancellationCount: UInt64 = 0
  private var exclusiveLeaseBeginCount: UInt64 = 0
  private var exclusiveLeaseEndCount: UInt64 = 0
  private var exclusiveLeaseSuccessCount: UInt64 = 0
  private var exclusiveLeaseFailureCount: UInt64 = 0
  private var exclusiveLeaseCancellationCount: UInt64 = 0
  private var automaticResumeAfterExclusiveCount: UInt64 = 0

  init() {
    let live = CameraCapture()
    let vision = VisionWorker()
    let analysisPipeline = PlotterSceneAnalysisPipeline(worker: vision)
    self.live = live
    self.vision = vision
    self.analysisPipeline = analysisPipeline
    plannedDrawingObserver = { request in
      await vision.observePlannedDrawingInk(request)
    }
  }

  /// Internal composition seam for deterministic lifecycle tests. Production
  /// continues to use `init()` and its one shared VisionWorker.
  init(
    live: CameraCapture,
    vision: VisionWorker,
    analysisPipeline: PlotterSceneAnalysisPipeline,
    plannedDrawingObserver: @escaping @Sendable (
      PlannedDrawingObservationRequest
    ) async -> PlannedDrawingObservationOutcome
  ) {
    self.live = live
    self.vision = vision
    self.analysisPipeline = analysisPipeline
    self.plannedDrawingObserver = plannedDrawingObserver
  }

  func discover() async -> CameraCaptureSnapshot {
    await live.discoverDevices()
    return await live.snapshot()
  }

  func select(_ id: CameraDeviceID) async throws -> CameraCaptureSnapshot {
    await stopAutomaticInspection()
    await setSceneAnalysisRegion(nil)
    try await live.select(id)
    return await live.snapshot()
  }

  func start() async -> CameraCaptureSnapshot {
    await live.start()
    return await live.snapshot()
  }

  func stop() async -> CameraCaptureSnapshot {
    await stopAutomaticInspection()
    await live.stop()
    return await live.snapshot()
  }

  func restart() async -> CameraCaptureSnapshot {
    await stopAutomaticInspection()
    await setSceneAnalysisRegion(nil)
    await live.restart()
    return await live.snapshot()
  }

  func snapshot() async -> CameraCaptureSnapshot {
    await live.snapshot()
  }

  func visionDiagnostics() async -> CameraSourceSessionVisionDiagnostics {
    CameraSourceSessionVisionDiagnostics(
      automaticInspectionConfigurationRevision: automaticInspectionConfigurationRevision,
      automaticPipelineStartCallCount: automaticPipelineStartCallCount,
      automaticFrameSubscriptionStartCount: automaticFrameSubscriptionStartCount,
      automaticPauseCallCount: automaticPauseCallCount,
      automaticFrameSubscriptionCancellationCount:
        automaticFrameSubscriptionCancellationCount,
      exclusiveLeaseBeginCount: exclusiveLeaseBeginCount,
      exclusiveLeaseEndCount: exclusiveLeaseEndCount,
      exclusiveLeaseSuccessCount: exclusiveLeaseSuccessCount,
      exclusiveLeaseFailureCount: exclusiveLeaseFailureCount,
      exclusiveLeaseCancellationCount: exclusiveLeaseCancellationCount,
      automaticResumeAfterExclusiveCount: automaticResumeAfterExclusiveCount,
      activeExclusiveLeaseCount: activeVisionComputationLeaseIDs.count,
      requestedCadence: automaticInspectionCadence,
      requestedFeatures: automaticInspectionFeatures,
      capture: await live.diagnostics(),
      pipeline: await analysisPipeline.diagnostics()
    )
  }

  func frames() async -> AsyncStream<DisplayedFrame> {
    await live.frames()
  }

  func inspectWorkflowScene(
    newerThanNanoseconds boundary: UInt64 = 0,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws
    -> LiveSceneInspection?
  {
    try await withExclusiveVisionLease { scope in
      try await scope.inspectWorkflowScene(
        newerThanNanoseconds: boundary,
        requestedFeatures: requestedFeatures,
        analysisRegion: analysisRegion
      )
    }
  }

  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame? {
    try await boundedlyAwaitNewestCameraValue {
      try await self.live.materializeLatestFrame(
        newerThanNanoseconds: boundary,
        policy: .returnOnly
      )
    }
  }

  func captureStableWorkflowCap(
    _ request: StableWorkflowCapCaptureRequest
  ) async throws -> StableWorkflowCapInspection {
    try await withExclusiveVisionLease { scope in
      var boundary = request.newerThanNanoseconds
      var samples: [StableWorkflowCapInspection] = []
      samples.reserveCapacity(FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount)

      for _ in 0..<FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount {
        try Task.checkCancellation()
        guard
          let inspection = try await scope.inspectWorkflowScene(
            newerThanNanoseconds: boundary,
            requestedFeatures: [.penCap],
            analysisRegion: nil
          ),
          inspection.displayedFrame.frame.captureNanoseconds > boundary
        else {
          throw LearningPathOperationError.freshFrameUnavailable
        }
        guard case .found(let cap, _) = inspection.measurement.penCap else {
          throw LearningPathOperationError.requiredState(
            "Pen-cap measurement refused: \(inspection.measurement.penCap.diagnosticReason)."
          )
        }
        samples.append(StableWorkflowCapInspection(inspection: inspection, cap: cap))
        boundary = inspection.displayedFrame.frame.captureNanoseconds
        try Task.checkCancellation()
      }

      let selected = try FixedCameraOpticalSettlingPolicy.newestStableCapSample(samples)
      try Task.checkCancellation()
      _ = try await scope.publishValidatedFrame(selected.inspection.displayedFrame)
      return selected
    }
  }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    do {
      return try await withExclusiveVisionLease { _ in
        await self.plannedDrawingObserver(request)
      }
    } catch {
      preconditionFailure("A nonthrowing planned-observation body unexpectedly threw: \(error)")
    }
  }

  /// Runs a caller-supplied async batch while one real preview/automatic-
  /// analysis lease remains held. The operation result is retained locally so
  /// settlement is awaited exactly once before success, failure, or
  /// cancellation is returned to the caller.
  func withExclusiveVisionLease<Output: Sendable>(
    _ operation: @escaping @Sendable (CameraSourceSessionVisionLeaseScope) async throws
      -> Output
  ) async throws -> Output {
    let lease = await beginExclusiveVisionComputation()
    let scope = CameraSourceSessionVisionLeaseScope(session: self, leaseID: lease.id)
    let operationResult: Result<Output, Error>
    do {
      operationResult = .success(try await operation(scope))
    } catch {
      operationResult = .failure(error)
    }
    let disposition: VisionComputationLeaseDisposition
    switch operationResult {
    case .success:
      disposition = Task.isCancelled ? .cancelled : .succeeded
    case .failure(let error):
      disposition = error is CancellationError || Task.isCancelled ? .cancelled : .failed
    }
    await endExclusiveVisionComputation(lease, disposition: disposition)
    return try operationResult.get()
  }

  fileprivate func inspectWorkflowSceneHoldingLease(
    leaseID: UUID,
    newerThanNanoseconds boundary: UInt64,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws -> LiveSceneInspection? {
    guard activeVisionComputationLeaseIDs.contains(leaseID) else {
      throw CameraSourceSessionVisionLeaseError.inactiveLease
    }
    guard
      let displayedFrame = try await boundedlyAwaitNewestCameraValue(
        load: {
          try await self.live.materializeLatestFrame(
            newerThanNanoseconds: boundary,
            policy: .returnOnly
          )
        }
      )
    else { return nil }
    let measurement = try await vision.inspectPlotterScene(
      in: displayedFrame.frame,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion,
      penCapColor: penCapColor
    )
    return LiveSceneInspection(displayedFrame: displayedFrame, measurement: measurement)
  }

  fileprivate func captureFrameHoldingLease(
    leaseID: UUID,
    newerThanNanoseconds boundary: UInt64
  ) async throws -> DisplayedFrame? {
    guard activeVisionComputationLeaseIDs.contains(leaseID) else {
      throw CameraSourceSessionVisionLeaseError.inactiveLease
    }
    return try await boundedlyAwaitNewestCameraValue {
      try await self.live.materializeLatestFrame(
        newerThanNanoseconds: boundary,
        policy: .returnOnly
      )
    }
  }

  fileprivate func publishValidatedFrameHoldingLease(
    leaseID: UUID,
    _ displayedFrame: DisplayedFrame
  ) async throws -> ExactFramePublicationDisposition {
    guard activeVisionComputationLeaseIDs.contains(leaseID) else {
      throw CameraSourceSessionVisionLeaseError.inactiveLease
    }
    return try await live.publishMaterializedExactFrame(displayedFrame)
  }

  func setSceneAnalysisRegion(_ region: PixelRect?) async {
    guard sceneAnalysisRegion != region else { return }
    sceneAnalysisRegion = region
    await analysisPipeline.setAnalysisRegion(region)
  }

  func setPenCapColor(_ color: PenCapColor) async {
    guard penCapColor != color else { return }
    penCapColor = color
    await analysisPipeline.setPenCapColor(color)
  }

  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?,
    requestedFeatures: SceneFeatureSet
  ) async
    -> PlotterSceneAnalysisSnapshot
  {
    let normalizedFeatures = cadence == nil ? SceneFeatureSet() : requestedFeatures
    guard
      automaticInspectionCadence != cadence
        || automaticInspectionFeatures != normalizedFeatures
    else { return await analysisPipeline.snapshot() }

    automaticInspectionConfigurationRevision &+= 1
    guard let cadence else {
      automaticInspectionCadence = nil
      automaticInspectionFeatures = []
      await pauseAutomaticInspection()
      return await analysisPipeline.snapshot()
    }
    automaticInspectionCadence = cadence
    automaticInspectionFeatures = normalizedFeatures
    guard activeVisionComputationLeaseIDs.isEmpty else {
      return await analysisPipeline.snapshot()
    }
    await startAutomaticInspection(cadence, requestedFeatures: normalizedFeatures)
    return await analysisPipeline.snapshot()
  }

  private func startAutomaticInspection(
    _ cadence: VisionAnalysisCadence,
    requestedFeatures: SceneFeatureSet
  ) async {
    let phase = await analysisPipeline.snapshot().phase
    if phase.state != .running(cadence) || phase.requestedFeatures != requestedFeatures {
      automaticPipelineStartCallCount &+= 1
      await analysisPipeline.start(cadence: cadence, requestedFeatures: requestedFeatures)
    }
    if automaticInspectionFrameTask == nil {
      automaticFrameSubscriptionStartCount &+= 1
      let stream = await live.frames()
      let pipeline = analysisPipeline
      automaticInspectionFrameTask = Task {
        for await displayedFrame in stream {
          guard !Task.isCancelled else { return }
          await pipeline.submit(displayedFrame)
        }
      }
    }
  }

  func analysisUpdates() async -> AsyncStream<PlotterSceneAnalysisSnapshot> {
    await analysisPipeline.updates()
  }

  private func stopAutomaticInspection() async {
    guard automaticInspectionCadence != nil || !automaticInspectionFeatures.isEmpty else {
      await pauseAutomaticInspection()
      return
    }
    automaticInspectionConfigurationRevision &+= 1
    automaticInspectionCadence = nil
    automaticInspectionFeatures = []
    await pauseAutomaticInspection()
  }

  private func pauseAutomaticInspection() async {
    let pipelineIsRunning = await analysisPipeline.snapshot().state != .stopped
    guard automaticInspectionFrameTask != nil || pipelineIsRunning else { return }
    automaticPauseCallCount &+= 1
    if automaticInspectionFrameTask != nil {
      automaticFrameSubscriptionCancellationCount &+= 1
    }
    automaticInspectionFrameTask?.cancel()
    automaticInspectionFrameTask = nil
    await analysisPipeline.stop()
  }

  private func beginExclusiveVisionComputation() async -> VisionComputationLease {
    exclusiveLeaseBeginCount &+= 1
    let previewPauseToken = await live.pausePreviewPublication()
    let id = UUID()
    let isFirstLease = activeVisionComputationLeaseIDs.isEmpty
    activeVisionComputationLeaseIDs.insert(id)
    if isFirstLease, automaticInspectionCadence != nil { await pauseAutomaticInspection() }
    return VisionComputationLease(
      id: id,
      previewPauseToken: previewPauseToken
    )
  }

  private func endExclusiveVisionComputation(
    _ lease: VisionComputationLease,
    disposition: VisionComputationLeaseDisposition
  ) async {
    guard activeVisionComputationLeaseIDs.remove(lease.id) != nil else { return }
    exclusiveLeaseEndCount &+= 1
    switch disposition {
    case .succeeded:
      exclusiveLeaseSuccessCount &+= 1
    case .failed:
      exclusiveLeaseFailureCount &+= 1
    case .cancelled:
      exclusiveLeaseCancellationCount &+= 1
    }
    await live.resumePreviewPublication(lease.previewPauseToken)
    guard activeVisionComputationLeaseIDs.isEmpty, let cadence = automaticInspectionCadence else {
      return
    }
    automaticResumeAfterExclusiveCount &+= 1
    await startAutomaticInspection(cadence, requestedFeatures: automaticInspectionFeatures)
  }

}
