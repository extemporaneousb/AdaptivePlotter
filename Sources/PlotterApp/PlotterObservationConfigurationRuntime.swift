import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

protocol PlotterObservationPreferencePort: Sendable {
  func loadLegacyPenCapAppearance() -> PenCapAppearanceSelection?
  func clearLegacyPenCapAppearance() throws
  func loadOverlayPreference() -> Set<UserSceneOverlay>?
  func persistOverlayPreference(_ values: Set<UserSceneOverlay>) throws
}

/// UserDefaults documents its instance methods as thread-safe. This wrapper
/// exposes only immutable namespace identity and atomic typed reads/writes;
/// ordering across related values remains owned by the observation runtime.
struct UserDefaultsObservationPreferencePort:
  PlotterObservationPreferencePort, @unchecked Sendable
{
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func loadLegacyPenCapAppearance() -> PenCapAppearanceSelection? {
    guard let data = defaults.data(forKey: "AdaptivePlotter.penCapAppearanceSelection") else {
      return nil
    }
    return try? JSONDecoder().decode(PenCapAppearanceSelection.self, from: data)
  }

  func clearLegacyPenCapAppearance() throws {
    defaults.removeObject(forKey: "AdaptivePlotter.penCapAppearanceSelection")
  }

  func loadOverlayPreference() -> Set<UserSceneOverlay>? {
    defaults.stringArray(forKey: "AdaptivePlotter.userSceneOverlays").map {
      Set($0.compactMap(UserSceneOverlay.init(rawValue:)))
    }
  }

  func persistOverlayPreference(_ values: Set<UserSceneOverlay>) throws {
    defaults.set(values.map(\.rawValue).sorted(), forKey: "AdaptivePlotter.userSceneOverlays")
  }
}

struct PlotterObservationConfigurationReference: Hashable, Sendable {
  let revision: UInt64
  let capabilityID: UUID
}

enum PlotterObservationConfigurationIntent: Hashable, Sendable {
  case refreshSources
  case selectLiveSource(CameraDeviceID)
  case startLiveSource
  case stopLiveSource
  case restartLiveSource
  case configureAutomaticAnalysis(
    cadence: VisionAnalysisCadence?,
    features: SceneFeatureSet,
    region: PixelRect?,
    penCapColor: PenCapColor?
  )
  case requestDiagnostics
}

enum PlotterObservationOperatorIntent: Hashable, Sendable {
  case refresh
  case selectSource(OperatorFrameMode, CameraDeviceID?)
  case stopLiveSource
  case restartLiveSource
  case setCadence(VisionAnalysisCadence)
  case setRegion(PixelRect?, displayedFrame: DisplayedFrame)
  case setOverlay(UserSceneOverlay, enabled: Bool)
  case requestDiagnostics
}

struct PlotterObservationOperatorSubmission: Hashable, Sendable {
  let reference: PlotterObservationConfigurationReference
  let intent: PlotterObservationOperatorIntent
}

struct PlotterObservationConfigurationProjection: Sendable {
  let reference: PlotterObservationConfigurationReference
  let frameMode: OperatorFrameMode
  let cameraDevices: [CameraDevice]
  let selectedCameraID: CameraDeviceID?
  let cameraIsLive: Bool
  let sourceChangeUnavailableReason: String?
  let calibrationBusyReason: String?
  let simulatorEvidenceLabel: String
  let simulatorSummary: String
  let cameraStateText: String
  let captureThroughputText: String
  let visionThroughputText: String
  let cameraError: String?
  let visionError: String?
  let cadence: VisionAnalysisCadence
  let regionLock: VideoAnalysisRegionLock?
  let overlayCards: [OverlayCardPresentation]
  let enabledOverlays: Set<UserSceneOverlay>
  let penCapAppearance: PenCapAppearanceSelection?

  func request(_ intent: PlotterObservationOperatorIntent)
    -> PlotterObservationOperatorSubmission
  {
    .init(reference: reference, intent: intent)
  }
}

struct PlotterObservationConfigurationSubmission: Hashable, Sendable {
  let reference: PlotterObservationConfigurationReference
  let intent: PlotterObservationConfigurationIntent
}

enum PlotterObservationConfigurationDisposition: Hashable, Sendable {
  case applied(revision: UInt64)
  case refused(String)
  case stale
  case failed(String)
}

enum PlotterObservationRuntimeEvent: Sendable {
  case camera(CameraCaptureSnapshot)
  case frame(DisplayedFrame)
  case analysis(PlotterSceneAnalysisSnapshot)
  case diagnostics(CameraSourceSessionVisionDiagnostics)
  case failure(String)
}

