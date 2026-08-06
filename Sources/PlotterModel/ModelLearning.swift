import Foundation

public struct DrawingModelVersion: RawRepresentable, Codable, Hashable, Sendable, Comparable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum DrawingModelSnapshotOrigin: Codable, Hashable, Sendable {
  case prior(name: String)
  case acceptedCandidate(
    parentVersion: DrawingModelVersion,
    trainingObservationIDs: [String],
    holdoutObservationIDs: [String],
    acceptanceNote: String
  )
}

public struct DrawingModelSnapshotProvenance: Codable, Hashable, Sendable {
  public let origin: DrawingModelSnapshotOrigin

  public init(origin: DrawingModelSnapshotOrigin) {
    self.origin = origin
  }
}

/// One immutable model that has been explicitly accepted for command prediction.
///
/// The constant correction is intentionally carried separately from the affine
/// transform. Point-pair fitting below holds that correction fixed because a free
/// affine translation and a free constant offset are not separately identifiable
/// from the same observations.
public struct AcceptedDrawingModelSnapshot: Codable, Hashable, Sendable {
  public let version: DrawingModelVersion
  public let transform: DrawingTransform
  public let provenance: DrawingModelSnapshotProvenance

  public init(
    version: DrawingModelVersion,
    transform: DrawingTransform,
    provenance: DrawingModelSnapshotProvenance
  ) {
    self.version = version
    self.transform = transform
    self.provenance = provenance
  }

  public func predictedFieldPoint(for machinePoint: Point2<MachineSpace>) throws
    -> Point2<FieldSpace>
  {
    try transform.predictedFieldPoint(for: machinePoint)
  }

  public func predictedFieldPath(for machinePath: Polyline<MachineSpace>) throws
    -> Polyline<FieldSpace>
  {
    try transform.predictedFieldPath(for: machinePath)
  }
}

public enum ModelObservationSplit: String, Codable, Hashable, Sendable {
  case training
  case holdout
}

/// Transient physical evidence. It is intentionally non-Codable and its scalar
/// constructor is package-scoped so decoded or caller-authored values cannot
/// reacquire live-camera authority.
public struct PhysicalModelObservationEvidence: Hashable, Sendable {
  public let frameID: String
  public let contentSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let measuredCameraPoint: Point2<CameraPixelSpace>
  public let measurementConfidence: Double
  public let controllerPosition: Point2<MachineSpace>
  public let controllerSampleNanoseconds: UInt64
  public let fieldRegistrationID: FieldRegistrationID

  package init(
    frameID: String,
    contentSHA256: String,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    measuredCameraPoint: Point2<CameraPixelSpace>,
    measurementConfidence: Double,
    controllerPosition: Point2<MachineSpace>,
    controllerSampleNanoseconds: UInt64,
    fieldRegistrationID: FieldRegistrationID
  ) throws {
    guard !frameID.isEmpty, !contentSHA256.isEmpty else {
      throw ModelLearningError.emptyProvenanceField
    }
    guard measurementConfidence.isFinite, (0...1).contains(measurementConfidence) else {
      throw ModelLearningError.invalidMeasurementConfidence(measurementConfidence)
    }
    self.frameID = frameID
    self.contentSHA256 = contentSHA256
    self.captureNanoseconds = captureNanoseconds
    self.cameraConfigurationID = cameraConfigurationID
    self.measuredCameraPoint = measuredCameraPoint
    self.measurementConfidence = measurementConfidence
    self.controllerPosition = controllerPosition
    self.controllerSampleNanoseconds = controllerSampleNanoseconds
    self.fieldRegistrationID = fieldRegistrationID
  }
}

public enum ModelObservationEvidence: Hashable, Sendable {
  case physical(PhysicalModelObservationEvidence)
  case simulated(scenarioID: String)
}

public struct ModelObservationProvenance: Hashable, Sendable {
  public let observationID: String
  public let evidence: ModelObservationEvidence
  public let algorithmRevision: String

