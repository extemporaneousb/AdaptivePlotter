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
    }
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
