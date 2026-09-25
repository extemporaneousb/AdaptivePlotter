import Foundation
import PlotterModel

/// Compact supports are evaluated in retained decoded-image coordinates, before
/// crop/resampling. Skin is a face-box estimate with measured features protected;
/// silhouette refers only to the measured jaw contour, never an invented hairline.
enum PortraitTreatmentRegion: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
  case face = "Face", eyes = "Eyes", mouth = "Mouth", skin = "Skin", silhouette = "Silhouette"
  var id: Self { self }
}

struct PortraitRegionalParameters: Codable, Hashable, Sendable {
  var revision = "portrait-regions-v1"
  var scope: PortraitTreatmentRegion = .face
  var skinSuppression = 0.65
  var featureProtection = 1.0
  var angularity = 0.0
  var shadowStrength = 0.0
  var contourEmphasis = 0.0

  var bounded: Self {
    var result = self
    result.skinSuppression = Self.amount(skinSuppression)
    result.featureProtection = Self.amount(featureProtection)
    result.angularity = Self.amount(angularity)
    result.shadowStrength = Self.amount(shadowStrength)
    result.contourEmphasis = Self.amount(contourEmphasis)
    return result
  }
  var provenance: String {
    "\(revision),\(scope.rawValue),\(skinSuppression),\(featureProtection),\(angularity),\(shadowStrength),\(contourEmphasis)"
  }
  private static func amount(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

/// This report identifies the exact analysis used, including truthful identity
/// fallback. Program provenance binds its digest; no mutable renderer state is used.
struct PortraitRegionalManifest: Codable, Hashable, Sendable {
  let revision: String
  let analysisSHA256: String?
  let geometrySHA256: String?
  let statuses: [String]
  let addedPaths: Int
  let removedPaths: Int
  let pointBudgetLimited: Bool
}

struct PortraitStrokeBurden: Sendable {
  let strokeCount: Int
  let pointCount: Int
  let pathLengthPerDrawingHeight: Double
  init(program: DrawingProgram) {
    strokeCount = program.strokes.count
    pointCount = program.strokes.reduce(0) { $0 + $1.path.points.count }
    pathLengthPerDrawingHeight = program.strokes.reduce(0) { $0 + $1.path.length } / program.fieldExtent.height
  }
  /// Geometry burden, not an uncalibrated physical drawing-time estimate.
  var summary: String {
    "\(strokeCount) strokes · \(String(format: "%.1f", pathLengthPerDrawingHeight)) drawing-heights of ink path"
  }
}

enum PortraitRegionalTreatment {
  struct Result {
    let paths: [[CGPoint]]
    let manifest: PortraitRegionalManifest?
  }

  struct Field {
    private let geometry: PortraitAnalysisGeometry
    private let face: CGRect
    private let eyes: [CGRect]
    private let mouth: CGRect
    private let nose: CGRect
    private let contour: [CGPoint]
    private let padding: Double

    init?(raster: PortraitRaster) {
      guard (try? raster.validateAnalysisEvidence()) != nil,
        let analysis = raster.faceAnalysis, analysis.status == .detected,
        let geometry = raster.analysisGeometry,
        let bounds = analysis.boundingBox,
        let confidence = analysis.observationConfidence, confidence >= 0.5,
        let landmarksConfidence = analysis.landmarksConfidence, landmarksConfidence >= 0.5,
        analysis.region(.leftEye).count >= 2, analysis.region(.rightEye).count >= 2,
        analysis.region(.outerLips).count >= 3, analysis.region(.nose).count >= 1,
        analysis.region(.faceContour).count >= 3 else { return nil }
      self.geometry = geometry
      face = CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
      padding = max(1, bounds.width * 0.065)
      func box(_ points: [PortraitLandmarkPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
      }
      eyes = [box(analysis.region(.leftEye) + analysis.region(.leftEyebrow)),
        box(analysis.region(.rightEye) + analysis.region(.rightEyebrow))]
      mouth = box(analysis.region(.outerLips))
      nose = box(analysis.region(.nose) + analysis.region(.noseCrest))
      contour = analysis.region(.faceContour).map { CGPoint(x: $0.x, y: $0.y) }
    }

    func sourcePoint(_ point: CGPoint) -> CGPoint {
      CGPoint(x: geometry.crop.x + (point.x + 0.5) * geometry.crop.width / Double(geometry.rasterWidth),
        y: geometry.crop.y + (point.y + 0.5) * geometry.crop.height / Double(geometry.rasterHeight))
    }

    func weight(_ point: CGPoint, region: PortraitTreatmentRegion) -> Double {
      let p = sourcePoint(point)
      switch region {
      case .eyes: return eyeWeight(p)
      case .mouth: return ellipse(p, box: mouth, padding: padding * 1.2)
      case .face: return ellipse(p, box: face, padding: padding * 0.8)
      case .skin:
        let protected = max(eyeWeight(p), ellipse(p, box: mouth, padding: padding * 1.2),
          ellipse(p, box: nose, padding: padding * 1.2))
        return ellipse(p, box: face, padding: padding * 0.8) * pow(1 - protected, 2)
      case .silhouette:
        var distance = Double.infinity
        for (a, b) in zip(contour, contour.dropFirst()) { distance = min(distance, Self.distance(p, a, b)) }
        return Self.falloff(distance / (padding * 2.2))
      }
    }

    private func eyeWeight(_ p: CGPoint) -> Double {
      max(ellipse(p, box: eyes[0], padding: padding * 1.5), ellipse(p, box: eyes[1], padding: padding * 1.5))
    }

    func protection(_ point: CGPoint) -> Double {
      let p = sourcePoint(point)
      // Flat cores keep eye/lip marks intact; overlapping smooth tails avoid seams.
      return max(eyeWeight(p), ellipse(p, box: mouth, padding: padding * 1.2),
        ellipse(p, box: nose, padding: padding * 1.2))
    }

    private func ellipse(_ point: CGPoint, box: CGRect, padding: Double) -> Double {
      let dx = (point.x - box.midX) / (box.width * 0.65 + padding)
      let dy = (point.y - box.midY) / (box.height * 0.65 + padding)
      return Self.falloff(hypot(dx, dy))
    }
    private static func falloff(_ radius: Double) -> Double {
      guard radius < 1 else { return 0 }
      guard radius > 0.4 else { return 1 }
      let t = (radius - 0.4) / 0.6
      return 1 - t * t * (3 - 2 * t)
    }
    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
      let dx = b.x - a.x, dy = b.y - a.y, squared = dx * dx + dy * dy
      let t = squared > 0 ? min(1, max(0, ((p.x-a.x)*dx + (p.y-a.y)*dy) / squared)) : 0
      return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }
  }

  static func summary(raster: PortraitRaster, options: PortraitVectorOptions) -> String? {
    let parameters = [options.regionalTreatment].compactMap { $0 } + (options.regionalAdjustments ?? [])
    var summaries: [String] = []
    if !parameters.isEmpty {
      if parameters.allSatisfy({ $0.revision == "portrait-regions-v1" }), Field(raster: raster) != nil {
        summaries.append("Landmark regions: " + parameters.map { $0.scope.rawValue.lowercased() }.joined(separator: ", ")
          + ". Skin uses an estimated face area; silhouette uses the observed jaw.")
      } else {
        summaries.append("Regional treatment unavailable: reliable eyes, mouth, nose, jaw or source crop missing; base strokes retained.")
      }
    }
    if let parameters = options.eyeExaggeration {
      summaries.append(PortraitEyeTransform(raster: raster, parameters: parameters).manifest.summary)
    }
    return summaries.isEmpty ? nil : summaries.joined(separator: " ")
  }

  static func apply(_ base: [[CGPoint]], raster: PortraitRaster, options: PortraitVectorOptions) throws -> Result {
    let parameters = [options.regionalTreatment].compactMap { $0 } + (options.regionalAdjustments ?? [])
    guard !parameters.isEmpty else { return Result(paths: base, manifest: nil) }
    guard (options.regionalAdjustments?.count ?? 0) <= 8 else { throw PortraitDrawingError.tooManyRegionalAdjustments }
    try Task.checkCancellation()
    let digest = try raster.faceAnalysis.map { PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode($0)) }
    let geometryDigest = try raster.analysisGeometry.map { PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode($0)) }
    let field = Field(raster: raster)
    var result = base, statuses: [String] = [], added = 0, removed = 0, limited = false
    let pointLimit = max(180_000, base.reduce(0) { $0 + $1.count })
    let minimumSpacing = try PortraitFlowRenderer.minimumSpacing(raster: raster, options: options)
    for raw in parameters {
      try Task.checkCancellation()
      guard raw.revision == "portrait-regions-v1", let field else {
        statuses.append("\(raw.scope.rawValue):unavailable; base strokes retained")
        continue
      }
      let p = raw.bounded
      let frozenClearance = p.angularity > 0 ? Occupancy(paths: result, spacing: minimumSpacing) : nil
      var changed: [[CGPoint]] = []
      for (owner, path) in result.enumerated() {
        try Task.checkCancellation()
        // No global seed/occupancy rerun. Entirely unmodified paths keep their
        // exact points; edits of crossing paths retain exterior line geometry.
        let pieces = try treated(path, field: field, raster: raster, parameters: p, clearance: frozenClearance, owner: owner)
        if pieces.isEmpty { removed += 1 }
        changed.append(contentsOf: pieces)
      }
      guard changed.reduce(0, { $0 + $1.count }) <= pointLimit else { throw PortraitDrawingError.regionalBudgetExceeded }
      guard p.contourEmphasis > 0 || p.shadowStrength > 0 else {
        statuses.append("\(p.scope.rawValue):applied"); result = changed; continue
      }
      var occupancy = Occupancy(paths: changed, spacing: minimumSpacing)
      let basePoints = changed.reduce(0) { $0 + $1.count }
      let allowance = min(20_000, max(0, 180_000 - basePoints))
      var extraPoints = 0, extraPaths = 0
      func retain(_ paths: [[CGPoint]]) {
        for path in paths where path.count >= 2 {
          if added + extraPaths >= 256 || extraPoints + path.count > allowance || changed.count >= 4_096 {
            limited = true; return
          }
          changed.append(path); extraPoints += path.count; extraPaths += 1
          occupancy.insert(path)
        }
      }
      if p.contourEmphasis > 0 {
        for path in result where path.count >= 2 {
          try Task.checkCancellation()
          for sign in [-1.0, 1.0] {
            let samples = sampled(path)
            let offset = minimumSpacing + 1.0
            var rail: [CGPoint] = []
            for index in samples.indices {
              let a = samples[max(0, index - 1)], b = samples[min(samples.count - 1, index + 1)]
              let length = hypot(b.x-a.x, b.y-a.y)
              guard length > 0 else { continue }
              let point = CGPoint(x: samples[index].x - sign * (b.y-a.y) / length * offset,
                y: samples[index].y + sign * (b.x-a.x) / length * offset)
              rail.append(point)
            }
            let pieces = clipped(rail) { point in
              inRaster(point, raster) && field.weight(point, region: p.scope) > 0.15
                && field.weight(point, region: p.scope == .eyes || p.scope == .mouth ? p.scope : .silhouette) * p.contourEmphasis > 0.12
                && !occupancy.contains(point)
            }
            retain(pieces.filter { length($0) >= max(3, minimumSpacing * 2) })
          }
        }
      }
      if p.shadowStrength > 0 {
        // Ordered parallel pen centerlines construct dark masses explicitly.
        // Material spacing remains a hard floor; new strokes yield to old ones.
        let spacing = max(minimumSpacing + 1.0, 4.5 - 2.5 * p.shadowStrength)
        for y in stride(from: 0.0, through: Double(raster.height - 1), by: spacing) {
          try Task.checkCancellation()
          let row = (0..<raster.width).map { CGPoint(x: Double($0), y: y) }
          let pieces = clipped(row) { point in
            let weight = field.weight(point, region: p.scope)
              * (1 - p.featureProtection * field.protection(point))
            return weight > 0.15 && luminance(raster, point) < (0.20 + 0.34 * p.shadowStrength * weight)
              && !occupancy.contains(point)
          }
          retain(pieces.filter { length($0) >= max(3, minimumSpacing * 2) }.map { [$0.first!, $0.last!] })
        }
      }
      added += extraPaths
      statuses.append("\(p.scope.rawValue):applied")
      result = changed
    }
    return Result(paths: result, manifest: PortraitRegionalManifest(revision: "portrait-regions-v1",
      analysisSHA256: digest, geometrySHA256: geometryDigest, statuses: statuses, addedPaths: added, removedPaths: removed, pointBudgetLimited: limited))
  }

