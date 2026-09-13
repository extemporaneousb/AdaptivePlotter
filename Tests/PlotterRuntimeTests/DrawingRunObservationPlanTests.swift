import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

struct DrawingRunObservationPlanTests {
  @Test("A nearby accepted clearing pose wins over the final drawing endpoint")
  func nearestClearingPose() throws {
    let plan = try makePlan(minimum: 40, maximum: 60)
    let result = try DrawingRunObservationPlan(executionPlan: plan,
      acceptedMovementBounds: bounds(), currentPosition: MachinePosition(x: 20, y: 50))
    #expect(result.mode == .singlePose)
    #expect(result.poses.count == 1)
    #expect(result.poses.first?.position == (try MachinePosition(x: 20, y: 50)))
    #expect(result.poses.first?.minimumGeometryClearanceMM == 20)
    #expect(result.requiredPenState == .up)
    #expect(result.requestedClearanceAchieved)
    #expect(result.limitations.contains { $0.contains("visibility remains unknown") })
    #expect(try JSONDecoder().decode(DrawingRunObservationPlan.self,
      from: JSONEncoder().encode(result)) == result)
  }

  @Test("The rectangle interior is not clear merely because its border strokes are distant")
  func conservativeInteriorAndNearestSide() throws {
    let result = try DrawingRunObservationPlan(executionPlan: makePlan(minimum: 20, maximum: 80),
      acceptedMovementBounds: bounds(), currentPosition: MachinePosition(x: 25, y: 50))
    #expect(result.poses.count == 1)
    #expect(result.poses.first?.position == (try MachinePosition(x: 10, y: 50)))
    #expect(result.poses.first?.minimumGeometryClearanceMM == 10)
  }

  @Test("No clear pose produces a finite diverse set without expanding accepted bounds")
  func boundedMultiPose() throws {
    let accepted = try bounds()
    let result = try DrawingRunObservationPlan(executionPlan: makePlan(minimum: 0, maximum: 100),
      acceptedMovementBounds: accepted, currentPosition: MachinePosition(x: 50, y: 50))
    #expect(result.mode == .multiPose)
    #expect(result.poses.count == 3)
    #expect(!result.requestedClearanceAchieved)
    #expect(Set(result.poses.map(\.position)).count == 3)
    #expect(result.poses.allSatisfy { accepted.contains($0.position.point) })
    #expect(result.poses.allSatisfy { $0.minimumGeometryClearanceMM == 0 })
    let limited = try DrawingRunObservationPlan(executionPlan: makePlan(minimum: 0, maximum: 100),
      acceptedMovementBounds: accepted, currentPosition: MachinePosition(x: 50, y: 50), maximumPoseCount: 1)
    #expect(limited.poses.count == 1)
    #expect(!limited.requestedClearanceAchieved)
  }

  @Test("Actual accepted bounds reject outside current state and unbounded pose requests")
  func refusesInvalidBoundaries() throws {
    let plan = try makePlan(minimum: 20, maximum: 80)
    #expect(throws: DrawingRunObservationPlanError.currentPositionOutsideAcceptedBounds) {
      try DrawingRunObservationPlan(executionPlan: plan, acceptedMovementBounds: bounds(),
        currentPosition: MachinePosition(x: 101, y: 50))
    }
    #expect(throws: DrawingRunObservationPlanError.drawingOutsideAcceptedBounds) {
      try DrawingRunObservationPlan(executionPlan: plan,
        acceptedMovementBounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 50, maxY: 50),
        currentPosition: MachinePosition(x: 1, y: 1))
    }
    #expect(throws: DrawingRunObservationPlanError.invalidPolicy) {
      try DrawingRunObservationPlan(executionPlan: plan, acceptedMovementBounds: bounds(),
        currentPosition: MachinePosition(x: 50, y: 50), maximumPoseCount: 4)
    }
  }

  private func bounds() throws -> AxisAlignedBounds<MachineSpace> {
    try .init(minX: 0, minY: 0, maxX: 100, maxY: 100)
  }

  private func makePlan(minimum: Double, maximum: Double) throws -> ExecutionPlanRevision {
    let parts = try drawingEvidenceParts()
    let base = try #require(parts.plan.executionPlan)
    let strokeID = StrokeID(), checkpointID = PlanCheckpointID()
    let points: [Point2<MachineSpace>] = try [
      .init(x: minimum, y: minimum), .init(x: maximum, y: minimum),
      .init(x: maximum, y: maximum), .init(x: minimum, y: maximum), .init(x: minimum, y: minimum)
    ]
    return try ExecutionPlanRevision(sourceProgramID: base.sourceProgramID,
      sourceProgramContentHash: base.sourceProgramContentHash, placement: base.placement,
      drawableRegion: DrawableMachineRegion(bounds: bounds()), provenance: base.provenance,
      strokes: [PlannedMachineStroke(logicalStrokeID: strokeID, path: Polyline(points: points),
        style: base.strokes[0].style, semanticRole: .drawing, ordering: 0, endingCheckpointID: checkpointID)],
      checkpoints: [ExecutionCheckpoint(id: checkpointID, afterStrokeID: strokeID, ordering: 0)])
  }
}
