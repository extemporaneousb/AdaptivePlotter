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
    let legacyMachine = AcceptedArtifactCheckpointStore(
      fileURL: directory.appendingPathComponent("accepted-machine-artifacts-v1.json")
    )
    let legacyTip = AcceptedTipCalibrationCheckpointStore(
      fileURL: directory.appendingPathComponent("accepted-tip-calibration-v1.json")
    )
    return OperatorWorkspace.AcceptedLearningPathCheckpointActions(
      load: {
        let loaded = store.load()
        guard case .absent = loaded else { return loaded }
        let machine: AcceptedMachineArtifactCheckpoint? =
          if case .loaded(let value) = legacyMachine.load() { value } else { nil }
        let tip: AcceptedTipCalibrationCheckpoint? =
          if case .quarantined(let value) = legacyTip.load() { value } else { nil }
        guard machine != nil || tip != nil else { return .absent }
        do {
          let migrated = try AcceptedLearningPathCheckpoint(
            semanticIdentity: TipCalibrationSemanticIdentityComposition.state.learningPathIdentity,
            machineArtifacts: machine,
            tipCalibration: tip
          )
          try store.save(migrated)
          try legacyMachine.clear()
          try legacyTip.clear()
          return .loaded(migrated)
        } catch {
          return .rejected("Legacy Learning Path checkpoint migration failed: \(error)")
        }
      },
      save: {
        try store.save($0)
        try legacyMachine.clear()
        try legacyTip.clear()
      },
      clear: {
        try store.clear()
        try legacyMachine.clear()
        try legacyTip.clear()
      }
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