  private static func treated(_ path: [CGPoint], field: Field, raster: PortraitRaster,
    parameters p: PortraitRegionalParameters, clearance: Occupancy?, owner: Int) throws -> [[CGPoint]] {
    guard path.count >= 2, p.skinSuppression > 0 || p.angularity > 0 else { return [path] }
    let samples = sampled(path)
    let weights = samples.map { field.weight($0, region: p.scope) }
    guard weights.contains(where: { $0 > 0.05 }) else { return [path] }
    let hasSuppression = p.skinSuppression > 0 && samples.contains { point in
      suppression(point, field: field, raster: raster, parameters: p)
    }
    var pieces = hasSuppression ? clipped(samples) { !suppression($0, field: field, raster: raster, parameters: p) } : [path]
    if p.angularity > 0 {
      pieces = pieces.map { points in
        guard points.count > 2 else { return points }
        var output = [points[0]]
        for index in 1..<(points.count - 1) {
          let previous = output.last!, current = points[index], next = points[index + 1]
          let weight = min(field.weight(previous, region: p.scope), field.weight(current, region: p.scope),
            field.weight(next, region: p.scope)) * (1 - 0.7 * p.featureProtection * field.protection(current))
          let safe = weight > 0.05 && sampled([previous, next]).allSatisfy {
            field.weight($0, region: p.scope) > 0.05 && clearance?.contains($0, excluding: owner) != true
          }
          let area = abs((next.x-previous.x)*(previous.y-current.y) - (previous.x-current.x)*(next.y-previous.y))
          let distance = area / max(0.0001, hypot(next.x-previous.x, next.y-previous.y))
          if !safe || distance > p.angularity * 2.8 * weight { output.append(current) }
        }
        output.append(points.last!)
        return output
      }
    }
    return pieces.filter { $0.count >= 2 && length($0) > 0.01 }
  }

