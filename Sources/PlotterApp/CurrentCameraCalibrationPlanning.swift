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
  case circularMarkOutsideBoundaryEnvelope
}

extension CurrentCameraCalibrationPlanningError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .incompleteBoundaryEnvelope:
      "Camera calibration requires current accepted boundaries for X−, X+, Y−, and Y+."
    case .controllerSessionMismatch(let direction, let expected, let actual):
      "The accepted \(direction.displayName) boundary belongs to controller session \(actual.uuidString.lowercased()), not the current session \(expected.uuidString.lowercased()). Revalidate the accepted machine checkpoint before admitting calibration motion."
    case .coordinateRevisionMismatch(let direction, let expected, let actual):
      "The accepted \(direction.displayName) boundary uses controller coordinate revision \(actual), not the current revision \(expected). Revalidate the accepted machine checkpoint before admitting calibration motion."
    case .centerOutsideSafeEnvelope:
      "The calibration center is outside the accepted Boundary envelope after the 10 mm safety inset."
    case .insufficientXAxisSpan:
      "The accepted X boundaries do not leave a symmetric calibration rectangle with at least 10 mm usable X span."
    case .insufficientYAxisSpan:
      "The accepted Y boundaries do not leave a symmetric calibration rectangle with at least 10 mm usable Y span."
    case .circularMarkOutsideBoundaryEnvelope:
      "The 2 mm-radius calibration circle would cross the accepted Boundary envelope. Increase the usable paper/machine clearance before drawing."
    }
  }
}

/// One visible Stage 3.4 mark. The circle is a 16-chord approximation whose
/// maximum radial deviation is below the shared 0.05 mm machine-position
/// acceptance policy.
struct SparseTipCircularMarkPlan: Hashable, Sendable {
  static let radiusMM = 2.0
  static let chordCount = 16
  static let maximumFeedMMPerMinute = 100.0
  static let registrationEstimatorRevision =
    "affine-first-boundary-corner-five-circle-2mm-radius-16-chord-v4"

  let geometry: ToolContactMarkGeometryEvidence
  let pathPositions: [MachinePosition]
  let pathDeltas: [Vector2<MachineSpace>]

  var startPosition: MachinePosition { pathPositions[0] }

  static func restoredGeometry(
    for position: ToolContactCalibrationPosition,
    in domain: AxisAlignedBounds<MachineSpace>
  ) throws -> ToolContactMarkGeometryEvidence {
    let centerX = (domain.minX + domain.maxX) / 2
    let centerY = (domain.minY + domain.maxY) / 2
    let center: MachinePosition
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
    let toleranceMM = MachinePositionAcceptancePolicy.toleranceMM
    guard point.x - Self.radiusMM >= boundaryEnvelope.minX - toleranceMM,
      point.x + Self.radiusMM <= boundaryEnvelope.maxX + toleranceMM,
      point.y - Self.radiusMM >= boundaryEnvelope.minY - toleranceMM,
      point.y + Self.radiusMM <= boundaryEnvelope.maxY + toleranceMM
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

/// The complete Stage 3.4 physical mark layout. The four outer circle centers
/// are the maximum drawable corners inside the accepted Boundary envelope. The
/// fifth circle and final Pen-Up reveal are at that rectangle's center.
struct SparseTipBatchMarkPlan: Hashable, Sendable {
  struct Mark: Hashable, Sendable {
    let position: ToolContactCalibrationPosition
    let machinePosition: MachinePosition
    let circle: SparseTipCircularMarkPlan
  }

  let marks: [Mark]
  let applicabilityRectangle: AxisAlignedBounds<MachineSpace>
  let finalRevealPosition: MachinePosition

  init(
    boundarySideAggregates: [BoundaryDirection: BoundarySideAggregate]
  ) throws {
    guard BoundaryDirection.allCases.allSatisfy({ boundarySideAggregates[$0] != nil }) else {
      throw CurrentCameraCalibrationPlanningError.incompleteBoundaryEnvelope
    }
    let boundaryEnvelope = try AxisAlignedBounds<MachineSpace>(
      minX: boundarySideAggregates[.negativeX]!.estimateMM,
      minY: boundarySideAggregates[.negativeY]!.estimateMM,
      maxX: boundarySideAggregates[.positiveX]!.estimateMM,
      maxY: boundarySideAggregates[.positiveY]!.estimateMM
    )
    applicabilityRectangle = try AxisAlignedBounds<MachineSpace>(
      minX: boundaryEnvelope.minX + SparseTipCircularMarkPlan.radiusMM,
      minY: boundaryEnvelope.minY + SparseTipCircularMarkPlan.radiusMM,
      maxX: boundaryEnvelope.maxX - SparseTipCircularMarkPlan.radiusMM,
      maxY: boundaryEnvelope.maxY - SparseTipCircularMarkPlan.radiusMM
    )
    let center = try MachinePosition(
      x: (applicabilityRectangle.minX + applicabilityRectangle.maxX) / 2,
      y: (applicabilityRectangle.minY + applicabilityRectangle.maxY) / 2
    )
    let plannedPositions: [(ToolContactCalibrationPosition, MachinePosition)] = [
      (.center, center),
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
          boundaryEnvelope: boundaryEnvelope
        )
      )
    }
    finalRevealPosition = center
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
}

enum ObservedDrawingTrialPlanningError: Error, Equatable, Sendable {
  case noClearFiveMillimeterLine
}

extension ObservedDrawingTrialPlanningError: LocalizedError {
  var errorDescription: String? {
    "No 5 mm line inside the accepted tip-calibration rectangle clears all persistent 2 mm-radius calibration circles. Replace the paper and recalibrate with a larger usable rectangle before Stage 4."
  }
}

/// Chooses a 5 mm axis-aligned Stage 4 stroke that cannot cross one of the
/// persistent Stage 3.4 circles. Old ink remains valid baseline evidence, but
/// a new stroke may not be split into multiple components by an old outline.
struct ObservedDrawingTrialLinePlan: Hashable, Sendable {
  static let lengthMM = 5.0
  static let minimumInkClearanceMM = 0.25

