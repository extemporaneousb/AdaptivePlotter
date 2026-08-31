import CryptoKit
import Foundation
import PlotterRuntime

enum AcceptedLearningPathLegacyArtifactRecoveryState: Hashable, Sendable {
  case absent
  case original
  case stagedBackup
  case originalAndStagedBackup

  var detail: String {
    switch self {
    case .absent: "absent"
    case .original: "original"
    case .stagedBackup: "staged backup"
    case .originalAndStagedBackup: "original and staged backup"
    }
  }
}

struct AcceptedLearningPathLegacyCleanupFailure: Hashable, Sendable {
  let operation: String
  let machineRecovery: AcceptedLearningPathLegacyArtifactRecoveryState
  let tipRecovery: AcceptedLearningPathLegacyArtifactRecoveryState

  var detail: String {
    "\(operation). Recoverable machine bytes: \(machineRecovery.detail); "
      + "recoverable tip bytes: \(tipRecovery.detail)."
  }
}

enum AcceptedLearningPathLegacyMigrationFailure: Hashable, Sendable {
  case canonicalRejected(String)
  case machineRejected(String)
  case tipRejected(String)
  case canonicalConstruction(String)
  case canonicalSave(String)
  case legacyClear(AcceptedLearningPathLegacyCleanupFailure)

  var detail: String {
    switch self {
    case .canonicalRejected(let detail): "Canonical Learning Path checkpoint was rejected: \(detail)"
    case .machineRejected(let detail): "Legacy machine checkpoint was rejected: \(detail)"
    case .tipRejected(let detail): "Legacy tip checkpoint was rejected: \(detail)"
    case .canonicalConstruction(let detail): "Legacy checkpoints could not form a canonical checkpoint: \(detail)"
    case .canonicalSave(let detail): "Canonical Learning Path checkpoint save failed: \(detail)"
    case .legacyClear(let failure):
      "Canonical checkpoint was saved, but legacy cleanup requires reconciliation: \(failure.detail)"
    }
  }
}

struct AcceptedLearningPathLegacyMigrationCanonicalPersistence: Sendable {
  let load: @Sendable () -> AcceptedLearningPathCheckpointLoadResult
  let save: @Sendable (AcceptedLearningPathCheckpoint) throws -> Void

  static func store(_ store: AcceptedLearningPathCheckpointStore) -> Self {
    Self(load: { store.load() }, save: { try store.save($0) })
  }
}

struct AcceptedLearningPathLegacyMigrationPersistence: Sendable {
  let fileExists: @Sendable (URL) -> Bool
  let read: @Sendable (URL) throws -> Data
  let write: @Sendable (Data, URL) throws -> Void
  let remove: @Sendable (URL) throws -> Void

  static let fileSystem = Self(
    fileExists: { FileManager.default.fileExists(atPath: $0.path) },
    read: { try Data(contentsOf: $0) },
    write: { data, url in
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: url, options: .atomic)
    },
    remove: { try FileManager.default.removeItem(at: $0) }
  )
}

enum AcceptedLearningPathLegacyMigrationResult: Sendable {
  case absent
  case canonical(AcceptedLearningPathCheckpoint)
  case migrated(AcceptedLearningPathCheckpoint)
  case failed(AcceptedLearningPathLegacyMigrationFailure)

  var checkpointLoadResult: AcceptedLearningPathCheckpointLoadResult {
    switch self {
    case .absent: .absent
    case .canonical(let checkpoint), .migrated(let checkpoint): .loaded(checkpoint)
    case .failed(let failure): .rejected(failure.detail)
    }
  }
}

/// Version-aware, one-shot adapter for the two pre-canonical v1 files. A
/// canonical result never loads an ordinary legacy file. If a previous
/// canonical-save cleanup left a deterministic staged backup, it reconciles
/// that known transaction before returning canonical authority.
struct AcceptedLearningPathLegacyMigrationAdapter: Sendable {
  private struct LegacyEnvelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  private enum LegacyLoad<Value> {
    case absent
    case loaded(Value, bytes: Data)
    case rejected(String)
  }

  private struct LegacyArtifact {
    let name: String
    let url: URL
    let bytes: Data?

    var backupURL: URL {
      url.appendingPathExtension("migration-backup")
    }
  }

  let canonicalPersistence: AcceptedLearningPathLegacyMigrationCanonicalPersistence
  let machineURL: URL
  let tipURL: URL
  let semanticIdentity: LearningPathSemanticIdentity
  let persistence: AcceptedLearningPathLegacyMigrationPersistence

  init(
    canonicalStore: AcceptedLearningPathCheckpointStore,
    machineURL: URL,
    tipURL: URL,
    semanticIdentity: LearningPathSemanticIdentity,
    persistence: AcceptedLearningPathLegacyMigrationPersistence = .fileSystem
  ) {
    self.init(
      canonicalPersistence: .store(canonicalStore),
      machineURL: machineURL,
      tipURL: tipURL,
      semanticIdentity: semanticIdentity,
      persistence: persistence
    )
  }

