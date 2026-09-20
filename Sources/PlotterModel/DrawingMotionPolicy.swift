import Foundation

/// Values read from the controller, never application defaults. Nil means that
/// setting was not captured; it does not assert an unrestricted controller.
public struct DrawingControllerMotionLimits: Codable, Hashable, Sendable, CanonicalEncodable {
  public let maximumXFeedMMPerMinute: Double?
  public let maximumYFeedMMPerMinute: Double?
  public let xAccelerationMMPerSecondSquared: Double?
  public let yAccelerationMMPerSecondSquared: Double?
  public let junctionDeviationMM: Double?

  public init(maximumXFeedMMPerMinute: Double? = nil, maximumYFeedMMPerMinute: Double? = nil,
    xAccelerationMMPerSecondSquared: Double? = nil, yAccelerationMMPerSecondSquared: Double? = nil,
    junctionDeviationMM: Double? = nil) throws {
    self.maximumXFeedMMPerMinute = maximumXFeedMMPerMinute
    self.maximumYFeedMMPerMinute = maximumYFeedMMPerMinute
    self.xAccelerationMMPerSecondSquared = xAccelerationMMPerSecondSquared
    self.yAccelerationMMPerSecondSquared = yAccelerationMMPerSecondSquared
    self.junctionDeviationMM = junctionDeviationMM
    try validate()
  }

  private enum CodingKeys: String, CodingKey {
    case maximumXFeedMMPerMinute, maximumYFeedMMPerMinute, xAccelerationMMPerSecondSquared
    case yAccelerationMMPerSecondSquared, junctionDeviationMM
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(maximumXFeedMMPerMinute: values.decodeIfPresent(Double.self, forKey: .maximumXFeedMMPerMinute),
      maximumYFeedMMPerMinute: values.decodeIfPresent(Double.self, forKey: .maximumYFeedMMPerMinute),
      xAccelerationMMPerSecondSquared: values.decodeIfPresent(Double.self, forKey: .xAccelerationMMPerSecondSquared),
      yAccelerationMMPerSecondSquared: values.decodeIfPresent(Double.self, forKey: .yAccelerationMMPerSecondSquared),
      junctionDeviationMM: values.decodeIfPresent(Double.self, forKey: .junctionDeviationMM))
  }

  public func validate() throws {
    guard [maximumXFeedMMPerMinute, maximumYFeedMMPerMinute,
      xAccelerationMMPerSecondSquared, yAccelerationMMPerSecondSquared]
      .allSatisfy({ $0 == nil || ($0!.isFinite && $0! > 0) }),
      junctionDeviationMM == nil || (junctionDeviationMM!.isFinite && junctionDeviationMM! >= 0) else {
      throw PlotterModelError.invalidValue("invalid captured controller motion limits")
    }
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try validate()
    try encoder.appendString("DrawingControllerMotionLimits-v1")
    for value in [maximumXFeedMMPerMinute, maximumYFeedMMPerMinute,
      xAccelerationMMPerSecondSquared, yAccelerationMMPerSecondSquared, junctionDeviationMM] {
      encoder.appendBool(value != nil)
      if let value { try encoder.appendDouble(value) }
    }
  }
}

public struct DrawingMotionPenPolicy: Codable, Hashable, Sendable, CanonicalEncodable {
  public let raisedSpindleValue: Int
  public let loweredSpindleValue: Int
  public let settleSeconds: Double
  public init(raisedSpindleValue: Int, loweredSpindleValue: Int, settleSeconds: Double) throws {
    self.raisedSpindleValue = raisedSpindleValue; self.loweredSpindleValue = loweredSpindleValue
    self.settleSeconds = settleSeconds
    try validate()
  }
  private enum CodingKeys: String, CodingKey { case raisedSpindleValue, loweredSpindleValue, settleSeconds }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(raisedSpindleValue: values.decode(Int.self, forKey: .raisedSpindleValue),
      loweredSpindleValue: values.decode(Int.self, forKey: .loweredSpindleValue),
      settleSeconds: values.decode(Double.self, forKey: .settleSeconds))
  }
  public func validate() throws {
    guard (0...1000).contains(raisedSpindleValue), (0...1000).contains(loweredSpindleValue),
      settleSeconds.isFinite, settleSeconds >= 0 else {
      throw PlotterModelError.invalidValue("invalid drawing motion pen policy")
    }
  }
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try validate()
    encoder.appendUInt16(UInt16(raisedSpindleValue)); encoder.appendUInt16(UInt16(loweredSpindleValue))
    try encoder.appendDouble(settleSeconds)
  }
}

