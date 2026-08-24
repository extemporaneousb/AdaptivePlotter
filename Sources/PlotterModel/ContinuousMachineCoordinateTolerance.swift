/// The minimum tolerance for comparisons in continuous machine millimetres.
///
/// PlotterModel owns the value so model planning and runtime settlement cannot
/// silently select different numerical policies.
public enum ContinuousMachineCoordinateTolerance {
  public static let minimumMM = 0.5
}