/// The single effect-producing authority for observation-source configuration.
/// CameraCapture and CameraSourceSession retain device, exact-frame, lease, and
/// Vision-pipeline ownership; this runtime owns admission, configuration order,
/// ambient subscriptions, and bounded shutdown around that lower nominal port.
actor PlotterObservationConfigurationRuntime {
  private struct ActiveSubmission {
    let id: UUID
    let task: Task<PlotterObservationConfigurationDisposition, Never>
  }

  private let lower: any PlotterObservationCameraSessionPort
  private let recordingStore: EpisodeRecordingStore?
  private let capabilityID = UUID()
  private var revision: UInt64 = 0
  private var admissionClosed = false
  private var activeSubmission: ActiveSubmission?
  private var frameSubscription: Task<Void, Never>?
  private var analysisSubscription: Task<Void, Never>?
  private var activeRecordedStream: CameraStreamIdentity?
  private var pendingRecordedStart: CameraStreamIdentity?
  private var pendingRecordedStop: CameraStreamIdentity?
  private var lastRecordingOffset: UInt64 = 0
  private var continuations:
    [UUID: AsyncStream<PlotterObservationRuntimeEvent>.Continuation] = [:]

  init(
    lower: any PlotterObservationCameraSessionPort,
    recordingStore: EpisodeRecordingStore? = nil
  ) {
    self.lower = lower
    self.recordingStore = recordingStore
  }

  func reference() -> PlotterObservationConfigurationReference {
    .init(revision: revision, capabilityID: capabilityID)
  }

  func updates() -> AsyncStream<PlotterObservationRuntimeEvent> {
    let id = UUID()
    return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
      guard !admissionClosed else {
        continuation.finish()
        return
      }
      continuation.onTermination = { [weak self] _ in
        Task { await self?.removeContinuation(id) }
      }
      continuations[id] = continuation
    }
  }

  func submit(_ submission: PlotterObservationConfigurationSubmission) async
    -> PlotterObservationConfigurationDisposition
  {
    guard !admissionClosed else { return .refused("Observation configuration is shut down.") }
    guard submission.reference.capabilityID == capabilityID else { return .refused("Invalid observation capability.") }
    guard submission.reference.revision == revision else { return .stale }
    guard activeSubmission == nil else {
      return .refused("Another observation configuration is still active.")
    }

    let id = UUID()
    let task = Task { await execute(submission) }
    activeSubmission = ActiveSubmission(id: id, task: task)
    let disposition = await task.value
    if activeSubmission?.id == id { activeSubmission = nil }
    return disposition
  }

  private func execute(_ submission: PlotterObservationConfigurationSubmission) async
    -> PlotterObservationConfigurationDisposition
  {
    do {
      try requireOpenEffectBoundary()
      switch submission.intent {
      case .refreshSources:
        let snapshot = await lower.discover()
        try requireOpenEffectBoundary()
        publish(.camera(snapshot))
      case .selectLiveSource(let id):
        await stopAmbientSubscriptions()
        try requireOpenEffectBoundary()
        let snapshot = try await lower.select(id)
        try requireOpenEffectBoundary()
        publish(.camera(snapshot))
      case .startLiveSource:
        try requireOpenEffectBoundary()
        let lifecycle = await lower.startLifecycle()
        try requireOpenEffectBoundary()
        try await recordStartLifecycle(lifecycle)
        try requireOpenEffectBoundary()
        publish(.camera(lifecycle.snapshot))
        startFrameSubscriptionIfNeeded()
      case .stopLiveSource:
        await stopAmbientSubscriptions()
        try requireOpenEffectBoundary()
        try await recordStopRequest()
        try requireOpenEffectBoundary()
        let snapshot = await lower.stop()
        try requireOpenEffectBoundary()
        try await recordStopSettlement()
        try requireOpenEffectBoundary()
        publish(.camera(snapshot))
      case .restartLiveSource:
        await stopAmbientSubscriptions()
        try requireOpenEffectBoundary()
        try await recordStopRequest()
        try requireOpenEffectBoundary()
        _ = await lower.stop()
        try requireOpenEffectBoundary()
        try await recordStopSettlement()
        try requireOpenEffectBoundary()
        let lifecycle = await lower.startLifecycle()
        try requireOpenEffectBoundary()
        try await recordStartLifecycle(lifecycle)
        try requireOpenEffectBoundary()
        publish(.camera(lifecycle.snapshot))
        startFrameSubscriptionIfNeeded()
      case .configureAutomaticAnalysis(let cadence, let features, let region, let color):
        try requireOpenEffectBoundary()
        await lower.setSceneAnalysisRegion(region)
        try requireOpenEffectBoundary()
        if let color {
          await lower.setPenCapColor(color)
          try requireOpenEffectBoundary()
        }
        let snapshot = await lower.setAutomaticInspection(cadence, requestedFeatures: features)
        try requireOpenEffectBoundary()
        publish(.analysis(snapshot))
        if cadence == nil {
          await stopAnalysisSubscription()
          try requireOpenEffectBoundary()
        } else {
          await stopAnalysisSubscription()
          try requireOpenEffectBoundary()
          startFrameSubscriptionIfNeeded()
          startAnalysisSubscriptionIfNeeded()
        }
      case .requestDiagnostics:
        try requireOpenEffectBoundary()
        let diagnostics = await lower.visionDiagnostics()
        try requireOpenEffectBoundary()
        publish(.diagnostics(diagnostics))
      }
      revision &+= 1
      return .applied(revision: revision)
    } catch is CancellationError {
      return .refused("Observation configuration was cancelled.")
    } catch {
      guard !admissionClosed, !Task.isCancelled else {
        return .refused("Observation configuration was cancelled.")
      }
      let detail = error.localizedDescription
      publish(.failure(detail))
      revision &+= 1
      return .failed(detail)
    }
  }

  func snapshot() async -> CameraCaptureSnapshot { await lower.snapshot() }

  func inspectWorkflowScene(
    newerThanNanoseconds boundary: UInt64,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws -> LiveSceneInspection? {
    guard !admissionClosed else { throw CancellationError() }
    return try await lower.inspectWorkflowScene(
      newerThanNanoseconds: boundary,
      requestedFeatures: requestedFeatures,
      analysisRegion: analysisRegion
    )
  }

  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame? {
    guard !admissionClosed else { throw CancellationError() }
    return try await lower.captureFrame(newerThanNanoseconds: boundary)
  }

  func captureStableWorkflowCap(
    _ request: StableWorkflowCapCaptureRequest
  ) async throws -> StableWorkflowCapInspection {
    guard !admissionClosed else { throw CancellationError() }
    return try await lower.captureStableWorkflowCap(request)
  }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    guard !admissionClosed else {
      return .rejected(try! DrawingObservationRejection(
        frames: request.frames,
        reason: .computationCancelled,
        algorithmRevisions: request.additionalAlgorithmRevisions.union([request.observerRevision])
      ))
    }
    return await lower.observePlannedDrawingInk(request)
  }

  func shutdown() async {
    guard !admissionClosed else { return }
    admissionClosed = true
    revision &+= 1
    let submission = activeSubmission
    activeSubmission = nil
    if let submission {
      submission.task.cancel()
      _ = await submission.task.value
    }
    await stopAmbientSubscriptions()
    await recordPendingStartCancellation()
    try? await recordStopRequest()
    _ = await lower.stop()
    try? await recordStopSettlement()
    if let recordingStore {
      do {
        try await recordingStore.close(at: lastRecordingOffset &+ 1)
      } catch {
        publish(.failure("Observation recording could not close: \(error.localizedDescription)"))
      }
    }
    let values = continuations.values
    continuations.removeAll()
    values.forEach { $0.finish() }
  }

  private func startFrameSubscriptionIfNeeded() {
    guard !admissionClosed, frameSubscription == nil else { return }
    let lower = lower
    frameSubscription = Task { [weak self] in
      let stream = await lower.frames()
      for await frame in stream {
        guard !Task.isCancelled, let self else { return }
        await self.record(frame)
        await self.publish(.frame(frame))
      }
    }
  }

  private func startAnalysisSubscriptionIfNeeded() {
    guard !admissionClosed, analysisSubscription == nil else { return }
    let lower = lower
    analysisSubscription = Task { [weak self] in
      let stream = await lower.analysisUpdates()
      for await snapshot in stream {
        guard !Task.isCancelled, let self else { return }
        await self.publish(.analysis(snapshot))
      }
    }
  }

  private func stopAmbientSubscriptions() async {
    let frame = frameSubscription
    let analysis = analysisSubscription
    frameSubscription = nil
    analysisSubscription = nil
    frame?.cancel()
    analysis?.cancel()
    await frame?.value
    await analysis?.value
  }

  private func stopAnalysisSubscription() async {
    let analysis = analysisSubscription
    analysisSubscription = nil
    analysis?.cancel()
    await analysis?.value
  }

  private func publish(_ event: PlotterObservationRuntimeEvent) {
    guard !admissionClosed else { return }
    continuations.values.forEach { $0.yield(event) }
  }

  private func removeContinuation(_ id: UUID) {
    continuations[id] = nil
  }

  private func requireOpenEffectBoundary() throws {
    guard !admissionClosed else { throw CancellationError() }
    try Task.checkCancellation()
  }

  private func recordStartLifecycle(
    _ lifecycle: PlotterObservationCameraLifecycleResult
  ) async throws {
    guard let recordingStore, let requested = lifecycle.requestedStream else { return }
    do {
      let offset = nextRecordingOffset(
        lifecycle.snapshot.latestFrame?.frame.captureNanoseconds ?? 0
      )
      _ = try await recordingStore.recordCameraLifecycle(.startRequested(requested), at: offset)
      pendingRecordedStart = requested
    } catch {
      publish(.failure("Camera start recording failed: \(error.localizedDescription)"))
      return
    }
    try requireOpenEffectBoundary()
    do {
      if case .running = lifecycle.snapshot.state,
        lifecycle.settledStream == requested
      {
        _ = try await recordingStore.recordCameraLifecycle(
          .started(requested),
          at: nextRecordingOffset(
            lifecycle.snapshot.latestFrame?.frame.captureNanoseconds ?? 0
          )
        )
        activeRecordedStream = requested
      } else {
        _ = try await recordingStore.recordCameraLifecycle(
          .failed(.init(
            operation: .start(requested),
            kind: .sourceUnavailable,
            diagnostic: lifecycle.snapshot.error?.actionableDescription
          )),
          at: nextRecordingOffset(
            lifecycle.snapshot.latestFrame?.frame.captureNanoseconds ?? 0
          )
        )
      }
      self.pendingRecordedStart = nil
    } catch {
      publish(.failure("Camera start settlement recording failed: \(error.localizedDescription)"))
    }
  }

  private func recordPendingStartCancellation() async {
    guard let recordingStore, let pendingRecordedStart else { return }
    do {
      _ = try await recordingStore.recordCameraLifecycle(
        .failed(.init(
          operation: .start(pendingRecordedStart),
          kind: .cancelled,
          diagnostic: "Observation configuration shut down before start settlement."
        )),
        at: nextRecordingOffset(0)
      )
      self.pendingRecordedStart = nil
    } catch {
      publish(.failure("Camera start cancellation recording failed: \(error.localizedDescription)"))
    }
  }

  private func recordStopRequest() async throws {
    guard let recordingStore, pendingRecordedStop == nil, let activeRecordedStream else { return }
    do {
      _ = try await recordingStore.recordCameraLifecycle(
        .stopRequested(activeRecordedStream),
        at: nextRecordingOffset(0)
      )
      pendingRecordedStop = activeRecordedStream
    } catch {
      publish(.failure("Camera stop recording failed: \(error.localizedDescription)"))
    }
  }

  private func recordStopSettlement() async throws {
    guard let recordingStore, let pendingRecordedStop else { return }
    do {
      _ = try await recordingStore.recordCameraLifecycle(
        .stopped(pendingRecordedStop),
        at: nextRecordingOffset(0)
      )
      self.activeRecordedStream = nil
      self.pendingRecordedStop = nil
    } catch {
      publish(.failure("Camera stop settlement recording failed: \(error.localizedDescription)"))
    }
  }

  private func record(_ frame: DisplayedFrame) async {
    guard let recordingStore else { return }
    let stream = recordingStream(frame)
    guard stream == activeRecordedStream else { return }
    do {
      _ = try await recordingStore.recordCameraFrame(
        .init(
          stream: stream,
          frameID: CameraFrameIdentity(rawValue: frame.frame.id.rawValue),
          sequence: frame.frame.sequence,
          captureNanoseconds: frame.frame.captureNanoseconds,
          width: frame.frame.width,
          height: frame.frame.height,
          rowBytes: frame.frame.rowBytes,
          pixelFormat: recordingPixelFormat(frame.frame.pixelFormat)
        ),
        bytes: frame.frame.bytes.data,
        at: nextRecordingOffset(frame.frame.captureNanoseconds)
      )
    } catch {
      publish(.failure("Camera frame recording failed: \(error.localizedDescription)"))
    }
  }

  private func recordingStream(_ frame: DisplayedFrame) -> CameraStreamIdentity {
    .init(
      source: CameraSourceIdentity(rawValue: String(describing: frame.source)),
      configuration: CameraConfigurationIdentity(rawValue: frame.frame.cameraConfigurationID.rawValue)
    )
  }

  private func recordingPixelFormat(_ format: FramePixelFormat) -> CameraPixelFormat {
    switch format {
    case .bgra8: .bgra8
    case .rgba8: .rgba8
    case .gray8: .gray8
    }
  }

  private func nextRecordingOffset(_ candidate: UInt64) -> UInt64 {
    let value = max(lastRecordingOffset &+ 1, candidate)
    lastRecordingOffset = value
    return value
  }
}