  private static func suppression(_ point: CGPoint, field: Field, raster: PortraitRaster,
    parameters p: PortraitRegionalParameters) -> Bool {
    let weight = field.weight(point, region: p.scope) * field.weight(point, region: .skin)
      * (1 - p.featureProtection * field.protection(point))
    let gradient = abs(luminance(raster, .init(x: point.x + 1, y: point.y)) - luminance(raster, .init(x: point.x - 1, y: point.y)))
      + abs(luminance(raster, .init(x: point.x, y: point.y + 1)) - luminance(raster, .init(x: point.x, y: point.y - 1)))
    return p.skinSuppression * weight > 0.30 + min(0.65, gradient * 2)
  }

  private static func luminance(_ raster: PortraitRaster, _ point: CGPoint) -> Double {
    let x = min(raster.width - 1, max(0, Int(point.x.rounded())))
    let y = min(raster.height - 1, max(0, Int(point.y.rounded())))
    return raster.luminance[y * raster.width + x]
  }
  private static func inRaster(_ point: CGPoint, _ raster: PortraitRaster) -> Bool {
    point.x >= 0 && point.x <= Double(raster.width - 1) && point.y >= 0 && point.y <= Double(raster.height - 1)
  }
  private static func length(_ path: [CGPoint]) -> Double {
    zip(path, path.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
  }
  private static func sampled(_ path: [CGPoint]) -> [CGPoint] {
    guard let first = path.first else { return [] }
    var result = [first]
    for (a, b) in zip(path, path.dropFirst()) {
      let steps = max(1, Int(ceil(hypot(b.x-a.x, b.y-a.y) / 0.75)))
      for step in 1...steps {
        let t = Double(step) / Double(steps)
        result.append(CGPoint(x: a.x + (b.x-a.x)*t, y: a.y + (b.y-a.y)*t))
      }
    }
    return result
  }
  private static func clipped(_ path: [CGPoint], keeping: (CGPoint) -> Bool) -> [[CGPoint]] {
    var result: [[CGPoint]] = [], run: [CGPoint] = []
    for point in path {
      if keeping(point) { run.append(point) }
      else { if run.count >= 2 { result.append(compactCollinear(run)) }; run = [] }
    }
    if run.count >= 2 { result.append(compactCollinear(run)) }
    return result
  }

  private static func compactCollinear(_ path: [CGPoint]) -> [CGPoint] {
    guard path.count > 2 else { return path }
    var result = [path[0]]
    for i in 1..<(path.count - 1) {
      let a = result.last!, b = path[i], c = path[i + 1]
      let cross = abs((b.x-a.x)*(c.y-b.y) - (b.y-a.y)*(c.x-b.x))
      let forward = (b.x-a.x)*(c.x-b.x) + (b.y-a.y)*(c.y-b.y)
      if cross > 1e-10 || forward < 0 { result.append(b) }
    }
    result.append(path.last!)
    return result
  }

  /// Conservative sampled clearance: half a sampling step is added to the
  /// material floor, so gaps between occupancy samples cannot admit crowding.
  private struct Occupancy {
    let spacing: Double
    var cells: [Cell: [OwnedPoint]] = [:]
    struct Cell: Hashable { let x: Int; let y: Int }
    struct OwnedPoint { let point: CGPoint; let owner: Int }
    init(paths: [[CGPoint]], spacing: Double) {
      self.spacing = spacing + 0.5
      for (owner, path) in paths.enumerated() { insert(path, owner: owner) }
    }
    mutating func insert(_ path: [CGPoint], owner: Int = -1) {
      for point in sampled(path) {
        cells[key(Int(floor(point.x/spacing)), Int(floor(point.y/spacing))), default: []].append(OwnedPoint(point: point, owner: owner))
      }
    }
    func contains(_ point: CGPoint, excluding owner: Int? = nil) -> Bool {
      let x = Int(floor(point.x/spacing)), y = Int(floor(point.y/spacing))
      for dy in -1...1 { for dx in -1...1 {
        if cells[key(x+dx, y+dy), default: []].contains(where: {
          $0.owner != owner && hypot(point.x-$0.point.x, point.y-$0.point.y) < spacing
        }) { return true }
      } }
      return false
    }
    private func key(_ x: Int, _ y: Int) -> Cell { Cell(x: x, y: y) }
  }
}

/// A separate 2D capability: measured eye proportions only, without a claimed
/// 3D pose, inferred forehead, or any relaxation of archived semantic-head rules.
struct PortraitEyeExaggerationParameters: Codable, Hashable, Sendable {
  var revision = "portrait-eye-scale-v1"
  var amount = 0.3
  var bounded: Self {
    var result = self
    result.amount = amount.isFinite ? min(0.3, max(0, amount)) : 0
    return result
  }
}

struct PortraitEyeExaggerationManifest: Codable, Hashable, Sendable {
  struct Support: Codable, Hashable, Sendable {
    let measuredCenter: PortraitLandmarkPoint
    let radiusDecodedPixels: Double
  }
  let revision: String
  let applied: Bool
  let summary: String
  let analysisSHA256: String?
  let geometrySHA256: String?
  let amount: Double
  let supports: [Support]
  let minimumJacobianDeterminant: Double
  let maximumDisplacementDecodedPixels: Double
}

struct PortraitEyeTransform {
  let manifest: PortraitEyeExaggerationManifest
  private let geometry: PortraitAnalysisGeometry?

