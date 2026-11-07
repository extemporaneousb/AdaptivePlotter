import Foundation

public struct ExchangeEventClock: Hashable, Codable, Sendable {
  public let clockID: String
  public let bootSession: UUID
  public let ticks: String
  public let ticksPerSecond: UInt64
  public init(clockID: String, bootSession: UUID, ticks: String, ticksPerSecond: UInt64) throws {
    guard !clockID.isEmpty, !ticks.isEmpty, ticks.utf8.allSatisfy({ (48...57).contains($0) }),
      ticks == "0" || !ticks.hasPrefix("0"), ticksPerSecond > 0, ticksPerSecond <= 9_007_199_254_740_991 else { throw DrawingExchangeError.malformed("Event clock") }
    self.clockID = clockID; self.bootSession = bootSession; self.ticks = ticks; self.ticksPerSecond = ticksPerSecond
  }
  enum CodingKeys: String, CodingKey { case clockID, bootSession, ticks, ticksPerSecond }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(clockID: c.decode(String.self, forKey: .clockID), bootSession: exchangeUUID(c.decode(String.self, forKey: .bootSession)),
      ticks: c.decode(String.self, forKey: .ticks), ticksPerSecond: c.decode(UInt64.self, forKey: .ticksPerSecond))
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(clockID, forKey: .clockID); try c.encode(bootSession.uuidString.lowercased(), forKey: .bootSession)
    try c.encode(ticks, forKey: .ticks); try c.encode(ticksPerSecond, forKey: .ticksPerSecond)
  }
}
public struct ExchangeTimestamp: Hashable, Codable, Sendable {
  public let wallTime: String?
  public let event: ExchangeEventClock?
  public init(wallTime: String? = nil, event: ExchangeEventClock? = nil) throws {
    guard wallTime != nil || event != nil else { throw DrawingExchangeError.malformed("Timestamp needs wall or event clock") }
    if let wallTime, exchangeDate(wallTime) == nil { throw DrawingExchangeError.malformed("Invalid wall timestamp") }
    self.wallTime = wallTime; self.event = event
  }
  enum CodingKeys: String, CodingKey { case wallTime, event }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let wall = c.contains(.wallTime) ? try c.decode(String.self, forKey: .wallTime) : nil
    let event = c.contains(.event) ? try c.decode(ExchangeEventClock.self, forKey: .event) : nil
    try self.init(wallTime: wall, event: event)
  }
}
