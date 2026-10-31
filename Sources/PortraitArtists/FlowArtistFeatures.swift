import Foundation
import PlotterModel

/// Frozen, image-conditioned features. Fixed physical/image normalizations avoid
/// estimating preprocessing statistics from held-out photos.
package enum FlowArtistFeatures {
  package static let revision = "flow-artist-image-and-mask-features-v2"
  package static let legacyRevision = "flow-artist-image-and-mask-features-v1"
  package static let drawingCount = 153
  package static let strokeCount = 106

  package static func source(raster: PortraitRaster) -> [Double] {
    guard valid(raster) else { return Array(repeating: 0, count: 8) }
    let stride = max(1, raster.luminance.count / 4096)
    let samples = Swift.stride(from: 0, to: raster.luminance.count, by: stride).map { raster.luminance[$0] }
    let mean = samples.reduce(0, +) / Double(samples.count)
    let deviation = sqrt(samples.reduce(0) { $0 + pow($1 - mean, 2) } / Double(samples.count))
    var gradient = 0.0
    for index in Swift.stride(from: 0, to: raster.luminance.count, by: stride) {
      gradient += gradientAt(x: Double(index % raster.width), y: Double(index / raster.width), raster: raster)
    }
    let face = raster.faceBounds
    return [mean, deviation, gradient / Double(samples.count),
      Double(samples.filter { $0 < 0.45 }.count) / Double(samples.count), face == nil ? 0 : 1,
      min(1, max(0, Double(face?.width ?? 0))), min(1, max(0, Double(face?.height ?? 0))),
      Double(raster.width) / Double(raster.width + raster.height)]
  }

  package static func drawing(recipe: FlowArtistRecipe, program: DrawingProgram, raster: PortraitRaster,
    removedIndices: Set<Int> = []) -> [Double] {
    let photo = source(raster: raster), parameters = recipe.coordinates.map { $0 * 2 - 1 }
    let remaining = program.strokes.indices.filter { !removedIndices.contains($0) }
    let height = max(0.0001, program.fieldExtent.height), width = max(0.0001, program.fieldExtent.width)
    var length = 0.0, straightness = 0.0, turning = 0.0, closed = 0.0, corners = 0.0
    var bins = Array(repeating: 0.0, count: 9)
    for index in remaining {
      let path = program.strokes[index].path, points = path.points
      let normalizedLength = path.length / height
      length += normalizedLength
      if let first = points.first, let last = points.last {
        let ratio = min(1, hypot(last.x - first.x, last.y - first.y) / max(0.0001, path.length))
        straightness += ratio
        if ratio < 0.025 { closed += 1 }
      }
      let normalized = points.map { CGPoint(x: $0.x / width, y: $0.y / height) }
      turning += turn(normalized); corners += cornerFraction(normalized)
      for (a, b) in zip(points, points.dropFirst()) {
        let x = min(2, max(0, Int((a.x + b.x) / (2 * width) * 3)))
        let y = min(2, max(0, Int((a.y + b.y) / (2 * height) * 3)))
        bins[y * 3 + x] += hypot(b.x - a.x, b.y - a.y) / height
      }
    }
    let n = Double(max(1, remaining.count))
    let summary = [saturate(Double(remaining.count), scale: 300), saturate(length, scale: 40),
      Double(remaining.count) / Double(max(1, program.strokes.count)), straightness / n, turning / n]
      + bins.map { saturate($0, scale: 6) } + [closed / n, corners / n]
    // Source-only values cancel in same-photo comparisons. These interactions
    // allow different photos to prefer different parameters and retained masks.
    var features: [Double] = [1]
    features += parameters
    features += parameters.map { $0 * $0 }
    features += photo
    for parameter in parameters { for value in photo.prefix(4) { features.append(parameter * value) } }
    features += summary
    for statistic in summary { for value in photo.prefix(2) { features.append(statistic * value) } }
    return features
  }

  /// Known recipe/photo terms only. The output-statistic terms are zero, so this
  /// is a bounded proposal heuristic, never a claim to score an unseen drawing.
  package static func proposal(recipe: FlowArtistRecipe, raster: PortraitRaster) -> [Double] {
    let photo = source(raster: raster), parameters = recipe.coordinates.map { $0 * 2 - 1 }
    var result: [Double] = [1]
    result += parameters; result += parameters.map { $0 * $0 }; result += photo
    for parameter in parameters { for value in photo.prefix(4) { result.append(parameter * value) } }
    result += Array(repeating: 0, count: 48)
    return result
  }

  package static func strokes(recipe: FlowArtistRecipe, program: DrawingProgram, raster: PortraitRaster) -> [[Double]] {
    let photo = source(raster: raster), parameters = recipe.coordinates.map { $0 * 2 - 1 }
    let width = max(0.0001, program.fieldExtent.width), height = max(0.0001, program.fieldExtent.height)
    let normalized = program.strokes.map { stroke in
      stroke.path.points.map { CGPoint(x: $0.x / width, y: 1 - $0.y / height) }
    }
    let centers = normalized.map { points -> CGPoint in
      let total = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
      return CGPoint(x: total.x / Double(max(1, points.count)), y: total.y / Double(max(1, points.count)))
    }
    func key(_ x: Int, _ y: Int) -> String { "\(x),\(y)" }
    var cells: [String: [Int]] = [:]
    for (index, center) in centers.enumerated() { cells[key(Int(floor(center.x / 0.08)), Int(floor(center.y / 0.08))), default: []].append(index) }
    let field = valid(raster) ? PortraitRegionalTreatment.Field(raster: raster) : nil
    return program.strokes.indices.map { index in
      let stroke = program.strokes[index], points = normalized[index], center = centers[index]
      let cellX = Int(floor(center.x / 0.08)), cellY = Int(floor(center.y / 0.08))
      var nearby: [Int] = []
      for y in (cellY - 1)...(cellY + 1) { for x in (cellX - 1)...(cellX + 1) { nearby += cells[key(x, y)] ?? [] } }
      let neighbors = nearby.filter { $0 != index }
      let nearest = neighbors.prefix(128).map { hypot(centers[$0].x - center.x, centers[$0].y - center.y) }.min() ?? 0.25
      let sampleStep = max(1, points.count / 32)
      let samples = Swift.stride(from: 0, to: points.count, by: sampleStep).prefix(33).map { points[$0] }
      var light = 0.0, gradient = 0.0, protection = 0.0, supports = Array(repeating: 0.0, count: 5)
      let regions: [PortraitTreatmentRegion] = [.face, .eyes, .mouth, .skin, .silhouette]
      for p in samples {
        let point = CGPoint(x: p.x * Double(raster.width) - 0.5, y: p.y * Double(raster.height) - 0.5)
        light += luminance(x: point.x, y: point.y, raster: raster)
        gradient += gradientAt(x: point.x, y: point.y, raster: raster)
        protection = max(protection, field?.protection(point) ?? 0)
        for r in regions.indices { supports[r] = max(supports[r], field?.weight(point, region: regions[r]) ?? 0) }
      }
      let sampleCount = Double(max(1, samples.count))
      let endpointDistance: Double = points.count < 2 ? 0 : Double(hypot(points.last!.x - points.first!.x, points.last!.y - points.first!.y))
      let length = stroke.path.length / height
      let base: [Double] = [1, Double(center.x), Double(center.y), saturate(length, scale: 0.3),
        min(1, endpointDistance / max(0.0001, length)), turn(points), light / sampleCount,
        gradient / sampleCount, saturate(Double(neighbors.count), scale: 12), min(1, nearest / 0.25),
        protection] + supports + [field == nil ? 0.0 : 1.0,
          endpointDistance / max(0.0001, length) < 0.025 ? 1.0 : 0.0]
      let geometry = [base[3], base[4], base[5], base[7], base[8]]
      let style = [parameters[3], parameters[6], parameters[11], parameters[12], parameters[13], parameters[14]]
      var features = base
      features += parameters
      features += photo
      for statistic in base.dropFirst() { for value in photo.prefix(2) { features.append(statistic * value) } }
      for statistic in geometry { for value in style { features.append(statistic * value) } }
      return features
    }
  }

  private static func valid(_ raster: PortraitRaster) -> Bool {
    raster.width > 0 && raster.height > 0 && raster.width <= 8192 && raster.height <= 8192
      && raster.luminance.count == raster.width * raster.height
      && raster.luminance.allSatisfy { $0.isFinite && (0...1).contains($0) }
  }
  private static func luminance(x: Double, y: Double, raster: PortraitRaster) -> Double {
    guard raster.width > 0, raster.height > 0, x.isFinite, y.isFinite else { return 0 }
    let ix = min(raster.width - 1, max(0, Int(x.rounded()))), iy = min(raster.height - 1, max(0, Int(y.rounded())))
    let index = iy * raster.width + ix
    guard index < raster.luminance.count else { return 0 }
    let value = raster.luminance[index]
    return value.isFinite ? min(1, max(0, value)) : 0
  }
  private static func gradientAt(x: Double, y: Double, raster: PortraitRaster) -> Double {
    hypot(luminance(x: x + 1, y: y, raster: raster) - luminance(x: x - 1, y: y, raster: raster),
      luminance(x: x, y: y + 1, raster: raster) - luminance(x: x, y: y - 1, raster: raster)) / sqrt(2)
  }
  private static func turn(_ points: [CGPoint]) -> Double {
    let points = resampled(points)
    guard points.count > 2 else { return 0 }
    var total = 0.0, count = 0.0
    for index in 1..<(points.count - 1) {
      let a = points[index - 1], b = points[index], c = points[index + 1]
      let ux = b.x - a.x, uy = b.y - a.y, vx = c.x - b.x, vy = c.y - b.y
      let norm = hypot(ux, uy) * hypot(vx, vy)
      if norm > 1e-12 { total += acos(min(1, max(-1, (ux * vx + uy * vy) / norm))) / .pi; count += 1 }
    }
    return total / max(1, count)
  }
  private static func cornerFraction(_ points: [CGPoint]) -> Double {
    let points = resampled(points)
    guard points.count > 2 else { return 0 }
    var count = 0.0
    for index in 1..<(points.count - 1) {
      let a = points[index - 1], b = points[index], c = points[index + 1]
      let ux = b.x - a.x, uy = b.y - a.y, vx = c.x - b.x, vy = c.y - b.y
      let norm = hypot(ux, uy) * hypot(vx, vy)
      if norm > 1e-12, (ux * vx + uy * vy) / norm < cos(.pi / 6) { count += 1 }
    }
    return count / Double(points.count - 2)
  }
  /// Fixed arc-length sampling prevents a renderer's vertex budget from being
  /// mistaken for artistic curvature when a path is represented more densely.
  private static func resampled(_ points: [CGPoint]) -> [CGPoint] {
    guard points.count > 2 else { return points }
    var cumulative = [0.0]
    for (a, b) in zip(points, points.dropFirst()) { cumulative.append(cumulative.last! + hypot(b.x - a.x, b.y - a.y)) }
    let length = cumulative.last!
    guard length > 1e-12 else { return Array(points.prefix(2)) }
    var result: [CGPoint] = [], segment = 1
    for index in 0..<33 {
      let distance = length * Double(index) / 32
      while segment < points.count - 1, cumulative[segment] < distance { segment += 1 }
      let a = points[segment - 1], b = points[segment]
      let t = (distance - cumulative[segment - 1]) / max(1e-12, cumulative[segment] - cumulative[segment - 1])
      result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
    }
    return result
  }
  private static func saturate(_ value: Double, scale: Double) -> Double { max(0, value) / (max(0, value) + scale) }
}
