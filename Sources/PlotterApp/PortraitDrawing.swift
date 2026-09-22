import CryptoKit
import Foundation
import PlotterModel

enum PortraitPose: String, CaseIterable, Identifiable, Codable, Sendable {
  case left = "Left", front = "Front", right = "Right"
  var id: Self { self }
}

enum PortraitStyle: String, CaseIterable, Identifiable, Codable, Sendable {
  case flowEdges = "Flow Edge"
  case contours = "Contour", hatch = "Hatch", crosshatch = "Crosshatch"
  case sketch = "Sketch", sketchHatch = "Sketch + hatch"
  var id: Self { self }
}

/// Spatial values refer to analyzed-raster pixels, independently of paper
/// placement. They alter authored geometry only, never plotting authority.
struct PortraitVectorOptions: Codable, Hashable, Sendable {
  var contourLevels = 6
  var minimumContourLength = 3.0
  var simplificationTolerance = 0.35
  var hatchSpacing = 2
  var tonalStrength = 1.0
  var smoothing = 0.0
  var sketchThreshold = 0.012
  var hatchAngleDegrees = 0.0
  var headScale = 1.0
  var semanticHead: PortraitSemanticHeadParameters? = nil
  var materialContext: PortraitMaterialContext? = nil

  var bounded: Self {
    var result = self
    result.contourLevels = min(12, max(1, contourLevels))
    result.minimumContourLength = Self.clamp(minimumContourLength, to: 0...40, fallback: 3)
    result.simplificationTolerance = Self.clamp(simplificationTolerance, to: 0...3, fallback: 0.35)
    result.hatchSpacing = min(16, max(1, hatchSpacing))
    result.tonalStrength = Self.clamp(tonalStrength, to: 0.4...2, fallback: 1)
    result.smoothing = Self.clamp(smoothing, to: 0...4, fallback: 0)
    result.sketchThreshold = Self.clamp(sketchThreshold, to: 0.002...0.08, fallback: 0.012)
    result.hatchAngleDegrees = Self.clamp(hatchAngleDegrees, to: -90...90, fallback: 0)
    result.headScale = Self.clamp(headScale, to: 1...1.6, fallback: 1)
    result.semanticHead = semanticHead?.bounded
    return result
  }

  var provenance: String {
    let original = "levels=\(contourLevels)|minLength=\(minimumContourLength)|simplify=\(simplificationTolerance)"
      + "|hatchSpacing=\(hatchSpacing)|tone=\(tonalStrength)|smooth=\(smoothing)|sketchThreshold=\(sketchThreshold)"
    // Preserve source identity for the previous default geometry.
    let legacy = hatchAngleDegrees == 0 && headScale == 1 ? original
      : original + "|hatchAngle=\(hatchAngleDegrees)|headScale=\(headScale)"
    let head = semanticHead.map { "|semanticHead=\($0.revision),\($0.foreheadWidth),\($0.foreheadHeight),\($0.eyeScale),\($0.lateralScale)" } ?? ""
    return legacy + head + (materialContext.map { "|" + $0.provenance } ?? "")
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

/// The crop metric in oriented original-image pixels, before thumbnail/raster
/// sampling. Thumbnail crops can span fractional original pixels. This is image
/// geometry, not a physical measurement or a FieldSpace distance.
struct PortraitSourceCropExtent: Codable, Hashable, Sendable {
  let widthPixels: Double
  let heightPixels: Double

  init(widthPixels: Double, heightPixels: Double) throws {
    let ratio = widthPixels / heightPixels
    guard widthPixels.isFinite, heightPixels.isFinite, widthPixels > 0, heightPixels > 0,
      ratio.isFinite, ratio > 0, (100 * ratio).isFinite else { throw PortraitDrawingError.unreadableImage }
    self.widthPixels = widthPixels
    self.heightPixels = heightPixels
  }

  var aspectRatio: Double { widthPixels / heightPixels }

  private enum CodingKeys: String, CodingKey { case widthPixels, heightPixels }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(widthPixels: values.decode(Double.self, forKey: .widthPixels),
      heightPixels: values.decode(Double.self, forKey: .heightPixels))
  }
}

/// A bounded, top-left-origin brightness image. Image analysis owns cropping
/// and background removal; the vectorizer knows nothing about cameras or motion.
struct PortraitRaster: Codable, Sendable {
  static let schemaVersion = 3
  private var encodedSchemaVersion: Int? = Self.schemaVersion
  let width: Int
  let height: Int
  let luminance: [Double]
  let provenance: String
  let analysisSummary: String
  /// Measured face bounds in the cropped raster, normalized with +Y down.
  var faceBounds: CGRect?
  /// Absent only for legacy or synthetic rasters whose original crop is unknown.
  let sourceCropExtent: PortraitSourceCropExtent?
  /// Nil identifies legacy/synthetic analysis whose exact preprocessing is unavailable.
  let analysisGeometry: PortraitAnalysisGeometry?
  let personMask: PortraitPersonMask?
  let faceAnalysis: PortraitFaceAnalysis?

