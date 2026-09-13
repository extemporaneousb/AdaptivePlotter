import CoreGraphics
import Foundation
import Testing

@testable import PlotterApp

@Suite("Semantic head source-metric geometry")
struct PortraitSemanticHeadGeometryTests {
  @Test("frontal, rolled and three-quarter poses have bounded orientation-preserving geometry")
  func supportedPoses() throws {
    for (roll, yaw) in [(0.0, 0.0), (35.0, 0.0), (0.0, 45.0), (35.0, 45.0)] {
      let transform = PortraitHeadTransform(raster: try fixture(roll: roll, yaw: yaw), parameters: .init())
      #expect(transform.manifest.status == .applied || transform.manifest.status == .limited)
      #expect(transform.manifest.minimumJacobianDeterminant > 0)
      #expect(transform.manifest.kernels.allSatisfy { $0.derivativeNormBound/Double($0.steps) <= 0.2 })
      for y in stride(from: 1.0, through: 158, by: 5) {
        for x in stride(from: 1.0, through: 158, by: 5) {
          let p = CGPoint(x: x, y: y), q = transform.point(p), epsilon = 0.0001
          let dx = transform.point(.init(x: x+epsilon, y: y))
          let dy = transform.point(.init(x: x, y: y+epsilon))
          let determinant = ((dx.x-q.x)*(dy.y-q.y)-(dx.y-q.y)*(dy.x-q.x))/(epsilon*epsilon)
          #expect(determinant >= transform.manifest.minimumJacobianDeterminant-0.0001)
          #expect(q.x >= -0.5 && q.x <= 159.5 && q.y >= -0.5 && q.y <= 159.5)
          let sourceDisplacement = hypot(q.x-p.x, q.y-p.y)*2.5
          #expect(sourceDisplacement <= transform.manifest.maximumDisplacementSourcePixels+1e-8)
        }
      }
    }
  }

  @Test("forehead width and height increase, eye scale increases and lower face stays exact")
  func semanticEffects() throws {
    let base = try fixture()
    let transform = PortraitHeadTransform(raster: base, parameters: .init())
    let basis = try #require(transform.manifest.basis)
    let forehead = try #require(transform.manifest.anchors.first { $0.name == "forehead" }?.point)
    func point(_ x: Double, _ y: Double) -> CGPoint { rasterPoint(local: .init(x: x, y: y), basis: basis) }
    let beforeLeft = point(forehead.x-25, forehead.y), beforeRight = point(forehead.x+25, forehead.y)
    let afterLeft = transform.point(beforeLeft), afterRight = transform.point(beforeRight)
    #expect(afterRight.x-afterLeft.x > (beforeRight.x-beforeLeft.x)*1.08)
    #expect(transform.point(point(forehead.x, forehead.y)).y < point(forehead.x, forehead.y).y-3)
    let eyeOnly = PortraitHeadTransform(raster: base,
      parameters: .init(foreheadWidth: 0, foreheadHeight: 0, eyeScale: 0.3, lateralScale: 0))
    let a = point(-32-5, 0), b = point(-32+5, 0)
    #expect(eyeOnly.point(b).x-eyeOnly.point(a).x > (b.x-a.x)*1.15)
    let lateralOnly = PortraitHeadTransform(raster: base,
      parameters: .init(foreheadWidth: 0, foreheadHeight: 0, eyeScale: 0, lateralScale: 0.3))
    #expect(lateralOnly.point(point(0.88*64, -0.2*64)).x > point(0.88*64, -0.2*64).x+4)
    for y in stride(from: 48.0, through: 170, by: 7) {
      for x in stride(from: -90.0, through: 90, by: 9) {
        let p = point(x, y)
        #expect(transform.point(p) == p)
      }
    }
    #expect(transform.manifest.anchors.first { $0.name == "forehead" }?.evidence == .estimated)
    #expect(transform.manifest.anchors.first { $0.name == "ears" }?.evidence == .unavailable)
  }

  @Test("image boundaries remain fixed without clamping at all parameter limits")
  func fixedBoundary() throws {
    for roll in [0.0, 35.0] {
      let transform = PortraitHeadTransform(raster: try fixture(roll: roll),
        parameters: .init(foreheadWidth: 0.6, foreheadHeight: 0.6, eyeScale: 0.6, lateralScale: 0.6))
      for value in stride(from: -0.5, through: 159.5, by: 4) {
        for p in [CGPoint(x: value, y: -0.5), CGPoint(x: value, y: 159.5),
          CGPoint(x: -0.5, y: value), CGPoint(x: 159.5, y: value)] {
          #expect(transform.point(p) == p)
        }
      }
    }
  }

