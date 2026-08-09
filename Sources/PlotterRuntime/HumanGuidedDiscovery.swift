import Foundation
import PlotterModel

public enum BoundaryDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case negativeX
  case positiveX
  case negativeY
  case positiveY

  public var displayName: String {
    switch self {
    case .negativeX: "X−"
    case .positiveX: "X+"
    case .negativeY: "Y−"
    case .positiveY: "Y+"
    }
  }

  fileprivate var stableOrder: Int {
    switch self {
    case .negativeX: 0
    case .positiveX: 1
    case .negativeY: 2
    case .positiveY: 3
    }
  }

  public var opposite: Self {
    switch self {
    case .negativeX: .positiveX
    case .positiveX: .negativeX
    case .negativeY: .positiveY
    case .positiveY: .negativeY
    }
  }

  public var isXAxis: Bool {
    self == .negativeX || self == .positiveX
  }
}

public enum PairedBoundaryProgressError: Error, Equatable, Sendable {
  case directionNotCurrentlyAllowed(BoundaryDirection)
  case directionAlreadyAccepted(BoundaryDirection)
  case duplicateRevision(LearningArtifactRevisionID)
}

/// Pure sequencing policy for the four operator-observed sides. Selecting a
/// direction is intentionally outside this value; only an accepted artifact
/// revision advances it.
public struct PairedBoundaryProgress: Codable, Hashable, Sendable {
  public private(set) var acceptedDirections: [BoundaryDirection]
  public private(set) var acceptedRevisionIDs: [BoundaryDirection: LearningArtifactRevisionID]

  public init(
    acceptedDirections: [BoundaryDirection] = [],
    acceptedRevisionIDs: [BoundaryDirection: LearningArtifactRevisionID] = [:]
  ) {
    precondition(acceptedDirections.count == acceptedRevisionIDs.count)
    precondition(Set(acceptedDirections).count == acceptedDirections.count)
    precondition(Set(acceptedRevisionIDs.values).count == acceptedRevisionIDs.count)
    self.acceptedDirections = acceptedDirections
    self.acceptedRevisionIDs = acceptedRevisionIDs
  }

  public var allowedDirections: [BoundaryDirection] {
    switch acceptedDirections.count {
    case 0:
      return BoundaryDirection.allCases
    case 1:
      return [acceptedDirections[0].opposite]
    case 2:
      let remainingAxisIsX = !acceptedDirections[0].isXAxis
      return BoundaryDirection.allCases.filter { $0.isXAxis == remainingAxisIsX }
    case 3:
      return [acceptedDirections[2].opposite]
    default:
      return []
    }
  }

  public var isComplete: Bool { acceptedDirections.count == 4 }

  public mutating func accept(
    _ direction: BoundaryDirection,
    revisionID: LearningArtifactRevisionID
  ) throws {
    guard acceptedRevisionIDs[direction] == nil else {
      throw PairedBoundaryProgressError.directionAlreadyAccepted(direction)
    }
    guard !acceptedRevisionIDs.values.contains(revisionID) else {
      throw PairedBoundaryProgressError.duplicateRevision(revisionID)
    }
    guard allowedDirections.contains(direction) else {
      throw PairedBoundaryProgressError.directionNotCurrentlyAllowed(direction)
    }
    acceptedDirections.append(direction)
    acceptedRevisionIDs[direction] = revisionID
  }
}

public enum ToolContactPointEstimateError: Error, Equatable, Sendable {
  case invalidConfidence
  case emptyEstimatorRevision
}

/// The estimated paper-contact point is the bottom-center of the measured tool
/// component. It is deliberately retained separately from the component's
/// centroid so downstream registration never silently substitutes one for the
/// other.
public struct ToolContactPointEstimate: Codable, Hashable, Sendable {
  public let point: Point2<CameraPixelSpace>
  public let componentCentroid: Point2<CameraPixelSpace>
  public let componentBounds: AxisAlignedBounds<CameraPixelSpace>
  public let confidence: Double
  public let estimatorRevision: String
  public let source: FrameSourceIdentity
  public let frameID: FrameID
  public let cameraConfigurationID: CameraConfigurationID

  public init(
    componentCentroid: Point2<CameraPixelSpace>,
    componentBounds: AxisAlignedBounds<CameraPixelSpace>,
    confidence: Double,
    estimatorRevision: String,
    source: FrameSourceIdentity,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID
  ) throws {
    guard confidence.isFinite, confidence >= 0, confidence <= 1 else {
      throw ToolContactPointEstimateError.invalidConfidence
    }
    guard !estimatorRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ToolContactPointEstimateError.emptyEstimatorRevision
    }
    point = try Point2(
      x: (componentBounds.minX + componentBounds.maxX) / 2,
      y: componentBounds.maxY
    )
    self.componentCentroid = componentCentroid
    self.componentBounds = componentBounds
    self.confidence = confidence
    self.estimatorRevision = estimatorRevision
    self.source = source
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
  }
}

public enum BoundarySideEvidenceError: Error, Equatable, Sendable {
  case emptyFrameSHA256
  case inconsistentContactProvenance
  case successfulEvidenceRequiresOperatorStop
}

/// Immutable evidence from one exact Boundary attempt. Camera/contact values
/// remain exact attempt provenance and are never averaged into side identity.
public struct BoundarySideAttemptEvidence: Codable, Hashable, Sendable {
  public let attemptID: ExerciseAttemptID
  public let direction: BoundaryDirection
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let ownerID: BoundaryMotionOwnerID
  public let stopCapabilityID: UUID
  public let stopIntent: JogCancelIntent
  public let finalPosition: MachinePosition
  public let frameSource: FrameSourceIdentity
  public let frameID: FrameID
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let contactPoint: ToolContactPointEstimate
  public let contactEstimatorRevision: String
  public let contactConfidence: Double
  public let disposition: ExerciseAttemptDisposition

