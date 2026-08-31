import CryptoKit
import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("PER-004 one-shot Learning checkpoint migration", .serialized)
struct AcceptedLearningPathLegacyMigrationTests {
  @Test("canonical checkpoint short-circuits legacy reads and leaves legacy untouched")
  func canonicalShortCircuit() throws {
    let fixture = try MigrationFixture()
    defer { fixture.cleanup() }
    let canonical = try AcceptedLearningPathCheckpoint(
      semanticIdentity: fixture.identities.learningPathIdentity
    )
    try fixture.canonicalStore.save(canonical)
    let corruptLegacy = Data("must-not-be-read".utf8)
    try corruptLegacy.write(to: fixture.machineURL)

    guard case .canonical(let loaded) = fixture.adapter().migrateIfNeeded() else {
      Issue.record("Expected canonical authority to short-circuit legacy migration.")
      return
    }
    #expect(loaded == canonical)
    #expect(try Data(contentsOf: fixture.machineURL) == corruptLegacy)
  }

  @Test("both v1 legacy stores migrate only after canonical save and are deleted once")
  @MainActor
  func dualStoreMigration() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let app = makeCausalSimulatorAppFixture(tipCalibrationSemanticIdentities: identities)
    try await completeSimulatedPenInteractionPrerequisite(app.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: app.boundaryRuntime,
      workspace: app.workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(app.workspace, simulator: app.simulator)
    let registration = try #require(app.workspace.tipCameraRegistration)
    let tip = try AcceptedTipCalibrationCheckpoint(
      registration: registration,
      acceptanceEvent: TipCalibrationAcceptanceEvent(
        acceptedRevisionID: registration.acceptedRevisionID,
        timestamp: registration.acceptedAt,
        actor: "PER-004 fixture"
      )
    )
    await app.workspace.shutdown()

    let fixture = try MigrationFixture(identities: identities)
    defer { fixture.cleanup() }
    let machine = try acceptedBoundaryTestCheckpoint()
    try writeLegacy(machine, to: fixture.machineURL)
    try writeLegacy(tip, to: fixture.tipURL)

    guard case .migrated(let checkpoint) = fixture.adapter().migrateIfNeeded() else {
      Issue.record("Expected both readable legacy stores to migrate.")
      return
    }
    #expect(checkpoint.machineArtifacts == machine)
    #expect(checkpoint.tipCalibration == tip)
    #expect(FileManager.default.fileExists(atPath: fixture.canonicalStore.fileURL.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.machineURL.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.tipURL.path))
    guard case .canonical(let reloaded) = fixture.adapter().migrateIfNeeded() else {
      Issue.record("Expected the second load to use canonical authority only.")
      return
    }
    #expect(reloaded == checkpoint)
  }

  @Test("corrupt and unsupported legacy inputs fail explicitly without deletion")
  func rejectedLegacyPreserved() throws {
    let corrupt = try MigrationFixture()
    defer { corrupt.cleanup() }
    let bytes = Data("corrupt".utf8)
    try bytes.write(to: corrupt.machineURL)
    guard case .failed(.machineRejected) = corrupt.adapter().migrateIfNeeded() else {
      Issue.record("Expected corrupt machine legacy data to fail explicitly.")
      return
    }
    #expect(try Data(contentsOf: corrupt.machineURL) == bytes)
    #expect(!FileManager.default.fileExists(atPath: corrupt.canonicalStore.fileURL.path))

    let unsupported = try MigrationFixture()
    defer { unsupported.cleanup() }
    try writeLegacy(
      acceptedBoundaryTestCheckpoint(),
      to: unsupported.machineURL,
      envelopeVersion: 2
    )
    guard case .failed(.machineRejected(let detail)) = unsupported.adapter().migrateIfNeeded() else {
      Issue.record("Expected unsupported v2 legacy data to fail explicitly.")
      return
    }
    #expect(detail.contains("Unsupported v2"))
    #expect(FileManager.default.fileExists(atPath: unsupported.machineURL.path))
  }

