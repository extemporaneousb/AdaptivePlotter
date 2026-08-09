import Foundation
import PlotterModel
import PlotterRuntime

enum CameraComposition {
  private static let session = CameraSourceSession()

  static let actions = OperatorWorkspace.CameraActions(
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
    observeVisibilityTarget: { request in
      await session.observeVisibilityTarget(request)
    },
  )
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
  private let live = CameraCapture()
  private let vision: VisionWorker
  private let analysisPipeline: PlotterSceneAnalysisPipeline
  private let startupFrameRecorder = StartupFrameRecorder()
  private var startupFrameTask: Task<Void, Never>?
  private var automaticInspectionFrameTask: Task<Void, Never>?

  init() {
    let vision = VisionWorker()
    self.vision = vision
    analysisPipeline = PlotterSceneAnalysisPipeline(worker: vision)
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
    guard
      let displayedFrame = try await boundedlyAwaitNewestCameraValue(
        load: {
          try await self.live.materializeLatestFrame(
            newerThanNanoseconds: boundary
          )
        }
      )
    else { return nil }
    let measurement = try await vision.inspectPlotterScene(in: displayedFrame.frame)
    return LiveSceneInspection(displayedFrame: displayedFrame, measurement: measurement)
  }

  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame? {
    try await boundedlyAwaitNewestCameraValue {
      try await self.live.materializeLatestFrame(newerThanNanoseconds: boundary)
    }
  }

  func observeIsolatedInk(_ request: IsolatedInkObservationRequest) async
    -> IsolatedInkObservationOutcome
  {
    await vision.observeIsolatedInk(request)
  }

  func observeVisibilityTarget(_ request: VisibilityTargetObservationRequest) async
    -> VisibilityTargetObservationOutcome
  {
    await vision.observeVisibilityTarget(request)
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
      await stopAutomaticInspection()
      return await analysisPipeline.snapshot()
    }
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
    return await analysisPipeline.snapshot()
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
    automaticInspectionFrameTask?.cancel()
    automaticInspectionFrameTask = nil
    await analysisPipeline.stop()
  }

}
