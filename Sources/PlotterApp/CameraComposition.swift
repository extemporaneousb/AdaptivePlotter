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
      observeIsolatedInk: { request in
        await session.observeIsolatedInk(request)
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

private actor CameraSourceSession {
  private struct VisionComputationLease: Sendable {
    let id: UUID
    let previewPauseToken: CameraPreviewPauseToken
  }

  private let live: CameraCapture
  private let vision: VisionWorker
  private let analysisPipeline: PlotterSceneAnalysisPipeline
  private let startupFrameRecorder = StartupFrameRecorder()
  private var startupFrameTask: Task<Void, Never>?
  private var automaticInspectionFrameTask: Task<Void, Never>?
  private var automaticInspectionCadence: VisionAnalysisCadence?
  private var automaticInspectionFeatures: SceneFeatureSet = []
  private var activeVisionComputationLeaseIDs: Set<UUID> = []
  private var sceneAnalysisRegion: PixelRect?
  private var penCapColor: PenCapColor = .green

  init() {
    let live = CameraCapture()
    let vision = VisionWorker()
    self.live = live
    self.vision = vision
    analysisPipeline = PlotterSceneAnalysisPipeline(worker: vision)
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
    await setSceneAnalysisRegion(nil)
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

  func inspectWorkflowScene(
    newerThanNanoseconds boundary: UInt64 = 0,
    requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?
  ) async throws
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
      let measurement = try await vision.inspectPlotterScene(
        in: displayedFrame.frame,
        requestedFeatures: requestedFeatures,
        analysisRegion: analysisRegion,
        penCapColor: penCapColor
      )
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

  func setSceneAnalysisRegion(_ region: PixelRect?) async {
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
    guard let cadence else {
      automaticInspectionCadence = nil
      automaticInspectionFeatures = []
      await stopAutomaticInspection()
      return await analysisPipeline.snapshot()
    }
    automaticInspectionCadence = cadence
    automaticInspectionFeatures = requestedFeatures
    guard activeVisionComputationLeaseIDs.isEmpty else {
      await pauseAutomaticInspection()
      return await analysisPipeline.snapshot()
    }
    await startAutomaticInspection(cadence, requestedFeatures: requestedFeatures)
    return await analysisPipeline.snapshot()
  }

  private func startAutomaticInspection(
    _ cadence: VisionAnalysisCadence,
    requestedFeatures: SceneFeatureSet
  ) async {
    await analysisPipeline.start(cadence: cadence, requestedFeatures: requestedFeatures)
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
    let id = UUID()
    let isFirstLease = activeVisionComputationLeaseIDs.isEmpty
    activeVisionComputationLeaseIDs.insert(id)
    if isFirstLease, automaticInspectionCadence != nil { await pauseAutomaticInspection() }
    return VisionComputationLease(
      id: id,
      previewPauseToken: previewPauseToken
    )
  }

  private func endExclusiveVisionComputation(_ lease: VisionComputationLease) async {
    guard activeVisionComputationLeaseIDs.remove(lease.id) != nil else { return }
    await live.resumePreviewPublication(lease.previewPauseToken)
    guard activeVisionComputationLeaseIDs.isEmpty, let cadence = automaticInspectionCadence else {
      return
    }
    await startAutomaticInspection(cadence, requestedFeatures: automaticInspectionFeatures)
  }

}
