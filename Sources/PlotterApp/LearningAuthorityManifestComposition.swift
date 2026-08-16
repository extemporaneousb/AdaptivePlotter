import Foundation
import PlotterRuntime

enum LearningAuthorityManifestComposition {
  static let actions: OperatorWorkspace.LearningAuthorityManifestActions = {
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
        "Application Support is unavailable; accepted Learning authority is disabled: \(error)"
      return OperatorWorkspace.LearningAuthorityManifestActions(
        load: { .rejected(reason: reason, revision: .absent) },
        commit: { _, _ in throw CocoaError(.fileNoSuchFile) }
      )
    }
    let url = base
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("LearningAuthority", isDirectory: true)
      .appendingPathComponent("accepted-learning-authority-v1.json")
    let store = LearningAuthorityManifestStore(fileURL: url)
    return OperatorWorkspace.LearningAuthorityManifestActions(
      load: { store.load() },
      commit: { try store.commit(expectedRevision: $0, mutation: $1) }
    )
  }()
}
