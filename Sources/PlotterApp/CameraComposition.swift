import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

struct PlotterApplicationRuntimeDrawingRunCameraPort:
  PlotterDrawingRunCameraPort, PlotterDrawingRunVisionPort
{
  let session: any PlotterObservationCameraSessionPort

  func captureFrame(newerThan captureNanoseconds: UInt64) async throws -> DisplayedFrame {
    guard let frame = try await session.captureFrame(newerThanNanoseconds: captureNanoseconds),
      frame.frame.captureNanoseconds > captureNanoseconds
    else { throw LearningPathOperationError.freshFrameUnavailable }
    return frame
  }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    return await session.observePlannedDrawingInk(request)
  }
}

protocol PlotterObservationCameraSessionPort: Sendable {
  func discover() async -> CameraCaptureSnapshot
  func select(_ id: CameraDeviceID) async throws -> CameraCaptureSnapshot
  func start() async -> CameraCaptureSnapshot
  func startLifecycle() async -> PlotterObservationCameraLifecycleResult
  func stop() async -> CameraCaptureSnapshot
  func restart() async -> CameraCaptureSnapshot
  func snapshot() async -> CameraCaptureSnapshot
  func frames() async -> AsyncStream<DisplayedFrame>
  func inspectWorkflowScene(
    newerThanNanoseconds boundary: UInt64,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws -> LiveSceneInspection?
  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame?
  func captureStableWorkflowCap(
    _ request: StableWorkflowCapCaptureRequest
  ) async throws -> StableWorkflowCapInspection
  func setSceneAnalysisRegion(_ region: PixelRect?) async
  func setPenCapReference(_ reference: PenCapVisualReference?) async
  func setTrackingReference(visualReference: PenCapVisualReference?, markerReference: SampledColorMarkerReference?) async
  func setTrackingOpticalConfiguration(_ optical: CameraOpticalConfigurationIdentity?) async
  func setPenCapColor(_ color: PenCapColor) async
  func setAutomaticInspection(
    _ cadence: VisionAnalysisCadence?,
    requestedFeatures: SceneFeatureSet
  ) async -> PlotterSceneAnalysisSnapshot
  func analysisUpdates() async -> AsyncStream<PlotterSceneAnalysisSnapshot>
  func visionDiagnostics() async -> CameraSourceSessionVisionDiagnostics
  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome
}

struct PlotterObservationCameraLifecycleResult: Sendable {
  let snapshot: CameraCaptureSnapshot
  let requestedStream: CameraStreamIdentity?
  let settledStream: CameraStreamIdentity?

  /// A camera configuration is not authoritative until the lower camera owner
  /// returns an exact frame carrying both source and configuration identity.
  /// Absence therefore remains nil instead of borrowing a pre-start frame.
  static func exactFrameBacked(
    _ snapshot: CameraCaptureSnapshot
  ) -> PlotterObservationCameraLifecycleResult {
    let stream: CameraStreamIdentity?
    if case .running = snapshot.state, let frame = snapshot.latestFrame {
      stream = CameraStreamIdentity(
        source: CameraSourceIdentity(rawValue: String(describing: frame.source)),
        configuration: CameraConfigurationIdentity(
          rawValue: frame.frame.cameraConfigurationID.rawValue
        )
      )
    } else {
      stream = nil
    }
    return .init(snapshot: snapshot, requestedStream: stream, settledStream: stream)
  }
}

extension PlotterObservationCameraSessionPort {
  func setTrackingReference(visualReference: PenCapVisualReference?, markerReference: SampledColorMarkerReference?) async {
    await setPenCapReference(visualReference)
  }
  func setTrackingOpticalConfiguration(_ optical: CameraOpticalConfigurationIdentity?) async {}

  func startLifecycle() async -> PlotterObservationCameraLifecycleResult {
    .exactFrameBacked(await start())
  }
}

enum CameraComposition {
  private static let session = CameraSourceSession()

  static let observationSession: any PlotterObservationCameraSessionPort = session
  static let recordingStore: EpisodeRecordingStore? = {
    let id = EpisodeRecordingID(rawValue: UUID())
    do {
      let directory = AdaptivePlotterStoragePaths.production.episodeRecordingDirectory(id.rawValue)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      return try EpisodeRecordingStore.open(
        directoryURL: directory,
        recordingID: id,
        schemaRevision: EpisodeRecordingSchemaRevision(
          rawValue: "adaptive-plotter-observation-configuration-v1"
        ),
        frameRetentionPolicy: EpisodeFrameRetentionPolicy(
          maximumUniqueFrameCount: 256,
          maximumTotalUniqueFrameBytes: 1_024 * 1_024 * 1_024
        )
      )
    } catch {
      return nil
    }
  }()

