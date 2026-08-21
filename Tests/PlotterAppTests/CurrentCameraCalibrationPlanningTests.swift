import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Current-camera calibration planning")
struct CurrentCameraCalibrationPlanningTests {
  @Test("plan creates the exact five-position normalized cross and returns to center")
  func fivePositionCross() throws {
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
        try MachinePosition(x: -24, y: 0),
        try MachinePosition(x: 0, y: 24),
        try MachinePosition(x: 24, y: 0),
        try MachinePosition(x: 0, y: -24),
      ])
    #expect(plan.samples.map(\.position) == [.center, .negativeX, .positiveY, .positiveX, .negativeY])
    #expect(plan.samples.map(\.role) == [.fit, .fit, .fit, .holdout, .holdout])
    #expect(plan.samples.map { [$0.normalizedX, $0.normalizedY] } == [
      [0.5, 0.5], [0.1, 0.5], [0.5, 0.9], [0.9, 0.5], [0.5, 0.1],
    ])
    #expect(
      plan.motionDeltas == [
        try Vector2(dx: -24, dy: 0),
        try Vector2(dx: 24, dy: 24),
        try Vector2(dx: 24, dy: -24),
        try Vector2(dx: -24, dy: -24),
        try Vector2(dx: 0, dy: 24),
      ])
    #expect(plan.applicabilityRectangle == (try AxisAlignedBounds(
      minX: -30, minY: -30, maxX: 30, maxY: 30
    )))
    #expect(plan.rectangleDerivation == .boundaryEnvelopeInsetAndSymmetricallyReduced(
      safetyMarginMM: 10,
      maximumHalfSpanMM: 30
    ))

    let returnedPosition = try plan.motionDeltas.reduce(target.point) { position, delta in
      try Point2(x: position.x + delta.dx, y: position.y + delta.dy)
    }
    #expect(returnedPosition == target.point)
  }

  @Test("plan contracts symmetrically around an off-center target")
  func symmetricContraction() throws {
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

    #expect(plan.applicabilityRectangle == (try AxisAlignedBounds(minX: 50, minY: -70, maxX: 90, maxY: -30)))
    #expect(plan.samplePositions[1] == MachinePosition(point: try Point2(x: 54, y: -50)))
    #expect(plan.samplePositions[2] == MachinePosition(point: try Point2(x: 70, y: -34)))
    #expect(plan.samplePositions[3] == MachinePosition(point: try Point2(x: 86, y: -50)))
    #expect(plan.samplePositions[4] == MachinePosition(point: try Point2(x: 70, y: -66)))
  }

  @Test("sparse mark is a centered 2 mm circle inside its accepted Boundary envelope")
  func circularMarkGeometry() throws {
    let center = try MachinePosition(x: 70, y: 50)
    let mark = try SparseTipCircularMarkPlan(
      center: center,
      boundaryEnvelope: try AxisAlignedBounds(
        minX: -100, minY: -40, maxX: 200, maxY: 180)
    )

    #expect(mark.geometry.kind == .circularOutline)
    #expect(mark.geometry.center == center)
    #expect(mark.geometry.radiusMM == 2)
    #expect(mark.geometry.chordCount == 16)
    #expect(mark.geometry.maximumChordDeviationMM < 0.05)
    #expect(mark.geometry.maximumFeedMMPerMinute == 100)
    #expect(mark.pathDeltas.count == 16)
    for position in mark.pathPositions {
      #expect(abs(position.point.distance(to: center.point) - 2) < 1e-9)
    }
    let pathEnd = try mark.pathDeltas.reduce(mark.startPosition.point) { position, delta in
      try Point2(x: position.x + delta.dx, y: position.y + delta.dy)
    }
    #expect(pathEnd.distance(to: mark.startPosition.point) < 1e-9)
  }

  @Test("Stage 3.4 frames the picture at the 7.5 percent Boundary inset with 80 closed chords")
  func sparseBatchGeometry() throws {
    let envelope = try boundaryEnvelope(
      negativeX: -100,
      positiveX: 100,
      negativeY: -100,
      positiveY: 100
    )
    let batch = try SparseTipBatchMarkPlan(
      boundarySideAggregates: envelope
    )

    #expect(batch.marks.map(\.position) == [
      .center, .negativeX, .positiveY, .positiveX, .negativeY,
    ])
    #expect(batch.marks.map(\.machinePosition) == [
      try MachinePosition(x: 0, y: 0),
      try MachinePosition(x: -85, y: -85),
      try MachinePosition(x: -85, y: 85),
      try MachinePosition(x: 85, y: 85),
      try MachinePosition(x: 85, y: -85),
    ])
    #expect(batch.applicabilityRectangle == (try AxisAlignedBounds(
      minX: -85, minY: -85, maxX: 85, maxY: 85
    )))
    #expect(batch.pictureRectangle == (try AxisAlignedBounds(
      minX: -82.75, minY: -82.75, maxX: 82.75, maxY: 82.75
    )))
    #expect(batch.finalRevealPosition == (try MachinePosition(x: 0, y: 0)))
    #expect(
      try SparseTipBatchMarkPlan.applicabilityRectangle(
        for: batch.marks.map { $0.circle.geometry }) == batch.applicabilityRectangle
    )
    #expect(batch.marks.flatMap { $0.circle.pathDeltas }.count == 80)
    for mark in batch.marks {
      #expect(mark.circle.geometry.radiusMM == 2)
      #expect(mark.circle.geometry.chordCount == 16)
      #expect(mark.circle.geometry.maximumFeedMMPerMinute == 100)
      #expect(mark.circle.pathPositions.first == mark.circle.pathPositions.last)
    }
  }

  @Test("Stage 3.4 computes each Boundary-axis inset independently and enforces minimum clearance")
  func sparseBatchAxisInsetsAndMinimumClearance() throws {
    let wide = try SparseTipBatchMarkPlan(
      boundarySideAggregates: boundaryEnvelope(
        negativeX: 10,
        positiveX: 210,
        negativeY: -10,
        positiveY: 90
      )
    )

    #expect(wide.applicabilityRectangle == (try AxisAlignedBounds(
      minX: 25, minY: -2.5, maxX: 195, maxY: 82.5
    )))
    #expect(wide.pictureRectangle == (try AxisAlignedBounds(
      minX: 27.25, minY: -0.25, maxX: 192.75, maxY: 80.25
    )))

    let narrow = try SparseTipBatchMarkPlan(
      boundarySideAggregates: boundaryEnvelope(
        negativeX: 0,
        positiveX: 20,
        negativeY: 0,
        positiveY: 20
      )
    )
    #expect(narrow.applicabilityRectangle == (try AxisAlignedBounds(
      minX: 2.25, minY: 2.25, maxX: 17.75, maxY: 17.75
    )))
    #expect(narrow.pictureRectangle == (try AxisAlignedBounds(
      minX: 4.5, minY: 4.5, maxX: 15.5, maxY: 15.5
    )))
  }

  @Test("sparse circle refuses any mark that would cross the accepted Boundary envelope")
  func circularMarkRequiresSafeClearance() throws {
    let envelope = try AxisAlignedBounds<MachineSpace>(
      minX: -100, minY: -80, maxX: 100, maxY: 80
    )
    _ = try SparseTipCircularMarkPlan(
      center: MachinePosition(x: 98.013, y: 0),
      boundaryEnvelope: envelope
    )
    #expect(throws: CurrentCameraCalibrationPlanningError.circularMarkOutsideBoundaryEnvelope) {
      try SparseTipCircularMarkPlan(
        center: MachinePosition(x: 98.051, y: 0),
        boundaryEnvelope: envelope
      )
    }
  }

  @Test("boundary-corner checkpoint geometry reconstructs the center and four region corners")
  func restoredCircleGeometry() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -30, minY: -30, maxX: 30, maxY: 30
    )
    let geometry = try ToolContactCalibrationPosition.allCases.map {
      try SparseTipCircularMarkPlan.restoredGeometry(for: $0, in: domain)
    }

    #expect(geometry.map(\.center) == [
      try MachinePosition(x: 0, y: 0),
      try MachinePosition(x: -30, y: -30),
      try MachinePosition(x: -30, y: 30),
      try MachinePosition(x: 30, y: 30),
      try MachinePosition(x: 30, y: -30),
    ])
    #expect(geometry.allSatisfy { $0.radiusMM == 2 })
    #expect(geometry.allSatisfy { $0.chordCount == 16 })
    #expect(geometry.allSatisfy { $0.maximumFeedMMPerMinute == 100 })
  }

  @Test("accepted cardinal checkpoint geometry remains decodable after layout updates")
  func restoredCardinalCircleGeometry() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -30, minY: -30, maxX: 30, maxY: 30
    )
    let geometry = try ToolContactCalibrationPosition.allCases.map {
      try SparseTipCircularMarkPlan.restoredGeometry(
        for: $0,
        in: domain,
        estimatorRevision: SparseTipCircularMarkPlan.cardinalRegistrationEstimatorRevision
      )
    }

    #expect(geometry.map(\.center) == [
      try MachinePosition(x: 0, y: 0),
      try MachinePosition(x: -30, y: 0),
      try MachinePosition(x: 0, y: 30),
      try MachinePosition(x: 30, y: 0),
      try MachinePosition(x: 0, y: -30),
    ])
  }

  @Test("accepted v4 Boundary-corner checkpoint geometry remains decodable without v5 inset semantics")
  func restoredBoundaryCornerV4CircleGeometry() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -30, minY: -30, maxX: 30, maxY: 30
    )
    let geometry = try ToolContactCalibrationPosition.allCases.map {
      try SparseTipCircularMarkPlan.restoredGeometry(
        for: $0,
        in: domain,
        estimatorRevision: SparseTipCircularMarkPlan.boundaryCornerRegistrationEstimatorRevision
      )
    }

    #expect(geometry.map(\.center) == [
      try MachinePosition(x: 0, y: 0),
      try MachinePosition(x: -30, y: -30),
      try MachinePosition(x: -30, y: 30),
      try MachinePosition(x: 30, y: 30),
      try MachinePosition(x: 30, y: -30),
    ])
  }

  @Test("Stage 4 line plan clears all persistent calibration circles")
  func stageFourLineClearsCalibrationMarks() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -30, minY: -30, maxX: 30, maxY: 30
    )
    let marks = try [
      MachinePosition(x: 0, y: 0),
      MachinePosition(x: -30, y: -30),
      MachinePosition(x: -30, y: 30),
      MachinePosition(x: 30, y: 30),
      MachinePosition(x: 30, y: -30),
    ].map {
      try ToolContactMarkGeometryEvidence(
        center: $0, radiusMM: 2, chordCount: 16, maximumFeedMMPerMinute: 100
      )
    }
    let line = try ObservedDrawingTrialLinePlan(
      direction: .positiveX,
      domain: domain,
      existingMarks: marks
    )

    #expect(line.startPosition == (try MachinePosition(x: -2.5, y: 15)))
    #expect(line.endPosition == (try MachinePosition(x: 2.5, y: 15)))
    #expect(line.delta == (try Vector2(dx: 5, dy: 0)))
  }

  @Test("Stage 4 line plan blocks instead of crossing crowded calibration ink")
  func stageFourLineBlocksCrowdedDomain() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -5, minY: -5, maxX: 5, maxY: 5
    )
    let marks = try [
      MachinePosition(x: 0, y: 0),
      MachinePosition(x: -4, y: 0),
      MachinePosition(x: 0, y: 4),
      MachinePosition(x: 4, y: 0),
      MachinePosition(x: 0, y: -4),
    ].map {
      try ToolContactMarkGeometryEvidence(
        center: $0, radiusMM: 2, chordCount: 16, maximumFeedMMPerMinute: 100
      )
    }
    #expect(throws: ObservedDrawingTrialPlanningError.noClearFiveMillimeterLine) {
      try ObservedDrawingTrialLinePlan(
        direction: .positiveX,
        domain: domain,
        existingMarks: marks
      )
    }
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
    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientXAxisSpan) {
      try CurrentCameraCalibrationPlan(
        targetPosition: MachinePosition(x: 0, y: 0),
        boundarySideAggregates: try boundaryEnvelope(
          negativeX: -14,
          positiveX: 14,
          negativeY: -80,
          positiveY: 80
        ),
        controllerSessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision
      )
    }

    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientYAxisSpan) {
      try CurrentCameraCalibrationPlan(
        targetPosition: MachinePosition(x: 0, y: 0),
        boundarySideAggregates: try boundaryEnvelope(
          negativeX: -100,
          positiveX: 100,
          negativeY: -14,
          positiveY: 14
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
      CurrentCameraCalibrationPlanningError.insufficientXAxisSpan.errorDescription?
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
