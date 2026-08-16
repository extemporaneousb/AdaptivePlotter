import Foundation
import PlotterModel

public struct ExerciseAttemptID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum ExerciseAttemptDisposition: Codable, Hashable, Sendable {
  case succeeded
  case refused(String)
  case unclear(String)
  case stopped
  case cancelled
  case ambiguous(String)
  case failed(String)

  public var contributesSuccessfulValue: Bool {
    self == .succeeded
  }
}

public struct AttemptGroupIdentity: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    precondition(!rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    self.rawValue = rawValue
  }
}

public enum AttemptCoordinateSpace: String, Codable, Hashable, Sendable {
  case machine
  case cameraPixels
  case field
  case categorical
  case currentState
}

public enum AttemptUnits: String, Codable, Hashable, Sendable {
  case millimeters
  case pixels
  case unitless
  case categorical
  case state
}

/// Exact identities that determine whether attempts may enter one aggregate.
/// A nil camera identity is explicit for observations that do not consume a frame.
public struct AttemptCompatibility: Codable, Hashable, Sendable {
  public let cameraConfigurationID: CameraConfigurationID?
  public let coordinateSpace: AttemptCoordinateSpace
  public let units: AttemptUnits
  public let group: AttemptGroupIdentity
  public let algorithmRevision: String

  public init(
    cameraConfigurationID: CameraConfigurationID?,
    coordinateSpace: AttemptCoordinateSpace,
    units: AttemptUnits,
    group: AttemptGroupIdentity,
    algorithmRevision: String
  ) {
    precondition(!algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    self.cameraConfigurationID = cameraConfigurationID
    self.coordinateSpace = coordinateSpace
    self.units = units
    self.group = group
    self.algorithmRevision = algorithmRevision
  }
}

public enum ExerciseAttemptError: Error, Hashable, Sendable {
  case successfulAttemptRequiresValue
  case duplicateAttempt(ExerciseAttemptID)
  case incompatibleAttempt(expected: AttemptCompatibility, actual: AttemptCompatibility)
  case replacementTargetNotFound(ExerciseAttemptID)
  case replacementTargetNotIncluded(ExerciseAttemptID)
  case replacementIncludedSetEmpty
}

/// One exact attempt. Unsuccessful attempts may retain a partial evidence value,
/// but only a successful disposition can include that value in an aggregate.
public struct ExerciseAttempt<Value: Hashable & Sendable>: Hashable, Sendable {
  public let id: ExerciseAttemptID
  public let disposition: ExerciseAttemptDisposition
  public let compatibility: AttemptCompatibility
  public let acceptedSequence: UInt64
  public let value: Value?

  public init(
    id: ExerciseAttemptID = ExerciseAttemptID(),
    disposition: ExerciseAttemptDisposition,
    compatibility: AttemptCompatibility,
    acceptedSequence: UInt64,
    value: Value?
  ) throws {
    if disposition.contributesSuccessfulValue, value == nil {
      throw ExerciseAttemptError.successfulAttemptRequiresValue
    }
    self.id = id
    self.disposition = disposition
    self.compatibility = compatibility
    self.acceptedSequence = acceptedSequence
    self.value = value
  }
}

public enum ExerciseAttemptInclusionState: Codable, Hashable, Sendable {
  /// A successful value currently contributes to compatible aggregates.
  case included
  /// An unsuccessful attempt remains provenance but has no successful value.
  case excludedUnsuccessful
  /// A successful value was replaced atomically by the named attempt.
  case superseded(by: ExerciseAttemptID)

  public var contributesToAggregate: Bool {
    self == .included
  }
}

public struct ExerciseAttemptRecord<Value: Hashable & Sendable>: Hashable, Sendable {
  public let attempt: ExerciseAttempt<Value>
  public fileprivate(set) var inclusionState: ExerciseAttemptInclusionState

