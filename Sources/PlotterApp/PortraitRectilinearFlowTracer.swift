import Foundation

/// A straight tonal mark aligned with one image-derived cardinal direction.
/// The caller owns shared structural/tonal occupancy and the material floor.
/// Interior samples are reserved there; only the two endpoints become drawing
/// vertices. Choosing the axis once prevents per-sample snapping staircases.
enum PortraitRectilinearFlowTracer {
  struct Result: Equatable {
    let sampledPath: [CGPoint]
    let radii: [Double]
    let endpoints: [CGPoint]
  }

  static func trace(seed: CGPoint, tangent: CGPoint, width: Int, height: Int,
    minimumLength: Double, spacing: (CGPoint) -> Double,
    luminance: (CGPoint) -> Double, intersects: (CGPoint, Double) -> Bool
  ) throws -> Result? {
    try Task.checkCancellation()
    guard width >= 4, height >= 4, width <= 512, height <= 512,
      seed.x.isFinite, seed.y.isFinite, tangent.x.isFinite, tangent.y.isFinite,
      minimumLength.isFinite, minimumLength >= 0 else { return nil }
    // A line field has no sign. Opposite tangents produce identical geometry;
    // the exact diagonal tie uses the horizontal axis deterministically.
    let horizontal = abs(tangent.x) >= abs(tangent.y)
    let step = 0.9
    let maximumSteps = Int(ceil(Double(horizontal ? width : height) / step))
    func acceptedRadius(at point: CGPoint) -> Double? {
      guard point.x >= 1, point.y >= 1,
        point.x < Double(width - 2), point.y < Double(height - 2) else { return nil }
      let value = luminance(point), radius = spacing(point)
      guard value.isFinite, value < 0.95, radius.isFinite, radius > 0,
        !intersects(point, radius) else { return nil }
      return radius
    }
    guard let seedRadius = acceptedRadius(at: seed) else { return nil }
    func extend(sign: Double) throws -> (points: [CGPoint], radii: [Double]) {
      var points: [CGPoint] = [], radii: [Double] = []
      for index in 1...maximumSteps {
        if index.isMultiple(of: 32) { try Task.checkCancellation() }
        let offset = sign * Double(index) * step
        let point = CGPoint(x: seed.x + (horizontal ? offset : 0),
          y: seed.y + (horizontal ? 0 : offset))
        guard let radius = acceptedRadius(at: point) else { break }
        points.append(point); radii.append(radius)
      }
      return (points, radii)
    }
    let backward = try extend(sign: -1), forward = try extend(sign: 1)
    try Task.checkCancellation()
    let first = backward.points.last ?? seed, last = forward.points.last ?? seed
    let length = hypot(last.x - first.x, last.y - first.y)
    guard length > 0, length >= minimumLength else { return nil }
    return Result(sampledPath: Array(backward.points.reversed()) + [seed] + forward.points,
      radii: Array(backward.radii.reversed()) + [seedRadius] + forward.radii,
      endpoints: [first, last])
  }
}
