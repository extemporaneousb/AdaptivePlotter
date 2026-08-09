import Foundation
import PlotterRuntime

enum AcceptedArtifactCheckpointComposition {
  static let actions: OperatorWorkspace.AcceptedArtifactCheckpointActions = {
    let fileManager = FileManager.default
    let base =
      (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? fileManager.temporaryDirectory
    let url = base
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("AcceptedArtifacts", isDirectory: true)
      .appendingPathComponent("accepted-machine-artifacts-v1.json")
    let store = AcceptedArtifactCheckpointStore(fileURL: url)
    return OperatorWorkspace.AcceptedArtifactCheckpointActions(
      load: { store.load() },
      save: { try store.save($0) }
    )
  }()
}
