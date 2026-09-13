import CoreGraphics
import Foundation

/// Versioned semantic landmark warp with an isolated legacy face-bounds path.
/// The new path composes compact source-metric fields with analytic derivative
/// bounds; the legacy initializer preserves archived v1 rendering behavior.
struct PortraitHeadTransform {
  let manifest: PortraitHeadWarpManifest
  private var semantic = false
  private let center: CGPoint
  private let radius: CGSize
  private let width: Double
  private let height: Double
  private let amount: Double

  init?(faceBounds: CGRect?, width: Int, height: Int, scale: Double) {
    guard width >= 2, height >= 2, scale.isFinite,
      let face = Self.validFaceBounds(faceBounds) else { return nil }
    manifest = Self.identityManifest(parameters: .init(), status: .legacy, reason: "Archived face-bounds transform v1")
    self.width = Double(width-1)
    self.height = Double(height-1)
    center = CGPoint(x: face.midX * Double(width-1), y: face.midY * Double(height-1))
    radius = CGSize(width: face.width * Double(width-1) * 1.8,
                    height: face.height * Double(height-1) * 1.6)
    amount = min(1.6, max(1, scale)) - 1
  }

  static func validFaceBounds(_ value: CGRect?) -> CGRect? {
    guard let value, [value.minX, value.minY, value.width, value.height].allSatisfy(\.isFinite),
      value.width > 0, value.height > 0 else { return nil }
    let clipped = value.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    guard !clipped.isNull, clipped.width > 0, clipped.height > 0,
      clipped.midX > 0, clipped.midX < 1, clipped.midY > 0, clipped.midY < 1 else { return nil }
    return clipped
  }

  func point(_ point: CGPoint) -> CGPoint {
    if semantic { return semanticPoint(point) }
    guard amount > 0 else { return point }
    let xStrength = 1 + amount * falloff(point.y, center: center.y, radius: radius.height, limit: height)
    let x = mapped(point.x, center: center.x, radius: radius.width, limit: width, strength: xStrength)
    let yStrength = 1 + amount * falloff(x, center: center.x, radius: radius.width, limit: width)
    let y = mapped(point.y, center: center.y, radius: radius.height, limit: height, strength: yStrength)
    return CGPoint(x: x, y: y)
  }

  /// For t in [0, 1], t + a*t*(1-t)^2 has derivative at least 1-a/3.
  /// With a <= 0.6 this stays positive, matches identity at the support edge
  /// with derivative 1, and has the requested local scale at the face center.
  private func mapped(_ value: Double, center: Double, radius: Double, limit: Double, strength: Double) -> Double {
    let delta = value-center
    let reach = min(radius, delta < 0 ? center : limit-center)
    guard reach > 0, abs(delta) < reach else { return value }
    let t = abs(delta)/reach
    let mapped = (t + (strength-1)*t*(1-t)*(1-t))*reach
    return min(limit, max(0, center + (delta < 0 ? -mapped : mapped)))
  }

  private func falloff(_ value: Double, center: Double, radius: Double, limit: Double) -> Double {
    let reach = min(radius, value < center ? center : limit-center)
    guard reach > 0 else { return 0 }
    let t = abs(value-center)/reach
    guard t < 1 else { return 0 }
    let value = 1-t*t
    return value*value
  }
}

extension PortraitHeadTransform {
  init(raster: PortraitRaster, parameters: PortraitSemanticHeadParameters) {
    manifest = Self.semanticManifest(raster: raster, parameters: parameters)
    semantic = true
    center = .zero; radius = .zero; width = 0; height = 0; amount = 0
  }

  private static var zeroParameters: PortraitSemanticHeadParameters {
    .init(foreheadWidth: 0, foreheadHeight: 0, eyeScale: 0, lateralScale: 0)
  }

  private static func identityManifest(parameters: PortraitSemanticHeadParameters,
    status: PortraitHeadWarpManifest.Status = .unavailable, reason: String,
    digest: String? = nil) -> PortraitHeadWarpManifest {
    PortraitHeadWarpManifest(status: status, summary: reason, analysisSHA256: digest,
      basis: nil, anchors: [], requested: parameters.bounded, effective: zeroParameters,
      kernels: [], minimumJacobianDeterminant: 1, maximumDisplacementSourcePixels: 0)
  }

