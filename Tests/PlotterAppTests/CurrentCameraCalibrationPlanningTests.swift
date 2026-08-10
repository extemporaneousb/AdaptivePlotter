import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Current-camera calibration planning")
struct CurrentCameraCalibrationPlanningTests {
  @Test("plan creates a bounded orthogonal triangle and returns to the target")
  func safeOrthogonalTriangle() throws {
    let target = try MachinePosition(x: 0, y: 0)
    let plan = try CurrentCameraCalibrationPlan(
      targetPosition: target,
      boundarySideAggregates: try boundaryEnvelope(
        negativeX: -100,
        positiveX: 100,
        negativeY: -80,
        positiveY: 80
      ),
      controllerSessionID: calibrationSessionID,
      coordinateRevision: calibrationCoordinateRevision
    )

    #expect(plan.targetPosition == target)
    #expect(
      plan.samplePositions == [
        target,
        try MachinePosition(x: 30, y: 0),
        try MachinePosition(x: 30, y: 30),
      ])
    #expect(
      plan.motionDeltas == [
        try Vector2(dx: 30, dy: 0),
        try Vector2(dx: 0, dy: 30),
        try Vector2(dx: -30, dy: -30),
      ])

    let returnedPosition = try plan.motionDeltas.reduce(target.point) { position, delta in
      try Point2(x: position.x + delta.dx, y: position.y + delta.dy)
    }
    #expect(returnedPosition == target.point)
  }

  @Test("plan selects the direction with more safe clearance on each axis")
  func selectsDirectionWithMoreClearance() throws {
    let plan = try CurrentCameraCalibrationPlan(
      targetPosition: MachinePosition(x: 70, y: -50),
      boundarySideAggregates: try boundaryEnvelope(
        negativeX: -100,
        positiveX: 100,
        negativeY: -80,
        positiveY: 80
      ),
      controllerSessionID: calibrationSessionID,
      coordinateRevision: calibrationCoordinateRevision
    )

    #expect(plan.samplePositions[1] == MachinePosition(point: try Point2(x: 40, y: -50)))
    #expect(plan.samplePositions[2] == MachinePosition(point: try Point2(x: 40, y: -20)))
    #expect(plan.motionDeltas[0] == (try Vector2(dx: -30, dy: 0)))
    #expect(plan.motionDeltas[1] == (try Vector2(dx: 0, dy: 30)))
  }

  @Test("plan refuses an incomplete accepted boundary envelope")
  func refusesIncompleteBoundaryEnvelope() throws {
    var incomplete = try boundaryEnvelope(
      negativeX: -100,
      positiveX: 100,
      negativeY: -80,
      positiveY: 80
    )
    incomplete.removeValue(forKey: .positiveY)

    #expect(throws: CurrentCameraCalibrationPlanningError.incompleteBoundaryEnvelope) {
      try CurrentCameraCalibrationPlan(
        targetPosition: MachinePosition(x: 0, y: 0),
        boundarySideAggregates: incomplete,
        controllerSessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    }
  }

  @Test("plan refuses an axis without the minimum safe calibration excursion")
  func refusesInsufficientClearance() throws {
    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientXAxisClearance) {
      try CurrentCameraCalibrationPlan(
        targetPosition: MachinePosition(x: 0, y: 0),
        boundarySideAggregates: try boundaryEnvelope(
          negativeX: -15,
          positiveX: 15,
          negativeY: -80,
          positiveY: 80
        ),
        controllerSessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    }

    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientYAxisClearance) {
      try CurrentCameraCalibrationPlan(
        targetPosition: MachinePosition(x: 0, y: 0),
        boundarySideAggregates: try boundaryEnvelope(
          negativeX: -100,
          positiveX: 100,
          negativeY: -15,
          positiveY: 15
        ),
        controllerSessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    }
  }

  @Test("plan refuses boundary aggregates from another controller context")
  func refusesMismatchedControllerContext() throws {
    let otherSessionID = UUID(
      uuidString: "00000000-0000-0000-0000-000000000399"
    )!
    var wrongSession = try boundaryEnvelope(
      negativeX: -100,
      positiveX: 100,
      negativeY: -80,
      positiveY: 80
    )
    wrongSession[.positiveY] = try boundaryAggregate(
      .positiveY,
      estimateMM: 80,
      sessionID: otherSessionID,
      coordinateRevision: calibrationCoordinateRevision
    )

    #expect(
      throws: CurrentCameraCalibrationPlanningError.controllerSessionMismatch(
        direction: .positiveY,
        expected: calibrationSessionID,
        actual: otherSessionID
      )
    ) {
      try CurrentCameraCalibrationPlan(
        targetPosition: MachinePosition(x: 0, y: 0),
        boundarySideAggregates: wrongSession,
        controllerSessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    }

    var wrongRevision = try boundaryEnvelope(
      negativeX: -100,
      positiveX: 100,
      negativeY: -80,
      positiveY: 80
    )
    wrongRevision[.negativeX] = try boundaryAggregate(
      .negativeX,
      estimateMM: -100,
      sessionID: calibrationSessionID,
      coordinateRevision: calibrationCoordinateRevision + 1
    )

    #expect(
      throws: CurrentCameraCalibrationPlanningError.coordinateRevisionMismatch(
        direction: .negativeX,
        expected: calibrationCoordinateRevision,
        actual: calibrationCoordinateRevision + 1
      )
    ) {
      try CurrentCameraCalibrationPlan(
        targetPosition: MachinePosition(x: 0, y: 0),
        boundarySideAggregates: wrongRevision,
        controllerSessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    }
  }

  @Test("planner refusals provide actionable operator descriptions")
  func actionableErrorDescriptions() {
    #expect(
      CurrentCameraCalibrationPlanningError.incompleteBoundaryEnvelope.errorDescription?
        .contains("X−, X+, Y−, and Y+") == true
    )
    #expect(
      CurrentCameraCalibrationPlanningError.insufficientXAxisClearance.errorDescription?
        .contains("10 mm") == true
    )
  }
}

