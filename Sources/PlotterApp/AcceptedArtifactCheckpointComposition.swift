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
    let url =
      base
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("AcceptedArtifacts", isDirectory: true)
      .appendingPathComponent("accepted-machine-artifacts-v1.json")
    let store = AcceptedArtifactCheckpointStore(fileURL: url)
    return OperatorWorkspace.AcceptedArtifactCheckpointActions(
      load: { store.load() },
      save: { try store.save($0) },
      clear: { try store.clear() }
    )
  }()

  static let tipCalibrationActions: OperatorWorkspace.AcceptedTipCalibrationCheckpointActions = {
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
      .appendingPathComponent("AcceptedArtifacts", isDirectory: true)
      .appendingPathComponent("accepted-tip-calibration-v1.json")
    let store = AcceptedTipCalibrationCheckpointStore(fileURL: url)
    return OperatorWorkspace.AcceptedTipCalibrationCheckpointActions(
      load: { store.load() },
      save: { try store.save($0) },
      clear: { try store.clear() }
    )
  }()
}

enum TipCalibrationSemanticIdentityComposition {
  private enum Key {
    static let machineGeometry = "AdaptivePlotter.tip.machineGeometry.v1"
    static let toolAssembly = "AdaptivePlotter.tip.toolAssembly.v1"
    static let penContactProfile = "AdaptivePlotter.tip.penContactProfile.v1"
    static let paperInstance = "AdaptivePlotter.paper.instance.v1"
    static let paperContactPlane = "AdaptivePlotter.tip.paperContactPlane.v1"
    static let cameraMount = "AdaptivePlotter.tip.cameraMount.v1"
    static let cameraReframing = "AdaptivePlotter.tip.cameraReframing.v1"
  }

  static let state = TipCalibrationSemanticIdentityState(
    machineGeometry: MachineGeometryIdentity(rawValue: persistedUUID(for: Key.machineGeometry)),
    toolAssembly: ToolAssemblyRevision(rawValue: persistedUUID(for: Key.toolAssembly)),
    penContactProfile: PenContactProfileRevision(
      rawValue: persistedUUID(for: Key.penContactProfile)
    ),
    paperInstance: PaperInstanceRevision(rawValue: persistedUUID(for: Key.paperInstance)),
    paperContactPlane: PaperContactPlaneRevision(
      rawValue: persistedUUID(for: Key.paperContactPlane)
    ),
    cameraMountRevision: persistedUUID(for: Key.cameraMount),
    cameraReframingRevision: persistedUUID(for: Key.cameraReframing)
  )

  static func persistPaperInstance(_ revision: PaperInstanceRevision) {
    UserDefaults.standard.set(
      revision.rawValue.uuidString.lowercased(),
      forKey: Key.paperInstance
    )
  }

  static func persistPaperContactPlane(_ revision: PaperContactPlaneRevision) {
    UserDefaults.standard.set(
      revision.rawValue.uuidString.lowercased(),
      forKey: Key.paperContactPlane
    )
  }

  private static func persistedUUID(for key: String) -> UUID {
    if let value = UserDefaults.standard.string(forKey: key),
      let uuid = UUID(uuidString: value)
    {
      return uuid
    }
    let uuid = UUID()
    UserDefaults.standard.set(uuid.uuidString.lowercased(), forKey: key)
    return uuid
  }
}