  @Test("unsupported profiles, unknown pose, missing landmarks and crop pressure preserve base")
  func unsupported() throws {
    let fixtures = [try fixture(yaw: 75), try fixture(pitch: 45), try fixture(yaw: nil),
      try fixture(confidence: 0.3), try fixture(omitted: .rightEye), try fixture(omitted: .outerLips),
      try fixture(originY: 45)]
    for raster in fixtures {
      let transform = PortraitHeadTransform(raster: raster, parameters: .init())
      #expect(transform.manifest.status == .unavailable)
      #expect(!transform.manifest.summary.isEmpty)
      #expect(transform.manifest.kernels.isEmpty)
      #expect(transform.point(.init(x: 70, y: 60)) == CGPoint(x: 70, y: 60))
    }
  }

  @Test("corrupt numerical crop metadata refuses transformation without trapping")
  func corruptGeometry() throws {
    let valid = try fixture()
    let extent = try #require(valid.sourceCropExtent)
    let invalid = PortraitAnalysisGeometry(sourcePixelExtent: extent, decodedWidth: 400, decodedHeight: 400,
      crop: .init(x: 0, y: 0, width: .infinity, height: 400), rasterWidth: 160, rasterHeight: 160,
      contrastLow: 0, contrastHigh: 1, contrastApplied: true)
    let raster = PortraitRaster(width: 160, height: 160, luminance: valid.luminance,
      provenance: "invalid", analysisSummary: "Corrupt input", sourceCropExtent: extent,
      analysisGeometry: invalid, faceAnalysis: valid.faceAnalysis)
    let transform = PortraitHeadTransform(raster: raster, parameters: .init())
    #expect(transform.manifest.status == .unavailable)
    #expect(transform.point(.init(x: 70, y: 40)) == CGPoint(x: 70, y: 40))
  }

  @Test("unequal sampling resolution preserves the same source-metric deformation")
  func sourceMetricCovariance() throws {
    let a = PortraitHeadTransform(raster: try fixture(width: 160, height: 160), parameters: .init())
    let b = PortraitHeadTransform(raster: try fixture(width: 160, height: 80), parameters: .init())
    for y in stride(from: 20.0, through: 350, by: 10) {
      for x in stride(from: 20.0, through: 350, by: 10) {
        let p = a.point(.init(x: x/2.5-0.5, y: y/2.5-0.5))
        let q = b.point(.init(x: x/2.5-0.5, y: y/5-0.5))
        #expect(abs(p.x-q.x) < 1e-9)
        #expect(abs((p.y+0.5)*2.5-(q.y+0.5)*5) < 1e-9)
      }
    }
  }

  @Test("manifest roundtrip retains exact kernels and curved long-segment samples")
  func reproducibility() throws {
    let raster = try fixture()
    let a = PortraitHeadTransform(raster: raster, parameters: .init())
    let b = PortraitHeadTransform(raster: raster, parameters: .init())
    let encoded = try JSONEncoder().encode(a.manifest)
    #expect(try JSONDecoder().decode(PortraitHeadWarpManifest.self, from: encoded) == a.manifest)
    #expect(a.manifest == b.manifest)
    #expect(a.manifest.analysisSHA256?.count == 64)
    let left = a.point(.init(x: 10, y: 44)), right = a.point(.init(x: 149, y: 44))
    let interior = a.point(.init(x: 79.5, y: 44))
    #expect(abs(interior.y-(left.y+right.y)*0.5) > 2)
    for x in stride(from: 10.0, through: 149, by: 2) {
      #expect(a.point(.init(x: x, y: 44)) == b.point(.init(x: x, y: 44)))
    }
  }

