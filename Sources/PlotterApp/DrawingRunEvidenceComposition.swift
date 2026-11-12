import PortraitLibrary
import PortraitCore
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
    guard let application, application.drawingDestinationRecoveryAdmissionIsOpen else {
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
    let facts = await application.currentDrawingRunFacts(for: environment)
    guard application.drawingDestinationRecoveryAdmissionIsOpen else {
      return .init(environment: environment, interactiveLearningIsComplete: false, plan: nil,
        paperCoverageIsCurrent: false, displayedFrame: nil, interpreter: nil, penActuationProfile: .initialDefaults)
    }
    return facts
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

actor DrawingRunEvidencePort: PlotterDrawingRunEvidencePort, DrawingDestinationResultSource {
  private let store: DrawingRunEvidenceStore
  private let archiveLoader: (@Sendable () async -> DrawingRunEvidenceStoreLoadResult)?
  private(set) var loadCount = 0
  private var stagedPortraitBinding: (intent: DrawingRunIntent, archive: DrawingRunEvidenceArchive)?

  nonisolated var archiveURL: URL { store.fileURL }

  private func observeArchive(_ archive: DrawingRunEvidenceArchive) async -> DrawingRunEvidenceArchive {
    if let binding = stagedPortraitBinding,
      archive.attempts.contains(where: { $0.intent == binding.intent }) {
      stagedPortraitBinding = (binding.intent, archive)
    }
    return archive
  }

  init(store: DrawingRunEvidenceStore, archiveLoader: (@Sendable () async -> DrawingRunEvidenceStoreLoadResult)? = nil) {
    self.store = store
    self.archiveLoader = archiveLoader
  }

  func appendAxisMetricMeasurement(_ measurement: ControllerAxisMetricMeasurement) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.appendAxisMetricMeasurement(measurement))
  }
  func prepareAxisCalibration(_ attempt: ControllerAxisCalibrationAttempt) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.prepareAxisCalibration(attempt))
  }
  func appendAxisCalibrationTerminal(_ terminal: ControllerAxisCalibrationTerminal) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.appendAxisCalibrationTerminal(terminal))
  }

  func load() async -> DrawingRunEvidenceStoreLoadResult {
    loadCount += 1
    let result: DrawingRunEvidenceStoreLoadResult
    if let archiveLoader { result = await archiveLoader() } else { result = await store.load() }
    switch result {
    case .loaded: break
    case .absent:
      stagedPortraitBinding = nil
    case .rejected:
      stagedPortraitBinding = nil
    }
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
  }

  func deleteReview(recordID: DrawingEvidenceRecordID) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.deleteReview(recordID: recordID))
  }

  func dismissAttemptReview(runID: RunID) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.dismissAttemptReview(runID: runID))
  }

  func annotateReview(_ note: DrawingReviewNote) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.annotateReview(note))
  }

  func stageIssuance(_ proposal: DrawingRunIssuanceProposal) async throws -> DrawingRunIssuanceStageReceipt {
    let receipt = try await store.stageIssuance(proposal)
    stagedPortraitBinding = (receipt.intent, receipt.archive)
    return receipt
  }
  func lookupIssuance(_ binding: DrawingJobIssuance) async throws -> DrawingRunIssuanceStageReceipt? {
    let receipt = try await store.lookupIssuance(binding)
    if let receipt { stagedPortraitBinding = (receipt.intent, receipt.archive) }
    return receipt
  }
  func stageIntent(_ intent: DrawingRunIntent) async throws -> DrawingRunEvidenceArchive {
    let archive = try await store.stageIntent(intent)
    if intent.role == .ordinaryDrawing, intent.context.candidate != nil,
      !archive.records.contains(where: { $0.runID == intent.runID }) {
      stagedPortraitBinding = (intent, archive)
    }
    return await observeArchive(archive)
  }

  func installMedia(frame: StampedFrame, source: FrameSourceIdentity) async throws -> DrawingRunMediaReference {
    try await store.installMedia(frame: frame, source: source)
  }

  func readMedia(_ reference: DrawingRunMediaReference) async throws -> StampedFrame {
    try await store.readMedia(reference)
  }

  func exportAttempt(runID: RunID) async throws -> DrawingRunAttemptExport {
    try await store.exportAttempt(runID: runID)
  }

  func stageBaseline(runID: RunID, media: DrawingRunMediaReference) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.stageBaseline(runID: runID, media: media))
  }

  func stageProgressFrame(runID: RunID, frame: DrawingRunProgressFrame) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.stageProgressFrame(runID: runID, frame: frame))
  }

  func confirmNoInk(_ confirmation: DrawingRunNoInkConfirmation) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.confirmNoInk(confirmation))
  }

  func markInkDispatchPossible(runID: RunID) async throws -> DrawingRunEvidenceArchive {
    return await observeArchive(try await store.markInkDispatchPossible(runID: runID))
  }

  func append(_ record: DrawingRunEvidenceRecord) async throws
    -> DrawingRunEvidenceArchive
  {
    return await observeArchive(try await store.append(record))
  }
}