  init(raster: PortraitRaster, parameters: PortraitEyeExaggerationParameters) {
    geometry = raster.analysisGeometry
    let amount = parameters.bounded.amount
    let analysisDigest = raster.faceAnalysis.flatMap { try? PortraitCandidateCoding.encoder().encode($0) }
      .map(PortraitCandidateCoding.digest)
    let geometryDigest = geometry.flatMap { try? PortraitCandidateCoding.encoder().encode($0) }
      .map(PortraitCandidateCoding.digest)
    func unavailable(_ reason: String) -> PortraitEyeExaggerationManifest {
      .init(revision: "portrait-eye-scale-v1", applied: false,
        summary: "Measured eye exaggeration unavailable: \(reason); base strokes retained.",
        analysisSHA256: analysisDigest, geometrySHA256: geometryDigest, amount: amount,
        supports: [], minimumJacobianDeterminant: 1, maximumDisplacementDecodedPixels: 0)
    }
    guard parameters.revision == "portrait-eye-scale-v1" else {
      manifest = unavailable("unsupported modifier revision"); return
    }
    guard (try? raster.validateAnalysisEvidence()) != nil, let geometry,
      let analysis = raster.faceAnalysis, analysis.status == .detected,
      let confidence = analysis.observationConfidence, confidence >= 0.5,
      let landmarkConfidence = analysis.landmarksConfidence, landmarkConfidence >= 0.5,
      analysis.region(.leftEye).count >= 2, analysis.region(.rightEye).count >= 2 else {
      manifest = unavailable("reliable bilateral eye landmarks or source crop missing"); return
    }
    func mean(_ points: [PortraitLandmarkPoint]) -> PortraitLandmarkPoint {
      .init(x: points.reduce(0) { $0 + $1.x } / Double(points.count),
        y: points.reduce(0) { $0 + $1.y } / Double(points.count))
    }
    let centers = [mean(analysis.region(.leftEye)), mean(analysis.region(.rightEye))]
    let distance = hypot(centers[1].x-centers[0].x, centers[1].y-centers[0].y)
    guard distance.isFinite, distance > 1e-6 else {
      manifest = unavailable("coincident eye centers"); return
    }
    var supports: [PortraitEyeExaggerationManifest.Support] = []
    for center in centers {
      let edgeDistance = min(center.x-geometry.crop.x, center.y-geometry.crop.y,
        geometry.crop.x+geometry.crop.width-center.x, geometry.crop.y+geometry.crop.height-center.y)
      let radius = min(distance * 0.42, edgeDistance * 0.98)
      guard radius >= distance * 0.20 else {
        manifest = unavailable("eye support cut by the selected crop"); return
      }
      supports.append(.init(measuredCenter: center, radiusDecodedPixels: radius))
    }
    // For u=r² and g=(1-u)^3 the radial Jacobian eigenvalue is
    // 1+a(1-u)^2(1-7u) >= 1-32a/49, while the tangent eigenvalue
    // is >=1. Supports have radius <=0.42 eye separations and cannot overlap.
    manifest = .init(revision: "portrait-eye-scale-v1", applied: amount > 0,
      summary: amount > 0
        ? "Measured eye exaggeration: up to \(Int((amount * 100).rounded()))% local 2D expansion; no 3D pose or forehead inference."
        : "Measured eye exaggeration: zero amount; base strokes retained.",
      analysisSHA256: analysisDigest, geometrySHA256: geometryDigest, amount: amount, supports: supports,
      minimumJacobianDeterminant: 1 - 32 * amount / 49,
      maximumDisplacementDecodedPixels: amount * (supports.map(\.radiusDecodedPixels).max() ?? 0) * 0.24)
  }