  @Test("the production vectorizer bends supported hatches and binds its retained candidate manifest")
  func producerAndCandidate() throws {
    let raster = try fixture()
    let parameters = PortraitSemanticHeadParameters()
    let options = PortraitVectorOptions(simplificationTolerance: 0, hatchSpacing: 10,
      semanticHead: parameters)
    let pen = try portraitTestStyle()
    let base = try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch,
      strokeStyle: pen, vectorOptions: PortraitVectorOptions(simplificationTolerance: 0, hatchSpacing: 10))
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch,
      strokeStyle: pen, vectorOptions: options)
    let manifest = PortraitHeadTransform(raster: raster, parameters: parameters).manifest
    #expect(manifest.status == .applied || manifest.status == .limited)
    #expect(program.strokes.map(\.path) != base.strokes.map(\.path))
    #expect(program.strokes.contains { $0.path.points.count > 2 })
    #expect(program.source.sourceIdentifier.hasPrefix("portrait-v4|"))
    let digest = PortraitCandidateCoding.digest(try PortraitCandidateCoding.encoder().encode(manifest))
    #expect(program.source.sourceIdentifier.contains("|headWarp=" + digest))
    let recipe = PortraitStyleRecipe(id: "supported-head-fixture", title: "Supported semantic fixture", seed: 19,
      style: .hatch, vectorOptions: options, analysisOptions: .init())
    let candidate = try PortraitCandidate(sourceData: Data([1, 8, 9]), sourcePixelExtent: raster.sourceCropExtent,
      raster: raster, recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(),
      pose: .front, warpManifest: manifest)
    let restored = try JSONDecoder().decode(PortraitCandidate.self, from: PortraitCandidateCoding.encoder().encode(candidate))
    try restored.validateIntegrity()
    #expect(restored.program == program)
    #expect(restored.warpManifest == manifest)
    #expect(restored.raster.faceAnalysis == raster.faceAnalysis)
  }

  private func rasterPoint(local: PortraitLandmarkPoint, basis: PortraitHeadWarpBasis) -> CGPoint {
    let x = basis.origin.x+basis.xAxis.x*local.x+basis.yAxis.x*local.y
    let y = basis.origin.y+basis.xAxis.y*local.x+basis.yAxis.y*local.y
    return .init(x: x*Double(basis.rasterWidth)/basis.cropWidthSourcePixels-0.5,
      y: y*Double(basis.rasterHeight)/basis.cropHeightSourcePixels-0.5)
  }

  private func fixture(width: Int = 160, height: Int = 160, roll: Double = 0,
    yaw: Double? = 0, pitch: Double? = 0, confidence: Double = 0.95,
    omitted: PortraitFaceRegion? = nil, originY: Double = 170) throws -> PortraitRaster {
    let angle = roll*Double.pi/180
    func p(_ x: Double, _ y: Double) -> PortraitLandmarkPoint {
      .init(x: 200+cos(angle)*x-sin(angle)*y, y: originY+sin(angle)*x+cos(angle)*y)
    }
    let shapes: [(PortraitFaceRegion, [(Double, Double)])] = [
      (.leftEye, [(-39, 0), (-32, -3), (-25, 0), (-32, 3)]),
      (.rightEye, [(25, 0), (32, -3), (39, 0), (32, 3)]),
      (.leftEyebrow, [(-42, -18), (-32, -21), (-22, -18)]),
      (.rightEyebrow, [(22, -18), (32, -21), (42, -18)]),
      (.nose, [(-6, 22), (0, 25), (6, 22)]),
      (.outerLips, [(-18, 48), (0, 45), (18, 48), (0, 53)]),
      (.faceContour, [(-58, 0), (-48, 50), (0, 88), (48, 50), (58, 0)])]
    let yawRadians = (yaw ?? 0)*Double.pi/180
    let regions = shapes.filter { $0.0 != omitted }.map { kind, points in
      // Synthetic three-quarter geometry includes asymmetric foreshortening and
      // nose lateral offset, in addition to the retained admission metadata.
      PortraitLandmarkRegion(kind: kind, points: points.map { x, y in
        let compression = x > 0 ? 1-0.30*abs(sin(yawRadians)) : 1
        let offset = kind == .nose ? 12*sin(yawRadians) : 0
        return p(x*compression+offset, y)
      },
        precisionEstimates: nil, pointsClassification: 0)
    }
    let analysis = PortraitFaceAnalysis(requestRevision: 3, constellation: 2, platformVersion: "synthetic",
      status: .detected, unavailableReason: nil, decodedWidth: 400, decodedHeight: 400,
      boundingBox: .init(x: 100, y: 40, width: 200, height: 270),
      observationConfidence: confidence, landmarksConfidence: confidence, roll: angle,
      yaw: yaw.map { $0*Double.pi/180 }, pitch: pitch.map { $0*Double.pi/180 }, regions: regions)
    let extent = try PortraitSourceCropExtent(widthPixels: 400, heightPixels: 400)
    let geometry = PortraitAnalysisGeometry(sourcePixelExtent: extent, decodedWidth: 400, decodedHeight: 400,
      crop: .init(x: 0, y: 0, width: 400, height: 400), rasterWidth: width, rasterHeight: height,
      contrastLow: 0, contrastHigh: 1, contrastApplied: true)
    return PortraitRaster(width: width, height: height, luminance: Array(repeating: 0.4, count: width*height),
      provenance: "semantic-head-synthetic", analysisSummary: "Synthetic landmarks, no likeness evidence",
      sourceCropExtent: extent, analysisGeometry: geometry, faceAnalysis: analysis)
  }
}
