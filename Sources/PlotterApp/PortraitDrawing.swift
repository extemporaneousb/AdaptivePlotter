import CryptoKit
import Foundation
import PlotterModel

enum PortraitPose: String, CaseIterable, Identifiable, Sendable {
  case left = "Left", front = "Front", right = "Right"
  var id: Self { self }
}

enum PortraitStyle: String, CaseIterable, Identifiable, Sendable {
  case contours = "Contour", hatch = "Hatch", crosshatch = "Crosshatch"
  case sketch = "Sketch", sketchHatch = "Sketch + hatch"
  var id: Self { self }
}

/// Spatial values refer to analyzed-raster pixels, independently of paper
/// placement. They alter authored geometry only, never plotting authority.
struct PortraitVectorOptions: Hashable, Sendable {
  var contourLevels = 6
  var minimumContourLength = 3.0
  var simplificationTolerance = 0.35
  var hatchSpacing = 2
  var tonalStrength = 1.0
  var smoothing = 0.0
  var sketchThreshold = 0.012

  var bounded: Self {
    var result = self
    result.contourLevels = min(12, max(1, contourLevels))
    result.minimumContourLength = Self.clamp(minimumContourLength, to: 0...40, fallback: 3)
    result.simplificationTolerance = Self.clamp(simplificationTolerance, to: 0...3, fallback: 0.35)
    result.hatchSpacing = min(16, max(1, hatchSpacing))
    result.tonalStrength = Self.clamp(tonalStrength, to: 0.4...2, fallback: 1)
    result.smoothing = Self.clamp(smoothing, to: 0...4, fallback: 0)
    result.sketchThreshold = Self.clamp(sketchThreshold, to: 0.002...0.08, fallback: 0.012)
    return result
  }

  var provenance: String {
    "levels=\(contourLevels)|minLength=\(minimumContourLength)|simplify=\(simplificationTolerance)"
      + "|hatchSpacing=\(hatchSpacing)|tone=\(tonalStrength)|smooth=\(smoothing)|sketchThreshold=\(sketchThreshold)"
  }

  private static func clamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
  }
}

enum PortraitVectorPreset: String, CaseIterable, Identifiable, Sendable {
  case fine = "Fine", balanced = "Balanced", broadMarker = "Broad marker"
  var id: Self { self }
  var options: PortraitVectorOptions {
    switch self {
    case .fine:
      PortraitVectorOptions(contourLevels: 8, minimumContourLength: 2,
        simplificationTolerance: 0.2, hatchSpacing: 2, tonalStrength: 1, smoothing: 0.35)
    case .balanced:
      PortraitVectorOptions(contourLevels: 5, minimumContourLength: 4,
        simplificationTolerance: 0.5, hatchSpacing: 4, tonalStrength: 1, smoothing: 0.7)
    case .broadMarker:
      PortraitVectorOptions(contourLevels: 3, minimumContourLength: 8,
        simplificationTolerance: 1, hatchSpacing: 8, tonalStrength: 0.85, smoothing: 1.3,
        sketchThreshold: 0.018)
    }
  }
}

/// A bounded, top-left-origin brightness image. Image analysis owns cropping
/// and background removal; the vectorizer knows nothing about cameras or motion.
struct PortraitRaster: Sendable {
  let width: Int
  let height: Int
  let luminance: [Double]
  let provenance: String
  let analysisSummary: String
}

enum PortraitDrawingError: LocalizedError {
  case unreadableImage, noLines, noCameraFrame
  var errorDescription: String? {
    switch self {
    case .unreadableImage: "The image could not be decoded."
    case .noLines: "This style produced no lines. Try another style or turn off background removal."
    case .noCameraFrame: "Waiting for a portrait camera frame. Retry Capture after the face video appears."
    }
  }
}