  public init(
    attemptID: ExerciseAttemptID,
    direction: BoundaryDirection,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    ownerID: BoundaryMotionOwnerID,
    stopCapabilityID: UUID,
    stopIntent: JogCancelIntent,
    finalPosition: MachinePosition,
    frameSource: FrameSourceIdentity,
    frameID: FrameID,
    frameSHA256: String,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    contactPoint: ToolContactPointEstimate,
    disposition: ExerciseAttemptDisposition
  ) throws {
    guard !frameSHA256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw BoundarySideEvidenceError.emptyFrameSHA256
    }
    guard contactPoint.source == frameSource,
      contactPoint.frameID == frameID,
      contactPoint.cameraConfigurationID == cameraConfigurationID
    else {
      throw BoundarySideEvidenceError.inconsistentContactProvenance
    }
    if disposition == .succeeded, stopIntent != .operatorStop {
      throw BoundarySideEvidenceError.successfulEvidenceRequiresOperatorStop
    }
    self.attemptID = attemptID
    self.direction = direction
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.ownerID = ownerID
    self.stopCapabilityID = stopCapabilityID
    self.stopIntent = stopIntent
    self.finalPosition = finalPosition
    self.frameSource = frameSource
    self.frameID = frameID
    self.frameSHA256 = frameSHA256
    self.captureNanoseconds = captureNanoseconds
    self.cameraConfigurationID = cameraConfigurationID
    self.contactPoint = contactPoint
    contactEstimatorRevision = contactPoint.estimatorRevision
    contactConfidence = contactPoint.confidence
    self.disposition = disposition
  }

  public var machineValueMM: Double {
    direction.isXAxis ? finalPosition.point.x : finalPosition.point.y
  }
}

/// The complete identity for pooling machine-space Boundary values. Camera
/// configuration is deliberately absent; optical compatibility is separate.
public struct BoundaryNumericCompatibility: Codable, Hashable, Sendable {
  public let direction: BoundaryDirection
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let coordinateSpace: AttemptCoordinateSpace
  public let units: AttemptUnits
  public let numericEstimatorRevision: String

  public init(
    direction: BoundaryDirection,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    numericEstimatorRevision: String
  ) {
    precondition(!numericEstimatorRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    self.direction = direction
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    coordinateSpace = .machine
    units = .millimeters
    self.numericEstimatorRevision = numericEstimatorRevision
  }

  public var attemptCompatibility: AttemptCompatibility {
    AttemptCompatibility(
      cameraConfigurationID: nil,
      coordinateSpace: coordinateSpace,
      units: units,
      group: AttemptGroupIdentity(
        rawValue:
          "boundary-side-\(direction.rawValue)-\(controllerSessionID.uuidString)-\(coordinateRevision)"
      ),
      algorithmRevision: numericEstimatorRevision
    )
  }
}

public struct BoundarySideAttemptProvenance: Codable, Hashable, Sendable {
  public let attemptID: ExerciseAttemptID
  public let disposition: ExerciseAttemptDisposition
  public let inclusionState: ExerciseAttemptInclusionState
}

public enum BoundarySideAggregateError: Error, Equatable, Sendable {
  case incompatibleHistory(expected: AttemptCompatibility, actual: AttemptCompatibility)
  case noIncludedSamples
  case attemptIdentityMismatch
  case attemptDispositionMismatch
  case directionMismatch(expected: BoundaryDirection, actual: BoundaryDirection)
  case incompatibleControllerContext
  case nonFiniteMachineValue(ExerciseAttemptID)
}

/// Current accepted numeric value for one typed machine direction. Its frame
/// and contact samples remain in the referenced exact attempt evidence.
public struct BoundarySideAggregate: Codable, Hashable, Sendable {
  public let direction: BoundaryDirection
  public let revisionID: LearningArtifactRevisionID
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let coordinateSpace: AttemptCoordinateSpace
  public let units: AttemptUnits
  public let estimateMM: Double
  public let validSampleCount: Int
  public let estimator: AggregateEstimatorIdentity
  public let uncertainty: NumericUncertainty
  public let includedAttemptIDs: [ExerciseAttemptID]
  public let supersededAttempts: [BoundarySideAttemptProvenance]
  public let excludedAttempts: [BoundarySideAttemptProvenance]

  public init(
    direction: BoundaryDirection,
    revisionID: LearningArtifactRevisionID = LearningArtifactRevisionID(),
    history: ExerciseAttemptHistory<BoundarySideAttemptEvidence>,
    estimator: AggregateEstimatorIdentity = AggregateEstimatorIdentity(
      name: "arithmetic-mean",
      revision: "boundary-machine-coordinate-v1"
    )
  ) throws {
    let included = history.includedSuccessfulAttempts
    guard let first = included.first, let firstEvidence = first.value else {
      throw BoundarySideAggregateError.noIncludedSamples
    }
    let compatibility = BoundaryNumericCompatibility(
      direction: direction,
      controllerSessionID: firstEvidence.controllerSessionID,
      coordinateRevision: firstEvidence.coordinateRevision,
      numericEstimatorRevision: estimator.revision
    )
    guard history.compatibility == compatibility.attemptCompatibility else {
      throw BoundarySideAggregateError.incompatibleHistory(
        expected: compatibility.attemptCompatibility,
        actual: history.compatibility
      )
    }

    let values = try included.map { attempt -> Double in
      guard let evidence = attempt.value, evidence.attemptID == attempt.id else {
        throw BoundarySideAggregateError.attemptIdentityMismatch
      }
      guard evidence.disposition == attempt.disposition else {
        throw BoundarySideAggregateError.attemptDispositionMismatch
      }
      guard evidence.direction == direction else {
        throw BoundarySideAggregateError.directionMismatch(
          expected: direction,
          actual: evidence.direction
        )
      }
      guard evidence.controllerSessionID == firstEvidence.controllerSessionID,
        evidence.coordinateRevision == firstEvidence.coordinateRevision
      else {
        throw BoundarySideAggregateError.incompatibleControllerContext
      }
      let value = evidence.machineValueMM
      guard value.isFinite else {
        throw BoundarySideAggregateError.nonFiniteMachineValue(attempt.id)
      }
      return value
    }
    let mean = values.reduce(0, +) / Double(values.count)
    let uncertainty: NumericUncertainty = if values.count == 1 {
      .unavailable(validSampleCount: 1)
    } else {
      .sampleStandardDeviation(
        sqrt(values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1))
      )
    }
    let superseded = history.records.compactMap { record -> BoundarySideAttemptProvenance? in
      guard case .superseded = record.inclusionState else { return nil }
      return BoundarySideAttemptProvenance(
        attemptID: record.attempt.id,
        disposition: record.attempt.disposition,
        inclusionState: record.inclusionState
      )
    }
    let excluded = history.records.compactMap { record -> BoundarySideAttemptProvenance? in
      guard record.inclusionState == .excludedUnsuccessful else { return nil }
      return BoundarySideAttemptProvenance(
        attemptID: record.attempt.id,
        disposition: record.attempt.disposition,
        inclusionState: record.inclusionState
      )
    }
    self.direction = direction
    self.revisionID = revisionID
    controllerSessionID = firstEvidence.controllerSessionID
    coordinateRevision = firstEvidence.coordinateRevision
    coordinateSpace = .machine
    units = .millimeters
    estimateMM = mean
    validSampleCount = values.count
    self.estimator = estimator
    self.uncertainty = uncertainty
    includedAttemptIDs = included.map(\.id)
    supersededAttempts = superseded
    excludedAttempts = excluded
  }

