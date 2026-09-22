import Foundation

/// Image-evidence curves plus separated, tensor-guided tonal streamlines.
/// All geometry is in analysis pixels. Tone never modifies the structural image;
/// coherence smooths the orientation field, not the facial features underneath it.
/// This is a deterministic 2D renderer, not inferred facial anatomy or depth.
enum PortraitFlowRenderer {
  static let revision = "flow-edge-v1"

  struct Layers {
    let structure: [[CGPoint]]
    let tone: [[CGPoint]]
    let minimumSpacing: Double
  }

  static func paths(from raster: PortraitRaster, options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let result = try layers(from: raster, options: options)
    return result.structure + result.tone
  }

  static func layers(from raster: PortraitRaster, options: PortraitVectorOptions) throws -> Layers {
    try Task.checkCancellation()
    let width = raster.width, height = raster.height
    guard width >= 3, height >= 3, width <= 512, height <= 512,
      raster.luminance.count == width * height,
      raster.luminance.allSatisfy(\.isFinite) else { throw PortraitDrawingError.unreadableImage }
    let source = raster.luminance.map { min(1, max(0, $0)) }
    // Fixed subpixel noise suppression. Unlike the old smoothing control this
    // bandwidth cannot grow until an eye or mouth disappears.
    let image = try blur(source, width: width, height: height, sigma: 0.65)
    let field = try Evidence(image: image, width: width, height: height)
    let materialSpacing = try minimumSpacing(raster: raster, options: options)
    let extracted = try structuralCurves(field: field, options: options)
    let structure = try separatedStructure(extracted, field: field,
      minimumLength: options.minimumContourLength, minimumSpacing: materialSpacing)
    let tone = try tonalCurves(field: field, structure: structure,
      options: options, minimumSpacing: materialSpacing)
    return Layers(structure: structure, tone: tone, minimumSpacing: materialSpacing)
  }

  /// Suppress nearby parallel copies and texture in evidence-priority order.
  /// Real crossings/junctions remain permissible; the renderer does not claim a
  /// positive clearance between anatomical curves that actually meet.
  private static func separatedStructure(_ curves: [[CGPoint]], field: Evidence,
    minimumLength: Double, minimumSpacing: Double) throws -> [[CGPoint]] {
    var ranked: [(index: Int, score: Double)] = []
    for (index, curve) in curves.enumerated() {
      var totalEvidence = 0.0
      for point in curve { totalEvidence += field.sample(field.magnitude, point) }
      let evidence = totalEvidence / Double(curve.count)
      ranked.append((index: index, score: evidence * sqrt(length(curve))))
    }
    ranked.sort { lhs, rhs in
      lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score > rhs.score
    }
    var occupied = Occupancy(width: field.width, height: field.height)
    var result: [[CGPoint]] = []
    for item in ranked {
      try Task.checkCancellation()
      // Sample the fitted curve at subpixel spacing so that a long simplified
      // segment cannot jump through a previously reserved parallel stroke.
      let curve = resampled(curves[item.index])
      let firstAccepted = result.count
      var run: [CGPoint] = []
      func finish() {
        if run.count > 1, length(run) >= minimumLength {
          result.append(run)
        }
        run = []
      }
      for i in curve.indices {
        let a = curve[max(0, i - 1)], b = curve[min(curve.count - 1, i + 1)]
        if occupied.intersects(curve[i], radius: minimumSpacing, parallelTo: unit(b - a)) { finish() }
        else { run.append(curve[i]) }
      }
      finish()
      // Commit only after checking the complete candidate: its adjacent samples
      // and the two sides of a closed-loop join must not reject one another.
      for accepted in result.dropFirst(firstAccepted) { occupied.insert(accepted, radius: minimumSpacing) }
    }
    return result
  }

