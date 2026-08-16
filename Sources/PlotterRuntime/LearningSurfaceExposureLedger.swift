import CryptoKit
import Foundation

public struct LearningSurfaceExposureID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum LearningSurfaceExposureProvenance: String, Codable, Hashable, Sendable {
  /// A conservative reservation made before a LIVE Pen Down command. The
  /// geometry remains possible physical ink even if later controller evidence
  /// is incomplete or the process exits mid-operation.
  case livePossiblePhysicalInk
  /// Simulator geometry used by the same no-redraw planners. It is explicitly
  /// nonphysical and is rejected by the LIVE durable store.
  case simulatedNonphysical
}

public enum LearningSurfaceExposureOwner: Codable, Hashable, Sendable {
  case sparseTipMark(ToolContactCalibrationPosition)
  case drawingTrial(AttemptGroupIdentity)
}

public enum LearningSurfaceExposureGeometry: Codable, Hashable, Sendable {
  case sparseCalibrationCircle(center: MachinePosition, radiusMM: Double)
  case isolatedLine(startPosition: MachinePosition, endPosition: MachinePosition)
}

public enum LearningSurfacePenUpFinalizationReason: String, Codable, Hashable, Sendable {
  case penLowerTerminal
  case drawingStrokeAdmissionRejected
  case drawingStrokeCompleted
  case drawingStrokeCancelled
  case drawingStrokeAmbiguous
  case drawingStrokeRefused
  case circleDrawingFailed
  case circleCompleted
}

public struct LearningSurfacePenUpFinalization: Codable, Hashable, Sendable {
  public let reason: LearningSurfacePenUpFinalizationReason
  public let outcome: PenOutcome
  public let attemptedNanoseconds: UInt64

  public init(
    reason: LearningSurfacePenUpFinalizationReason,
    outcome: PenOutcome,
    attemptedNanoseconds: UInt64
  ) {
    self.reason = reason
    self.outcome = outcome
    self.attemptedNanoseconds = attemptedNanoseconds
  }
}

public struct LearningSurfaceExposure: Codable, Hashable, Sendable {
  public let id: LearningSurfaceExposureID
  public let provenance: LearningSurfaceExposureProvenance
  public let paperContactPlane: PaperContactPlaneRevision
  public let owner: LearningSurfaceExposureOwner
  public let geometry: LearningSurfaceExposureGeometry
  public let reservedNanoseconds: UInt64
  public let penUpFinalization: LearningSurfacePenUpFinalization?

  public init(
    id: LearningSurfaceExposureID = LearningSurfaceExposureID(),
    provenance: LearningSurfaceExposureProvenance,
    paperContactPlane: PaperContactPlaneRevision,
    owner: LearningSurfaceExposureOwner,
    geometry: LearningSurfaceExposureGeometry,
    reservedNanoseconds: UInt64,
    penUpFinalization: LearningSurfacePenUpFinalization? = nil
  ) throws {
    self.id = id
    self.provenance = provenance
    self.paperContactPlane = paperContactPlane
    self.owner = owner
    self.geometry = geometry
    self.reservedNanoseconds = reservedNanoseconds
    self.penUpFinalization = penUpFinalization
    try validate()
  }

  fileprivate func validate() throws {
    switch (owner, geometry) {
    case (.sparseTipMark, .sparseCalibrationCircle(_, let radiusMM)):
      guard radiusMM.isFinite, radiusMM > 0 else {
        throw LearningSurfaceExposureLedgerError.invalidGeometry(id)
      }
    case (.drawingTrial, .isolatedLine(let start, let end)):
      guard start != end else {
        throw LearningSurfaceExposureLedgerError.invalidGeometry(id)
      }
    default:
      throw LearningSurfaceExposureLedgerError.ownerGeometryMismatch(id)
    }
  }

  fileprivate func recordingPenUpFinalization(
    _ finalization: LearningSurfacePenUpFinalization
  ) throws -> Self {
    guard penUpFinalization == nil else {
      throw LearningSurfaceExposureLedgerError.duplicatePenUpFinalization(id)
    }
    return try Self(
      id: id,
      provenance: provenance,
      paperContactPlane: paperContactPlane,
      owner: owner,
      geometry: geometry,
      reservedNanoseconds: reservedNanoseconds,
      penUpFinalization: finalization
    )
  }
}