  public init(
    observationID: String,
    evidence: ModelObservationEvidence,
    algorithmRevision: String
  ) throws {
    guard !observationID.isEmpty, !algorithmRevision.isEmpty else {
      throw ModelLearningError.emptyProvenanceField
    }
    switch evidence {
    case .physical:
      break
    case .simulated(let scenarioID):
      guard !scenarioID.isEmpty else { throw ModelLearningError.emptyProvenanceField }
    }
    self.observationID = observationID
    self.evidence = evidence
    self.algorithmRevision = algorithmRevision
  }
}

/// One supervised point pair. Split membership is fixed when the observation is
/// created so candidate fitting cannot silently consume holdout evidence.
/// A current-session learning observation. Physical cases are intentionally
/// non-Codable and can be constructed only through the package's sealed live
/// observation path.
public struct DrawingModelTrainingObservation: Hashable, Sendable {
  public let machinePoint: Point2<MachineSpace>
  public let observedFieldPoint: Point2<FieldSpace>
  public let split: ModelObservationSplit
  public let provenance: ModelObservationProvenance

  public init(
    machinePoint: Point2<MachineSpace>,
    observedFieldPoint: Point2<FieldSpace>,
    split: ModelObservationSplit,
    provenance: ModelObservationProvenance
  ) throws {
    if case .physical = provenance.evidence {
      throw ModelLearningError.physicalObservationRequiresRegistration
    }
    self.machinePoint = machinePoint
    self.observedFieldPoint = observedFieldPoint
    self.split = split
    self.provenance = provenance
  }

  /// Constructs a physical observation by applying the cited registration to
  /// the cited measured camera point. Callers cannot supply an unrelated field
  /// point while retaining otherwise plausible physical provenance.
  package static func physical(
    evidence: PhysicalModelObservationEvidence,
    registration: FieldRegistration,
    split: ModelObservationSplit,
    observationID: String,
    algorithmRevision: String
  ) throws -> Self {
    guard registration.id == evidence.fieldRegistrationID else {
      throw ModelLearningError.physicalRegistrationMismatch
    }
    return Self(
      validatedMachinePoint: evidence.controllerPosition,
      observedFieldPoint: try registration.fieldPoint(from: evidence.measuredCameraPoint),
      split: split,
      provenance: try ModelObservationProvenance(
        observationID: observationID,
        evidence: .physical(evidence),
        algorithmRevision: algorithmRevision
      )
    )
  }

  private init(
    validatedMachinePoint: Point2<MachineSpace>,
    observedFieldPoint: Point2<FieldSpace>,
    split: ModelObservationSplit,
    provenance: ModelObservationProvenance
  ) {
    machinePoint = validatedMachinePoint
    self.observedFieldPoint = observedFieldPoint
    self.split = split
    self.provenance = provenance
  }
}

public struct ModelFitMetrics: Codable, Hashable, Sendable {
  public let observationCount: Int
  public let rootMeanSquareError: Double
  public let maximumError: Double

  public init(observationCount: Int, rootMeanSquareError: Double, maximumError: Double) {
    self.observationCount = observationCount
    self.rootMeanSquareError = rootMeanSquareError
    self.maximumError = maximumError
  }
}

public struct ModelSplitEvaluation: Codable, Hashable, Sendable {
  public let training: ModelFitMetrics
  public let holdout: ModelFitMetrics

  public init(training: ModelFitMetrics, holdout: ModelFitMetrics) {
    self.training = training
    self.holdout = holdout
  }
}

/// A fitted proposal is not an accepted model and cannot be used as one without
/// the explicit acceptance operation below.
public struct DrawingModelCandidate: Codable, Hashable, Sendable {
  public let baseVersion: DrawingModelVersion
  public let proposedTransform: DrawingTransform
  public let baselineEvaluation: ModelSplitEvaluation
  public let candidateEvaluation: ModelSplitEvaluation
  public let trainingObservationIDs: [String]
  public let holdoutObservationIDs: [String]

  public init(
    baseVersion: DrawingModelVersion,
    proposedTransform: DrawingTransform,
    baselineEvaluation: ModelSplitEvaluation,
    candidateEvaluation: ModelSplitEvaluation,
    trainingObservationIDs: [String],
    holdoutObservationIDs: [String]
  ) {
    self.baseVersion = baseVersion
    self.proposedTransform = proposedTransform
    self.baselineEvaluation = baselineEvaluation
    self.candidateEvaluation = candidateEvaluation
    self.trainingObservationIDs = trainingObservationIDs
    self.holdoutObservationIDs = holdoutObservationIDs
  }
}