  func point(_ point: CGPoint) -> CGPoint {
    guard manifest.applied, let geometry else { return point }
    let source = CGPoint(x: geometry.crop.x + (point.x+0.5) * geometry.crop.width / Double(geometry.rasterWidth),
      y: geometry.crop.y + (point.y+0.5) * geometry.crop.height / Double(geometry.rasterHeight))
    for support in manifest.supports {
      let dx = source.x-support.measuredCenter.x, dy = source.y-support.measuredCenter.y
      let squaredRadius = (dx*dx+dy*dy) / (support.radiusDecodedPixels * support.radiusDecodedPixels)
      guard squaredRadius < 1 else { continue }
      let gain = 1 + manifest.amount * pow(1-squaredRadius, 3)
      return CGPoint(x: (support.measuredCenter.x+dx*gain-geometry.crop.x) / geometry.crop.width * Double(geometry.rasterWidth)-0.5,
        y: (support.measuredCenter.y+dy*gain-geometry.crop.y) / geometry.crop.height * Double(geometry.rasterHeight)-0.5)
    }
    return point // Exact exterior identity, without a numerical round trip.
  }

  func paths(_ paths: [[CGPoint]]) throws -> [[CGPoint]] {
    guard manifest.applied, let geometry else { return paths }
    var result: [[CGPoint]] = [], points = 0
    let limit = max(180_000, paths.reduce(0) { $0 + $1.count })
    for path in paths {
      try Task.checkCancellation()
      guard let first = path.first else { continue }
      func decoded(_ p: CGPoint) -> CGPoint {
        .init(x: geometry.crop.x+(p.x+0.5)*geometry.crop.width/Double(geometry.rasterWidth),
          y: geometry.crop.y+(p.y+0.5)*geometry.crop.height/Double(geometry.rasterHeight))
      }
      let intersects = zip(path, path.dropFirst()).contains { a, b in
        let a = decoded(a), b = decoded(b), dx = b.x-a.x, dy = b.y-a.y
        let squared = dx*dx+dy*dy
        return manifest.supports.contains { support in
          let p = support.measuredCenter
          let t = squared > 0 ? min(1, max(0, ((p.x-a.x)*dx+(p.y-a.y)*dy)/squared)) : 0
          return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy) < support.radiusDecodedPixels
        }
      }
      if !intersects {
        points += path.count
        guard points <= limit else { throw PortraitDrawingError.regionalBudgetExceeded }
        result.append(path); continue
      }
      var samples = [first]
      for (a, b) in zip(path, path.dropFirst()) {
        try Task.checkCancellation()
        let distance = hypot(b.x-a.x, b.y-a.y)
        guard distance.isFinite, distance <= Double(limit) else { throw PortraitDrawingError.regionalBudgetExceeded }
        let steps = max(1, Int(ceil(distance)))
        guard points + samples.count + steps <= limit else { throw PortraitDrawingError.regionalBudgetExceeded }
        for step in 1...steps {
          if step.isMultiple(of: 64) { try Task.checkCancellation() }
          let t = Double(step) / Double(steps)
          samples.append(.init(x: a.x+(b.x-a.x)*t, y: a.y+(b.y-a.y)*t))
        }
      }
      let warped = samples.map(point)
      let selected = warped == samples ? path : warped
      points += selected.count
      guard points <= limit else { throw PortraitDrawingError.regionalBudgetExceeded }
      result.append(selected)
    }
    return result
  }
}
