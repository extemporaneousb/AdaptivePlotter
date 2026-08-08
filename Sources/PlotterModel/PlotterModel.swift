public enum PlotterModelError: Error, Equatable, Sendable {
  case invalidValue(String)
  case contentHashMismatch
}