  init(width: Int, height: Int, luminance: [Double], provenance: String,
    analysisSummary: String, faceBounds: CGRect? = nil,
    sourceCropExtent: PortraitSourceCropExtent? = nil,
    analysisGeometry: PortraitAnalysisGeometry? = nil, personMask: PortraitPersonMask? = nil,
    faceAnalysis: PortraitFaceAnalysis? = nil) {
    self.width = width
    self.height = height
    self.luminance = luminance
    self.provenance = provenance
    self.analysisSummary = analysisSummary
    self.faceBounds = faceBounds
    self.sourceCropExtent = sourceCropExtent
    self.analysisGeometry = analysisGeometry
    self.personMask = personMask
    self.faceAnalysis = faceAnalysis
  }

  var metricProvenance: String {
    if let sourceCropExtent {
      return "source-crop-pixels-v1=\(sourceCropExtent.widthPixels)x\(sourceCropExtent.heightPixels)|sampling=pixel-centers-v1"
    }
    return "legacy-sample-lattice-v1=\(width - 1)x\(height - 1)"
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, width, height, luminance, provenance, analysisSummary, faceBounds, sourceCropExtent
    case analysisGeometry, personMask, faceAnalysis
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
    guard (0...Self.schemaVersion).contains(version) else {
      throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values,
        debugDescription: "Unsupported portrait raster schema version")
    }
    self.init(width: try values.decode(Int.self, forKey: .width),
      height: try values.decode(Int.self, forKey: .height),
      luminance: try values.decode([Double].self, forKey: .luminance),
      provenance: try values.decode(String.self, forKey: .provenance),
      analysisSummary: try values.decode(String.self, forKey: .analysisSummary),
      faceBounds: try values.decodeIfPresent(CGRect.self, forKey: .faceBounds),
      sourceCropExtent: try values.decodeIfPresent(PortraitSourceCropExtent.self, forKey: .sourceCropExtent),
      analysisGeometry: try values.decodeIfPresent(PortraitAnalysisGeometry.self, forKey: .analysisGeometry),
      personMask: try values.decodeIfPresent(PortraitPersonMask.self, forKey: .personMask),
      faceAnalysis: try values.decodeIfPresent(PortraitFaceAnalysis.self, forKey: .faceAnalysis))
    encodedSchemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion)
    guard faceAnalysis == nil || version >= 3 else { throw PortraitDrawingError.unreadableImage }
    try validateAnalysisEvidence()
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encodeIfPresent(encodedSchemaVersion, forKey: .schemaVersion)
    try values.encode(width, forKey: .width)
    try values.encode(height, forKey: .height)
    try values.encode(luminance, forKey: .luminance)
    try values.encode(provenance, forKey: .provenance)
    try values.encode(analysisSummary, forKey: .analysisSummary)
    try values.encodeIfPresent(faceBounds, forKey: .faceBounds)
    try values.encodeIfPresent(sourceCropExtent, forKey: .sourceCropExtent)
    try values.encodeIfPresent(analysisGeometry, forKey: .analysisGeometry)
    try values.encodeIfPresent(personMask, forKey: .personMask)
    try values.encodeIfPresent(faceAnalysis, forKey: .faceAnalysis)
  }

  func validateAnalysisEvidence() throws {
    guard width >= 2, height >= 2, width <= 512, height <= 512,
      luminance.count == width * height, luminance.allSatisfy(\.isFinite)
    else { throw PortraitDrawingError.unreadableImage }
    try analysisGeometry?.validate(width: width, height: height)
    try personMask?.validate(width: width, height: height)
    try faceAnalysis?.validate()
    if let faceAnalysis, let analysisGeometry {
      guard faceAnalysis.decodedWidth == analysisGeometry.decodedWidth,
        faceAnalysis.decodedHeight == analysisGeometry.decodedHeight else { throw PortraitDrawingError.unreadableImage }
    }
    if let geometry = analysisGeometry {
      let expected = try PortraitSourceCropExtent(
        widthPixels: geometry.sourcePixelExtent.widthPixels * (geometry.crop.width / Double(geometry.decodedWidth)),
        heightPixels: geometry.sourcePixelExtent.heightPixels * (geometry.crop.height / Double(geometry.decodedHeight)))
      guard let sourceCropExtent,
        abs(expected.widthPixels / sourceCropExtent.widthPixels - 1) < 1e-12,
        abs(expected.heightPixels / sourceCropExtent.heightPixels - 1) < 1e-12
      else { throw PortraitDrawingError.unreadableImage }
    }
  }
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
    var options = configuration.bounded
    if let material = options.materialContext { options = try material.adapting(options, raster: raster) }
    // Flow keeps structural evidence independent of its tone/coherence controls.
    // Legacy styles retain their exact preprocessing and archived identities.
    let prepared = style == .flowEdges ? raster : try preparedRaster(raster, options: options)
    let authoredPaths: [[CGPoint]]
    switch style {
    case .flowEdges: authoredPaths = try PortraitFlowRenderer.paths(from: raster, options: options)
    case .contours: authoredPaths = try contours(prepared, options: options)
    case .hatch: authoredPaths = try hatching(prepared, crosshatch: false, options: options)
    case .crosshatch: authoredPaths = try hatching(prepared, crosshatch: true, options: options)
    case .sketch: authoredPaths = try sketch(prepared, options: options)
    case .sketchHatch:
      authoredPaths = try sketch(prepared, options: options)
        + hatching(prepared, crosshatch: false, options: options)
    }
    let paths = try enlargedHeadPaths(authoredPaths, raster: raster, options: options)
    guard !paths.isEmpty else { throw PortraitDrawingError.noLines }
    let producer = options.semanticHead == nil ? "portrait-v3" : "portrait-v4"
    var provenance = "\(producer)|metric=\(raster.metricProvenance)|\(raster.provenance)|pose=\(pose.rawValue)|style=\(style.rawValue)|\(options.provenance)"
    if style == .flowEdges { provenance += "|flow=\(PortraitFlowRenderer.revision)" }
    if let parameters = options.semanticHead {
      let manifest = PortraitHeadTransform(raster: raster, parameters: parameters).manifest
      provenance += "|headWarp=" + PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(manifest))
    } else if options.headScale > 1 {
      if let bounds = PortraitHeadTransform.validFaceBounds(raster.faceBounds) {
        provenance += "|headTransform=v1|headFace=\(bounds.origin.x),\(bounds.origin.y),\(bounds.width),\(bounds.height)"
      } else { provenance += "|headTransform=unavailable" }
    }
    let extent = try Size2<FieldSpace>(
      width: 100 * (raster.sourceCropExtent?.aspectRatio
        ?? (Double(raster.width - 1) / Double(raster.height - 1))), height: 100)
    let strokes = try paths.enumerated().map { index, path in
      try Task.checkCancellation()
      return LogicalStroke(
        id: StrokeID(stableID("\(provenance)|stroke=\(index)")),
        path: try Polyline(points: path.map { point in
          // CGContext samples are pixel centers inside the source crop. Using
          // width-1/height-1 would stretch the two sample axes independently.
          // Preserve the previous lattice convention only for unknown legacy crops.
          let sourceMetric = raster.sourceCropExtent != nil
          let x = sourceMetric ? (Double(point.x) + 0.5) / Double(raster.width)
            : Double(point.x) / Double(raster.width - 1)
          let y = sourceMetric ? (Double(point.y) + 0.5) / Double(raster.height)
            : Double(point.y) / Double(raster.height - 1)
          return try Point2<FieldSpace>(x: x * extent.width, y: (1 - y) * extent.height)
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
  private static func hatching(_ raster: PortraitRaster, crosshatch: Bool, options: PortraitVectorOptions) throws -> [[CGPoint]] {
    if options.hatchAngleDegrees != 0 {
      return try angledHatching(raster, crosshatch: crosshatch, options: options)
    }
    let spacing = options.hatchSpacing
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

  /// Clip each rotated scanline to the image before sampling it. The original
  /// zero-degree route remains exact; this route adds arbitrary pen direction.
  private static func angledHatching(_ raster: PortraitRaster, crosshatch: Bool,
                                    options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let width = Double(raster.width - 1), height = Double(raster.height - 1)
    let corners = [CGPoint.zero, CGPoint(x: width, y: 0), CGPoint(x: 0, y: height),
                   CGPoint(x: width, y: height)]
    var paths: [[CGPoint]] = []
    for pass in 0..<(crosshatch ? 2 : 1) {
      let angle = (options.hatchAngleDegrees + Double(pass) * 90) * .pi / 180
      let dx = cos(angle), dy = sin(angle), nx = -dy, ny = dx
      let offsets = corners.map { $0.x * nx + $0.y * ny }
      let lower = offsets.min()!, upper = offsets.max()!
      let first = Int(ceil(lower / Double(options.hatchSpacing)))
      let last = Int(floor(upper / Double(options.hatchSpacing)))
      guard first <= last else { continue }
      for (rowIndex, row) in (first...last).enumerated() {
        try Task.checkCancellation()
        let offset = Double(row * options.hatchSpacing)
        let origin = CGPoint(x: nx * offset, y: ny * offset)
        var from = -Double.infinity, through = Double.infinity
        for (position, direction, limit) in [(origin.x, dx, width), (origin.y, dy, height)] {
          if abs(direction) < 1e-10 {
            if position < -1e-8 || position > limit + 1e-8 { from = 1; through = 0; break }
          } else {
            let a = -position / direction, b = (limit - position) / direction
            from = max(from, min(a, b)); through = min(through, max(a, b))
          }
        }
        guard through > from else { continue }
        let steps = max(1, Int(ceil(through - from)))
        let threshold = pass == 1 ? 0.30 : [0.35, 0.55, 0.75][rowIndex % 3]
        var start: CGPoint?, lastDark: CGPoint?
        for sample in 0...(steps + 1) {
          let t = from + Double(min(sample, steps)) / Double(steps) * (through - from)
          let point = CGPoint(x: min(width, max(0, origin.x + dx * t)),
                              y: min(height, max(0, origin.y + dy * t)))
          let dark = sample <= steps && luminance(raster, at: point) < threshold
          if dark {
            if start == nil { start = point }
            lastDark = point
          } else if let firstPoint = start, let lastPoint = lastDark {
            if hypot(firstPoint.x - lastPoint.x, firstPoint.y - lastPoint.y) > 0.5 {
              paths.append(rowIndex.isMultiple(of: 2) ? [lastPoint, firstPoint] : [firstPoint, lastPoint])
            }
            start = nil; lastDark = nil
          }
        }
      }
    }
    return paths
  }

  private static func luminance(_ raster: PortraitRaster, at point: CGPoint) -> Double {
    let x = min(raster.width - 1, max(0, Int(point.x))), y = min(raster.height - 1, max(0, Int(point.y)))
    let x1 = min(raster.width - 1, x + 1), y1 = min(raster.height - 1, y + 1)
    let fx = point.x - Double(x), fy = point.y - Double(y)
    let upper = raster.luminance[y*raster.width+x] * (1-fx) + raster.luminance[y*raster.width+x1] * fx
    let lower = raster.luminance[y1*raster.width+x] * (1-fx) + raster.luminance[y1*raster.width+x1] * fx
    return upper * (1-fy) + lower * fy
  }

  private static func enlargedHeadPaths(_ paths: [[CGPoint]], raster: PortraitRaster,
                                        options: PortraitVectorOptions) throws -> [[CGPoint]] {
    let transform: PortraitHeadTransform
    if let parameters = options.semanticHead {
      transform = PortraitHeadTransform(raster: raster, parameters: parameters)
      guard transform.manifest.status == .applied || transform.manifest.status == .limited else { return paths }
    } else {
      guard options.headScale > 1,
        let legacy = PortraitHeadTransform(faceBounds: raster.faceBounds, width: raster.width,
          height: raster.height, scale: options.headScale) else { return paths }
      transform = legacy
    }
    return try paths.compactMap { path in
      try Task.checkCancellation()
      guard let first = path.first else { return path }
      var warped = [transform.point(first)]
      for (a, b) in zip(path, path.dropFirst()) {
        // Long hatches need interior samples to follow the nonlinear warp.
        let steps = max(1, Int(ceil(hypot(b.x-a.x, b.y-a.y) / 2)))
        for step in 1...steps {
          if step.isMultiple(of: 64) { try Task.checkCancellation() }
          let t = Double(step) / Double(steps)
          warped.append(transform.point(CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t)))
        }
      }
      let simplified = try simplify(warped, tolerance: options.simplificationTolerance)
      return pathLength(simplified) > 0.000_001 ? simplified : nil
    }
  }

  private static func preparedRaster(_ raster: PortraitRaster, options: PortraitVectorOptions) throws -> PortraitRaster {
    let smooth = try gaussian(raster.luminance, width: raster.width, height: raster.height,
                              sigma: options.smoothing)
    let values = smooth.map { pow(min(1, max(0, $0)), options.tonalStrength) }
    return PortraitRaster(width: raster.width, height: raster.height, luminance: values,
      provenance: raster.provenance, analysisSummary: raster.analysisSummary, faceBounds: raster.faceBounds,
      sourceCropExtent: raster.sourceCropExtent, analysisGeometry: raster.analysisGeometry,
      personMask: raster.personMask, faceAnalysis: raster.faceAnalysis)
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
