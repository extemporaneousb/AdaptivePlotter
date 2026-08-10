import CryptoKit
import Foundation
import PlotterModel

public enum ControllerCheckpointContextError: Error, Equatable, Sendable {
  case probeBlocked
  case missingCompletedQuery(PassiveQuery)
  case emptyEvidence(PassiveQuery)
}

/// Passive controller facts that must remain numerically and textually stable
/// before a parked accepted-artifact checkpoint can become current again.
/// Status/MPos is compared separately because it changes during legitimate
/// accepted operations.
public struct ControllerCheckpointContext: Codable, Hashable, Sendable {
  public static let revision = "grbl-passive-context-v1"

  public let link: MachineLinkDescriptor
  public let buildInfo: [String]
  public let parserState: [String]
  public let configuration: [String]
  public let coordinateOffsets: [String]
  public let revision: String

  public init(probe: PassiveProbeResult) throws {
    guard probe.blockers.isEmpty else { throw ControllerCheckpointContextError.probeBlocked }
    link = probe.link
    buildInfo = try Self.evidence(for: .buildInfo, in: probe)
    parserState = try Self.evidence(for: .parserState, in: probe)
    configuration = try Self.evidence(for: .configuration, in: probe)
    coordinateOffsets = try Self.evidence(for: .coordinateOffsets, in: probe)
    _ = try Self.evidence(for: .status, in: probe)
    revision = Self.revision
  }

  private static func evidence(
    for query: PassiveQuery,
    in probe: PassiveProbeResult
  ) throws -> [String] {
    guard let exchange = probe.exchanges.first(where: { $0.query == query }),
      exchange.completed,
      exchange.blocker == nil
    else { throw ControllerCheckpointContextError.missingCompletedQuery(query) }
    let evidence = exchange.lines.compactMap { line -> String? in
      guard line.kind != .acknowledgement else { return nil }
      let normalized = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      return normalized.isEmpty ? nil : normalized
    }.sorted()
    guard !evidence.isEmpty else { throw ControllerCheckpointContextError.emptyEvidence(query) }
    return evidence
  }
}

public enum AcceptedArtifactCheckpointCompatibility: Equatable, Sendable {
  case compatible(residualMM: Double)
  case incompatible(String)
}

public enum AcceptedArtifactCheckpointValidationError: Error, Equatable, Sendable {
  case unsupportedSchema(UInt16)
  case unsupportedAlgorithm(String)
  case noAcceptedBoundaryArtifacts
  case duplicateDirection(BoundaryDirection)
  case duplicateAttemptEvidence(ExerciseAttemptID)
  case missingAttemptEvidence(ExerciseAttemptID)
  case aggregateEvidenceMismatch(BoundaryDirection)
  case controllerContextMismatch
  case invalidProgress
  case invalidDerivedCenter
  case invalidLocalFrame
  case invalidRevisionSet
}