  @Test("canonical save failure preserves every legacy artifact")
  func saveFailurePreservesLegacy() throws {
    let fixture = try MigrationFixture()
    defer { fixture.cleanup() }
    try writeLegacy(acceptedBoundaryTestCheckpoint(), to: fixture.machineURL)
    let tipMarker = Data("tip-marker".utf8)
    try tipMarker.write(to: fixture.tipURL)

    guard case .failed(.tipRejected) = fixture.adapter().migrateIfNeeded() else {
      Issue.record("Expected rejected tip input before canonical save.")
      return
    }
    #expect(FileManager.default.fileExists(atPath: fixture.machineURL.path))
    #expect(try Data(contentsOf: fixture.tipURL) == tipMarker)

    try FileManager.default.removeItem(at: fixture.tipURL)
    let canonicalPersistence = AcceptedLearningPathLegacyMigrationCanonicalPersistence(
      load: { fixture.canonicalStore.load() },
      save: { _ in throw InjectedPersistenceFault.planned("canonical save") }
    )
    guard case .failed(.canonicalSave) = fixture.adapter(
      canonicalPersistence: canonicalPersistence
    ).migrateIfNeeded() else {
      Issue.record("Expected canonical save failure.")
      return
    }
    #expect(FileManager.default.fileExists(atPath: fixture.machineURL.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.machineBackupURL.path))
  }

  @Test("second legacy removal failure restores the first source and retains both staged backups")
  @MainActor
  func secondCleanupRemovalFailureIsRecoverable() async throws {
    let fixture = try MigrationFixture()
    defer { fixture.cleanup() }
    try writeLegacy(acceptedBoundaryTestCheckpoint(), to: fixture.machineURL)
    try writeLegacy(
      try await acceptedTipLegacyCheckpoint(identities: fixture.identities),
      to: fixture.tipURL
    )
    let machineBytes = try Data(contentsOf: fixture.machineURL)
    let tipBytes = try Data(contentsOf: fixture.tipURL)
    let faults = FaultInjectingLegacyPersistence(
      failures: [.remove(fixture.tipURL): 1]
    )

    guard case .failed(.legacyClear(let failure)) = fixture.adapter(
      persistence: faults.persistence
    ).migrateIfNeeded() else {
      Issue.record("Expected the second source removal to fail explicitly.")
      return
    }
    #expect(failure.machineRecovery == .originalAndStagedBackup)
    #expect(failure.tipRecovery == .originalAndStagedBackup)
    #expect(try Data(contentsOf: fixture.machineURL) == machineBytes)
    #expect(try Data(contentsOf: fixture.tipURL) == tipBytes)
    #expect(try Data(contentsOf: fixture.machineBackupURL) == machineBytes)
    #expect(try Data(contentsOf: fixture.tipBackupURL) == tipBytes)
    #expect(FileManager.default.fileExists(atPath: fixture.canonicalStore.fileURL.path))
  }

  @Test("failed restoration reports staged recovery truth and the next canonical load reconciles it")
  @MainActor
  func restorationFailureRetainsBackupForReconciliation() async throws {
    let fixture = try MigrationFixture()
    defer { fixture.cleanup() }
    try writeLegacy(acceptedBoundaryTestCheckpoint(), to: fixture.machineURL)
    try writeLegacy(
      try await acceptedTipLegacyCheckpoint(identities: fixture.identities),
      to: fixture.tipURL
    )
    let machineBytes = try Data(contentsOf: fixture.machineURL)
    let tipBytes = try Data(contentsOf: fixture.tipURL)
    let faults = FaultInjectingLegacyPersistence(
      failures: [
        .remove(fixture.tipURL): 1,
        .write(fixture.machineURL): 1,
      ]
    )

    guard case .failed(.legacyClear(let failure)) = fixture.adapter(
      persistence: faults.persistence
    ).migrateIfNeeded() else {
      Issue.record("Expected explicit failure when rollback restoration fails.")
      return
    }
    #expect(failure.machineRecovery == .stagedBackup)
    #expect(failure.tipRecovery == .originalAndStagedBackup)
    #expect(failure.detail.contains("could not restore machine source"))
    #expect(!FileManager.default.fileExists(atPath: fixture.machineURL.path))
    #expect(try Data(contentsOf: fixture.machineBackupURL) == machineBytes)
    #expect(try Data(contentsOf: fixture.tipURL) == tipBytes)
    #expect(try Data(contentsOf: fixture.tipBackupURL) == tipBytes)

    guard case .canonical = fixture.adapter().migrateIfNeeded() else {
      Issue.record("Expected a later canonical load to reconcile staged legacy backups.")
      return
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.machineURL.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.tipURL.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.machineBackupURL.path))
    #expect(!FileManager.default.fileExists(atPath: fixture.tipBackupURL.path))
  }
}

private struct MigrationFixture {
  let root: URL
  let legacyDirectory: URL
  let canonicalStore: AcceptedLearningPathCheckpointStore
  let machineURL: URL
  let tipURL: URL
  let identities: TipCalibrationSemanticIdentityState