  /// The tone knob must never undo a physical material spacing floor. Derive
  /// that floor independently of the already-adapted style spacing.
  static func minimumSpacing(raster: PortraitRaster, options: PortraitVectorOptions) throws -> Double {
    guard let material = options.materialContext else { return 1.75 }
    try material.profile.validate()
    let aspect = raster.sourceCropExtent?.aspectRatio
      ?? Double(raster.width - 1) / Double(raster.height - 1)
    let xSamples = Double(raster.sourceCropExtent == nil ? raster.width - 1 : raster.width)
    let ySamples = Double(raster.sourceCropExtent == nil ? raster.height - 1 : raster.height)
    let pitch = min(material.drawingHeightMM * aspect / xSamples, material.drawingHeightMM / ySamples)
    let result = material.profile.conservativeWidthMM / pitch * 1.5
    guard result.isFinite, result > 0 else { throw PortraitDrawingError.unreadableImage }
    return max(1.75, result)
  }

  private struct Evidence {
    let width: Int
    let height: Int
    let image: [Double]
    let gx: [Double]
    let gy: [Double]
    let magnitude: [Double]

    init(image: [Double], width: Int, height: Int) throws {
      self.image = image; self.width = width; self.height = height
      var gx = image, gy = image, magnitude = image
      for y in 0..<height {
        try Task.checkCancellation()
        let up = max(0, y - 1), down = min(height - 1, y + 1)
        for x in 0..<width {
          let left = max(0, x - 1), right = min(width - 1, x + 1), i = y * width + x
          gx[i] = (image[up * width + right] + 2 * image[y * width + right] + image[down * width + right]
            - image[up * width + left] - 2 * image[y * width + left] - image[down * width + left]) / 8
          gy[i] = (image[down * width + left] + 2 * image[down * width + x] + image[down * width + right]
            - image[up * width + left] - 2 * image[up * width + x] - image[up * width + right]) / 8
          magnitude[i] = hypot(gx[i], gy[i])
        }
      }
      self.gx = gx; self.gy = gy; self.magnitude = magnitude
    }

    func sample(_ values: [Double], _ point: CGPoint) -> Double {
      PortraitFlowRenderer.sample(values, point, width: width, height: height)
    }
  }

