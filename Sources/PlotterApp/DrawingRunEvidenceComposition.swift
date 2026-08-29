import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime

actor OperatorWorkspaceDrawingRunFactSource: PlotterDrawingRunFactSource {
  private weak var workspace: OperatorWorkspace?

  func install(_ workspace: OperatorWorkspace) {
    self.workspace = workspace
  }

  func drawingRunFacts(
    for environment: PlotterEnvironment
  ) async -> PlotterDrawingRunExternalFacts {
    guard let workspace else {
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
    return await workspace.currentDrawingRunFacts(for: environment)
  }
}

struct PlotterDrawingRunComposition: Sendable {
  let runtime: PlotterDrawingRunRuntime
  let factSource: OperatorWorkspaceDrawingRunFactSource
  let interpreter: OperatorWorkspaceDrawingRunInterpreterPort
  let camera: OperatorWorkspaceDrawingRunCameraPort

  static func make(
    machineActions: OperatorWorkspace.MachineActions,
    cameraActions: OperatorWorkspace.CameraActions
  ) -> Self {
    let factSource = OperatorWorkspaceDrawingRunFactSource()
    let interpreter = OperatorWorkspaceDrawingRunInterpreterPort(actions: machineActions)
    let camera = OperatorWorkspaceDrawingRunCameraPort(actions: cameraActions)
    let evidence = DrawingRunEvidenceComposition.port
    return Self(
      runtime: PlotterDrawingRunRuntime(
        facts: factSource,
        interpreter: interpreter,
        camera: camera,
        vision: camera,
        evidence: evidence
      ),
      factSource: factSource,
      interpreter: interpreter,
      camera: camera
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
