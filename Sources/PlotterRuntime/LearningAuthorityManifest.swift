import CryptoKit
import Foundation

public struct LearningAuthorityManifest: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 1

  public let schemaVersion: UInt16
  public let generation: UInt64
  public let machine: AcceptedMachineArtifactCheckpoint?
  public let tip: AcceptedTipCalibrationCheckpoint?

  public init(
    schemaVersion: UInt16 = Self.schemaVersion,
    generation: UInt64,
    machine: AcceptedMachineArtifactCheckpoint?,
    tip: AcceptedTipCalibrationCheckpoint?
  ) throws {
    self.schemaVersion = schemaVersion
    self.generation = generation
    self.machine = machine
    self.tip = tip
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == Self.schemaVersion else {
      throw LearningAuthorityManifestError.unsupportedSchema(schemaVersion)
    }
    try machine?.validate()
    try tip?.validate()
  }
}

public enum LearningAuthorityStoreRevision: Codable, Hashable, Sendable {
  case absent
  case valid(generation: UInt64, payloadSHA256: String)
  case corrupt(fileSHA256: String)
}

public struct LearningAuthorityManifestSnapshot: Hashable, Sendable {
  public let manifest: LearningAuthorityManifest
  public let revision: LearningAuthorityStoreRevision

  public init(
    manifest: LearningAuthorityManifest,
    revision: LearningAuthorityStoreRevision
  ) {
    self.manifest = manifest
    self.revision = revision
  }
}

public enum LearningAuthorityManifestLoadResult: Sendable {
  case loaded(LearningAuthorityManifestSnapshot)
  case rejected(reason: String, revision: LearningAuthorityStoreRevision)
}

public enum LearningAuthorityManifestFieldMutation<Value: Sendable>: Sendable {
  case preserve
  case replace(Value?)
}

public struct LearningAuthorityManifestMutation: Sendable {
  public let machine:
    LearningAuthorityManifestFieldMutation<AcceptedMachineArtifactCheckpoint>
  public let tip:
    LearningAuthorityManifestFieldMutation<AcceptedTipCalibrationCheckpoint>

  public init(
    machine: LearningAuthorityManifestFieldMutation<AcceptedMachineArtifactCheckpoint> = .preserve,
    tip: LearningAuthorityManifestFieldMutation<AcceptedTipCalibrationCheckpoint> = .preserve
  ) {
    self.machine = machine
    self.tip = tip
  }
}

public enum LearningAuthorityManifestError: Error, Equatable, Sendable {
  case unsupportedSchema(UInt16)
  case staleRevision(
    expected: LearningAuthorityStoreRevision,
    actual: LearningAuthorityStoreRevision
  )
  case corruptManifestCannotPreserveFields
  case generationOverflow
}

/// One crash-atomic accepted Learning-authority store. Machine and tip payloads
/// are never cleared or restored independently: every successful mutation
/// replaces one complete generation through a single atomic rename.
public struct LearningAuthorityManifestStore: Sendable {
  private struct Envelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  public let fileURL: URL
  private let storeLock: PathScopedAtomicStoreLock

  public init(fileURL: URL) {
    self.fileURL = fileURL
    storeLock = PathScopedAtomicStoreLock(dataFileURL: fileURL)
  }

  public func load() -> LearningAuthorityManifestLoadResult {
    do {
      return try storeLock.withLock { readState().result }
    } catch {
      return .rejected(
        reason: "Learning-authority manifest lock failed: \(error)",
        revision: .corrupt(fileSHA256: "lock-unavailable")
      )
    }
  }

  public func commit(
    expectedRevision: LearningAuthorityStoreRevision,
    mutation: LearningAuthorityManifestMutation
  ) throws -> LearningAuthorityManifestSnapshot {
    try storeLock.withLock {
      let current = readState()
      guard current.revision == expectedRevision else {
        throw LearningAuthorityManifestError.staleRevision(
          expected: expectedRevision,
          actual: current.revision
        )
      }

      let prior: LearningAuthorityManifest?
      switch current.result {
      case .loaded(let snapshot):
        prior = snapshot.manifest
      case .rejected:
        guard case .replace = mutation.machine, case .replace = mutation.tip else {
          throw LearningAuthorityManifestError.corruptManifestCannotPreserveFields
        }
        prior = nil
      }

      let machine = try applying(mutation.machine, to: prior?.machine)
      let tip = try applying(mutation.tip, to: prior?.tip)
      let priorGeneration = prior?.generation ?? 0
      guard priorGeneration < UInt64.max else {
        throw LearningAuthorityManifestError.generationOverflow
      }
      let manifest = try LearningAuthorityManifest(
        generation: priorGeneration + 1,
        machine: machine,
        tip: tip
      )
      let encoded = try encode(manifest)
      try encoded.fileData.write(to: fileURL, options: [.atomic])
      return LearningAuthorityManifestSnapshot(
        manifest: manifest,
        revision: .valid(
          generation: manifest.generation,
          payloadSHA256: encoded.payloadSHA256
        )
      )
    }
  }

  private func applying<Value: Sendable>(
    _ mutation: LearningAuthorityManifestFieldMutation<Value>,
    to prior: Value?
  ) throws -> Value? {
    switch mutation {
    case .preserve: prior
    case .replace(let value): value
    }
  }

  private func readState() -> (
    result: LearningAuthorityManifestLoadResult,
    revision: LearningAuthorityStoreRevision
  ) {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      let manifest = try! LearningAuthorityManifest(generation: 0, machine: nil, tip: nil)
      return (
        .loaded(LearningAuthorityManifestSnapshot(manifest: manifest, revision: .absent)),
        .absent
      )
    }
    do {
      let fileData = try Data(contentsOf: fileURL)
      let envelope = try JSONDecoder().decode(Envelope.self, from: fileData)
      guard envelope.schemaVersion == LearningAuthorityManifest.schemaVersion else {
        throw LearningAuthorityManifestError.unsupportedSchema(envelope.schemaVersion)
      }
      guard Self.sha256(envelope.payload) == envelope.payloadSHA256 else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let manifest = try JSONDecoder().decode(
        LearningAuthorityManifest.self,
        from: envelope.payload
      )
      try manifest.validate()
      let revision = LearningAuthorityStoreRevision.valid(
        generation: manifest.generation,
        payloadSHA256: envelope.payloadSHA256
      )
      return (
        .loaded(LearningAuthorityManifestSnapshot(manifest: manifest, revision: revision)),
        revision
      )
    } catch {
      let raw = (try? Data(contentsOf: fileURL)) ?? Data()
      let revision = LearningAuthorityStoreRevision.corrupt(
        fileSHA256: Self.sha256(raw)
      )
      return (
        .rejected(
          reason: "Learning-authority manifest could not be validated: \(error)",
          revision: revision
        ),
        revision
      )
    }
  }

  private func encode(
    _ manifest: LearningAuthorityManifest
  ) throws -> (fileData: Data, payloadSHA256: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(manifest)
    let digest = Self.sha256(payload)
    let envelope = Envelope(
      schemaVersion: LearningAuthorityManifest.schemaVersion,
      payload: payload,
      payloadSHA256: digest
    )
    return (try encoder.encode(envelope), digest)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
