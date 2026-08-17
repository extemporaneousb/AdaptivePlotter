import Foundation
import PlotterRuntime

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

  static let actions = OperatorWorkspace.DrawingEvidenceActions(
    load: { await store.load() },
    append: { record in try await store.append(record) }
  )
}
