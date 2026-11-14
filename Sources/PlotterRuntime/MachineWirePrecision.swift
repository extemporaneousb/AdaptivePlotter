import Foundation

/// The controller's existing three-decimal command representation. This is
/// serialization precision, not measured axis resolution or pose settlement.
enum MachineWirePrecision {
  static let unitsPerMillimetre = 1_000.0
  static let maximumComponentRoundingErrorMM = 0.0005
  private static let formatter = WireNumberFormatter()

  /// String(format:locale:) reconfigures an ICU formatter for every coordinate.
  /// Keep the same decimal formatter and raw Double conversion, with immutable
  /// properties and serialized access. NSNumber and C printf change some ties
  /// or large integral values, so neither is an equivalent wire representation.
  private final class WireNumberFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: CFNumberFormatter

    init() {
      formatter = CFNumberFormatterCreate(nil, Locale(identifier: "en_US_POSIX") as NSLocale, .decimalStyle)!
      CFNumberFormatterSetProperty(formatter, .useGroupingSeparator, kCFBooleanFalse)
      CFNumberFormatterSetProperty(formatter, .minFractionDigits, NSNumber(value: 3))
      CFNumberFormatterSetProperty(formatter, .maxFractionDigits, NSNumber(value: 3))
    }

    func string(_ input: Double) -> String? {
      lock.lock(); defer { lock.unlock() }
      var value = input
      return CFNumberFormatterCreateStringWithValue(nil, formatter, .doubleType, &value) as String?
    }
  }

  static func number(_ value: Double) -> (value: Double, text: String)? {
    guard value.isFinite else { return nil }
    guard let text = formatter.string(value), let quantized = Double(text), quantized.isFinite else { return nil }
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
