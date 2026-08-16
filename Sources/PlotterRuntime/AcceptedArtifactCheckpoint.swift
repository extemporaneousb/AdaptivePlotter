import Foundation
import PlotterModel

public enum ControllerCheckpointContextError: Error, Equatable, Sendable {
  case probeBlocked
  case missingCompletedQuery(PassiveQuery)
  case emptyEvidence(PassiveQuery)
}

public enum ControllerCheckpointContextField: String, Codable, CaseIterable, Hashable, Sendable {
  case revision
  case link
  case buildInfo
  case parserCoordinateState
  case configuration
  case coordinateOffsets

  public var displayName: String {
    switch self {
    case .revision: "context schema"
    case .link: "selected controller"
    case .buildInfo: "controller build information"
    case .parserCoordinateState: "parser coordinate state"
    case .configuration: "controller settings"
    case .coordinateOffsets: "coordinate offsets"
    }
  }
}

public struct ControllerCheckpointContextDifference: Codable, Hashable, Sendable {
  public let field: ControllerCheckpointContextField
  public let baseline: [String]
  public let refreshed: [String]

  public init(
    field: ControllerCheckpointContextField,
    baseline: [String],
    refreshed: [String]
  ) {
    self.field = field
    self.baseline = baseline
    self.refreshed = refreshed
  }

  public var actionableDescription: String {
    "\(field.displayName) changed from \(Self.render(baseline)) to \(Self.render(refreshed))"
  }

  private static func render(_ values: [String]) -> String {
    values.isEmpty ? "<none>" : values.joined(separator: " | ")
  }
}

/// A field-level comparison of controller facts. Raw parser text is retained
/// for provenance, but application-owned modal values are not allowed to make
/// coordinate identity unstable after the app itself actuates the pen or runs
/// a typed motion command.
public struct ControllerCheckpointContextComparison: Codable, Hashable, Sendable {
  public let differences: [ControllerCheckpointContextDifference]
  public let ignoredApplicationParserChanges: [ControllerCheckpointContextDifference]

  public init(
    differences: [ControllerCheckpointContextDifference],
    ignoredApplicationParserChanges: [ControllerCheckpointContextDifference]
  ) {
    self.differences = differences
    self.ignoredApplicationParserChanges = ignoredApplicationParserChanges
  }

  public var isCompatible: Bool { differences.isEmpty }

  public var actionableDescription: String {
    guard !differences.isEmpty else {
      if ignoredApplicationParserChanges.isEmpty {
        return "Controller coordinate context is compatible."
      }
      return
        "Controller coordinate context is compatible; only application-owned parser modes changed."
    }
    return differences.map(\.actionableDescription).joined(separator: "; ") + "."
  }
}

/// An operation-scoped controller-context baseline. It is intentionally a
/// value supplied by the caller instead of an implicit reference to the
/// workspace's most recent probe.
public struct ControllerContextBaseline: Codable, Hashable, Sendable {
  public let probeID: UUID
  public let context: ControllerCheckpointContext

  public init(probe: PassiveProbeResult) throws {
    probeID = probe.probeID
    context = try ControllerCheckpointContext(probe: probe)
  }
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

