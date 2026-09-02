import Foundation
import PlotterModel
import PlotterRuntime

enum CurrentCameraCalibrationPlanningError: Error, Equatable, Sendable {
  case incompleteBoundaryEnvelope
  case controllerSessionMismatch(
    direction: BoundaryDirection,
    expected: UUID,
    actual: UUID
  )
  case coordinateRevisionMismatch(
    direction: BoundaryDirection,
    expected: UInt64,
    actual: UInt64
  )
  case centerOutsideSafeEnvelope
  case insufficientXAxisSpan
  case insufficientYAxisSpan
  case insufficientSparseTipXAxisSpan
  case insufficientSparseTipYAxisSpan
  case circularMarkOutsideBoundaryEnvelope
  case unsupportedSparseTipEstimatorRevision(String)
}

extension CurrentCameraCalibrationPlanningError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .incompleteBoundaryEnvelope:
      "Camera calibration requires current accepted boundaries for X−, X+, Y−, and Y+."
    case .controllerSessionMismatch(let direction, let expected, let actual):
      "The accepted \(direction.displayName) Drawing Boundary belongs to controller session \(actual.uuidString.lowercased()), not the current session \(expected.uuidString.lowercased()). Revalidate the accepted machine checkpoint before starting calibration motion."
    case .coordinateRevisionMismatch(let direction, let expected, let actual):
      "The accepted \(direction.displayName) Drawing Boundary uses controller coordinate revision \(actual), not the current revision \(expected). Revalidate the accepted machine checkpoint before starting calibration motion."
    case .centerOutsideSafeEnvelope:
      "The calibration center is outside the accepted Boundary envelope after the 10 mm safety inset."
    case .insufficientXAxisSpan:
      "The accepted X boundaries do not leave a symmetric calibration rectangle with at least 10 mm usable X span."
    case .insufficientYAxisSpan:
      "The accepted Y boundaries do not leave a symmetric calibration rectangle with at least 10 mm usable Y span."
    case .insufficientSparseTipXAxisSpan:
      "The accepted X boundaries must span more than 20 mm to leave four distinct calibration-circle centers after the 10 mm safety inset."
    case .insufficientSparseTipYAxisSpan:
      "The accepted Y boundaries must span more than 20 mm to leave four distinct calibration-circle centers after the 10 mm safety inset."
    case .circularMarkOutsideBoundaryEnvelope:
      "The 2 mm-radius calibration circle would cross the accepted Boundary envelope. Increase the usable paper/machine clearance before drawing."
    case .unsupportedSparseTipEstimatorRevision(let revision):
      "The saved sparse-tip estimator revision \(revision) has no retained mark-geometry decoder."
    }
  }
}

/// One visible Exercise 1.4 mark. The circle is a 16-chord approximation whose
/// maximum radial deviation is below the shared 0.5 mm machine-position
/// acceptance policy.
struct SparseTipCircularMarkPlan: Hashable, Sendable {
  static let radiusMM = 2.0
  static let chordCount = 16
  static let maximumFeedMMPerMinute =
    PlotterMotionThroughput.applicationXYFeedMMPerMinute
  static let registrationEstimatorRevision =
    "affine-first-boundary-10mm-inset-four-circle-2mm-radius-16-chord-v7"
  static let boundaryExtremeFourCircleRegistrationEstimatorRevision =
    "affine-first-boundary-extreme-four-circle-2mm-radius-16-chord-v6"
  static let insetFiveCircleRegistrationEstimatorRevision =
    "affine-first-boundary-inset-five-circle-2mm-radius-16-chord-v5"
  static let boundaryCornerRegistrationEstimatorRevision =
    "affine-first-boundary-corner-five-circle-2mm-radius-16-chord-v4"
  static let cardinalRegistrationEstimatorRevision =
    "affine-first-all-five-circle-2mm-radius-16-chord-v3"

  static func supportsRestoredGeometry(for estimatorRevision: String) -> Bool {
    estimatorRevision == registrationEstimatorRevision
      || estimatorRevision == boundaryExtremeFourCircleRegistrationEstimatorRevision
      || estimatorRevision == insetFiveCircleRegistrationEstimatorRevision
      || estimatorRevision == boundaryCornerRegistrationEstimatorRevision
      || estimatorRevision == cardinalRegistrationEstimatorRevision
  }

