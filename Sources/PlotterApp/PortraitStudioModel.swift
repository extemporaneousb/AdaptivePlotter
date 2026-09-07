import Foundation
import Observation
import PlotterModel
import PlotterRuntime

@Observable @MainActor
final class PortraitCameraPreviewModel {
  var frame: DisplayedFrame?
}

@Observable @MainActor
final class PortraitStudioModel {
  var pose: PortraitPose = .front
  var style: PortraitStyle = .contours
  var options = PortraitAnalysisOptions()
  private(set) var photos: [PortraitPose: Data] = [:]
  private(set) var program: DrawingProgram?
  private(set) var summary = "Capture a portrait or choose a photo."
  private(set) var isProcessing = false
  private(set) var devices: [CameraDevice] = []
  var selectedDeviceID: CameraDeviceID?
  private(set) var cameraIsRunning = false
  private(set) var cameraIsStarting = false
  private(set) var cameraStatus: String?
  let preview = PortraitCameraPreviewModel()
  @ObservationIgnored private var cameraGeneration: UInt64 = 0
  @ObservationIgnored private let camera: CameraCapture
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var renderTask: Task<Void, Never>?
  @ObservationIgnored private var rasters: [PortraitPose: PortraitRaster] = [:]

  init(camera: CameraCapture = CameraCapture()) { self.camera = camera }

  func discover(excluding plotterDeviceID: CameraDeviceID?) async {
    await camera.discoverDevices()
    devices = await camera.snapshot().devices.filter { $0.id != plotterDeviceID }
    if !devices.contains(where: { $0.id == selectedDeviceID }) {
      selectedDeviceID = devices.first?.id
    }
  }

  func startCamera() async {
    guard let selectedDeviceID else { return }
    let generation = cameraGeneration &+ 1
    await stopCamera()
    guard generation == cameraGeneration else { return }
    cameraIsStarting = true
    cameraStatus = nil
    defer { if generation == cameraGeneration { cameraIsStarting = false } }
    do {
      try await camera.select(selectedDeviceID)
      guard generation == cameraGeneration else { return }
      let frames = await camera.frames()
      guard generation == cameraGeneration else { return }
      await camera.start()
      let snapshot = await camera.snapshot()
      guard generation == cameraGeneration else { return }
      cameraIsRunning = snapshot.state == .running
      cameraStatus = snapshot.error.map { String(describing: $0) }
      if cameraIsRunning {
        frameTask = Task { [weak self] in
          for await frame in frames {
            guard !Task.isCancelled else { return }
            self?.preview.frame = frame
          }
        }
      }
    } catch {
      if generation == cameraGeneration { cameraStatus = String(describing: error) }
    }
  }

  func stopCamera() async {
    cameraGeneration &+= 1
    frameTask?.cancel()
    frameTask = nil
    preview.frame = nil
    cameraIsRunning = false
    cameraIsStarting = false
    await camera.stop()
  }

  func capture(strokeStyle: StrokeStyle) async {
    let capturedPose = pose
    do {
      guard let frame = try await camera.materializeLatestFrame(policy: .returnOnly) else {
        cameraStatus = "Waiting for a camera frame."
        return
      }
      let data = try await Task.detached(priority: .userInitiated) {
        guard let image = FrameImageFactory.image(from: frame.frame) else {
          throw PortraitDrawingError.unreadableImage
        }
        return try PortraitImageAnalyzer.encodedImage(image)
      }.value
      setPhoto(data, for: capturedPose, strokeStyle: strokeStyle)
    } catch { cameraStatus = error.localizedDescription }
  }

  func importPhoto(_ url: URL, strokeStyle: StrokeStyle) async {
    let capturedPose = pose
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
      let data = try await Task.detached(priority: .userInitiated) {
        // Decode orientation and retain only a bounded image in this editor.
        let input = try Data(contentsOf: url)
        return try PortraitImageAnalyzer.encodedImage(PortraitImageAnalyzer.image(from: input))
      }.value
      setPhoto(data, for: capturedPose, strokeStyle: strokeStyle)
    } catch { summary = error.localizedDescription }
  }

  func setPhoto(_ data: Data, for pose: PortraitPose, strokeStyle: StrokeStyle) {
    photos[pose] = data
    rasters[pose] = nil
    if pose == self.pose { render(strokeStyle: strokeStyle) }
  }

  func analysisOptionsChanged(strokeStyle: StrokeStyle) {
    rasters.removeAll()
    render(strokeStyle: strokeStyle)
  }

  func render(strokeStyle: StrokeStyle) {
    renderTask?.cancel()
    program = nil
    guard let data = photos[pose] else {
      isProcessing = false
      summary = "Capture the \(pose.rawValue.lowercased()) view or choose a photo."
      return
    }
    let pose = pose, style = style, options = options, cached = rasters[pose]
    isProcessing = true
    summary = "Preparing \(style.rawValue.lowercased()) portrait…"
    renderTask = Task {
      let worker = Task.detached(priority: .userInitiated) {
        let raster = try cached ?? PortraitImageAnalyzer.analyze(data: data, options: options)
        try Task.checkCancellation()
        let program = try PortraitVectorizer.program(from: raster, pose: pose, style: style, strokeStyle: strokeStyle)
        return (raster, program)
      }
      do {
        let (raster, result) = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return }
        rasters[pose] = raster
        program = result
        summary = "\(raster.analysisSummary) · \(result.strokes.count) strokes"
        isProcessing = false
      } catch {
        guard !Task.isCancelled else { return }
        summary = error.localizedDescription
        isProcessing = false
      }
    }
  }
}