  public func comparison(with refreshed: ControllerCheckpointContext)
    -> ControllerCheckpointContextComparison
  {
    var differences: [ControllerCheckpointContextDifference] = []
    Self.appendDifference(
      .revision,
      baseline: [revision],
      refreshed: [refreshed.revision],
      to: &differences
    )
    Self.appendDifference(
      .link,
      baseline: Self.linkEvidence(link),
      refreshed: Self.linkEvidence(refreshed.link),
      to: &differences
    )
    Self.appendDifference(
      .buildInfo,
      baseline: buildInfo,
      refreshed: refreshed.buildInfo,
      to: &differences
    )

    let baselineParser = Self.semanticParserState(parserState)
    let refreshedParser = Self.semanticParserState(refreshed.parserState)
    Self.appendDifference(
      .parserCoordinateState,
      baseline: baselineParser.coordinateContext,
      refreshed: refreshedParser.coordinateContext,
      to: &differences
    )
    Self.appendDifference(
      .configuration,
      baseline: configuration,
      refreshed: refreshed.configuration,
      to: &differences
    )
    Self.appendDifference(
      .coordinateOffsets,
      baseline: coordinateOffsets,
      refreshed: refreshed.coordinateOffsets,
      to: &differences
    )

    var ignored: [ControllerCheckpointContextDifference] = []
    Self.appendDifference(
      .parserCoordinateState,
      baseline: baselineParser.applicationOwned,
      refreshed: refreshedParser.applicationOwned,
      to: &ignored
    )
    return ControllerCheckpointContextComparison(
      differences: differences,
      ignoredApplicationParserChanges: ignored
    )
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

  private static func appendDifference(
    _ field: ControllerCheckpointContextField,
    baseline: [String],
    refreshed: [String],
    to differences: inout [ControllerCheckpointContextDifference]
  ) {
    guard baseline != refreshed else { return }
    differences.append(
      ControllerCheckpointContextDifference(
        field: field,
        baseline: baseline,
        refreshed: refreshed
      )
    )
  }

  private static func linkEvidence(_ link: MachineLinkDescriptor) -> [String] {
    [
      "identifier=\(link.identifier)",
      "displayName=\(link.displayName)",
      "bsdPath=\(link.bsdPath ?? "<none>")",
      "transport=\(link.transport.rawValue)",
    ]
  }

  private static func semanticParserState(
    _ evidence: [String]
  ) -> (coordinateContext: [String], applicationOwned: [String]) {
    var coordinateContext: [String] = []
    var applicationOwned: [String] = []
    for line in evidence {
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard trimmed.hasPrefix("[GC:"), trimmed.hasSuffix("]") else {
        coordinateContext.append(trimmed)
        continue
      }
      let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
      let end = trimmed.index(before: trimmed.endIndex)
      for token in trimmed[start..<end].split(whereSeparator: \.isWhitespace).map(String.init) {
        if applicationOwnsParserToken(token) {
          applicationOwned.append(token)
        } else {
          coordinateContext.append(token)
        }
      }
    }
    return (coordinateContext.sorted(), applicationOwned.sorted())
  }

  private static func applicationOwnsParserToken(_ token: String) -> Bool {
    let value = token.uppercased()
    if value.hasPrefix("S") || value.hasPrefix("F") { return true }
    if ["M3", "M4", "M5"].contains(value) { return true }
    // Typed app requests always provide their own motion mode. These modal
    // tokens can legitimately change after an app-owned travel or stroke but
    // do not change units, distance mode, work coordinates, or offsets.
    if ["G0", "G00", "G1", "G01", "G2", "G02", "G3", "G03", "G80"].contains(value) {
      return true
    }
    return value.hasPrefix("G38.")
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
    let contextComparison = controllerContext.comparison(with: freshContext)
    guard contextComparison.isCompatible else {
      return .incompatible(contextComparison.actionableDescription)
    }
    let residual = ControllerPositionAcceptancePolicy.residualMM(
      currentPosition,
      from: machinePositionAtSave
    )
    guard ControllerPositionAcceptancePolicy.accepts(residualMM: residual) else {
      return .incompatible(
        String(
          format: "Controller MPos differs by %.3f mm; checkpoint tolerance is %.3f mm.",
          residual,
          ControllerPositionAcceptancePolicy.toleranceMM
        )
      )
    }
    return .compatible(residualMM: residual)
  }

  public func restoredBoundaryHistories()
    throws -> [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<
      BoundarySideAttemptEvidence
    >]]
  {
    let evidenceByID = Dictionary(
      uniqueKeysWithValues: acceptedBoundaryEvidence.map {
        ($0.attemptID, $0)
      })
    var histories:
      [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<
        BoundarySideAttemptEvidence
      >]] = [:]
    var sequence: UInt64 = 0
    for aggregate in boundarySideAggregates.sorted(by: {
      $0.direction.rawValue < $1.direction.rawValue
    }) {
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
    let evidenceByID = Dictionary(
      uniqueKeysWithValues: acceptedBoundaryEvidence.map {
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
    guard
      acceptedRevisions.allSatisfy({
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