  private static func semanticManifest(raster: PortraitRaster,
    parameters: PortraitSemanticHeadParameters) -> PortraitHeadWarpManifest {
    let requested = parameters.bounded
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    let digest = raster.faceAnalysis.flatMap { try? encoder.encode($0) }.map(PortraitCandidateCoding.digest)
    func unavailable(_ reason: String) -> PortraitHeadWarpManifest {
      identityManifest(parameters: requested, reason: reason, digest: digest)
    }
    guard (try? raster.validateAnalysisEvidence()) != nil else { return unavailable("Invalid raster analysis metric; base geometry preserved") }
    guard parameters.revision == "semantic-head-v1" else { return unavailable("Unsupported semantic parameter revision") }
    guard let analysis = raster.faceAnalysis, analysis.status == .detected,
      (try? analysis.validate()) != nil else { return unavailable("Reliable face landmarks unavailable; base geometry preserved") }
    guard let geometry = raster.analysisGeometry, let extent = raster.sourceCropExtent,
      geometry.decodedWidth == analysis.decodedWidth, geometry.decodedHeight == analysis.decodedHeight,
      raster.width > 1, raster.height > 1 else { return unavailable("Original crop metric unavailable; base geometry preserved") }
    guard let confidence = analysis.observationConfidence, confidence >= 0.5,
      let landmarkConfidence = analysis.landmarksConfidence, landmarkConfidence >= 0.5 else {
      return unavailable("Face or landmark confidence below 0.5; base geometry preserved")
    }
    guard let yaw = analysis.yaw, let pitch = analysis.pitch else {
      return unavailable("Measured yaw or pitch unavailable; base geometry preserved")
    }
    guard abs(yaw) <= Double.pi/3, abs(pitch) <= Double.pi/6 else {
      return unavailable("Profile above 60 degrees yaw or pitch above 30 degrees unsupported; base geometry preserved")
    }
    let required: [(PortraitFaceRegion, Int)] = [(.leftEye, 2), (.rightEye, 2), (.leftEyebrow, 2),
      (.rightEyebrow, 2), (.nose, 1), (.outerLips, 3), (.faceContour, 3)]
    guard required.allSatisfy({ analysis.region($0.0).count >= $0.1 }) else {
      return unavailable("Bilateral eyes, brows, nose, lips or chin unavailable; base geometry preserved")
    }
    func source(_ p: PortraitLandmarkPoint) -> PortraitLandmarkPoint {
      .init(x: (p.x-geometry.crop.x)*extent.widthPixels/geometry.crop.width,
        y: (p.y-geometry.crop.y)*extent.heightPixels/geometry.crop.height)
    }
    func region(_ kind: PortraitFaceRegion) -> [PortraitLandmarkPoint] { analysis.region(kind).map(source) }
    var left = mean(region(.leftEye)), right = mean(region(.rightEye))
    if left.x > right.x { swap(&left, &right) }
    let eyeDelta = subtract(right, left), eyeDistance = length(eyeDelta)
    guard eyeDistance.isFinite, eyeDistance > 1e-6 else { return unavailable("Degenerate eye basis; base geometry preserved") }
    let origin = scale(add(left, right), 0.5), xAxis = scale(eyeDelta, 1/eyeDistance)
    var yAxis = PortraitLandmarkPoint(x: -xAxis.y, y: xAxis.x)
    let nose = mean(region(.nose))
    guard [origin.x, origin.y, nose.x, nose.y].allSatisfy(\.isFinite) else { return unavailable("Unbounded landmark metric; base geometry preserved") }
    if dot(subtract(nose, origin), yAxis) < 0 { yAxis = scale(yAxis, -1) }
    func local(_ p: PortraitLandmarkPoint) -> PortraitLandmarkPoint {
      let q = subtract(p, origin); return .init(x: dot(q, xAxis), y: dot(q, yAxis))
    }
    let lips = region(.outerLips).map(local)
    let lipTop = lips.map(\.y).min() ?? 0
    let chin = region(.faceContour).max { local($0).y < local($1).y }!
    let brow = mean(region(.leftEyebrow) + region(.rightEyebrow))
    let noseLocal = local(nose), browLocal = local(brow)
    guard noseLocal.y > eyeDistance*0.05, lipTop > noseLocal.y,
      local(chin).y > lipTop, browLocal.y < 0 else {
      return unavailable("Inconsistent eye, brow, nose, lip or chin ordering; base geometry preserved")
    }
    let basis = PortraitHeadWarpBasis(origin: origin, xAxis: xAxis, yAxis: yAxis,
      cropWidthSourcePixels: extent.widthPixels, cropHeightSourcePixels: extent.heightPixels,
      rasterWidth: raster.width, rasterHeight: raster.height)
    let forehead = PortraitLandmarkPoint(x: browLocal.x, y: browLocal.y - 0.55*eyeDistance)
    var anchors: [PortraitHeadWarpAnchor] = [
      .init(name: "leftEye", evidence: .measured, point: local(left), derivation: "Mean retained eye landmarks"),
      .init(name: "rightEye", evidence: .measured, point: local(right), derivation: "Mean retained eye landmarks"),
      .init(name: "brows", evidence: .measured, point: browLocal, derivation: "Mean retained bilateral brow landmarks"),
      .init(name: "nose", evidence: .measured, point: noseLocal, derivation: "Mean retained nose landmarks"),
      .init(name: "upperLipProtection", evidence: .measured, point: .init(x: 0, y: lipTop), derivation: "Minimum local y of retained outer lips; all points at or below remain fixed"),
      .init(name: "chin", evidence: .measured, point: local(chin), derivation: "Maximum local y of retained face contour"),
      .init(name: "forehead", evidence: .estimated, point: forehead, derivation: "Brow mean minus 0.55 inter-eye distances along nose axis; no observed hairline"),
      .init(name: "ears", evidence: .unavailable, point: nil, derivation: "Vision provides no ear landmarks; no ear-specific expansion")]
    var kernels: [PortraitHeadWarpKernel] = []
    var limited = parameters.bounded != parameters
    // Every ellipse is strictly within the original crop and strictly above lips.
    // Its C2 field is zero outside that support, including the image boundary.
    func append(name: String, center: PortraitLandmarkPoint, rx: Double, ry: Double,
      expansion: PortraitLandmarkPoint, translation: PortraitLandmarkPoint) -> Bool {
      guard max(abs(expansion.x), abs(expansion.y)) + length(translation) > 0 else { return true }
      let world = add(origin, add(scale(xAxis, center.x), scale(yAxis, center.y)))
      let extentX = abs(xAxis.x)*rx + abs(yAxis.x)*ry
      let extentY = abs(xAxis.y)*rx + abs(yAxis.y)*ry
      guard [world.x, world.y, extentX, extentY, rx, ry].allSatisfy(\.isFinite), rx > 0, ry > 0 else { return false }
      let fraction = min(1, min(min(world.x, extent.widthPixels-world.x)/max(extentX, 1e-12),
        min(world.y, extent.heightPixels-world.y)/max(extentY, 1e-12)))
      let protectedFraction = min(fraction, (lipTop-center.y)*0.98/ry)
      guard protectedFraction >= 0.65 else { return false }
      let supportFraction = min(1, protectedFraction*0.98)
      if supportFraction < 0.97 { limited = true }
      let radius = PortraitLandmarkPoint(x: rx*supportFraction, y: ry*supportFraction)
      let a = max(abs(expansion.x), abs(expansion.y))
      let bound = a*max(radius.x, radius.y) + length(translation)
      // max ||grad (1-r²)^3|| <= 1.718 / min(radius), use 1.72 upward bound.
      let derivative = a + 1.72*bound/min(radius.x, radius.y)
      guard derivative.isFinite, derivative >= 0, derivative <= 100, bound.isFinite else { return false }
      let steps = max(1, Int(ceil(derivative/0.2)))
      kernels.append(.init(name: name, center: center, radius: radius, expansion: expansion,
        translation: translation, steps: steps, derivativeNormBound: derivative, displacementBound: bound))
      return true
    }
    let d = eyeDistance
    let requests: [(String, PortraitLandmarkPoint, Double, Double, PortraitLandmarkPoint, PortraitLandmarkPoint)] = [
      ("forehead", forehead, 1.35*d, 0.95*d, .init(x: requested.foreheadWidth, y: 0), .init(x: 0, y: -requested.foreheadHeight*d)),
      ("leftEye", local(left), 0.40*d, 0.32*d, .init(x: requested.eyeScale, y: requested.eyeScale), .init(x: 0, y: 0)),
      ("rightEye", local(right), 0.40*d, 0.32*d, .init(x: requested.eyeScale, y: requested.eyeScale), .init(x: 0, y: 0)),
      ("leftUpperLateral", .init(x: -0.88*d, y: -0.20*d), 0.48*d, 0.70*d, .init(x: 0, y: 0), .init(x: -requested.lateralScale*d, y: 0)),
      ("rightUpperLateral", .init(x: 0.88*d, y: -0.20*d), 0.48*d, 0.70*d, .init(x: 0, y: 0), .init(x: requested.lateralScale*d, y: 0))]
    for request in requests {
      guard append(name: request.0, center: request.1, rx: request.2, ry: request.3,
        expansion: request.4, translation: request.5) else {
        return unavailable("Insufficient image or lip protection support for \(request.0); base geometry preserved")
      }
    }
    anchors.append(.init(name: "upperLateral", evidence: .estimated, point: .init(x: 0.88*d, y: -0.20*d),
      derivation: "Symmetric inter-eye-distance support; not an observed ear or hairline"))
    let determinant = kernels.reduce(1.0) { result, kernel in
      result * pow(1-kernel.derivativeNormBound/Double(kernel.steps), 2*Double(kernel.steps))
    }
    let status: PortraitHeadWarpManifest.Status = kernels.isEmpty ? .identity : (limited ? .limited : .applied)
    return PortraitHeadWarpManifest(status: status,
      summary: kernels.isEmpty ? "Zero semantic amplitudes; base geometry preserved" :
        "Semantic forehead, eye and upper-lateral warp\(limited ? "; support limited by crop or lips" : ""); forehead estimated, ears unavailable",
      analysisSHA256: digest, basis: basis, anchors: anchors, requested: requested, effective: requested,
      kernels: kernels, minimumJacobianDeterminant: determinant,
      maximumDisplacementSourcePixels: kernels.reduce(0) { $0 + $1.displacementBound })
  }

