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
  case targetOutsideSafeEnvelope
  case insufficientXAxisClearance
  case insufficientYAxisClearance
}

extension CurrentCameraCalibrationPlanningError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .incompleteBoundaryEnvelope:
      "Automatic camera calibration requires current accepted boundaries for X−, X+, Y−, and Y+."
    case .controllerSessionMismatch(let direction, let expected, let actual):
      "The accepted \(direction.displayName) boundary belongs to controller session \(actual.uuidString.lowercased()), not the current session \(expected.uuidString.lowercased()). Revalidate the accepted machine checkpoint before admitting calibration motion."
    case .coordinateRevisionMismatch(let direction, let expected, let actual):
      "The accepted \(direction.displayName) boundary uses controller coordinate revision \(actual), not the current revision \(expected). Revalidate the accepted machine checkpoint before admitting calibration motion."
    case .targetOutsideSafeEnvelope:
      "The registered target pose is outside the accepted boundary envelope after the 10 mm safety margin. Register a target farther from the accepted boundaries."
    case .insufficientXAxisClearance:
      "The accepted X boundaries do not leave the required 10 mm safe X calibration excursion from this target pose. Register a target with more X clearance."
    case .insufficientYAxisClearance:
      "The accepted Y boundaries do not leave the required 10 mm safe Y calibration excursion from this target pose. Register a target with more Y clearance."
    }
  }
}

/// A target-anchored, machine-space calibration triangle. The first sample is
/// captured without motion; two orthogonal Pen-Up legs create the remaining
/// non-collinear samples, and the final leg returns to the exact target pose.
struct CurrentCameraCalibrationPlan: Hashable, Sendable {
  static let safetyMarginMM = 10.0
  static let minimumExcursionMM = 10.0
  static let maximumExcursionMM = 30.0

  let targetPosition: MachinePosition
  let samplePositions: [MachinePosition]
  let motionDeltas: [Vector2<MachineSpace>]

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

    let negativeX = boundarySideAggregates[.negativeX]!.estimateMM
    let positiveX = boundarySideAggregates[.positiveX]!.estimateMM
    let negativeY = boundarySideAggregates[.negativeY]!.estimateMM
    let positiveY = boundarySideAggregates[.positiveY]!.estimateMM

    let safeNegativeX = negativeX + Self.safetyMarginMM
    let safePositiveX = positiveX - Self.safetyMarginMM
    let safeNegativeY = negativeY + Self.safetyMarginMM
    let safePositiveY = positiveY - Self.safetyMarginMM
    let target = targetPosition.point
    guard target.x >= safeNegativeX, target.x <= safePositiveX,
      target.y >= safeNegativeY, target.y <= safePositiveY
    else {
      throw CurrentCameraCalibrationPlanningError.targetOutsideSafeEnvelope
    }

    let xOffset = Self.preferredOffset(
      negativeClearance: target.x - safeNegativeX,
      positiveClearance: safePositiveX - target.x
    )
    guard abs(xOffset) >= Self.minimumExcursionMM else {
      throw CurrentCameraCalibrationPlanningError.insufficientXAxisClearance
    }
    let yOffset = Self.preferredOffset(
      negativeClearance: target.y - safeNegativeY,
      positiveClearance: safePositiveY - target.y
    )
    guard abs(yOffset) >= Self.minimumExcursionMM else {
      throw CurrentCameraCalibrationPlanningError.insufficientYAxisClearance
    }

    let second = try MachinePosition(x: target.x + xOffset, y: target.y)
    let third = try MachinePosition(x: target.x + xOffset, y: target.y + yOffset)
    self.targetPosition = targetPosition
    samplePositions = [targetPosition, second, third]
    motionDeltas = [
      try Vector2(dx: xOffset, dy: 0),
      try Vector2(dx: 0, dy: yOffset),
      try Vector2(dx: -xOffset, dy: -yOffset),
    ]
  }

  private static func preferredOffset(
    negativeClearance: Double,
    positiveClearance: Double
  ) -> Double {
    if positiveClearance >= negativeClearance {
      return min(maximumExcursionMM, positiveClearance)
    }
    return -min(maximumExcursionMM, negativeClearance)
  }
}
