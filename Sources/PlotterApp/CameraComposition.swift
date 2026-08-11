import Foundation
import PlotterModel
import PlotterRuntime

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
    inspectScene: { boundary in
      try await session.inspectScene(newerThanNanoseconds: boundary)
    },
    captureFrame: { boundary in
      try await session.captureFrame(newerThanNanoseconds: boundary)
    },
    captureSnapshot: {
      try await session.captureSnapshot()
    },
    setAutomaticInspection: { cadence in
      await session.setAutomaticInspection(cadence)
    },
    analysisUpdates: {
      await session.analysisUpdates()
    },
    observeIsolatedInk: { request in
      await session.observeIsolatedInk(request)
    },
    observeVisibilityTarget: { request, progress in
      await session.observeVisibilityTarget(request, progress: progress)
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

private actor AutomaticAnalysisPreviewGate {
  private let live: CameraCapture
  private var pauseToken: CameraPreviewPauseToken?
  private var analysisActive = false
  private var revision: UInt64 = 0

  init(live: CameraCapture) {
    self.live = live
  }

  func setAnalysisActive(_ active: Bool) async {
    revision &+= 1
    let requestedRevision = revision
    analysisActive = active
    if active {
      guard pauseToken == nil else { return }
      let issuedToken = await live.pausePreviewPublication()
      guard analysisActive, revision == requestedRevision, pauseToken == nil else {
        await live.resumePreviewPublication(issuedToken)
        return
      }
      pauseToken = issuedToken
      return
    }
    guard let pauseToken else { return }
    self.pauseToken = nil
    await live.resumePreviewPublication(pauseToken)
  }
}

private actor CameraSourceSession {
  private struct VisionComputationLease: Sendable {
    let previewPauseToken: CameraPreviewPauseToken
    let automaticCadenceToRestore: VisionAnalysisCadence?
  }

  private let live: CameraCapture
  private let vision: VisionWorker
  private let analysisPipeline: PlotterSceneAnalysisPipeline
  private let automaticAnalysisPreviewGate: AutomaticAnalysisPreviewGate
  private let startupFrameRecorder = StartupFrameRecorder()
  private var startupFrameTask: Task<Void, Never>?
  private var automaticInspectionFrameTask: Task<Void, Never>?
  private var automaticInspectionCadence: VisionAnalysisCadence?
  private var foregroundVisibilityObservationInProgress = false

  init() {
    let live = CameraCapture()
    let vision = VisionWorker()
    let previewGate = AutomaticAnalysisPreviewGate(live: live)
    self.live = live
    self.vision = vision
    automaticAnalysisPreviewGate = previewGate
    analysisPipeline = PlotterSceneAnalysisPipeline(
      worker: vision,
      activityHandler: { active in
        await previewGate.setAnalysisActive(active)
      }
    )
  }

  func discover() async -> CameraCaptureSnapshot {
    await live.discoverDevices()
    return await live.snapshot()
  }

  func select(_ id: CameraDeviceID) async throws -> CameraCaptureSnapshot {
    await stopAutomaticInspection()
    try await live.select(id)
    return await live.snapshot()
  }

  func start() async -> CameraCaptureSnapshot {
    await live.start()
    let snapshot = await live.snapshot()
    await beginStartupFrameRecordingIfNeeded(snapshot)
    return snapshot
  }

  func stop() async -> CameraCaptureSnapshot {
    await stopAutomaticInspection()
    await live.stop()
    return await live.snapshot()
  }

  func restart() async -> CameraCaptureSnapshot {
    await stopAutomaticInspection()
    await live.restart()
    let snapshot = await live.snapshot()
    await beginStartupFrameRecordingIfNeeded(snapshot)
    return snapshot
  }

  func snapshot() async -> CameraCaptureSnapshot {
    await live.snapshot()
  }

  func frames() async -> AsyncStream<DisplayedFrame> {
    await live.frames()
  }

  func inspectScene(newerThanNanoseconds boundary: UInt64 = 0) async throws
    -> LiveSceneInspection?
  {
    let lease = await beginExclusiveVisionComputation()
    do {
      guard
        let displayedFrame = try await boundedlyAwaitNewestCameraValue(
          load: {
            try await self.live.materializeLatestFrame(
              newerThanNanoseconds: boundary
            )
          }
        )
      else {
        await endExclusiveVisionComputation(lease)
        return nil
      }
      let measurement = try await vision.inspectPlotterScene(in: displayedFrame.frame)
      await endExclusiveVisionComputation(lease)
      return LiveSceneInspection(displayedFrame: displayedFrame, measurement: measurement)
    } catch {
      await endExclusiveVisionComputation(lease)
      throw error
    }
  }

  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame? {
    try await boundedlyAwaitNewestCameraValue {
      try await self.live.materializeLatestFrame(newerThanNanoseconds: boundary)
    }
  }

  func observeIsolatedInk(_ request: IsolatedInkObservationRequest) async
    -> IsolatedInkObservationOutcome
  {
    let lease = await beginExclusiveVisionComputation()
    let outcome = await vision.observeIsolatedInk(request)
    await endExclusiveVisionComputation(lease)
    return outcome
  }

  func observeVisibilityTarget(
    _ request: VisibilityTargetObservationRequest,
    progress: @escaping @Sendable (VisibilityTargetObservationProgress) -> Void
  ) async
    -> VisibilityTargetObservationOutcome
  {
    guard !foregroundVisibilityObservationInProgress else {
      return .rejected(.observationAlreadyInProgress)
    }
    foregroundVisibilityObservationInProgress = true
    let lease = await beginExclusiveVisionComputation()
    let outcome = await vision.observeVisibilityTarget(request, progress: progress)
    foregroundVisibilityObservationInProgress = false
    await endExclusiveVisionComputation(lease)
    return outcome
  }

  func captureSnapshot() async throws -> String {
    let snapshot = await live.snapshot()
    guard let displayedFrame = try await live.materializeLatestFrame(),
      let selectedDeviceID = snapshot.selectedDeviceID,
      let device = snapshot.devices.first(where: { $0.id == selectedDeviceID })
    else {
      throw CameraCaptureError.captureFailed("No current selected-camera frame is available.")
    }
    return try startupFrameRecorder.recordSnapshot(displayedFrame, device: device).path
  }

  func setAutomaticInspection(_ cadence: VisionAnalysisCadence?) async
    -> PlotterSceneAnalysisSnapshot
  {
    guard let cadence else {
      automaticInspectionCadence = nil
      await stopAutomaticInspection()
      return await analysisPipeline.snapshot()
    }
    automaticInspectionCadence = cadence
    guard !foregroundVisibilityObservationInProgress else {
      return await analysisPipeline.snapshot()
    }
    await startAutomaticInspection(cadence)
    return await analysisPipeline.snapshot()
  }

  private func startAutomaticInspection(_ cadence: VisionAnalysisCadence) async {
    await analysisPipeline.start(cadence: cadence)
    if automaticInspectionFrameTask == nil {
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

  private func beginStartupFrameRecordingIfNeeded(_ snapshot: CameraCaptureSnapshot) async {
    guard startupFrameTask == nil,
      case .running = snapshot.state,
      let selectedDeviceID = snapshot.selectedDeviceID,
      let device = snapshot.devices.first(where: { $0.id == selectedDeviceID })
    else { return }
    let stream = await live.frames()
    let recorder = startupFrameRecorder
    startupFrameTask = Task {
      do {
        let directory = try await recorder.record(frames: stream, device: device)
        print("Saved startup camera samples to \(directory.path)")
      } catch is CancellationError {
        return
      } catch {
        let message =
          (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        FileHandle.standardError.write(Data("Startup camera samples failed: \(message)\n".utf8))
      }
    }
  }

  private func stopAutomaticInspection() async {
    automaticInspectionCadence = nil
    await pauseAutomaticInspection()
  }

  private func pauseAutomaticInspection() async {
    automaticInspectionFrameTask?.cancel()
    automaticInspectionFrameTask = nil
    await analysisPipeline.stop()
  }

  private func beginExclusiveVisionComputation() async -> VisionComputationLease {
    let previewPauseToken = await live.pausePreviewPublication()
    let cadence = automaticInspectionCadence
    if cadence != nil { await pauseAutomaticInspection() }
    return VisionComputationLease(
      previewPauseToken: previewPauseToken,
      automaticCadenceToRestore: cadence
    )
  }

  private func endExclusiveVisionComputation(_ lease: VisionComputationLease) async {
    await live.resumePreviewPublication(lease.previewPauseToken)
    guard let cadence = lease.automaticCadenceToRestore,
      automaticInspectionCadence == cadence,
      !foregroundVisibilityObservationInProgress
    else { return }
    await startAutomaticInspection(cadence)
  }

}
