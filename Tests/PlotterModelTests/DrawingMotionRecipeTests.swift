import Foundation
import Testing
@testable import PlotterModel

@Suite("Drawing motion recipe identity and pure costs")
struct DrawingMotionRecipeTests {
  @Test("Policy binding preserves intended geometry and distinguishes execution recipes")
  func identity() throws {
    let plan = try fixture()
    let original = try canonicalBytes(of: plan)
    let isolated = try DrawingPlanner.motionRecipe(for: plan, policy: policy(.isolatedSegments))
    let continuous = try DrawingPlanner.motionRecipe(for: plan, policy: policy(.continuousWithinStroke))
    #expect(isolated.contentHash != continuous.contentHash)
    #expect(continuous.planContentHash == plan.contentHash)
    #expect(continuous.planRevisionID == plan.revisionID)
    #expect(try canonicalBytes(of: plan) == original)
    #expect(try JSONDecoder().decode(DrawingMotionRecipe.self,
      from: JSONEncoder().encode(continuous)) == continuous)
    let changedFeed = try DrawingPlanner.motionRecipe(for: plan,
      policy: policy(.continuousWithinStroke, feed: 301))
    #expect(changedFeed.contentHash != continuous.contentHash)
    let changedLimits = try DrawingPlanner.motionRecipe(for: plan,
      policy: policy(.continuousWithinStroke, deviation: 0.02))
    #expect(changedLimits.contentHash != continuous.contentHash)
  }

  @Test("Recipe refuses policy tampering and unknown schema")
  func tampering() throws {
    let recipe = try DrawingPlanner.motionRecipe(for: fixture(), policy: policy(.continuousWithinStroke))
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
    var policyObject = try #require(json["policy"] as? [String: Any])
    policyObject["travelFeedMMPerMinute"] = 999
    json["policy"] = policyObject
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(DrawingMotionRecipe.self, from: JSONSerialization.data(withJSONObject: json))
    }
    json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any])
    json["schemaVersion"] = 2
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(DrawingMotionRecipe.self, from: JSONSerialization.data(withJSONObject: json))
    }
  }

  @Test("Isolated cost uses triangular and trapezoidal acceleration with axis projection")
  func isolatedCost() throws {
    let limits = try DrawingControllerMotionLimits(maximumXFeedMMPerMinute: 600,
      maximumYFeedMMPerMinute: 600, xAccelerationMMPerSecondSquared: 10,
      yAccelerationMMPerSecondSquared: 10, junctionDeviationMM: 0.01)
    #expect(abs(DrawingMotionCost.isolatedMoveSeconds(dx: 1, dy: 0,
      feedMMPerMinute: 600, limits: limits) - 2 * sqrt(0.1)) < 1e-12)
    #expect(abs(DrawingMotionCost.isolatedMoveSeconds(dx: 100, dy: 0,
      feedMMPerMinute: 600, limits: limits) - 11) < 1e-12)
    #expect(DrawingMotionCost.isolatedMoveSeconds(dx: 0, dy: 0,
      feedMMPerMinute: 600, limits: limits) == 0)
    #expect(abs(DrawingMotionCost.isolatedMoveSeconds(dx: 100, dy: 100,
      feedMMPerMinute: 6000, limits: limits) - 11) < 1e-12)
  }

  @Test("Continuous estimates retain junction stops and qualify missing settings")
  func continuousCost() throws {
    let limits = try policy(.continuousWithinStroke).controllerLimits
    let straight = try Polyline<MachineSpace>(points: [Point2(x: 0, y: 0), Point2(x: 5, y: 0), Point2(x: 10, y: 0)])
    let continuous = DrawingMotionCost.estimate(path: straight, feedMMPerMinute: 300,
      limits: limits, assumption: .continuousJunctionDeviation)
    let isolated = DrawingMotionCost.estimate(path: straight, feedMMPerMinute: 300,
      limits: limits, assumption: .isolatedMoves)
    #expect(try #require(continuous.seconds) < #require(isolated.seconds))
    let reverse = try Polyline<MachineSpace>(points: [Point2(x: 0, y: 0), Point2(x: 5, y: 0), Point2(x: 0, y: 0)])
    let reversed = DrawingMotionCost.estimate(path: reverse, feedMMPerMinute: 300,
      limits: limits, assumption: .continuousJunctionDeviation)
    #expect(abs(try #require(reversed.seconds) - #require(isolated.seconds)) < 1e-12)
    let unknown = DrawingMotionCost.estimate(path: straight, feedMMPerMinute: 300,
      limits: try DrawingControllerMotionLimits(), assumption: .continuousJunctionDeviation)
    #expect(unknown.seconds == nil)
    #expect(!unknown.qualification.isEmpty)
  }

  private func policy(_ continuity: DrawingMotionPolicy.Continuity, feed: Double = 300,
    deviation: Double = 0.01) throws -> DrawingMotionPolicy {
    try DrawingMotionPolicy(continuity: continuity, drawingFeedMMPerMinute: feed, travelFeedMMPerMinute: 300,
      pen: DrawingMotionPenPolicy(raisedSpindleValue: 40, loweredSpindleValue: 760, settleSeconds: 0.3),
      controllerLimits: DrawingControllerMotionLimits(maximumXFeedMMPerMinute: 600,
        maximumYFeedMMPerMinute: 600, xAccelerationMMPerSecondSquared: 10,
        yAccelerationMMPerSecondSquared: 10, junctionDeviationMM: deviation), executionStrategyRevision: "fixture-v1")
  }

  private func fixture() throws -> ExecutionPlanRevision {
    let program = try DrawingProgramCatalog.program(for: .line,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()))
    let digest = try Digest(bytes: Array(repeating: 1, count: 32))
    return try DrawingPlanner.plan(program: program,
      placement: DrawingPlacement(fieldAnchor: Point2(x: 0, y: 0), machineAnchor: Point2(x: 0, y: 0), uniformScale: 1),
      drawableRegion: DrawableMachineRegion(bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200)),
      provenance: DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(), modelContentHash: digest,
        registrationRevisionID: DrawingRegistrationRevisionID(), registrationContentHash: digest))
  }
}