  private static func structuralCurves(field: Evidence, options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let width = field.width, height = field.height, count = width * height
    let low = max(0.001, options.sketchThreshold), high = low * 2
    var ridge = [Bool](repeating: false, count: count)
    var retained = ridge
    var locations = [CGPoint](repeating: .zero, count: count)
    var queue: [Int] = []
    // Nonmaximum suppression gives subpixel edge ridges; hysteresis retains weak
    // detail only when connected to stronger measured image evidence.
    for y in 1..<(height - 1) {
      try Task.checkCancellation()
      for x in 1..<(width - 1) {
        let i = y * width + x, value = field.magnitude[i]
        guard value >= low else { continue }
        let normal = CGPoint(x: field.gx[i] / value, y: field.gy[i] / value)
        let point = CGPoint(x: x, y: y)
        let before = field.sample(field.magnitude, point - normal)
        let after = field.sample(field.magnitude, point + normal)
        guard value >= before, value > after else { continue }
        let curvature = before - 2 * value + after
        let offset = curvature < -1e-9 ? min(0.5, max(-0.5, (before - after) / (2 * curvature))) : 0
        locations[i] = point + normal * offset
        ridge[i] = true
        if value >= high { retained[i] = true; queue.append(i) }
      }
    }
    var head = 0
    while head < queue.count {
      if head.isMultiple(of: 256) { try Task.checkCancellation() }
      let i = queue[head]; head += 1
      let x = i % width, y = i / width
      for dy in -1...1 {
        for dx in -1...1 where dx != 0 || dy != 0 {
          let nx = x + dx, ny = y + dy
          guard nx > 0, ny > 0, nx < width - 1, ny < height - 1 else { continue }
          let neighbor = ny * width + nx
          if ridge[neighbor], !retained[neighbor] { retained[neighbor] = true; queue.append(neighbor) }
        }
      }
    }
    var links = [[Int]](repeating: [], count: count)
    for i in 0..<count where retained[i] {
      if i.isMultiple(of: 256) { try Task.checkCancellation() }
      let x = i % width, y = i / width
      for dy in -1...1 {
        for dx in -1...1 where dx != 0 || dy != 0 {
          let nx = x + dx, ny = y + dy
          guard nx >= 0, ny >= 0, nx < width, ny < height, retained[ny * width + nx] else { continue }
          if dx != 0, dy != 0, retained[y * width + nx] || retained[ny * width + x] { continue }
          links[i].append(ny * width + nx)
        }
      }
    }
    let starts = (0..<count).filter { !links[$0].isEmpty }.sorted {
      let lhs = links[$0].count == 1, rhs = links[$1].count == 1
      return lhs == rhs ? $0 < $1 : lhs
    }
    func edge(_ a: Int, _ b: Int) -> UInt64 {
      UInt64(min(a, b)) << 32 | UInt64(max(a, b))
    }
    var visited = Set<UInt64>(), curves: [[CGPoint]] = []
    for start in starts {
      try Task.checkCancellation()
      for first in links[start] where !visited.contains(edge(start, first)) {
        var previous = start, current = first, indices = [start], local = Set([start])
        visited.insert(edge(start, first))
        while true {
          if indices.count.isMultiple(of: 128) { try Task.checkCancellation() }
          indices.append(current)
          guard local.insert(current).inserted else { break }
          let direction = unit(locations[current] - locations[previous])
          let next = links[current].filter { !visited.contains(edge(current, $0)) }.max { a, b in
            let da = dot(direction, unit(locations[a] - locations[current]))
            let db = dot(direction, unit(locations[b] - locations[current]))
            return da == db ? a > b : da < db
          }
          guard let next else { break }
          visited.insert(edge(current, next)); previous = current; current = next
        }
        let raw = indices.map { locations[$0] }
        guard length(raw) >= options.minimumContourLength else { continue }
        // Fair within a subpixel tube around the measured ridge. Endpoints and
        // closed-loop joins are retained. Coherence and tone cannot erase it.
        let curve = try fair(raw, tolerance: min(0.3, max(0, options.simplificationTolerance)))
        if curve.count >= 2, length(curve) > 0 { curves.append(curve) }
      }
    }
    return curves
  }