  fileprivate init(
    attempt: ExerciseAttempt<Value>,
    inclusionState: ExerciseAttemptInclusionState
  ) {
    self.attempt = attempt
    self.inclusionState = inclusionState
  }
}

public struct ExerciseAttemptReplacementCommit: Hashable, Sendable {
  public let replacedAttemptID: ExerciseAttemptID
  public let replacementAttemptID: ExerciseAttemptID
  public let replacementDisposition: ExerciseAttemptDisposition
  public let acceptedReplacement: Bool
}

/// Result of the narrow Redo operation that replaces one complete accepted
/// aggregate input set. The former included attempts remain provenance.
public struct ExerciseAttemptWholeSetReplacementCommit: Hashable, Sendable {
  public let supersededAttemptIDs: [ExerciseAttemptID]
  public let replacementAttemptID: ExerciseAttemptID
  public let replacementDisposition: ExerciseAttemptDisposition
  public let acceptedReplacement: Bool
}

/// A compatibility-bound provenance list. Accepted artifact revisions are
/// intentionally owned separately by `LearningDependencyGraph`.
public struct ExerciseAttemptHistory<Value: Hashable & Sendable>: Sendable {
  public let compatibility: AttemptCompatibility
  public private(set) var records: [ExerciseAttemptRecord<Value>]

  /// Full attempt provenance, including unsuccessful and superseded attempts.
  public var attempts: [ExerciseAttempt<Value>] {
    records.map(\.attempt)
  }

  /// Only current successful samples. Every aggregate consumes this projection.
  public var includedSuccessfulAttempts: [ExerciseAttempt<Value>] {
    records.compactMap { record in
      guard record.inclusionState.contributesToAggregate,
        record.attempt.disposition.contributesSuccessfulValue
      else { return nil }
      return record.attempt
    }
  }

  public init(
    compatibility: AttemptCompatibility,
    attempts: [ExerciseAttempt<Value>] = []
  ) throws {
    self.compatibility = compatibility
    self.records = []
    for attempt in attempts {
      try record(attempt)
    }
  }

  /// Appends an independent attempt. A successful attempt is included (Record
  /// Another semantics); an unsuccessful attempt remains excluded provenance.
  public mutating func record(_ attempt: ExerciseAttempt<Value>) throws {
    try validateNewAttempt(attempt)
    records.append(
      ExerciseAttemptRecord(
        attempt: attempt,
        inclusionState: attempt.disposition.contributesSuccessfulValue
          ? .included
          : .excludedUnsuccessful
      )
    )
  }

  /// Records a replacement attempt atomically. Success supersedes exactly the
  /// named included sample; any unsuccessful disposition is retained as
  /// excluded provenance and leaves the accepted sample unchanged.
  @discardableResult
  public mutating func recordReplacement(
    _ replacement: ExerciseAttempt<Value>,
    replacing replacedAttemptID: ExerciseAttemptID
  ) throws -> ExerciseAttemptReplacementCommit {
    try validateNewAttempt(replacement)
    guard let targetIndex = records.firstIndex(where: {
      $0.attempt.id == replacedAttemptID
    }) else {
      throw ExerciseAttemptError.replacementTargetNotFound(replacedAttemptID)
    }
    guard records[targetIndex].inclusionState == .included,
      records[targetIndex].attempt.disposition.contributesSuccessfulValue
    else {
      throw ExerciseAttemptError.replacementTargetNotIncluded(replacedAttemptID)
    }

    var updatedRecords = records
    let acceptedReplacement = replacement.disposition.contributesSuccessfulValue
    if acceptedReplacement {
      updatedRecords[targetIndex].inclusionState = .superseded(by: replacement.id)
    }
    updatedRecords.append(
      ExerciseAttemptRecord(
        attempt: replacement,
        inclusionState: acceptedReplacement ? .included : .excludedUnsuccessful
      )
    )
    records = updatedRecords
    return ExerciseAttemptReplacementCommit(
      replacedAttemptID: replacedAttemptID,
      replacementAttemptID: replacement.id,
      replacementDisposition: replacement.disposition,
      acceptedReplacement: acceptedReplacement
    )
  }