/// A policy changes execution, never authored geometry. Version one fixes the
/// order, direction, and barriers explicitly rather than permitting optimization.
public struct DrawingMotionPolicy: Codable, Hashable, Sendable, CanonicalEncodable {
  public enum Continuity: String, Codable, Hashable, Sendable {
    case isolatedSegments
    case continuousWithinStroke
  }
  public enum Ordering: String, Codable, Hashable, Sendable { case authored }
  public enum Direction: String, Codable, Hashable, Sendable { case authored }
  public enum Stops: String, Codable, Hashable, Sendable { case strokeEndPenTransitionAndCheckpoint }
  public enum Corners: String, Codable, Hashable, Sendable { case controllerJunctionHandling }

  public let schemaVersion: UInt16
  public let continuity: Continuity
  public let ordering: Ordering
  public let direction: Direction
  public let requiredStops: Stops
  public let cornerHandling: Corners
  public let drawingFeedMMPerMinute: Double
  public let travelFeedMMPerMinute: Double
  public let pen: DrawingMotionPenPolicy
  public let controllerLimits: DrawingControllerMotionLimits
  public let executionStrategyRevision: String

  public init(continuity: Continuity, drawingFeedMMPerMinute: Double, travelFeedMMPerMinute: Double,
    pen: DrawingMotionPenPolicy, controllerLimits: DrawingControllerMotionLimits,
    executionStrategyRevision: String) throws {
    schemaVersion = 1; self.continuity = continuity
    ordering = .authored; direction = .authored
    requiredStops = .strokeEndPenTransitionAndCheckpoint; cornerHandling = .controllerJunctionHandling
    self.drawingFeedMMPerMinute = drawingFeedMMPerMinute; self.travelFeedMMPerMinute = travelFeedMMPerMinute
    self.pen = pen; self.controllerLimits = controllerLimits
    self.executionStrategyRevision = executionStrategyRevision
    try validate()
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, continuity, ordering, direction, requiredStops, cornerHandling
    case drawingFeedMMPerMinute, travelFeedMMPerMinute, pen, controllerLimits, executionStrategyRevision
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard try values.decode(UInt16.self, forKey: .schemaVersion) == 1,
      try values.decode(Ordering.self, forKey: .ordering) == .authored,
      try values.decode(Direction.self, forKey: .direction) == .authored,
      try values.decode(Stops.self, forKey: .requiredStops) == .strokeEndPenTransitionAndCheckpoint,
      try values.decode(Corners.self, forKey: .cornerHandling) == .controllerJunctionHandling else {
      throw PlotterModelError.invalidValue("unsupported drawing motion policy schema or rules")
    }
    try self.init(continuity: values.decode(Continuity.self, forKey: .continuity),
      drawingFeedMMPerMinute: values.decode(Double.self, forKey: .drawingFeedMMPerMinute),
      travelFeedMMPerMinute: values.decode(Double.self, forKey: .travelFeedMMPerMinute),
      pen: values.decode(DrawingMotionPenPolicy.self, forKey: .pen),
      controllerLimits: values.decode(DrawingControllerMotionLimits.self, forKey: .controllerLimits),
      executionStrategyRevision: values.decode(String.self, forKey: .executionStrategyRevision))
  }

  public func validate() throws {
    guard schemaVersion == 1, drawingFeedMMPerMinute.isFinite, drawingFeedMMPerMinute > 0,
      travelFeedMMPerMinute.isFinite, travelFeedMMPerMinute > 0,
      !executionStrategyRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PlotterModelError.invalidValue("invalid drawing motion policy")
    }
    try pen.validate(); try controllerLimits.validate()
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try validate()
    try encoder.appendString("DrawingMotionPolicy"); encoder.appendUInt16(schemaVersion)
    for value in [continuity.rawValue, ordering.rawValue, direction.rawValue, requiredStops.rawValue,
      cornerHandling.rawValue, executionStrategyRevision] { try encoder.appendString(value) }
    try encoder.appendDouble(drawingFeedMMPerMinute); try encoder.appendDouble(travelFeedMMPerMinute)
    try pen.encodeCanonical(to: &encoder); try controllerLimits.encodeCanonical(to: &encoder)
  }
}
