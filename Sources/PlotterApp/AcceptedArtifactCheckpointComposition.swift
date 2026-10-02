import Foundation
import PlotterRuntime

enum AcceptedArtifactCheckpointComposition {
  static let statePersistencePort: any PlotterApplicationStatePersistencePort = {
    let paths = AdaptivePlotterStoragePaths.production
    let store = AcceptedLearningPathCheckpointStore(
      fileURL: paths.acceptedLearningCheckpoint,
      historyDirectoryURL: paths.acceptedLearningHistoryDirectory
    )
    let migration = AcceptedLearningPathLegacyMigrationAdapter(
      canonicalStore: store,
      machineURL: paths.legacyMachineCheckpoint,
      tipURL: paths.legacyTipCheckpoint,
      semanticIdentity: TipCalibrationSemanticIdentityComposition.state.learningPathIdentity
    )
    return AcceptedArtifactCheckpointStatePersistenceAdapter(
      store: store,
      migration: migration
    )
  }()
}

private struct AcceptedArtifactCheckpointStatePersistenceAdapter:
  PlotterApplicationStatePersistencePort
{
  let store: AcceptedLearningPathCheckpointStore
  let migration: AcceptedLearningPathLegacyMigrationAdapter

  func loadAcceptedLearningPathCheckpoint() -> AcceptedLearningPathCheckpointLoadResult {
    migration.migrateIfNeeded().checkpointLoadResult
  }

  func saveAcceptedLearningPathCheckpoint(
    _ checkpoint: AcceptedLearningPathCheckpoint
  ) throws {
    try store.save(checkpoint)
  }

  func clearAcceptedLearningPathCheckpoint() throws {
    try store.clear()
  }

  func persistPaperRevisionContext(_ context: PaperRevisionContext) throws {
    try TipCalibrationSemanticIdentityComposition.persistPaperRevisionContext(context)
  }

  func persistMachineGeometryIdentity(_ identity: MachineGeometryIdentity) throws {
    try TipCalibrationSemanticIdentityComposition.persistMachineGeometryIdentity(identity)
  }
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

  static var state: TipCalibrationSemanticIdentityState {
    TipCalibrationSemanticIdentityState(
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
  }

  static func persistMachineGeometryIdentity(_ identity: MachineGeometryIdentity) throws {
    let value = identity.rawValue.uuidString.lowercased()
    UserDefaults.standard.set(value, forKey: Key.machineGeometry)
    guard UserDefaults.standard.string(forKey: Key.machineGeometry) == value else {
      throw MachineGeometryPersistenceError.readBackMismatch
    }
  }

  enum MachineGeometryPersistenceError: Error {
    case readBackMismatch
  }

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
