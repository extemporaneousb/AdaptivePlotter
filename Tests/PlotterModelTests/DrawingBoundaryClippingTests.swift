import Foundation
import Testing
@testable import PlotterModel

@Suite("Ordinary drawing boundary clipping")
struct DrawingBoundaryClippingTests {
  @Test("unchanged source endpoints join exactly after entering the clipped region")
  func clippingPreservesAdjacentEndpoints() throws {
    let path = try Polyline<MachineSpace>(points: [-1.0, 0.2, 0.9, 0.9001].map {
      try Point2(x: $0, y: 0.5)
    })
    let clipped = try DrawingPlanner.clippedPaths(path,
      to: AxisAlignedBounds(minX: 0, minY: 0, maxX: 1, maxY: 1))
    #expect(clipped.count == 1)
    #expect(clipped.first?.points == [try Point2(x: 0, y: 0.5)] + path.points.dropFirst())
    #expect(clipped.first?.end == path.end)
  }

  @Test("crossing segments split at outside excursions without boundary bridges")
  func splitsOutsideExcursions() throws {
    let program = try program(points: [(0, 5), (20, 5), (20, 15), (0, 15)])
    let region = try DrawableMachineRegion(bounds: .init(minX: 2, minY: 2, maxX: 18, maxY: 18), edgeClearance: 2)
    let placement = try DrawingPlacement(fieldAnchor: .init(x: 0, y: 0),
      machineAnchor: .init(x: 0, y: 0), uniformScale: 1)
    let first = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: region, provenance: provenance, boundaryPolicy: .clipToDrawableRegion)
    let second = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: region, provenance: provenance, boundaryPolicy: .clipToDrawableRegion)
    #expect(first == second)
    #expect(first.sourceProgramID == program.id)
    #expect(first.sourceProgramContentHash == program.contentHash)
    #expect(first.strokes.map(\.path.points) == [
      [try Point2(x: 4, y: 5), try Point2(x: 16, y: 5)],
      [try Point2(x: 16, y: 15), try Point2(x: 4, y: 15)]])
    #expect(Set(first.strokes.map(\.logicalStrokeID)).count == 2)
    #expect(first.strokes.allSatisfy { $0.logicalStrokeID != program.strokes[0].id })
    #expect(first.checkpoints.map(\.afterStrokeID) == first.strokes.map(\.logicalStrokeID))
    #expect(first.checkpoints.map(\.id) == first.strokes.map(\.endingCheckpointID))
    #expect(try JSONDecoder().decode(ExecutionPlanRevision.self,
      from: JSONEncoder().encode(first)) == first)
    #expect(throws: DrawingPlanningError.self) {
      try DrawingPlanner.plan(program: program, placement: placement,
        drawableRegion: region, provenance: provenance)
    }
  }

  @Test("all authored rotations yield contained paths without resizing", arguments: stride(from: -180.0, through: 180.0, by: 15.0).map { $0 })
  func rotations(degrees: Double) throws {
    let program = try program(points: [(0, 0), (20, 20), (0, 20), (20, 0)])
    let placement = try DrawingPlacement(fieldAnchor: .init(x: 10, y: 10),
      machineAnchor: .init(x: 5, y: 5), uniformScale: 1, rotationRadians: degrees * .pi / 180)
    let region = try DrawableMachineRegion(bounds: .init(minX: 0, minY: 0, maxX: 10, maxY: 10))
    let plan = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: region, provenance: provenance, boundaryPolicy: .clipToDrawableRegion)
    #expect(plan.placement == placement)
    #expect(plan.strokes.allSatisfy { region.contains($0.path) })
    #expect(plan.strokes.allSatisfy { $0.path.length > 0 })
  }

  @Test("fully omitted and point-only contact cannot become drawable plans")
  func noDrawableFragments() throws {
    for points in [[(0.0, 0.0), (1.0, 1.0)], [(0.0, 2.0), (2.0, 0.0)]] {
      let program = try program(points: points)
      let region = try DrawableMachineRegion(bounds: .init(minX: 1, minY: 1, maxX: 10, maxY: 10))
      let placement = try DrawingPlacement(fieldAnchor: .init(x: 0, y: 0),
        machineAnchor: .init(x: 0, y: 0), uniformScale: 1)
      #expect(throws: DrawingPlanningError.emptyPlan) {
        try DrawingPlanner.plan(program: program, placement: placement,
          drawableRegion: region, provenance: provenance, boundaryPolicy: .clipToDrawableRegion)
      }
    }
  }

  @Test("contained paths retain strict plan identities")
  func preservesContainedIdentity() throws {
    let program = try program(points: [(2, 2), (8, 2), (8, 8)])
    let placement = try DrawingPlacement(fieldAnchor: .init(x: 0, y: 0),
      machineAnchor: .init(x: 0, y: 0), uniformScale: 1)
    let region = try DrawableMachineRegion(bounds: .init(minX: 0, minY: 0, maxX: 10, maxY: 10))
    let strict = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: region, provenance: provenance)
    let clipped = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: region, provenance: provenance, boundaryPolicy: .clipToDrawableRegion)
    #expect(clipped == strict)
  }

  private func program(points: [(Double, Double)]) throws -> DrawingProgram {
    try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 20, height: 20),
      strokes: [.init(id: StrokeID(), path: .init(points: points.map { try Point2(x: $0.0, y: $0.1) }),
        style: .init(nominalLineWidth: 0.4, penProfileID: PenProfileID()), ordering: 0)],
      source: .init(kind: "test", sourceIdentifier: "clipping"))
  }

  private var provenance: DrawingPlanningProvenance {
    get throws {
      try .init(modelRevisionID: DrawingModelRevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!),
        modelContentHash: Digest(bytes: Array(repeating: 1, count: 32)),
        registrationRevisionID: DrawingRegistrationRevisionID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!),
        registrationContentHash: Digest(bytes: Array(repeating: 2, count: 32)))
    }
  }
}
