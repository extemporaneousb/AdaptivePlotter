/// Namespace marker for the deterministic domain target.
public enum PlotterModelModule {}

public enum PlotterModelError: Error, Equatable, Sendable {
  case invalidValue(String)
  case contentHashMismatch
}