  let geometry: ToolContactMarkGeometryEvidence
  let pathPositions: [MachinePosition]
  let pathDeltas: [Vector2<MachineSpace>]

  var startPosition: MachinePosition { pathPositions[0] }

  static func restoredGeometry(
    for position: ToolContactCalibrationPosition,
    in domain: AxisAlignedBounds<MachineSpace>,
    estimatorRevision: String = registrationEstimatorRevision
  ) throws -> ToolContactMarkGeometryEvidence {
    guard supportsRestoredGeometry(for: estimatorRevision) else {
      throw CurrentCameraCalibrationPlanningError.unsupportedSparseTipEstimatorRevision(
        estimatorRevision
      )
    }
    let centerX = (domain.minX + domain.maxX) / 2
    let centerY = (domain.minY + domain.maxY) / 2
    let center: MachinePosition
    if estimatorRevision == cardinalRegistrationEstimatorRevision {
      switch position {
      case .center:
        center = try MachinePosition(x: centerX, y: centerY)
      case .negativeX:
        center = try MachinePosition(x: domain.minX, y: centerY)
      case .positiveY:
        center = try MachinePosition(x: centerX, y: domain.maxY)
      case .positiveX:
        center = try MachinePosition(x: domain.maxX, y: centerY)
      case .negativeY:
        center = try MachinePosition(x: centerX, y: domain.minY)
      }
    } else {
      switch position {
      case .center:
        center = try MachinePosition(x: centerX, y: centerY)
      case .negativeX:
        center = try MachinePosition(x: domain.minX, y: domain.minY)
      case .positiveY:
        center = try MachinePosition(x: domain.minX, y: domain.maxY)
      case .positiveX:
        center = try MachinePosition(x: domain.maxX, y: domain.maxY)
      case .negativeY:
        center = try MachinePosition(x: domain.maxX, y: domain.minY)
      }
    }
    return try ToolContactMarkGeometryEvidence(
      center: center,
      radiusMM: Self.radiusMM,
      chordCount: Self.chordCount,
      maximumFeedMMPerMinute: Self.maximumFeedMMPerMinute
    )
  }

  init(
    center: MachinePosition,
    boundaryEnvelope: AxisAlignedBounds<MachineSpace>
  ) throws {
    let point = center.point
    guard DrawingRegionContainmentPolicy.containsCircle(
      center: point,
      radiusMM: Self.radiusMM,
      in: boundaryEnvelope
    )
    else { throw CurrentCameraCalibrationPlanningError.circularMarkOutsideBoundaryEnvelope }

    var positions = try (0..<Self.chordCount).map { index in
      let angle = 2 * Double.pi * Double(index) / Double(Self.chordCount)
      return try MachinePosition(
        x: point.x + Self.radiusMM * cos(angle),
        y: point.y + Self.radiusMM * sin(angle)
      )
    }
    positions.append(positions[0])
    let deltas = try zip(positions, positions.dropFirst()).map { from, to in
      try Vector2<MachineSpace>(
        dx: to.point.x - from.point.x,
        dy: to.point.y - from.point.y
      )
    }
    geometry = try ToolContactMarkGeometryEvidence(
      center: center,
      radiusMM: Self.radiusMM,
      chordCount: Self.chordCount,
      maximumFeedMMPerMinute: Self.maximumFeedMMPerMinute
    )
    pathPositions = positions
    pathDeltas = deltas
  }
}

/// The complete Exercise 1.4 physical mark layout. The four circle centers are
/// inset 10 mm from the operator-accepted Boundary envelope, leaving 8 mm
/// between each 2 mm-radius outline and its adjacent accepted edges. No center
/// mark is drawn. The final reveal remains a Pen-Up move to the rectangle center.
struct SparseTipBatchMarkPlan: Hashable, Sendable {
  static let boundaryInsetMM = 10.0

  struct Mark: Hashable, Sendable {
    let position: ToolContactCalibrationPosition
    let machinePosition: MachinePosition
    let circle: SparseTipCircularMarkPlan
  }

  let marks: [Mark]
  /// The exact accepted Exercise 1.2 machine-space Boundary from which this batch
  /// is derived. It remains distinct from the inset calibration/Border domain.
  let boundaryEnvelope: AxisAlignedBounds<MachineSpace>
  /// The calibration applicability and 10 mm-inset Drawing Border bounds
  /// through the four observed mark centers.
  let applicabilityRectangle: AxisAlignedBounds<MachineSpace>
  let finalRevealPosition: MachinePosition

