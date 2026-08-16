import Foundation
import PlotterRuntime

enum LearningSurfaceExposureComposition {
  static let actions: OperatorWorkspace.LiveLearningSurfaceExposureActions = {
    let fileManager = FileManager.default
    let base: URL
    do {
      base = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    } catch {
      let reason =
        "Application Support is unavailable; LIVE surface contact is disabled: \(error)"
      return OperatorWorkspace.LiveLearningSurfaceExposureActions(
        load: { .rejected(reason: reason, revision: .corrupt(fileSHA256: "unavailable")) },
        save: { _, _, _ in throw CocoaError(.fileNoSuchFile) },
        recoverForPaperReplacement: { _, _ in throw CocoaError(.fileNoSuchFile) }
      )
    }
    let directory = base
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("SafetyHistory", isDirectory: true)
    let store = LiveLearningSurfaceExposureStore(
      fileURL: directory.appendingPathComponent("learning-surface-exposures-v1.json"),
      corruptArchiveDirectoryURL: directory.appendingPathComponent(
        "CorruptArchive",
        isDirectory: true
      )
    )
    return OperatorWorkspace.LiveLearningSurfaceExposureActions(
      load: { store.load() },
      save: {
        try store.save(
          expectedRevision: $0,
          $1,
          currentPaperContactPlane: $2
        )
      },
      recoverForPaperReplacement: {
        try store.recoverForPaperReplacement(expectedRevision: $0, $1)
      }
    )
  }()
}
