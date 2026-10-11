import PortraitArtists
import PortraitLibrary
import Foundation
import Observation
import OSLog
import PlotterModel
import PlotterRuntime

package struct PortraitRenderDiagnostics: Equatable, Sendable {
  package var requestedWorkCount = 0
  package var cancellationCount = 0
  package var startedWorkerCount = 0
  package var settledWorkerCount = 0
  package var activeWorkerCount = 0
  package var maximumConcurrentWorkerCount = 0

  package init(
    requestedWorkCount: Int = 0,
    cancellationCount: Int = 0,
    startedWorkerCount: Int = 0,
    settledWorkerCount: Int = 0,
    activeWorkerCount: Int = 0,
    maximumConcurrentWorkerCount: Int = 0
  ) {
    self.requestedWorkCount = requestedWorkCount
    self.cancellationCount = cancellationCount
    self.startedWorkerCount = startedWorkerCount
    self.settledWorkerCount = settledWorkerCount
    self.activeWorkerCount = activeWorkerCount
    self.maximumConcurrentWorkerCount = maximumConcurrentWorkerCount
  }
}

@Observable @MainActor
package final class PortraitCameraPreviewModel {
  package init() {}

  package var frame: DisplayedFrame?
}

@Observable @MainActor
package final class PortraitStudioModel {
  private static let logger = Logger(subsystem: "com.adaptiveplotter.app", category: "portrait-browser")
  package var pose: PortraitPose = .front {
    didSet {
      if pose != oldValue {
        invalidateExploration()
        selectedPhotoID = recentPhotos.last(where: { $0.pose == pose })?.id
      }
    }
  }
  package var style: PortraitStyle = .contours
  package private(set) var singlePortraitStatus: String?
  private var forwardPortraits: [(candidate: PortraitCandidate, pen: StrokeStyle)] = []
  package var canGoForwardPortrait: Bool { forwardPortraits.contains { !isDeletedAttempt($0.candidate) } }
  package var options = PortraitAnalysisOptions()
  package var vectorOptions = PortraitVectorOptions.nativeDefaults(for: .contours)
  @ObservationIgnored private var vectorOptionsByStyle: [PortraitStyle: PortraitVectorOptions] = [:]
  package let sketches: PortraitSketchCollection
  package private(set) var completedCandidate: PortraitCandidate?
  @ObservationIgnored private var pendingRenders: [PendingRender] = []
  @ObservationIgnored private var activeRender: PendingRender?
  @ObservationIgnored private var activeRenderWasCancelled = false
  /// Exact last successful projection; gallery browsing cannot replace this association.
  package private(set) var projectedCandidate: PortraitCandidate?
  package private(set) var projectedDrawing: SavedDrawing?
  private var recipeTitle: String?
  package var selectedCandidate: PortraitCandidate? {
    if let candidate = sketches.selected?.portraitCandidate {
      return isDeletedAttempt(candidate) ? nil : candidate
    }
    // currentProgram already checks configuration and deletion applicability.
    return currentProgram == nil ? nil : completedCandidate
  }
  package var renderConfiguration: PortraitRenderConfiguration {
    .init(style: style, vectors: vectorOptions.bounded, analysis: options)
  }
  package var framePosition: String {
    guard let index = recentPhotos.firstIndex(where: { $0.id == selectedPhotoID }) else { return selectedSource == nil ? "No frame" : "Retained source" }
    return "Frame \(index + 1) / \(recentPhotos.count)"
  }
  /// The completed drawing is usable only for its exact current selection.
  package var currentProgram: DrawingProgram? {
    guard completedKey?.photoID == selectedPhotoID,
      completedKey?.configuration == renderConfiguration,
      let completedCandidate, !isDeletedAttempt(completedCandidate) else { return nil }
    return program
  }
  @ObservationIgnored private var cache = PortraitRenderCache()
  @ObservationIgnored private var requestedKey: PortraitRenderCacheKey?
  @ObservationIgnored private var completedKey: PortraitRenderCacheKey?
  @ObservationIgnored package private(set) var renderCacheHits = 0
  package private(set) var recentPhotos: [PortraitPhoto] = []
  package private(set) var selectedPhotoID: UUID?
  @ObservationIgnored private var retainedEditSource: PortraitPhoto?
  @ObservationIgnored private var photoSelectionTask: Task<Void, Never>?
  @ObservationIgnored private var photoSelectionRevision: UInt64 = 0
  package private(set) var loadingPhotoID: UUID?
  @ObservationIgnored private var historyStepTask: Task<Void, Never>?
  @ObservationIgnored private var historyStepRevision: UInt64 = 0
  private var selectedSource: PortraitPhoto? {
    recentPhotos.first(where: { $0.id == selectedPhotoID })
      ?? (retainedEditSource?.id == selectedPhotoID ? retainedEditSource : nil)
      ?? sketches.sourcePhotos.first(where: { $0.id == selectedPhotoID })
  }
  /// Retained source frames remain discoverable after the recent-photo cache expires.
  package var browsablePhotos: [PortraitPhoto] {
    var seen = Set(recentPhotos.map(\.id))
    let retainedSources = sketches.sourcePhotos.reversed().filter { seen.insert($0.id).inserted }
    return recentPhotos + retainedSources + sketches.entries.reversed().compactMap { entry in
      let candidate = entry.candidate
      guard seen.insert(candidate.photoID).inserted, let pose = candidate.renderPose else { return nil }
      return PortraitPhoto(id: candidate.photoID, data: candidate.sourceData,
        label: "Retained frame", capturedAt: candidate.createdAt, frameID: nil,
        captureNanoseconds: nil, pose: pose, sourcePixelExtent: candidate.sourcePixelExtent,
        captureSessionID: candidate.captureSessionID)
    }
  }
  package var selectedPhoto: Data? { selectedCandidate?.sourceData ?? selectedSource?.data }
  package var photoListItems: [PortraitPhotoListItem] {
    var seen = Set<UUID>()
    return recentPhotos.reversed().map { PortraitPhotoListItem(id: $0.id, label: $0.label) }
      .filter { seen.insert($0.id).inserted }
      + sketches.photoReferences.compactMap {
        seen.insert($0.id).inserted ? PortraitPhotoListItem(id: $0.id, label: $0.label) : nil
      }
  }

  package func photoForBrowsing(_ id: UUID) async throws -> PortraitPhoto {
    if let photo = recentPhotos.first(where: { $0.id == id }) { return photo }
    return try await sketches.photoForBrowsing(id)
  }
  package var retainedPhotoBytes: Int { recentPhotos.reduce(0) { $0 + $1.data.count } }
  package let captureDuration: Double = 0.8
  package private(set) var isCapturing = false
  package private(set) var captureProgress = 0.0
  package private(set) var screenIlluminationActive = false
  package private(set) var captureSummary: String?
  package private(set) var program: DrawingProgram?
  package private(set) var summary = "Capture a portrait or choose a photo."
  package private(set) var authoringError: String?
  package private(set) var isProcessing = false
  package private(set) var devices: [CameraDevice] = []
  package var selectedDeviceID: CameraDeviceID?
  package private(set) var cameraIsRunning = false
  package private(set) var cameraIsStarting = false
  package private(set) var cameraStatus: String?
  package let preview = PortraitCameraPreviewModel()
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
  @ObservationIgnored package private(set) var acquisitionDiagnostics = PortraitRenderDiagnostics()
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
      PortraitExplorationPolicy.VisibleGeometry(candidate.program)
        .isMeaningfullyDifferent(from: PortraitExplorationPolicy.VisibleGeometry($0))
    } ?? true
    let attempt = try PortraitAttemptRecord.prepare(candidate: candidate, pen: pending.key.strokeStyle)
    return PreparedRender(result: result, candidate: candidate, isDifferent: isDifferent, attempt: attempt,
      preparationSeconds: ProcessInfo.processInfo.systemUptime - started)
  }

  @ObservationIgnored private var renderRevision: UInt64 = 0
  @ObservationIgnored private var isShutdown = false
  @ObservationIgnored package private(set) var renderDiagnostics = PortraitRenderDiagnostics()
  @ObservationIgnored package private(set) var workDiagnostics = PortraitRenderDiagnostics()

  package init(
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

  package func capture(strokeStyle: StrokeStyle) async {
    await acquirePhoto(file: nil, strokeStyle: strokeStyle)
  }

  package func importPhoto(_ url: URL, strokeStyle: StrokeStyle) async {
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
    vectorOptionsByStyle[style] = vectorOptions
    style = .contours
    vectorOptions = vectorOptionsByStyle[style] ?? .nativeDefaults(for: style)
    vectorOptions.materialContext = material
  }

  package func setPhoto(_ data: Data, for pose: PortraitPose, strokeStyle: StrokeStyle) {
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
    let photo = PortraitPhoto(id: UUID(), data: sample.data, label: sample.label,
      capturedAt: Date(), frameID: sample.frameID, captureNanoseconds: sample.captureNanoseconds,
      pose: pose, sourcePixelExtent: sample.sourcePixelExtent, captureSessionID: sessionID,
      selectionProvenance: sample.selectionProvenance)
    sketches.retainSourcePhoto(photo)
    guard photoRetention.maximumCount > 0, sample.data.count <= photoRetention.maximumBytes else {
      summary = "The original photo is retained in Photos; it exceeds the recent-photo memory limit."
      authoringError = summary
      return false
    }
    recentPhotos.append(photo)
    selectedPhotoID = photo.id
    while recentPhotos.count > photoRetention.maximumCount || retainedPhotoBytes > photoRetention.maximumBytes {
      cache.remove(photoID: recentPhotos.removeFirst().id)
    }
    return true
  }

  package func selectPhoto(_ id: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown else { return }
    photoSelectionRevision &+= 1
    photoSelectionTask?.cancel()
    loadingPhotoID = nil
    if let photo = browsablePhotos.first(where: { $0.id == id }) {
      installPhotoSelection(photo, strokeStyle: strokeStyle)
      return
    }
    guard sketches.photoReferences.contains(where: { $0.id == id }) else { return }
    let revision = photoSelectionRevision
    let priorSelection = selectedPhotoID
    let priorRender = renderRevision
    let priorAcquisition = acquisitionRevision
    loadingPhotoID = id
    photoSelectionTask = Task {
      defer { if revision == photoSelectionRevision { loadingPhotoID = nil; photoSelectionTask = nil } }
      do {
        if let candidate = try await sketches.matchingCandidateForBrowsing(photoID: id,
          configuration: renderConfiguration, strokeStyle: strokeStyle), let pose = candidate.renderPose {
          guard !isShutdown, !Task.isCancelled, revision == photoSelectionRevision,
            selectedPhotoID == priorSelection, renderRevision == priorRender,
            acquisitionRevision == priorAcquisition else { return }
          installInspectedCandidate(candidate, pose: pose, strokeStyle: strokeStyle)
          return
        }
        let photo = try await photoForBrowsing(id)
        guard !isShutdown, !Task.isCancelled, revision == photoSelectionRevision,
          selectedPhotoID == priorSelection, renderRevision == priorRender,
          acquisitionRevision == priorAcquisition else { return }
        installPhotoSelection(photo, strokeStyle: strokeStyle)
      } catch {
        if !Task.isCancelled, revision == photoSelectionRevision { authoringError = error.localizedDescription }
      }
    }
  }

  package func awaitPhotoSelection() async { await photoSelectionTask?.value }

  private func installPhotoSelection(_ photo: PortraitPhoto, strokeStyle: StrokeStyle) {
    let id = photo.id
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

  package var canRemoveSelectedRecentPhoto: Bool { recentPhotos.contains { $0.id == selectedPhotoID } }

  package func deleteRetainedSource(_ photoID: UUID, strokeStyle: StrokeStyle) {
    if loadingPhotoID == photoID {
      photoSelectionRevision &+= 1; photoSelectionTask?.cancel(); photoSelectionTask = nil
      loadingPhotoID = nil
    }
    sketches.deleteSource(photoID: photoID)
    recentPhotos.removeAll { $0.id == photoID }
    cache.remove(photoID: photoID)
    explorationHistory.removeAll { $0.candidate.photoID == photoID }
    forwardPortraits.removeAll { $0.candidate.photoID == photoID }
    pendingRenders.removeAll { $0.photo.id == photoID }
    if let activeRender, activeRender.photo.id == photoID {
      activeRenderWasCancelled = true; renderWorker?.cancel()
    }
    if projectedDrawing?.sourcePhotoID == photoID {
      projectedDrawing = nil; projectedCandidate = nil
    }
    if selectedPhotoID == photoID {
      cancelExplorationWork()
      renderRevision &+= 1; pendingRenders = []; activeRenderWasCancelled = true; renderWorker?.cancel()
      completedCandidate = nil; completedKey = nil; requestedKey = nil; program = nil
      retainedEditSource = nil; selectedPhotoID = nil; isProcessing = false
    }
  }

  package func removePhoto(_ id: UUID, strokeStyle: StrokeStyle) {
    guard !isShutdown, recentPhotos.contains(where: { $0.id == id }) else { return }
    recentPhotos.removeAll { $0.id == id }
    cache.remove(photoID: id)
    if selectedPhotoID == id {
      selectedPhotoID = recentPhotos.last?.id
      render(strokeStyle: strokeStyle)
    }
  }

  package func removeCaptureSession(_ id: UUID, strokeStyle: StrokeStyle) {
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

  package func removeSelectedBurst(strokeStyle: StrokeStyle) {
    guard let sessionID = selectedSource?.captureSessionID else { return }
    removeCaptureSession(sessionID, strokeStyle: strokeStyle)
  }

  package private(set) var firstAlternativeSeconds: Double?
  package private(set) var lastHistoryNavigationSeconds: Double?
  package var isExploring: Bool { explorationJob != nil }
  package var canGoBackExploration: Bool { explorationHistory.contains { !isDeletedAttempt($0.candidate) } }
  @ObservationIgnored private var nextExplorationSeed: UInt64
  private var explorationHistory: [(candidate: PortraitCandidate, pen: StrokeStyle)] = []
  private var explorationJob: ExplorationJob?
  package private(set) var explorationRejections: [String: Int] = [:]

  private struct ExplorationJob {
    let id = UUID()
    let seed: UInt64
    let center: PortraitCandidate
    let photo: PortraitPhoto
    let pen: StrokeStyle
    let backwards: Bool
    let startedAt = ProcessInfo.processInfo.systemUptime
    var attempt = 0
    var configurations: Set<PortraitVectorOptions>
  }

  /// Historical shared recipes display their effective authored values without
  /// rewriting their stored coordinates or applying material spacing floors.
  package var nativeVectorOptions: PortraitVectorOptions {
    vectorOptions.nativeOptions(rasterHeight: nativeRasterHeight)
  }

  package var canEditNativeParameters: Bool {
    vectorOptions.drawingParameters == nil || applicableNativeRaster != nil
  }

  private var applicableNativeRaster: PortraitRaster? {
    for candidate in [selectedCandidate, completedCandidate].compactMap({ $0 }) {
      if candidate.recipe.style == style, candidate.photoID == selectedPhotoID,
        candidate.recipe.analysisOptions == options {
        return candidate.raster
      }
    }
    return nil
  }

  private var nativeRasterHeight: Int {
    applicableNativeRaster?.height ?? PortraitImageAnalyzer.analysisMaximumDimension(for: style)
  }

  package func editNativeVectorOptions(_ edit: (inout PortraitVectorOptions) -> Void) {
    guard !isShutdown, !isCapturing, canEditNativeParameters else { return }
    var edited = nativeVectorOptions
    edit(&edited)
    edited.drawingParameters = nil
    cancelPortraitStep()
    forwardPortraits = []
    vectorOptions = edited.bounded
    vectorOptionsByStyle[style] = vectorOptions
    recipeTitle = nil
  }

  /// Each kernel restores its own tuning. Source framing and physical material
  /// remain shared; no Contour control is projected into Flow Edge parameters.
  package func selectStyle(_ selected: PortraitStyle, strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, selected != style,
      PortraitStyle.authoringCases.contains(selected) else { return }
    vectorOptionsByStyle[style] = vectorOptions
    var restored = vectorOptionsByStyle[selected] ?? .nativeDefaults(for: selected)
    restored.materialContext = vectorOptions.materialContext
    cancelPortraitStep()
    forwardPortraits = []
    style = selected
    vectorOptions = restored
    recipeTitle = nil
    if !sketches.historyLoadHasCompleted, let photoID = selectedPhotoID {
      photoSelectionRevision &+= 1; photoSelectionTask?.cancel()
      let revision = photoSelectionRevision, configuration = renderConfiguration
      photoSelectionTask = Task {
        defer { if revision == photoSelectionRevision { photoSelectionTask = nil } }
        do {
          let candidate = try await sketches.matchingCandidateForBrowsing(photoID: photoID,
            configuration: configuration, strokeStyle: strokeStyle)
          guard !isShutdown, !Task.isCancelled, revision == photoSelectionRevision,
            selectedPhotoID == photoID, renderConfiguration == configuration else { return }
          if let candidate, let pose = candidate.renderPose {
            installInspectedCandidate(candidate, pose: pose, strokeStyle: strokeStyle)
          } else { renderIfConfigurationChanged(strokeStyle: strokeStyle) }
        } catch {
          if !Task.isCancelled, revision == photoSelectionRevision { authoringError = error.localizedDescription }
        }
      }
    } else { renderIfConfigurationChanged(strokeStyle: strokeStyle) }
  }

  package func applyDetailPreset(_ preset: PortraitVectorPreset) {
    let tuning = preset.nativeOptions(for: style)
    editNativeVectorOptions {
      $0.contourLevels = tuning.contourLevels
      $0.minimumContourLength = tuning.minimumContourLength
      $0.simplificationTolerance = tuning.simplificationTolerance
      $0.hatchSpacing = tuning.hatchSpacing
      $0.tonalStrength = tuning.tonalStrength
      $0.smoothing = tuning.smoothing
      $0.sketchThreshold = tuning.sketchThreshold
    }
  }

  /// Named starting points in each renderer's recipe space.
  package func resetStyle(_ preset: PortraitStyle, strokeStyle: StrokeStyle) {
    guard !isShutdown, !isCapturing, PortraitStyle.authoringCases.contains(preset) else { return }
    vectorOptionsByStyle[style] = vectorOptions
    cancelPortraitStep()
    forwardPortraits = []
    var vectors = PortraitVectorOptions.nativeDefaults(for: preset)
    vectors.materialContext = vectorOptions.materialContext
    style = preset
    vectorOptions = vectors
    vectorOptionsByStyle[preset] = vectors
    recipeTitle = nil
    renderIfConfigurationChanged(strokeStyle: strokeStyle)
  }

  /// Retained navigation never renders. Either end can request a fresh sample.
  package func nextPortrait(strokeStyle: StrokeStyle) {
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
    if !sketches.historyLoadHasCompleted {
      guard historyStepTask == nil else { return }
      let revision = historyStepRevision
      singlePortraitStatus = "Loading retained preference history…"
      historyStepTask = Task {
        defer { if revision == historyStepRevision { historyStepTask = nil } }
        await sketches.load()
        guard !Task.isCancelled, !isShutdown, selectedCandidate?.id == current.id,
          completedKey?.strokeStyle == pen else { return }
        requestPortraitStep(current: current, pen: pen, backwards: backwards)
      }
      return
    }
    guard !isExploring, PortraitStyle.authoringCases.contains(style), let photo = selectedSource,
      photo.id == current.photoID else { return }
    let seed = nextExplorationSeed
    nextExplorationSeed &+= 1
    singlePortraitStatus = nil
    firstAlternativeSeconds = nil
    explorationJob = .init(seed: seed, center: current, photo: photo, pen: pen,
      backwards: backwards,
      configurations: [PortraitExplorationPolicy.effectiveOptions(current.recipe.vectorOptions, center: current)])
    queueExplorationJob()
    startWorkIfNeeded()
  }

  package func previousPortrait() {
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

  package func cancelPortraitStep() {
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
    else { recipe = PortraitExplorationPolicy.nativeRecipe(around: job.center, seed: job.seed) }
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
      explorationCenter: job.center.program))
  }

  private func retryExploration(_ recipe: PortraitStyleRecipe, rejection: PortraitExplorationPolicy.Rejection,
    failure: String) {
    guard var job = explorationJob else { return }
    explorationRejections[rejection.rawValue, default: 0] += 1
    job.attempt += 1
    explorationJob = job
    let recovery = job.attempt < PortraitExplorationPolicy.maximumAttemptsPerSlot
      ? PortraitExplorationPolicy.nativeRecoveryRecipe(around: job.center, failed: recipe,
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
    sketches.drawingWasDeleted(SavedDrawing(candidate: candidate))
  }

  private func cancelExplorationWork() {
    historyStepRevision &+= 1
    historyStepTask?.cancel()
    historyStepTask = nil
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

  package func render(strokeStyle: StrokeStyle, parent: PortraitCandidate? = nil,
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
  package func renderIfConfigurationChanged(strokeStyle: StrokeStyle) {
    if requestedKey?.photoID == selectedPhotoID,
      requestedKey?.configuration == renderConfiguration { return }
    renderIfNeeded(strokeStyle: strokeStyle)
  }

  package func renderIfNeeded(strokeStyle: StrokeStyle) {
    guard let selectedPhotoID else { return }
    let key = PortraitRenderCacheKey(photoID: selectedPhotoID,
      configuration: renderConfiguration, strokeStyle: strokeStyle)
    guard requestedKey != key else { return }
    sketches.selectedID = nil
    render(strokeStyle: strokeStyle)
  }

  private func installRecipe(_ recipe: PortraitStyleRecipe) {
    vectorOptionsByStyle[style] = vectorOptions
    recipeTitle = recipe.title
    style = recipe.style
    vectorOptions = recipe.vectorOptions
    vectorOptionsByStyle[style] = vectorOptions
    options = recipe.analysisOptions
    sketches.selectedID = nil
  }

  /// Applies an explicit profile at the accepted height to a new candidate.
  /// Exact source/head analysis survives, and old/rated candidates stay immutable.
  package func applyMaterial(_ profile: DrawingMaterialProfileRevision, drawingHeightMM: Double) async -> String? {
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

  package func movePhoto(by offset: Int, strokeStyle: StrokeStyle) {
    let photos = photoListItems
    guard !photos.isEmpty else { return }
    let current = photos.firstIndex(where: { $0.id == selectedPhotoID }) ?? 0
    let index = ((current + offset) % photos.count + photos.count) % photos.count
    sketches.selectedID = nil
    selectPhoto(photos[index].id, strokeStyle: strokeStyle)
  }

  package func loadPhotoBrowser() async { await sketches.loadPhotoBrowser() }

  package func feedback(for candidate: PortraitCandidate) -> PortraitAttemptFeedback {
    sketches.feedback(for: .init(candidateID: candidate.id, photoID: candidate.photoID))
  }

  package func toggleFeedback(_ value: PortraitAttemptFeedback, candidate: PortraitCandidate) {
    guard !sketches.drawingWasDeleted(SavedDrawing(candidate: candidate)) else { return }
    sketches.setFeedback(feedback(for: candidate) == value ? .unknown : value,
      for: .init(candidateID: candidate.id, photoID: candidate.photoID))
  }

  /// Install the retained payload directly. No portrait render or source analysis
  /// is scheduled by Back, a history click, or a feedback change.
  package func inspectAttempt(_ id: String, strokeStyle: StrokeStyle) {
    guard !isShutdown, let candidate = sketches.entries.first(where: { $0.id == id })?.candidate,
      let pose = candidate.renderPose else { return }
    installInspectedCandidate(candidate, pose: pose, strokeStyle: strokeStyle)
  }

  package func inspectDrawing(_ id: String, strokeStyle: StrokeStyle) async -> String? {
    do {
      let candidate = try await sketches.candidateForBrowsing(id)
      guard !isShutdown, !Task.isCancelled, !isDeletedAttempt(candidate), let pose = candidate.renderPose else {
        return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
      }
      installInspectedCandidate(candidate, pose: pose, strokeStyle: strokeStyle)
      return nil
    } catch { return error.localizedDescription }
  }

  package func inspectDrawing(_ identity: PortraitDrawingIdentity, strokeStyle: StrokeStyle) async -> String? {
    do {
      guard let candidate = try await sketches.drawingForBrowsing(identity).portraitCandidate else {
        return SavedDrawingBrowserError.notPortrait.localizedDescription
      }
      guard candidate.photoID == identity.photoID, !isShutdown, !Task.isCancelled,
        !isDeletedAttempt(candidate), let pose = candidate.renderPose else {
        return SavedDrawingBrowserError.drawingUnavailable.localizedDescription
      }
      installInspectedCandidate(candidate, pose: pose, strokeStyle: strokeStyle)
      return nil
    } catch { return error.localizedDescription }
  }

  private func installInspectedCandidate(_ candidate: PortraitCandidate, pose: PortraitPose, strokeStyle: StrokeStyle) {
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

  package func clearUnkeptHistory() {
    forwardPortraits = []
    cancelExplorationWork()
    explorationHistory = []
    let displayed = selectedCandidate
      ?? (completedCandidate?.photoID == selectedPhotoID ? completedCandidate : nil)
    if let displayed {
      sketches.clearUnkeptHistory(preserving: .init(candidateID: displayed.id, photoID: displayed.photoID))
    } else { sketches.clearUnkeptHistory() }
  }

  package func deleteAttempt(_ id: String) {
    let candidate = (selectedCandidate?.id == id ? selectedCandidate : nil)
      ?? sketches.entries.first(where: { $0.id == id })?.candidate
      ?? (completedCandidate?.id == id ? completedCandidate : nil)
    guard let candidate else { sketches.remove(id); return }
    deleteAttempt(.init(candidateID: id, photoID: candidate.photoID))
  }

  package func deleteAttempt(_ identity: PortraitDrawingIdentity) {
    forwardPortraits.removeAll { $0.candidate.id == identity.candidateID && $0.candidate.photoID == identity.photoID }
    explorationHistory.removeAll { $0.candidate.id == identity.candidateID && $0.candidate.photoID == identity.photoID }
    if completedCandidate?.id == identity.candidateID && completedCandidate?.photoID == identity.photoID {
      cancelExplorationWork()
      completedCandidate = nil; completedKey = nil; requestedKey = nil; program = nil
    }
    sketches.deleteDrawing(identity)
  }

  package func burdenSummary(for candidate: PortraitCandidate) -> String {
    sketches.entries.first(where: { $0.id == candidate.id && $0.candidate.photoID == candidate.photoID })?.attempt?.burdenSummary
      ?? "\(candidate.program.strokes.count) strokes"
  }

  package var browserTimingSummary: String {
    func ms(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0 * 1000) } ?? "Not measured" }
    return "History selection install: \(ms(lastHistoryNavigationSeconds)). Next useful variation: \(ms(firstAlternativeSeconds)). Renderer calls: \(renderDiagnostics.startedWorkerCount). Selection timing excludes display painting. Variation timing includes queue wait and publication."
  }

  package func saveStyle(name: String) {
    guard let candidate = selectedCandidate else { return }
    sketches.saveStyle(name: name, recipe: candidate.recipe)
  }

  package func applySavedStyle(_ saved: PortraitSavedStyle, strokeStyle: StrokeStyle) {
    let parent = selectedCandidate
    installRecipe(saved.recipe)
    render(strokeStyle: strokeStyle, parent: parent)
  }

  package func saveAuthoredDrawing(_ drawing: SavedDrawing, isStillCurrent: () -> Bool) async -> String? {
    if let error = await sketches.saveDrawing(drawing) { return error }
    guard !Task.isCancelled, isStillCurrent(), !sketches.drawingWasDeleted(drawing) else {
      return "The drawing changed while Save Drawing was pending. The captured drawing was saved; review the current drawing."
    }
    projectedDrawing = drawing; projectedCandidate = drawing.portraitCandidate
    return nil
  }

  package func saveSelectedDrawing() async -> String? {
    guard let candidate = selectedCandidate else { return "Wait for the selected drawing to finish rendering." }
    return await sketches.saveDrawing(SavedDrawing(candidate: candidate))
  }

  /// Save the captured immutable snapshot before handing it to Drawing. Selection
  /// changes during persistence cannot substitute another drawing for this one.
  package func acceptDrawingProjection(_ drawing: SavedDrawing,
    perform: () async -> String?) async -> String? {
    if let error = await sketches.saveDrawing(drawing) { return error }
    guard !Task.isCancelled, !sketches.drawingWasDeleted(drawing) else {
      return "The drawing was deleted while handoff was pending."
    }
    if let error = await perform() { return error }
    guard !Task.isCancelled, !sketches.drawingWasDeleted(drawing) else {
      return "The drawing was deleted while handoff was pending."
    }
    if let candidate = drawing.portraitCandidate {
      let selection = sketches.selectedID
      let error = sketches.retain(candidate: candidate, reason: .projectionAccepted(acceptanceID: UUID()))
      sketches.selectedID = selection
      if let error { return error }
      await sketches.awaitPersistence()
      guard sketches.persistenceState == .saved, !sketches.drawingWasDeleted(drawing), !Task.isCancelled else {
        if case .failed(let error) = sketches.persistenceState { return error }
        return "The drawing handoff has not finished saving. Retry Send to Drawing."
      }
    }
    projectedDrawing = drawing; projectedCandidate = drawing.portraitCandidate
    return nil
  }

  package func acceptProjection(_ candidate: PortraitCandidate,
    perform: () async -> String?) async -> String? {
    await acceptDrawingProjection(SavedDrawing(candidate: candidate), perform: perform)
  }

  /// Stop expensive work without discarding captured photos or the last
  /// completed draft. Replacement work waits for the current worker to settle.
  package func cancelRendering() async {
    photoSelectionRevision &+= 1; photoSelectionTask?.cancel(); photoSelectionTask = nil
    loadingPhotoID = nil
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

  package func awaitRendering() async {
    await photoSelectionTask?.value
    await historyStepTask?.value
    await workTask?.value
  }

  package func cameraDiagnostics() async -> CameraCaptureSnapshot { await camera.snapshot() }

  package func shutdown() async {
    isShutdown = true
    photoSelectionRevision &+= 1; photoSelectionTask?.cancel(); photoSelectionTask = nil
    loadingPhotoID = nil
    await cancelRendering()
    await stopCamera()
    await sketches.awaitPersistence()
    await sketches.awaitLibrarySynchronization()
  }
}