  private static func tonalCurves(field: Evidence, structure: [[CGPoint]],
    options: PortraitVectorOptions, minimumSpacing: Double) throws -> [[CGPoint]] {
    let width = field.width, height = field.height
    // Structure tensors represent an unoriented line field without +/- vector
    // cancellation. Smoothing this field alters flow coherence, not edge evidence.
    let sigma = 1.5 + max(0, options.smoothing) * 1.5
    let radius = Int(ceil(sigma))
    let xx = try coherentField(field.gx.map { $0 * $0 }, width: width, height: height, radius: radius)
    let yy = try coherentField(field.gy.map { $0 * $0 }, width: width, height: height, radius: radius)
    let xy = try coherentField(zip(field.gx, field.gy).map { $0.0 * $0.1 }, width: width, height: height, radius: radius)
    let cos2 = zip(xx, yy).map { $0 - $1 }, sin2 = xy.map { 2 * $0 }
    func direction(_ point: CGPoint, following previous: CGPoint?) -> CGPoint {
      let a = field.sample(cos2, point), b = field.sample(sin2, point)
      // Quiet regions have no measured orientation. The deterministic diagonal
      // fallback is a graphic convention, not claimed surface geometry.
      let angle = hypot(a, b) > 1e-8 ? 0.5 * atan2(b, a) + .pi / 2 : -.pi / 4
      var vector = CGPoint(x: cos(angle), y: sin(angle))
      if let previous, dot(vector, previous) < 0 { vector = vector * -1 }
      return vector
    }
    let nominal = max(3, Double(options.hatchSpacing))
    let strength = min(2, max(0.4, options.tonalStrength))
    func spacing(_ point: CGPoint) -> Double {
      let darkness = max(0, 1 - field.sample(field.image, point))
      return max(minimumSpacing, nominal / ((0.25 + 0.75 * sqrt(darkness)) * sqrt(strength)))
    }
    var occupied = Occupancy(width: width, height: height)
    for curve in structure {
      try Task.checkCancellation()
      occupied.insert(curve, radius: max(minimumSpacing, nominal * 0.45))
    }
    let strideSize = max(2, Int(nominal * 0.6))
    var seeds: [Int] = []
    for y in stride(from: 2, to: height - 2, by: strideSize) {
      for x in stride(from: 2, to: width - 2, by: strideSize) where field.image[y * width + x] < 0.92 {
        seeds.append(y * width + x)
      }
    }
    seeds.sort {
      field.image[$0] == field.image[$1] ? $0 < $1 : field.image[$0] < field.image[$1]
    }
    var curves: [[CGPoint]] = []
    let maximumSteps = 4 * (width + height), stepSize = 0.9
    for seed in seeds {
      try Task.checkCancellation()
      let start = CGPoint(x: seed % width, y: seed / width)
      guard !occupied.intersects(start, radius: spacing(start)) else { continue }
      // Half-pixel visitation catches returning/crossing streamlines while
      // permitting adjacent integration samples. This is per candidate, bounded
      // by maximumSteps, and cannot grow with the number of previous candidates.
      var seen: [Int: Int] = [:]
      var localOccupancy = Occupancy(width: width, height: height)
      func key(_ point: CGPoint) -> Int { Int((point.y * 2).rounded()) * width * 2 + Int((point.x * 2).rounded()) }
      func trace(sign: Double) throws -> [CGPoint] {
        var result: [CGPoint] = [], point = start, heading = direction(start, following: nil) * sign
        for index in 0..<maximumSteps {
          if index.isMultiple(of: 64) { try Task.checkCancellation() }
          let first = direction(point, following: heading)
          let middle = point + first * (stepSize * 0.5)
          let proposed = direction(middle, following: first)
          // A tensor singularity must not create a sudden hairpin. Integrating
          // a bounded turn gives smooth plotter motion; stop at an opposing flow.
          guard dot(proposed, heading) > 0.35 else { break }
          let blend = 0.35 + min(4, max(0, options.smoothing)) * 0.1
          let tangent = unit(proposed * (1 - blend) + heading * blend)
          let next = point + tangent * stepSize
          guard next.x >= 1, next.y >= 1, next.x < Double(width - 2), next.y < Double(height - 2),
            field.sample(field.image, next) < 0.95,
            !occupied.intersects(next, radius: spacing(next)) else { break }
          let progress = sign * Double(index + 1) * stepSize
          guard !localOccupancy.intersects(next, radius: spacing(next),
            excludingAdjacentProgress: progress) else { break }
          let cell = key(next)
          if let earlier = seen[cell], index > 3 || earlier < 0 { break }
          seen[cell] = sign > 0 ? index : -index - 1
          localOccupancy.insert(next, radius: spacing(next), tangent: tangent, progress: progress)
          result.append(next); point = next; heading = tangent
        }
        return result
      }
      let backward = try trace(sign: -1)
      let forward = try trace(sign: 1)
      let curve = Array(backward.reversed()) + [start] + forward
      guard length(curve) >= max(12, options.minimumContourLength * 2) else { continue }
      // Retain integration samples. Chord simplification could cut across a
      // reserved feature curve or through the material clearance tube.
      occupied.insert(curve, radii: curve.map(spacing))
      curves.append(curve)
    }
    return curves
  }

  private struct Occupancy {
    struct Entry { let point: CGPoint; let radius: Double; let tangent: CGPoint; let progress: Double? }
    let width: Int
    let height: Int
    let columns: Int
    let rows: Int
    var cells: [[Entry]]
    var maximumRadius = 0.0
    private let cellSize = 4.0

    init(width: Int, height: Int) {
      self.width = width; self.height = height
      columns = (width + 3) / 4; rows = (height + 3) / 4
      cells = .init(repeating: [], count: columns * rows)
    }

