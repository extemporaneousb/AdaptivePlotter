import Foundation

/// Image-supported closed tonal marks. Every chord is sampled against the same
/// bounds, luminance, support and previously accepted stroke occupancy as Flow.
/// Circle/polygon interiors are not semantic anatomy; these are graphic marks.
package enum PortraitFlowMarkTracer {
  package struct Result: Sendable {
    package let path: [CGPoint]
    package let samples: [CGPoint]
    package let radii: [Double]
  }

  package static func closed(seed: CGPoint, radius: Double, polygonSides: Int?,
    phase: Double, minimumLength: Double, width: Int, height: Int,
    spacing: (CGPoint) -> Double, luminance: (CGPoint) -> Double,
    intersects: (CGPoint, Double) -> Bool, support: ((CGPoint) -> Double)?,
    minimumSupport: Double, minimumClearance: Double = 0
  ) throws -> Result? {
    guard radius.isFinite, radius >= 1, radius <= 16, phase.isFinite,
      seed.x.isFinite, seed.y.isFinite, (4...512).contains(width), (4...512).contains(height),
      minimumLength.isFinite, minimumLength >= 0, minimumSupport.isFinite,
      (0...1).contains(minimumSupport), minimumClearance.isFinite, minimumClearance >= 0 else { return nil }
    let sides = polygonSides.map { min(8, max(3, $0)) }
      ?? min(192, max(24, Int(ceil(2 * .pi * radius / 0.45))))
    let inradius = polygonSides == nil ? radius : radius * cos(.pi / Double(sides))
    // Closing a stroke intentionally joins its adjacent endpoints. Its opposed
    // sides must still leave the same material clearance as separate marks.
    guard 2 * inradius >= minimumClearance + 0.6 else { return nil }
    var vertices = (0..<sides).map { index in
      let angle = phase + Double(index) * 2 * .pi / Double(sides)
      return CGPoint(x: seed.x + radius * cos(angle), y: seed.y + radius * sin(angle))
    }
    vertices.append(vertices[0])
    var samples: [CGPoint] = [], radii: [Double] = [], length = 0.0, confidence = 0.0
    for (a, b) in zip(vertices, vertices.dropFirst()) {
      try Task.checkCancellation()
      let segment = hypot(b.x - a.x, b.y - a.y); length += segment
      let steps = max(1, Int(ceil(segment / 0.45)))
      for index in 0..<steps {
        let t = Double(index) / Double(steps)
        let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        let r = spacing(p), light = luminance(p)
        guard p.x >= 1, p.y >= 1, p.x < Double(width - 2), p.y < Double(height - 2),
          r.isFinite, r > 0, light.isFinite, light < 0.95, !intersects(p, r) else { return nil }
        if let support {
          let value = support(p)
          guard value.isFinite, value >= minimumSupport else { return nil }
          confidence += value
        }
        samples.append(p); radii.append(r)
      }
    }
    guard length >= minimumLength, !samples.isEmpty,
      support == nil || confidence / Double(samples.count) >= minimumSupport else { return nil }
    // The analytic circle/convex polygon cannot self-intersect. Reserve only
    // after accepting the entire loop; adjacent samples must not reject itself.
    return Result(path: vertices, samples: samples, radii: radii)
  }
}
