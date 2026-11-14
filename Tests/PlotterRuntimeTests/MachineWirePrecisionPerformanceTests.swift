import Foundation
@testable import PlotterRuntime
import Testing

@Suite("Machine wire formatter equivalence and performance", .serialized)
struct MachineWirePrecisionPerformanceTests {
  @Test("Cached formatter preserves decimal ties, adjacent doubles, signed zero and extreme values")
  func equivalence() {
    verify(Self.fixtures(halfRange: 1000, randomCount: 5000))
  }

  @Test("One immutable formatter can be used concurrently")
  func concurrentFormatting() {
    let values = Self.fixtures(halfRange: 20, randomCount: 100)
    let expected = values.map(Self.original)
    DispatchQueue.concurrentPerform(iterations: 16) { _ in
      for (index, value) in values.enumerated() {
        #expect(MachineWirePrecision.number(value)?.text == expected[index]?.text)
      }
    }
  }

  @Test("Large frozen-oracle differential and repeated wire-unit benchmark", .enabled(if: ProcessInfo.processInfo.environment["MACHINE_WIRE_BENCHMARK"] == "1"))
  func benchmark() {
    let values = Self.fixtures(halfRange: 10_000, randomCount: 100_000)
    verify(values)
    print("MACHINE_WIRE_EQUIVALENCE inputs=\(values.count) mismatches=0")
    let coordinates = (0..<10_000).map { Double($0 - 5_000) / 73.0 }
    func measure(_ label: String, convert: (Double) -> Int64?) {
      var checksum: Int64 = 0
      let samples = (0..<7).map { _ -> Double in
        let start = ContinuousClock.now
        for value in coordinates { checksum &+= convert(value) ?? 0 }
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
      }.sorted()
      print("MACHINE_WIRE_BENCHMARK \(label) median_ms=\(samples[3]) samples_ms=\(samples) checksum=\(checksum)")
    }
    measure("original", convert: Self.originalUnits)
    measure("cached", convert: MachineWirePrecision.units)
  }

  private func verify(_ values: [Double]) {
    for value in values {
      let expected = Self.original(value), actual = MachineWirePrecision.number(value)
      #expect(actual?.text == expected?.text)
      #expect(actual?.value.bitPattern == expected?.value.bitPattern)
      #expect(MachineWirePrecision.units(value) == Self.originalUnits(value))
    }
  }

  private static func original(_ value: Double) -> (value: Double, text: String)? {
    guard value.isFinite else { return nil }
    let text = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    guard let quantized = Double(text), quantized.isFinite else { return nil }
    let normalized = quantized == 0 ? 0 : quantized
    return (normalized, normalized == 0 ? "0.000" : text)
  }

  private static func originalUnits(_ value: Double) -> Int64? {
    guard let quantized = original(value)?.value else { return nil }
    return Int64(exactly: (quantized * 1_000).rounded())
  }

  private static func fixtures(halfRange: Int, randomCount: Int) -> [Double] {
    let limit = Double(Int64.max) / 1000
    var values = [0.0, -0.0, .nan, .infinity, -.infinity,
      .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNonzeroMagnitude, -.leastNonzeroMagnitude,
      limit.nextDown, limit, limit.nextUp, -limit.nextDown, -limit, -limit.nextUp]
    for index in -halfRange...halfRange {
      let value = Double(index) / 1000 + 0.0005
      values.append(contentsOf: [value.nextDown, value, value.nextUp])
    }
    var state: UInt64 = 7
    for _ in 0..<randomCount {
      state = state &* 6364136223846793005 &+ 1
      values.append(Double(bitPattern: state))
    }
    return values
  }
}