  init(
    acceptedBoundaryAggregates: [BoundaryDirection: BoundarySideAggregate]
  ) throws {
    let acceptedBoundary = try Self.boundaryEnvelope(
      for: acceptedBoundaryAggregates
    )
    boundaryEnvelope = acceptedBoundary
    applicabilityRectangle = try Self.drawingBorderBounds(for: acceptedBoundary)
    let center = try MachinePosition(
      x: (applicabilityRectangle.minX + applicabilityRectangle.maxX) / 2,
      y: (applicabilityRectangle.minY + applicabilityRectangle.maxY) / 2
    )
    let plannedPositions: [(ToolContactCalibrationPosition, MachinePosition)] = [
      (.negativeX, try MachinePosition(
        x: applicabilityRectangle.minX, y: applicabilityRectangle.minY)),
      (.positiveY, try MachinePosition(
        x: applicabilityRectangle.minX, y: applicabilityRectangle.maxY)),
      (.positiveX, try MachinePosition(
        x: applicabilityRectangle.maxX, y: applicabilityRectangle.maxY)),
      (.negativeY, try MachinePosition(
        x: applicabilityRectangle.maxX, y: applicabilityRectangle.minY)),
    ]
    marks = try plannedPositions.map { position, machinePosition in
      return Mark(
        position: position,
        machinePosition: machinePosition,
        circle: try SparseTipCircularMarkPlan(
          center: machinePosition,
          boundaryEnvelope: acceptedBoundary
        )
      )
    }
    finalRevealPosition = center
  }

  static func boundaryEnvelope(
    for acceptedBoundaryAggregates: [BoundaryDirection: BoundarySideAggregate]
  ) throws -> AxisAlignedBounds<MachineSpace> {
    guard BoundaryDirection.allCases.allSatisfy({ acceptedBoundaryAggregates[$0] != nil }) else {
      throw CurrentCameraCalibrationPlanningError.incompleteBoundaryEnvelope
    }
    return try AxisAlignedBounds<MachineSpace>(
      minX: acceptedBoundaryAggregates[.negativeX]!.estimateMM,
      minY: acceptedBoundaryAggregates[.negativeY]!.estimateMM,
      maxX: acceptedBoundaryAggregates[.positiveX]!.estimateMM,
      maxY: acceptedBoundaryAggregates[.positiveY]!.estimateMM
    )
  }

  /// Derives the current Drawing Border directly from the accepted Boundary.
  /// This is the one owner of the 10 mm inset used by Exercise 1.4 and 2.1.
  static func drawingBorderBounds(
    for acceptedBoundary: AxisAlignedBounds<MachineSpace>
  ) throws -> AxisAlignedBounds<MachineSpace> {
    let inset = Self.boundaryInsetMM
    guard acceptedBoundary.maxX - acceptedBoundary.minX > 2 * inset else {
      throw CurrentCameraCalibrationPlanningError.insufficientSparseTipXAxisSpan
    }
    guard acceptedBoundary.maxY - acceptedBoundary.minY > 2 * inset else {
      throw CurrentCameraCalibrationPlanningError.insufficientSparseTipYAxisSpan
    }
    return try AxisAlignedBounds<MachineSpace>(
      minX: acceptedBoundary.minX + inset,
      minY: acceptedBoundary.minY + inset,
      maxX: acceptedBoundary.maxX - inset,
      maxY: acceptedBoundary.maxY - inset
    )
  }

  static func applicabilityRectangle(
    for markGeometry: [ToolContactMarkGeometryEvidence]
  ) throws -> AxisAlignedBounds<MachineSpace> {
    let centers = markGeometry.map(\.center.point)
    return try AxisAlignedBounds(
      minX: centers.map(\.x).min()!,
      minY: centers.map(\.y).min()!,
      maxX: centers.map(\.x).max()!,
      maxY: centers.map(\.y).max()!
    )
  }

