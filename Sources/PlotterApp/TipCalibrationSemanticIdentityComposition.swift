import Foundation
import PlotterRuntime

enum TipCalibrationSemanticIdentityComposition {
  private enum Key {
    static let machineGeometry = "AdaptivePlotter.tip.machineGeometry.v1"
    static let toolAssembly = "AdaptivePlotter.tip.toolAssembly.v1"
    static let penContactProfile = "AdaptivePlotter.tip.penContactProfile.v1"
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
    paperContactPlane: PaperContactPlaneRevision(
      rawValue: persistedUUID(for: Key.paperContactPlane)
    ),
    cameraMountRevision: persistedUUID(for: Key.cameraMount),
    cameraReframingRevision: persistedUUID(for: Key.cameraReframing)
  )

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
