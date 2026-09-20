import Foundation

public enum DrawingMotionCost {
  public enum Assumption: String, Codable, Hashable, Sendable {
    case isolatedMoves
    /// Idealized junction-deviation approximation with start/end at rest.
    /// Excludes firmware short-segment refinements, direction-change acceleration,
    /// transport overhead and finite planner-buffer starvation. Never a timeout budget.
    case continuousJunctionDeviation
  }
  public struct Estimate: Hashable, Sendable {
    public let assumption: Assumption
    public let seconds: Double?
    public let qualification: String
  }

  /// Acceleration-aware stop-to-stop estimate. Missing acceleration retains the
  /// former distance/feed fallback. Timeout grace and caps belong to Runtime.
  public static func isolatedMoveSeconds(dx: Double, dy: Double, feedMMPerMinute: Double,
    limits: DrawingControllerMotionLimits) -> Double {
    let distance = hypot(dx, dy)
    guard distance.isFinite, feedMMPerMinute.isFinite, feedMMPerMinute > 0 else { return .infinity }
    guard distance > 0 else { return 0 }
    guard let segment = segment(dx: dx, dy: dy, feed: feedMMPerMinute, limits: limits) else {
      return distance / feedMMPerMinute * 60
    }
    return duration(distance: distance, velocity: segment.velocity, acceleration: segment.acceleration,
      entry: 0, exit: 0)
  }

  public static func estimate(path: Polyline<MachineSpace>, feedMMPerMinute: Double,
    limits: DrawingControllerMotionLimits, assumption: Assumption) -> Estimate {
    guard feedMMPerMinute.isFinite, feedMMPerMinute > 0, (try? limits.validate()) != nil else {
      return Estimate(assumption: assumption, seconds: nil, qualification: "Invalid motion inputs.")
    }
    let vectors = zip(path.points, path.points.dropFirst()).map { ($1.x - $0.x, $1.y - $0.y) }
      .filter { hypot($0.0, $0.1) > 0 }
    if assumption == .isolatedMoves {
      let seconds = vectors.reduce(0) { $0 + isolatedMoveSeconds(dx: $1.0, dy: $1.1,
        feedMMPerMinute: feedMMPerMinute, limits: limits) }
      let complete = vectors.allSatisfy { segment(dx: $0.0, dy: $0.1,
        feed: feedMMPerMinute, limits: limits) != nil }
      return Estimate(assumption: assumption, seconds: seconds.isFinite ? seconds : nil,
        qualification: complete ? "Stop-to-stop acceleration estimate; excludes command and pen time."
          : "Missing controller limits: distance/feed fallback; excludes acceleration, command and pen time.")
    }
    guard let deviation = limits.junctionDeviationMM else {
      return Estimate(assumption: assumption, seconds: nil, qualification: "Controller junction deviation was not captured.")
    }
    let segments = vectors.compactMap { segment(dx: $0.0, dy: $0.1, feed: feedMMPerMinute, limits: limits) }
    guard segments.count == vectors.count else {
      return Estimate(assumption: assumption, seconds: nil, qualification: "Controller axis feed or acceleration limits were not captured.")
    }
    guard !segments.isEmpty else {
      return Estimate(assumption: assumption, seconds: 0, qualification: "No nonzero segments.")
    }
    var speeds = Array(repeating: 0.0, count: segments.count + 1)
    for index in 1..<segments.count {
      let before = segments[index - 1], after = segments[index]
      let dot = min(1, max(-1, before.ux * after.ux + before.uy * after.uy))
      let sineHalf = sqrt((1 + dot) / 2)
      let cap = min(before.velocity, after.velocity)
      speeds[index] = sineHalf >= 1 - 1e-12 ? cap : min(cap,
        sqrt(max(0, min(before.acceleration, after.acceleration) * deviation * sineHalf / (1 - sineHalf))))
    }
    for index in segments.indices {
      speeds[index + 1] = min(speeds[index + 1],
        sqrt(speeds[index] * speeds[index] + 2 * segments[index].acceleration * segments[index].distance))
    }
    for index in segments.indices.reversed() {
      speeds[index] = min(speeds[index],
        sqrt(speeds[index + 1] * speeds[index + 1] + 2 * segments[index].acceleration * segments[index].distance))
    }
    let seconds = segments.indices.reduce(0.0) { total, index in
      let value = segments[index]
      return total + duration(distance: value.distance, velocity: value.velocity,
        acceleration: value.acceleration, entry: speeds[index], exit: speeds[index + 1])
    }
    return Estimate(assumption: assumption, seconds: seconds.isFinite ? seconds : nil,
      qualification: "Idealized junction-deviation approximation; start/end stopped; excludes firmware refinements, direction-change acceleration, transport, buffer starvation and pen time. Not a timeout budget.")
  }

  private struct Segment {
    let distance: Double
    let velocity: Double
    let acceleration: Double
    let ux: Double
    let uy: Double
  }
  private static func segment(dx: Double, dy: Double, feed: Double,
    limits: DrawingControllerMotionLimits) -> Segment? {
    let distance = hypot(dx, dy)
    guard distance.isFinite, distance > 0,
      let xf = limits.maximumXFeedMMPerMinute, let yf = limits.maximumYFeedMMPerMinute,
      let xa = limits.xAccelerationMMPerSecondSquared, let ya = limits.yAccelerationMMPerSecondSquared,
      xf > 0, yf > 0, xa > 0, ya > 0 else { return nil }
    let x = abs(dx) / distance, y = abs(dy) / distance
    let velocity = min(feed, x > 0 ? xf / x : .infinity, y > 0 ? yf / y : .infinity) / 60
    let acceleration = min(x > 0 ? xa / x : .infinity, y > 0 ? ya / y : .infinity)
    return Segment(distance: distance, velocity: velocity, acceleration: acceleration, ux: dx / distance, uy: dy / distance)
  }
  private static func duration(distance: Double, velocity: Double, acceleration: Double,
    entry: Double, exit: Double) -> Double {
    let peak = min(velocity, sqrt(acceleration * distance + (entry * entry + exit * exit) / 2))
    let acceleratingDistance = max(0, (peak * peak - entry * entry) / (2 * acceleration))
    let deceleratingDistance = max(0, (peak * peak - exit * exit) / (2 * acceleration))
    return max(0, peak - entry) / acceleration + max(0, peak - exit) / acceleration
      + max(0, distance - acceleratingDistance - deceleratingDistance) / peak
  }
}