public enum ModelLearningError: Error, Equatable, Sendable {
  case emptyProvenanceField
  case invalidMeasurementConfidence(Double)
  case physicalObservationRequiresRegistration
  case physicalRegistrationMismatch
  case duplicateObservationID(String)
  case insufficientTrainingObservations(required: Int, actual: Int)
  case insufficientHoldoutObservations(required: Int, actual: Int)
  case degenerateTrainingGeometry
  case invalidAcceptanceCriteria
  case emptyAcceptanceNote
  case candidateBaseMismatch(
    candidate: DrawingModelVersion,
    accepted: DrawingModelVersion
  )
  case nonIncreasingVersion(
    proposed: DrawingModelVersion,
    base: DrawingModelVersion
  )
  case rejectedCandidate(ModelCandidateRejection)
  case penDownStrokeActive(String)
  case penDownStrokeAlreadyActive(String)
  case noPenDownStrokeActive
  case activeStrokeMismatch(expected: String, actual: String)
  case emptyStrokeIdentifier
}

public enum DrawingModelTrainer {
  public static func fitCandidate(
    basedOn accepted: AcceptedDrawingModelSnapshot,
    observations: [DrawingModelTrainingObservation]
  ) throws -> DrawingModelCandidate {
    var identifiers = Set<String>()
    for observation in observations {
      guard identifiers.insert(observation.provenance.observationID).inserted else {
        throw ModelLearningError.duplicateObservationID(observation.provenance.observationID)
      }
    }

    let training =
      observations
      .filter { $0.split == .training }
      .sorted { $0.provenance.observationID < $1.provenance.observationID }
    let holdout =
      observations
      .filter { $0.split == .holdout }
      .sorted { $0.provenance.observationID < $1.provenance.observationID }
    guard training.count >= 3 else {
      throw ModelLearningError.insufficientTrainingObservations(
        required: 3,
        actual: training.count
      )
    }
    guard !holdout.isEmpty else {
      throw ModelLearningError.insufficientHoldoutObservations(required: 1, actual: 0)
    }

    let affine = try fitAffine(
      training,
      heldConstantCorrection: accepted.transform.constantFieldCorrection
    )
    let proposed = DrawingTransform(
      machineToField: affine,
      constantFieldCorrection: accepted.transform.constantFieldCorrection,
      machineDomain: accepted.transform.machineDomain
    )
    return DrawingModelCandidate(
      baseVersion: accepted.version,
      proposedTransform: proposed,
      baselineEvaluation: try evaluate(accepted.transform, training: training, holdout: holdout),
      candidateEvaluation: try evaluate(proposed, training: training, holdout: holdout),
      trainingObservationIDs: training.map(\.provenance.observationID),
      holdoutObservationIDs: holdout.map(\.provenance.observationID)
    )
  }

  private static func evaluate(
    _ transform: DrawingTransform,
    training: [DrawingModelTrainingObservation],
    holdout: [DrawingModelTrainingObservation]
  ) throws -> ModelSplitEvaluation {
    ModelSplitEvaluation(
      training: try metrics(for: training, transform: transform),
      holdout: try metrics(for: holdout, transform: transform)
    )
  }

