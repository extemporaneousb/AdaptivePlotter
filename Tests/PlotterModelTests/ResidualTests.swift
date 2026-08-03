import Testing

@testable import PlotterModel

@Suite("Residual calculation")
struct ResidualTests {
  @Test("goal residual and model innovation remain separate")
  func residuals() throws {
    let correspondence = try CorrespondedGeometry(
      intended: Polyline(points: [fieldPoint(0, 0), fieldPoint(10, 0)]),
      predicted: Polyline(points: [fieldPoint(1, 0), fieldPoint(11, 0)]),
      observed: Polyline(points: [fieldPoint(2, 0), fieldPoint(12, 0)])
    )
    let result = try ResidualCalculator.evaluate(correspondence)
    #expect(result.goalMetrics.rootMeanSquare == 2)
    #expect(result.modelMetrics.rootMeanSquare == 1)
    #expect(result.goalResiduals[0].dx == 2)
    #expect(result.modelInnovations[0].dx == 1)
  }
}