  let direction: BoundaryDirection
  let startPosition: MachinePosition
  let endPosition: MachinePosition
  let delta: Vector2<MachineSpace>

  init(
    direction: BoundaryDirection,
    domain: AxisAlignedBounds<MachineSpace>,
    existingMarks: [ToolContactMarkGeometryEvidence]
  ) throws {
    let centerX = (domain.minX + domain.maxX) / 2
    let centerY = (domain.minY + domain.maxY) / 2
    let halfLength = Self.lengthMM / 2
    let spanX = domain.maxX - domain.minX
    let spanY = domain.maxY - domain.minY
    let perpendicularFractions = [0.25, -0.25, 0.375, -0.375]
    let candidates: [(Point2<MachineSpace>, Point2<MachineSpace>)] = try
      perpendicularFractions.map { fraction in
        switch direction {
        case .positiveX:
          let y = centerY + spanY * fraction
          return (
            try Point2(x: centerX - halfLength, y: y),
            try Point2(x: centerX + halfLength, y: y)
          )
        case .negativeX:
          let y = centerY + spanY * fraction
          return (
            try Point2(x: centerX + halfLength, y: y),
            try Point2(x: centerX - halfLength, y: y)
          )
        case .positiveY:
          let x = centerX + spanX * fraction
          return (
            try Point2(x: x, y: centerY - halfLength),
            try Point2(x: x, y: centerY + halfLength)
          )
        case .negativeY:
          let x = centerX + spanX * fraction
          return (
            try Point2(x: x, y: centerY + halfLength),
            try Point2(x: x, y: centerY - halfLength)
          )
        }
      }
    guard let selected = candidates.first(where: { start, end in
      Self.contains(start, in: domain) && Self.contains(end, in: domain)
        && existingMarks.allSatisfy { mark in
          Self.distance(from: mark.center.point, toSegmentFrom: start, to: end)
            > mark.radiusMM + Self.minimumInkClearanceMM
        }
    }) else { throw ObservedDrawingTrialPlanningError.noClearFiveMillimeterLine }
    self.direction = direction
    startPosition = MachinePosition(point: selected.0)
    endPosition = MachinePosition(point: selected.1)
    delta = try selected.0.vector(to: selected.1)
  }

  private static func contains(
    _ point: Point2<MachineSpace>,
    in bounds: AxisAlignedBounds<MachineSpace>
  ) -> Bool {
    MachinePositionAcceptancePolicy.contains(point, in: bounds)
  }

  private static func distance(
    from point: Point2<MachineSpace>,
    toSegmentFrom start: Point2<MachineSpace>,
    to end: Point2<MachineSpace>
  ) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return point.distance(to: start) }
    let projection = ((point.x - start.x) * dx + (point.y - start.y) * dy)
      / lengthSquared
    let t = min(1, max(0, projection))
    let closest = try! Point2<MachineSpace>(
      x: start.x + t * dx,
      y: start.y + t * dy
    )
    return point.distance(to: closest)
  }
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
    boundarySideAggregates: [BoundaryDirection: BoundarySideAggregate],
    controllerSessionID: UUID,
    coordinateRevision: UInt64
  ) throws {
    guard BoundaryDirection.allCases.allSatisfy({ boundarySideAggregates[$0] != nil }) else {
      throw CurrentCameraCalibrationPlanningError.incompleteBoundaryEnvelope
    }
    for direction in BoundaryDirection.allCases {
      let aggregate = boundarySideAggregates[direction]!
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

    let safeMinX = boundarySideAggregates[.negativeX]!.estimateMM + Self.safetyMarginMM
    let safeMaxX = boundarySideAggregates[.positiveX]!.estimateMM - Self.safetyMarginMM
    let safeMinY = boundarySideAggregates[.negativeY]!.estimateMM + Self.safetyMarginMM
    let safeMaxY = boundarySideAggregates[.positiveY]!.estimateMM - Self.safetyMarginMM
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