  private static func metrics(
    for observations: [DrawingModelTrainingObservation],
    transform: DrawingTransform
  ) throws -> ModelFitMetrics {
    let errors = try observations.map {
      try transform.predictedFieldPoint(for: $0.machinePoint).distance(
        to: $0.observedFieldPoint
      )
    }
    let rms = sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count))
    return ModelFitMetrics(
      observationCount: errors.count,
      rootMeanSquareError: rms,
      maximumError: errors.max() ?? 0
    )
  }

  private static func fitAffine(
    _ observations: [DrawingModelTrainingObservation],
    heldConstantCorrection correction: Vector2<FieldSpace>
  ) throws -> AffineTransform2<MachineSpace, FieldSpace> {
    let count = Double(observations.count)
    let centerX = observations.reduce(0) { $0 + $1.machinePoint.x } / count
    let centerY = observations.reduce(0) { $0 + $1.machinePoint.y } / count
    let averageSquaredRadius =
      observations.reduce(0) { partial, observation in
        let x = observation.machinePoint.x - centerX
        let y = observation.machinePoint.y - centerY
        return partial + x * x + y * y
      } / count
    let scale = sqrt(averageSquaredRadius)
    guard scale.isFinite, scale > 1e-12 else {
      throw ModelLearningError.degenerateTrainingGeometry
    }

    let normalized = observations.map { observation in
      (
        (observation.machinePoint.x - centerX) / scale,
        (observation.machinePoint.y - centerY) / scale,
        observation.observedFieldPoint.x - correction.dx,
        observation.observedFieldPoint.y - correction.dy
      )
    }
    let sxx = normalized.reduce(0) { $0 + $1.0 * $1.0 } / count
    let syy = normalized.reduce(0) { $0 + $1.1 * $1.1 } / count
    let sxy = normalized.reduce(0) { $0 + $1.0 * $1.1 } / count
    guard sxx * syy - sxy * sxy > 1e-10 else {
      throw ModelLearningError.degenerateTrainingGeometry
    }

    var normal = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
    var targetX = Array(repeating: 0.0, count: 3)
    var targetY = Array(repeating: 0.0, count: 3)
    for sample in normalized {
      let row = [sample.0, sample.1, 1.0]
      for i in 0..<3 {
        targetX[i] += row[i] * sample.2
        targetY[i] += row[i] * sample.3
        for j in 0..<3 { normal[i][j] += row[i] * row[j] }
      }
    }
    let betaX = try solve3x3(normal, targetX)
    let betaY = try solve3x3(normal, targetY)
    let m11 = betaX[0] / scale
    let m12 = betaX[1] / scale
    let m21 = betaY[0] / scale
    let m22 = betaY[1] / scale
    return try AffineTransform2(
      m11: m11,
      m12: m12,
      m21: m21,
      m22: m22,
      tx: betaX[2] - m11 * centerX - m12 * centerY,
      ty: betaY[2] - m21 * centerX - m22 * centerY
    )
  }

  private static func solve3x3(_ matrix: [[Double]], _ rightHandSide: [Double]) throws
    -> [Double]
  {
    var augmented = zip(matrix, rightHandSide).map { $0 + [$1] }
    for column in 0..<3 {
      var pivot = column
      for candidate in (column + 1)..<3
      where abs(augmented[candidate][column]) > abs(augmented[pivot][column]) {
        pivot = candidate
      }
      guard abs(augmented[pivot][column]) > 1e-12 else {
        throw ModelLearningError.degenerateTrainingGeometry
      }
      if pivot != column { augmented.swapAt(pivot, column) }
      let divisor = augmented[column][column]
      for index in column..<4 { augmented[column][index] /= divisor }
      for row in 0..<3 where row != column {
        let factor = augmented[row][column]
        for index in column..<4 {
          augmented[row][index] -= factor * augmented[column][index]
        }
      }
    }
    return augmented.map { $0[3] }
  }
}

public struct ModelAcceptanceCriteria: Codable, Hashable, Sendable {
  public let maximumHoldoutRootMeanSquareError: Double
  public let maximumHoldoutError: Double
  public let minimumHoldoutRootMeanSquareImprovement: Double

  public init(
    maximumHoldoutRootMeanSquareError: Double,
    maximumHoldoutError: Double,
    minimumHoldoutRootMeanSquareImprovement: Double
  ) throws {
    guard maximumHoldoutRootMeanSquareError.isFinite,
      maximumHoldoutRootMeanSquareError >= 0,
      maximumHoldoutError.isFinite,
      maximumHoldoutError >= 0,
      minimumHoldoutRootMeanSquareImprovement.isFinite,
      minimumHoldoutRootMeanSquareImprovement >= 0
    else { throw ModelLearningError.invalidAcceptanceCriteria }
    self.maximumHoldoutRootMeanSquareError = maximumHoldoutRootMeanSquareError
    self.maximumHoldoutError = maximumHoldoutError
    self.minimumHoldoutRootMeanSquareImprovement =
      minimumHoldoutRootMeanSquareImprovement
  }
}

