import Foundation

/// A small timing requirement used by the current camera-frame buffer.
///
/// This is a local runtime parameter, not a phase gate or durable authority
/// record. Callers may choose values appropriate to the current operation.
public struct StableFrameRequirement: Hashable, Codable, Sendable {
  public let minimumFrameCount: UInt16
  public let newerThanMonotonicNanoseconds: UInt64
  public let maximumSpanNanoseconds: UInt64

  public init(
    minimumFrameCount: UInt16,
    newerThanMonotonicNanoseconds: UInt64,
    maximumSpanNanoseconds: UInt64
  ) throws {
    guard minimumFrameCount >= 2, maximumSpanNanoseconds > 0 else {
      throw PlotterModelError.invalidValue("stable frame requirement is not bounded")
    }
    self.minimumFrameCount = minimumFrameCount
    self.newerThanMonotonicNanoseconds = newerThanMonotonicNanoseconds
    self.maximumSpanNanoseconds = maximumSpanNanoseconds
  }

  private enum CodingKeys: String, CodingKey {
    case minimumFrameCount, newerThanMonotonicNanoseconds, maximumSpanNanoseconds
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      minimumFrameCount: container.decode(UInt16.self, forKey: .minimumFrameCount),
      newerThanMonotonicNanoseconds: container.decode(
        UInt64.self,
        forKey: .newerThanMonotonicNanoseconds
      ),
      maximumSpanNanoseconds: container.decode(UInt64.self, forKey: .maximumSpanNanoseconds)
    )
  }
}