    func intersects(_ point: CGPoint, radius: Double, parallelTo direction: CGPoint? = nil,
      excludingAdjacentProgress progress: Double? = nil) -> Bool {
      // Sampled curves are covered conservatively between their samples as well
      // as at them. The same floor applies to every strength and spacing setting.
      let reach = max(radius, maximumRadius) + 0.6
      let x0 = max(0, Int((point.x - reach) / cellSize)), x1 = min(columns - 1, Int((point.x + reach) / cellSize))
      let y0 = max(0, Int((point.y - reach) / cellSize)), y1 = min(rows - 1, Int((point.y + reach) / cellSize))
      guard x0 <= x1, y0 <= y1 else { return false }
      for y in y0...y1 {
        for x in x0...x1 {
          for entry in cells[y * columns + x] {
            if let direction, abs(dot(direction, entry.tangent)) < 0.8 { continue }
            if let progress, let prior = entry.progress,
              abs(progress - prior) <= max(radius, entry.radius) + 1.8 { continue }
            let distance = max(radius, entry.radius) + 0.6
            let difference = point - entry.point
            if dot(difference, difference) < distance * distance { return true }
          }
        }
      }
      return false
    }

    mutating func insert(_ path: [CGPoint], radius: Double) {
      insert(path, radii: .init(repeating: radius, count: path.count))
    }