public enum ModelCandidateRejection: Error, Codable, Hashable, Sendable {
  case holdoutRootMeanSquareExceeded(actual: Double, maximum: Double)
  case holdoutMaximumExceeded(actual: Double, maximum: Double)
  case insufficientHoldoutImprovement(actual: Double, minimum: Double)
}

public enum ModelAcceptanceDecision: Codable, Hashable, Sendable {
  case accept
  case reject(ModelCandidateRejection)
}

public enum DrawingModelAcceptance {
  /// Produces a recommendation only. It does not mutate or replace an accepted model.
  public static func decision(
    for candidate: DrawingModelCandidate,
    criteria: ModelAcceptanceCriteria
  ) -> ModelAcceptanceDecision {
    let holdout = candidate.candidateEvaluation.holdout
    guard holdout.rootMeanSquareError <= criteria.maximumHoldoutRootMeanSquareError else {
      return .reject(
        .holdoutRootMeanSquareExceeded(
          actual: holdout.rootMeanSquareError,
          maximum: criteria.maximumHoldoutRootMeanSquareError
        ))
    }
    guard holdout.maximumError <= criteria.maximumHoldoutError else {
      return .reject(
        .holdoutMaximumExceeded(
          actual: holdout.maximumError,
          maximum: criteria.maximumHoldoutError
        ))
    }
    let improvement =
      candidate.baselineEvaluation.holdout.rootMeanSquareError
      - holdout.rootMeanSquareError
    guard improvement > 0,
      improvement >= criteria.minimumHoldoutRootMeanSquareImprovement
    else {
      return .reject(
        .insufficientHoldoutImprovement(
          actual: improvement,
          minimum: criteria.minimumHoldoutRootMeanSquareImprovement
        ))
    }
    return .accept
  }

  /// The sole model-promotion operation. Callers must pass the explicit decision
  /// and choose a monotonically increasing version.
  public static func accept(
    _ candidate: DrawingModelCandidate,
    replacing accepted: AcceptedDrawingModelSnapshot,
    decision: ModelAcceptanceDecision,
    as newVersion: DrawingModelVersion,
    acceptanceNote: String
  ) throws -> AcceptedDrawingModelSnapshot {
    guard candidate.baseVersion == accepted.version else {
      throw ModelLearningError.candidateBaseMismatch(
        candidate: candidate.baseVersion,
        accepted: accepted.version
      )
    }
    guard newVersion > accepted.version else {
      throw ModelLearningError.nonIncreasingVersion(
        proposed: newVersion,
        base: accepted.version
      )
    }
    guard case .accept = decision else {
      guard case .reject(let reason) = decision else { preconditionFailure() }
      throw ModelLearningError.rejectedCandidate(reason)
    }
    guard !acceptanceNote.isEmpty else { throw ModelLearningError.emptyAcceptanceNote }
    return AcceptedDrawingModelSnapshot(
      version: newVersion,
      transform: candidate.proposedTransform,
      provenance: DrawingModelSnapshotProvenance(
        origin: .acceptedCandidate(
          parentVersion: accepted.version,
          trainingObservationIDs: candidate.trainingObservationIDs,
          holdoutObservationIDs: candidate.holdoutObservationIDs,
          acceptanceNote: acceptanceNote
        )
      )
    )
  }
}

public enum ModelLearningCheckpoint: Codable, Hashable, Sendable {
  case penUpBetweenStrokes(identifier: String)
  case runComplete(identifier: String)
}

public struct StrokeModelPin: Codable, Hashable, Sendable {
  public let strokeIdentifier: String
  public let acceptedModel: AcceptedDrawingModelSnapshot

  public init(strokeIdentifier: String, acceptedModel: AcceptedDrawingModelSnapshot) {
    self.strokeIdentifier = strokeIdentifier
    self.acceptedModel = acceptedModel
  }
}