  /// Produces an independently owned camera/vision composition for tests that
  /// exercise multiple workspaces concurrently in one process. Production uses
  /// `actions`, whose single session remains the application-wide hardware
  /// authority.
  static func makeIsolatedObservationSessionForTesting()
    -> any PlotterObservationCameraSessionPort
  {
    CameraSourceSession()
  }
}

protocol CameraNewestValueLoader: Sendable {
  associatedtype Value: Sendable

  func loadNewestValue() async throws -> Value?
}

struct CameraMaterializedFrameLoader: CameraNewestValueLoader {
  let capture: CameraCapture
  let newerThanNanoseconds: UInt64

  func loadNewestValue() async throws -> DisplayedFrame? {
    try await capture.materializeLatestFrame(
      newerThanNanoseconds: newerThanNanoseconds,
      policy: .returnOnly
    )
  }
}

func boundedlyAwaitNewestCameraValue<Loader: CameraNewestValueLoader>(
  maximumAttempts: Int = 40,
  pollIntervalNanoseconds: UInt64 = 25_000_000,
  loader: Loader
) async throws -> Loader.Value? {
  precondition(maximumAttempts > 0)
  for attempt in 0..<maximumAttempts {
    if let value = try await loader.loadNewestValue() { return value }
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
  let trackingEvidenceFailure: String?

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
    pipeline: PlotterSceneAnalysisDiagnostics,
    trackingEvidenceFailure: String? = nil
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
    self.trackingEvidenceFailure = trackingEvidenceFailure
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
    analysisRegion: PixelRect?,
    searchCenter: Point2<CameraPixelSpace>? = nil
  ) async throws -> LiveSceneInspection? {
    try await session.inspectWorkflowSceneHoldingLease(
      leaseID: leaseID,
      newerThanNanoseconds: boundary,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion,
      searchCenter: searchCenter
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

protocol CameraSourceSessionVisionLeaseOperation: Sendable {
  associatedtype Output: Sendable

  func perform(
    in scope: CameraSourceSessionVisionLeaseScope
  ) async throws -> Output
}

struct CameraWorkflowSceneInspectionLeaseOperation: CameraSourceSessionVisionLeaseOperation {
  let newerThanNanoseconds: UInt64
  let requestedFeatures: SceneFeatureSet
  let analysisRegion: PixelRect?

  func perform(
    in scope: CameraSourceSessionVisionLeaseScope
  ) async throws -> LiveSceneInspection? {
    try await scope.inspectWorkflowScene(
      newerThanNanoseconds: newerThanNanoseconds,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion
    )
  }
}

struct CameraStableWorkflowCapLeaseOperation: CameraSourceSessionVisionLeaseOperation {
  let request: StableWorkflowCapCaptureRequest

  func perform(
    in scope: CameraSourceSessionVisionLeaseScope
  ) async throws -> StableWorkflowCapInspection {
    var boundary = request.newerThanNanoseconds
    var samples: [StableWorkflowCapInspection] = []
    var firstFrame: DisplayedFrame?
    samples.reserveCapacity(FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount)

    // An occlusion is an observation gap, not a failed marking attempt. Keep
    // the existing cancellable owner at its settled pose and look on newer
    // frames. Never substitute the predicted position or bridge a missing
    // observation with earlier samples. Stop/Cancel still cancels this lease.
    while samples.count < FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount {
      try Task.checkCancellation()
      guard
        let inspection = try await scope.inspectWorkflowScene(
          newerThanNanoseconds: boundary,
          requestedFeatures: [.penCap],
          analysisRegion: nil,
          searchCenter: request.searchCenter
        ),
        inspection.displayedFrame.frame.captureNanoseconds > boundary
      else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
      let frame = inspection.displayedFrame
      if let firstFrame {
        guard firstFrame.source == frame.source,
          firstFrame.frame.cameraConfigurationID == frame.frame.cameraConfigurationID,
          firstFrame.frame.width == frame.frame.width,
          firstFrame.frame.height == frame.frame.height,
          firstFrame.frame.pixelFormat == frame.frame.pixelFormat else {
          throw LearningPathOperationError.requiredState(
            "Camera source or configuration changed while looking for the pen cap.")
        }
      } else {
        firstFrame = frame
      }
      boundary = frame.frame.captureNanoseconds
      switch inspection.measurement.penCap {
      case .found(let cap, _):
        samples.append(StableWorkflowCapInspection(inspection: inspection, cap: cap))
      case .notFound, .ambiguous:
        samples.removeAll(keepingCapacity: true)
        // Bound scan cadence during a prolonged obstruction. This sleep is
        // cooperative: explicit cancellation releases the sole Vision lease.
        try await Task.sleep(nanoseconds: 100_000_000)
      case .notRequested, .failed:
        throw LearningPathOperationError.requiredState(
          "Pen-cap analysis is unavailable: \(inspection.measurement.penCap.diagnosticReason).")
      }
      try Task.checkCancellation()
    }

    let selected = try FixedCameraOpticalSettlingPolicy.newestCompatibleCapSample(samples)
    try Task.checkCancellation()
    _ = try await scope.publishValidatedFrame(selected.inspection.displayedFrame)
    try Task.checkCancellation()
    return selected
  }
}

protocol CameraPlannedDrawingObserverPort: Sendable {
  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome
}

extension VisionWorker: CameraPlannedDrawingObserverPort {}

struct CameraPlannedDrawingObservationLeaseOperation: CameraSourceSessionVisionLeaseOperation {
  let observer: any CameraPlannedDrawingObserverPort
  let request: PlannedDrawingObservationRequest

  func perform(
    in _: CameraSourceSessionVisionLeaseScope
  ) async throws -> PlannedDrawingObservationOutcome {
    await observer.observePlannedDrawingInk(request)
  }
}

actor CameraSourceSession: PlotterObservationCameraSessionPort {
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
  private let plannedDrawingObserver: any CameraPlannedDrawingObserverPort
  private let trackingEvidenceRecorder: TrackingAcquisitionEvidenceRecorder?
  private var automaticInspectionFrameTask: Task<Void, Never>?
  private var automaticInspectionCadence: VisionAnalysisCadence?
  private var automaticInspectionFeatures: SceneFeatureSet = []
  private var activeVisionComputationLeaseIDs: Set<UUID> = []
  private var sceneAnalysisRegion: PixelRect?
  private var penCapColor: PenCapColor = .green
  private var penCapReference: PenCapVisualReference?
  private var markerReference: SampledColorMarkerReference?
  private var trackingOpticalConfiguration: CameraOpticalConfigurationIdentity?
  private var trackingConfigurationRevision: UInt64 = 0
  private var trackingEvidenceFailure: String?
  private struct TrackingInspectionEvidence: Sendable {
    let frame: DisplayedFrame
    let detection: PenCapDetectionResult?
    let reference: PenCapVisualReference?
    let priors: PlotterSceneVisionPriors
    var analysisElapsedNanoseconds: UInt64? = nil
  }
  private var pendingTrackingEvidenceWrites = 0
  private var trackingEvidenceAttempt: UInt64 = 0
  private var trackingInspectionsByLease: [UUID: TrackingInspectionEvidence] = [:]
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
    plannedDrawingObserver = vision
    trackingEvidenceRecorder = .shared
  }

  /// Internal composition seam for deterministic lifecycle tests. Production
  /// continues to use `init()` and its one shared VisionWorker.
  init(
    live: CameraCapture,
    vision: VisionWorker,
    analysisPipeline: PlotterSceneAnalysisPipeline,
    plannedDrawingObserver: any CameraPlannedDrawingObserverPort,
    trackingEvidenceRecorder: TrackingAcquisitionEvidenceRecorder? = nil
  ) {
    self.live = live
    self.vision = vision
    self.analysisPipeline = analysisPipeline
    self.plannedDrawingObserver = plannedDrawingObserver
    self.trackingEvidenceRecorder = trackingEvidenceRecorder
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
      pipeline: await analysisPipeline.diagnostics(),
      trackingEvidenceFailure: trackingEvidenceFailure
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
    try await withExclusiveVisionLease(CameraWorkflowSceneInspectionLeaseOperation(
      newerThanNanoseconds: boundary,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion
    ))
  }

  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame? {
    try await boundedlyAwaitNewestCameraValue(loader: CameraMaterializedFrameLoader(
      capture: live,
      newerThanNanoseconds: boundary
    ))
  }

  func captureStableWorkflowCap(
    _ request: StableWorkflowCapCaptureRequest
  ) async throws -> StableWorkflowCapInspection {
    try await withExclusiveVisionLease(CameraStableWorkflowCapLeaseOperation(request: request),
      trackingRequest: request)
  }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    do {
      return try await withExclusiveVisionLease(CameraPlannedDrawingObservationLeaseOperation(
        observer: plannedDrawingObserver,
        request: request
      ))
    } catch {
      preconditionFailure("A nonthrowing planned-observation body unexpectedly threw: \(error)")
    }
  }

  /// Runs a nominal async batch while one real preview/automatic-
  /// analysis lease remains held. The operation result is retained locally so
  /// settlement is awaited exactly once before success, failure, or
  /// cancellation is returned to the caller.
  func withExclusiveVisionLease<Operation: CameraSourceSessionVisionLeaseOperation>(
    _ operation: Operation,
    trackingRequest: StableWorkflowCapCaptureRequest? = nil
  ) async throws -> Operation.Output {
    let lease = await beginExclusiveVisionComputation()
    let scope = CameraSourceSessionVisionLeaseScope(session: self, leaseID: lease.id)
    let operationResult: Result<Operation.Output, Error>
    do {
      operationResult = .success(try await operation.perform(in: scope))
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
    let trackingEvidence = trackingInspectionsByLease[lease.id]
    await endExclusiveVisionComputation(lease, disposition: disposition)
    if let trackingRequest {
      let phase: TrackingAcquisitionPhase
      let detail: String?
      switch operationResult {
      case .success:
        phase = Task.isCancelled ? .cancelled : .success
        detail = Task.isCancelled ? "Acquisition cancelled during publication settlement." : nil
      case .failure(let error):
        phase = error is CancellationError || Task.isCancelled ? .cancelled : .failure
        detail = String(describing: error)
      }
      queueTrackingAcquisition(evidence: trackingEvidence, leaseID: lease.id,
        request: trackingRequest, phase: phase, detail: detail)
      // Stable capture must not return success after cancellation during settlement.
      // Other operations may represent cancellation in their nonthrowing output.
      if case .success = operationResult { try Task.checkCancellation() }
    }
    return try operationResult.get()
  }

  fileprivate func inspectWorkflowSceneHoldingLease(
    leaseID: UUID,
    newerThanNanoseconds boundary: UInt64,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?,
    searchCenter: Point2<CameraPixelSpace>?
  ) async throws -> LiveSceneInspection? {
    guard activeVisionComputationLeaseIDs.contains(leaseID) else {
      throw CameraSourceSessionVisionLeaseError.inactiveLease
    }
    guard
      let displayedFrame = try await boundedlyAwaitNewestCameraValue(
        loader: CameraMaterializedFrameLoader(
          capture: live,
          newerThanNanoseconds: boundary
        )
      )
    else { return nil }
    let reference = penCapReference
    let marker = markerReference
    let revision = trackingConfigurationRevision
    let binding = trackingOpticalConfiguration.flatMap { optical in
      if let marker {
        return PenCapReferenceBinding(markerReference: marker, frame: displayedFrame, opticalConfiguration: optical)
      }
      return reference.flatMap { PenCapReferenceBinding(reference: $0,
        frame: displayedFrame, opticalConfiguration: optical) }
    }
    let priors = try PlotterSceneVisionPriors.sceneDefaults(
      frameWidth: displayedFrame.frame.width, frameHeight: displayedFrame.frame.height,
      analysisRegion: analysisRegion, penCapColor: penCapColor, penCapReference: reference,
      markerReference: marker,
      referenceBinding: binding, searchCenter: searchCenter)
    // Preserve the actual input before the first suspension into Vision. A
    // thrown/cancelled analysis must not retain the preceding sample instead.
    trackingInspectionsByLease[leaseID] = .init(frame: displayedFrame, detection: nil,
      reference: reference, priors: priors)
    let analysisStarted = DispatchTime.now().uptimeNanoseconds
    let measurement: PlotterSceneMeasurement
    do {
      measurement = try await vision.inspectPlotterScene(
        in: displayedFrame.frame, requestedFeatures: requestedFeatures, priors: priors)
    } catch {
      trackingInspectionsByLease[leaseID] = .init(frame: displayedFrame, detection: nil,
        reference: reference, priors: priors,
        analysisElapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - analysisStarted)
      throw error
    }
    let inspection = LiveSceneInspection(displayedFrame: displayedFrame, measurement: measurement)
    trackingInspectionsByLease[leaseID] = .init(frame: displayedFrame, detection: measurement.penCap,
      reference: reference, priors: priors,
      analysisElapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - analysisStarted)
    guard revision == trackingConfigurationRevision else {
      throw LearningPathOperationError.requiredState("The tracking reference or camera optics changed during acquisition. Retry with the current reference.")
    }
    return inspection
  }

  private func queueTrackingAcquisition(
    evidence: TrackingInspectionEvidence?, leaseID: UUID, request: StableWorkflowCapCaptureRequest,
    phase: TrackingAcquisitionPhase, detail: String?
  ) {
    guard let trackingEvidenceRecorder else { return }
    trackingEvidenceAttempt &+= 1
    let attempt = trackingEvidenceAttempt
    guard let evidence else {
      trackingEvidenceFailure = "No analyzed frame was available to retain for this acquisition (\(phase.rawValue))."
      return
    }
    // Bound queued raw images before spawning work. Disk persistence does not
    // hold a camera lease or delay Stop/Cancel settlement.
    guard pendingTrackingEvidenceWrites < 2 else {
      trackingEvidenceFailure = "Tracking evidence queue is full; this acquisition was not retained."
      return
    }
    pendingTrackingEvidenceWrites += 1
    var owner = ["operation": "stable-workflow-reference", "leaseID": leaseID.uuidString]
    if let detail { owner["terminalDetail"] = detail }
    if let binding = evidence.priors.referenceBinding {
      owner["boundCaptureConfigurationID"] = binding.cameraConfigurationID.description
      owner["boundReferenceIdentity"] = binding.referenceIdentity
    }
    let ownerEvidence = owner
    Task {
      let failure = await trackingEvidenceRecorder.record(
        frame: evidence.frame, reference: evidence.reference, detection: evidence.detection,
        searchCenter: request.searchCenter, phase: phase, acquisitionID: leaseID,
        newerThanNanoseconds: request.newerThanNanoseconds, ownerEvidence: ownerEvidence,
        priors: evidence.priors, context: request.diagnosticContext,
        markerReference: evidence.priors.markerReference,
        analysisElapsedNanoseconds: evidence.analysisElapsedNanoseconds)
      finishTrackingEvidenceWrite(failure, attempt: attempt)
    }
  }

  private func finishTrackingEvidenceWrite(_ failure: String?, attempt: UInt64) {
    pendingTrackingEvidenceWrites -= 1
    // An older write cannot erase a newer overflow or missing-frame warning.
    if attempt == trackingEvidenceAttempt { trackingEvidenceFailure = failure }
  }

  fileprivate func captureFrameHoldingLease(
    leaseID: UUID,
    newerThanNanoseconds boundary: UInt64
  ) async throws -> DisplayedFrame? {
    guard activeVisionComputationLeaseIDs.contains(leaseID) else {
      throw CameraSourceSessionVisionLeaseError.inactiveLease
    }
    return try await boundedlyAwaitNewestCameraValue(loader: CameraMaterializedFrameLoader(
      capture: live,
      newerThanNanoseconds: boundary
    ))
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

  func setTrackingOpticalConfiguration(_ optical: CameraOpticalConfigurationIdentity?) async {
    guard trackingOpticalConfiguration != optical else { return }
    trackingConfigurationRevision &+= 1
    trackingOpticalConfiguration = optical
    await analysisPipeline.setTrackingOpticalConfiguration(optical)
  }

  func setPenCapReference(_ reference: PenCapVisualReference?) async {
    await setTrackingReference(visualReference: reference, markerReference: reference == nil ? markerReference : nil)
  }

  func setTrackingReference(visualReference: PenCapVisualReference?, markerReference: SampledColorMarkerReference?) async {
    guard penCapReference != visualReference || self.markerReference != markerReference else { return }
    trackingConfigurationRevision &+= 1
    penCapReference = visualReference
    self.markerReference = markerReference
    await analysisPipeline.setTrackingReference(visualReference: visualReference, markerReference: markerReference)
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
    let frameTask = automaticInspectionFrameTask
    guard frameTask != nil || pipelineIsRunning else {
      await analysisPipeline.stop()
      return
    }
    automaticPauseCallCount &+= 1
    if frameTask != nil {
      automaticFrameSubscriptionCancellationCount &+= 1
    }
    automaticInspectionFrameTask = nil
    if let frameTask {
      frameTask.cancel()
      _ = await frameTask.value
    }
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
    trackingInspectionsByLease[lease.id] = nil
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