  public var numericCompatibility: BoundaryNumericCompatibility {
    BoundaryNumericCompatibility(
      direction: direction,
      controllerSessionID: controllerSessionID,
      coordinateRevision: coordinateRevision,
      numericEstimatorRevision: estimator.revision
    )
  }
}

public enum EstimatedMachineCenterError: Error, Equatable, Sendable {
  case missingDirection(BoundaryDirection)
  case incompatibleControllerContext
  case duplicateDirection(BoundaryDirection)
  case invalidSpans
  case incompatibleEstimator
}

/// A machine-space midpoint derived from four accepted controller positions.
/// Camera configuration is intentionally absent from its compatibility domain.
public struct EstimatedMachineCenter: Codable, Hashable, Sendable {
  public let point: Point2<MachineSpace>
  public let xSpanMM: Double
  public let ySpanMM: Double
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let consumedRevisionIDs: Set<LearningArtifactRevisionID>
  public let sampleCountByAxis: [String: Int]
  public let estimatorRevision: String

  public static func derive(
    from aggregates: [BoundarySideAggregate],
    estimatorRevision: String = "opposite-side-midpoint-v1"
  ) throws -> Self {
    var byDirection: [BoundaryDirection: BoundarySideAggregate] = [:]
    for aggregate in aggregates {
      guard byDirection[aggregate.direction] == nil else {
        throw EstimatedMachineCenterError.duplicateDirection(aggregate.direction)
      }
      byDirection[aggregate.direction] = aggregate
    }
    for direction in BoundaryDirection.allCases where byDirection[direction] == nil {
      throw EstimatedMachineCenterError.missingDirection(direction)
    }
    let contexts = Set(aggregates.map {
      ControllerCoordinateContext(
        controllerSessionID: $0.controllerSessionID,
        coordinateRevision: $0.coordinateRevision
      )
    })
    guard contexts.count == 1, let context = contexts.first else {
      throw EstimatedMachineCenterError.incompatibleControllerContext
    }
    guard Set(aggregates.map { $0.estimator.revision }).count == 1 else {
      throw EstimatedMachineCenterError.incompatibleEstimator
    }
    let negativeX = byDirection[.negativeX]!.estimateMM
    let positiveX = byDirection[.positiveX]!.estimateMM
    let negativeY = byDirection[.negativeY]!.estimateMM
    let positiveY = byDirection[.positiveY]!.estimateMM
    let xSpan = positiveX - negativeX
    let ySpan = positiveY - negativeY
    guard xSpan.isFinite, ySpan.isFinite, xSpan > 0, ySpan > 0 else {
      throw EstimatedMachineCenterError.invalidSpans
    }
    return Self(
      point: try Point2(x: negativeX + xSpan / 2, y: negativeY + ySpan / 2),
      xSpanMM: xSpan,
      ySpanMM: ySpan,
      controllerSessionID: context.controllerSessionID,
      coordinateRevision: context.coordinateRevision,
      consumedRevisionIDs: Set(aggregates.map(\.revisionID)),
      sampleCountByAxis: [
        "X": byDirection[.negativeX]!.validSampleCount + byDirection[.positiveX]!.validSampleCount,
        "Y": byDirection[.negativeY]!.validSampleCount + byDirection[.positiveY]!.validSampleCount,
      ],
      estimatorRevision: estimatorRevision
    )
  }
}

public enum LearnedLocalCoordinateFrameError: Error, Equatable, Sendable {
  case missingDirection(BoundaryDirection)
  case duplicateDirection(BoundaryDirection)
  case incompatibleControllerContext
  case incompatibleEstimator
  case invalidSpans
}

/// A presentation-only local frame whose origin is the X-/Y- intersection.
/// It is an invertible translation in millimetres and is never motion authority.
public struct LearnedLocalCoordinateFrame: Codable, Hashable, Sendable {
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let origin: Point2<MachineSpace>
  public let xSpanMM: Double
  public let ySpanMM: Double
  public let consumedAggregateRevisionIDs: [BoundaryDirection: LearningArtifactRevisionID]
  public let estimator: AggregateEstimatorIdentity
  public let units: AttemptUnits

