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
    simulatedContent: {
      try await session.simulatedContent()
    }
  )
}

private actor CameraSourceSession {
  private let live = CameraCapture()
  private let startupFrameRecorder = StartupFrameRecorder()
  private var simulator: SimulatedFrameSource
  private let scene: SimulatedFieldScene
  private var startupFrameTask: Task<Void, Never>?

  init() {
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
      scene = try SimulatedFieldScene.standard()
    } catch {
      preconditionFailure("Invalid deterministic simulator composition: \(error)")
    }
  }

  func discover() async -> CameraCaptureSnapshot {
    await live.discoverDevices()
    return await live.snapshot()
  }

  func select(_ id: CameraDeviceID) async throws -> CameraCaptureSnapshot {
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
    await live.stop()
    return await live.snapshot()
  }

  func restart() async -> CameraCaptureSnapshot {
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

  func simulatedContent() throws -> SimulatedActionSurfaceContent {
    let observedCamera = try simulator.cameraPolyline(from: scene.observed)
    let strokes = zip(observedCamera.points, observedCamera.points.dropFirst()).map {
      SimulatedCameraStroke(start: $0.0, end: $0.1, green: 210)
    }
    let displayedFrame = try simulator.render(strokes: strokes)
    var overlays: [CameraOverlayMeasurement] = [
      overlay(
        .polyline(try simulator.cameraPolyline(from: scene.logical)),
        operation: CanvasLayer.logical.operationName,
        displayedFrame: displayedFrame
      ),
      overlay(
        .polyline(try simulator.cameraPolyline(from: scene.predicted)),
        operation: CanvasLayer.predicted.operationName,
        displayedFrame: displayedFrame
      ),
      overlay(
        .polyline(observedCamera),
        operation: CanvasLayer.observed.operationName,
        displayedFrame: displayedFrame
      ),
    ]
    for (predicted, observed) in zip(scene.predicted.points, scene.observed.points) {
      let residual = try Polyline<FieldSpace>(points: [predicted, observed])
      overlays.append(
        overlay(
          .polyline(try simulator.cameraPolyline(from: residual)),
          operation: CanvasLayer.residuals.operationName,
          displayedFrame: displayedFrame
        )
      )
    }
    return SimulatedActionSurfaceContent(displayedFrame: displayedFrame, overlays: overlays)
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

  private func overlay(
    _ geometry: CameraPixelGeometry,
    operation: String,
    displayedFrame: DisplayedFrame
  ) -> CameraOverlayMeasurement {
    CameraOverlayMeasurement(
      frameID: displayedFrame.frame.id,
      cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
      geometry: geometry,
      provenance: CameraMeasurementProvenance(
        operation: operation,
        algorithmRevision: "deterministic-simulator-v1"
      )
    )
  }
}

private struct SimulatedFieldScene: Sendable {
  let logical: Polyline<FieldSpace>
  let predicted: Polyline<FieldSpace>
  let observed: Polyline<FieldSpace>

  static func standard() throws -> Self {
    Self(
      logical: try Polyline(points: [
        Point2(x: 18, y: 25),
        Point2(x: 72, y: 82),
        Point2(x: 146, y: 42),
        Point2(x: 182, y: 92),
      ]),
      predicted: try Polyline(points: [
        Point2(x: 20, y: 24),
        Point2(x: 74, y: 80),
        Point2(x: 148, y: 41),
        Point2(x: 184, y: 90),
      ]),
      observed: try Polyline(points: [
        Point2(x: 21, y: 26),
        Point2(x: 76, y: 79),
        Point2(x: 149, y: 44),
        Point2(x: 183, y: 93),
      ])
    )
  }
}