  init(identities: TipCalibrationSemanticIdentityState = .ephemeral()) throws {
    self.identities = identities
    root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "per-004-\(UUID().uuidString)",
      isDirectory: true
    )
    legacyDirectory = root.appendingPathComponent("legacy", isDirectory: true)
    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    machineURL = legacyDirectory.appendingPathComponent("accepted-machine-artifacts-v1.json")
    tipURL = legacyDirectory.appendingPathComponent("accepted-tip-calibration-v1.json")
    let canonicalParent = root.appendingPathComponent("canonical", isDirectory: true)
    canonicalStore = AcceptedLearningPathCheckpointStore(
      fileURL: canonicalParent.appendingPathComponent("accepted-learning-path-v1.json")
    )
  }

  var machineBackupURL: URL {
    machineURL.appendingPathExtension("migration-backup")
  }

  var tipBackupURL: URL {
    tipURL.appendingPathExtension("migration-backup")
  }

  func adapter(
    canonicalPersistence: AcceptedLearningPathLegacyMigrationCanonicalPersistence? = nil,
    persistence: AcceptedLearningPathLegacyMigrationPersistence = .fileSystem
  ) -> AcceptedLearningPathLegacyMigrationAdapter {
    AcceptedLearningPathLegacyMigrationAdapter(
      canonicalPersistence: canonicalPersistence ?? .store(canonicalStore),
      machineURL: machineURL,
      tipURL: tipURL,
      semanticIdentity: identities.learningPathIdentity,
      persistence: persistence
    )
  }

  func cleanup() {
    try? FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: legacyDirectory.path
    )
    try? FileManager.default.removeItem(at: root)
  }
}

@MainActor
private func acceptedTipLegacyCheckpoint(
  identities: TipCalibrationSemanticIdentityState
) async throws -> AcceptedTipCalibrationCheckpoint {
  let app = makeCausalSimulatorAppFixture(tipCalibrationSemanticIdentities: identities)
  try await completeSimulatedPenInteractionPrerequisite(app.workspace)
  try await installAcceptedBoundaryTestProjection(
    runtime: app.boundaryRuntime,
    workspace: app.workspace,
    environment: .simulated
  )
  try await completeSimulatedTipCalibration(app.workspace, simulator: app.simulator)
  let registration = try #require(app.workspace.tipCameraRegistration)
  await app.workspace.shutdown()
  return try AcceptedTipCalibrationCheckpoint(
    registration: registration,
    acceptanceEvent: TipCalibrationAcceptanceEvent(
      acceptedRevisionID: registration.acceptedRevisionID,
      timestamp: registration.acceptedAt,
      actor: "PER-004 fixture"
    )
  )
}

private enum FaultInjectionOperation: Hashable {
  case write(URL)
  case remove(URL)
}

private enum InjectedPersistenceFault: Error, CustomStringConvertible {
  case planned(String)

  var description: String {
    switch self {
    case .planned(let operation): "Injected \(operation) failure"
    }
  }
}

private final class FaultInjectingLegacyPersistence: @unchecked Sendable {
  private let lock = NSLock()
  private let base = AcceptedLearningPathLegacyMigrationPersistence.fileSystem
  private var remainingFailures: [FaultInjectionOperation: Int]

  init(failures: [FaultInjectionOperation: Int]) {
    remainingFailures = failures
  }

  var persistence: AcceptedLearningPathLegacyMigrationPersistence {
    AcceptedLearningPathLegacyMigrationPersistence(
      fileExists: { [base] url in base.fileExists(url) },
      read: { [base] url in try base.read(url) },
      write: { [weak self, base] data, url in
        try self?.failIfPlanned(.write(url))
        try base.write(data, url)
      },
      remove: { [weak self, base] url in
        try self?.failIfPlanned(.remove(url))
        try base.remove(url)
      }
    )
  }

  private func failIfPlanned(_ operation: FaultInjectionOperation) throws {
    lock.lock()
    defer { lock.unlock() }
    guard let remaining = remainingFailures[operation], remaining > 0 else { return }
    remainingFailures[operation] = remaining - 1
    throw InjectedPersistenceFault.planned(String(describing: operation))
  }
}

private struct LegacyEnvelope: Codable {
  let schemaVersion: UInt16
  let payload: Data
  let payloadSHA256: String
}

private func writeLegacy<Value: Encodable>(
  _ value: Value,
  to url: URL,
  envelopeVersion: UInt16 = 1
) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  let payload = try encoder.encode(value)
  let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
  try encoder.encode(LegacyEnvelope(
    schemaVersion: envelopeVersion,
    payload: payload,
    payloadSHA256: digest
  )).write(to: url, options: .atomic)
}