enum PortraitVectorizer {
  static func program(
    from raster: PortraitRaster, pose: PortraitPose, style: PortraitStyle,
    levels: Int? = nil, strokeStyle: StrokeStyle,
    vectorOptions: PortraitVectorOptions = PortraitVectorOptions()
  ) throws -> DrawingProgram {
    try Task.checkCancellation()
    guard raster.width >= 2, raster.height >= 2, raster.width <= 512, raster.height <= 512,
      raster.luminance.count == raster.width * raster.height,
      raster.luminance.allSatisfy(\.isFinite)
    else { throw PortraitDrawingError.unreadableImage }
    var configuration = vectorOptions
    if let levels { configuration.contourLevels = levels }
    let options = configuration.bounded
    let prepared = try preparedRaster(raster, options: options)
    let paths: [[CGPoint]]
    switch style {
    case .contours: paths = try contours(prepared, options: options)
    case .hatch: paths = try hatching(prepared, crosshatch: false, spacing: options.hatchSpacing)
    case .crosshatch: paths = try hatching(prepared, crosshatch: true, spacing: options.hatchSpacing)
    case .sketch: paths = try sketch(prepared, options: options)
    case .sketchHatch:
      paths = try sketch(prepared, options: options)
        + hatching(prepared, crosshatch: false, spacing: options.hatchSpacing)
    }
    guard !paths.isEmpty else { throw PortraitDrawingError.noLines }
    let provenance = "portrait-v2|\(raster.provenance)|pose=\(pose.rawValue)|style=\(style.rawValue)|\(options.provenance)"
    let extent = try Size2<FieldSpace>(
      width: 100 * Double(raster.width - 1) / Double(raster.height - 1), height: 100)
    let strokes = try paths.enumerated().map { index, path in
      try Task.checkCancellation()
      return LogicalStroke(
        id: StrokeID(stableID("\(provenance)|stroke=\(index)")),
        path: try Polyline(points: path.map { point in
          // Raster +Y is down; drawing-local FieldSpace +Y is up.
          try Point2<FieldSpace>(
            x: Double(point.x) / Double(raster.width - 1) * extent.width,
            y: (1.0 - Double(point.y) / Double(raster.height - 1)) * extent.height)
        }),
        style: strokeStyle, ordering: UInt32(index))
    }
    return try DrawingProgram(
      id: ProgramID(stableID(provenance)), fieldExtent: extent, strokes: strokes,
      source: DrawingSourceProvenance(kind: "portrait", sourceIdentifier: provenance))
  }

  static func stableID(_ text: String) -> UUID {
    let b = Array(SHA256.hash(data: Data(text.utf8)))
    return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                       b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
  }

  /// Marching squares joins shared grid edges by identity, avoiding gaps from
  /// rounded coordinates and preserving closed curves as uninterrupted strokes.
  private static func contours(_ raster: PortraitRaster, options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let w = raster.width, h = raster.height
    var paths: [[CGPoint]] = []
    let levels = options.contourLevels
    for levelIndex in 1...max(1, levels) {
      let level = Double(levelIndex) / Double(max(1, levels) + 1)
      var points: [Int: CGPoint] = [:]
      var links: [Int: [Int]] = [:]
      for y in 0..<(h - 1) {
        try Task.checkCancellation()
        for x in 0..<(w - 1) {
          let values = [raster.luminance[y*w+x], raster.luminance[y*w+x+1],
                        raster.luminance[(y+1)*w+x+1], raster.luminance[(y+1)*w+x]]
          let corners = [CGPoint(x: x, y: y), CGPoint(x: x+1, y: y),
                         CGPoint(x: x+1, y: y+1), CGPoint(x: x, y: y+1)]
          let ids = [(y*w+x)*2, (y*w+x+1)*2+1,
                     ((y+1)*w+x)*2, (y*w+x)*2+1]
          var crossings: [Int] = []
          for edge in 0..<4 {
            let next = (edge + 1) % 4
            if (values[edge] < level) != (values[next] < level) {
              let t = (level - values[edge]) / (values[next] - values[edge])
              points[ids[edge]] = CGPoint(
                x: corners[edge].x + t * (corners[next].x - corners[edge].x),
                y: corners[edge].y + t * (corners[next].y - corners[edge].y))
              crossings.append(edge)
            }
          }
          let pairs: [(Int, Int)]
          if crossings.count == 2 {
            pairs = [(crossings[0], crossings[1])]
          } else if crossings.count == 4 {
            // Resolve a saddle from the cell center, consistently on both axes.
            let centerLow = values.reduce(0, +) / 4 < level
            pairs = (centerLow == (values[0] < level)) ? [(0, 1), (2, 3)] : [(0, 3), (1, 2)]
          } else { continue }
          for (a, b) in pairs {
            links[ids[a], default: []].append(ids[b])
            links[ids[b], default: []].append(ids[a])
          }
        }
      }
      var visited: Set<Int> = []
      // Start open paths at endpoints; closed paths then start at a stable edge.
      let starts = links.keys.sorted { a, b in
        let aEnd = links[a]?.count == 1, bEnd = links[b]?.count == 1
        return aEnd != bEnd ? aEnd : a < b
      }
      for start in starts where !visited.contains(start) {
        try Task.checkCancellation()
        var path: [CGPoint] = [], current = start, previous: Int?
        repeat {
          visited.insert(current)
          if let point = points[current] { path.append(point) }
          guard let next = links[current]?.first(where: { $0 != previous }) else { break }
          previous = current
          current = next
          if current == start {
            if let point = points[start] { path.append(point) }
            break
          }
        } while !visited.contains(current)
        if let cleaned = try cleanedPath(path, options: options) { paths.append(cleaned) }
      }
    }
    return paths
  }