  private func semanticPoint(_ point: CGPoint) -> CGPoint {
    guard let basis = manifest.basis, !manifest.kernels.isEmpty else { return point }
    let source = PortraitLandmarkPoint(x: (point.x+0.5)*basis.cropWidthSourcePixels/Double(basis.rasterWidth),
      y: (point.y+0.5)*basis.cropHeightSourcePixels/Double(basis.rasterHeight))
    let offset = Self.subtract(source, basis.origin)
    var local = PortraitLandmarkPoint(x: Self.dot(offset, basis.xAxis), y: Self.dot(offset, basis.yAxis))
    var changed = false
    for kernel in manifest.kernels {
      for _ in 0..<kernel.steps {
        let delta = Self.subtract(local, kernel.center)
        let radiusSquared = pow(delta.x/kernel.radius.x, 2) + pow(delta.y/kernel.radius.y, 2)
        if radiusSquared >= 1 { continue }
        changed = true
        let weight = pow(1-radiusSquared, 3)/Double(kernel.steps)
        local = Self.add(local, .init(x: weight*(kernel.expansion.x*delta.x+kernel.translation.x),
          y: weight*(kernel.expansion.y*delta.y+kernel.translation.y)))
      }
    }
    guard changed else { return point }
    let mapped = Self.add(basis.origin, Self.add(Self.scale(basis.xAxis, local.x), Self.scale(basis.yAxis, local.y)))
    return CGPoint(x: mapped.x*Double(basis.rasterWidth)/basis.cropWidthSourcePixels-0.5,
      y: mapped.y*Double(basis.rasterHeight)/basis.cropHeightSourcePixels-0.5)
  }

  private static func mean(_ points: [PortraitLandmarkPoint]) -> PortraitLandmarkPoint {
    scale(points.reduce(.init(x: 0, y: 0), add), 1/Double(points.count))
  }
  private static func add(_ a: PortraitLandmarkPoint, _ b: PortraitLandmarkPoint) -> PortraitLandmarkPoint { .init(x: a.x+b.x, y: a.y+b.y) }
  private static func subtract(_ a: PortraitLandmarkPoint, _ b: PortraitLandmarkPoint) -> PortraitLandmarkPoint { .init(x: a.x-b.x, y: a.y-b.y) }
  private static func scale(_ a: PortraitLandmarkPoint, _ b: Double) -> PortraitLandmarkPoint { .init(x: a.x*b, y: a.y*b) }
  private static func dot(_ a: PortraitLandmarkPoint, _ b: PortraitLandmarkPoint) -> Double { a.x*b.x+a.y*b.y }
  private static func length(_ a: PortraitLandmarkPoint) -> Double { hypot(a.x, a.y) }
}
