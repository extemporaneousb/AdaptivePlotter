import Foundation
import Observation
import OSLog
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
  private static let logger = Logger(subsystem: "com.adaptiveplotter.app", category: "portrait-browser")
  var pose: PortraitPose = .front {
    didSet {
      if pose != oldValue {
        invalidateExploration()
        selectedPhotoID = recentPhotos.last(where: { $0.pose == pose })?.id
      }
    }
  }
  var style: PortraitStyle = .contours
  private(set) var singlePortraitStatus: String?
  private var forwardPortraits: [(candidate: PortraitCandidate, pen: StrokeStyle)] = []
  var canGoForwardPortrait: Bool { forwardPortraits.contains { !isDeletedAttempt($0.candidate) } }
  var options = PortraitAnalysisOptions()
  var vectorOptions = PortraitVectorOptions(drawingParameters: .init())
  let sketches: PortraitSketchCollection
  private(set) var completedCandidate: PortraitCandidate?
  @ObservationIgnored private var pendingRenders: [PendingRender] = []
  @ObservationIgnored private var activeRender: PendingRender?
  @ObservationIgnored private var activeRenderWasCancelled = false
  /// Exact last successful projection; gallery browsing cannot replace this association.
  private(set) var projectedCandidate: PortraitCandidate?
  private var recipeTitle: String?
  var selectedCandidate: PortraitCandidate? {
    if let candidate = sketches.selected?.candidate {
      return isDeletedAttempt(candidate) ? nil : candidate
    }
    // currentProgram already checks configuration and deletion applicability.
    return currentProgram == nil ? nil : completedCandidate
  }
  var renderConfiguration: PortraitRenderConfiguration {
    .init(style: style, vectors: vectorOptions.bounded, analysis: options)
  }
  var framePosition: String {
    guard let index = recentPhotos.firstIndex(where: { $0.id == selectedPhotoID }) else { return selectedSource == nil ? "No frame" : "Retained source" }
    return "Frame \(index + 1) / \(recentPhotos.count)"
  }
  /// The completed drawing is usable only for its exact current selection.
  var currentProgram: DrawingProgram? {
    guard completedKey?.photoID == selectedPhotoID,
      completedKey?.configuration == renderConfiguration,
      let completedCandidate, !isDeletedAttempt(completedCandidate) else { return nil }
    return program
  }
  @ObservationIgnored private var cache = PortraitRenderCache()
  @ObservationIgnored private var requestedKey: PortraitRenderCacheKey?
  @ObservationIgnored private var completedKey: PortraitRenderCacheKey?
  @ObservationIgnored private(set) var renderCacheHits = 0
  private(set) var recentPhotos: [PortraitPhoto] = []
  private(set) var selectedPhotoID: UUID?
  @ObservationIgnored private var retainedEditSource: PortraitPhoto?
  private var selectedSource: PortraitPhoto? {
    recentPhotos.first(where: { $0.id == selectedPhotoID })
      ?? (retainedEditSource?.id == selectedPhotoID ? retainedEditSource : nil)
  }
  /// Retained source frames remain discoverable after the recent-photo cache expires.
  var browsablePhotos: [PortraitPhoto] {
    var seen = Set(recentPhotos.map(\.id))
    return recentPhotos + sketches.entries.reversed().compactMap { entry in
      let candidate = entry.candidate
      guard seen.insert(candidate.photoID).inserted, let pose = candidate.renderPose else { return nil }
      return PortraitPhoto(id: candidate.photoID, data: candidate.sourceData,
        label: "Retained frame", capturedAt: candidate.createdAt, frameID: nil,
        captureNanoseconds: nil, pose: pose, sourcePixelExtent: candidate.sourcePixelExtent,
        captureSessionID: candidate.captureSessionID)
    }
  }
  var selectedPhoto: Data? { selectedCandidate?.sourceData ?? selectedSource?.data }
  var retainedPhotoBytes: Int { recentPhotos.reduce(0) { $0 + $1.data.count } }
  let captureDuration: Double = 0.8
  private(set) var isCapturing = false
  private(set) var captureProgress = 0.0
  private(set) var screenIlluminationActive = false
  private(set) var captureSummary: String?
  private(set) var program: DrawingProgram?
  private(set) var summary = "Capture a portrait or choose a photo."
  private(set) var authoringError: String?
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
  @ObservationIgnored private var renderWorker: Task<PreparedRender, Error>?
  @ObservationIgnored private let renderer: any PortraitRendering
  @ObservationIgnored private let photoAcquirer: any PortraitPhotoAcquiring
  @ObservationIgnored private var acquisitionWorker: Task<[PortraitBurstSample], Error>?
  @ObservationIgnored private var illuminationTask: Task<Void, Never>?
  @ObservationIgnored private let frameSource: any PortraitFrameAcquiring
  @ObservationIgnored private let captureClock: any PortraitCaptureClock
  @ObservationIgnored private let photoRetention: PortraitPhotoRetention
  @ObservationIgnored private var pendingAcquisition: PhotoAcquisition?
  @ObservationIgnored private var acquisitionRevision: UInt64 = 0
  @ObservationIgnored private(set) var acquisitionDiagnostics = PortraitRenderDiagnostics()
  private struct PendingRender: Sendable {
    var queuedAt = ProcessInfo.processInfo.systemUptime
    var createdAt = Date()
    let revision: UInt64
    let key: PortraitRenderCacheKey
    let request: PortraitRenderRequest
    let photo: PortraitPhoto
    let recipe: PortraitStyleRecipe
    let lineage: PortraitCandidateLineage?
    let ownsSource: Bool
    var explorationID: UUID? = nil
    var explorationCenter: DrawingProgram? = nil
    var explorationRegion: PortraitTreatmentRegion? = nil
  }
  private struct PreparedRender: Sendable {
    let result: PortraitRenderResult
    let candidate: PortraitCandidate
    let isDifferent: Bool
    let attempt: PortraitAttemptRecord
    let preparationSeconds: Double
  }

  nonisolated private static func prepare(_ result: PortraitRenderResult, pending: PendingRender) throws -> PreparedRender {
    try Task.checkCancellation()
    let started = ProcessInfo.processInfo.systemUptime
    let candidate = try PortraitCandidate(sourceData: pending.photo.data,
      sourcePixelExtent: pending.photo.sourcePixelExtent, raster: result.raster,
      recipe: pending.recipe, program: result.program, photoID: pending.photo.id,
      captureSessionID: pending.photo.captureSessionID, createdAt: pending.createdAt, lineage: pending.lineage,
      pose: pending.photo.pose, warpManifest: result.warpManifest)
    try Task.checkCancellation()
    let isDifferent = pending.explorationCenter.map {
      let mask = pending.explorationRegion.flatMap {
        PortraitExplorationPolicy.VisibleGeometry.regionMask($0, raster: candidate.raster,
          program: candidate.program)
      }
      return PortraitExplorationPolicy.VisibleGeometry(candidate.program)
        .isMeaningfullyDifferent(from: PortraitExplorationPolicy.VisibleGeometry($0), mask: mask)
    } ?? true
    let attempt = try PortraitAttemptRecord.prepare(candidate: candidate, pen: pending.key.strokeStyle)
    return PreparedRender(result: result, candidate: candidate, isDifferent: isDifferent, attempt: attempt,
      preparationSeconds: ProcessInfo.processInfo.systemUptime - started)
  }

  @ObservationIgnored private var renderRevision: UInt64 = 0
  @ObservationIgnored private var isShutdown = false
  @ObservationIgnored private(set) var renderDiagnostics = PortraitRenderDiagnostics()
  @ObservationIgnored private(set) var workDiagnostics = PortraitRenderDiagnostics()

  init(
    camera: CameraCapture = CameraCapture(materializationPolicy:
      LiveFrameMaterializationPolicy(minimumPreviewIntervalNanoseconds: 33_333_333)),
    renderer: any PortraitRendering = PortraitImageAnalyzer(),
    photoAcquirer: any PortraitPhotoAcquiring = PortraitImageAnalyzer(),
    frameSource: (any PortraitFrameAcquiring)? = nil,
    captureClock: any PortraitCaptureClock = PortraitSystemCaptureClock(),
    photoRetention: PortraitPhotoRetention = PortraitPhotoRetention(),
    candidateStore: PortraitCandidateStore? = nil,
    explorationSeed: UInt64 = 1
  ) {
    let collection = PortraitSketchCollection(store: candidateStore)
    sketches = collection
    self.camera = camera
    self.renderer = renderer
    self.photoAcquirer = photoAcquirer
    self.frameSource = frameSource ?? PortraitCameraFrameSource(camera: camera)
    self.captureClock = captureClock
    self.photoRetention = photoRetention
    self.nextExplorationSeed = explorationSeed
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

  func capture(strokeStyle: StrokeStyle) async {
    await acquirePhoto(file: nil, strokeStyle: strokeStyle)
  }

  func importPhoto(_ url: URL, strokeStyle: StrokeStyle) async {
    await acquirePhoto(file: url, strokeStyle: strokeStyle)
  }

  private struct PhotoAcquisition: Sendable {
    let revision: UInt64
    let sessionID: UUID
    let file: URL?
    let pose: PortraitPose
    let strokeStyle: StrokeStyle
    let duration: Double
  }

  private func acquirePhoto(file: URL?, strokeStyle: StrokeStyle) async {
    guard !isShutdown else { return }
    prepareStyleForNewSource()
    invalidateExploration()
    acquisitionRevision &+= 1
    acquisitionDiagnostics.requestedWorkCount += 1
    acquisitionWorker?.cancel()
    renderRevision &+= 1
    renderWorker?.cancel()
    pendingRenders = []
    requestedKey = nil
    isProcessing = false
    isCapturing = file == nil
    illuminationTask?.cancel()
    illuminationTask = nil
    screenIlluminationActive = false
    captureProgress = 0
    captureSummary = nil
    authoringError = nil
    pendingAcquisition = PhotoAcquisition(revision: acquisitionRevision, sessionID: UUID(), file: file, pose: pose,
      strokeStyle: strokeStyle, duration: captureDuration)
    startWorkIfNeeded()
    await workTask?.value
  }

  private func startWorkIfNeeded() {
    if workTask == nil { workTask = Task { await drainWork() } }
  }

  private func drainWork() async {
    defer { workTask = nil }
    while !isShutdown && (pendingAcquisition != nil || !pendingRenders.isEmpty) {
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
      let acquirer = photoAcquirer, frameSource = frameSource
      let clock = captureClock, retention = photoRetention
      let worker = Task.detached(priority: .userInitiated) { [weak self] in
        if let file = request.file {
          let acquired = try await acquirer.acquire(.file(file))
          try Task.checkCancellation()
          return [PortraitBurstSample(data: acquired.data, frameID: nil,
            captureNanoseconds: nil, label: file.lastPathComponent, sourcePixelExtent: acquired.sourcePixelExtent)]
        }
        await self?.beginCaptureIllumination(duration: request.duration, revision: request.revision)
        let started = await clock.now()
        // Leave the light stable long enough for camera exposure to settle.
        try await clock.sleep(seconds: 0.25)
        // Reject any frame still retained from before the exposure settled.
        let exposureBoundary = try await frameSource.latestFrame(newerThanNanoseconds: 0)
        var lastCaptureNanoseconds = exposureBoundary?.captureNanoseconds ?? 0
        var seenFrames = Set<FrameID>()
        var buffer = PortraitBurstBuffer(retention: retention)
        while true {
          try Task.checkCancellation()
          let elapsed = await clock.now() - started
          guard elapsed < request.duration else { break }
          let sampleStarted = await clock.now()
          if let frame = try await frameSource.latestFrame(newerThanNanoseconds: lastCaptureNanoseconds),
            frame.captureNanoseconds > lastCaptureNanoseconds,
            seenFrames.insert(frame.id).inserted {
            lastCaptureNanoseconds = frame.captureNanoseconds
            let acquired = try await acquirer.acquire(.frame(frame))
            try Task.checkCancellation()
            buffer.append(PortraitBurstSample(data: acquired.data, frameID: frame.id,
              captureNanoseconds: frame.captureNanoseconds,
              label: String(format: "Frame %.1fs", elapsed), sourcePixelExtent: acquired.sourcePixelExtent))
          }
          let afterSample = await clock.now()
          await self?.updateCaptureProgress(min(1, (afterSample - started) / request.duration),
            revision: request.revision)
          let remaining = request.duration - (afterSample - started)
          if remaining > 0 {
            try await clock.sleep(seconds: min(remaining, max(0.001, 0.1 - (afterSample - sampleStarted))))
          }
        }
        try Task.checkCancellation()
        guard !buffer.samples.isEmpty else { throw PortraitDrawingError.noCameraFrame }
        guard let selected = try PortraitBurstSelector.select(from: buffer.samples) else {
          throw PortraitDrawingError.noCameraFrame
        }
        return [selected]
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
        let samples = try await worker.value
        guard request.revision == acquisitionRevision, !isShutdown else { continue }
        finishCapture()
        if request.file == nil { cameraStatus = nil }
        var retained = 0
        for sample in samples {
          if appendPhoto(sample, pose: request.pose, sessionID: request.sessionID) { retained += 1 }
        }
        captureSummary = request.file == nil ? "Photo captured." : nil
        if retained > 0 { render(strokeStyle: request.strokeStyle) }
      } catch {
        guard request.revision == acquisitionRevision, !isShutdown else { continue }
        finishCapture()
        if error is CancellationError { continue }
        if request.file == nil { cameraStatus = error.localizedDescription }
        else { summary = error.localizedDescription; authoringError = error.localizedDescription }
      }
    }
  }

  private func beginCaptureIllumination(duration: Double, revision: UInt64) {
    guard revision == acquisitionRevision, !isShutdown, isCapturing else { return }
    screenIlluminationActive = true
    illuminationTask?.cancel()
    illuminationTask = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(duration)) } catch { return }
      guard let self, revision == self.acquisitionRevision else { return }
      // Image encoding may be synchronous and slow; it cannot extend the
      // visible light beyond the requested capture interval.
      self.screenIlluminationActive = false
      self.captureProgress = 1
    }
  }

  private func updateCaptureProgress(_ progress: Double, revision: UInt64) {
    guard revision == acquisitionRevision, !isShutdown, isCapturing else { return }
    captureProgress = max(captureProgress, progress)
  }

  private func finishCapture() {
    illuminationTask?.cancel()
    illuminationTask = nil
    isCapturing = false
    screenIlluminationActive = false
    captureProgress = 1
  }

  private func prepareStyleForNewSource() {
    guard !PortraitStyle.authoringCases.contains(style) else { return }
    let material = vectorOptions.materialContext
    style = .contours
    vectorOptions = PortraitVectorOptions()
    vectorOptions.materialContext = material
  }

  func setPhoto(_ data: Data, for pose: PortraitPose, strokeStyle: StrokeStyle) {
    guard !isShutdown, photoRetention.maximumCount > 0,
      data.count <= photoRetention.maximumBytes else { return }
    prepareStyleForNewSource()
    invalidateExploration()
    acquisitionRevision &+= 1
    acquisitionWorker?.cancel()
    pendingAcquisition = nil
    finishCapture()
    // Compatibility entry point replaces one legacy pose. Camera bursts and
    // imports append identified photos through the bounded collection instead.
    let replaced = recentPhotos.filter { $0.pose == pose }.map(\.id)
    recentPhotos.removeAll { $0.pose == pose }
    for id in replaced { cache.remove(photoID: id) }
    appendPhoto(.init(data: data, frameID: nil, captureNanoseconds: nil, label: "Photo"), pose: pose)
    if pose == self.pose { render(strokeStyle: strokeStyle) }
  }

  @discardableResult
  private func appendPhoto(_ sample: PortraitBurstSample, pose: PortraitPose, sessionID: UUID = UUID()) -> Bool {
    guard photoRetention.maximumCount > 0, sample.data.count <= photoRetention.maximumBytes else {
      summary = "This photo exceeds the studio's recent-photo memory limit."
      authoringError = summary
      return false
    }
    let photo = PortraitPhoto(id: UUID(), data: sample.data, label: sample.label,
      capturedAt: Date(), frameID: sample.frameID, captureNanoseconds: sample.captureNanoseconds, pose: pose, sourcePixelExtent: sample.sourcePixelExtent, captureSessionID: sessionID,
      selectionProvenance: sample.selectionProvenance)
    recentPhotos.append(photo)
    selectedPhotoID = photo.id
    while recentPhotos.count > photoRetention.maximumCount || retainedPhotoBytes > photoRetention.maximumBytes {
      cache.remove(photoID: recentPhotos.removeFirst().id)
    }
    return true
  }

  func selectPhoto(_ id: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown, let photo = browsablePhotos.first(where: { $0.id == id }) else { return }
    if let entry = sketches.attempts.first(where: {
      $0.candidate.photoID == id && $0.candidate.recipe.style == style
        && $0.candidate.recipe.vectorOptions.bounded == vectorOptions.bounded
        && $0.candidate.recipe.analysisOptions == options
        && $0.candidate.program.strokes.first?.style == strokeStyle
    }) {
      inspectAttempt(entry.id, strokeStyle: strokeStyle)
      return
    }
    let parent = selectedCandidate
    sketches.selectedID = nil
    if !recentPhotos.contains(where: { $0.id == id }) { retainedEditSource = photo }
    pose = photo.pose
    selectedPhotoID = id
    render(strokeStyle: strokeStyle, parent: parent)
  }

  var canRemoveSelectedRecentPhoto: Bool { recentPhotos.contains { $0.id == selectedPhotoID } }

  func deleteRetainedSource(_ photoID: UUID, strokeStyle: StrokeStyle) {
    let sources = Set(sketches.entries.filter { $0.candidate.photoID == photoID }.map { $0.candidate.sourceSHA256 })
    var photoIDs = Set(sketches.entries.filter { sources.contains($0.candidate.sourceSHA256) }.map { $0.candidate.photoID })
    photoIDs.insert(photoID)
    // This explicit source-deletion operation includes byte-identical recent
    // aliases, even when one alias has not completed its first render.
    for photo in recentPhotos where sources.contains(PortraitCandidateCoding.digest(photo.data)) { photoIDs.insert(photo.id) }
    if let retainedEditSource, sources.contains(PortraitCandidateCoding.digest(retainedEditSource.data)) {
      photoIDs.insert(retainedEditSource.id)
    }
    for source in sources { sketches.deleteSource(source) }
    recentPhotos.removeAll { photoIDs.contains($0.id) }
    for id in photoIDs { cache.remove(photoID: id) }
    explorationHistory.removeAll { sources.contains($0.candidate.sourceSHA256) }
    forwardPortraits.removeAll { sources.contains($0.candidate.sourceSHA256) }
    pendingRenders.removeAll { photoIDs.contains($0.photo.id) }
    if let activeRender, photoIDs.contains(activeRender.photo.id) {
      activeRenderWasCancelled = true; renderWorker?.cancel()
    }
    if let selectedPhotoID, photoIDs.contains(selectedPhotoID) {
      cancelExplorationWork()
      renderRevision &+= 1; pendingRenders = []; activeRenderWasCancelled = true; renderWorker?.cancel()
      completedCandidate = nil; completedKey = nil; requestedKey = nil; program = nil
      retainedEditSource = nil; self.selectedPhotoID = nil; isProcessing = false
    }
  }

  func removePhoto(_ id: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown, recentPhotos.contains(where: { $0.id == id }) else { return }
    recentPhotos.removeAll { $0.id == id }
    cache.remove(photoID: id)
    if selectedPhotoID == id {
      selectedPhotoID = recentPhotos.last?.id
      render(strokeStyle: strokeStyle)
    }
  }

  func removeCaptureSession(_ id: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown else { return }
    let removed = recentPhotos.filter { $0.captureSessionID == id }.map(\.id)
    guard !removed.isEmpty else { return }
    recentPhotos.removeAll { $0.captureSessionID == id }
    for photoID in removed { cache.remove(photoID: photoID) }
    if let selectedPhotoID, removed.contains(selectedPhotoID) {
      self.selectedPhotoID = recentPhotos.last?.id
      render(strokeStyle: strokeStyle)
    }
  }

  func removeSelectedBurst(strokeStyle: StrokeStyle) {
    guard let sessionID = selectedSource?.captureSessionID else { return }
    removeCaptureSession(sessionID, strokeStyle: strokeStyle)
  }

  private(set) var firstAlternativeSeconds: Double?
  private(set) var lastHistoryNavigationSeconds: Double?
  var explorationRegion: PortraitTreatmentRegion? = nil {
    didSet {
      if explorationRegion != oldValue {
        forwardPortraits = []
        cancelPortraitStep()
      }
    }
  }
  var isExploring: Bool { explorationJob != nil }
  var canGoBackExploration: Bool { explorationHistory.contains { !isDeletedAttempt($0.candidate) } }
  @ObservationIgnored private var nextExplorationSeed: UInt64
  private var explorationHistory: [(candidate: PortraitCandidate, pen: StrokeStyle)] = []
  private var explorationJob: ExplorationJob?
  private(set) var explorationRejections: [String: Int] = [:]

  private struct ExplorationJob {
    let id = UUID()
    let seed: UInt64
    let center: PortraitCandidate
    let photo: PortraitPhoto
    let pen: StrokeStyle
    let region: PortraitTreatmentRegion?
    let backwards: Bool
    let startedAt = ProcessInfo.processInfo.systemUptime
    var attempt = 0
    var configurations: Set<PortraitVectorOptions>
  }

  var drawingParameters: PortraitDrawingParameters {
    get { vectorOptions.drawingParameters(for: style,
      rasterHeight: selectedCandidate?.raster.height ?? completedCandidate?.raster.height
        ?? PortraitImageAnalyzer.analysisMaximumDimension(for: style)) }
    set { vectorOptions.drawingParameters = newValue.bounded }
  }

  /// Switching kernels preserves shared authoring intent, framing and feature edits.
  func selectStyle(_ selected: PortraitStyle, strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, selected != style,
      PortraitStyle.authoringCases.contains(selected) else { return }
    let parameters = drawingParameters
    cancelPortraitStep()
    vectorOptions.drawingParameters = parameters
    style = selected
    recipeTitle = nil
    renderIfConfigurationChanged(strokeStyle: strokeStyle)
  }

  func applyDetailPreset(_ preset: PortraitVectorPreset) {
    drawingParameters = .preset(preset)
  }

  /// Named starting points in the recipe space, not interaction modes.
  func resetStyle(_ preset: PortraitStyle, strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, PortraitStyle.authoringCases.contains(preset) else { return }
    cancelPortraitStep()
    forwardPortraits = []
    var vectors = PortraitVectorOptions(drawingParameters: .init())
    vectors.materialContext = vectorOptions.materialContext
    style = preset
    vectorOptions = vectors
    recipeTitle = nil
    renderIfConfigurationChanged(strokeStyle: strokeStyle)
  }

  /// Retained navigation never renders. Either end can request a fresh sample.
  func nextPortrait(strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, !isProcessing, !isExploring,
      let current = selectedCandidate, let pen = completedKey?.strokeStyle, pen == strokeStyle else { return }
    forwardPortraits.removeAll { isDeletedAttempt($0.candidate) }
    if let next = forwardPortraits.popLast(), let pose = next.candidate.renderPose {
      explorationHistory.append((current, pen))
      trimHistory(&explorationHistory)
      installCandidateSource(next.candidate, pose: pose)
      installExplorationCandidate(next.candidate, pen: next.pen)
      singlePortraitStatus = nil
      return
    }
    requestPortraitStep(current: current, pen: pen, backwards: false)
  }

  private func requestPortraitStep(current: PortraitCandidate, pen: StrokeStyle, backwards: Bool) {
    guard !isExploring, PortraitStyle.authoringCases.contains(style), let photo = selectedSource,
      photo.id == current.photoID else { return }
    if explorationRegion != nil, PortraitRegionalTreatment.Field(raster: current.raster) == nil {
      singlePortraitStatus = "Feature edits need reliable facial landmarks. Choose Whole portrait or another photo."
      return
    }
    let seed = nextExplorationSeed
    nextExplorationSeed &+= 1
    singlePortraitStatus = nil
    firstAlternativeSeconds = nil
    explorationJob = .init(seed: seed, center: current, photo: photo, pen: pen,
      region: explorationRegion, backwards: backwards,
      configurations: [PortraitExplorationPolicy.effectiveOptions(current.recipe.vectorOptions, center: current)])
    queueExplorationJob()
    startWorkIfNeeded()
  }

  func previousPortrait() {
    guard !isShutdown, !isCapturing, !isProcessing,
      let current = selectedCandidate, let pen = completedKey?.strokeStyle else { return }
    explorationHistory.removeAll { isDeletedAttempt($0.candidate) }
    guard let previous = explorationHistory.popLast(), let pose = previous.candidate.renderPose else {
      requestPortraitStep(current: current, pen: pen, backwards: true)
      return
    }
    forwardPortraits.append((current, pen))
    trimHistory(&forwardPortraits)
    cancelPortraitStep()
    installCandidateSource(previous.candidate, pose: pose)
    installExplorationCandidate(previous.candidate, pen: previous.pen)
  }

  private func trimHistory(_ history: inout [(candidate: PortraitCandidate, pen: StrokeStyle)]) {
    while history.count > PortraitExplorationPolicy.maximumHistoryRounds
      || history.reduce(0, { $0 + PortraitExplorationPolicy.pointCount($1.candidate) }) > PortraitExplorationPolicy.maximumHistoryPoints {
      history.removeFirst()
    }
  }

  func cancelPortraitStep() {
    cancelExplorationWork()
    singlePortraitStatus = nil
  }

  private func installExplorationCandidate(_ candidate: PortraitCandidate, pen: StrokeStyle) {
    guard !isDeletedAttempt(candidate) else { return }
    cancelAuthoringWork()
    installRecipe(candidate.recipe)
    let key = PortraitRenderCacheKey(photoID: candidate.photoID,
      configuration: renderConfiguration, strokeStyle: pen)
    requestedKey = key; completedKey = key; completedCandidate = candidate
    program = candidate.program; isProcessing = false; authoringError = nil
    summary = "\(candidate.program.strokes.count) strokes"
  }

  private func cancelAuthoringWork() {
    pendingRenders.removeAll { $0.explorationID == nil }
    if let activeRender, activeRender.explorationID == nil {
      activeRenderWasCancelled = true
      renderWorker?.cancel()
    }
  }

  private func queueExplorationJob(recipeOverride: PortraitStyleRecipe? = nil,
    failure: String = "No visible change this time. Next tries different parameters.") {
    guard var job = explorationJob else { return }
    guard job.attempt < PortraitExplorationPolicy.maximumAttemptsPerSlot else {
      explorationJob = nil
      singlePortraitStatus = failure
      return
    }
    let recipe: PortraitStyleRecipe
    if let recipeOverride { recipe = recipeOverride }
    else if let region = job.region {
      recipe = PortraitExplorationPolicy.regionalRecipe(around: job.center, region: region,
        seed: job.seed, attempt: job.attempt)
    } else {
      recipe = PortraitExplorationPolicy.recipe(around: job.center, seed: job.seed)
    }
    let identity = try? PortraitAttemptRecord.proposalIdentity(
      sourceSHA256: job.center.sourceSHA256, sourcePixelExtent: job.photo.sourcePixelExtent,
      pose: job.photo.pose, recipe: recipe, pen: job.pen)
    if let identity, sketches.rejectedProposalIdentities.contains(identity) {
      retryExploration(recipe, rejection: .rejectedAttempt,
        failure: "This exact treatment was rejected. Try Next again.")
      return
    }
    let effective = PortraitExplorationPolicy.effectiveOptions(recipe.vectorOptions, center: job.center)
    guard job.configurations.insert(effective).inserted else {
      retryExploration(recipe, rejection: .duplicateConfiguration, failure: failure)
      return
    }
    explorationJob = job
    let key = PortraitRenderCacheKey(photoID: job.photo.id,
      configuration: .init(style: recipe.style, vectors: recipe.vectorOptions, analysis: recipe.analysisOptions),
      strokeStyle: job.pen)
    pendingRenders.append(PendingRender(revision: renderRevision, key: key,
      request: .init(data: job.photo.data, pose: job.photo.pose, style: recipe.style,
        options: recipe.analysisOptions, cachedRaster: job.center.raster,
        strokeStyle: job.pen, vectorOptions: recipe.vectorOptions, sourcePixelExtent: job.photo.sourcePixelExtent),
      photo: job.photo, recipe: recipe,
      lineage: .init(parentID: job.center.id, parentProgramHash: job.center.program.contentHash.description,
        parentRecipe: job.center.recipe, ancestryGroupID: job.center.lineage.ancestryGroupID),
      ownsSource: retainedEditSource?.id == job.photo.id, explorationID: job.id,
      explorationCenter: job.center.program, explorationRegion: job.region))
  }

  private func retryExploration(_ recipe: PortraitStyleRecipe, rejection: PortraitExplorationPolicy.Rejection,
    failure: String) {
    guard var job = explorationJob else { return }
    explorationRejections[rejection.rawValue, default: 0] += 1
    job.attempt += 1
    explorationJob = job
    let recovery = job.region == nil && job.attempt < PortraitExplorationPolicy.maximumAttemptsPerSlot
      ? PortraitExplorationPolicy.recoveryRecipe(around: job.center, failed: recipe,
          rejection: rejection, neighbor: Int(job.seed % 2), seed: job.seed, variation: 0.35,
          excluding: job.configurations) : nil
    queueExplorationJob(recipeOverride: recovery, failure: failure)
  }

  private func finishExplorationJob(_ prepared: PreparedRender, pending: PendingRender) {
    guard let job = explorationJob, job.id == pending.explorationID else { return }
    let candidate = prepared.candidate
    if PortraitExplorationPolicy.pointCount(candidate) + PortraitExplorationPolicy.pointCount(job.center)
      > PortraitExplorationPolicy.maximumRoundPoints {
      retryExploration(pending.recipe, rejection: .detailBudget, failure: "Drawing exceeds the detail budget.")
    } else if !prepared.isDifferent {
      retryExploration(pending.recipe, rejection: .similarGeometry,
        failure: "No visible change this time. Next tries different parameters.")
    } else {
      sketches.recordAttempt(candidate, record: prepared.attempt)
      if job.backwards {
        forwardPortraits.append((job.center, job.pen))
        trimHistory(&forwardPortraits)
      } else {
        explorationHistory.append((job.center, job.pen))
        trimHistory(&explorationHistory)
      }
      explorationJob = nil
      installExplorationCandidate(candidate, pen: job.pen)
      firstAlternativeSeconds = ProcessInfo.processInfo.systemUptime - job.startedAt
      singlePortraitStatus = nil
    }
  }

  private func isDeletedAttempt(_ candidate: PortraitCandidate) -> Bool {
    let deletions = sketches.tombstones.lazy.filter { $0.kind != .label && candidate.createdAt <= $0.createdAt
      && ($0.affectedCandidateIDs.contains(candidate.id) || ($0.kind == .source && $0.identity == candidate.sourceSHA256)) }
    guard let latest = deletions.map(\.createdAt).max() else { return false }
    // The legacy archive API permits an explicit re-retention after deletion.
    // Automatic completed-attempt history does not create such a qualifying event.
    return sketches.entries.first(where: { $0.id == candidate.id && $0.candidate.createdAt == candidate.createdAt })?
      .reasons.contains { $0.createdAt > latest } != true
  }

  private func cancelExplorationWork() {
    explorationJob = nil
    pendingRenders.removeAll { $0.explorationID != nil }
    if activeRender?.explorationID != nil {
      activeRenderWasCancelled = true
      renderWorker?.cancel()
    }
  }

  private func invalidateExploration() {
    forwardPortraits = []
    singlePortraitStatus = nil
    cancelExplorationWork()
    explorationHistory = []
  }

  private func workIsApplicable(_ pending: PendingRender) -> Bool {
    guard !isShutdown, pending.key.photoID == selectedPhotoID,
      pending.ownsSource || recentPhotos.contains(where: { $0.id == pending.key.photoID }) else { return false }
    if let id = pending.explorationID, explorationJob?.id != id { return false }
    return pending.revision == renderRevision
  }

  private func publishRender(_ prepared: PreparedRender, pending: PendingRender) {
    guard pending.revision == renderRevision, pending.key == requestedKey else { return }
    sketches.recordAttempt(prepared.candidate, record: prepared.attempt)
    completedCandidate = prepared.candidate
    completedKey = pending.key
    program = prepared.result.program
    summary = "\(prepared.candidate.program.strokes.count) strokes"
    isProcessing = false
  }

  func render(strokeStyle: StrokeStyle, parent: PortraitCandidate? = nil,
    exactRaster: PortraitRaster? = nil) {
    guard !isShutdown else { return }
    invalidateExploration()
    authoringError = nil
    vectorOptions.headScale = 1
    vectorOptions.semanticHead = nil
    sketches.selectedID = nil
    renderRevision &+= 1
    cancelAuthoringWork()
    program = nil
    completedKey = nil
    requestedKey = nil
    guard let photo = selectedSource else {
      pendingRenders = []
      activeRenderWasCancelled = true
      renderWorker?.cancel()
      completedCandidate = nil
      isProcessing = false
      summary = "Capture a portrait or choose a photo."
      return
    }
    let key = PortraitRenderCacheKey(photoID: photo.id, configuration: renderConfiguration, strokeStyle: strokeStyle)
    requestedKey = key
    isProcessing = true
    let ancestor = parent ?? completedCandidate.flatMap { $0.photoID == photo.id ? $0 : nil }
    let lineage = ancestor.map { PortraitCandidateLineage(parentID: $0.id,
      parentProgramHash: $0.program.contentHash.description, parentRecipe: $0.recipe,
      ancestryGroupID: $0.lineage.ancestryGroupID) }
    let recipe = PortraitStyleRecipe(id: "algorithm-\(style.rawValue)",
      title: recipeTitle ?? style.rawValue, seed: 0, style: style,
      vectorOptions: vectorOptions.bounded, analysisOptions: options)
    pendingRenders.append(PendingRender(revision: renderRevision, key: key,
      request: .init(data: photo.data, pose: photo.pose, style: style, options: options,
        cachedRaster: exactRaster.flatMap { PortraitImageAnalyzer.cachedRasterIsCompatible($0, with: style) ? $0 : nil },
        strokeStyle: strokeStyle, vectorOptions: recipe.vectorOptions, sourcePixelExtent: photo.sourcePixelExtent),
      photo: photo, recipe: recipe, lineage: lineage, ownsSource: retainedEditSource?.id == photo.id))
    startWorkIfNeeded()
  }

  private func drainRenders() async {
    while pendingAcquisition == nil, !isShutdown {
      guard !pendingRenders.isEmpty else { break }
      let pending = pendingRenders.removeFirst()
      guard workIsApplicable(pending) else { continue }
      let cachedResult = cache.result(for: pending.key)
      if cachedResult != nil { renderCacheHits += 1 }
      // Render the selected algorithm first and reuse its exact analysis.
      let original = pending.request
      let request = PortraitRenderRequest(data: original.data, pose: original.pose, style: original.style,
        options: original.options, cachedRaster: original.cachedRaster
          ?? cache.raster(for: .init(photoID: pending.photo.id, analysis: original.options,
            maximumDimension: PortraitImageAnalyzer.analysisMaximumDimension(for: original.style))),
        strokeStyle: original.strokeStyle, vectorOptions: original.vectorOptions,
        sourcePixelExtent: original.sourcePixelExtent,
        flowWorkspace: original.flowWorkspace ?? cache.flowWorkspace(for: .init(photoID: pending.photo.id,
          analysis: original.options, maximumDimension: PortraitImageAnalyzer.analysisMaximumDimension(for: original.style))),
        preparedSource: original.preparedSource ?? cache.sourcePreparation(for: pending.photo.id))
      let renderer = renderer
      let workerStartedAt = ProcessInfo.processInfo.systemUptime
      let queueMS = (workerStartedAt - pending.queuedAt) * 1000
      let roundID = pending.explorationID?.uuidString ?? "selected"
      Self.logger.info("Render started source=\(pending.photo.id.uuidString, privacy: .public) round=\(roundID, privacy: .public) revision=\(pending.revision) style=\(pending.recipe.style.rawValue, privacy: .public) queue_ms=\(queueMS) result_cache=\(cachedResult != nil) source_cache=\(request.preparedSource != nil) raster_cache=\(request.cachedRaster != nil)")
      let worker = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let result: PortraitRenderResult
        if let cachedResult { result = cachedResult }
        else { result = try await renderer.render(request) }
        return try Self.prepare(result, pending: pending)
      }
      renderWorker = worker
      activeRender = pending
      activeRenderWasCancelled = false
      workerStarted()
      // Renderer diagnostics count actual calls; work diagnostics include
      // cached-result preparation as part of the same bounded worker lifecycle.
      if cachedResult == nil {
        renderDiagnostics.startedWorkerCount += 1
        renderDiagnostics.activeWorkerCount += 1
        renderDiagnostics.maximumConcurrentWorkerCount = max(
          renderDiagnostics.maximumConcurrentWorkerCount, renderDiagnostics.activeWorkerCount)
      }
      defer {
        workerSettled()
        if cachedResult == nil {
          renderDiagnostics.activeWorkerCount -= 1
          renderDiagnostics.settledWorkerCount += 1
        }
        renderWorker = nil
        activeRender = nil
        activeRenderWasCancelled = false
      }
      do {
        let prepared = try await worker.value
        let result = prepared.result
        guard !activeRenderWasCancelled, workIsApplicable(pending) else { continue }
        let publicationStarted = ProcessInfo.processInfo.systemUptime
        cache.insert(result, for: pending.key)
        if pending.explorationID != nil { finishExplorationJob(prepared, pending: pending) }
        else { publishRender(prepared, pending: pending) }
        let stages = cachedResult == nil ? result.timings : nil
        let publicationMS = (ProcessInfo.processInfo.systemUptime - publicationStarted) * 1000
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - pending.queuedAt) * 1000
        Self.logger.info("Render published source=\(pending.photo.id.uuidString, privacy: .public) round=\(roundID, privacy: .public) revision=\(pending.revision) source_ms=\(stages?.sourceMS ?? 0) crop_ms=\(stages?.cropMS ?? 0) flow_ms=\(stages?.flowMS ?? 0) vector_ms=\(stages?.vectorMS ?? 0) preparation_ms=\(prepared.preparationSeconds * 1000) publication_ms=\(publicationMS) total_ms=\(elapsedMS)")
      } catch {
        guard !activeRenderWasCancelled, workIsApplicable(pending) else { continue }
        if let failure = error as? PortraitPreparedRenderFailure {
          cache.insertSourcePreparation(failure.preparedSource, for: pending.photo.id)
        }
        let renderError = (error as? PortraitPreparedRenderFailure)?.underlyingError ?? error
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - pending.queuedAt) * 1000
        Self.logger.info("Render failed source=\(pending.photo.id.uuidString, privacy: .public) round=\(roundID, privacy: .public) revision=\(pending.revision) total_ms=\(elapsedMS) reason=\(renderError.localizedDescription, privacy: .public)")
        if pending.explorationID != nil {
          let rejection: PortraitExplorationPolicy.Rejection
          if let error = renderError as? PortraitDrawingError, case .noLines = error { rejection = .noLines }
          else { rejection = .renderFailure }
          retryExploration(pending.recipe, rejection: rejection, failure: renderError.localizedDescription)
          continue
        }
        if pending.revision == renderRevision, pending.key == requestedKey {
          if !(renderError is CancellationError) {
            summary = renderError.localizedDescription
            authoringError = renderError.localizedDescription
          }
          isProcessing = false
          requestedKey = nil
        }
      }
    }
  }

  /// Material adaptation owns its requested pen. Configuration callbacks do
  /// not replace that pen with the global nominal profile; actual pen changes
  /// use renderIfNeeded to invalidate the current result.
  func renderIfConfigurationChanged(strokeStyle: StrokeStyle) {
    if requestedKey?.photoID == selectedPhotoID,
      requestedKey?.configuration == renderConfiguration { return }
    renderIfNeeded(strokeStyle: strokeStyle)
  }

  func renderIfNeeded(strokeStyle: StrokeStyle) {
    guard let selectedPhotoID else { return }
    let key = PortraitRenderCacheKey(photoID: selectedPhotoID,
      configuration: renderConfiguration, strokeStyle: strokeStyle)
    guard requestedKey != key else { return }
    sketches.selectedID = nil
    render(strokeStyle: strokeStyle)
  }

  private func installRecipe(_ recipe: PortraitStyleRecipe) {
    recipeTitle = recipe.title
    style = recipe.style
    vectorOptions = recipe.vectorOptions
    options = recipe.analysisOptions
    sketches.selectedID = nil
  }

  /// Applies an explicit profile at the accepted height to a new candidate.
  /// Exact source/head analysis survives, and old/rated candidates stay immutable.
  func applyMaterial(_ profile: DrawingMaterialProfileRevision, drawingHeightMM: Double) async -> String? {
    guard let parent = selectedCandidate, let pose = parent.renderPose else {
      return "Select a completed drawing before applying a material."
    }
    do {
      let context = try PortraitMaterialContext(profile: profile, drawingHeightMM: drawingHeightMM)
      let pen = try StrokeStyle(nominalLineWidth: profile.nominalWidthMM, penProfileID: PenProfileID(profile.id))
      acquisitionRevision &+= 1; pendingAcquisition = nil; acquisitionWorker?.cancel(); finishCapture()
      installCandidateSource(parent, pose: pose)
      installRecipe(parent.recipe)
      vectorOptions.materialContext = context
      render(strokeStyle: pen, parent: parent, exactRaster: parent.raster)
      await awaitRendering()
      guard let result = completedCandidate, result.lineage.parentID == parent.id,
        result.recipe.vectorOptions.materialContext == context else {
        return isProcessing ? "Material rendering was superseded." : summary
      }
      return nil
    } catch { return error.localizedDescription }
  }

  private func installCandidateSource(_ candidate: PortraitCandidate, pose: PortraitPose) {
    retainedEditSource = PortraitPhoto(id: candidate.photoID, data: candidate.sourceData,
      label: candidate.recipe.title, capturedAt: candidate.createdAt, frameID: nil,
      captureNanoseconds: nil, pose: pose, sourcePixelExtent: candidate.sourcePixelExtent,
      captureSessionID: candidate.captureSessionID)
    let history = explorationHistory
    let forward = forwardPortraits
    self.pose = pose
    explorationHistory = history
    forwardPortraits = forward
    selectedPhotoID = candidate.photoID
  }

  func movePhoto(by offset: Int, strokeStyle: StrokeStyle) {
    let photos = browsablePhotos
    guard !photos.isEmpty else { return }
    let current = photos.firstIndex(where: { $0.id == selectedPhotoID }) ?? 0
    let index = ((current + offset) % photos.count + photos.count) % photos.count
    sketches.selectedID = nil
    selectPhoto(photos[index].id, strokeStyle: strokeStyle)
  }

  func loadArchive() async { await sketches.load() }

  func feedback(for candidate: PortraitCandidate) -> PortraitAttemptFeedback {
    sketches.entries.first(where: { $0.id == candidate.id })?.attempt?.feedback ?? .unknown
  }

  func toggleFeedback(_ value: PortraitAttemptFeedback, candidate: PortraitCandidate) {
    sketches.setFeedback(feedback(for: candidate) == value ? .unknown : value, for: candidate.id)
  }

  /// Install the retained payload directly. No portrait render or source analysis
  /// is scheduled by Back, a history click, or a feedback change.
  func inspectAttempt(_ id: String, strokeStyle: StrokeStyle) {
    guard !isShutdown, let candidate = sketches.entries.first(where: { $0.id == id })?.candidate,
      let pose = candidate.renderPose else { return }
    forwardPortraits = []
    singlePortraitStatus = nil
    let started = ProcessInfo.processInfo.systemUptime
    acquisitionRevision &+= 1
    pendingAcquisition = nil
    acquisitionWorker?.cancel()
    finishCapture()
    if let current = selectedCandidate, current.id != candidate.id, let pen = completedKey?.strokeStyle {
      explorationHistory.append((current, pen))
      trimHistory(&explorationHistory)
    }
    cancelExplorationWork()
    renderRevision &+= 1
    pendingRenders = []
    activeRenderWasCancelled = true
    renderWorker?.cancel()
    installCandidateSource(candidate, pose: pose)
    let pen = candidate.program.strokes.first?.style ?? strokeStyle
    installExplorationCandidate(candidate, pen: pen)
    lastHistoryNavigationSeconds = ProcessInfo.processInfo.systemUptime - started
    Self.logger.info("History selection installed elapsed_ms=\((self.lastHistoryNavigationSeconds ?? 0) * 1000) render_count=\(self.renderDiagnostics.startedWorkerCount)")
  }

  func clearUnkeptHistory() {
    forwardPortraits = []
    cancelExplorationWork()
    explorationHistory = []
    let displayedID = selectedCandidate?.id
      ?? (completedCandidate?.photoID == selectedPhotoID ? completedCandidate?.id : nil)
    sketches.clearUnkeptHistory(preserving: displayedID)
  }

  func deleteAttempt(_ id: String) {
    forwardPortraits.removeAll { $0.candidate.id == id }
    explorationHistory.removeAll { $0.candidate.id == id }
    if completedCandidate?.id == id {
      cancelExplorationWork()
      completedCandidate = nil; completedKey = nil; requestedKey = nil; program = nil
    }
    sketches.remove(id)
  }

  func burdenSummary(for candidate: PortraitCandidate) -> String {
    sketches.entries.first(where: { $0.id == candidate.id })?.attempt?.burdenSummary
      ?? "\(candidate.program.strokes.count) strokes"
  }

  var browserTimingSummary: String {
    func ms(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0 * 1000) } ?? "Not measured" }
    return "History selection install: \(ms(lastHistoryNavigationSeconds)). Next useful variation: \(ms(firstAlternativeSeconds)). Renderer calls: \(renderDiagnostics.startedWorkerCount). Selection timing excludes display painting. Variation timing includes queue wait and publication."
  }

  func saveStyle(name: String) {
    guard let candidate = selectedCandidate else { return }
    sketches.saveStyle(name: name, recipe: candidate.recipe)
  }

  func applySavedStyle(_ saved: PortraitSavedStyle, strokeStyle: StrokeStyle) {
    let parent = selectedCandidate
    installRecipe(saved.recipe)
    render(strokeStyle: strokeStyle, parent: parent)
  }

  func keepSelection() -> String? {
    guard let candidate = selectedCandidate else { return "Wait for the selected drawing to finish rendering." }
    let selection = sketches.selectedID
    defer { sketches.selectedID = selection }
    return sketches.retain(candidate: candidate, reason: .shortlisted)
  }

  /// Capture the immutable candidate before crossing an asynchronous acceptance
  /// boundary. A failed camera/program/Fit action cannot qualify the drawing.
  func acceptProjection(_ candidate: PortraitCandidate,
    perform: () async -> String?) async -> String? {
    guard !isDeletedAttempt(candidate) else { return "This attempt was deleted. Select a retained attempt before handoff." }
    if let error = await perform() { return error }
    guard !isDeletedAttempt(candidate) else { return "The accepted attempt was deleted while handoff was pending." }
    projectedCandidate = candidate
    let selection = sketches.selectedID
    defer { sketches.selectedID = selection }
    return sketches.retain(candidate: candidate, reason: .projectionAccepted(acceptanceID: UUID()))
  }

  /// Stop expensive work without discarding captured photos or the last
  /// completed draft. Replacement work waits for the current worker to settle.
  func cancelRendering() async {
    cancelExplorationWork()
    acquisitionDiagnostics.cancellationCount += 1
    acquisitionRevision &+= 1
    pendingAcquisition = nil
    illuminationTask?.cancel()
    illuminationTask = nil
    isCapturing = false
    screenIlluminationActive = false
    captureProgress = 0
    acquisitionWorker?.cancel()
    renderRevision &+= 1
    pendingRenders = []
    requestedKey = currentProgram == nil ? nil : completedKey
    isProcessing = false
    activeRenderWasCancelled = true
    renderWorker?.cancel()
    await workTask?.value
  }

  func awaitRendering() async { await workTask?.value }

  func cameraDiagnostics() async -> CameraCaptureSnapshot { await camera.snapshot() }

  func shutdown() async {
    isShutdown = true
    await cancelRendering()
    await stopCamera()
    await sketches.awaitPersistence()
  }
}