  /// Continuous tonal scanlines reduce pen lifts compared with the legacy
  /// per-cell hatch marks. A darker orthogonal pass supplies crosshatching.
  private static func hatching(_ raster: PortraitRaster, crosshatch: Bool, spacing: Int) throws -> [[CGPoint]] {
    var paths: [[CGPoint]] = []
    for vertical in crosshatch ? [false, true] : [false] {
      let rows = vertical ? raster.width : raster.height
      let columns = vertical ? raster.height : raster.width
      for (rowIndex, row) in stride(from: 1, to: rows - 1, by: spacing).enumerated() {
        try Task.checkCancellation()
        let threshold = vertical ? 0.30 : [0.35, 0.55, 0.75][rowIndex % 3]
        var start: Int?
        for column in 0...columns {
          let dark = column < columns && (vertical
            ? raster.luminance[column*raster.width+row]
            : raster.luminance[row*raster.width+column]) < threshold
          if dark, start == nil { start = column }
          if !dark, let first = start {
            let last = column - 1
            if last > first {
              var line = vertical
                ? [CGPoint(x: row, y: first), CGPoint(x: row, y: last)]
                : [CGPoint(x: first, y: row), CGPoint(x: last, y: row)]
              if rowIndex.isMultiple(of: 2) { line.reverse() }
              paths.append(line)
            }
            start = nil
          }
        }
      }
    }
    return paths
  }

  private static func preparedRaster(_ raster: PortraitRaster, options: PortraitVectorOptions) throws -> PortraitRaster {
    let smooth = try gaussian(raster.luminance, width: raster.width, height: raster.height,
                              sigma: options.smoothing)
    let values = smooth.map { pow(min(1, max(0, $0)), options.tonalStrength) }
    return PortraitRaster(width: raster.width, height: raster.height, luminance: values,
      provenance: raster.provenance, analysisSummary: raster.analysisSummary)
  }

