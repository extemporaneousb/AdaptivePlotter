import CryptoKit
import Foundation
import PlotterModel

enum PortraitPose: String, CaseIterable, Identifiable, Sendable {
  case left = "Left", front = "Front", right = "Right"
  var id: Self { self }
}

enum PortraitStyle: String, CaseIterable, Identifiable, Sendable {
  case contours = "Contour", hatch = "Hatch", crosshatch = "Crosshatch"
  var id: Self { self }
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
  case unreadableImage, noLines
  var errorDescription: String? {
    switch self {
    case .unreadableImage: "The image could not be decoded."
    case .noLines: "This style produced no lines. Try another style or turn off background removal."
    }
  }
}

enum PortraitVectorizer {
  static func program(
    from raster: PortraitRaster, pose: PortraitPose, style: PortraitStyle,
    levels: Int = 6, strokeStyle: StrokeStyle
  ) throws -> DrawingProgram {
    let paths: [[CGPoint]]
    switch style {
    case .contours: paths = contours(raster, levels: levels)
    case .hatch: paths = hatching(raster, crosshatch: false)
    case .crosshatch: paths = hatching(raster, crosshatch: true)
    }
    guard !paths.isEmpty else { throw PortraitDrawingError.noLines }
    let provenance = "portrait-v1|\(raster.provenance)|pose=\(pose.rawValue)|style=\(style.rawValue)|levels=\(levels)"
    let extent = try Size2<FieldSpace>(
      width: 100 * Double(raster.width - 1) / Double(raster.height - 1), height: 100)
    let strokes = try paths.enumerated().map { index, path in
      LogicalStroke(
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
  private static func contours(_ raster: PortraitRaster, levels: Int) -> [[CGPoint]] {
    let w = raster.width, h = raster.height
    var paths: [[CGPoint]] = []
    for levelIndex in 1...max(1, levels) {
      let level = Double(levelIndex) / Double(max(1, levels) + 1)
      var points: [Int: CGPoint] = [:]
      var links: [Int: [Int]] = [:]
      for y in 0..<(h - 1) {
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
        let length = zip(path, path.dropFirst()).reduce(0.0) { $0 + hypot($1.1.x-$1.0.x, $1.1.y-$1.0.y) }
        if length >= 3 { paths.append(simplify(path, tolerance: 0.35)) }
      }
    }
    return paths
  }

  /// Continuous tonal scanlines reduce pen lifts compared with the legacy
  /// per-cell hatch marks. A darker orthogonal pass supplies crosshatching.
  private static func hatching(_ raster: PortraitRaster, crosshatch: Bool) -> [[CGPoint]] {
    var paths: [[CGPoint]] = []
    for vertical in crosshatch ? [false, true] : [false] {
      let rows = vertical ? raster.width : raster.height
      let columns = vertical ? raster.height : raster.width
      for row in stride(from: 1, to: rows - 1, by: 2) {
        let threshold = vertical ? 0.30 : [0.35, 0.55, 0.75][(row / 2) % 3]
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
              if (row / 2).isMultiple(of: 2) { line.reverse() }
              paths.append(line)
            }
            start = nil
          }
        }
      }
    }
    return paths
  }

  private static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
    guard points.count > 2, let a = points.first, let b = points.last else { return points }
    let dx = b.x-a.x, dy = b.y-a.y, squaredLength = dx*dx+dy*dy
    var farthest = 0, maximum = 0.0
    for i in 1..<(points.count - 1) {
      let p = points[i]
      let t = squaredLength == 0 ? 0 : min(1, max(0, ((p.x-a.x)*dx+(p.y-a.y)*dy)/squaredLength))
      let distance = hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
      if distance > maximum { maximum = distance; farthest = i }
    }
    guard maximum > tolerance else { return [a, b] }
    return Array(simplify(Array(points[...farthest]), tolerance: tolerance).dropLast())
      + simplify(Array(points[farthest...]), tolerance: tolerance)
  }
}
