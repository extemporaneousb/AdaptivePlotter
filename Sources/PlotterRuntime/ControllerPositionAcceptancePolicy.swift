/// The single machine-position comparison policy for controller-confirmed poses.
///
/// GRBL reports positions quantized by the configured steps-per-millimetre values,
/// so a mathematically exact commanded coordinate is not necessarily representable.
/// This tolerance accepts that controller quantization while remaining materially
/// tighter than any product motion or camera-registration scale.
public enum ControllerPositionAcceptancePolicy {
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
    let residual = residualMM(actual, from: target)
    return accepts(residualMM: residual)
  }

  public static func accepts(residualMM: Double) -> Bool {
    residualMM.isFinite && residualMM >= 0 && residualMM <= toleranceMM
  }
}
