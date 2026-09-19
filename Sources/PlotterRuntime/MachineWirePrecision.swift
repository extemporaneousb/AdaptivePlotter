import Foundation
import PlotterModel

/// The controller's existing three-decimal command representation. This is
/// serialization precision, not measured axis resolution or pose settlement.
enum MachineWirePrecision {
  static let unitsPerMillimetre = 1_000.0
  static let maximumComponentRoundingErrorMM = 0.0005

  static func number(_ value: Double) -> (value: Double, text: String)? {
    guard value.isFinite else { return nil }
    let text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    guard let quantized = Double(text), quantized.isFinite else { return nil }
    let normalized = quantized == 0 ? 0 : quantized
    return (normalized, normalized == 0 ? "0.000" : text)
  }

  /// Integer wire units prevent displacement error accumulating with each
  /// source segment. Values outside this finite representation are refused.
  static func units(_ value: Double) -> Int64? {
    guard let quantized = number(value)?.value else { return nil }
    return Int64(exactly: (quantized * unitsPerMillimetre).rounded())
  }
}
