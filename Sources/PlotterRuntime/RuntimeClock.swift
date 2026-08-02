import Foundation

public protocol RuntimeClock: Sendable {
  func nowNanoseconds() -> UInt64
  func sleep(nanoseconds: UInt64) async throws
}

public struct SystemRuntimeClock: RuntimeClock {
  public init() {}

  public func nowNanoseconds() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
  }

  public func sleep(nanoseconds: UInt64) async throws {
    try await Task.sleep(nanoseconds: nanoseconds)
  }
}

public struct RuntimeTimestamp: Codable, Hashable, Sendable {
  public let monotonicNanoseconds: UInt64
  public let wallTime: Date

  public init(monotonicNanoseconds: UInt64, wallTime: Date = Date()) {
    self.monotonicNanoseconds = monotonicNanoseconds
    self.wallTime = wallTime
  }
}