  /// Restores the smaller ordinary-picture region recorded by the superseded
  /// v5 estimator without applying that inset to later four-corner calibration.
  static func legacyInsetFiveCirclePictureRectangle(
    framedByMarkCenters markCenterRectangle: AxisAlignedBounds<MachineSpace>
  ) throws -> AxisAlignedBounds<MachineSpace> {
    let clearance = SparseTipCircularMarkPlan.radiusMM + 0.25
    return try AxisAlignedBounds<MachineSpace>(
      minX: markCenterRectangle.minX + clearance,
      minY: markCenterRectangle.minY + clearance,
      maxX: markCenterRectangle.maxX - clearance,
      maxY: markCenterRectangle.maxY - clearance
    )
  }
}

/// The closed Stage 2 Drawing Border through the four Exercise 1.4 calibration centers.
/// Consecutive points differ on exactly one axis, giving four right-angle
/// corners and returning to the starting point without a diagonal segment.
struct DrawingBorderPlan: Hashable, Sendable {
  let pathPositions: [MachinePosition]
  let pathDeltas: [Vector2<MachineSpace>]
  let fieldPath: Polyline<FieldSpace>
  let fieldExtent: Size2<FieldSpace>

  var startPosition: MachinePosition { pathPositions[0] }

  init(bounds: AxisAlignedBounds<MachineSpace>) throws {
    pathPositions = try closedMachineRectanglePositions(bounds: bounds)
    pathDeltas = try zip(pathPositions, pathPositions.dropFirst()).map { from, to in
      try from.point.vector(to: to.point)
    }
    let origin = pathPositions[0].point
    fieldPath = try Polyline(
      points: pathPositions.map { position in
        try Point2<FieldSpace>(
          x: position.point.x - origin.x,
          y: position.point.y - origin.y
        )
      }
    )
    fieldExtent = try Size2(
      width: bounds.maxX - bounds.minX,
      height: bounds.maxY - bounds.minY
    )
  }
}

func closedMachineRectanglePositions(
  bounds: AxisAlignedBounds<MachineSpace>
) throws -> [MachinePosition] {
  [
    try MachinePosition(x: bounds.minX, y: bounds.minY),
    try MachinePosition(x: bounds.minX, y: bounds.maxY),
    try MachinePosition(x: bounds.maxX, y: bounds.maxY),
    try MachinePosition(x: bounds.maxX, y: bounds.minY),
    try MachinePosition(x: bounds.minX, y: bounds.minY),
  ]
}

struct CurrentCameraCalibrationSample: Hashable, Sendable {
  let position: ToolContactCalibrationPosition
  let role: TipCalibrationSampleRole
  let normalizedX: Double
  let normalizedY: Double
  let machinePosition: MachinePosition
}

/// Five unique positions inside a Boundary-derived rectangle. `C`, `X−`, and
/// `Y+` fit the first affine model; `X+` and `Y−` are independent holdouts.
/// The final delta returns Pen Up to `C`, ready for sparse contact calibration.
struct CurrentCameraCalibrationPlan: Hashable, Sendable {
  static let safetyMarginMM = 10.0
  static let minimumUsableSpanMM = 10.0
  /// Boundary discovery proves the machine envelope, not paper coverage or
  /// visibility. Until a separate source proves the full safe envelope, keep
  /// this bootstrap rectangle local and symmetric around C.
  static let maximumUnprovenHalfSpanMM = 30.0

  let applicabilityRectangle: AxisAlignedBounds<MachineSpace>
  let rectangleDerivation: MachineCameraRegistrationApplicabilityDerivation
  let samples: [CurrentCameraCalibrationSample]
  let motionDeltas: [Vector2<MachineSpace>]

  var targetPosition: MachinePosition { samples[0].machinePosition }
  var samplePositions: [MachinePosition] { samples.map(\.machinePosition) }
  var fitSamples: [CurrentCameraCalibrationSample] { samples.filter { $0.role == .fit } }
  var holdoutSamples: [CurrentCameraCalibrationSample] {
    samples.filter { $0.role == .holdout }
  }