  public static func derive(
    from aggregates: [BoundarySideAggregate],
    estimator: AggregateEstimatorIdentity = AggregateEstimatorIdentity(
      name: "lower-side-origin",
      revision: "boundary-local-coordinate-v1"
    )
  ) throws -> Self {
    var byDirection: [BoundaryDirection: BoundarySideAggregate] = [:]
    for aggregate in aggregates {
      guard byDirection[aggregate.direction] == nil else {
        throw LearnedLocalCoordinateFrameError.duplicateDirection(aggregate.direction)
      }
      byDirection[aggregate.direction] = aggregate
    }
    for direction in BoundaryDirection.allCases where byDirection[direction] == nil {
      throw LearnedLocalCoordinateFrameError.missingDirection(direction)
    }
    let contexts = Set(aggregates.map {
      ControllerCoordinateContext(
        controllerSessionID: $0.controllerSessionID,
        coordinateRevision: $0.coordinateRevision
      )
    })
    guard contexts.count == 1, let context = contexts.first else {
      throw LearnedLocalCoordinateFrameError.incompatibleControllerContext
    }
    guard Set(aggregates.map { $0.estimator.revision }).count == 1 else {
      throw LearnedLocalCoordinateFrameError.incompatibleEstimator
    }
    let lowerX = byDirection[.negativeX]!.estimateMM
    let upperX = byDirection[.positiveX]!.estimateMM
    let lowerY = byDirection[.negativeY]!.estimateMM
    let upperY = byDirection[.positiveY]!.estimateMM
    let xSpan = upperX - lowerX
    let ySpan = upperY - lowerY
    guard xSpan.isFinite, ySpan.isFinite, xSpan > 0, ySpan > 0 else {
      throw LearnedLocalCoordinateFrameError.invalidSpans
    }
    return Self(
      controllerSessionID: context.controllerSessionID,
      coordinateRevision: context.coordinateRevision,
      origin: try Point2(x: lowerX, y: lowerY),
      xSpanMM: xSpan,
      ySpanMM: ySpan,
      consumedAggregateRevisionIDs: Dictionary(uniqueKeysWithValues: aggregates.map {
        ($0.direction, $0.revisionID)
      }),
      estimator: estimator,
      units: .millimeters
    )
  }

  public func localPoint(fromRaw rawPoint: Point2<MachineSpace>) throws -> Point2<MachineSpace> {
    try Point2(x: rawPoint.x - origin.x, y: rawPoint.y - origin.y)
  }

  public func rawPoint(fromLocal localPoint: Point2<MachineSpace>) throws -> Point2<MachineSpace> {
    try Point2(x: localPoint.x + origin.x, y: localPoint.y + origin.y)
  }
}

public struct ControllerCoordinateContext: Codable, Hashable, Sendable {
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64

  public init(controllerSessionID: UUID, coordinateRevision: UInt64) {
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
  }
}

/// Runtime provenance around the geometry-only affine fit.
public enum MachineCameraRegistrationError: Error, Equatable, Sendable {
  case invalidValidationPolicy
  case insufficientCorrespondenceProvenance
  case correspondenceSourceMismatch
  case correspondenceControllerMismatch
  case correspondenceCameraMismatch
  case correspondenceContactEstimatorMismatch
  case correspondenceFitMismatch
  case validationResidualExceeded(actualPixels: Double, maximumPixels: Double)
}

public struct MachineCameraCorrespondenceProvenance: Codable, Hashable, Sendable {
  public let machinePoint: Point2<MachineSpace>
  public let contactPoint: Point2<CameraPixelSpace>
  public let source: FrameSourceIdentity
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let frameID: FrameID
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let attemptID: ExerciseAttemptID
  public let contactEstimatorRevision: String
  public let algorithmRevision: String
  public let contactConfidence: Double
  public let artifactRevisionID: LearningArtifactRevisionID

