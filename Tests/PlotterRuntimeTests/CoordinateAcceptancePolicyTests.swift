import PlotterModel
import PlotterRuntime
import Testing

@Suite("Coordinate acceptance policies")
struct CoordinateAcceptancePolicyTests {
  @Test("controller settlement and drawing containment have distinct typed contracts")
  func policiesAreDistinct() {
    #expect(
      MachinePositionAcceptancePolicy.metric == .euclideanResidualMillimetres
    )
    #expect(
      MachinePositionAcceptancePolicy.revision == .controllerQuantizedEuclideanV1
    )
    #expect(
      DrawingRegionContainmentPolicy.metric == .axisAlignedClosedBounds
    )
    #expect(
      DrawingRegionContainmentPolicy.revision
        == .acceptedBoundaryNumericalEpsilonV1
    )
    #expect(
      DrawingRegionContainmentPolicy.numericalEpsilonMM
        < MachinePositionAcceptancePolicy.toleranceMM
    )
  }

  @Test("controller settlement retains the Euclidean half-millimetre threshold")
  func controllerSettlementThreshold() {
    #expect(MachinePositionAcceptancePolicy.accepts(residualMM: 0.5))
    #expect(!MachinePositionAcceptancePolicy.accepts(residualMM: 0.501))
  }

  @Test("drawing containment admits only the separately versioned numerical epsilon")
  func drawingContainmentBoundary() throws {
    let bounds = try AxisAlignedBounds<MachineSpace>(
      minX: 0,
      minY: 0,
      maxX: 10,
      maxY: 10
    )
    let region = try DrawableMachineRegion(bounds: bounds)
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM

    #expect(region.contains(try Point2(x: 10, y: 5)))
    #expect(region.contains(try Point2(x: 10 + epsilon, y: 5)))
    #expect(!region.contains(try Point2(x: 10 + epsilon + 1e-6, y: 5)))

    let exactBoundary = try Polyline<MachineSpace>(
      points: [Point2(x: 0, y: 0), Point2(x: 10, y: 10)]
    )
    let outsideBoundary = try Polyline<MachineSpace>(
      points: [Point2(x: 0, y: 0), Point2(x: 10.000001001, y: 10)]
    )
    #expect(region.contains(exactBoundary))
    #expect(!region.contains(outsideBoundary))
  }
}