/// Durable payload for accepted machine-space learning only. It deliberately
/// has no transaction, operation owner, active Stop capability, authorization,
/// pending command, or recovery instruction field.
public struct AcceptedMachineArtifactCheckpoint: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 1
  public static let algorithmRevision = "accepted-machine-artifacts-v1"
  public static let revalidationPositionToleranceMM = 0.05

  public let schemaVersion: UInt16
  public let algorithmRevision: String
  public let checkpointID: UUID
  public let controllerContext: ControllerCheckpointContext
  public let machinePositionAtSave: MachinePosition
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let acceptedAttemptSequence: UInt64
  public let pairedBoundaryProgress: PairedBoundaryProgress
  public let acceptedBoundaryEvidence: [BoundarySideAttemptEvidence]
  public let boundarySideAggregates: [BoundarySideAggregate]
  public let estimatedMachineCenter: EstimatedMachineCenter?
  public let learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame?
  public let centerArrivalPosition: MachinePosition?
  public let acceptedRevisions: [LearningArtifactRevision]

  public init(
    checkpointID: UUID = UUID(),
    controllerContext: ControllerCheckpointContext,
    machinePositionAtSave: MachinePosition,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    acceptedAttemptSequence: UInt64,
    pairedBoundaryProgress: PairedBoundaryProgress,
    acceptedBoundaryEvidence: [BoundarySideAttemptEvidence],
    boundarySideAggregates: [BoundarySideAggregate],
    estimatedMachineCenter: EstimatedMachineCenter?,
    learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame?,
    centerArrivalPosition: MachinePosition?,
    acceptedRevisions: [LearningArtifactRevision]
  ) throws {
    schemaVersion = Self.schemaVersion
    algorithmRevision = Self.algorithmRevision
    self.checkpointID = checkpointID
    self.controllerContext = controllerContext
    self.machinePositionAtSave = machinePositionAtSave
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.acceptedAttemptSequence = acceptedAttemptSequence
    self.pairedBoundaryProgress = pairedBoundaryProgress
    self.acceptedBoundaryEvidence = acceptedBoundaryEvidence
    self.boundarySideAggregates = boundarySideAggregates
    self.estimatedMachineCenter = estimatedMachineCenter
    self.learnedLocalCoordinateFrame = learnedLocalCoordinateFrame
    self.centerArrivalPosition = centerArrivalPosition
    self.acceptedRevisions = acceptedRevisions
    try validate()
  }

  public func compatibility(
    with freshContext: ControllerCheckpointContext,
    currentPosition: MachinePosition
  ) -> AcceptedArtifactCheckpointCompatibility {
    guard controllerContext == freshContext else {
      return .incompatible(
        "The selected device, build information, parser state, settings, or coordinate offsets changed."
      )
    }
    let residual = machinePositionAtSave.point.distance(to: currentPosition.point)
    guard residual.isFinite, residual <= Self.revalidationPositionToleranceMM else {
      return .incompatible(
        String(
          format: "Controller MPos differs by %.3f mm; checkpoint tolerance is %.3f mm.",
          residual,
          Self.revalidationPositionToleranceMM
        )
      )
    }
    return .compatible(residualMM: residual)
  }

  public func restoredBoundaryHistories()
    throws -> [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<BoundarySideAttemptEvidence>]]
  {
    let evidenceByID = Dictionary(uniqueKeysWithValues: acceptedBoundaryEvidence.map {
      ($0.attemptID, $0)
    })
    var histories:
      [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<BoundarySideAttemptEvidence>]] = [:]
    var sequence: UInt64 = 0
    for aggregate in boundarySideAggregates.sorted(by: { $0.direction.rawValue < $1.direction.rawValue }) {
      let compatibility = aggregate.numericCompatibility.attemptCompatibility
      var history = try ExerciseAttemptHistory<BoundarySideAttemptEvidence>(
        compatibility: compatibility
      )
      for attemptID in aggregate.includedAttemptIDs {
        guard let evidence = evidenceByID[attemptID] else {
          throw AcceptedArtifactCheckpointValidationError.missingAttemptEvidence(attemptID)
        }
        sequence &+= 1
        try history.record(
          ExerciseAttempt(
            id: attemptID,
            disposition: .succeeded,
            compatibility: compatibility,
            acceptedSequence: sequence,
            value: evidence
          )
        )
      }
      histories[aggregate.direction] = [compatibility: history]
    }
    return histories
  }

  public func restoredLearningGraph() throws -> LearningDependencyGraph {
    var graph = LearningDependencyGraph()
    let order: [LearningArtifactKind] =
      BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
      + [.estimatedMachineCenter, .centerArrival]
    for kind in order {
      guard let revision = acceptedRevisions.first(where: { $0.kind == kind }) else { continue }
      _ = try graph.commitReplacement(
        LearningArtifactRevision(
          id: revision.id,
          kind: revision.kind,
          attemptID: revision.attemptID,
          disposition: revision.disposition,
          consumedRevisionIDs: revision.consumedRevisionIDs
        )
      )
    }
    return graph
  }

  public func validate() throws {
    guard schemaVersion == Self.schemaVersion else {
      throw AcceptedArtifactCheckpointValidationError.unsupportedSchema(schemaVersion)
    }
    guard algorithmRevision == Self.algorithmRevision else {
      throw AcceptedArtifactCheckpointValidationError.unsupportedAlgorithm(algorithmRevision)
    }
    guard !boundarySideAggregates.isEmpty else {
      throw AcceptedArtifactCheckpointValidationError.noAcceptedBoundaryArtifacts
    }
    guard Set(boundarySideAggregates.map(\.direction)).count == boundarySideAggregates.count else {
      throw AcceptedArtifactCheckpointValidationError.duplicateDirection(
        boundarySideAggregates.first!.direction
      )
    }
    var seenAttemptIDs: Set<ExerciseAttemptID> = []
    if let duplicateAttemptID = acceptedBoundaryEvidence.first(where: {
      !seenAttemptIDs.insert($0.attemptID).inserted
    })?.attemptID {
      throw AcceptedArtifactCheckpointValidationError.duplicateAttemptEvidence(
        duplicateAttemptID
      )
    }
    guard pairedBoundaryProgress.acceptedDirections.count == boundarySideAggregates.count,
      Set(pairedBoundaryProgress.acceptedDirections) == Set(boundarySideAggregates.map(\.direction))
    else { throw AcceptedArtifactCheckpointValidationError.invalidProgress }
    let evidenceByID = Dictionary(uniqueKeysWithValues: acceptedBoundaryEvidence.map {
      ($0.attemptID, $0)
    })
    for aggregate in boundarySideAggregates {
      guard aggregate.controllerSessionID == controllerSessionID,
        aggregate.coordinateRevision == coordinateRevision,
        pairedBoundaryProgress.acceptedRevisionIDs[aggregate.direction] == aggregate.revisionID,
        !aggregate.includedAttemptIDs.isEmpty
      else { throw AcceptedArtifactCheckpointValidationError.controllerContextMismatch }
      for attemptID in aggregate.includedAttemptIDs {
        guard let evidence = evidenceByID[attemptID] else {
          throw AcceptedArtifactCheckpointValidationError.missingAttemptEvidence(attemptID)
        }
        guard evidence.direction == aggregate.direction,
          evidence.controllerSessionID == controllerSessionID,
          evidence.coordinateRevision == coordinateRevision,
          evidence.disposition == .succeeded
        else {
          throw AcceptedArtifactCheckpointValidationError.aggregateEvidenceMismatch(
            aggregate.direction
          )
        }
      }
    }
    if let estimatedMachineCenter {
      guard boundarySideAggregates.count == BoundaryDirection.allCases.count,
        try EstimatedMachineCenter.derive(from: boundarySideAggregates) == estimatedMachineCenter
      else { throw AcceptedArtifactCheckpointValidationError.invalidDerivedCenter }
    }
    if let learnedLocalCoordinateFrame {
      guard boundarySideAggregates.count == BoundaryDirection.allCases.count,
        try LearnedLocalCoordinateFrame.derive(from: boundarySideAggregates)
          == learnedLocalCoordinateFrame
      else { throw AcceptedArtifactCheckpointValidationError.invalidLocalFrame }
    }
    let allowedKinds: Set<LearningArtifactKind> = Set(
      BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
        + [.estimatedMachineCenter, .centerArrival]
    )
    guard acceptedRevisions.allSatisfy({
      $0.state == .current && $0.disposition == .succeeded && allowedKinds.contains($0.kind)
    }),
      Set(acceptedRevisions.map(\.kind)).count == acceptedRevisions.count
    else { throw AcceptedArtifactCheckpointValidationError.invalidRevisionSet }
    let graph = try restoredLearningGraph()
    for revision in acceptedRevisions {
      guard graph.currentRevision(for: revision.kind)?.id == revision.id else {
        throw AcceptedArtifactCheckpointValidationError.invalidRevisionSet
      }
    }
  }
}

