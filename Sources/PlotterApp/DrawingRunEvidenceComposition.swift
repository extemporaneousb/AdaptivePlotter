import PortraitLibrary
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import PlotterModel

@MainActor
final class PlotterApplicationRuntimeDrawingRunFactSource: PlotterDrawingRunFactSource {
  private weak var application: PlotterApplicationRuntime?

  nonisolated init() {}

  func install(_ application: PlotterApplicationRuntime) {
    self.application = application
  }

  func retainCandidateForAttempt(_ intent: DrawingRunIntent) async throws {
    guard let application else { throw DrawingRunEvidenceError.invalidAttemptContext }
    try await application.retainDrawingCandidateForAttempt(intent)
  }

  func drawingRunFacts(
    for environment: PlotterEnvironment
  ) async -> PlotterDrawingRunExternalFacts {
    guard let application else {
      return PlotterDrawingRunExternalFacts(
        environment: environment,
        interactiveLearningIsComplete: false,
        plan: nil,
        paperCoverageIsCurrent: false,
        displayedFrame: nil,
        interpreter: nil,
        penActuationProfile: .initialDefaults
      )
    }
    return await application.currentDrawingRunFacts(for: environment)
  }
}

struct PlotterDrawingRunComposition: Sendable {
  let runtime: PlotterDrawingRunRuntime
  let evidencePort: DrawingRunEvidencePort
  private let factSource: PlotterApplicationRuntimeDrawingRunFactSource

  @MainActor
  func install(on application: PlotterApplicationRuntime) {
    factSource.install(application)
  }

  static func make(
    machineSession: (any PlotterMachineSession),
    observationSession: any PlotterObservationCameraSessionPort,
    evidencePort: DrawingRunEvidencePort = DrawingRunEvidenceComposition.port,
    clock: any RuntimeClock = SystemRuntimeClock()
  ) -> Self {
    let factSource = PlotterApplicationRuntimeDrawingRunFactSource()
    let interpreter = PlotterApplicationRuntimeDrawingRunInterpreterPort(session: machineSession)
    let camera = PlotterApplicationRuntimeDrawingRunCameraPort(session: observationSession)
    return Self(
      runtime: PlotterDrawingRunRuntime(
        facts: factSource,
        interpreter: interpreter,
        camera: camera,
        vision: camera,
        evidence: evidencePort,
        clock: clock
      ),
      evidencePort: evidencePort,
      factSource: factSource
    )
  }
}

enum DrawingRunEvidenceComposition {
  private static let store: DrawingRunEvidenceStore = {
    DrawingRunEvidenceStore(fileURL: AdaptivePlotterStoragePaths.production.drawingEvidenceArchive)
  }()

  static let port = DrawingRunEvidencePort(store: store)
}