public enum LearningSurfaceExposureLedgerError: Error, Equatable, Sendable {
  case duplicateExposureID(LearningSurfaceExposureID)
  case duplicateOwnerOnPaper(LearningSurfaceExposureOwner, PaperContactPlaneRevision)
  case missingExposure(LearningSurfaceExposureID)
  case duplicatePenUpFinalization(LearningSurfaceExposureID)
  case ownerGeometryMismatch(LearningSurfaceExposureID)
  case invalidGeometry(LearningSurfaceExposureID)
  case nonLiveEntryInLiveStore(LearningSurfaceExposureID)
  case unsupportedSchema(UInt16)
  case corruptStoreRequiresPaperReplacement
  case recoveryRequiresCorruptStore
  case generationOverflow
  case staleStoreRevision(
    expected: LiveLearningSurfaceExposureStoreRevision,
    actual: LiveLearningSurfaceExposureStoreRevision
  )
}

/// The sole active-session no-redraw authority for Learning-created surface
/// exposure. Both LIVE and SIMULATED sessions use this value type; persistence
/// is a separate LIVE-only boundary.
public struct LearningSurfaceExposureLedger: Codable, Hashable, Sendable {
  public private(set) var entries: [LearningSurfaceExposure]

  public init() {
    entries = []
  }

  public init(entries: [LearningSurfaceExposure]) throws {
    self.entries = entries
    try validate()
  }

  public mutating func reserve(_ exposure: LearningSurfaceExposure) throws {
    guard !entries.contains(where: { $0.id == exposure.id }) else {
      throw LearningSurfaceExposureLedgerError.duplicateExposureID(exposure.id)
    }
    guard !entries.contains(where: {
      $0.paperContactPlane == exposure.paperContactPlane && $0.owner == exposure.owner
    }) else {
      throw LearningSurfaceExposureLedgerError.duplicateOwnerOnPaper(
        exposure.owner,
        exposure.paperContactPlane
      )
    }
    try exposure.validate()
    entries.append(exposure)
  }

  public mutating func recordPenUpFinalization(
    for id: LearningSurfaceExposureID,
    finalization: LearningSurfacePenUpFinalization
  ) throws {
    guard let index = entries.firstIndex(where: { $0.id == id }) else {
      throw LearningSurfaceExposureLedgerError.missingExposure(id)
    }
    entries[index] = try entries[index].recordingPenUpFinalization(finalization)
  }

  public func exposures(
    on paperContactPlane: PaperContactPlaneRevision
  ) -> [LearningSurfaceExposure] {
    entries.filter { $0.paperContactPlane == paperContactPlane }
  }

  public func validate() throws {
    var ids: Set<LearningSurfaceExposureID> = []
    var ownersByPaper: Set<OwnerOnPaper> = []
    for entry in entries {
      try entry.validate()
      guard ids.insert(entry.id).inserted else {
        throw LearningSurfaceExposureLedgerError.duplicateExposureID(entry.id)
      }
      let ownerOnPaper = OwnerOnPaper(
        owner: entry.owner,
        paperContactPlane: entry.paperContactPlane
      )
      guard ownersByPaper.insert(ownerOnPaper).inserted else {
        throw LearningSurfaceExposureLedgerError.duplicateOwnerOnPaper(
          entry.owner,
          entry.paperContactPlane
        )
      }
    }
  }

  private struct OwnerOnPaper: Hashable {
    let owner: LearningSurfaceExposureOwner
    let paperContactPlane: PaperContactPlaneRevision
  }
}