/// A compact, current-session projection of the immutable observations available
/// to the affine learner. It is deliberately not a history or replay model.
public struct OnlineModelDatasetSummary: Codable, Hashable, Sendable {
  public let observationCount: Int
  public let trainingCount: Int
  public let holdoutCount: Int
  public let physicalCount: Int
  public let simulatedCount: Int
  public let observationIDs: [String]

  public init(
    observationCount: Int,
    trainingCount: Int,
    holdoutCount: Int,
    physicalCount: Int,
    simulatedCount: Int,
    observationIDs: [String]
  ) {
    self.observationCount = observationCount
    self.trainingCount = trainingCount
    self.holdoutCount = holdoutCount
    self.physicalCount = physicalCount
    self.simulatedCount = simulatedCount
    self.observationIDs = observationIDs
  }
}

/// Accumulates online observations but has no API capable of replacing its
/// accepted snapshot. Promotion is external and creates a new immutable snapshot.
public struct OnlineModelAccumulator: Sendable {
  public let acceptedModel: AcceptedDrawingModelSnapshot
  public private(set) var observations: [DrawingModelTrainingObservation]
  public private(set) var activeStrokePin: StrokeModelPin?

  public init(
    acceptedModel: AcceptedDrawingModelSnapshot,
    observations: [DrawingModelTrainingObservation] = []
  ) {
    self.acceptedModel = acceptedModel
    self.observations = observations
    activeStrokePin = nil
  }

  public var datasetSummary: OnlineModelDatasetSummary {
    let trainingCount = observations.count { $0.split == .training }
    let holdoutCount = observations.count { $0.split == .holdout }
    let physicalCount = observations.count {
      if case .physical = $0.provenance.evidence { return true }
      return false
    }
    return OnlineModelDatasetSummary(
      observationCount: observations.count,
      trainingCount: trainingCount,
      holdoutCount: holdoutCount,
      physicalCount: physicalCount,
      simulatedCount: observations.count - physicalCount,
      observationIDs: observations.map(\.provenance.observationID)
    )
  }

  @discardableResult
  public mutating func beginPenDownStroke(identifier: String) throws -> StrokeModelPin {
    guard !identifier.isEmpty else { throw ModelLearningError.emptyStrokeIdentifier }
    if let activeStrokePin {
      throw ModelLearningError.penDownStrokeAlreadyActive(activeStrokePin.strokeIdentifier)
    }
    let pin = StrokeModelPin(strokeIdentifier: identifier, acceptedModel: acceptedModel)
    activeStrokePin = pin
    return pin
  }

  public mutating func endPenDownStroke(identifier: String) throws {
    guard let activeStrokePin else { throw ModelLearningError.noPenDownStrokeActive }
    guard activeStrokePin.strokeIdentifier == identifier else {
      throw ModelLearningError.activeStrokeMismatch(
        expected: activeStrokePin.strokeIdentifier,
        actual: identifier
      )
    }
    self.activeStrokePin = nil
  }

  public mutating func record(
    _ observation: DrawingModelTrainingObservation,
    at checkpoint: ModelLearningCheckpoint
  ) throws {
    try record([observation], at: checkpoint)
  }

  /// Atomically records one physical episode's observations. Validation happens
  /// before mutation so a duplicate second point cannot leave a half-recorded
  /// training episode behind.
  public mutating func record(
    _ newObservations: [DrawingModelTrainingObservation],
    at _: ModelLearningCheckpoint
  ) throws {
    if let activeStrokePin {
      throw ModelLearningError.penDownStrokeActive(activeStrokePin.strokeIdentifier)
    }
    var identifiers = Set(observations.map(\.provenance.observationID))
    for observation in newObservations {
      guard identifiers.insert(observation.provenance.observationID).inserted else {
        throw ModelLearningError.duplicateObservationID(
          observation.provenance.observationID
        )
      }
    }
    observations.append(contentsOf: newObservations)
  }

  public func proposeCandidate(at _: ModelLearningCheckpoint) throws -> DrawingModelCandidate {
    if let activeStrokePin {
      throw ModelLearningError.penDownStrokeActive(activeStrokePin.strokeIdentifier)
    }
    return try DrawingModelTrainer.fitCandidate(
      basedOn: acceptedModel,
      observations: observations
    )
  }
}