  /// Atomically replaces the entire currently included set. A successful Redo
  /// supersedes every included sample and begins the accepted set at N == 1.
  /// An unsuccessful Redo appends excluded provenance without changing any
  /// existing inclusion state.
  @discardableResult
  public mutating func recordWholeIncludedSetReplacement(
    _ replacement: ExerciseAttempt<Value>
  ) throws -> ExerciseAttemptWholeSetReplacementCommit {
    try validateNewAttempt(replacement)
    let includedIndices = records.indices.filter {
      records[$0].inclusionState == .included
        && records[$0].attempt.disposition.contributesSuccessfulValue
    }
    guard !includedIndices.isEmpty else {
      throw ExerciseAttemptError.replacementIncludedSetEmpty
    }

    var updatedRecords = records
    let acceptedReplacement = replacement.disposition.contributesSuccessfulValue
    let supersededAttemptIDs = includedIndices.map { records[$0].attempt.id }
    if acceptedReplacement {
      for index in includedIndices {
        updatedRecords[index].inclusionState = .superseded(by: replacement.id)
      }
    }
    updatedRecords.append(
      ExerciseAttemptRecord(
        attempt: replacement,
        inclusionState: acceptedReplacement ? .included : .excludedUnsuccessful
      )
    )
    records = updatedRecords
    return ExerciseAttemptWholeSetReplacementCommit(
      supersededAttemptIDs: acceptedReplacement ? supersededAttemptIDs : [],
      replacementAttemptID: replacement.id,
      replacementDisposition: replacement.disposition,
      acceptedReplacement: acceptedReplacement
    )
  }

  /// Supersedes one accepted sample without appending a value. This is the old
  /// history half of a successful replacement whose new attempt has a different
  /// compatibility identity and therefore must be recorded in another history.
  /// Callers can stage copies of both histories before assigning either one.
  @discardableResult
  public mutating func supersedeIncludedAttempt(
    _ attemptID: ExerciseAttemptID,
    by replacementAttemptID: ExerciseAttemptID
  ) throws -> ExerciseAttemptRecord<Value> {
    guard attemptID != replacementAttemptID,
      !records.contains(where: { $0.attempt.id == replacementAttemptID })
    else {
      throw ExerciseAttemptError.duplicateAttempt(replacementAttemptID)
    }
    guard let targetIndex = records.firstIndex(where: {
      $0.attempt.id == attemptID
    }) else {
      throw ExerciseAttemptError.replacementTargetNotFound(attemptID)
    }
    guard records[targetIndex].inclusionState == .included,
      records[targetIndex].attempt.disposition.contributesSuccessfulValue
    else {
      throw ExerciseAttemptError.replacementTargetNotIncluded(attemptID)
    }

    var updatedRecords = records
    updatedRecords[targetIndex].inclusionState = .superseded(by: replacementAttemptID)
    records = updatedRecords
    return updatedRecords[targetIndex]
  }

  private func validateNewAttempt(_ attempt: ExerciseAttempt<Value>) throws {
    guard attempt.compatibility == compatibility else {
      throw ExerciseAttemptError.incompatibleAttempt(
        expected: compatibility,
        actual: attempt.compatibility
      )
    }
    guard !records.contains(where: { $0.attempt.id == attempt.id }) else {
      throw ExerciseAttemptError.duplicateAttempt(attempt.id)
    }
  }
}

public struct AggregateEstimatorIdentity: Codable, Hashable, Sendable {
  public let name: String
  public let revision: String

