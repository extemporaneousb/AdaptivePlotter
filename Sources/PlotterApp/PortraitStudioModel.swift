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

enum PortraitStudioMode: Hashable { case contour, explorer }

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
  private(set) var studioMode: PortraitStudioMode = .contour
  private(set) var singlePortraitStatus: String?
  private var forwardPortraits: [(candidate: PortraitCandidate, pen: StrokeStyle)] = []
  var canGoForwardPortrait: Bool { forwardPortraits.contains { !isDeletedAttempt($0.candidate) } }
  var options = PortraitAnalysisOptions()
  var vectorOptions = PortraitVectorOptions()
  let sketches: PortraitSketchCollection
  private(set) var completedCandidate: PortraitCandidate?
  /// Stable style references belong to the source context, independently of the
  /// currently authored drawing and its preference trajectory.
  private var algorithmResults: [PortraitCandidate] = []
  var algorithmCandidates: [PortraitCandidate] {
    guard let context = comparisonContext, comparisonContextIsCurrent(context) else { return [] }
    return algorithmResults.filter { !isDeletedAttempt($0) }
  }
  var selectedAlgorithm: PortraitStyle { style }
  private(set) var isStyleComparisonExpanded = false
  private(set) var isComparingAlgorithms = false
  @ObservationIgnored private var pendingAlgorithms: [PendingRender] = []
  @ObservationIgnored private var activeAlgorithm: PendingRender?
  @ObservationIgnored private var activeAlgorithmWasCancelled = false
  private struct ComparisonContextKey: Equatable, Sendable {
    let photoID: UUID
    let pose: PortraitPose
    let analysis: PortraitAnalysisOptions
    let material: PortraitMaterialContext?
    let pen: StrokeStyle
  }
  private struct ComparisonContext: Sendable {
    let id: UUID
    let key: ComparisonContextKey
    let vectors: PortraitVectorOptions
    let lineage: PortraitCandidateLineage?
  }
  @ObservationIgnored private var comparisonContext: ComparisonContext?
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
    var exploration: ExplorationJob? = nil
    var comparisonID: UUID? = nil
  }
  private struct PreparedRender: Sendable {
    let result: PortraitRenderResult
    let candidate: PortraitCandidate
    let geometry: PortraitExplorationPolicy.VisibleGeometry
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
    let geometry = PortraitExplorationPolicy.VisibleGeometry(candidate.program)
    let attempt = try PortraitAttemptRecord.prepare(candidate: candidate, pen: pending.key.strokeStyle)
    return PreparedRender(result: result, candidate: candidate, geometry: geometry, attempt: attempt,
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
    pendingAlgorithms = []
    algorithmResults = []
    comparisonContext = nil
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
      strokeStyle: strokeStyle, duration: captureDuration)
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
    algorithmResults.removeAll { sources.contains($0.sourceSHA256) }
    explorationHistory.removeAll { snapshot in
      snapshot.round.slots.contains { $0.candidate.map { sources.contains($0.sourceSHA256) } == true }
    }
    pendingAlgorithms.removeAll { photoIDs.contains($0.photo.id) }
    if let activeAlgorithm, photoIDs.contains(activeAlgorithm.photo.id) {
      activeAlgorithmWasCancelled = true; renderWorker?.cancel()
    }
    if let selectedPhotoID, photoIDs.contains(selectedPhotoID) {
      cancelExplorationWork()
      explorationRound = nil
      renderRevision &+= 1; pendingAlgorithms = []; activeAlgorithmWasCancelled = true; renderWorker?.cancel()
      completedCandidate = nil; completedKey = nil; requestedKey = nil; program = nil
      retainedEditSource = nil; self.selectedPhotoID = nil; isProcessing = false
      comparisonContext = nil; isComparingAlgorithms = false
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

  /// Select the immutable object displayed in the tile. No proposal or rerender
  /// can change the result between choosing it and showing its adjustments.
  func selectAlgorithm(_ algorithm: PortraitStyle, strokeStyle: StrokeStyle) {
    guard !isShutdown, let candidate = algorithmCandidates.first(where: {
      $0.recipe.style == algorithm
    }), let key = algorithmKey(for: candidate), key.strokeStyle == strokeStyle else { return }
    invalidateExploration()
    cancelAuthoringWork()
    installRecipe(candidate.recipe)
    requestedKey = key
    completedKey = key
    completedCandidate = candidate
    program = candidate.program
    isProcessing = false
    summary = "\(candidate.program.strokes.count) strokes"
    beginExplorationIfNeeded()
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
    guard let pen = comparisonContext?.key.pen else { return nil }
    return .init(photoID: candidate.photoID,
      configuration: .init(style: candidate.recipe.style,
        vectors: candidate.recipe.vectorOptions.bounded, analysis: candidate.recipe.analysisOptions),
      strokeStyle: pen)
  }

  private(set) var explorationRound: PortraitExplorationRound?
  private(set) var explorationSearch = PortraitExplorationSearchState()
  var explorationVariation: Double { explorationSearch.step }
  var displayedExplorationRound: PortraitExplorationRound? {
    let round = buildingExploration.map { explorationSnapshot($0, unfinishedReason: "Generating") } ?? explorationRound
    guard let round, !isDeletedAttempt(round.center) else { return nil }
    return .init(id: round.id, seed: round.seed, variation: round.variation, center: round.center,
      slots: round.slots.map { slot in
        if let candidate = slot.candidate, isDeletedAttempt(candidate) {
          return .init(index: slot.index, candidate: nil, unavailableReason: "Attempt deleted")
        }
        return slot
      })
  }
  var explorationDisplayID: UUID? { displayedExplorationRound?.id }
  private(set) var firstAlternativeSeconds: Double?
  private(set) var alternativePairSeconds: Double?
  private(set) var lastHistoryNavigationSeconds: Double?
  @ObservationIgnored private var explorationStartedAt: TimeInterval?
  var explorationRegion: PortraitTreatmentRegion? = nil {
    didSet {
      if explorationRegion != oldValue {
        forwardPortraits = []
        cancelExplorationWork()
        explorationRound = nil
      }
    }
  }
  private(set) var isExploring = false
  private(set) var isExplorationEnabled = false
  var canGoBackExploration: Bool {
    explorationHistory.contains { !$0.round.slots.contains { $0.candidate.map { isDeletedAttempt($0) } == true } }
  }
  @ObservationIgnored private var nextExplorationSeed: UInt64
  @ObservationIgnored private var explorationPen: StrokeStyle?
  @ObservationIgnored private var explorationHistory: [ExplorationSnapshot] = []
  @ObservationIgnored private var explorationTrace: [PortraitExplorationRecord] = []
  @ObservationIgnored private let explorationTraceSessionID = UUID()
  @ObservationIgnored private var explorationTraceSequence: UInt64 = 0
  @ObservationIgnored private var buildingExploration: ExplorationBuilder?
  @ObservationIgnored private var geometryCache: [(String, PortraitExplorationPolicy.VisibleGeometry)] = []
  private(set) var explorationRejections: [String: Int] = [:]
  private(set) var explorationPreviousOptionCount = 0

  private func rememberGeometry(_ geometry: PortraitExplorationPolicy.VisibleGeometry, program: DrawingProgram) {
    let key = program.contentHash.description
    geometryCache.removeAll { $0.0 == key }
    geometryCache.append((key, geometry))
    if geometryCache.count > 64 { geometryCache.removeFirst() }
  }

  private func geometry(for candidate: PortraitCandidate) -> PortraitExplorationPolicy.VisibleGeometry {
    if let retained = geometryCache.first(where: { $0.0 == candidate.program.contentHash.description }) { return retained.1 }
    let value = PortraitExplorationPolicy.VisibleGeometry(candidate.program)
    rememberGeometry(value, program: candidate.program)
    return value
  }

  private func rejected(_ reason: PortraitExplorationPolicy.Rejection) {
    explorationRejections[reason.rawValue, default: 0] += 1
  }

  private struct ExplorationJob: Sendable {
    let roundID: UUID
    let neighbor: Int
    let attempt: Int
  }
  private struct ExplorationSnapshot {
    let round: PortraitExplorationRound
    let pen: StrokeStyle
    let search: PortraitExplorationSearchState
  }
  private struct ExplorationBuilder {
    let id: UUID
    let seed: UInt64
    let center: PortraitCandidate
    let photo: PortraitPhoto
    let pen: StrokeStyle
    let variation: Double
    let recipes: [[PortraitStyleRecipe]]
    let previousChoices: [PortraitCandidate]
    let region: PortraitTreatmentRegion?
    let singleStep: Bool
    var slots: [Int: PortraitExplorationSlot] = [:]
    var geometries: [PortraitExplorationPolicy.VisibleGeometry]
    var configurations: Set<PortraitVectorOptions>
    var pointCount: Int
  }

  func selectStudioMode(_ mode: PortraitStudioMode, strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing else { return }
    studioMode = mode
    setExplorationEnabled(false, strokeStyle: strokeStyle)
    if mode == .contour, style != .contours {
      let material = vectorOptions.materialContext
      style = .contours
      vectorOptions = PortraitVectorOptions()
      vectorOptions.materialContext = material
      recipeTitle = nil
      render(strokeStyle: strokeStyle)
    }
  }

  /// Navigation installs retained candidates synchronously; only an explicit
  /// Next at the end of the trail requests a single bounded render search.
  func nextPortrait(strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, !isProcessing, !isExploring,
      let current = selectedCandidate, let pen = completedKey?.strokeStyle, pen == strokeStyle else { return }
    forwardPortraits.removeAll { isDeletedAttempt($0.candidate) }
    if let next = forwardPortraits.popLast(), let pose = next.candidate.renderPose {
      rememberExploration(singlePortraitSnapshot(current))
      installCandidateSource(next.candidate, pose: pose)
      installExplorationCandidate(next.candidate, pen: next.pen)
      explorationRound = nil
      singlePortraitStatus = nil
      return
    }
    explorationPen = pen
    explorationRound = nil
    singlePortraitStatus = nil
    beginExplorationIfNeeded(singleStep: true)
  }

  func previousPortrait() {
    guard !isShutdown, !isCapturing, !isProcessing, canGoBackExploration,
      let current = selectedCandidate, let pen = completedKey?.strokeStyle else { return }
    forwardPortraits.append((current, pen))
    while forwardPortraits.count > PortraitExplorationPolicy.maximumHistoryRounds
      || forwardPortraits.reduce(0, { $0 + PortraitExplorationPolicy.pointCount($1.candidate) }) > PortraitExplorationPolicy.maximumHistoryPoints {
      forwardPortraits.removeFirst()
    }
    goBackExploration()
    singlePortraitStatus = nil
  }

  func cancelPortraitStep() {
    cancelExplorationWork()
    singlePortraitStatus = nil
  }

  private func singlePortraitSnapshot(_ candidate: PortraitCandidate) -> PortraitExplorationRound {
    .init(id: UUID(), seed: nextExplorationSeed, variation: explorationVariation, center: candidate,
      slots: (0..<PortraitExplorationPolicy.slotCount).map { index in
        .init(index: index, candidate: index == PortraitExplorationPolicy.centerIndex ? candidate : nil,
          unavailableReason: index == PortraitExplorationPolicy.centerIndex ? nil : "Not requested")
      })
  }

  func setExplorationEnabled(_ enabled: Bool, strokeStyle: StrokeStyle) {
    guard !isShutdown else { return }
    isExplorationEnabled = enabled
    if enabled {
      renderIfConfigurationChanged(strokeStyle: strokeStyle)
      beginExplorationIfNeeded()
    } else { cancelExplorationWork() }
  }

  func chooseExplorationSlot(_ index: Int, roundID: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, currentProgram != nil else { return }
    guard let round = displayedExplorationRound, round.id == roundID,
      completedCandidate?.id == round.center.id,
      let candidate = round.slots.first(where: { $0.index == index })?.candidate, !isDeletedAttempt(candidate),
      let pen = explorationPen else { return }
    if isExploring && index == PortraitExplorationPolicy.centerIndex { return }
    recordExploration(round, action: .selected(index: index))
    rememberExploration(round)
    cancelExplorationWork()
    explorationRound = nil
    installExplorationCandidate(candidate, pen: pen)
    beginExplorationIfNeeded()
  }

  func resampleExploration(roundID: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, !isExploring, let round = explorationRound,
      round.id == roundID else { return }
    rememberExploration(round)
    if round.slots.contains(where: { $0.index != PortraitExplorationPolicy.centerIndex && ($0.candidate == nil || $0.isPrevious) }) {
      explorationSearch.direction = nil
    }
    explorationRound = nil
    beginExplorationIfNeeded()
  }

  func goBackExploration() {
    guard !isShutdown else { return }
    explorationHistory.removeAll { $0.round.slots.contains { $0.candidate.map { isDeletedAttempt($0) } == true } }
    guard let previous = explorationHistory.popLast(), let pose = previous.round.center.renderPose else { return }
    cancelExplorationWork()
    installCandidateSource(previous.round.center, pose: pose)
    explorationSearch = previous.search
    explorationPen = previous.pen
    installExplorationCandidate(previous.round.center, pen: previous.pen)
    explorationRound = previous.round
    recordExploration(previous.round, action: .back)
  }

  private func installExplorationCandidate(_ candidate: PortraitCandidate, pen: StrokeStyle) {
    guard !isDeletedAttempt(candidate) else { return }
    // Alternative algorithms are tied to their exact configuration. They may
    // finish independently, but cannot overwrite the selected recipe/program.
    installRecipe(candidate.recipe)
    let key = PortraitRenderCacheKey(photoID: candidate.photoID,
      configuration: renderConfiguration, strokeStyle: pen)
    requestedKey = key; completedKey = key; completedCandidate = candidate
    program = candidate.program; isProcessing = false; authoringError = nil
    cancelAuthoringWork()
    summary = "\(candidate.program.strokes.count) strokes"
  }

  /// A trajectory change owns only the authored drawing. Style reference jobs
  /// retain their independent context and their place in the same serial drain.
  private func cancelAuthoringWork() {
    pendingAlgorithms.removeAll { $0.exploration == nil && $0.comparisonID == nil }
    if let activeAlgorithm, activeAlgorithm.exploration == nil, activeAlgorithm.comparisonID == nil {
      activeAlgorithmWasCancelled = true
      renderWorker?.cancel()
    }
  }

  private func beginExplorationIfNeeded(singleStep: Bool = false) {
    guard (isExplorationEnabled || singleStep), !isShutdown, !isExploring, explorationRound == nil,
      PortraitStyle.authoringCases.contains(style),
      let center = completedCandidate, currentProgram != nil,
      let key = completedKey, let photo = selectedSource,
      photo.id == center.photoID else { return }
    if explorationRegion != nil, (center.recipe.vectorOptions.regionalAdjustments?.count ?? 0) >= 8 {
      authoringError = "This attempt already has eight regional adjustments. Revisit an earlier attempt to start another branch."
      return
    }
    let seed = nextExplorationSeed
    explorationStartedAt = ProcessInfo.processInfo.systemUptime
    Self.logger.info("Alternative round started seed=\(seed) region=\(self.explorationRegion?.rawValue ?? "Whole drawing", privacy: .public)")
    firstAlternativeSeconds = nil
    alternativePairSeconds = nil
    nextExplorationSeed &+= 1
    let builder = ExplorationBuilder(id: UUID(), seed: seed, center: center, photo: photo,
      pen: key.strokeStyle, variation: explorationVariation,
      recipes: explorationRecipes(around: center, seed: seed),
      previousChoices: !singleStep && explorationRegion == nil ? previousChoices(for: center) : [],
      region: explorationRegion, singleStep: singleStep,
      geometries: [geometry(for: center)],
      configurations: [PortraitExplorationPolicy.effectiveOptions(center.recipe.vectorOptions, center: center)],
      pointCount: PortraitExplorationPolicy.pointCount(center))
    explorationPen = key.strokeStyle
    buildingExploration = builder
    isExploring = true
    if singleStep {
      // Keep the historical receipt shape, but spend work on only one direction.
      let neighbor = Int(seed % UInt64(PortraitExplorationPolicy.neighborIndices.count))
      for other in PortraitExplorationPolicy.neighborIndices.indices where other != neighbor {
        let index = PortraitExplorationPolicy.neighborIndices[other]
        buildingExploration?.slots[index] = .init(index: index, candidate: nil, unavailableReason: "Not requested")
      }
      queueExplorationJob(roundID: builder.id, neighbor: neighbor, attempt: 0)
    } else {
      for neighbor in PortraitExplorationPolicy.neighborIndices.indices { queueExplorationJob(roundID: builder.id, neighbor: neighbor, attempt: 0) }
    }
    trimExplorationHistory()
    if !pendingAlgorithms.isEmpty { startWorkIfNeeded() }
  }

  private func explorationRecipes(around center: PortraitCandidate, seed: UInt64) -> [[PortraitStyleRecipe]] {
    guard let region = explorationRegion else {
      return PortraitExplorationPolicy.recipes(around: center, variation: explorationVariation,
        seed: seed, direction: nil)
    }
    return (0..<2).map { neighbor in
      (0..<PortraitExplorationPolicy.maximumAttemptsPerSlot).map { attempt in
        var vectors = center.recipe.vectorOptions
        var treatment = PortraitRegionalParameters()
        treatment.scope = region
        treatment.featureProtection = neighbor == 0 ? 0.85 : 0.35
        treatment.skinSuppression = neighbor == 0 ? 0.7 : 0.25
        treatment.contourEmphasis = neighbor == 0 ? 0.25 : 0.65
        treatment.angularity = neighbor == 0 ? 0 : 0.65
        treatment.shadowStrength = neighbor == 0 ? 0 : (attempt == 0 ? 0.5 : 0.8)
        if attempt > 0 { treatment.contourEmphasis = neighbor == 0 ? 0.5 : 0.9 }
        vectors.regionalAdjustments = (vectors.regionalAdjustments ?? []) + [treatment]
        return PortraitStyleRecipe(id: "region-\(region.rawValue)-\(seed)-\(neighbor)-\(attempt)",
          title: "\(region.rawValue) treatment", seed: seed, style: center.recipe.style,
          vectorOptions: vectors, analysisOptions: center.recipe.analysisOptions)
      }
    }
  }

  private func previousChoices(for center: PortraitCandidate) -> [PortraitCandidate] {
    var seen = Set<String>(), choices: [PortraitCandidate] = []
    let rejectedIdentities = sketches.rejectedProposalIdentities
    for snapshot in explorationHistory.reversed() {
      for candidate in [snapshot.round.center] + snapshot.round.slots.compactMap(\.candidate) {
        guard !isDeletedAttempt(candidate), !isRejectedAttempt(candidate, identities: rejectedIdentities),
          candidate.id != center.id, candidate.sourceSHA256 == center.sourceSHA256,
          candidate.rasterSHA256 == center.rasterSHA256, candidate.recipe.style == center.recipe.style,
          candidate.recipe.analysisOptions == center.recipe.analysisOptions,
          candidate.recipe.vectorOptions.materialContext == center.recipe.vectorOptions.materialContext,
          seen.insert(candidate.program.contentHash.description).inserted else { continue }
        choices.append(candidate)
        if choices.count == 6 { return choices }
      }
    }
    return choices
  }

  private func settleMissingOption(roundID: UUID, neighbor: Int, reason: String,
    failureKind: PortraitExplorationSlot.FailureKind = .searchExhausted) {
    guard var builder = buildingExploration, builder.id == roundID else { return }
    let index = PortraitExplorationPolicy.neighborIndices[neighbor]
    for candidate in builder.previousChoices {
      guard !isDeletedAttempt(candidate), !isRejectedAttempt(candidate, identities: sketches.rejectedProposalIdentities) else { continue }
      let footprint = geometry(for: candidate)
      let points = PortraitExplorationPolicy.pointCount(candidate)
      guard builder.pointCount + points <= PortraitExplorationPolicy.maximumRoundPoints,
        builder.geometries.allSatisfy({ footprint.isMeaningfullyDifferent(from: $0) }) else { continue }
      builder.geometries.append(footprint)
      builder.pointCount += points
      builder.slots[index] = .init(index: index, candidate: candidate, unavailableReason: nil, isPrevious: true)
      explorationPreviousOptionCount += 1
      buildingExploration = builder
      recordFirstAlternativeTiming()
      settleExplorationIfReady()
      return
    }
    builder.slots[index] = .init(index: index, candidate: nil, unavailableReason: reason, failureKind: failureKind)
    buildingExploration = builder
    settleExplorationIfReady()
  }

  private func queueExplorationJob(roundID: UUID, neighbor: Int, attempt: Int,
    recipeOverride: PortraitStyleRecipe? = nil, failureReason: String? = nil,
    failureKind: PortraitExplorationSlot.FailureKind = .searchExhausted) {
    guard var builder = buildingExploration, builder.id == roundID else { return }
    guard attempt < PortraitExplorationPolicy.maximumAttemptsPerSlot else {
      settleMissingOption(roundID: roundID, neighbor: neighbor,
        reason: failureReason ?? "No useful new change. Current is still available.", failureKind: failureKind)
      return
    }
    let recipe = recipeOverride ?? builder.recipes[neighbor][attempt]
    let proposalIdentity = try? PortraitAttemptRecord.proposalIdentity(
      sourceSHA256: builder.center.sourceSHA256, sourcePixelExtent: builder.photo.sourcePixelExtent,
      pose: builder.photo.pose, recipe: recipe, pen: builder.pen)
    if let proposalIdentity, sketches.rejectedProposalIdentities.contains(proposalIdentity) {
      rejected(.rejectedAttempt)
      queueExplorationJob(roundID: roundID, neighbor: neighbor, attempt: attempt + 1,
        failureReason: "This exact treatment was rejected. Try New options.")
      return
    }
    let effective = PortraitExplorationPolicy.effectiveOptions(recipe.vectorOptions, center: builder.center)
    guard builder.configurations.insert(effective).inserted else {
      rejected(.duplicateConfiguration)
      let recovery = builder.region != nil ? builder.recipes[neighbor][min(attempt + 1, PortraitExplorationPolicy.maximumAttemptsPerSlot - 1)] : PortraitExplorationPolicy.recoveryRecipe(around: builder.center, failed: recipe,
        rejection: .duplicateConfiguration, neighbor: neighbor, seed: builder.seed, variation: builder.variation,
        excluding: builder.configurations)
      queueExplorationJob(roundID: roundID, neighbor: neighbor, attempt: attempt + 1, recipeOverride: recovery,
        failureReason: failureReason, failureKind: failureKind)
      return
    }
    buildingExploration = builder
    let key = PortraitRenderCacheKey(photoID: builder.photo.id,
      configuration: .init(style: recipe.style, vectors: recipe.vectorOptions, analysis: recipe.analysisOptions),
      strokeStyle: builder.pen)
    let pending = PendingRender(revision: renderRevision, key: key,
      request: .init(data: builder.photo.data, pose: builder.photo.pose, style: recipe.style,
        options: recipe.analysisOptions, cachedRaster: builder.center.raster,
        strokeStyle: builder.pen, vectorOptions: recipe.vectorOptions,
        sourcePixelExtent: builder.photo.sourcePixelExtent),
      photo: builder.photo, recipe: recipe,
      lineage: .init(parentID: builder.center.id, parentProgramHash: builder.center.program.contentHash.description,
        parentRecipe: builder.center.recipe, ancestryGroupID: builder.center.lineage.ancestryGroupID),
      ownsSource: retainedEditSource?.id == builder.photo.id,
      exploration: .init(roundID: roundID, neighbor: neighbor, attempt: attempt))
    // Current-choice feedback precedes queued style thumbnails. Cache hits
    // retain the same serial offer order; an active worker is never interrupted.
    let insertion = pendingAlgorithms.firstIndex { $0.exploration == nil && $0.key != requestedKey }
      ?? pendingAlgorithms.endIndex
    pendingAlgorithms.insert(pending, at: insertion)
  }

  private func finishExplorationJob(_ job: ExplorationJob, pending: PendingRender,
    result: PortraitRenderResult?, error: Error?, preparedResult: PreparedRender? = nil) async {
    guard buildingExploration?.id == job.roundID else { return }
    let index = PortraitExplorationPolicy.neighborIndices[job.neighbor]
    var failure = error?.localizedDescription ?? "No useful new change. Current is still available."
    var rejection: PortraitExplorationPolicy.Rejection = error == nil ? .similarGeometry : .renderFailure
    if let drawingError = error as? PortraitDrawingError, case .noLines = drawingError { rejection = .noLines }
    if let result {
      do {
        // Source/raster hashing and preview occupancy are joined off the main
        // actor. The serial drain still owns publication and waits for settlement.
        let prepared: PreparedRender
        if let preparedResult { prepared = preparedResult }
        else { prepared = try await Task.detached(priority: .userInitiated) {
          try Self.prepare(result, pending: pending)
        }.value }
        guard var builder = buildingExploration, builder.id == job.roundID else { return }
        let candidate = prepared.candidate, footprint = prepared.geometry
        rememberGeometry(footprint, program: candidate.program)
        if !builder.singleStep { sketches.recordAttempt(candidate, record: prepared.attempt) }
        let points = PortraitExplorationPolicy.pointCount(candidate)
        if builder.pointCount + points > PortraitExplorationPolicy.maximumRoundPoints {
          failure = "Drawing exceeds the comparison detail budget."
          rejection = .detailBudget
        } else if builder.geometries.allSatisfy({ footprint.isMeaningfullyDifferent(from: $0) }) {
          if builder.singleStep { sketches.recordAttempt(candidate, record: prepared.attempt) }
          builder.geometries.append(footprint)
          builder.pointCount += points
          builder.slots[index] = .init(index: index, candidate: candidate, unavailableReason: nil)
          buildingExploration = builder
          recordFirstAlternativeTiming()
          trimExplorationHistory()
          settleExplorationIfReady()
          return
        }
      } catch { failure = error.localizedDescription; rejection = .renderFailure }
    }
    guard let builder = buildingExploration, builder.id == job.roundID else { return }
    rejected(rejection)
    if job.attempt + 1 == PortraitExplorationPolicy.maximumAttemptsPerSlot {
      settleMissingOption(roundID: job.roundID, neighbor: job.neighbor, reason: failure,
        failureKind: rejection == .renderFailure ? .generationFailed : .searchExhausted)
    } else {
      let recipe = builder.region != nil ? builder.recipes[job.neighbor][job.attempt + 1] : PortraitExplorationPolicy.recoveryRecipe(around: builder.center, failed: pending.recipe,
        rejection: rejection, neighbor: job.neighbor, seed: builder.seed, variation: builder.variation,
        excluding: builder.configurations)
      queueExplorationJob(roundID: job.roundID, neighbor: job.neighbor, attempt: job.attempt + 1, recipeOverride: recipe,
        failureReason: failure, failureKind: rejection == .renderFailure ? .generationFailed : .searchExhausted)
    }
  }

  private func explorationSnapshot(_ builder: ExplorationBuilder,
    unfinishedReason: String = "No visibly different option. Try New options.") -> PortraitExplorationRound {
    let slots = (0..<PortraitExplorationPolicy.slotCount).map { index in
      index == PortraitExplorationPolicy.centerIndex
        ? PortraitExplorationSlot(index: index, candidate: builder.center, unavailableReason: nil)
        : (builder.slots[index] ?? .init(index: index, candidate: nil, unavailableReason: unfinishedReason))
    }
    return PortraitExplorationRound(id: builder.id, seed: builder.seed,
      variation: builder.variation, center: builder.center, slots: slots)
  }

  private func recordFirstAlternativeTiming() {
    guard firstAlternativeSeconds == nil, let started = explorationStartedAt else { return }
    let elapsed = ProcessInfo.processInfo.systemUptime - started
    firstAlternativeSeconds = elapsed
    Self.logger.info("First alternative published elapsed_ms=\(elapsed * 1000)")
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

  private func isRejectedAttempt(_ candidate: PortraitCandidate, identities: Set<String>) -> Bool {
    guard let record = sketches.entries.first(where: { $0.id == candidate.id })?.attempt else { return false }
    return identities.contains(record.proposalIdentity)
  }

  private func settleExplorationIfReady() {
    guard let builder = buildingExploration,
      builder.slots.count == PortraitExplorationPolicy.neighborIndices.count else { return }
    let round = explorationSnapshot(builder)
    buildingExploration = nil
    explorationRound = round
    isExploring = false
    if let started = explorationStartedAt {
      let elapsed = ProcessInfo.processInfo.systemUptime - started
      let available = builder.slots.values.filter { $0.candidate != nil }.count
      alternativePairSeconds = available == 2 ? elapsed : nil
      Self.logger.info("Alternative round settled seed=\(builder.seed) ready=\(available) elapsed_ms=\(elapsed * 1000)")
    }
    recordExploration(round, action: .offered)
    if builder.singleStep {
      if let slot = round.slots.first(where: { $0.index != PortraitExplorationPolicy.centerIndex && $0.candidate != nil }),
        let candidate = slot.candidate {
        rememberExploration(round)
        recordExploration(round, action: .selected(index: slot.index))
        explorationRound = nil
        installExplorationCandidate(candidate, pen: builder.pen)
        singlePortraitStatus = nil
      } else {
        singlePortraitStatus = round.slots.first { $0.failureKind != nil }?.unavailableReason
          ?? "No useful new variation. Try Next again."
        explorationRound = nil
      }
    }
    trimExplorationHistory()
  }

  private func rememberExploration(_ round: PortraitExplorationRound) {
    guard let pen = explorationPen else { return }
    explorationHistory.append(.init(round: round, pen: pen, search: explorationSearch))
    trimExplorationHistory()
  }

  private func trimExplorationHistory() {
    func points() -> Int {
      var seen = Set<String>()
      let rounds = explorationHistory.map(\.round) + (explorationRound.map { [$0] } ?? [])
      return rounds.flatMap(\.slots).compactMap(\.candidate).reduce(0) { count, candidate in
        count + (seen.insert(candidate.id).inserted ? PortraitExplorationPolicy.pointCount(candidate) : 0)
      } + (buildingExploration?.pointCount ?? 0)
    }
    while explorationHistory.count > PortraitExplorationPolicy.maximumHistoryRounds
      || (!explorationHistory.isEmpty && points() > PortraitExplorationPolicy.maximumHistoryPoints) {
      explorationHistory.removeFirst()
    }
  }

  private func recordExploration(_ round: PortraitExplorationRound, action: PortraitExplorationRecord.Action) {
    explorationTrace.append(.init(round: round, action: action,
      traceSessionID: explorationTraceSessionID, sequence: explorationTraceSequence))
    explorationTraceSequence &+= 1
    if explorationTrace.count > PortraitExplorationPolicy.maximumRecords {
      explorationTrace.removeFirst(explorationTrace.count - PortraitExplorationPolicy.maximumRecords)
    }
  }

  private func explorationRecords(for candidate: PortraitCandidate) -> [PortraitExplorationRecord]? {
    let matching = explorationTrace.filter { $0.sourceSHA256 == candidate.sourceSHA256 }
    guard matching.contains(where: { $0.offers.contains(where: { $0.candidateID == candidate.id }) }) else { return nil }
    return matching
  }

  private func cancelExplorationWork() {
    buildingExploration = nil
    isExploring = false
    pendingAlgorithms.removeAll { $0.exploration != nil }
    if activeAlgorithm?.exploration != nil {
      activeAlgorithmWasCancelled = true
      renderWorker?.cancel()
    }
  }

  private func invalidateExploration() {
    forwardPortraits = []
    singlePortraitStatus = nil
    cancelExplorationWork()
    explorationRound = nil
    explorationHistory = []
    explorationSearch = PortraitExplorationSearchState()
  }


  private func comparisonContextIsCurrent(_ context: ComparisonContext) -> Bool {
    context.key.photoID == selectedPhotoID && context.key.pose == selectedSource?.pose
      && context.key.analysis == options && context.key.material == vectorOptions.materialContext
  }

  private func establishComparisonContext(photo: PortraitPhoto, pen: StrokeStyle,
    lineage: PortraitCandidateLineage?) {
    let key = ComparisonContextKey(photoID: photo.id, pose: photo.pose, analysis: options,
      material: vectorOptions.materialContext, pen: pen)
    guard comparisonContext?.key != key else { return }
    comparisonContext = .init(id: UUID(), key: key, vectors: vectorOptions.bounded, lineage: lineage)
    algorithmResults = []
    pendingAlgorithms.removeAll { $0.comparisonID != nil }
    if activeAlgorithm?.comparisonID != nil {
      activeAlgorithmWasCancelled = true
      renderWorker?.cancel()
    }
  }

  private func workIsApplicable(_ pending: PendingRender) -> Bool {
    guard !isShutdown, pending.key.photoID == selectedPhotoID,
      pending.ownsSource || recentPhotos.contains(where: { $0.id == pending.key.photoID }) else { return false }
    if let id = pending.comparisonID {
      guard let context = comparisonContext, id == context.id,
        comparisonContextIsCurrent(context) else { return false }
      return isStyleComparisonExpanded
    }
    return pending.revision == renderRevision
  }

  /// Folding cancels only unfinished style-reference demand. The selected drawing
  /// and completed reference objects retain their own identities.
  func setStyleComparisonExpanded(_ expanded: Bool, strokeStyle: StrokeStyle) {
    guard !isShutdown, expanded != isStyleComparisonExpanded else { return }
    isStyleComparisonExpanded = expanded
    if expanded {
      renderIfNeeded(strokeStyle: strokeStyle)
      if let photo = selectedSource, requestedKey != nil {
        if comparisonContext == nil {
          let candidate = selectedCandidate
          establishComparisonContext(photo: photo, pen: strokeStyle, lineage: candidate?.lineage)
          if let candidate, completedKey?.strokeStyle == strokeStyle { algorithmResults = [candidate] }
        }
        queueAlgorithmComparison(photo: photo, strokeStyle: strokeStyle, exactRaster: nil, lineage: nil)
      }
    } else {
      pendingAlgorithms.removeAll { $0.comparisonID != nil }
      if let activeAlgorithm, activeAlgorithm.comparisonID != nil {
        activeAlgorithmWasCancelled = true
        renderWorker?.cancel()
      }
      updateComparisonProgress()
    }
  }

  private func updateComparisonProgress() {
    guard let context = comparisonContext else { isComparingAlgorithms = false; return }
    isComparingAlgorithms = isStyleComparisonExpanded && (
      pendingAlgorithms.contains { $0.comparisonID == context.id && workIsApplicable($0) }
        || (activeAlgorithm.map { $0.comparisonID == context.id && workIsApplicable($0) } == true
          && !activeAlgorithmWasCancelled))
  }

  private func queueAlgorithmComparison(photo: PortraitPhoto, strokeStyle: StrokeStyle,
    exactRaster: PortraitRaster?, lineage: PortraitCandidateLineage?, includeSelected: Bool = false) {
    guard let context = comparisonContext, comparisonContextIsCurrent(context),
      context.key.pen == strokeStyle else { return }
    func enqueue(_ algorithm: PortraitStyle, vectors: PortraitVectorOptions,
      lineage: PortraitCandidateLineage?, comparisonID: UUID?) {
      let recipe = PortraitStyleRecipe(id: "algorithm-\(algorithm.rawValue)",
        title: comparisonID == nil ? (recipeTitle ?? algorithm.rawValue) : algorithm.rawValue, seed: 0, style: algorithm,
        vectorOptions: vectors, analysisOptions: context.key.analysis)
      let key = PortraitRenderCacheKey(photoID: photo.id,
        configuration: .init(style: algorithm, vectors: vectors, analysis: recipe.analysisOptions),
        strokeStyle: strokeStyle)
      if comparisonID != nil, algorithmResults.contains(where: { algorithmKey(for: $0) == key }) { return }
      func satisfiesRequest(_ pending: PendingRender) -> Bool {
        pending.key == key && workIsApplicable(pending) && pending.lineage == lineage
          && (comparisonID != nil || pending.comparisonID == nil)
      }
      if pendingAlgorithms.contains(where: satisfiesRequest)
        || (activeAlgorithm.map(satisfiesRequest) == true
          && !activeAlgorithmWasCancelled) { return }
      let pending = PendingRender(revision: renderRevision, key: key,
        request: .init(data: photo.data, pose: photo.pose, style: algorithm,
          options: recipe.analysisOptions, cachedRaster: exactRaster.flatMap { raster in
            PortraitImageAnalyzer.cachedRasterIsCompatible(raster, with: algorithm) ? raster : nil
          }, strokeStyle: strokeStyle, vectorOptions: vectors, sourcePixelExtent: photo.sourcePixelExtent),
        photo: photo, recipe: recipe, lineage: lineage,
        ownsSource: retainedEditSource?.id == photo.id, comparisonID: comparisonID)
      if comparisonID == nil { pendingAlgorithms.insert(pending, at: 0) }
      else { pendingAlgorithms.append(pending) }
    }
    // Selected authoring can reproduce a retained legacy style. Automatically
    // offered reference tiles are limited to current authoring algorithms.
    if includeSelected { enqueue(style, vectors: vectorOptions.bounded, lineage: lineage, comparisonID: nil) }
    if isStyleComparisonExpanded {
      for algorithm in PortraitStyle.authoringCases {
        enqueue(algorithm, vectors: context.vectors, lineage: context.lineage, comparisonID: context.id)
      }
    }
    updateComparisonProgress()
    if !pendingAlgorithms.isEmpty { startWorkIfNeeded() }
  }

  private func publishAlgorithm(_ prepared: PreparedRender, pending: PendingRender) {
    let candidate = prepared.candidate
    sketches.recordAttempt(candidate, record: prepared.attempt)
    rememberGeometry(prepared.geometry, program: candidate.program)
    if let context = comparisonContext, comparisonContextIsCurrent(context),
      pending.key.strokeStyle == context.key.pen,
      candidate.recipe.vectorOptions.bounded == context.vectors, pending.lineage == context.lineage,
      !algorithmResults.contains(where: { $0.recipe.style == candidate.recipe.style }) {
      algorithmResults.append(candidate)
      algorithmResults.sort {
        PortraitStyle.allCases.firstIndex(of: $0.recipe.style)!
          < PortraitStyle.allCases.firstIndex(of: $1.recipe.style)!
      }
    }
    if pending.comparisonID == nil, pending.revision == renderRevision, pending.key == requestedKey {
      completedCandidate = candidate
      completedKey = pending.key
      program = prepared.result.program
      summary = "\(candidate.program.strokes.count) strokes"
      isProcessing = false
      beginExplorationIfNeeded()
    }
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
    if activeAlgorithm?.comparisonID != nil {
      activeAlgorithmWasCancelled = true
      renderWorker?.cancel()
    }
    program = nil
    completedKey = nil
    requestedKey = nil
    guard let photo = selectedSource else {
      comparisonContext = nil
      algorithmResults = []
      pendingAlgorithms = []
      activeAlgorithmWasCancelled = true
      renderWorker?.cancel()
      completedCandidate = nil
      isComparingAlgorithms = false
      isProcessing = false
      summary = "Capture a portrait or choose a photo."
      return
    }
    requestedKey = .init(photoID: photo.id, configuration: renderConfiguration, strokeStyle: strokeStyle)
    isProcessing = true
    let ancestor = parent ?? completedCandidate.flatMap { $0.photoID == photo.id ? $0 : nil }
    let lineage = ancestor.map { PortraitCandidateLineage(parentID: $0.id,
      parentProgramHash: $0.program.contentHash.description, parentRecipe: $0.recipe,
      ancestryGroupID: $0.lineage.ancestryGroupID) }
    establishComparisonContext(photo: photo, pen: strokeStyle, lineage: lineage)
    queueAlgorithmComparison(photo: photo, strokeStyle: strokeStyle,
      exactRaster: exactRaster, lineage: lineage, includeSelected: true)
  }

  private func drainRenders() async {
    while pendingAcquisition == nil, !isShutdown {
      guard !pendingAlgorithms.isEmpty else { break }
      let pending = pendingAlgorithms.removeFirst()
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
      let roundID = pending.exploration?.roundID.uuidString ?? "selected-or-style"
      Self.logger.info("Render started source=\(pending.photo.id.uuidString, privacy: .public) round=\(roundID, privacy: .public) revision=\(pending.revision) style=\(pending.recipe.style.rawValue, privacy: .public) queue_ms=\(queueMS) result_cache=\(cachedResult != nil) source_cache=\(request.preparedSource != nil) raster_cache=\(request.cachedRaster != nil)")
      let worker = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let result: PortraitRenderResult
        if let cachedResult { result = cachedResult }
        else { result = try await renderer.render(request) }
        return try Self.prepare(result, pending: pending)
      }
      renderWorker = worker
      activeAlgorithm = pending
      activeAlgorithmWasCancelled = false
      updateComparisonProgress()
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
        activeAlgorithm = nil
        activeAlgorithmWasCancelled = false
        updateComparisonProgress()
      }
      do {
        let prepared = try await worker.value
        let result = prepared.result
        guard !activeAlgorithmWasCancelled, workIsApplicable(pending) else { continue }
        let publicationStarted = ProcessInfo.processInfo.systemUptime
        cache.insert(result, for: pending.key)
        if let job = pending.exploration {
          await finishExplorationJob(job, pending: pending, result: result, error: nil, preparedResult: prepared)
        } else {
          publishAlgorithm(prepared, pending: pending)
        }
        let stages = cachedResult == nil ? result.timings : nil
        let publicationMS = (ProcessInfo.processInfo.systemUptime - publicationStarted) * 1000
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - pending.queuedAt) * 1000
        Self.logger.info("Render published source=\(pending.photo.id.uuidString, privacy: .public) round=\(roundID, privacy: .public) revision=\(pending.revision) source_ms=\(stages?.sourceMS ?? 0) crop_ms=\(stages?.cropMS ?? 0) flow_ms=\(stages?.flowMS ?? 0) vector_ms=\(stages?.vectorMS ?? 0) preparation_ms=\(prepared.preparationSeconds * 1000) publication_ms=\(publicationMS) total_ms=\(elapsedMS)")
      } catch {
        guard !activeAlgorithmWasCancelled, workIsApplicable(pending) else { continue }
        if let failure = error as? PortraitPreparedRenderFailure {
          cache.insertSourcePreparation(failure.preparedSource, for: pending.photo.id)
        }
        let renderError = (error as? PortraitPreparedRenderFailure)?.underlyingError ?? error
        let elapsedMS = (ProcessInfo.processInfo.systemUptime - pending.queuedAt) * 1000
        Self.logger.info("Render failed source=\(pending.photo.id.uuidString, privacy: .public) round=\(roundID, privacy: .public) revision=\(pending.revision) total_ms=\(elapsedMS) reason=\(renderError.localizedDescription, privacy: .public)")
        if let job = pending.exploration {
          await finishExplorationJob(job, pending: pending, result: nil, error: renderError)
          continue
        }
        if pending.comparisonID == nil, pending.revision == renderRevision, pending.key == requestedKey {
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
    if let round = displayedExplorationRound { rememberExploration(round) }
    else if let current = selectedCandidate, current.id != candidate.id, let pen = completedKey?.strokeStyle {
      explorationPen = pen
      rememberExploration(singlePortraitSnapshot(current))
    }
    cancelExplorationWork()
    renderRevision &+= 1
    pendingAlgorithms = []
    activeAlgorithmWasCancelled = true
    renderWorker?.cancel()
    comparisonContext = nil
    algorithmResults = []
    isComparingAlgorithms = false
    explorationRound = nil
    installCandidateSource(candidate, pose: pose)
    let pen = candidate.program.strokes.first?.style ?? strokeStyle
    installExplorationCandidate(candidate, pen: pen)
    if candidate.recipe.style != .contours { studioMode = .explorer }
    lastHistoryNavigationSeconds = ProcessInfo.processInfo.systemUptime - started
    Self.logger.info("History selection installed elapsed_ms=\((self.lastHistoryNavigationSeconds ?? 0) * 1000) render_count=\(self.renderDiagnostics.startedWorkerCount)")
  }

  func exploreSelection(strokeStyle: StrokeStyle) {
    if let round = displayedExplorationRound { rememberExploration(round) }
    cancelExplorationWork()
    explorationRound = nil
    beginExplorationIfNeeded()
  }

  func clearUnkeptHistory() {
    forwardPortraits = []
    cancelExplorationWork()
    explorationHistory = []
    explorationRound = nil
    let displayedID = selectedCandidate?.id
      ?? (completedCandidate?.photoID == selectedPhotoID ? completedCandidate?.id : nil)
    sketches.clearUnkeptHistory(preserving: displayedID)
    algorithmResults.removeAll { isDeletedAttempt($0) }
  }

  func deleteAttempt(_ id: String) {
    forwardPortraits.removeAll { $0.candidate.id == id }
    // A deleted offered object loses its selection capability immediately. Stop
    // the current offer so a late worker cannot refill its deleted slot.
    let round = displayedExplorationRound
    if round?.slots.contains(where: { $0.candidate?.id == id }) == true {
      cancelExplorationWork()
      if let round, round.center.id != id {
        explorationRound = .init(id: UUID(), seed: round.seed, variation: round.variation,
          center: round.center, slots: round.slots.map { slot in
            slot.candidate?.id == id
              ? .init(index: slot.index, candidate: nil, unavailableReason: "Attempt deleted") : slot
          })
      } else { explorationRound = nil }
    }
    if completedCandidate?.id == id {
      cancelExplorationWork(); explorationRound = nil
      completedCandidate = nil; completedKey = nil; requestedKey = nil; program = nil
    }
    explorationHistory.removeAll { $0.round.slots.contains { $0.candidate?.id == id } }
    algorithmResults.removeAll { $0.id == id }
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

  func applyPrototype(_ prototype: PortraitPrototypeRecipe, strokeStyle: StrokeStyle) {
    guard !isShutdown else { return }
    let parent = selectedCandidate
    let recipe = prototype.recipe(analysisOptions: options)
    installRecipe(recipe)
    if let parent {
      vectorOptions.materialContext = parent.recipe.vectorOptions.materialContext
    }
    render(strokeStyle: strokeStyle, parent: parent)
  }

  func saveStyle(name: String) {
    guard let candidate = selectedCandidate else { return }
    sketches.saveStyle(name: name, recipe: candidate.recipe)
  }

  func applySavedStyle(_ saved: PortraitSavedStyle, strokeStyle: StrokeStyle) {
    let parent = selectedCandidate
    installRecipe(saved.recipe)
    if saved.recipe.style != .contours { studioMode = .explorer }
    render(strokeStyle: strokeStyle, parent: parent)
  }

  func keepSelection() -> String? {
    guard let candidate = selectedCandidate else { return "Wait for the selected drawing to finish rendering." }
    let selection = sketches.selectedID
    defer { sketches.selectedID = selection }
    return sketches.retain(candidate: candidate, reason: .shortlisted, exploration: explorationRecords(for: candidate))
  }

  /// Capture the immutable candidate before crossing an asynchronous acceptance
  /// boundary. A failed camera/program/Fit action cannot qualify the drawing.
  func acceptProjection(_ candidate: PortraitCandidate,
    perform: () async -> String?) async -> String? {
    guard !isDeletedAttempt(candidate) else { return "This attempt was deleted. Select a retained attempt before handoff." }
    let exploration = explorationRecords(for: candidate)
    if let error = await perform() { return error }
    guard !isDeletedAttempt(candidate) else { return "The accepted attempt was deleted while handoff was pending." }
    projectedCandidate = candidate
    let selection = sketches.selectedID
    defer { sketches.selectedID = selection }
    return sketches.retain(candidate: candidate, reason: .projectionAccepted(acceptanceID: UUID()), exploration: exploration)
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
    pendingAlgorithms = []
    isComparingAlgorithms = false
    requestedKey = currentProgram == nil ? nil : completedKey
    isProcessing = false
    // Reference work deliberately outlives authoring revisions. A global stop
    // must invalidate its publication and reuse ownership explicitly as well.
    activeAlgorithmWasCancelled = true
    renderWorker?.cancel()
    await workTask?.value
  }

  func awaitRendering() async { await workTask?.value }

  func awaitExploration() async { await workTask?.value }

  func cameraDiagnostics() async -> CameraCaptureSnapshot { await camera.snapshot() }

  func shutdown() async {
    isShutdown = true
    await cancelRendering()
    await stopCamera()
    await sketches.awaitPersistence()
  }
}