public enum AcceptedArtifactCheckpointLoadResult: Sendable {
  case absent
  case loaded(AcceptedMachineArtifactCheckpoint)
  case rejected(String)
}

public struct AcceptedArtifactCheckpointStore: Sendable {
  private struct Envelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() -> AcceptedArtifactCheckpointLoadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
    do {
      let data = try Data(contentsOf: fileURL)
      let envelope = try JSONDecoder().decode(Envelope.self, from: data)
      guard envelope.schemaVersion == AcceptedMachineArtifactCheckpoint.schemaVersion else {
        return .rejected("Unsupported checkpoint envelope schema \(envelope.schemaVersion).")
      }
      let digest = Self.sha256(envelope.payload)
      guard digest == envelope.payloadSHA256 else {
        return .rejected("Checkpoint integrity verification failed.")
      }
      let checkpoint = try JSONDecoder().decode(
        AcceptedMachineArtifactCheckpoint.self,
        from: envelope.payload
      )
      try checkpoint.validate()
      return .loaded(checkpoint)
    } catch {
      return .rejected("Checkpoint could not be decoded: \(error)")
    }
  }

  public func save(_ checkpoint: AcceptedMachineArtifactCheckpoint) throws {
    try checkpoint.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(checkpoint)
    let envelope = Envelope(
      schemaVersion: AcceptedMachineArtifactCheckpoint.schemaVersion,
      payload: payload,
      payloadSHA256: Self.sha256(payload)
    )
    let encoded = try encoder.encode(envelope)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try encoded.write(to: fileURL, options: [.atomic])
  }

  /// Removes the durable authority file. Absence is already the cleared state,
  /// so repeated explicit resets are idempotent.
  public func clear() throws {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    try FileManager.default.removeItem(at: fileURL)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
