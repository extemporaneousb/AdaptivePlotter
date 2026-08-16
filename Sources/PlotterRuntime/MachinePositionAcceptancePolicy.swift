import PlotterModel

/// The single comparison policy for continuous machine-space positions.
///
/// GRBL reports positions quantized by the configured steps-per-millimetre values,
/// and computed planning geometry can accumulate floating-point residue. No physical
/// or computed machine position is therefore admitted through exact equality or
/// zero-tolerance containment. Discrete identities and provenance remain exact.
public enum MachinePositionAcceptancePolicy {
  public static let toleranceMM = 0.05

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

  public static func contains(
    _ position: MachinePosition,
    in bounds: AxisAlignedBounds<MachineSpace>
  ) -> Bool {
    contains(position.point, in: bounds)
  }

  public static func contains(
    _ point: Point2<MachineSpace>,
    in bounds: AxisAlignedBounds<MachineSpace>
  ) -> Bool {
    bounds.contains(point, tolerance: toleranceMM)
  }
}
