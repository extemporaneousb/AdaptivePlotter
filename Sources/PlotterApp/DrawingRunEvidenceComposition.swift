import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime

@MainActor
final class PlotterApplicationRuntimeDrawingRunFactSource: PlotterDrawingRunFactSource {
  private weak var application: PlotterApplicationRuntime?

  nonisolated init() {}

  func install(_ application: PlotterApplicationRuntime) {
    self.application = application
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
  private let factSource: PlotterApplicationRuntimeDrawingRunFactSource

  @MainActor
  func install(on application: PlotterApplicationRuntime) {
    factSource.install(application)
  }

  static func make(
    machineSession: (any PlotterMachineSession),
    observationSession: any PlotterObservationCameraSessionPort
  ) -> Self {
    let factSource = PlotterApplicationRuntimeDrawingRunFactSource()
    let interpreter = PlotterApplicationRuntimeDrawingRunInterpreterPort(session: machineSession)
    let camera = PlotterApplicationRuntimeDrawingRunCameraPort(session: observationSession)
    let evidence = DrawingRunEvidenceComposition.port
    return Self(
      runtime: PlotterDrawingRunRuntime(
        facts: factSource,
        interpreter: interpreter,
        camera: camera,
        vision: camera,
        evidence: evidence
      ),
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

  init(store: DrawingRunEvidenceStore) {
    self.store = store
  }

  func load() async -> DrawingRunEvidenceStoreLoadResult {
    await store.load()
  }

  func append(_ record: DrawingRunEvidenceRecord) async throws
    -> DrawingRunEvidenceArchive
  {
    try await store.append(record)
  }
}