public struct LiveLearningSurfaceExposureCheckpoint: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 1

  public let schemaVersion: UInt16
  public let generation: UInt64
  public let currentPaperContactPlane: PaperContactPlaneRevision
  public let ledger: LearningSurfaceExposureLedger

  public init(
    schemaVersion: UInt16 = Self.schemaVersion,
    generation: UInt64,
    currentPaperContactPlane: PaperContactPlaneRevision,
    ledger: LearningSurfaceExposureLedger
  ) throws {
    self.schemaVersion = schemaVersion
    self.generation = generation
    self.currentPaperContactPlane = currentPaperContactPlane
    self.ledger = ledger
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == Self.schemaVersion else {
      throw LearningSurfaceExposureLedgerError.unsupportedSchema(schemaVersion)
    }
    try ledger.validate()
    for entry in ledger.entries where entry.provenance != .livePossiblePhysicalInk {
      throw LearningSurfaceExposureLedgerError.nonLiveEntryInLiveStore(entry.id)
    }
  }
}

public struct LiveLearningSurfaceExposureSnapshot: Hashable, Sendable {
  public let checkpoint: LiveLearningSurfaceExposureCheckpoint
  public let revision: LiveLearningSurfaceExposureStoreRevision

  public init(
    checkpoint: LiveLearningSurfaceExposureCheckpoint,
    revision: LiveLearningSurfaceExposureStoreRevision
  ) {
    self.checkpoint = checkpoint
    self.revision = revision
  }
}

public enum LiveLearningSurfaceExposureStoreRevision: Hashable, Sendable {
  case absent
  case valid(generation: UInt64, payloadSHA256: String)
  case corrupt(fileSHA256: String)
}

public enum LiveLearningSurfaceExposureLoadResult: Sendable {
  case absent
  case loaded(LiveLearningSurfaceExposureSnapshot)
  case rejected(reason: String, revision: LiveLearningSurfaceExposureStoreRevision)
}

/// Checksum-protected, atomic LIVE safety persistence. There is deliberately
/// no clear operation: explicit paper replacement changes applicability while
/// preserving the prior paper's exposure history.
public struct LiveLearningSurfaceExposureStore: Sendable {
  private struct Envelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  public let fileURL: URL
  public let corruptArchiveDirectoryURL: URL
  private let storeLock: PathScopedAtomicStoreLock

  public init(
    fileURL: URL,
    corruptArchiveDirectoryURL: URL? = nil
  ) {
    self.fileURL = fileURL
    self.corruptArchiveDirectoryURL = corruptArchiveDirectoryURL
      ?? fileURL.deletingLastPathComponent().appendingPathComponent(
        "CorruptArchive",
        isDirectory: true
      )
    storeLock = PathScopedAtomicStoreLock(dataFileURL: fileURL)
  }

  public func load() -> LiveLearningSurfaceExposureLoadResult {
    do {
      return try storeLock.withLock { loadUnlocked() }
    } catch {
      return .rejected(
        reason: "Surface-exposure store lock failed: \(error)",
        revision: .corrupt(fileSHA256: "lock-unavailable")
      )
    }
  }

  @discardableResult
  public func save(
    expectedRevision: LiveLearningSurfaceExposureStoreRevision,
    _ ledger: LearningSurfaceExposureLedger,
    currentPaperContactPlane: PaperContactPlaneRevision
  ) throws -> LiveLearningSurfaceExposureSnapshot {
    try storeLock.withLock {
      let loaded = loadUnlocked()
      let actualRevision: LiveLearningSurfaceExposureStoreRevision = switch loaded {
      case .absent: .absent
      case .loaded(let snapshot): snapshot.revision
      case .rejected(_, let revision): revision
      }
      guard actualRevision == expectedRevision else {
        throw LearningSurfaceExposureLedgerError.staleStoreRevision(
          expected: expectedRevision,
          actual: actualRevision
        )
      }
      let generation: UInt64
      switch loaded {
      case .absent:
        generation = 1
      case .loaded(let snapshot):
        guard snapshot.checkpoint.generation < UInt64.max else {
          throw LearningSurfaceExposureLedgerError.generationOverflow
        }
        generation = snapshot.checkpoint.generation + 1
      case .rejected:
        throw LearningSurfaceExposureLedgerError.corruptStoreRequiresPaperReplacement
      }
      return try writeUnlocked(
        ledger,
        generation: generation,
        currentPaperContactPlane: currentPaperContactPlane
      )
    }
  }