  init(
    canonicalPersistence: AcceptedLearningPathLegacyMigrationCanonicalPersistence,
    machineURL: URL,
    tipURL: URL,
    semanticIdentity: LearningPathSemanticIdentity,
    persistence: AcceptedLearningPathLegacyMigrationPersistence = .fileSystem
  ) {
    self.canonicalPersistence = canonicalPersistence
    self.machineURL = machineURL
    self.tipURL = tipURL
    self.semanticIdentity = semanticIdentity
    self.persistence = persistence
  }

  func migrateIfNeeded() -> AcceptedLearningPathLegacyMigrationResult {
    switch canonicalPersistence.load() {
    case .loaded(let checkpoint):
      if let failure = reconcileStagedCleanup() {
        return .failed(.legacyClear(failure))
      }
      return .canonical(checkpoint)
    case .rejected(let reason):
      return .failed(.canonicalRejected(reason))
    case .absent:
      break
    }

    let machine = loadLegacy(
      AcceptedMachineArtifactCheckpoint.self,
      from: machineURL,
      expectedVersion: AcceptedMachineArtifactCheckpoint.schemaVersion,
      expectedAlgorithm: AcceptedMachineArtifactCheckpoint.algorithmRevision,
      validate: { try $0.validate() }
    )
    let tip = loadLegacy(
      AcceptedTipCalibrationCheckpoint.self,
      from: tipURL,
      expectedVersion: AcceptedTipCalibrationCheckpoint.schemaVersion,
      expectedAlgorithm: AcceptedTipCalibrationCheckpoint.algorithmRevision,
      validate: { try $0.validate() }
    )
    guard case .rejected(let reason) = machine else {
      guard case .rejected(let reason) = tip else {
        return migrate(machine: machine, tip: tip)
      }
      return .failed(.tipRejected(reason))
    }
    return .failed(.machineRejected(reason))
  }

  private func migrate(
    machine: LegacyLoad<AcceptedMachineArtifactCheckpoint>,
    tip: LegacyLoad<AcceptedTipCalibrationCheckpoint>
  ) -> AcceptedLearningPathLegacyMigrationResult {
    let machineValue: AcceptedMachineArtifactCheckpoint?
    let machineBytes: Data?
    switch machine {
    case .absent: (machineValue, machineBytes) = (nil, nil)
    case .loaded(let value, let bytes): (machineValue, machineBytes) = (value, bytes)
    case .rejected: preconditionFailure("Rejected legacy input must stop before migration.")
    }
    let tipValue: AcceptedTipCalibrationCheckpoint?
    let tipBytes: Data?
    switch tip {
    case .absent: (tipValue, tipBytes) = (nil, nil)
    case .loaded(let value, let bytes): (tipValue, tipBytes) = (value, bytes)
    case .rejected: preconditionFailure("Rejected legacy input must stop before migration.")
    }
    guard machineValue != nil || tipValue != nil else { return .absent }

    let checkpoint: AcceptedLearningPathCheckpoint
    do {
      checkpoint = try AcceptedLearningPathCheckpoint(
        semanticIdentity: semanticIdentity,
        machineArtifacts: machineValue,
        tipCalibration: tipValue
      )
    } catch {
      return .failed(.canonicalConstruction(String(describing: error)))
    }
    do {
      try canonicalPersistence.save(checkpoint)
    } catch {
      return .failed(.canonicalSave(String(describing: error)))
    }

    let artifacts = [
      LegacyArtifact(name: "machine", url: machineURL, bytes: machineBytes),
      LegacyArtifact(name: "tip", url: tipURL, bytes: tipBytes),
    ]
    if let failure = stageAndClear(artifacts) {
      return .failed(.legacyClear(failure))
    }
    return .migrated(checkpoint)
  }

  private func loadLegacy<Value: Decodable>(
    _ type: Value.Type,
    from url: URL,
    expectedVersion: UInt16,
    expectedAlgorithm: String,
    validate: (Value) throws -> Void
  ) -> LegacyLoad<Value> {
    guard persistence.fileExists(url) else { return .absent }
    do {
      let bytes = try persistence.read(url)
      let envelope = try JSONDecoder().decode(LegacyEnvelope.self, from: bytes)
      guard envelope.schemaVersion == expectedVersion else {
        return .rejected("Unsupported v\(envelope.schemaVersion) envelope; expected v\(expectedVersion).")
      }
      guard Self.sha256(envelope.payload) == envelope.payloadSHA256 else {
        return .rejected("Integrity verification failed.")
      }
      let value = try JSONDecoder().decode(type, from: envelope.payload)
      try validate(value)
      let payloadObject = try JSONSerialization.jsonObject(with: envelope.payload)
      guard let payload = payloadObject as? [String: Any],
        payload["algorithmRevision"] as? String == expectedAlgorithm
      else { return .rejected("Unsupported legacy algorithm; expected \(expectedAlgorithm).") }
      return .loaded(value, bytes: bytes)
    } catch {
      return .rejected("Legacy checkpoint could not be decoded: \(error)")
    }
  }