private let calibrationSessionID = UUID(
  uuidString: "00000000-0000-0000-0000-000000000301"
)!
private let calibrationCoordinateRevision: UInt64 = 1

private func boundaryEnvelope(
  negativeX: Double,
  positiveX: Double,
  negativeY: Double,
  positiveY: Double
) throws -> [BoundaryDirection: BoundarySideAggregate] {
  return try Dictionary(uniqueKeysWithValues: [
    (
      .negativeX,
      boundaryAggregate(
        .negativeX,
        estimateMM: negativeX,
        sessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    ),
    (
      .positiveX,
      boundaryAggregate(
        .positiveX,
        estimateMM: positiveX,
        sessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    ),
    (
      .negativeY,
      boundaryAggregate(
        .negativeY,
        estimateMM: negativeY,
        sessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    ),
    (
      .positiveY,
      boundaryAggregate(
        .positiveY,
        estimateMM: positiveY,
        sessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    ),
  ])
}

private func boundaryAggregate(
  _ direction: BoundaryDirection,
  estimateMM: Double,
  sessionID: UUID,
  coordinateRevision: UInt64
) throws -> BoundarySideAggregate {
  let estimator = AggregateEstimatorIdentity(
    name: "arithmetic-mean",
    revision: "boundary-machine-coordinate-v1"
  )
  let compatibility = BoundaryNumericCompatibility(
    direction: direction,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    numericEstimatorRevision: estimator.revision
  ).attemptCompatibility
  let attemptID = ExerciseAttemptID()
  let position =
    direction.isXAxis
    ? try MachinePosition(x: estimateMM, y: 0)
    : try MachinePosition(x: 0, y: estimateMM)
  let evidence = try BoundarySideAttemptEvidence(
    attemptID: attemptID,
    direction: direction,
    controllerSessionID: sessionID,
    coordinateRevision: coordinateRevision,
    ownerID: BoundaryMotionOwnerID(),
    stopCapabilityID: UUID(),
    stopIntent: .operatorStop,
    finalPosition: position,
    disposition: .succeeded
  )
  var history = try ExerciseAttemptHistory<BoundarySideAttemptEvidence>(
    compatibility: compatibility
  )
  try history.record(
    ExerciseAttempt(
      id: attemptID,
      disposition: .succeeded,
      compatibility: compatibility,
      acceptedSequence: 1,
      value: evidence
    ))
  return try BoundarySideAggregate(
    direction: direction,
    history: history,
    estimator: estimator
  )
}
