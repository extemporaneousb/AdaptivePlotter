import PlotterModel

/// Controller-position settlement for requested and reported machine poses.
///
/// GRBL reports positions quantized by the configured steps-per-millimetre values,
/// so a physically settled requested pose cannot require exact floating-point
/// equality. Drawing-region containment is owned separately by PlotterModel.
public enum MachinePositionAcceptancePolicy {
  public enum Metric: String, Codable, Hashable, Sendable {
    case euclideanResidualMillimetres
  }

  public enum Revision: String, Codable, Hashable, Sendable {
    case controllerQuantizedEuclideanV1
  }

  public static let metric = Metric.euclideanResidualMillimetres
  public static let revision = Revision.controllerQuantizedEuclideanV1
  public static let toleranceMM = 0.5

  public static func residualMM(
    _ actual: MachinePosition,
    from target: MachinePosition
  ) -> Double {
    target.point.distance(to: actual.point)
  }

  public static func accepts(
    _ actual: MachinePosition,
    target: MachinePosition
  ) -> Bool {
    accepts(residualMM: residualMM(actual, from: target))
  }

  public static func accepts(residualMM: Double) -> Bool {
    residualMM.isFinite && residualMM >= 0 && residualMM <= toleranceMM
  }
}
