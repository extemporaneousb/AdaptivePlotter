import Foundation
import Testing

@testable import PlotterModel

@Suite("Exact metric drawing targets")
struct DrawingMetricTargetTests {
  @Test("40 square has an exact perimeter and two separately checkpointed diagonals")
  func squarePerimeterAndDiagonals() throws {
    let program = try DrawingProgramCatalog.program(for: .metricSquare40, style: metricTargetStyle())
    #expect(program.fieldExtent == (try Size2<FieldSpace>(width: 40, height: 40)))
    #expect(program.strokes.count == 3)
    #expect(program.strokes.map(\.ordering) == [0, 1, 2])
    #expect(Set(program.strokes.map(\.id)).count == 3)
    let perimeter = program.strokes[0].path.points
    #expect(perimeter == (try metricTargetPoints([(0, 0), (40, 0), (40, 40), (0, 40), (0, 0)])))
    #expect(program.strokes[1].path.points == (try metricTargetPoints([(0, 0), (40, 40)])))
    #expect(program.strokes[2].path.points == (try metricTargetPoints([(40, 0), (0, 40)])))
    #expect(program.strokes.allSatisfy { $0.semanticRole == .drawing })
    #expect(program.source.sourceIdentifier == "adaptiveplotter.builtin.metricSquare40.v1")
  }

  @Test("40 by 20 rectangle uses its full exact field extent")
  func rectanglePerimeter() throws {
    let program = try DrawingProgramCatalog.program(for: .metricRectangle40x20, style: metricTargetStyle())
    #expect(program.fieldExtent == (try Size2<FieldSpace>(width: 40, height: 20)))
    #expect(program.strokes.count == 1)
    #expect(program.strokes[0].path.points == (try metricTargetPoints([(0, 0), (40, 0), (40, 20), (0, 20), (0, 0)])))
    #expect(program.source.sourceIdentifier == "adaptiveplotter.builtin.metricRectangle40x20.v1")
  }

  @Test("ordinary planning at 100 percent preserves metric spans at zero and ninety degrees",
    arguments: [DrawingCatalogEntryID.metricSquare40, .metricRectangle40x20])
  func placedGeometryAndRoundTrip(_ id: DrawingCatalogEntryID) throws {
    let program = try DrawingProgramCatalog.program(for: id, style: metricTargetStyle())
    let region = try DrawableMachineRegion(bounds: AxisAlignedBounds<MachineSpace>(minX: 0, minY: 0, maxX: 200, maxY: 200))
    let provenance = try DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(),
      modelContentHash: Digest(bytes: Array(repeating: 0x11, count: 32)),
      registrationRevisionID: DrawingRegistrationRevisionID(),
      registrationContentHash: Digest(bytes: Array(repeating: 0x22, count: 32)))
    var plans: [ExecutionPlanRevision] = []
    for angle in [0.0, Double.pi / 2] {
      let placement = try DrawingPlacement(
        fieldAnchor: Point2<FieldSpace>(x: 20, y: id == .metricSquare40 ? 20 : 10),
        machineAnchor: Point2<MachineSpace>(x: 100, y: 100), uniformScale: 1, rotationRadians: angle)
      let plan = try DrawingPlanner.plan(program: program, placement: placement,
        drawableRegion: region, provenance: provenance)
      #expect(plan.sourceProgramContentHash == program.contentHash)
      #expect(plan.strokes.count == program.strokes.count)
      #expect(plan.checkpoints.count == program.strokes.count)
      let points = plan.strokes[0].path.points
      let xSpan = points.map(\.x).max()! - points.map(\.x).min()!
      let ySpan = points.map(\.y).max()! - points.map(\.y).min()!
      let shortSide = id == .metricSquare40 ? 40.0 : 20.0
      #expect(abs(xSpan - (angle == 0 ? 40 : shortSide)) < 1e-9)
      #expect(abs(ySpan - (angle == 0 ? shortSide : 40)) < 1e-9)
      if id == .metricSquare40 {
        for diagonal in plan.strokes.dropFirst() {
          let a = diagonal.path.points[0], b = diagonal.path.points[1]
          #expect(abs(hypot(b.x - a.x, b.y - a.y) - 40 * sqrt(2)) < 1e-9)
        }
      }
      let restored = try JSONDecoder().decode(ExecutionPlanRevision.self, from: JSONEncoder().encode(plan))
      #expect(restored == plan)
      #expect(restored.contentHash == plan.contentHash)
      plans.append(plan)
    }
    #expect(plans[0].contentHash != plans[1].contentHash)
    let restoredProgram = try JSONDecoder().decode(DrawingProgram.self, from: JSONEncoder().encode(program))
    #expect(restoredProgram == program)
    #expect(restoredProgram.id == program.id)
    #expect(restoredProgram.contentHash == program.contentHash)
  }

  @Test("metric additions leave historical square and rectangle identities and paths distinct")
  func historicalCatalogRemainsUnchanged() throws {
    let style = try metricTargetStyle()
    let square = try DrawingProgramCatalog.program(for: .square, style: style)
    let rectangle = try DrawingProgramCatalog.program(for: .rectangle, style: style)
    #expect(square.source.sourceIdentifier == "adaptiveplotter.builtin.square.v1")
    #expect(rectangle.source.sourceIdentifier == "adaptiveplotter.builtin.rectangle.v1")
    #expect(square.strokes[0].path.points == (try metricTargetPoints([(2, 2), (98, 2), (98, 98), (2, 98), (2, 2)])))
    #expect(rectangle.strokes[0].path.points == (try metricTargetPoints([(2, 2), (98, 2), (98, 68), (2, 68), (2, 2)])))
    #expect(square.id != (try DrawingProgramCatalog.program(for: .metricSquare40, style: style)).id)
    #expect(rectangle.id != (try DrawingProgramCatalog.program(for: .metricRectangle40x20, style: style)).id)
  }
}

private func metricTargetStyle() throws -> StrokeStyle {
  try StrokeStyle(nominalLineWidth: 0.4,
    penProfileID: PenProfileID(UUID(uuidString: "7d3bfa35-4278-4cb6-94c4-755ce8bbb6e2")!))
}

private func metricTargetPoints(_ coordinates: [(Double, Double)]) throws -> [Point2<FieldSpace>] {
  try coordinates.map { try Point2(x: $0.0, y: $0.1) }
}
