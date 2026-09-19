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
  var pose: PortraitPose = .front {
    didSet {
      if pose != oldValue { selectedPhotoID = recentPhotos.last(where: { $0.pose == pose })?.id }
    }
  }
  var style: PortraitStyle = .contours
  var options = PortraitAnalysisOptions()
  var vectorOptions = PortraitVectorOptions()
  let sketches: PortraitSketchCollection
  private(set) var completedCandidate: PortraitCandidate?
  /// One immutable result per built-in renderer for the same photo and controls.
  private var algorithmResults: [PortraitCandidate] = []
  var algorithmCandidates: [PortraitCandidate] {
    algorithmResults.filter { $0.photoID == selectedPhotoID
      && $0.recipe.analysisOptions == options
      && $0.recipe.vectorOptions.bounded == vectorOptions.bounded }
  }
  var selectedAlgorithm: PortraitStyle { style }
  private(set) var hasSelectedAlgorithm = false
  private(set) var isComparingAlgorithms = false
  @ObservationIgnored private var pendingAlgorithms: [PendingRender] = []
  /// Exact last successful projection; gallery browsing cannot replace this association.
  private(set) var projectedCandidate: PortraitCandidate?
  var selectedCandidate: PortraitCandidate? {
    sketches.selected?.candidate ?? (currentProgram == nil ? nil : completedCandidate)
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
      completedKey?.configuration == renderConfiguration else { return nil }
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
  var selectedPhoto: Data? { selectedCandidate?.sourceData ?? selectedSource?.data }
  var retainedPhotoBytes: Int { recentPhotos.reduce(0) { $0 + $1.data.count } }
  // Transitional access for existing source-provenance consumers. New studio
  // controls use identified recent photos, never left/center/right slots.
  var photos: [PortraitPose: Data] {
    Dictionary(recentPhotos.map { ($0.pose, $0.data) }, uniquingKeysWith: { _, newest in newest })
  }
  var captureDuration: Double = 4
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
  @ObservationIgnored private var renderWorker: Task<PortraitRenderResult, Error>?
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
    let revision: UInt64
    let key: PortraitRenderCacheKey
    let request: PortraitRenderRequest
    let photo: PortraitPhoto
    let recipe: PortraitStyleRecipe
    let lineage: PortraitCandidateLineage?
    let ownsSource: Bool
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
    candidateStore: PortraitCandidateStore? = nil
  ) {
    let collection = PortraitSketchCollection(store: candidateStore)
    sketches = collection
    self.camera = camera
    self.renderer = renderer
    self.photoAcquirer = photoAcquirer
    self.frameSource = frameSource ?? PortraitCameraFrameSource(camera: camera)
    self.captureClock = captureClock
    self.photoRetention = photoRetention
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
    acquisitionRevision &+= 1
    acquisitionDiagnostics.requestedWorkCount += 1
    acquisitionWorker?.cancel()
    renderRevision &+= 1
    renderWorker?.cancel()
    pendingAlgorithms = []
    algorithmResults = []
    isComparingAlgorithms = false
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
      strokeStyle: strokeStyle, duration: min(5, max(3, captureDuration.isFinite ? captureDuration : 4)))
    startWorkIfNeeded()
    await workTask?.value
  }

  private func startWorkIfNeeded() {
    if workTask == nil { workTask = Task { await drainWork() } }
  }

  private func drainWork() async {
    defer { workTask = nil }
    while !isShutdown && (pendingAcquisition != nil || !pendingAlgorithms.isEmpty) {
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
        try await clock.sleep(seconds: 0.5)
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
            try await clock.sleep(seconds: min(remaining, max(0.001, 0.125 - (afterSample - sampleStarted))))
          }
        }
        try Task.checkCancellation()
        guard !buffer.samples.isEmpty else { throw PortraitDrawingError.noCameraFrame }
        return buffer.samples
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
        captureSummary = request.file == nil ? "Captured \(retained) distinct frames. Choose a frame to sketch." : nil
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

  func setPhoto(_ data: Data, for pose: PortraitPose, strokeStyle: StrokeStyle) {
    guard !isShutdown, photoRetention.maximumCount > 0,
      data.count <= photoRetention.maximumBytes else { return }
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
      capturedAt: Date(), frameID: sample.frameID, captureNanoseconds: sample.captureNanoseconds, pose: pose, sourcePixelExtent: sample.sourcePixelExtent, captureSessionID: sessionID)
    recentPhotos.append(photo)
    selectedPhotoID = photo.id
    while recentPhotos.count > photoRetention.maximumCount || retainedPhotoBytes > photoRetention.maximumBytes {
      cache.remove(photoID: recentPhotos.removeFirst().id)
    }
    return true
  }

  func selectPhoto(_ id: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown, let photo = recentPhotos.first(where: { $0.id == id }) else { return }
    sketches.selectedID = nil
    pose = photo.pose
    selectedPhotoID = id
    render(strokeStyle: strokeStyle)
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

  /// Select the immutable object displayed in the tile. No proposal or rerender
  /// can change the result between choosing it and showing its adjustments.
  func selectAlgorithm(_ algorithm: PortraitStyle, strokeStyle: StrokeStyle) {
    guard !isShutdown, let candidate = algorithmCandidates.first(where: {
      $0.recipe.style == algorithm
    }), let key = algorithmKey(for: candidate), key.strokeStyle == strokeStyle else { return }
    installRecipe(candidate.recipe)
    hasSelectedAlgorithm = true
    requestedKey = key
    completedKey = key
    completedCandidate = candidate
    program = candidate.program
    isProcessing = false
    summary = "\(candidate.program.strokes.count) strokes"
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

  private func algorithmKey(for candidate: PortraitCandidate) -> PortraitRenderCacheKey? {
    // Empty renderings still carry their requested pen in the comparison key.
    guard let pen = comparisonPen else { return nil }
    return .init(photoID: candidate.photoID,
      configuration: .init(style: candidate.recipe.style,
        vectors: candidate.recipe.vectorOptions.bounded, analysis: candidate.recipe.analysisOptions),
      strokeStyle: pen)
  }

  @ObservationIgnored private var comparisonPen: StrokeStyle?

  private func queueAlgorithmComparison(photo: PortraitPhoto, strokeStyle: StrokeStyle,
    exactRaster: PortraitRaster?, lineage: PortraitCandidateLineage?) {
    comparisonPen = strokeStyle
    isProcessing = true
    // Render the current selection first; present the completed tiles in the
    // stable enum order regardless of completion order.
    let order = [style] + PortraitStyle.allCases.filter { $0 != style }
    for algorithm in order {
      let recipe = PortraitStyleRecipe(id: "algorithm-\(algorithm.rawValue)",
        title: algorithm.rawValue, seed: 0, style: algorithm,
        vectorOptions: vectorOptions.bounded, analysisOptions: options)
      let key = PortraitRenderCacheKey(photoID: photo.id,
        configuration: .init(style: algorithm, vectors: recipe.vectorOptions,
          analysis: recipe.analysisOptions), strokeStyle: strokeStyle)
      if let result = cache.result(for: key) {
        renderCacheHits += 1
        publishAlgorithm(result, key: key, photo: photo, recipe: recipe, lineage: lineage)
      } else {
        pendingAlgorithms.append(PendingRender(revision: renderRevision, key: key,
          request: .init(data: photo.data, pose: photo.pose, style: algorithm,
            options: options, cachedRaster: exactRaster, strokeStyle: strokeStyle,
            vectorOptions: recipe.vectorOptions, sourcePixelExtent: photo.sourcePixelExtent),
          photo: photo, recipe: recipe, lineage: lineage,
          ownsSource: retainedEditSource?.id == photo.id))
      }
    }
    isComparingAlgorithms = !pendingAlgorithms.isEmpty
    if isComparingAlgorithms { startWorkIfNeeded() }
  }

  private func publishAlgorithm(_ result: PortraitRenderResult, key: PortraitRenderCacheKey,
    photo: PortraitPhoto, recipe: PortraitStyleRecipe, lineage: PortraitCandidateLineage?) {
    do {
      let candidate = try PortraitCandidate(sourceData: photo.data,
        sourcePixelExtent: photo.sourcePixelExtent, raster: result.raster, recipe: recipe,
        program: result.program, photoID: photo.id, captureSessionID: photo.captureSessionID,
        lineage: lineage, pose: photo.pose, warpManifest: result.warpManifest)
      algorithmResults.removeAll { $0.recipe.style == recipe.style }
      algorithmResults.append(candidate)
      algorithmResults.sort {
        PortraitStyle.allCases.firstIndex(of: $0.recipe.style)!
          < PortraitStyle.allCases.firstIndex(of: $1.recipe.style)!
      }
      if key == requestedKey {
        completedCandidate = candidate
        completedKey = key
        program = result.program
        summary = "\(result.program.strokes.count) strokes"
        isProcessing = false
      }
    } catch {
      summary = error.localizedDescription
      authoringError = error.localizedDescription
      if key == requestedKey { isProcessing = false }
    }
  }

  func render(strokeStyle: StrokeStyle, parent: PortraitCandidate? = nil,
    exactRaster: PortraitRaster? = nil) {
    guard !isShutdown else { return }
    authoringError = nil
    vectorOptions.headScale = 1
    vectorOptions.semanticHead = nil
    sketches.selectedID = nil
    renderRevision &+= 1
    renderWorker?.cancel()
    pendingAlgorithms = []
    algorithmResults = []
    isComparingAlgorithms = false
    program = nil
    completedKey = nil
    requestedKey = nil
    guard let photo = selectedSource else {
      completedCandidate = nil
      isProcessing = false
      summary = "Capture a portrait or choose a photo."
      return
    }
    requestedKey = .init(photoID: photo.id, configuration: renderConfiguration, strokeStyle: strokeStyle)
    let lineage = parent.map { PortraitCandidateLineage(parentID: $0.id,
      parentProgramHash: $0.program.contentHash.description, parentRecipe: $0.recipe,
      ancestryGroupID: $0.lineage.ancestryGroupID) }
    queueAlgorithmComparison(photo: photo, strokeStyle: strokeStyle,
      exactRaster: exactRaster, lineage: lineage)
  }

  private func drainRenders() async {
    defer { renderWorker = nil }
    while pendingAcquisition == nil, !isShutdown {
      guard !pendingAlgorithms.isEmpty else { break }
      let pending = pendingAlgorithms.removeFirst()
      // Render the selected algorithm first and reuse its exact analysis.
      let original = pending.request
      let request = PortraitRenderRequest(data: original.data, pose: original.pose, style: original.style,
        options: original.options, cachedRaster: original.cachedRaster
          ?? cache.raster(for: .init(photoID: pending.photo.id, analysis: original.options)),
        strokeStyle: original.strokeStyle, vectorOptions: original.vectorOptions,
        sourcePixelExtent: original.sourcePixelExtent)
      let renderer = renderer
      let worker = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        return try await renderer.render(request)
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
        guard pending.revision == renderRevision, selectedPhotoID == pending.key.photoID,
          (pending.ownsSource || recentPhotos.contains(where: { $0.id == pending.key.photoID })), !isShutdown else { continue }
        cache.insert(result, for: pending.key)
        publishAlgorithm(result, key: pending.key, photo: pending.photo,
          recipe: pending.recipe, lineage: pending.lineage)
      } catch {
        guard pending.revision == renderRevision, !isShutdown else { continue }
        if !(error is CancellationError) {
          summary = error.localizedDescription
          authoringError = error.localizedDescription
        }
        if pending.key == requestedKey {
          isProcessing = false
          requestedKey = nil
        }
      }
      isComparingAlgorithms = !pendingAlgorithms.isEmpty
    }
  }

  /// Material adaptation owns its requested pen. Configuration callbacks do
  /// not replace that pen with the global nominal profile; actual pen changes
  /// use renderIfNeeded to invalidate every algorithm result.
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
    self.pose = pose
    selectedPhotoID = candidate.photoID
  }

  func movePhoto(by offset: Int, strokeStyle: StrokeStyle) {
    guard !recentPhotos.isEmpty else { return }
    let current = recentPhotos.firstIndex(where: { $0.id == selectedPhotoID }) ?? 0
    let index = ((current + offset) % recentPhotos.count + recentPhotos.count) % recentPhotos.count
    sketches.selectedID = nil
    selectPhoto(recentPhotos[index].id, strokeStyle: strokeStyle)
  }

  func loadArchive() async { await sketches.load() }

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
    if let error = await perform() { return error }
    projectedCandidate = candidate
    let selection = sketches.selectedID
    defer { sketches.selectedID = selection }
    return sketches.retain(candidate: candidate, reason: .projectionAccepted(acceptanceID: UUID()))
  }

  /// Stop expensive work without discarding captured photos or the last
  /// completed draft. Replacement work waits for the current worker to settle.
  func cancelRendering() async {
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
    pendingAlgorithms = []
    isComparingAlgorithms = false
    requestedKey = nil
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
    await sketches.awaitPersistence()
  }
}