    mutating func insert(_ path: [CGPoint], radii: [Double]) {
      guard let first = path.first, let firstRadius = radii.first else { return }
      let firstTangent = path.count > 1 ? unit(path[1] - first) : CGPoint(x: 1, y: 0)
      insert(first, radius: firstRadius, tangent: firstTangent)
      for i in 1..<path.count {
        let a = path[i - 1], b = path[i], steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y))))
        for step in 1...steps {
          let amount = Double(step) / Double(steps)
          insert(a + (b - a) * amount, radius: max(radii[i - 1], radii[i]), tangent: unit(b - a))
        }
      }
    }

    mutating func insert(_ point: CGPoint, radius: Double, tangent: CGPoint, progress: Double? = nil) {
      let x = min(columns - 1, max(0, Int(point.x / cellSize)))
      let y = min(rows - 1, max(0, Int(point.y / cellSize)))
      cells[y * columns + x].append(.init(point: point, radius: radius, tangent: tangent, progress: progress))
      maximumRadius = max(maximumRadius, radius)
    }
  }

  /// Two separable box passes give a continuous piecewise-linear averaging
  /// kernel in O(pixels), independent of coherence radius. This is applied only
  /// to the orientation tensors, never to structural brightness evidence.
  private static func coherentField(_ values: [Double], width: Int, height: Int,
    radius: Int) throws -> [Double] {
    var current = values
    let divisor = Double(2 * radius + 1)
    for _ in 0..<2 {
      var horizontal = current, output = current
      for y in 0..<height {
        try Task.checkCancellation()
        var total = 0.0
        for offset in -radius...radius { total += current[y * width + min(width - 1, max(0, offset))] }
        for x in 0..<width {
          horizontal[y * width + x] = total / divisor
          total -= current[y * width + max(0, x - radius)]
          total += current[y * width + min(width - 1, x + radius + 1)]
        }
      }
      for x in 0..<width {
        try Task.checkCancellation()
        var total = 0.0
        for offset in -radius...radius { total += horizontal[min(height - 1, max(0, offset)) * width + x] }
        for y in 0..<height {
          output[y * width + x] = total / divisor
          total -= horizontal[max(0, y - radius) * width + x]
          total += horizontal[min(height - 1, y + radius + 1) * width + x]
        }
      }
      current = output
    }
    return current
  }

  private static func resampled(_ path: [CGPoint]) -> [CGPoint] {
    guard let first = path.first else { return [] }
    var result = [first]
    for (a, b) in zip(path, path.dropFirst()) {
      let steps = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y) / 0.9)))
      for step in 1...steps { result.append(a + (b - a) * (Double(step) / Double(steps))) }
    }
    return result
  }

  /// Four conservative fairing iterations keep every moved point within 0.4 px
  /// of its observed ridge. A small Douglas-Peucker tolerance bounds the further
  /// chord error; large legacy simplification settings cannot flatten a face.
  private static func fair(_ original: [CGPoint], tolerance: Double) throws -> [CGPoint] {
    guard original.count > 2 else { return original }
    let closed = original.first == original.last
    var points = original
    for _ in 0..<4 {
      try Task.checkCancellation()
      var next = points
      for i in 1..<(points.count - 1) {
        let proposal = points[i] * 0.5 + (points[i - 1] + points[i + 1]) * 0.25
        let displacement = proposal - original[i], distance = hypot(displacement.x, displacement.y)
        next[i] = original[i] + displacement * (distance > 0.4 ? 0.4 / distance : 1)
      }
      if closed, points.count > 3 {
        let proposal = points[0] * 0.5 + (points[1] + points[points.count - 2]) * 0.25
        let displacement = proposal - original[0], distance = hypot(displacement.x, displacement.y)
        next[0] = original[0] + displacement * (distance > 0.4 ? 0.4 / distance : 1)
        next[next.count - 1] = next[0]
      }
      points = next
    }
    guard tolerance > 0 else { return points }
    var keep = Set([0, points.count - 1]), pending = [(0, points.count - 1)]
    while let (first, last) = pending.popLast() {
      try Task.checkCancellation()
      guard last - first > 1 else { continue }
      let a = points[first], direction = points[last] - a, squared = dot(direction, direction)
      var farthest = first, maximum = tolerance
      for i in (first + 1)..<last {
        let t = squared > 0 ? min(1, max(0, dot(points[i] - a, direction) / squared)) : 0
        let delta = points[i] - (a + direction * t), distance = hypot(delta.x, delta.y)
        if distance > maximum { maximum = distance; farthest = i }
      }
      if farthest != first {
        keep.insert(farthest); pending.append((first, farthest)); pending.append((farthest, last))
      }
    }
    return keep.sorted().map { points[$0] }
  }

  private static func blur(_ values: [Double], width: Int, height: Int, sigma: Double) throws -> [Double] {
    let radius = Int(ceil(3 * sigma))
    let raw = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
    let sum = raw.reduce(0, +), kernel = raw.map { $0 / sum }
    var horizontal = values, result = values
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        var value = 0.0
        for offset in -radius...radius {
          value += values[y * width + min(width - 1, max(0, x + offset))] * kernel[offset + radius]
        }
        horizontal[y * width + x] = value
      }
    }
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        var value = 0.0
        for offset in -radius...radius {
          value += horizontal[min(height - 1, max(0, y + offset)) * width + x] * kernel[offset + radius]
        }
        result[y * width + x] = value
      }
    }
    return result
  }

  private static func sample(_ values: [Double], _ point: CGPoint, width: Int, height: Int) -> Double {
    let px = min(Double(width - 1), max(0, point.x)), py = min(Double(height - 1), max(0, point.y))
    let x = Int(px), y = Int(py), x1 = min(width - 1, x + 1), y1 = min(height - 1, y + 1)
    let fx = px - Double(x), fy = py - Double(y)
    return (values[y * width + x] * (1 - fx) + values[y * width + x1] * fx) * (1 - fy)
      + (values[y1 * width + x] * (1 - fx) + values[y1 * width + x1] * fx) * fy
  }

  private static func length(_ points: [CGPoint]) -> Double {
    zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
  }
  private static func dot(_ a: CGPoint, _ b: CGPoint) -> Double { a.x * b.x + a.y * b.y }
  private static func unit(_ point: CGPoint) -> CGPoint {
    let size = hypot(point.x, point.y)
    return size > 1e-12 ? point * (1 / size) : CGPoint(x: 1, y: 0)
  }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
private func * (lhs: CGPoint, rhs: Double) -> CGPoint { CGPoint(x: lhs.x * rhs, y: lhs.y * rhs) }