  public init(name: String, revision: String) {
    precondition(!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    precondition(!revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    self.name = name
    self.revision = revision
  }
}

public enum NumericAggregateError: Error, Hashable, Sendable {
  case noSuccessfulValues
  case nonFiniteValue(ExerciseAttemptID)
}

public enum NumericUncertainty: Codable, Hashable, Sendable {
  case unavailable(validSampleCount: Int)
  case sampleStandardDeviation(Double)
}

public struct NumericAttemptAggregate: Hashable, Sendable {
  public let validSampleCount: Int
  public let estimator: AggregateEstimatorIdentity
  public let estimate: Double
  public let uncertainty: NumericUncertainty
  public let includedAttemptIDs: [ExerciseAttemptID]

  public init(
    history: ExerciseAttemptHistory<Double>,
    estimator: AggregateEstimatorIdentity = AggregateEstimatorIdentity(
      name: "arithmetic-mean",
      revision: "1"
    )
  ) throws {
    let included = history.includedSuccessfulAttempts
    guard !included.isEmpty else { throw NumericAggregateError.noSuccessfulValues }
    let values = try included.map { attempt in
      guard let value = attempt.value, value.isFinite else {
        throw NumericAggregateError.nonFiniteValue(attempt.id)
      }
      return value
    }
    let mean = values.reduce(0, +) / Double(values.count)
    let uncertainty: NumericUncertainty
    if values.count < 2 {
      uncertainty = .unavailable(validSampleCount: values.count)
    } else {
      let squaredResiduals = values.reduce(0) { partial, value in
        partial + (value - mean) * (value - mean)
      }
      uncertainty = .sampleStandardDeviation(
        sqrt(squaredResiduals / Double(values.count - 1))
      )
    }
    validSampleCount = values.count
    self.estimator = estimator
    estimate = mean
    self.uncertainty = uncertainty
    includedAttemptIDs = included.map(\.id)
  }
}

public enum PointAttemptAggregateError: Error, Hashable, Sendable {
  case noSuccessfulValues
  case nonGeometricCoordinateSpace(AttemptCoordinateSpace)
  case nonFiniteEstimate
}

public enum PointSampleUncertainty<Space>: Hashable, Sendable {
  case unavailable(validSampleCount: Int)
  case componentSampleStandardDeviation(Vector2<Space>)
}

/// A compatibility-bound component arithmetic mean for geometric point
/// measurements. Point coordinates preserve their compile-time coordinate
/// space and uncertainty is reported in the same typed space.
public struct PointAttemptAggregate<Space>: Hashable, Sendable {
  public let validSampleCount: Int
  public let estimator: AggregateEstimatorIdentity
  public let centroid: Point2<Space>
  public let uncertainty: PointSampleUncertainty<Space>
  public let includedAttemptIDs: [ExerciseAttemptID]

  public init(
    history: ExerciseAttemptHistory<Point2<Space>>,
    estimator: AggregateEstimatorIdentity = AggregateEstimatorIdentity(
      name: "component-arithmetic-mean",
      revision: "1"
    )
  ) throws {
    guard [.machine, .cameraPixels, .field].contains(
      history.compatibility.coordinateSpace
    ) else {
      throw PointAttemptAggregateError.nonGeometricCoordinateSpace(
        history.compatibility.coordinateSpace
      )
    }
    let included = history.includedSuccessfulAttempts
    guard !included.isEmpty else { throw PointAttemptAggregateError.noSuccessfulValues }
    let values = included.compactMap(\.value)
    let meanX = values.reduce(0) { $0 + $1.x } / Double(values.count)
    let meanY = values.reduce(0) { $0 + $1.y } / Double(values.count)
    guard meanX.isFinite, meanY.isFinite else {
      throw PointAttemptAggregateError.nonFiniteEstimate
    }
    let centroid = try Point2<Space>(x: meanX, y: meanY)
    let uncertainty: PointSampleUncertainty<Space>
    if values.count < 2 {
      uncertainty = .unavailable(validSampleCount: values.count)
    } else {
      let denominator = Double(values.count - 1)
      let squaredX = values.reduce(0) { partial, value in
        partial + (value.x - meanX) * (value.x - meanX)
      }
      let squaredY = values.reduce(0) { partial, value in
        partial + (value.y - meanY) * (value.y - meanY)
      }
      let deviationX = sqrt(squaredX / denominator)
      let deviationY = sqrt(squaredY / denominator)
      guard deviationX.isFinite, deviationY.isFinite else {
        throw PointAttemptAggregateError.nonFiniteEstimate
      }
      uncertainty = .componentSampleStandardDeviation(
        try Vector2<Space>(dx: deviationX, dy: deviationY)
      )
    }
    validSampleCount = values.count
    self.estimator = estimator
    self.centroid = centroid
    self.uncertainty = uncertainty
    includedAttemptIDs = included.map(\.id)
  }
}

public enum CategoricalAggregateError: Error, Hashable, Sendable {
  case noSuccessfulValues
}

public struct CategoricalAttemptAggregate<Category: Hashable & Sendable>: Sendable {
  public let validSampleCount: Int
  public let estimator: AggregateEstimatorIdentity
  public let counts: [Category: Int]
  public let proportions: [Category: Double]
  public let includedAttemptIDs: [ExerciseAttemptID]

  public init(
    history: ExerciseAttemptHistory<Category>,
    estimator: AggregateEstimatorIdentity = AggregateEstimatorIdentity(
      name: "categorical-counts",
      revision: "1"
    )
  ) throws {
    let included = history.includedSuccessfulAttempts
    guard !included.isEmpty else { throw CategoricalAggregateError.noSuccessfulValues }
    var counts: [Category: Int] = [:]
    for attempt in included {
      if let value = attempt.value { counts[value, default: 0] += 1 }
    }
    validSampleCount = included.count
    self.estimator = estimator
    self.counts = counts
    proportions = counts.mapValues { Double($0) / Double(included.count) }
    includedAttemptIDs = included.map(\.id)
  }
}

public enum LatestStateAggregateError: Error, Hashable, Sendable {
  case noSuccessfulValues
}

public struct LatestStateAggregate<State: Hashable & Sendable>: Hashable, Sendable {
  public let validSampleCount: Int
  public let estimator: AggregateEstimatorIdentity
  public let value: State
  public let latestAttemptID: ExerciseAttemptID
  public let includedAttemptIDs: [ExerciseAttemptID]

  public init(
    history: ExerciseAttemptHistory<State>,
    estimator: AggregateEstimatorIdentity = AggregateEstimatorIdentity(
      name: "latest-accepted",
      revision: "1"
    )
  ) throws {
    let included = history.includedSuccessfulAttempts
    guard let latest = included.max(by: { lhs, rhs in
      if lhs.acceptedSequence == rhs.acceptedSequence {
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
      }
      return lhs.acceptedSequence < rhs.acceptedSequence
    }), let value = latest.value
    else { throw LatestStateAggregateError.noSuccessfulValues }
    validSampleCount = included.count
    self.estimator = estimator
    self.value = value
    latestAttemptID = latest.id
    includedAttemptIDs = included.map(\.id)
  }
}

public struct LearningArtifactRevisionID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum LearningArtifactKind: Codable, Hashable, Sendable {
  case penCapAppearance
  case penInteraction
  case boundarySideAggregate(BoundaryDirection)
  case estimatedMachineCenter
  case centerArrival
  case machineCameraRegistration
  case toolContactObservation(ToolContactObservationID)
  case tipCameraRegistration
  case linePlan(AttemptGroupIdentity)
  case localPreLineContext(AttemptGroupIdentity)
  case lineStartArrival(AttemptGroupIdentity)
  case lineExecution(AttemptGroupIdentity)
  case postLineObservation(AttemptGroupIdentity)
  case comparison(AttemptGroupIdentity)
}

public enum LearningArtifactRevisionState: String, Codable, Hashable, Sendable {
  case candidate
  case current
  case superseded
  case invalidated
}

public struct LearningArtifactRevision: Codable, Hashable, Sendable {
  public let id: LearningArtifactRevisionID
  public let kind: LearningArtifactKind
  public let attemptID: ExerciseAttemptID
  public let disposition: ExerciseAttemptDisposition
  public let consumedRevisionIDs: Set<LearningArtifactRevisionID>
  public fileprivate(set) var state: LearningArtifactRevisionState

  public init(
    id: LearningArtifactRevisionID = LearningArtifactRevisionID(),
    kind: LearningArtifactKind,
    attemptID: ExerciseAttemptID,
    disposition: ExerciseAttemptDisposition,
    consumedRevisionIDs: Set<LearningArtifactRevisionID> = [],
    state: LearningArtifactRevisionState = .candidate
  ) {
    self.id = id
    self.kind = kind
    self.attemptID = attemptID
    self.disposition = disposition
    self.consumedRevisionIDs = consumedRevisionIDs
    self.state = state
  }
}

public enum LearningDependencyGraphError: Error, Hashable, Sendable {
  case duplicateRevision(LearningArtifactRevisionID)
  case unsuccessfulReplacement(ExerciseAttemptDisposition)
  case invalidInitialState(LearningArtifactRevisionState)
  case dependencyUnavailable(LearningArtifactRevisionID)
  case invalidDependencyShape(LearningArtifactKind)
  case explicitReplacementRevisionUnavailable(LearningArtifactRevisionID)
  case explicitReplacementKindMismatch(
    revisionID: LearningArtifactRevisionID,
    expected: LearningArtifactKind,
    actual: LearningArtifactKind
  )
  case explicitReplacementStateMismatch(
    revisionID: LearningArtifactRevisionID,
    actual: LearningArtifactRevisionState
  )
  case explicitReplacementCurrentConflict(
    kind: LearningArtifactKind,
    revisionID: LearningArtifactRevisionID
  )
}

public struct LearningArtifactCommit: Hashable, Sendable {
  public let currentRevision: LearningArtifactRevision
  public let supersededRevisionID: LearningArtifactRevisionID?
  public let invalidatedRevisionIDs: Set<LearningArtifactRevisionID>
}

public struct LearningArtifactInvalidation: Hashable, Sendable {
  public let rootInvalidatedRevisionIDs: Set<LearningArtifactRevisionID>
  public let transitiveInvalidatedRevisionIDs: Set<LearningArtifactRevisionID>

  public var allInvalidatedRevisionIDs: Set<LearningArtifactRevisionID> {
    rootInvalidatedRevisionIDs.union(transitiveInvalidatedRevisionIDs)
  }

  public init(
    rootInvalidatedRevisionIDs: Set<LearningArtifactRevisionID>,
    transitiveInvalidatedRevisionIDs: Set<LearningArtifactRevisionID>
  ) {
    self.rootInvalidatedRevisionIDs = rootInvalidatedRevisionIDs
    self.transitiveInvalidatedRevisionIDs = transitiveInvalidatedRevisionIDs
  }
}

/// In-memory accepted-revision index and explicit dependency graph. It is not a
/// workflow state store and intentionally contains no artifact payload values.
public struct LearningDependencyGraph: Sendable {
  private var revisionsByID: [LearningArtifactRevisionID: LearningArtifactRevision] = [:]
  private var currentRevisionIDByKind: [LearningArtifactKind: LearningArtifactRevisionID] = [:]
  public private(set) var revision: UInt64 = 0

  public init() {}

  public var revisions: [LearningArtifactRevision] {
    Array(revisionsByID.values)
  }

  public func revision(id: LearningArtifactRevisionID) -> LearningArtifactRevision? {
    revisionsByID[id]
  }

  public func currentRevision(for kind: LearningArtifactKind) -> LearningArtifactRevision? {
    guard let id = currentRevisionIDByKind[kind] else { return nil }
    return revisionsByID[id]
  }

  /// Invalidates exactly the caller-declared current camera-dependent roots and
  /// their explicit transitive consumers. Camera policy belongs to the caller;
  /// the graph neither selects roots nor infers dependencies from sequence.
  /// Existing revisions remain indexed with their identities and provenance.
  @discardableResult
  public mutating func invalidateForCameraChange(
    rootKinds: Set<LearningArtifactKind>
  ) -> LearningArtifactInvalidation {
    invalidateCurrentRevisions(rootKinds: rootKinds)
  }

  /// Invalidates the named current revisions plus their explicit transitive
  /// consumers. The caller owns the policy that selected the roots; this graph
  /// never infers visible workflow order. Existing revisions remain indexed as
  /// invalidated provenance and cannot contribute current authority.
  @discardableResult
  public mutating func invalidateCurrentRevisions(
    rootKinds: Set<LearningArtifactKind>
  ) -> LearningArtifactInvalidation {
    let rootRevisionIDs: Set<LearningArtifactRevisionID> = Set(rootKinds.compactMap {
      kind -> LearningArtifactRevisionID? in
      guard let revisionID = currentRevisionIDByKind[kind],
        revisionsByID[revisionID]?.state == .current
      else { return nil }
      return revisionID
    })
    let transitiveRevisionIDs = Self.transitiveDependents(
      of: rootRevisionIDs,
      in: revisionsByID
    )
    let allInvalidatedRevisionIDs = rootRevisionIDs.union(transitiveRevisionIDs)

    for revisionID in allInvalidatedRevisionIDs {
      guard revisionsByID[revisionID]?.state == .current else { continue }
      let kind = revisionsByID[revisionID]!.kind
      revisionsByID[revisionID]?.state = .invalidated
      if currentRevisionIDByKind[kind] == revisionID {
        currentRevisionIDByKind.removeValue(forKey: kind)
      }
    }
    if !allInvalidatedRevisionIDs.isEmpty { revision &+= 1 }

    return LearningArtifactInvalidation(
      rootInvalidatedRevisionIDs: rootRevisionIDs,
      transitiveInvalidatedRevisionIDs: transitiveRevisionIDs
    )
  }

  /// Commits only a successful candidate. The replacement and every declared
  /// transitive invalidation are applied to a copy before the graph changes.
  @discardableResult
  public mutating func commitReplacement(
    _ candidate: LearningArtifactRevision
  ) throws -> LearningArtifactCommit {
    guard revisionsByID[candidate.id] == nil else {
      throw LearningDependencyGraphError.duplicateRevision(candidate.id)
    }
    guard candidate.disposition == .succeeded else {
      throw LearningDependencyGraphError.unsuccessfulReplacement(candidate.disposition)
    }
    guard candidate.state == .candidate else {
      throw LearningDependencyGraphError.invalidInitialState(candidate.state)
    }
    for dependencyID in candidate.consumedRevisionIDs {
      guard revisionsByID[dependencyID]?.state == .current else {
        throw LearningDependencyGraphError.dependencyUnavailable(dependencyID)
      }
    }
    try Self.validateSemanticDependencies(candidate, revisions: revisionsByID)

    var updatedRevisions = revisionsByID
    var updatedCurrent = currentRevisionIDByKind
    let supersededID = updatedCurrent[candidate.kind]
    if let supersededID {
      updatedRevisions[supersededID]?.state = .superseded
      updatedCurrent.removeValue(forKey: candidate.kind)
    }

    let invalidatedIDs = Self.transitiveDependents(
      of: supersededID,
      in: updatedRevisions
    )
    for invalidatedID in invalidatedIDs {
      guard updatedRevisions[invalidatedID]?.state == .current else { continue }
      let invalidatedKind = updatedRevisions[invalidatedID]!.kind
      updatedRevisions[invalidatedID]?.state = .invalidated
      if updatedCurrent[invalidatedKind] == invalidatedID {
        updatedCurrent.removeValue(forKey: invalidatedKind)
      }
    }

    var currentCandidate = candidate
    currentCandidate.state = .current
    updatedRevisions[currentCandidate.id] = currentCandidate
    updatedCurrent[currentCandidate.kind] = currentCandidate.id
    revisionsByID = updatedRevisions
    currentRevisionIDByKind = updatedCurrent
    revision &+= 1
    return LearningArtifactCommit(
      currentRevision: currentCandidate,
      supersededRevisionID: supersededID,
      invalidatedRevisionIDs: invalidatedIDs
    )
  }

  /// Finalizes a staged replacement whose exact accepted predecessor was
  /// already invalidated in the draft by replacement of one of its declared
  /// dependencies. This is not a recovery or policy API: callers must name the
  /// exact same-kind invalidated revision. No other invalidation is changed.
  @discardableResult
  public mutating func commitReplacement(
    _ candidate: LearningArtifactRevision,
    supersedingInvalidatedRevision revisionID: LearningArtifactRevisionID
  ) throws -> LearningArtifactCommit {
    guard revisionsByID[candidate.id] == nil else {
      throw LearningDependencyGraphError.duplicateRevision(candidate.id)
    }
    guard candidate.disposition == .succeeded else {
      throw LearningDependencyGraphError.unsuccessfulReplacement(candidate.disposition)
    }
    guard candidate.state == .candidate else {
      throw LearningDependencyGraphError.invalidInitialState(candidate.state)
    }
    guard let replacedRevision = revisionsByID[revisionID] else {
      throw LearningDependencyGraphError.explicitReplacementRevisionUnavailable(revisionID)
    }
    guard replacedRevision.kind == candidate.kind else {
      throw LearningDependencyGraphError.explicitReplacementKindMismatch(
        revisionID: revisionID,
        expected: candidate.kind,
        actual: replacedRevision.kind
      )
    }
    guard replacedRevision.state == .invalidated else {
      throw LearningDependencyGraphError.explicitReplacementStateMismatch(
        revisionID: revisionID,
        actual: replacedRevision.state
      )
    }
    if let currentRevisionID = currentRevisionIDByKind[candidate.kind] {
      throw LearningDependencyGraphError.explicitReplacementCurrentConflict(
        kind: candidate.kind,
        revisionID: currentRevisionID
      )
    }
    for dependencyID in candidate.consumedRevisionIDs {
      guard revisionsByID[dependencyID]?.state == .current else {
        throw LearningDependencyGraphError.dependencyUnavailable(dependencyID)
      }
    }
    try Self.validateSemanticDependencies(candidate, revisions: revisionsByID)

    var currentCandidate = candidate
    currentCandidate.state = .current
    revisionsByID[revisionID]?.state = .superseded
    revisionsByID[currentCandidate.id] = currentCandidate
    currentRevisionIDByKind[currentCandidate.kind] = currentCandidate.id
    revision &+= 1
    return LearningArtifactCommit(
      currentRevision: currentCandidate,
      supersededRevisionID: revisionID,
      invalidatedRevisionIDs: []
    )
  }

  private static func transitiveDependents(
    of revisionID: LearningArtifactRevisionID?,
    in revisions: [LearningArtifactRevisionID: LearningArtifactRevision]
  ) -> Set<LearningArtifactRevisionID> {
    guard let revisionID else { return [] }
    return transitiveDependents(of: [revisionID], in: revisions)
  }

  private static func transitiveDependents(
    of revisionIDs: Set<LearningArtifactRevisionID>,
    in revisions: [LearningArtifactRevisionID: LearningArtifactRevision]
  ) -> Set<LearningArtifactRevisionID> {
    var pending = Array(revisionIDs)
    var dependents: Set<LearningArtifactRevisionID> = []
    while let dependencyID = pending.popLast() {
      for revision in revisions.values
      where revision.state == .current
        && revision.consumedRevisionIDs.contains(dependencyID)
        && dependents.insert(revision.id).inserted
      {
        pending.append(revision.id)
      }
    }
    return dependents
  }

  private static func validateSemanticDependencies(
    _ candidate: LearningArtifactRevision,
    revisions: [LearningArtifactRevisionID: LearningArtifactRevision]
  ) throws {
    let dependencyKinds = candidate.consumedRevisionIDs.compactMap { revisions[$0]?.kind }
    switch candidate.kind {
    case .penCapAppearance, .boundarySideAggregate:
      guard dependencyKinds.isEmpty else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .penInteraction:
      guard dependencyKinds == [.penCapAppearance] else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .estimatedMachineCenter:
      let directions = Set(dependencyKinds.compactMap { kind -> BoundaryDirection? in
        guard case .boundarySideAggregate(let direction) = kind else { return nil }
        return direction
      })
      guard dependencyKinds.count == directions.count,
        directions == Set(BoundaryDirection.allCases)
      else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .centerArrival:
      guard dependencyKinds == [.estimatedMachineCenter] else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .machineCameraRegistration:
      guard Set(dependencyKinds) == [.centerArrival, .penCapAppearance],
        dependencyKinds.count == 2
      else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .toolContactObservation:
      guard dependencyKinds.count == 1,
        dependencyKinds[0] == .machineCameraRegistration
      else { throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind) }
    case .tipCameraRegistration:
      let machineCount = dependencyKinds.filter { $0 == .machineCameraRegistration }.count
      let observationIDs: Set<ToolContactObservationID> = Set(dependencyKinds.compactMap { kind in
        guard case .toolContactObservation(let id) = kind else { return nil }
        return id
      })
      guard dependencyKinds.count == machineCount + observationIDs.count,
        machineCount == 1,
        observationIDs.isEmpty || observationIDs.count == 1
          || observationIDs.count == 5 || observationIDs.count == 6
      else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .linePlan:
      guard dependencyKinds == [.tipCameraRegistration] else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .localPreLineContext(let group):
      guard Set(dependencyKinds) == [.linePlan(group), .tipCameraRegistration],
        dependencyKinds.count == 2
      else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .lineStartArrival(let group):
      guard Set(dependencyKinds) == [.linePlan(group), .localPreLineContext(group)],
        dependencyKinds.count == 2
      else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .lineExecution(let group):
      guard Set(dependencyKinds) == [
        .linePlan(group), .localPreLineContext(group), .lineStartArrival(group),
      ], dependencyKinds.count == 3 else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .postLineObservation(let group):
      guard Set(dependencyKinds) == [
        .lineExecution(group), .localPreLineContext(group), .tipCameraRegistration,
      ], dependencyKinds.count == 3 else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    case .comparison(let group):
      guard dependencyKinds == [.postLineObservation(group)] else {
        throw LearningDependencyGraphError.invalidDependencyShape(candidate.kind)
      }
    }
  }
}