actor DrawingRunEvidencePort: PlotterDrawingRunEvidencePort {
  private enum LibraryPublication: Sendable {
    case synchronize, enqueue, stagedPortrait(RunID), bindingSettled(RunID)
  }

  private let store: DrawingRunEvidenceStore
  private(set) var loadCount = 0
  private var libraryPublication: (@Sendable (DrawingRunEvidenceStoreLoadResult, URL, LibraryPublication) async -> Void)?
  private var lastPublishedArchive: DrawingRunEvidenceArchive?
  private var publishedEvidenceStateIsKnown = false
  private var stagedPortraitBinding: (intent: DrawingRunIntent, archive: DrawingRunEvidenceArchive)?

  nonisolated var archiveURL: URL { store.fileURL }

  /// Catalog failures are advisory browse failures after the raw safety commit.
  /// They must never turn a committed effect into a runtime hardware retry.
  func installPortraitLibrary(_ collection: PortraitSketchCollection) {
    libraryPublication = { [weak collection] result, sourceURL, publication in
      guard let collection else { return }
      switch result {
      case .loaded(let archive):
        switch publication {
        case .synchronize:
          await collection.queueDrawingEvidenceReconciliation(archive, sourceURL: sourceURL)
          await collection.awaitLibrarySynchronization()
        case .enqueue: await collection.queueDrawingEvidenceReconciliation(archive, sourceURL: sourceURL)
        case .stagedPortrait(let runID):
          await collection.deferDrawingEvidenceReconciliation(archive, sourceURL: sourceURL, untilBinding: runID)
        case .bindingSettled(let runID): await collection.finishDrawingEvidenceBinding(runID)
        }
      case .absent: await collection.reconcileAbsentDrawingEvidence(sourceURL: sourceURL)
      case .rejected(let rejection):
        await collection.markLibraryUnavailable("Portrait library is unavailable because raw DrawingEvidence was rejected: \(rejection)")
      }
    }
  }

  private func publishLibrary(_ archive: DrawingRunEvidenceArchive) async -> DrawingRunEvidenceArchive {
    lastPublishedArchive = archive
    publishedEvidenceStateIsKnown = true
    if let binding = stagedPortraitBinding,
      archive.attempts.contains(where: { $0.intent == binding.intent }) {
      stagedPortraitBinding = (binding.intent, archive)
    }
    await libraryPublication?(.loaded(archive), store.fileURL, .enqueue)
    return archive
  }

  init(store: DrawingRunEvidenceStore) {
    self.store = store
  }

  func appendAxisMetricMeasurement(_ measurement: ControllerAxisMetricMeasurement) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.appendAxisMetricMeasurement(measurement))
  }
  func prepareAxisCalibration(_ attempt: ControllerAxisCalibrationAttempt) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.prepareAxisCalibration(attempt))
  }
  func appendAxisCalibrationTerminal(_ terminal: ControllerAxisCalibrationTerminal) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.appendAxisCalibrationTerminal(terminal))
  }

  func load() async -> DrawingRunEvidenceStoreLoadResult {
    loadCount += 1
    let result = await store.load()
    switch result {
    case .loaded(let archive):
      lastPublishedArchive = archive
      publishedEvidenceStateIsKnown = true
    case .absent:
      lastPublishedArchive = nil
      publishedEvidenceStateIsKnown = true
      stagedPortraitBinding = nil
    case .rejected:
      lastPublishedArchive = nil
      publishedEvidenceStateIsKnown = false
      stagedPortraitBinding = nil
    }
    await libraryPublication?(result, store.fileURL, .synchronize)
    return result
  }

  /// Reuse only this port's successful current stage receipt. Storage proves the
  /// exact current leaf and stable manifest; raw load retains its full verifier.
  func loadForPortraitBinding(_ intent: DrawingRunIntent) -> DrawingRunEvidenceStoreLoadResult {
    guard let binding = stagedPortraitBinding, binding.intent == intent,
      binding.archive.attempts.contains(where: { $0.intent == intent }) else {
      return .rejected(.invalidArchive("The exact portrait stage receipt is unavailable."))
    }
    return .loaded(binding.archive)
  }

  func finishPortraitBinding(_ intent: DrawingRunIntent) async {
    guard let binding = stagedPortraitBinding, binding.intent == intent else { return }
    stagedPortraitBinding = nil
    await libraryPublication?(.loaded(binding.archive), store.fileURL, .bindingSettled(intent.runID))
  }

  func deleteReview(recordID: DrawingEvidenceRecordID) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.deleteReview(recordID: recordID))
  }

  func dismissAttemptReview(runID: RunID) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.dismissAttemptReview(runID: runID))
  }

  func annotateReview(_ note: DrawingReviewNote) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.annotateReview(note))
  }

  func stageIntent(_ intent: DrawingRunIntent) async throws -> DrawingRunEvidenceArchive {
    let priorStateWasKnown = publishedEvidenceStateIsKnown
    let wasAlreadyStaged = lastPublishedArchive?.attempts.contains(where: { $0.intent.runID == intent.runID }) == true
      || lastPublishedArchive?.records.contains(where: { $0.runID == intent.runID }) == true
    let archive = try await store.stageIntent(intent)
    if intent.role == .ordinaryDrawing, intent.context.program.source.kind == "portrait",
      !archive.records.contains(where: { $0.runID == intent.runID }) {
      stagedPortraitBinding = (intent, archive)
      // Unknown pre-stage state cannot distinguish insertion from idempotent
      // recovery. It supplies a stage receipt without suppressing publication.
      if priorStateWasKnown, !wasAlreadyStaged {
        lastPublishedArchive = archive
        publishedEvidenceStateIsKnown = true
        await libraryPublication?(.loaded(archive), store.fileURL, .stagedPortrait(intent.runID))
        return archive
      }
    }
    return await publishLibrary(archive)
  }

  func installMedia(frame: StampedFrame, source: FrameSourceIdentity) async throws -> DrawingRunMediaReference {
    try await store.installMedia(frame: frame, source: source)
  }

  func readMedia(_ reference: DrawingRunMediaReference) async throws -> StampedFrame {
    try await store.readMedia(reference)
  }

  func exportTerminalRecord(runID: RunID) async throws -> DrawingRunTerminalExport {
    try await store.exportTerminalRecord(runID: runID)
  }

  func stageBaseline(runID: RunID, media: DrawingRunMediaReference) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.stageBaseline(runID: runID, media: media))
  }

  func stageProgressFrame(runID: RunID, frame: DrawingRunProgressFrame) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.stageProgressFrame(runID: runID, frame: frame))
  }

  func confirmNoInk(_ confirmation: DrawingRunNoInkConfirmation) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.confirmNoInk(confirmation))
  }

  func markInkDispatchPossible(runID: RunID) async throws -> DrawingRunEvidenceArchive {
    return await publishLibrary(try await store.markInkDispatchPossible(runID: runID))
  }

  func append(_ record: DrawingRunEvidenceRecord) async throws
    -> DrawingRunEvidenceArchive
  {
    return await publishLibrary(try await store.append(record))
  }
}
