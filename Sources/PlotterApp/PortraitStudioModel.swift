import Foundation
import Observation
import PlotterModel
import PlotterRuntime

struct PortraitRenderDiagnostics: Equatable, Sendable {
  var requestedWorkCount = 0
  var cancellationCount = 0
  var startedWorkerCount = 0
  var settledWorkerCount = 0
  var activeWorkerCount = 0
  var maximumConcurrentWorkerCount = 0
}

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
  @ObservationIgnored private var workTask: Task<Void, Never>?
  @ObservationIgnored private var renderWorker: Task<PortraitRenderResult, Error>?
  @ObservationIgnored private let renderer: any PortraitRendering
  @ObservationIgnored private let photoAcquirer: any PortraitPhotoAcquiring
  @ObservationIgnored private var acquisitionWorker: Task<Data, Error>?
  @ObservationIgnored private var pendingAcquisition: PhotoAcquisition?
  @ObservationIgnored private var acquisitionRevision: UInt64 = 0
  @ObservationIgnored private(set) var acquisitionDiagnostics = PortraitRenderDiagnostics()
  @ObservationIgnored private var pendingRender: (revision: UInt64, request: PortraitRenderRequest)?
  @ObservationIgnored private var renderRevision: UInt64 = 0
  @ObservationIgnored private var isShutdown = false
  @ObservationIgnored private(set) var renderDiagnostics = PortraitRenderDiagnostics()
  @ObservationIgnored private(set) var workDiagnostics = PortraitRenderDiagnostics()
  @ObservationIgnored private var rasters: [PortraitPose: PortraitRaster] = [:]

  init(
    camera: CameraCapture = CameraCapture(),
    renderer: any PortraitRendering = PortraitImageAnalyzer(),
    photoAcquirer: any PortraitPhotoAcquiring = PortraitImageAnalyzer()
  ) {
    self.camera = camera
    self.renderer = renderer
    self.photoAcquirer = photoAcquirer
  }

  func discover(excluding plotterDeviceID: CameraDeviceID?) async {
    await camera.discoverDevices()
    devices = await camera.snapshot().devices.filter { $0.id != plotterDeviceID }
    if !devices.contains(where: { $0.id == selectedDeviceID }) {
      selectedDeviceID = devices.first?.id
    }
  }

  func startCamera() async {
    guard !isShutdown else { return }
    guard let selectedDeviceID else {
      cameraStatus = "No portrait camera is available. Connect a face camera and retry Portrait Studio, or import a photo."
      return
    }
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
      cameraStatus = snapshot.error?.actionableDescription
      if cameraIsRunning {
        frameTask = Task { [weak self] in
          for await frame in frames {
            guard !Task.isCancelled else { return }
            self?.preview.frame = frame
          }
        }
      }
    } catch {
      if generation == cameraGeneration {
        cameraStatus = (error as? CameraCaptureError)?.actionableDescription ?? error.localizedDescription
      }
    }
  }

  func stopCamera() async {
    cameraGeneration &+= 1
    let frames = frameTask
    frames?.cancel()
    frameTask = nil
    preview.frame = nil
    cameraIsRunning = false
    cameraIsStarting = false
    await camera.stop()
    await frames?.value
  }

  func capture(strokeStyle: StrokeStyle) async {
    await acquirePhoto(file: nil, strokeStyle: strokeStyle)
  }

  func importPhoto(_ url: URL, strokeStyle: StrokeStyle) async {
    await acquirePhoto(file: url, strokeStyle: strokeStyle)
  }

  private struct PhotoAcquisition: Sendable {
    let revision: UInt64
    let file: URL?
    let pose: PortraitPose
    let strokeStyle: StrokeStyle
  }

  private func acquirePhoto(file: URL?, strokeStyle: StrokeStyle) async {
    guard !isShutdown else { return }
    acquisitionRevision &+= 1
    acquisitionDiagnostics.requestedWorkCount += 1
    acquisitionWorker?.cancel()
    renderRevision &+= 1
    renderWorker?.cancel()
    pendingRender = nil
    pendingAcquisition = PhotoAcquisition(revision: acquisitionRevision, file: file, pose: pose, strokeStyle: strokeStyle)
    startWorkIfNeeded()
    await workTask?.value
  }

  private func startWorkIfNeeded() {
    if workTask == nil { workTask = Task { await drainWork() } }
  }

  private func drainWork() async {
    defer { workTask = nil }
    while !isShutdown && (pendingAcquisition != nil || pendingRender != nil) {
      await drainAcquisitions()
      await drainRenders()
    }
  }

  private func workerStarted() {
    workDiagnostics.startedWorkerCount += 1
    workDiagnostics.activeWorkerCount += 1
    workDiagnostics.maximumConcurrentWorkerCount = max(
      workDiagnostics.maximumConcurrentWorkerCount, workDiagnostics.activeWorkerCount)
  }

  private func workerSettled() {
    workDiagnostics.activeWorkerCount -= 1
    workDiagnostics.settledWorkerCount += 1
  }

  private func drainAcquisitions() async {
    defer { acquisitionWorker = nil }
    while let request = pendingAcquisition, !isShutdown {
      pendingAcquisition = nil
      let camera = camera, acquirer = photoAcquirer
      let worker = Task.detached(priority: .userInitiated) {
        let input: PortraitPhotoInput
        if let file = request.file {
          input = .file(file)
        } else {
          guard let frame = try await camera.materializeLatestFrame(policy: .returnOnly) else {
            throw PortraitDrawingError.noCameraFrame
          }
          input = .frame(frame.frame)
        }
        try Task.checkCancellation()
        return try await acquirer.acquire(input)
      }
      acquisitionWorker = worker
      workerStarted()
      acquisitionDiagnostics.startedWorkerCount += 1
      acquisitionDiagnostics.activeWorkerCount += 1
      acquisitionDiagnostics.maximumConcurrentWorkerCount = max(
        acquisitionDiagnostics.maximumConcurrentWorkerCount, acquisitionDiagnostics.activeWorkerCount)
      defer {
        workerSettled()
        acquisitionDiagnostics.activeWorkerCount -= 1
        acquisitionDiagnostics.settledWorkerCount += 1
      }
      do {
        let data = try await worker.value
        guard request.revision == acquisitionRevision, !isShutdown else { continue }
        installPhoto(data, for: request.pose, strokeStyle: request.strokeStyle)
      } catch {
        guard request.revision == acquisitionRevision, !isShutdown, !(error is CancellationError) else { continue }
        if request.file == nil { cameraStatus = error.localizedDescription }
        else { summary = error.localizedDescription }
      }
    }
  }

  func setPhoto(_ data: Data, for pose: PortraitPose, strokeStyle: StrokeStyle) {
    guard !isShutdown else { return }
    acquisitionRevision &+= 1
    acquisitionWorker?.cancel()
    pendingAcquisition = nil
    installPhoto(data, for: pose, strokeStyle: strokeStyle)
  }

  private func installPhoto(_ data: Data, for pose: PortraitPose, strokeStyle: StrokeStyle) {
    photos[pose] = data
    rasters[pose] = nil
    if pose == self.pose { render(strokeStyle: strokeStyle) }
  }

  func analysisOptionsChanged(strokeStyle: StrokeStyle) {
    rasters.removeAll()
    render(strokeStyle: strokeStyle)
  }

  func render(strokeStyle: StrokeStyle) {
    guard !isShutdown else { return }
    renderRevision &+= 1
    renderWorker?.cancel()
    pendingRender = nil
    program = nil
    guard let data = photos[pose] else {
      isProcessing = false
      summary = "Capture the \(pose.rawValue.lowercased()) view or choose a photo."
      return
    }
    isProcessing = true
    summary = "Preparing \(style.rawValue.lowercased()) portrait…"
    pendingRender = (renderRevision, .init(
      data: data, pose: pose, style: style, options: options,
      cachedRaster: rasters[pose], strokeStyle: strokeStyle))
    startWorkIfNeeded()
  }

  private func drainRenders() async {
    defer { renderWorker = nil }
    while let pending = pendingRender, pendingAcquisition == nil, !isShutdown {
      pendingRender = nil
      let renderer = renderer
      let worker = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        return try await renderer.render(pending.request)
      }
      renderWorker = worker
      workerStarted()
      renderDiagnostics.startedWorkerCount += 1
      renderDiagnostics.activeWorkerCount += 1
      renderDiagnostics.maximumConcurrentWorkerCount = max(
        renderDiagnostics.maximumConcurrentWorkerCount, renderDiagnostics.activeWorkerCount)
      defer {
        workerSettled()
        renderDiagnostics.activeWorkerCount -= 1
        renderDiagnostics.settledWorkerCount += 1
      }
      do {
        let result = try await worker.value
        guard pending.revision == renderRevision, !isShutdown else { continue }
        rasters[pending.request.pose] = result.raster
        program = result.program
        summary = "\(result.raster.analysisSummary) · \(result.program.strokes.count) strokes"
        isProcessing = false
      } catch {
        guard pending.revision == renderRevision, !isShutdown else { continue }
        if !(error is CancellationError) { summary = error.localizedDescription }
        isProcessing = false
      }
    }
  }

  /// Stop expensive work without discarding captured photos or the last
  /// completed draft. Replacement work waits for the current worker to settle.
  func cancelRendering() async {
    acquisitionDiagnostics.cancellationCount += 1
    acquisitionRevision &+= 1
    pendingAcquisition = nil
    acquisitionWorker?.cancel()
    renderRevision &+= 1
    pendingRender = nil
    isProcessing = false
    renderWorker?.cancel()
    await workTask?.value
  }

  func awaitRendering() async { await workTask?.value }

  func cameraDiagnostics() async -> CameraCaptureSnapshot { await camera.snapshot() }

  func shutdown() async {
    isShutdown = true
    await cancelRendering()
    await stopCamera()
  }
}
