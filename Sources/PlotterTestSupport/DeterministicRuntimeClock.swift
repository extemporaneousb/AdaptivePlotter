import Foundation
import PlotterRuntime

public final class DeterministicRuntimeClock: RuntimeClock, @unchecked Sendable {
  private let lock = NSLock()
  private var currentNanoseconds: UInt64

  public init(startNanoseconds: UInt64 = 1_000_000) {
    currentNanoseconds = startNanoseconds
  }

  public func nowNanoseconds() -> UInt64 {
    lock.withLock { currentNanoseconds }
  }

  public func sleep(nanoseconds: UInt64) async throws {
    try Task.checkCancellation()
    lock.withLock { currentNanoseconds &+= nanoseconds }
  }

  public func advance(nanoseconds: UInt64) {
    lock.withLock { currentNanoseconds &+= nanoseconds }
  }
}