  /// A backup is atomically written before its source is removed. Therefore a
  /// failed removal can be rolled back, and a failed rollback still has a
  /// deterministic staged byte copy for the next canonical load to reconcile.
  private func stageAndClear(
    _ artifacts: [LegacyArtifact]
  ) -> AcceptedLearningPathLegacyCleanupFailure? {
    do {
      for artifact in artifacts where artifact.bytes != nil {
        try stage(artifact)
      }
    } catch {
      return cleanupFailure(operation: "Could not stage legacy cleanup: \(error)", artifacts: artifacts)
    }

    var removed: [LegacyArtifact] = []
    for artifact in artifacts where artifact.bytes != nil {
      do {
        try persistence.remove(artifact.url)
        removed.append(artifact)
      } catch {
        let rollbackErrors = restore(removed)
        let rollbackDetail = rollbackErrors.isEmpty
          ? ""
          : " Rollback also failed: \(rollbackErrors.joined(separator: "; "))."
        return cleanupFailure(
          operation: "Could not remove legacy \(artifact.name) source: \(error).\(rollbackDetail)",
          artifacts: artifacts
        )
      }
    }

    do {
      for artifact in artifacts where artifact.bytes != nil {
        try persistence.remove(artifact.backupURL)
      }
    } catch {
      return cleanupFailure(
        operation: "Could not finalize staged legacy cleanup: \(error)",
        artifacts: artifacts
      )
    }
    return nil
  }

  private func stage(_ artifact: LegacyArtifact) throws {
    guard let bytes = artifact.bytes else { return }
    if persistence.fileExists(artifact.backupURL) {
      let stagedBytes = try persistence.read(artifact.backupURL)
      guard stagedBytes == bytes else {
        throw LegacyCleanupError.stagedBackupMismatch(artifact.name)
      }
      return
    }
    try persistence.write(bytes, artifact.backupURL)
  }

  private func restore(_ artifacts: [LegacyArtifact]) -> [String] {
    artifacts.reversed().compactMap { artifact in
      guard let bytes = artifact.bytes else { return nil }
      do {
        try persistence.write(bytes, artifact.url)
        return nil
      } catch {
        return "could not restore \(artifact.name) source: \(error)"
      }
    }
  }

  /// Only a known staged-backup path permits canonical-load reconciliation.
  /// Unpaired legacy files remain untouched, preserving the canonical-load
  /// short-circuit for unrelated/corrupt legacy data.
  private func reconcileStagedCleanup() -> AcceptedLearningPathLegacyCleanupFailure? {
    let artifacts = [
      LegacyArtifact(name: "machine", url: machineURL, bytes: nil),
      LegacyArtifact(name: "tip", url: tipURL, bytes: nil),
    ]
    do {
      for artifact in artifacts where persistence.fileExists(artifact.backupURL) {
        if persistence.fileExists(artifact.url) {
          let original = try persistence.read(artifact.url)
          let backup = try persistence.read(artifact.backupURL)
          guard original == backup else {
            throw LegacyCleanupError.stagedBackupMismatch(artifact.name)
          }
          try persistence.remove(artifact.url)
        }
        try persistence.remove(artifact.backupURL)
      }
      return nil
    } catch {
      return cleanupFailure(
        operation: "Could not reconcile staged legacy cleanup: \(error)",
        artifacts: artifacts
      )
    }
  }

  private func cleanupFailure(
    operation: String,
    artifacts: [LegacyArtifact]
  ) -> AcceptedLearningPathLegacyCleanupFailure {
    func state(for artifact: LegacyArtifact) -> AcceptedLearningPathLegacyArtifactRecoveryState {
      let original = persistence.fileExists(artifact.url)
      let backup = persistence.fileExists(artifact.backupURL)
      switch (original, backup) {
      case (false, false): return .absent
      case (true, false): return .original
      case (false, true): return .stagedBackup
      case (true, true): return .originalAndStagedBackup
      }
    }
    return AcceptedLearningPathLegacyCleanupFailure(
      operation: operation,
      machineRecovery: state(for: artifacts[0]),
      tipRecovery: state(for: artifacts[1])
    )
  }

  private enum LegacyCleanupError: Error, CustomStringConvertible {
    case stagedBackupMismatch(String)

    var description: String {
      switch self {
      case .stagedBackupMismatch(let artifact):
        "Staged \(artifact) backup does not match its original source."
      }
    }
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
