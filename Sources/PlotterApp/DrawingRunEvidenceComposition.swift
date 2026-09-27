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
    let fileManager = FileManager.default
    let base =
      (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? fileManager.temporaryDirectory
    let url =
      base
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("DrawingEvidence", isDirectory: true)
      .appendingPathComponent("drawing-run-evidence-v1.json")
    return DrawingRunEvidenceStore(fileURL: url)
  }()

  static let port = DrawingRunEvidencePort(store: store)
}

actor DrawingRunEvidencePort: PlotterDrawingRunEvidencePort {
  private let store: DrawingRunEvidenceStore
  private(set) var loadCount = 0

  init(store: DrawingRunEvidenceStore) {
    self.store = store
  }

  nonisolated func loadSnapshot() -> DrawingRunEvidenceStoreLoadResult { store.loadSnapshot() }

  func appendAxisMetricMeasurement(_ measurement: ControllerAxisMetricMeasurement) async throws -> DrawingRunEvidenceArchive {
    try await store.appendAxisMetricMeasurement(measurement)
  }
  func prepareAxisCalibration(_ attempt: ControllerAxisCalibrationAttempt) async throws -> DrawingRunEvidenceArchive {
    try await store.prepareAxisCalibration(attempt)
  }
  func appendAxisCalibrationTerminal(_ terminal: ControllerAxisCalibrationTerminal) async throws -> DrawingRunEvidenceArchive {
    try await store.appendAxisCalibrationTerminal(terminal)
  }

  func load() async -> DrawingRunEvidenceStoreLoadResult {
    loadCount += 1
    return await store.load()
  }

  func deleteReview(recordID: DrawingEvidenceRecordID) async throws -> DrawingRunEvidenceArchive {
    try await store.deleteReview(recordID: recordID)
  }

  func stageIntent(_ intent: DrawingRunIntent) async throws -> DrawingRunEvidenceArchive {
    try await store.stageIntent(intent)
  }

  func installMedia(frame: StampedFrame, source: FrameSourceIdentity) async throws -> DrawingRunMediaReference {
    try await store.installMedia(frame: frame, source: source)
  }

  func readMedia(_ reference: DrawingRunMediaReference) async throws -> StampedFrame {
    try await store.readMedia(reference)
  }

  func stageBaseline(runID: RunID, media: DrawingRunMediaReference) async throws -> DrawingRunEvidenceArchive {
    try await store.stageBaseline(runID: runID, media: media)
  }

  func stageProgressFrame(runID: RunID, frame: DrawingRunProgressFrame) async throws -> DrawingRunEvidenceArchive {
    try await store.stageProgressFrame(runID: runID, frame: frame)
  }

  func confirmNoInk(_ confirmation: DrawingRunNoInkConfirmation) async throws -> DrawingRunEvidenceArchive {
    try await store.confirmNoInk(confirmation)
  }

  func markInkDispatchPossible(runID: RunID) async throws -> DrawingRunEvidenceArchive {
    try await store.markInkDispatchPossible(runID: runID)
  }

  func append(_ record: DrawingRunEvidenceRecord) async throws
    -> DrawingRunEvidenceArchive
  {
    try await store.append(record)
  }
}