  public init(
    machinePoint: Point2<MachineSpace>,
    contactPoint: Point2<CameraPixelSpace>,
    source: FrameSourceIdentity,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    frameID: FrameID,
    frameSHA256: String,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    attemptID: ExerciseAttemptID,
    contactEstimatorRevision: String,
    algorithmRevision: String,
    contactConfidence: Double,
    artifactRevisionID: LearningArtifactRevisionID
  ) {
    precondition(!frameSHA256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    precondition(
      !contactEstimatorRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
    precondition(!algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    precondition(contactConfidence.isFinite && contactConfidence >= 0 && contactConfidence <= 1)
    self.machinePoint = machinePoint
    self.contactPoint = contactPoint
    self.source = source
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.frameID = frameID
    self.frameSHA256 = frameSHA256
    self.captureNanoseconds = captureNanoseconds
    self.cameraConfigurationID = cameraConfigurationID
    self.attemptID = attemptID
    self.contactEstimatorRevision = contactEstimatorRevision
    self.algorithmRevision = algorithmRevision
    self.contactConfidence = contactConfidence
    self.artifactRevisionID = artifactRevisionID
  }
}

public struct MachineCameraRegistration: Codable, Hashable, Sendable {
  public let fit: MachineCameraRegistrationFit
  public let source: FrameSourceIdentity
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let correspondenceProvenance: [MachineCameraCorrespondenceProvenance]
  public let correspondenceFrameIDs: Set<FrameID>
  public let correspondenceRevisionIDs: Set<LearningArtifactRevisionID>
  public let contactEstimatorRevision: String
  public let validationTargetFrameID: FrameID
  public let validationMachinePoint: Point2<MachineSpace>
  public let validationContactPoint: Point2<CameraPixelSpace>
  public let validationResidualPixels: Double
  public let maximumValidationResidualPixels: Double
  public let estimatorRevision: String
  public let uncertaintyPixels: Double

  public init(
    fit: MachineCameraRegistrationFit,
    source: FrameSourceIdentity,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    correspondenceProvenance: [MachineCameraCorrespondenceProvenance],
    validationTargetFrameID: FrameID,
    validationMachinePoint: Point2<MachineSpace>,
    validationContactPoint: Point2<CameraPixelSpace>,
    maximumValidationResidualPixels: Double,
    estimatorRevision: String,
    uncertaintyPixels: Double
  ) throws {
    precondition(!estimatorRevision.isEmpty)
    precondition(uncertaintyPixels.isFinite && uncertaintyPixels >= 0)
    guard maximumValidationResidualPixels.isFinite, maximumValidationResidualPixels >= 0 else {
      throw MachineCameraRegistrationError.invalidValidationPolicy
    }
    guard correspondenceProvenance.count >= 3 else {
      throw MachineCameraRegistrationError.insufficientCorrespondenceProvenance
    }
    guard Set(correspondenceProvenance.map(\.source)) == [source] else {
      throw MachineCameraRegistrationError.correspondenceSourceMismatch
    }
    guard correspondenceProvenance.allSatisfy({
      $0.controllerSessionID == controllerSessionID
        && $0.coordinateRevision == coordinateRevision
    }) else {
      throw MachineCameraRegistrationError.correspondenceControllerMismatch
    }
    guard Set(correspondenceProvenance.map(\.cameraConfigurationID)) == [cameraConfigurationID] else {
      throw MachineCameraRegistrationError.correspondenceCameraMismatch
    }
    let contactEstimatorRevisions = Set(correspondenceProvenance.map(\.contactEstimatorRevision))
    guard contactEstimatorRevisions.count == 1,
      let contactEstimatorRevision = contactEstimatorRevisions.first
    else {
      throw MachineCameraRegistrationError.correspondenceContactEstimatorMismatch
    }
    let fitPairs = Set(fit.correspondences)
    let provenancePairs = Set(correspondenceProvenance.map {
      MachineCameraRegistrationCorrespondence(
        machine: $0.machinePoint,
        camera: $0.contactPoint
      )
    })
    guard fitPairs == provenancePairs else {
      throw MachineCameraRegistrationError.correspondenceFitMismatch
    }
    let predicted = try fit.cameraPoint(from: validationMachinePoint)
    let validationResidual = predicted.distance(to: validationContactPoint)
    guard validationResidual <= maximumValidationResidualPixels else {
      throw MachineCameraRegistrationError.validationResidualExceeded(
        actualPixels: validationResidual,
        maximumPixels: maximumValidationResidualPixels
      )
    }
    self.fit = fit
    self.source = source
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.cameraConfigurationID = cameraConfigurationID
    self.correspondenceProvenance = correspondenceProvenance
    correspondenceFrameIDs = Set(correspondenceProvenance.map(\.frameID))
    correspondenceRevisionIDs = Set(correspondenceProvenance.map(\.artifactRevisionID))
    self.contactEstimatorRevision = contactEstimatorRevision
    self.validationTargetFrameID = validationTargetFrameID
    self.validationMachinePoint = validationMachinePoint
    self.validationContactPoint = validationContactPoint
    validationResidualPixels = validationResidual
    self.maximumValidationResidualPixels = maximumValidationResidualPixels
    self.estimatorRevision = estimatorRevision
    self.uncertaintyPixels = uncertaintyPixels
  }
}

public struct BoundaryMotionOwnerID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

/// One logical operator-stopped boundary operation. `segment` is a finite GRBL
/// wire request, not an application boundary or successful completion horizon.
public struct BoundaryMotionRequest: Hashable, Sendable {
  public let ownerID: BoundaryMotionOwnerID
  public let direction: BoundaryDirection
  public let segment: RelativeJogRequest

  public init(
    ownerID: BoundaryMotionOwnerID = BoundaryMotionOwnerID(),
    direction: BoundaryDirection,
    segment: RelativeJogRequest
  ) {
    precondition(Self.matches(direction: direction, delta: segment.delta))
    self.ownerID = ownerID
    self.direction = direction
    self.segment = segment
  }

  private static func matches(
    direction: BoundaryDirection,
    delta: Vector2<MachineSpace>
  ) -> Bool {
    switch direction {
    case .negativeX: delta.dx < 0 && delta.dy == 0
    case .positiveX: delta.dx > 0 && delta.dy == 0
    case .negativeY: delta.dy < 0 && delta.dx == 0
    case .positiveY: delta.dy > 0 && delta.dx == 0
    }
  }
}

public enum JogCancelIntent: String, Codable, Hashable, Sendable {
  case operatorStop
  case cancelAttempt
  case shutdown
}

public struct BoundaryMotionSettlement: Hashable, Sendable {
  public let ownerID: BoundaryMotionOwnerID
  public let intent: JogCancelIntent
  public let completedSegmentCount: Int
  public let finalPosition: MachinePosition
  public let jogCancelOutcome: JogCancelOutcome

  public init(
    ownerID: BoundaryMotionOwnerID,
    intent: JogCancelIntent,
    completedSegmentCount: Int,
    finalPosition: MachinePosition,
    jogCancelOutcome: JogCancelOutcome
  ) {
    precondition(completedSegmentCount >= 0)
    self.ownerID = ownerID
    self.intent = intent
    self.completedSegmentCount = completedSegmentCount
    self.finalPosition = finalPosition
    self.jogCancelOutcome = jogCancelOutcome
  }
}

public enum BoundaryMotionTerminal: Hashable, Sendable {
  case limitAsserted(pins: String, finalPosition: MachinePosition?)
  case alarm(String)
  case refusal(MotionRefusal)
  case disconnected
  case fault(MotionAmbiguity)
}

public enum BoundaryMotionOutcome: Hashable, Sendable {
  case settled(BoundaryMotionSettlement)
  case needsAttention(ownerID: BoundaryMotionOwnerID, terminal: BoundaryMotionTerminal)
}

public enum DiscoverySequenceID: String, Codable, CaseIterable, Hashable, Sendable {
  case boundaryNegativeX
  case boundaryPositiveX
  case boundaryNegativeY
  case boundaryPositiveY
  case penInteraction
}

public enum DiscoveryParticipant: String, Codable, CaseIterable, Hashable, Sendable {
  case application
  case operatorChoice
  case controller
  case camera
  case vision

  public var displayName: String {
    switch self {
    case .application: "AdaptivePlotter"
    case .operatorChoice: "Operator"
    case .controller: "Plotter controller"
    case .camera: "Camera"
    case .vision: "Vision"
    }
  }
}

/// Short answers are accepted only while their defining discovery question is
/// current. A response has no ambient controller meaning.
public enum OperatorChoice: String, Codable, CaseIterable, Hashable, Sendable {
  case yes = "YES"
  case no = "NO"

  public var exactPhrase: String { rawValue }
}

public struct DiscoveryQuestion: Hashable, Sendable {
  public let prompt: String
  public let choices: [OperatorChoice]
  public let advancingChoices: Set<OperatorChoice>
  public let negativeAcknowledgement: String

  public init(
    prompt: String,
    choices: [OperatorChoice] = [.yes, .no],
    advancingChoices: Set<OperatorChoice> = [.yes],
    negativeAcknowledgement: String
  ) {
    precondition(!choices.isEmpty)
    precondition(advancingChoices.isSubset(of: Set(choices)))
    self.prompt = prompt
    self.choices = choices
    self.advancingChoices = advancingChoices
    self.negativeAcknowledgement = negativeAcknowledgement
  }

  public var choiceLabel: String {
    choices.map(\.exactPhrase).joined(separator: " / ")
  }
}

public enum DiscoveryAction: Hashable, Sendable {
  case askQuestion(DiscoveryQuestion)
  case awaitOperatorChoice(DiscoveryQuestion)
  case announce(String)
  case startBoundaryJog(BoundaryDirection)
  case awaitContextualStop(BoundaryDirection)
  case cancelBoundaryJogAndAwaitIdle(BoundaryDirection)
  case captureFreshCameraFrame
  case measureBoundary(BoundaryDirection)
  case commitBoundaryObservation(BoundaryDirection)
  case actuatePen(PenCommand)
  case awaitPhysicalPenConfirmation(PenState, question: DiscoveryQuestion)
}

public enum DiscoveryEventExpectation: Hashable, Sendable {
  case questionPresented
  case operatorChoice(Set<OperatorChoice>)
  case announcementCompleted
  case boundaryJogStarted(BoundaryDirection)
  case operatorStopRequested(BoundaryDirection)
  case boundaryJogCancelled(BoundaryDirection)
  case freshFrameCaptured
  case boundaryMeasured(BoundaryDirection)
  case boundaryObservationCommitted(BoundaryDirection)
  case penCommandSettled(PenCommand)
  case physicalPenConfirmed(PenState, response: OperatorChoice)

  fileprivate func accepts(_ event: DiscoveryEvent) -> Bool {
    switch (self, event) {
    case (.questionPresented, .questionPresented):
      true
    case (.operatorChoice(let expected), .operatorChoiceAccepted(let actual)):
      expected.contains(actual)
    case (.announcementCompleted, .announcementCompleted):
      true
    case (.boundaryJogStarted(let expected), .boundaryJogStarted(let actual, _)):
      expected == actual
    case (.operatorStopRequested(let expected), .operatorStopRequested(let actual)):
      expected == actual
    case (.boundaryJogCancelled(let expected), .boundaryJogCancelled(let actual, _, _)):
      expected == actual
    case (.freshFrameCaptured, .freshFrameCaptured):
      true
    case (.boundaryMeasured(let expected), .boundaryMeasured(let actual, _, _, _, _, _, _)):
      expected == actual
    case (.boundaryObservationCommitted(let expected), .boundaryObservationCommitted(let evidence, let aggregate)):
      expected == evidence.direction && aggregate.direction == expected
    case (.penCommandSettled(let expected), .penCommandSettled(let actual, _)):
      expected == actual
    case (
      .physicalPenConfirmed(let expectedState, let expectedResponse),
      .physicalPenConfirmed(let actualState, let actualResponse, _)
    ):
      expectedState == actualState && expectedResponse == actualResponse
    default:
      false
    }
  }
}

public struct DiscoveryStep: Hashable, Sendable, Identifiable {
  public let id: String
  public let participant: DiscoveryParticipant
  public let action: DiscoveryAction
  public let expectedEvent: DiscoveryEventExpectation

  public init(
    id: String,
    participant: DiscoveryParticipant,
    action: DiscoveryAction,
    expectedEvent: DiscoveryEventExpectation
  ) {
    self.id = id
    self.participant = participant
    self.action = action
    self.expectedEvent = expectedEvent
  }

  public var question: DiscoveryQuestion? {
    switch action {
    case .awaitOperatorChoice(let question), .awaitPhysicalPenConfirmation(_, let question):
      question
    default:
      nil
    }
  }
}

public struct DiscoverySequenceDefinition: Hashable, Sendable, Identifiable {
  public let id: DiscoverySequenceID
  public let title: String
  public let summary: String
  public let steps: [DiscoveryStep]

  public init(
    id: DiscoverySequenceID,
    title: String,
    summary: String,
    steps: [DiscoveryStep]
  ) {
    self.id = id
    self.title = title
    self.summary = summary
    self.steps = steps
  }

  public var questions: [DiscoveryQuestion] {
    steps.compactMap(\.question)
  }
}

public enum DiscoverySequenceCatalog {
  public static let title = "Human-Guided Discovery"

  public static let all: [DiscoverySequenceDefinition] = DiscoverySequenceID.allCases.map {
    definition(for: $0)
  }

  public static func definition(for id: DiscoverySequenceID) -> DiscoverySequenceDefinition {
    switch id {
    case .boundaryNegativeX:
      boundary(.negativeX, id: id)
    case .boundaryPositiveX:
      boundary(.positiveX, id: id)
    case .boundaryNegativeY:
      boundary(.negativeY, id: id)
    case .boundaryPositiveY:
      boundary(.positiveY, id: id)
    case .penInteraction:
      penInteraction(id: id)
    }
  }

  private static func boundary(
    _ direction: BoundaryDirection,
    id: DiscoverySequenceID
  ) -> DiscoverySequenceDefinition {
    return DiscoverySequenceDefinition(
      id: id,
      title: "\(direction.displayName) Boundary Discovery",
      summary: "Move toward \(direction.displayName), Stop at the observed boundary, and update one exact-frame side observation.",
      steps: [
        DiscoveryStep(
          id: "announce-jog",
          participant: .application,
          action: .announce("Moving toward \(direction.displayName) boundary."),
          expectedEvent: .announcementCompleted
        ),
        DiscoveryStep(
          id: "start-jog",
          participant: .controller,
          action: .startBoundaryJog(direction),
          expectedEvent: .boundaryJogStarted(direction)
        ),
        DiscoveryStep(
          id: "stop-boundary",
          participant: .operatorChoice,
          action: .awaitContextualStop(direction),
          expectedEvent: .operatorStopRequested(direction)
        ),
        DiscoveryStep(
          id: "cancel-and-idle",
          participant: .controller,
          action: .cancelBoundaryJogAndAwaitIdle(direction),
          expectedEvent: .boundaryJogCancelled(direction)
        ),
        DiscoveryStep(
          id: "capture-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
        DiscoveryStep(
          id: "measure-boundary",
          participant: .vision,
          action: .measureBoundary(direction),
          expectedEvent: .boundaryMeasured(direction)
        ),
        DiscoveryStep(
          id: "commit-boundary-observation",
          participant: .application,
          action: .commitBoundaryObservation(direction),
          expectedEvent: .boundaryObservationCommitted(direction)
        ),
      ]
    )
  }

  private static func penInteraction(id: DiscoverySequenceID) -> DiscoverySequenceDefinition {
    let initiallyUp = DiscoveryQuestion(
      prompt: "Is the pen currently up?",
      negativeAcknowledgement:
        "The sequence needs an observed up position before it can continue. I will wait."
    )
    let currentlyDown = DiscoveryQuestion(
      prompt: "Is the pen currently down?",
      negativeAcknowledgement:
        "The down position was not confirmed. I will command Pen Up and end this cycle."
    )
    let finallyUp = DiscoveryQuestion(
      prompt: "Is the pen up?",
      negativeAcknowledgement: "The final up position was not confirmed. I will wait."
    )
    return DiscoverySequenceDefinition(
      id: id,
      title: "Pen Interaction",
      summary:
        "Confirm up, lower after the explicit spoken cue, observe down, retract, and confirm up.",
      steps: [
        DiscoveryStep(
          id: "question-initially-up",
          participant: .application,
          action: .askQuestion(initiallyUp),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-initially-up",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.up, question: initiallyUp),
          expectedEvent: .physicalPenConfirmed(.up, response: .yes)
        ),
        DiscoveryStep(
          id: "announce-down",
          participant: .application,
          action: .announce("Lowering the pen."),
          expectedEvent: .announcementCompleted
        ),
        DiscoveryStep(
          id: "command-down",
          participant: .controller,
          action: .actuatePen(.lower),
          expectedEvent: .penCommandSettled(.lower)
        ),
        DiscoveryStep(
          id: "question-currently-down",
          participant: .application,
          action: .askQuestion(currentlyDown),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-currently-down",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.down, question: currentlyDown),
          expectedEvent: .physicalPenConfirmed(.down, response: .yes)
        ),
        DiscoveryStep(
          id: "capture-down-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
        DiscoveryStep(
          id: "announce-up",
          participant: .application,
          action: .announce("Raising the pen."),
          expectedEvent: .announcementCompleted
        ),
        DiscoveryStep(
          id: "command-up",
          participant: .controller,
          action: .actuatePen(.raise),
          expectedEvent: .penCommandSettled(.raise)
        ),
        DiscoveryStep(
          id: "question-finally-up",
          participant: .application,
          action: .askQuestion(finallyUp),
          expectedEvent: .questionPresented
        ),
        DiscoveryStep(
          id: "answer-finally-up",
          participant: .operatorChoice,
          action: .awaitPhysicalPenConfirmation(.up, question: finallyUp),
          expectedEvent: .physicalPenConfirmed(.up, response: .yes)
        ),
        DiscoveryStep(
          id: "capture-up-frame",
          participant: .camera,
          action: .captureFreshCameraFrame,
          expectedEvent: .freshFrameCaptured
        ),
      ]
    )
  }
}

public enum DiscoveryEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
  case operatorChoice
  case operatorObservation
  case controller
  case camera
  case visionMeasurement
  case observedInk
}

/// Current-transaction evidence only. `observedInk` is deliberately distinct
/// from controller acceptance, camera capture, and inferred vision geometry.
public struct DiscoveryEvidenceSummary: Hashable, Sendable {
  public let kind: DiscoveryEvidenceKind
  public let summary: String
  public let frameID: FrameID?
  public let cameraConfigurationID: CameraConfigurationID?

  public init(
    kind: DiscoveryEvidenceKind,
    summary: String,
    frameID: FrameID? = nil,
    cameraConfigurationID: CameraConfigurationID? = nil
  ) {
    self.kind = kind
    self.summary = summary
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
  }
}

public enum DiscoveryEvent: Hashable, Sendable {
  case questionPresented
  case operatorChoiceAccepted(OperatorChoice)
  case announcementCompleted
  case boundaryJogStarted(BoundaryDirection, controllerSummary: String)
  case operatorStopRequested(BoundaryDirection)
  case boundaryJogCancelled(
    BoundaryDirection,
    finalPosition: MachinePosition,
    controllerSummary: String
  )
  case freshFrameCaptured(FrameID, CameraConfigurationID)
  case boundaryMeasured(
    BoundaryDirection,
    controllerPosition: MachinePosition,
    observedToolCentroid: Point2<CameraPixelSpace>,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    confidence: Double,
    summary: String
  )
  case boundaryObservationCommitted(
    BoundarySideAttemptEvidence,
    aggregate: BoundarySideAggregate
  )
  case penCommandSettled(PenCommand, controllerSummary: String)
  case physicalPenConfirmed(
    PenState,
    response: OperatorChoice,
    operatorSummary: String
  )

  fileprivate var evidenceSummary: DiscoveryEvidenceSummary? {
    switch self {
    case .questionPresented, .announcementCompleted:
      nil
    case .operatorChoiceAccepted(let response):
      DiscoveryEvidenceSummary(
        kind: .operatorChoice,
        summary: "Accepted contextual choice: \(response.exactPhrase)"
      )
    case .operatorStopRequested(let direction):
      DiscoveryEvidenceSummary(
        kind: .operatorChoice,
        summary: "Operator requested Stop during \(direction.displayName) Boundary Discovery."
      )
    case .boundaryJogStarted(_, let summary),
      .boundaryJogCancelled(_, _, let summary),
      .penCommandSettled(_, let summary):
      DiscoveryEvidenceSummary(kind: .controller, summary: summary)
    case .freshFrameCaptured(let frameID, let configurationID):
      DiscoveryEvidenceSummary(
        kind: .camera,
        summary: "Captured exact discovery frame \(frameID.rawValue).",
        frameID: frameID,
        cameraConfigurationID: configurationID
      )
    case .boundaryMeasured(
      let direction,
      let controllerPosition,
      let observedToolCentroid,
      let frameID,
      let configurationID,
      _,
      let summary
    ):
      DiscoveryEvidenceSummary(
        kind: .visionMeasurement,
        summary:
          "\(direction.displayName) at controller X \(controllerPosition.point.x) Y \(controllerPosition.point.y), observed tool pixel X \(observedToolCentroid.x) Y \(observedToolCentroid.y): \(summary)",
        frameID: frameID,
        cameraConfigurationID: configurationID
      )
    case .boundaryObservationCommitted(let evidence, let aggregate):
      DiscoveryEvidenceSummary(
        kind: .visionMeasurement,
        summary:
          "Committed \(evidence.direction.displayName) Boundary aggregate revision \(aggregate.revisionID.rawValue) from N=\(aggregate.validSampleCount) exact attempt sample(s).",
        frameID: evidence.frameID,
        cameraConfigurationID: evidence.cameraConfigurationID
      )
    case .physicalPenConfirmed(let state, _, let summary):
      DiscoveryEvidenceSummary(
        kind: .operatorObservation,
        summary: "Pen physically \(state.rawValue): \(summary)"
      )
    }
  }
}

public enum DiscoveryTransactionState: Hashable, Sendable {
  case notStarted
  case active
  case cancelling
  case succeeded
  case failed(String)
  case cancelled
}

public enum DiscoveryTransactionError: Error, Equatable, Sendable {
  case alreadyStarted
  case notActive
  case noCurrentStep
  case unexpectedEvent(stepID: String)
  case invalidBoundaryConfidence
  case invalidBoundaryCommit
}

/// A small in-memory transaction for driving and presenting one sequence.
/// It has no persistence, replay, or cross-launch authority.
public struct DiscoveryTransaction: Hashable, Sendable, Identifiable {
  public let id: UUID
  public let definition: DiscoverySequenceDefinition
  public private(set) var state: DiscoveryTransactionState
  public private(set) var completedStepCount: Int
  public private(set) var evidenceSummaries: [DiscoveryEvidenceSummary]

  public init(id: UUID = UUID(), definition: DiscoverySequenceDefinition) {
    self.id = id
    self.definition = definition
    state = .notStarted
    completedStepCount = 0
    evidenceSummaries = []
  }

  public init(id: UUID = UUID(), sequenceID: DiscoverySequenceID) {
    self.init(id: id, definition: DiscoverySequenceCatalog.definition(for: sequenceID))
  }

  public var currentStep: DiscoveryStep? {
    switch state {
    case .active where completedStepCount < definition.steps.count:
      return definition.steps[completedStepCount]
    default:
      return nil
    }
  }

  public var progress: Double {
    guard !definition.steps.isEmpty else { return state == .succeeded ? 1 : 0 }
    return Double(completedStepCount) / Double(definition.steps.count)
  }

  public mutating func begin() throws {
    guard state == .notStarted else { throw DiscoveryTransactionError.alreadyStarted }
    state = definition.steps.isEmpty ? .succeeded : .active
  }

  public mutating func record(_ event: DiscoveryEvent) throws {
    guard state == .active else { throw DiscoveryTransactionError.notActive }
    guard let step = currentStep else { throw DiscoveryTransactionError.noCurrentStep }
    try Self.validateEvidence(in: event)
    guard step.expectedEvent.accepts(event) else {
      throw DiscoveryTransactionError.unexpectedEvent(stepID: step.id)
    }
    if let evidence = event.evidenceSummary {
      evidenceSummaries.append(evidence)
    }
    completedStepCount += 1
    if completedStepCount == definition.steps.count {
      state = .succeeded
    }
  }

  public mutating func fail(_ actionableReason: String) {
    guard state == .active else { return }
    state = .failed(actionableReason)
  }

  public mutating func cancel() {
    switch state {
    case .notStarted:
      state = .cancelled
    case .active:
      state = .cancelled
    default:
      break
    }
  }

  private static func validateEvidence(in event: DiscoveryEvent) throws {
    switch event {
    case .boundaryMeasured(_, _, _, _, _, let confidence, _):
      guard confidence.isFinite, confidence >= 0, confidence <= 1 else {
        throw DiscoveryTransactionError.invalidBoundaryConfidence
      }
    case .boundaryObservationCommitted(let evidence, let aggregate):
      guard evidence.disposition == .succeeded,
        aggregate.direction == evidence.direction,
        aggregate.includedAttemptIDs.contains(evidence.attemptID),
        aggregate.validSampleCount > 0
      else {
        throw DiscoveryTransactionError.invalidBoundaryCommit
      }
    default:
      break
    }
  }
}