  /// Explicit Paper Replacement is the only recovery for corrupt LIVE safety
  /// history. The corrupt bytes are copied to an integrity-named archive before
  /// the primary file is atomically replaced by an empty generation bound to
  /// the new paper. A crash before replacement leaves the corrupt primary in
  /// place; a crash after replacement leaves both the archive and fresh store.
  @discardableResult
  public func recoverForPaperReplacement(
    expectedRevision: LiveLearningSurfaceExposureStoreRevision,
    _ newPaperContactPlane: PaperContactPlaneRevision
  ) throws -> LiveLearningSurfaceExposureSnapshot {
    try storeLock.withLock {
      guard case .rejected(_, let actualRevision) = loadUnlocked() else {
        throw LearningSurfaceExposureLedgerError.recoveryRequiresCorruptStore
      }
      guard actualRevision == expectedRevision else {
        throw LearningSurfaceExposureLedgerError.staleStoreRevision(
          expected: expectedRevision,
          actual: actualRevision
        )
      }
      guard case .corrupt(let digest) = actualRevision else {
        throw LearningSurfaceExposureLedgerError.recoveryRequiresCorruptStore
      }
      let corruptBytes = try Data(contentsOf: fileURL)
      try FileManager.default.createDirectory(
        at: corruptArchiveDirectoryURL,
        withIntermediateDirectories: true
      )
      let archiveURL = corruptArchiveDirectoryURL.appendingPathComponent(
        "learning-surface-exposures-corrupt-\(digest).json"
      )
      if !FileManager.default.fileExists(atPath: archiveURL.path) {
        try corruptBytes.write(to: archiveURL, options: [.atomic])
      }
      return try writeUnlocked(
        LearningSurfaceExposureLedger(),
        generation: 1,
        currentPaperContactPlane: newPaperContactPlane
      )
    }
  }

  private func loadUnlocked() -> LiveLearningSurfaceExposureLoadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
    do {
      let data = try Data(contentsOf: fileURL)
      let envelope = try JSONDecoder().decode(Envelope.self, from: data)
      guard envelope.schemaVersion == LiveLearningSurfaceExposureCheckpoint.schemaVersion else {
        return .rejected(
          reason: "Unsupported surface-exposure envelope schema \(envelope.schemaVersion).",
          revision: .corrupt(fileSHA256: Self.sha256(data))
        )
      }
      guard Self.sha256(envelope.payload) == envelope.payloadSHA256 else {
        return .rejected(
          reason: "Surface-exposure checkpoint integrity verification failed.",
          revision: .corrupt(fileSHA256: Self.sha256(data))
        )
      }
      let checkpoint = try JSONDecoder().decode(
        LiveLearningSurfaceExposureCheckpoint.self,
        from: envelope.payload
      )
      try checkpoint.validate()
      let revision = LiveLearningSurfaceExposureStoreRevision.valid(
        generation: checkpoint.generation,
        payloadSHA256: envelope.payloadSHA256
      )
      return .loaded(
        LiveLearningSurfaceExposureSnapshot(checkpoint: checkpoint, revision: revision)
      )
    } catch {
      let raw = (try? Data(contentsOf: fileURL)) ?? Data()
      return .rejected(
        reason: "Surface-exposure checkpoint could not be decoded: \(error)",
        revision: .corrupt(fileSHA256: Self.sha256(raw))
      )
    }
  }

  private func writeUnlocked(
    _ ledger: LearningSurfaceExposureLedger,
    generation: UInt64,
    currentPaperContactPlane: PaperContactPlaneRevision
  ) throws -> LiveLearningSurfaceExposureSnapshot {
    let checkpoint = try LiveLearningSurfaceExposureCheckpoint(
      generation: generation,
      currentPaperContactPlane: currentPaperContactPlane,
      ledger: ledger
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(checkpoint)
    let digest = Self.sha256(payload)
    let envelope = Envelope(
      schemaVersion: LiveLearningSurfaceExposureCheckpoint.schemaVersion,
      payload: payload,
      payloadSHA256: digest
    )
    let encoded = try encoder.encode(envelope)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try encoded.write(to: fileURL, options: [.atomic])
    return LiveLearningSurfaceExposureSnapshot(
      checkpoint: checkpoint,
      revision: .valid(generation: checkpoint.generation, payloadSHA256: digest)
    )
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
