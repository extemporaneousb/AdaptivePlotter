import Foundation
import Observation
import DrawingLibrary
import PortraitCore
import PortraitArtists
import PortraitLibrary
import PlotterModel
import PlotterRuntime

@Observable @MainActor
package final class PortraitCameraPreviewModel {
  package init() {}
  package var frame: DisplayedFrame?
}

/// Camera acquisition and the current authored value. The shared Library owns
/// durable drawings; the Dojo owns generation, curation and learning actions.
@Observable @MainActor
package final class PortraitStudioModel {
  package let library: DrawingLibrary
  package let sketches: PortraitSketchCollection
  package private(set) var currentDrawing: Drawing?
  package var currentProgram: DrawingProgram? { currentDrawing?.program }
  package var selectionEpoch: UInt64 { selectionRevision }
  package var selectedRef: DrawingRef? { currentDrawing?.reference }
  package private(set) var projectedDrawing: Drawing?
  package var selectedPhoto: Data? { portfolioPhoto?.data }
  package private(set) var embeddedDojo: FlowDojoModel?
  package private(set) var devices: [CameraDevice] = []
  package var selectedDeviceID: CameraDeviceID?
  package private(set) var cameraIsRunning = false
  package private(set) var cameraIsStarting = false
  package private(set) var cameraStatus: String?
  package private(set) var isCapturing = false
  package private(set) var screenIlluminationActive = false
  package private(set) var capturePhase: String?
  package private(set) var captureProgress = 0.0
  package private(set) var portfolioPhoto: PortraitPhoto?
  package let preview = PortraitCameraPreviewModel()
  @ObservationIgnored private let drawingLoader: @Sendable (DrawingRef) async throws -> Drawing
  @ObservationIgnored private let camera: CameraCapture
  @ObservationIgnored private let photoAcquirer: any PortraitPhotoAcquiring
  @ObservationIgnored private let frameSource: any PortraitFrameAcquiring
  @ObservationIgnored private let captureClock: any PortraitCaptureClock
  @ObservationIgnored private let photoRetention: PortraitPhotoRetention
  @ObservationIgnored private var materialWorkerEpoch: UInt64?
  @ObservationIgnored private var materialWorker: Task<DrawingProduction<PortraitRenderResult>, Error>?
  @ObservationIgnored private var illuminationTask: Task<Void, Never>?
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var acquisitionWorker: Task<PortraitPhoto, Error>?
  @ObservationIgnored private var acquisitionRevision: UInt64 = 0
  @ObservationIgnored private var cameraGeneration: UInt64 = 0
  @ObservationIgnored private var isShutdown = false
  @ObservationIgnored private var portfolioShutdownStarted = false
  @ObservationIgnored private var selectionRevision: UInt64 = 0

  package init(camera: CameraCapture = CameraCapture(materializationPolicy:
    LiveFrameMaterializationPolicy(minimumPreviewIntervalNanoseconds: 33_333_333)),
    library: DrawingLibrary = DrawingLibrary(directoryURL: DrawingLibrary.defaultDirectoryURL),
    drawingLoader: (@Sendable (DrawingRef) async throws -> Drawing)? = nil,
    photoAcquirer: any PortraitPhotoAcquiring = PortraitImageAnalyzer(),
    frameSource: (any PortraitFrameAcquiring)? = nil,
    captureClock: any PortraitCaptureClock = PortraitSystemCaptureClock(),
    photoRetention: PortraitPhotoRetention = PortraitPhotoRetention()) {
    self.library = library; sketches = PortraitSketchCollection(library: library)
    self.drawingLoader = drawingLoader ?? { try await library.drawing($0) }
    self.camera = camera; self.photoAcquirer = photoAcquirer
    self.frameSource = frameSource ?? PortraitCameraFrameSource(camera: camera)
    self.captureClock = captureClock; self.photoRetention = photoRetention
  }
  package func portfolioDojo(strokeStyle: StrokeStyle, nominalPenWidthMM: Double? = nil) -> FlowDojoModel {
    if let embeddedDojo { embeddedDojo.updateStrokeStyle(strokeStyle, nominalPenWidthMM: nominalPenWidthMM); return embeddedDojo }
    let dojo = FlowDojoModel(library: library, strokeStyle: strokeStyle, nominalPenWidthMM: nominalPenWidthMM)
    if portfolioShutdownStarted { dojo.closeMutationAdmission() }
    embeddedDojo = dojo; return dojo
  }
  package func preparePortfolioShutdown() async -> Bool {
    portfolioShutdownStarted = true
    let ready = await embeddedDojo?.shutdown() ?? true
    if !ready { portfolioShutdownStarted = false }
    return ready
  }
  package func discover(excluding plotterDeviceID: CameraDeviceID?) async {
    await camera.discoverDevices()
    devices = await camera.snapshot().devices.filter { $0.id != plotterDeviceID }
    if !devices.contains(where: { $0.id == selectedDeviceID }) {
      selectedDeviceID = devices.first?.id
    }
  }

  package func startCamera() async {
    guard !isShutdown else { return }
    guard let selectedDeviceID else {
      cameraStatus = "No portrait camera is available. Connect a face camera and retry Portrait Studio, or import a photo."
      return
    }
    // Repeated photos share the same live session. Restarting here on every
    // capture threw away a healthy stream immediately before its short burst.
    let observedGeneration = cameraGeneration
    let current = await camera.snapshot()
    guard !isShutdown, observedGeneration == cameraGeneration,
      self.selectedDeviceID == selectedDeviceID else { return }
    if current.state == .running, current.selectedDeviceID == selectedDeviceID {
      cameraIsRunning = true
      cameraStatus = current.error?.actionableDescription
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

  package func stopCamera() async {
    cameraGeneration &+= 1
    if isCapturing { await cancelRendering() }
    let frames = frameTask
    frames?.cancel()
    frameTask = nil
    preview.frame = nil
    cameraIsRunning = false
    cameraIsStarting = false
    await camera.stop()
    await frames?.value
  }


  package func captureForPortfolio(strokeStyle: StrokeStyle) async -> PortraitPhoto? {
    guard !isShutdown, !isCapturing else { return nil }
    acquisitionRevision &+= 1
    let revision = acquisitionRevision, acquirer = photoAcquirer, source = frameSource
    let clock = captureClock, retention = photoRetention
    illuminationTask?.cancel(); illuminationTask = nil; screenIlluminationActive = false
    portfolioPhoto = nil; isCapturing = true; capturePhase = "Waiting for fresh camera video…"
    captureProgress = 0
    let worker = Task.detached(priority: .userInitiated) { [weak self] () async throws -> PortraitPhoto in
      let waitingAt = await clock.now(), boundary = try await source.latestCaptureNanoseconds() ?? 0
      var ready = false
      while await clock.now() - waitingAt < 3 {
        try Task.checkCancellation()
        if let timestamp = try await source.latestCaptureNanoseconds(), timestamp > boundary { ready = true; break }
        try await clock.sleep(seconds: 0.05)
      }
      guard ready else { throw FlowPortfolioError.unavailable("The selected camera is not delivering fresh video. Restart Camera, then retry Capture Photo.") }
      await self?.beginIllumination(revision: revision)
      let started = await clock.now()
      try await clock.sleep(seconds: 0.25)
      var last = try await source.latestCaptureNanoseconds() ?? 0
      var seen = Set<FrameID>(), buffer = PortraitBurstBuffer(retention: retention)
      while await clock.now() - started < 0.8 {
        try Task.checkCancellation()
        let sampleStarted = await clock.now()
        if let frame = try await source.latestFrame(newerThanNanoseconds: last), frame.captureNanoseconds > last,
          seen.insert(frame.id).inserted {
          last = frame.captureNanoseconds
          let acquired = try await acquirer.acquire(.frame(frame))
          buffer.append(.init(data: acquired.data, frameID: frame.id, captureNanoseconds: frame.captureNanoseconds,
            label: "Captured frame", sourcePixelExtent: acquired.sourcePixelExtent))
        }
        let now = await clock.now()
        await self?.updateCapture(min(1, (now - started) / 0.8), revision: revision)
        let remaining = 0.8 - (now - started)
        if remaining > 0 { try await clock.sleep(seconds: min(remaining, max(0.001, 0.1 - (now - sampleStarted)))) }
      }
      try Task.checkCancellation()
      guard let sample = try PortraitBurstSelector.select(from: buffer.samples) else {
        throw FlowPortfolioError.unavailable("The selected camera stopped delivering fresh video during capture. Use Restart Camera, then retry Capture Photo.")
      }
      return PortraitPhoto(id: UUID(), data: sample.data, label: sample.label, capturedAt: Date(),
        frameID: sample.frameID, captureNanoseconds: sample.captureNanoseconds, pose: .front,
        sourcePixelExtent: sample.sourcePixelExtent, captureSessionID: UUID(), selectionProvenance: sample.selectionProvenance)
    }
    acquisitionWorker = worker
    defer { if acquisitionRevision == revision {
      illuminationTask?.cancel(); illuminationTask = nil
      acquisitionWorker = nil; isCapturing = false; screenIlluminationActive = false; capturePhase = nil
    } }
    do {
      let photo = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      guard !isShutdown, acquisitionRevision == revision, !Task.isCancelled else { return nil }
      portfolioPhoto = photo; cameraStatus = nil; return photo
    } catch is CancellationError { return nil }
    catch { if acquisitionRevision == revision { cameraStatus = error.localizedDescription }; return nil }
  }
  private func beginIllumination(revision: UInt64) {
    guard !isShutdown, revision == acquisitionRevision, !Task.isCancelled else { return }
    illuminationTask?.cancel()
    screenIlluminationActive = true; capturePhase = "Capturing fresh frames…"
    illuminationTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(0.8)) } catch { return }
      guard let self, !Task.isCancelled, !self.isShutdown, self.acquisitionRevision == revision else { return }
      self.screenIlluminationActive = false; self.captureProgress = 1; self.illuminationTask = nil
    }
  }
  private func updateCapture(_ value: Double, revision: UInt64) {
    guard revision == acquisitionRevision else { return }; captureProgress = max(captureProgress, value)
  }
  package func cancelRendering() async {
    acquisitionRevision &+= 1; let revision = acquisitionRevision
    let worker = acquisitionWorker, material = materialWorker
    acquisitionWorker = nil; materialWorker = nil; materialWorkerEpoch = nil
    illuminationTask?.cancel(); illuminationTask = nil
    isCapturing = false; screenIlluminationActive = false; capturePhase = nil
    worker?.cancel(); material?.cancel(); embeddedDojo?.cancel()
    _ = await worker?.result
    _ = await material?.result
    guard acquisitionRevision == revision else { return }
    isCapturing = false; screenIlluminationActive = false; capturePhase = nil
  }
  package func awaitRendering() async { _ = await acquisitionWorker?.result; _ = await materialWorker?.result }
  package func cameraDiagnostics() async -> CameraCaptureSnapshot { await camera.snapshot() }
  private struct SelectionEpoch {
    let model: UInt64
    let collection: UInt64
  }
  package func clearDrawingSelection() {
    selectionRevision &+= 1; sketches.clearSelection()
    currentDrawing = nil; projectedDrawing = nil
  }
  private func beginSelection(isStillCurrent: @MainActor () -> Bool) throws -> SelectionEpoch {
    guard !isShutdown, !Task.isCancelled, isStillCurrent() else { throw CancellationError() }
    selectionRevision &+= 1
    return SelectionEpoch(model: selectionRevision, collection: sketches.selectionEpoch)
  }
  private func requireSelection(_ epoch: SelectionEpoch, isStillCurrent: @MainActor () -> Bool) throws {
    guard !isShutdown, !Task.isCancelled, epoch.model == selectionRevision, epoch.collection == sketches.selectionEpoch,
      isStillCurrent(), epoch.model == selectionRevision, epoch.collection == sketches.selectionEpoch else { throw CancellationError() }
  }
  private func publishSelection(_ drawing: Drawing, epoch: SelectionEpoch,
    isStillCurrent: @MainActor () -> Bool) throws {
    try requireSelection(epoch, isStillCurrent: isStillCurrent)
    // All three visible associations change within this uninterrupted MainActor turn.
    try sketches.selectLoaded(drawing)
    currentDrawing = drawing; projectedDrawing = drawing
    selectionRevision &+= 1
  }
  package func projectDrawing(_ drawing: Drawing,
    isStillCurrent: @MainActor () -> Bool = { true }) async throws {
    guard let ref = drawing.reference else { throw DrawingExchangeError.mismatchedParent }
    let epoch = try beginSelection(isStillCurrent: isStillCurrent)
    let exact = try await drawingLoader(ref)
    try requireSelection(epoch, isStillCurrent: isStillCurrent)
    guard exact.reference == ref, exact.program == drawing.program else { throw DrawingExchangeError.mismatchedParent }
    try exact.capabilities.require(.plot)
    try publishSelection(exact, epoch: epoch, isStillCurrent: isStillCurrent)
  }
  package func saveAuthoredDrawing(_ drawing: Drawing,
    isStillCurrent: @MainActor () -> Bool) async throws -> Drawing {
    let epoch = try beginSelection(isStillCurrent: isStillCurrent)
    let retained = try await sketches.retain(drawing, reason: "save")
    try requireSelection(epoch, isStillCurrent: isStillCurrent)
    try publishSelection(retained, epoch: epoch, isStillCurrent: isStillCurrent)
    return retained
  }
  package func acceptDrawingProjection(_ drawing: Drawing,
    isStillCurrent: @MainActor () -> Bool = { true },
    operation: @MainActor () async throws -> Void) async -> String? {
    do {
      try drawing.capabilities.require(.plot)
      let epoch = try beginSelection(isStillCurrent: isStillCurrent)
      let retained = try await sketches.retain(drawing, reason: "plot-handoff")
      try requireSelection(epoch, isStillCurrent: isStillCurrent)
      try retained.capabilities.require(.plot)
      try await operation()
      try requireSelection(epoch, isStillCurrent: isStillCurrent)
      try publishSelection(retained, epoch: epoch, isStillCurrent: isStillCurrent)
      return nil
    } catch { return error.localizedDescription }
  }
  package var currentDrawingMaterialContext: PortraitMaterialContext? {
    guard let drawing = currentDrawing, drawing.producer.id == PortraitFlowProducerClaim.producerID,
      drawing.producer.version == PortraitFlowProducerClaim.version,
      let claim = try? JSONDecoder().decode(PortraitFlowProducerClaim.self, from: drawing.producer.originalJSON) else { return nil }
    return claim.settings.materialContext
  }
  package func applyMaterial(_ profile: DrawingMaterialProfileRevision, drawingHeightMM: Double) async -> String? {
    guard let parent = currentDrawing, let reference = parent.reference, let store = embeddedDojo?.store else {
      return "The selected drawing has no known Flow source and recipe for material adaptation."
    }
    do {
      let revision = try beginSelection(isStillCurrent: { self.currentDrawing?.reference == reference })
      let source = try await store.materialSource(for: reference)
      try requireSelection(revision, isStillCurrent: { self.currentDrawing?.reference == reference })
      let context = try PortraitMaterialContext(profile: profile, drawingHeightMM: drawingHeightMM)
      let pen = try StrokeStyle(nominalLineWidth: profile.nominalWidthMM, penProfileID: PenProfileID(profile.id))
      await cancelRendering()
      try requireSelection(revision, isStillCurrent: { self.currentDrawing?.reference == reference })
      let settings = PortraitFlowDrawingProducer.Settings(recipe: source.recipe, analysisOptions: source.analysisOptions,
        strokeStyle: pen, nominalPenWidthMM: profile.nominalWidthMM, materialContext: context)
      let input = PortraitFlowDrawingProducer.Input(data: source.data, input: parent.input, parent: .present(reference), photo: source.photo)
      let worker = Task.detached(priority: .userInitiated) {
        let result = try await PortraitImageAnalyzer().render(.init(data: source.data, pose: .front, style: .flowEdges,
          options: source.analysisOptions, cachedRaster: source.raster, strokeStyle: pen, vectorOptions: settings.vectorOptions))
        return try PortraitFlowDrawingProducer.admit(result: result, input: input, settings: settings, origin: .providedArtifacts)
      }
      materialWorker = worker; materialWorkerEpoch = revision.model
      defer { if materialWorkerEpoch == revision.model { materialWorker = nil; materialWorkerEpoch = nil } }
      let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try requireSelection(revision, isStillCurrent: { self.currentDrawing?.reference == reference })
      let retained = try await library.retain(result.drawing, reason: "material-adaptation",
        closure: result.artifacts.drawingInput.map { DrawingLibraryRetainedClosure(input: $0) } ?? .empty)
      try requireSelection(revision, isStillCurrent: { self.currentDrawing?.reference == reference })
      let exact = try await drawingLoader(retained.reference)
      try requireSelection(revision, isStillCurrent: { self.currentDrawing?.reference == reference })
      guard exact.reference == retained.reference, exact.program == result.drawing.program else { throw DrawingExchangeError.mismatchedParent }
      try publishSelection(exact, epoch: revision, isStillCurrent: { self.currentDrawing?.reference == reference })
      return nil
    } catch { return error.localizedDescription }
  }
  package func shutdown() async {
    guard !isShutdown else { return }
    isShutdown = true; selectionRevision &+= 1
    illuminationTask?.cancel(); illuminationTask = nil; screenIlluminationActive = false
    _ = await preparePortfolioShutdown()
    await cancelRendering(); await stopCamera(); await sketches.shutdown()
  }
}
