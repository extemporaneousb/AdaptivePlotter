import Foundation

public struct CorrespondedGeometry: Hashable, Sendable {
  public let intended: Polyline<FieldSpace>
  public let predicted: Polyline<FieldSpace>
  public let observed: Polyline<FieldSpace>

  public init(
    intended: Polyline<FieldSpace>,
    predicted: Polyline<FieldSpace>,
    observed: Polyline<FieldSpace>
  ) throws {
    guard intended.points.count == predicted.points.count,
      predicted.points.count == observed.points.count
    else { throw PlotterModelError.invalidValue("corresponded paths require equal point counts") }
    self.intended = intended
    self.predicted = predicted
    self.observed = observed
  }
}

public struct ResidualMetrics: Hashable, Sendable {
  public let rootMeanSquare: Double
  public let maximum: Double
}

public struct ResidualEvaluation: Hashable, Sendable {
  public let goalResiduals: [Vector2<FieldSpace>]
  public let modelInnovations: [Vector2<FieldSpace>]
  public let goalMetrics: ResidualMetrics
  public let modelMetrics: ResidualMetrics
}

public enum ResidualCalculator {
  public static func evaluate(_ correspondence: CorrespondedGeometry) throws -> ResidualEvaluation {
    let goal = try zip(correspondence.intended.points, correspondence.observed.points).map {
      try $0.vector(to: $1)
    }
    let model = try zip(correspondence.predicted.points, correspondence.observed.points).map {
      try $0.vector(to: $1)
    }
    return ResidualEvaluation(
      goalResiduals: goal,
      modelInnovations: model,
      goalMetrics: metrics(for: goal),
      modelMetrics: metrics(for: model)
    )
  }

  private static func metrics(for residuals: [Vector2<FieldSpace>]) -> ResidualMetrics {
    let magnitudes = residuals.map(\.magnitude)
    let rms = sqrt(magnitudes.reduce(0) { $0 + $1 * $1 } / Double(magnitudes.count))
    return ResidualMetrics(rootMeanSquare: rms, maximum: magnitudes.max() ?? 0)
  }
}