  init(
    targetPosition: MachinePosition,
    acceptedBoundaryAggregates: [BoundaryDirection: BoundarySideAggregate],
    controllerSessionID: UUID,
    coordinateRevision: UInt64
  ) throws {
    guard BoundaryDirection.allCases.allSatisfy({ acceptedBoundaryAggregates[$0] != nil }) else {
      throw CurrentCameraCalibrationPlanningError.incompleteBoundaryEnvelope
    }
    for direction in BoundaryDirection.allCases {
      let aggregate = acceptedBoundaryAggregates[direction]!
      guard aggregate.controllerSessionID == controllerSessionID else {
        throw CurrentCameraCalibrationPlanningError.controllerSessionMismatch(
          direction: direction,
          expected: controllerSessionID,
          actual: aggregate.controllerSessionID
        )
      }
      guard aggregate.coordinateRevision == coordinateRevision else {
        throw CurrentCameraCalibrationPlanningError.coordinateRevisionMismatch(
          direction: direction,
          expected: coordinateRevision,
          actual: aggregate.coordinateRevision
        )
      }
    }

    let safeMinX = acceptedBoundaryAggregates[.negativeX]!.estimateMM + Self.safetyMarginMM
    let safeMaxX = acceptedBoundaryAggregates[.positiveX]!.estimateMM - Self.safetyMarginMM
    let safeMinY = acceptedBoundaryAggregates[.negativeY]!.estimateMM + Self.safetyMarginMM
    let safeMaxY = acceptedBoundaryAggregates[.positiveY]!.estimateMM - Self.safetyMarginMM
    let center = targetPosition.point
    guard center.x >= safeMinX, center.x <= safeMaxX,
      center.y >= safeMinY, center.y <= safeMaxY
    else { throw CurrentCameraCalibrationPlanningError.centerOutsideSafeEnvelope }

    // The rectangle is deliberately symmetric around the selected center. A
    // smaller paper/visibility-confirmed rectangle can use the same value type
    // later without changing the 10/50/90 sample layout.
    let halfSpanX = [
      center.x - safeMinX,
      safeMaxX - center.x,
      Self.maximumUnprovenHalfSpanMM
    ].min()!
    let halfSpanY = [
      center.y - safeMinY,
      safeMaxY - center.y,
      Self.maximumUnprovenHalfSpanMM
    ].min()!
    let spanX = 2 * halfSpanX
    let spanY = 2 * halfSpanY
    guard spanX >= Self.minimumUsableSpanMM else {
      throw CurrentCameraCalibrationPlanningError.insufficientXAxisSpan
    }
    guard spanY >= Self.minimumUsableSpanMM else {
      throw CurrentCameraCalibrationPlanningError.insufficientYAxisSpan
    }

    let rectangle = try AxisAlignedBounds<MachineSpace>(
      minX: center.x - halfSpanX,
      minY: center.y - halfSpanY,
      maxX: center.x + halfSpanX,
      maxY: center.y + halfSpanY
    )
    func point(_ x: Double, _ y: Double) throws -> MachinePosition {
      try MachinePosition(
        x: rectangle.minX + spanX * x,
        y: rectangle.minY + spanY * y
      )
    }
    let plannedSamples = [
      CurrentCameraCalibrationSample(
        position: .center, role: .fit, normalizedX: 0.5, normalizedY: 0.5,
        machinePosition: try point(0.5, 0.5)
      ),
      CurrentCameraCalibrationSample(
        position: .negativeX, role: .fit, normalizedX: 0.1, normalizedY: 0.5,
        machinePosition: try point(0.1, 0.5)
      ),
      CurrentCameraCalibrationSample(
        position: .positiveY, role: .fit, normalizedX: 0.5, normalizedY: 0.9,
        machinePosition: try point(0.5, 0.9)
      ),
      CurrentCameraCalibrationSample(
        position: .positiveX, role: .holdout, normalizedX: 0.9, normalizedY: 0.5,
        machinePosition: try point(0.9, 0.5)
      ),
      CurrentCameraCalibrationSample(
        position: .negativeY, role: .holdout, normalizedX: 0.5, normalizedY: 0.1,
        machinePosition: try point(0.5, 0.1)
      ),
    ]
    let travelTargets = Array(plannedSamples.dropFirst().map(\.machinePosition)) + [targetPosition]
    let plannedDeltas = try zip(plannedSamples.map(\.machinePosition), travelTargets).map { from, to in
      try Vector2<MachineSpace>(dx: to.point.x - from.point.x, dy: to.point.y - from.point.y)
    }
    applicabilityRectangle = rectangle
    rectangleDerivation = .boundaryEnvelopeInsetAndSymmetricallyReduced(
      safetyMarginMM: Self.safetyMarginMM,
      maximumHalfSpanMM: Self.maximumUnprovenHalfSpanMM
    )
    samples = plannedSamples
    motionDeltas = plannedDeltas
  }
}
