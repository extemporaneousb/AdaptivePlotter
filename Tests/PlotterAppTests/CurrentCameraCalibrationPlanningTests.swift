import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Current-camera calibration planning")
struct CurrentCameraCalibrationPlanningTests {
  @Test("minimum calibration span survives fractional translation without admitting a smaller envelope")
  func fractionalMinimumCalibrationSpan() throws {
    let target = try MachinePosition(x: 0.2, y: -0.2)
    let plan = try CurrentCameraCalibrationPlan(
      targetPosition: target,
      acceptedBoundaryAggregates: boundaryEnvelope(
        negativeX: -14.8, positiveX: 15.2, negativeY: -15.2, positiveY: 14.8),
      controllerSessionID: calibrationSessionID,
      coordinateRevision: calibrationCoordinateRevision)
    #expect(plan.samplePositions[0] == target)
    #expect(plan.samplePositions.count == 5)
    #expect(abs(plan.applicabilityRectangle.maxX - plan.applicabilityRectangle.minX - 10) < 1e-12)
    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientXAxisSpan) {
      try CurrentCameraCalibrationPlan(
        targetPosition: target,
        acceptedBoundaryAggregates: boundaryEnvelope(
          negativeX: -14.799, positiveX: 15.2, negativeY: -15.2, positiveY: 14.8),
        controllerSessionID: calibrationSessionID,
        coordinateRevision: calibrationCoordinateRevision)
    }
  }

  @Test("live fractional border round trip still produces a complete camera prediction")
  func fractionalBorderPrediction() throws {
    // Coordinates retained from the 2026-09-06 LIVE outsideDomain failure.
    let bounds = try AxisAlignedBounds<MachineSpace>(
      minX: -357.052, minY: -94.056, maxX: -99.716, maxY: 85.917)
    let border = try DrawingBorderPlan(bounds: bounds)
    let placement = try DrawingPlacement(
      fieldAnchor: Point2(x: 0, y: 0), machineAnchor: border.startPosition.point,
      uniformScale: 1)
    let executed = try placement.applying(to: border.fieldPath)
    #expect(executed.points.contains { !bounds.contains($0) })
    #expect(executed.points[1].y - bounds.maxY < 1e-12)
    let transform = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: -1.6855608038158412, m12: 0.042683097551509966,
      m21: -0.01195600123519079, m22: -1.3297014792618584,
      tx: 858.9853609502268, ty: 334.1615169300525)
    #expect(DrawingRegionContainmentPolicy.contains(executed, in: bounds))
    let prediction = [try transform.applying(to: executed)]
    #expect(prediction.count == 1)
    #expect(prediction[0].points.count == 5)
    #expect(prediction[0].points.first == prediction[0].points.last)
    for (machine, pixel) in zip(executed.points, prediction[0].points) {
      #expect(pixel == (try transform.applying(to: machine)))
    }
  }

  @Test("plan creates the exact five-position normalized cross and returns to center")
  func fivePositionCross() throws {
    let target = try MachinePosition(x: 0, y: 0)
    let plan = try CurrentCameraCalibrationPlan(
      targetPosition: target,
      acceptedBoundaryAggregates: try boundaryEnvelope(
        negativeX: -100,
        positiveX: 100,
        negativeY: -80,
        positiveY: 80
      ),
      controllerSessionID: calibrationSessionID,
      coordinateRevision: calibrationCoordinateRevision
    )

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

  @Test("plan preserves a fractional target directly as calibration sample zero")
  func preservesFractionalTargetAsSampleZero() throws {
    let target = try MachinePosition(x: 0.1, y: -0.2)
    let plan = try CurrentCameraCalibrationPlan(
      targetPosition: target,
      acceptedBoundaryAggregates: try boundaryEnvelope(
        negativeX: -100,
        positiveX: 100,
        negativeY: -80,
        positiveY: 80
      ),
      controllerSessionID: calibrationSessionID,
      coordinateRevision: calibrationCoordinateRevision
    )

    #expect(plan.samples[0].position == .center)
    #expect(plan.samples[0].role == .fit)
    #expect(plan.samples[0].machinePosition == target)
    #expect(plan.samplePositions[0] == target)
  }

  @Test("plan contracts symmetrically around an off-center target")
  func symmetricContraction() throws {
    let plan = try CurrentCameraCalibrationPlan(
      targetPosition: MachinePosition(x: 70, y: -50),
      acceptedBoundaryAggregates: try boundaryEnvelope(
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
    #expect(mark.geometry.maximumFeedMMPerMinute == 500)
    #expect(mark.pathDeltas.count == 16)
    for position in mark.pathPositions {
      #expect(abs(position.point.distance(to: center.point) - 2) < 1e-9)
    }
    let pathEnd = try mark.pathDeltas.reduce(mark.startPosition.point) { position, delta in
      try Point2(x: position.x + delta.dx, y: position.y + delta.dy)
    }
    #expect(pathEnd.distance(to: mark.startPosition.point) < 1e-9)
  }

  @Test("Exercise 1.4 places four circle centers 10 mm inside the accepted Drawing Boundary")
  func sparseBatchGeometry() throws {
    let envelope = try boundaryEnvelope(
      negativeX: -100,
      positiveX: 100,
      negativeY: -100,
      positiveY: 100
    )
    let batch = try SparseTipBatchMarkPlan(
      acceptedBoundaryAggregates: envelope
    )

    #expect(batch.marks.map(\.position) == [
      .negativeX, .positiveY, .positiveX, .negativeY,
    ])
    #expect(batch.marks.map(\.machinePosition) == [
      try MachinePosition(x: -90, y: -90),
      try MachinePosition(x: -90, y: 90),
      try MachinePosition(x: 90, y: 90),
      try MachinePosition(x: 90, y: -90),
    ])
    #expect(batch.boundaryEnvelope == (try AxisAlignedBounds(
      minX: -100, minY: -100, maxX: 100, maxY: 100
    )))
    #expect(batch.applicabilityRectangle == (try AxisAlignedBounds(
      minX: -90, minY: -90, maxX: 90, maxY: 90
    )))
    #expect(batch.finalRevealPosition == (try MachinePosition(x: 0, y: 0)))
    #expect(
      try SparseTipBatchMarkPlan.applicabilityRectangle(
        for: batch.marks.map { $0.circle.geometry }) == batch.applicabilityRectangle
    )
    #expect(batch.marks.flatMap { $0.circle.pathDeltas }.count == 64)
    for mark in batch.marks {
      #expect(mark.circle.geometry.radiusMM == 2)
      #expect(mark.circle.geometry.chordCount == 16)
      #expect(mark.circle.geometry.maximumFeedMMPerMinute == 500)
      #expect(mark.circle.pathPositions.first == mark.circle.pathPositions.last)
      #expect(mark.circle.pathPositions.allSatisfy {
        $0.point.x >= batch.boundaryEnvelope.minX + 8
          && $0.point.x <= batch.boundaryEnvelope.maxX - 8
          && $0.point.y >= batch.boundaryEnvelope.minY + 8
          && $0.point.y <= batch.boundaryEnvelope.maxY - 8
      })
    }
  }

  @Test("Exercise 1.4 uses a 10 mm center inset and refuses collapsed Border axes")
  func sparseBatchUsesTenMillimeterInset() throws {
    let wide = try SparseTipBatchMarkPlan(
      acceptedBoundaryAggregates: boundaryEnvelope(
        negativeX: 10,
        positiveX: 210,
        negativeY: -10,
        positiveY: 90
      )
    )

    #expect(wide.applicabilityRectangle == (try AxisAlignedBounds(
      minX: 20, minY: 0, maxX: 200, maxY: 80
    )))

    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientSparseTipXAxisSpan) {
      try SparseTipBatchMarkPlan(
        acceptedBoundaryAggregates: boundaryEnvelope(
          negativeX: 0,
          positiveX: 20,
          negativeY: 0,
          positiveY: 40
        )
      )
    }
    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientSparseTipYAxisSpan) {
      try SparseTipBatchMarkPlan(
        acceptedBoundaryAggregates: boundaryEnvelope(
          negativeX: 0,
          positiveX: 40,
          negativeY: 0,
          positiveY: 20
        )
      )
    }
    let smallestAccepted = try SparseTipBatchMarkPlan(
      acceptedBoundaryAggregates: boundaryEnvelope(
        negativeX: 0,
        positiveX: 25,
        negativeY: 0,
        positiveY: 25
      )
    )
    #expect(smallestAccepted.applicabilityRectangle.minX == 10)
    #expect(smallestAccepted.applicabilityRectangle.minY == 10)
    #expect(abs(smallestAccepted.applicabilityRectangle.maxX - 15) < 1e-12)
    #expect(abs(smallestAccepted.applicabilityRectangle.maxY - 15) < 1e-12)
  }

  @Test("sparse circle refuses any mark that would cross the accepted Boundary envelope")
  func circularMarkRequiresSafeClearance() throws {
    let envelope = try AxisAlignedBounds<MachineSpace>(
      minX: -100, minY: -80, maxX: 100, maxY: 80
    )
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM
    _ = try SparseTipCircularMarkPlan(
      center: MachinePosition(x: 98 + epsilon, y: 0),
      boundaryEnvelope: envelope
    )
    #expect(throws: CurrentCameraCalibrationPlanningError.circularMarkOutsideBoundaryEnvelope) {
      try SparseTipCircularMarkPlan(
        center: MachinePosition(x: 98 + epsilon + 1e-6, y: 0),
        boundaryEnvelope: envelope
      )
    }
  }

  @Test("current checkpoint geometry reconstructs only the four region corners")
  func restoredCircleGeometry() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -30, minY: -30, maxX: 30, maxY: 30
    )
    let geometry = try ToolContactCalibrationPosition.sparseTipCornerPositions.map {
      try SparseTipCircularMarkPlan.restoredGeometry(for: $0, in: domain)
    }

    #expect(geometry.map(\.center) == [
      try MachinePosition(x: -30, y: -30),
      try MachinePosition(x: -30, y: 30),
      try MachinePosition(x: 30, y: 30),
      try MachinePosition(x: 30, y: -30),
    ])
    #expect(geometry.allSatisfy { $0.radiusMM == 2 })
    #expect(geometry.allSatisfy { $0.chordCount == 16 })
    #expect(geometry.allSatisfy { $0.maximumFeedMMPerMinute == 500 })
  }

  @Test("accepted v6 extreme-corner checkpoint geometry remains decodable at its recorded domain")
  func restoredBoundaryExtremeV6CircleGeometry() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -98, minY: -78, maxX: 98, maxY: 78
    )
    let geometry = try ToolContactCalibrationPosition.sparseTipCornerPositions.map {
      try SparseTipCircularMarkPlan.restoredGeometry(
        for: $0,
        in: domain,
        estimatorRevision:
          SparseTipCircularMarkPlan.boundaryExtremeFourCircleRegistrationEstimatorRevision
      )
    }

    #expect(geometry.map(\.center) == [
      try MachinePosition(x: -98, y: -78),
      try MachinePosition(x: -98, y: 78),
      try MachinePosition(x: 98, y: 78),
      try MachinePosition(x: 98, y: -78),
    ])
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

  @Test("Exercise 2.1 Drawing Border closes the four corners with orthogonal segments")
  func drawingBorderPlan() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: -30, minY: -30, maxX: 30, maxY: 30
    )
    let border = try DrawingBorderPlan(bounds: domain)
    #expect(border.pathPositions == [
      try MachinePosition(x: -30, y: -30),
      try MachinePosition(x: -30, y: 30),
      try MachinePosition(x: 30, y: 30),
      try MachinePosition(x: 30, y: -30),
      try MachinePosition(x: -30, y: -30),
    ])
    #expect(border.pathDeltas == [
      try Vector2(dx: 0, dy: 60),
      try Vector2(dx: 60, dy: 0),
      try Vector2(dx: 0, dy: -60),
      try Vector2(dx: -60, dy: 0),
    ])
    #expect(border.fieldPath.points == [
      try Point2<FieldSpace>(x: 0, y: 0),
      try Point2<FieldSpace>(x: 0, y: 60),
      try Point2<FieldSpace>(x: 60, y: 60),
      try Point2<FieldSpace>(x: 60, y: 0),
      try Point2<FieldSpace>(x: 0, y: 0),
    ])
    #expect(border.fieldExtent == (try Size2<FieldSpace>(width: 60, height: 60)))
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
        acceptedBoundaryAggregates: incomplete,
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
        acceptedBoundaryAggregates: try boundaryEnvelope(
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
        acceptedBoundaryAggregates: try boundaryEnvelope(
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
        acceptedBoundaryAggregates: wrongSession,
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
        acceptedBoundaryAggregates: wrongRevision,
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


extension CurrentCameraCalibrationPlanningTests {
  @Test("off-center selected extent owns all circle footprints and the retained center domain")
  func selectedWorkingExtent() throws {
    let boundary = try boundaryEnvelope(negativeX: -100, positiveX: 200, negativeY: -80, positiveY: 160)
    let selected = try AxisAlignedBounds<MachineSpace>(minX: -65, minY: 12, maxX: 47, maxY: 95)
    let plan = try SparseTipBatchMarkPlan(acceptedBoundaryAggregates: boundary, workingRegion: selected)
    #expect(plan.workingRegion == selected)
    #expect(plan.applicabilityRectangle == (try AxisAlignedBounds(minX: -55, minY: 22, maxX: 37, maxY: 85)))
    for mark in plan.marks {
      #expect(DrawingRegionContainmentPolicy.containsCircle(center: mark.machinePosition.point,
        radiusMM: SparseTipCircularMarkPlan.radiusMM, in: selected))
      #expect(DrawingRegionContainmentPolicy.containsCircle(center: mark.machinePosition.point,
        radiusMM: SparseTipCircularMarkPlan.radiusMM, in: plan.boundaryEnvelope))
    }
    for invalid in [
      try AxisAlignedBounds<MachineSpace>(minX: -101, minY: 0, maxX: 50, maxY: 80),
      try AxisAlignedBounds<MachineSpace>(minX: 0, minY: -81, maxX: 50, maxY: 80),
      try AxisAlignedBounds<MachineSpace>(minX: 0, minY: 0, maxX: 201, maxY: 80),
      try AxisAlignedBounds<MachineSpace>(minX: 0, minY: 0, maxX: 50, maxY: 161),
    ] {
      #expect(throws: CurrentCameraCalibrationPlanningError.selectedWorkingRegionOutsideBoundary) {
        try SparseTipBatchMarkPlan(acceptedBoundaryAggregates: boundary, workingRegion: invalid)
      }
    }
    #expect(throws: CurrentCameraCalibrationPlanningError.insufficientSparseTipXAxisSpan) {
      try SparseTipBatchMarkPlan(acceptedBoundaryAggregates: boundary,
        workingRegion: .init(minX: 0, minY: 0, maxX: 24.999, maxY: 25))
    }
    let smallest = try SparseTipBatchMarkPlan(acceptedBoundaryAggregates: boundary,
      workingRegion: .init(minX: 0, minY: 0, maxX: 25, maxY: 25))
    let a = smallest.marks[0].machinePosition.point, b = smallest.marks[1].machinePosition.point
    #expect(a.distance(to: b) - 2 * SparseTipCircularMarkPlan.radiusMM == 1)
  }

  @Test("historical v3-v7 mark restoration remains distinct from v8 selected-region provenance")
  func historicalEstimatorGeometry() throws {
    let domain = try AxisAlignedBounds<MachineSpace>(minX: -20, minY: 10, maxX: 60, maxY: 70)
    let revisions = [SparseTipCircularMarkPlan.cardinalRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.boundaryCornerRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.insetFiveCircleRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.boundaryExtremeFourCircleRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.boundaryInsetFourCircleRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.registrationEstimatorRevision]
    for revision in revisions {
      #expect(SparseTipCircularMarkPlan.supportsRestoredGeometry(for: revision))
      let mark = try SparseTipCircularMarkPlan.restoredGeometry(for: .negativeX, in: domain, estimatorRevision: revision)
      #expect(mark.center.point.x == domain.minX)
      #expect(mark.center.point.y == (revision == revisions[0] ? 40 : domain.minY))
    }
    #expect(SparseTipCircularMarkPlan.boundaryInsetFourCircleRegistrationEstimatorRevision.hasSuffix("-v7"))
    #expect(SparseTipCircularMarkPlan.registrationEstimatorRevision.hasSuffix("-v8"))
  }
}
