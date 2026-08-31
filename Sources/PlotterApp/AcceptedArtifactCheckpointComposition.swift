import Foundation
import PlotterRuntime

enum AcceptedArtifactCheckpointComposition {
  static let actions: OperatorWorkspace.AcceptedLearningPathCheckpointActions = {
    let fileManager = FileManager.default
    let base =
      (try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )) ?? fileManager.temporaryDirectory
    let directory =
      base
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("AcceptedArtifacts", isDirectory: true)
    let store = AcceptedLearningPathCheckpointStore(
      fileURL: directory.appendingPathComponent("accepted-learning-path-v1.json")
    )
    let migration = AcceptedLearningPathLegacyMigrationAdapter(
      canonicalStore: store,
      machineURL: directory.appendingPathComponent("accepted-machine-artifacts-v1.json"),
      tipURL: directory.appendingPathComponent("accepted-tip-calibration-v1.json"),
      semanticIdentity: TipCalibrationSemanticIdentityComposition.state.learningPathIdentity
    )
    return OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: { migration.migrateIfNeeded().checkpointLoadResult },
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

  static func persistPaperRevisionContext(_ context: PaperRevisionContext) throws {
    let instance = context.instance.rawValue.uuidString.lowercased()
    let plane = context.contactPlane.rawValue.uuidString.lowercased()
    UserDefaults.standard.set(instance, forKey: Key.paperInstance)
    UserDefaults.standard.set(plane, forKey: Key.paperContactPlane)
    guard UserDefaults.standard.string(forKey: Key.paperInstance) == instance,
      UserDefaults.standard.string(forKey: Key.paperContactPlane) == plane
    else {
      throw PaperRevisionPersistenceError.readBackMismatch
    }
  }

  enum PaperRevisionPersistenceError: Error {
    case readBackMismatch
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

extension TipCalibrationSemanticIdentityState {
  var learningPathIdentity: LearningPathSemanticIdentity {
    LearningPathSemanticIdentity(
      machineGeometry: machineGeometry,
      toolAssembly: toolAssembly,
      penContactProfile: penContactProfile,
      paperInstance: paperInstance,
      paperContactPlane: paperContactPlane,
      cameraMountRevision: cameraMountRevision,
      cameraReframingRevision: cameraReframingRevision
    )
  }
}