  /// Separable, edge-clamped Gaussian. The bounded sigma limits the kernel to
  /// 25 samples; cancellation is checked between rows and between passes.
  private static func gaussian(_ values: [Double], width: Int, height: Int, sigma: Double) throws -> [Double] {
    guard sigma > 0.05 else { return values }
    let radius = Int(ceil(sigma * 3))
    let unscaled = (-radius...radius).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
    let total = unscaled.reduce(0, +)
    let kernel = unscaled.map { $0 / total }
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

  /// A local Difference-of-Gaussians sketch, not a learned portrait model.
  /// The dark-side response selects structural transitions. Thinning turns
  /// each ink band into centerlines so a physical pen draws it once rather
  /// than tracing both sides of a raster line. Tonal contours remain separate.
  private static func sketch(_ raster: PortraitRaster, options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let w = raster.width, h = raster.height
    guard w > 2, h > 2 else { return [] }
    let narrow = try gaussian(raster.luminance, width: w, height: h, sigma: 0.8)
    let wide = try gaussian(raster.luminance, width: w, height: h, sigma: 1.6)
    var ink = zip(narrow, wide).map { $0.0 - $0.1 < -options.sketchThreshold }
    // Zhang-Suen thinning preserves endpoints and connected components. The
    // DoG bands are narrow; the cap also bounds adversarial input work.
    for _ in 0..<min(max(w, h), 96) {
      var changed = false
      for pass in 0...1 {
        var remove: [Int] = []
        for y in 1..<(h - 1) {
          try Task.checkCancellation()
          for x in 1..<(w - 1) where ink[y*w+x] {
            let i = y*w+x
            let p = [ink[i-w], ink[i-w+1], ink[i+1], ink[i+w+1],
                     ink[i+w], ink[i+w-1], ink[i-1], ink[i-w-1]]
            let count = p.filter { $0 }.count
            guard (2...6).contains(count) else { continue }
            let transitions = (0..<8).filter { !p[$0] && p[($0+1)%8] }.count
            guard transitions == 1 else { continue }
            let first = pass == 0 ? !(p[0] && p[2] && p[4]) : !(p[0] && p[2] && p[6])
            let second = pass == 0 ? !(p[2] && p[4] && p[6]) : !(p[0] && p[4] && p[6])
            if first && second { remove.append(i) }
          }
        }
        for index in remove { ink[index] = false }
        changed = changed || !remove.isEmpty
      }
      if !changed { break }
    }

    var links: [Int: [Int]] = [:]
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w where ink[y*w+x] {
        let index = y*w+x
        var neighbors: [Int] = []
        for dy in -1...1 {
          for dx in -1...1 where dx != 0 || dy != 0 {
            let nx = x+dx, ny = y+dy
            guard nx >= 0, nx < w, ny >= 0, ny < h, ink[ny*w+nx] else { continue }
            // An available cardinal connection wins over the diagonal; this
            // avoids tiny triangular loops at otherwise smooth corners.
            if dx != 0, dy != 0, ink[y*w+nx] || ink[ny*w+x] { continue }
            neighbors.append(ny*w+nx)
          }
        }
        if !neighbors.isEmpty { links[index] = neighbors }
      }
    }
    func edgeID(_ a: Int, _ b: Int) -> UInt64 {
      (UInt64(min(a, b)) << 32) | UInt64(max(a, b))
    }
    var visited: Set<UInt64> = []
    var paths: [[CGPoint]] = []
    let starts = links.keys.sorted { a, b in
      let aJunction = links[a]?.count != 2, bJunction = links[b]?.count != 2
      return aJunction != bJunction ? aJunction : a < b
    }
    for start in starts {
      try Task.checkCancellation()
      for neighbor in links[start] ?? [] where !visited.contains(edgeID(start, neighbor)) {
        var indices = [start], previous = start, current = neighbor
        visited.insert(edgeID(previous, current))
        while true {
          if indices.count.isMultiple(of: 128) { try Task.checkCancellation() }
          indices.append(current)
          guard current != start, let nextLinks = links[current], nextLinks.count == 2,
                let next = nextLinks.first(where: { $0 != previous }),
                !visited.contains(edgeID(current, next)) else { break }
          visited.insert(edgeID(current, next))
          previous = current
          current = next
        }
        let path = indices.map { CGPoint(x: $0 % w, y: $0 / w) }
        if let cleaned = try cleanedPath(path, options: options) { paths.append(cleaned) }
      }
    }
    return paths
  }

  private static func cleanedPath(_ path: [CGPoint], options: PortraitVectorOptions) throws -> [CGPoint]? {
    guard pathLength(path) >= options.minimumContourLength else { return nil }
    let simplified = try simplify(path, tolerance: options.simplificationTolerance)
    return simplified.count >= 2 && pathLength(simplified) > 0.000_001 ? simplified : nil
  }

  private static func pathLength(_ path: [CGPoint]) -> Double {
    zip(path, path.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x-$1.0.x, $1.1.y-$1.0.y) }
  }

  /// Iterative Douglas-Peucker avoids recursive stack growth on noisy contours.
  private static func simplify(_ points: [CGPoint], tolerance: Double) throws -> [CGPoint] {
    try Task.checkCancellation()
    guard points.count > 2, tolerance > 0 else { return points }
    var retained = Set([0, points.count - 1])
    var pending = [(0, points.count - 1)]
    while let (first, last) = pending.popLast() {
      try Task.checkCancellation()
      guard last - first > 1 else { continue }
      let a = points[first], b = points[last]
      let dx = b.x-a.x, dy = b.y-a.y, squaredLength = dx*dx+dy*dy
      var farthest = first, maximum = 0.0
      for i in (first + 1)..<last {
        if i.isMultiple(of: 256) { try Task.checkCancellation() }
        let p = points[i]
        let t = squaredLength == 0 ? 0 : min(1, max(0, ((p.x-a.x)*dx+(p.y-a.y)*dy)/squaredLength))
        let distance = hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
        if distance > maximum { maximum = distance; farthest = i }
      }
      if maximum > tolerance {
        retained.insert(farthest)
        pending.append((first, farthest))
        pending.append((farthest, last))
      }
    }
    return retained.sorted().map { points[$0] }
  }
}
