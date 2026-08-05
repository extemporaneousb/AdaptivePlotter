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
    inspectScene: {
      try await session.inspectScene()
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
    simulatedContent: { mode in
      try await session.simulatedContent(mode: mode)
    }
  )
}

private actor CameraSourceSession {
  private let live = CameraCapture()
  private let vision: VisionWorker
  private let analysisPipeline: PlotterSceneAnalysisPipeline
  private let startupFrameRecorder = StartupFrameRecorder()
  private var simulator: SimulatedFrameSource
  private let learningDemonstration: SimulatedLearningDemonstration
  private var startupFrameTask: Task<Void, Never>?
  private var automaticInspectionFrameTask: Task<Void, Never>?

  init() {
    let vision = VisionWorker()
    self.vision = vision
    analysisPipeline = PlotterSceneAnalysisPipeline(worker: vision)
    do {
      let fieldToCamera = try AffineTransform2<FieldSpace, CameraPixelSpace>(
        m11: 2.5,
        m12: 0,
        m21: 0,
        m22: -2.5,
        tx: 70,
        ty: 390
      )
      simulator = try SimulatedFrameSource(
        width: 640,
        height: 480,
        fieldToCamera: fieldToCamera,
        cameraConfigurationID: CameraConfigurationID(),
        initialSequence: 0
      )
      learningDemonstration = try SimulatedLearningDemonstration.standard()
    } catch {
      preconditionFailure("Invalid deterministic simulator composition: \(error)")
    }
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

  func inspectScene() async throws -> LiveSceneInspection? {
    guard let displayedFrame = try await live.materializeLatestFrame() else { return nil }
    let measurement = try await vision.inspectPlotterScene(in: displayedFrame.frame)
    return LiveSceneInspection(displayedFrame: displayedFrame, measurement: measurement)
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

  func simulatedContent(mode: SimulatorModelMode) throws -> SimulatedActionSurfaceContent {
    let scene = mode == .prior
      ? learningDemonstration.priorScene
      : learningDemonstration.trainedScene
    let content = try simulator.renderModelMismatch(scene)
    return SimulatedActionSurfaceContent(
      displayedFrame: content.displayedFrame,
      overlays: content.overlays,
      evidenceLabel: SimulatedOverlaySceneContent.evidenceLabel,
      commandedPenState: content.penState ?? .unknown,
      learningSummary: learningDemonstration.summary(for: mode)
    )
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

private struct SimulatedLearningDemonstration: Sendable {
  let priorScene: SimulatedModelMismatchScene
  let trainedScene: SimulatedModelMismatchScene
  let candidate: DrawingModelCandidate
  let accepted: AcceptedDrawingModelSnapshot

  static func standard() throws -> Self {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: 0, minY: 0, maxX: 220, maxY: 120
    )
    let prior = try AcceptedDrawingModelSnapshot(
      version: DrawingModelVersion(rawValue: 1),
      transform: DrawingTransform(
        machineToField: AffineTransform2(
          m11: 1, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0
        ),
        machineDomain: domain
      ),
      provenance: DrawingModelSnapshotProvenance(
        origin: .prior(name: "simulator-affine-prior")
      )
    )
    let truth = try DrawingTransform(
      machineToField: AffineTransform2(
        m11: 1.025, m12: 0.012, m21: -0.009, m22: 0.978, tx: 2.4, ty: 3.1
      ),
      machineDomain: domain
    )
    let observations = try observationSet(truth: truth)
    let candidate = try DrawingModelTrainer.fitCandidate(
      basedOn: prior,
      observations: observations
    )
    let criteria = try ModelAcceptanceCriteria(
      maximumHoldoutRootMeanSquareError: 0.01,
      maximumHoldoutError: 0.02,
      minimumHoldoutRootMeanSquareImprovement: 0.25
    )
    let decision = DrawingModelAcceptance.decision(for: candidate, criteria: criteria)
    let accepted = try DrawingModelAcceptance.accept(
      candidate,
      replacing: prior,
      decision: decision,
      as: DrawingModelVersion(rawValue: 2),
      acceptanceNote: "simulated upfront training with held-out improvement"
    )
    let online = OnlineModelAccumulator(acceptedModel: accepted, observations: observations)
    _ = try online.proposeCandidate(at: .penUpBetweenStrokes(identifier: "sim-checkpoint"))

    let logical = try Polyline<FieldSpace>(points: [
      Point2(x: 18, y: 25), Point2(x: 72, y: 82),
      Point2(x: 146, y: 42), Point2(x: 182, y: 92),
    ])
    let machine = try Polyline<MachineSpace>(points: [
      Point2(x: 18, y: 25), Point2(x: 72, y: 82),
      Point2(x: 146, y: 42), Point2(x: 182, y: 92),
    ])
    let frame = try AxisAlignedBounds<FieldSpace>(minX: 5, minY: 8, maxX: 205, maxY: 108)
    let armature = try AxisAlignedBounds<FieldSpace>(
      minX: 100,
      minY: 14,
      maxX: 124,
      maxY: 102
    )
    let priorScene = try SimulatedModelMismatchScene(
      scenarioID: "prior-model-mismatch",
      logicalFieldPath: logical,
      commandedMachinePath: machine,
      acceptedModel: prior,
      simulatedGroundTruthTransform: truth,
      capFieldPoint: Point2(x: 112, y: 34),
      frameFieldBounds: frame,
      armatureFieldBounds: armature,
      penState: .down
    )
    let trainedScene = try SimulatedModelMismatchScene(
      scenarioID: "accepted-trained-model",
      logicalFieldPath: logical,
      commandedMachinePath: machine,
      acceptedModel: accepted,
      simulatedGroundTruthTransform: truth,
      capFieldPoint: Point2(x: 112, y: 34),
      frameFieldBounds: frame,
      armatureFieldBounds: armature,
      penState: .down
    )
    return Self(
      priorScene: priorScene,
      trainedScene: trainedScene,
      candidate: candidate,
      accepted: accepted
    )
  }

  func summary(for mode: SimulatorModelMode) -> String {
    let baseline = candidate.baselineEvaluation.holdout.rootMeanSquareError
    let trained = candidate.candidateEvaluation.holdout.rootMeanSquareError
    switch mode {
    case .prior:
      return String(
        format: "v1 prior · holdout RMS %.3f → %.3f · candidate explicitly accepted as v2",
        baseline,
        trained
      )
    case .trained:
      return String(
        format: "v%llu accepted · holdout RMS %.3f · online proposals only at pen-up checkpoints",
        accepted.version.rawValue,
        trained
      )
    }
  }

  private static func observationSet(truth: DrawingTransform) throws
    -> [DrawingModelTrainingObservation]
  {
    let samples: [(Double, Double, ModelObservationSplit, String)] = [
      (10, 10, .training, "train-1"), (200, 10, .training, "train-2"),
      (10, 105, .training, "train-3"), (200, 105, .training, "train-4"),
      (110, 55, .training, "train-5"), (45, 70, .holdout, "holdout-1"),
      (175, 38, .holdout, "holdout-2"),
    ]
    return try samples.map { sample in
      let (x, y, split, identifier) = sample
      let machine = try Point2<MachineSpace>(x: x, y: y)
      return try DrawingModelTrainingObservation(
        machinePoint: machine,
        observedFieldPoint: truth.predictedFieldPoint(for: machine),
        split: split,
        provenance: ModelObservationProvenance(
          observationID: identifier,
          evidence: .simulated(scenarioID: "operator-simulator-training"),
          algorithmRevision: "exact-affine-simulator-v1"
        )
      )
    }
  }
}
