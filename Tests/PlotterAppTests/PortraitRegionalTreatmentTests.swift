import Foundation
import Testing
@testable import PlotterApp

@Suite("Landmark regional stroke treatment")
struct PortraitRegionalTreatmentTests {
  @Test("Compact source-coordinate regions overlap softly and survive crop mapping")
  func sourceCoordinateWeights() throws {
    let raster = try regionalFixture()
    let field = try #require(PortraitRegionalTreatment.Field(raster: raster))
    let eye = CGPoint(x: 67, y: 67)
    #expect(field.weight(eye, region: .eyes) > 0.8)
    #expect(field.weight(eye, region: .face) > 0.5)
    #expect(field.weight(eye, region: .skin) < 0.1)
    #expect(field.weight(.init(x: 5, y: 5), region: .face) == 0)
    let extent = try PortraitSourceCropExtent(widthPixels: 200, heightPixels: 240)
    let geometry = try PortraitAnalysisGeometry(sourcePixelExtent: .init(widthPixels: 400, heightPixels: 400),
      decodedWidth: 400, decodedHeight: 400, crop: .init(x: 100, y: 40, width: 200, height: 240),
      rasterWidth: 160, rasterHeight: 160, contrastLow: 0, contrastHigh: 1, contrastApplied: true)
    let cropped = PortraitRaster(width: 160, height: 160, luminance: raster.luminance,
      provenance: "regional-crop-fixture", analysisSummary: "Synthetic", sourceCropExtent: extent,
      analysisGeometry: geometry, faceAnalysis: raster.faceAnalysis)
    let croppedField = try #require(PortraitRegionalTreatment.Field(raster: cropped))
    for y in stride(from: 45.0, to: 110, by: 4) {
      for x in stride(from: 45.0, to: 110, by: 4) {
        let p = CGPoint(x: x, y: y)
        let source = field.sourcePoint(p)
        let q = CGPoint(x: (source.x-100)/200*160-0.5, y: (source.y-40)/240*160-0.5)
        for region in PortraitTreatmentRegion.allCases {
          #expect(abs(field.weight(p, region: region)-croppedField.weight(q, region: region)) < 1e-10)
        }
      }
    }
  }

  @Test("Skin suppression removes actual strokes while eyelids and exterior paths stay exact")
  func actualStrokeSuppression() throws {
    let raster = try regionalFixture(uniform: true)
    let eyelid = [CGPoint(x: 64, y: 67), CGPoint(x: 67, y: 66), CGPoint(x: 70, y: 67)]
    let forehead = [CGPoint(x: 77, y: 43), CGPoint(x: 81, y: 43)]
    let outside = [CGPoint(x: 4, y: 4), CGPoint(x: 20, y: 12)]
    let base = [eyelid, forehead, outside]
    var options = PortraitVectorOptions.flowDefaults
    options.regionalTreatment = .init(skinSuppression: 1, featureProtection: 1)
    let result = try PortraitRegionalTreatment.apply(base, raster: raster, options: options)
    #expect(result.paths.contains(eyelid))
    #expect(result.paths.contains(outside))
    #expect(!result.paths.contains(forehead))
    #expect(result.paths != base)
    #expect(result.manifest?.analysisSHA256?.count == 64)
    #expect(try PortraitRegionalTreatment.apply(base, raster: raster, options: options).paths == result.paths)
  }

  @Test("Eye-only overlays preserve an already successful global treatment outside eyes")
  func localOverlayIsolation() throws {
    let raster = try regionalFixture(uniform: true)
    let eye = [CGPoint(x: 63, y: 67), CGPoint(x: 65, y: 66.4), CGPoint(x: 67, y: 66), CGPoint(x: 69, y: 66.4), CGPoint(x: 71, y: 67)]
    let lip = [CGPoint(x: 73, y: 88), CGPoint(x: 80, y: 87), CGPoint(x: 87, y: 88)]
    let outside = [CGPoint(x: 2, y: 2), CGPoint(x: 25, y: 27)]
    let forehead = [CGPoint(x: 77, y: 43), CGPoint(x: 81, y: 43)]
    var options = PortraitVectorOptions.flowDefaults
    options.regionalTreatment = .init(skinSuppression: 1)
    let base = [eye, lip, outside, forehead]
    let prior = try PortraitRegionalTreatment.apply(base, raster: raster, options: options)
    options.regionalAdjustments = [.init(scope: .eyes, skinSuppression: 0, featureProtection: 0, angularity: 1)]
    let local = try PortraitRegionalTreatment.apply(base, raster: raster, options: options)
    #expect(prior.paths.contains(lip) && local.paths.contains(lip))
    #expect(prior.paths.contains(outside) && local.paths.contains(outside))
    #expect(!prior.paths.contains(forehead) && !local.paths.contains(forehead))
    #expect(prior.paths.contains(eye) && !local.paths.contains(eye))
    #expect(local.paths.count == prior.paths.count)
  }

  @Test("Angular shortcuts yield to another frozen stroke instead of crossing its clearance")
  func angularClearance() throws {
    let raster = try regionalFixture(uniform: true)
    let arch = [CGPoint(x: 62, y: 68), CGPoint(x: 65, y: 64), CGPoint(x: 69, y: 64), CGPoint(x: 72, y: 68)]
    let obstacle = [CGPoint(x: 66, y: 67.5), CGPoint(x: 68, y: 67.5)]
    let exterior = [CGPoint(x: 2, y: 2), CGPoint(x: 20, y: 12)]
    var options = PortraitVectorOptions.flowDefaults
    options.regionalTreatment = .init(scope: .eyes, skinSuppression: 0, featureProtection: 0, angularity: 1)
    let free = try PortraitRegionalTreatment.apply([arch, exterior], raster: raster, options: options)
    let guarded = try PortraitRegionalTreatment.apply([arch, obstacle, exterior], raster: raster, options: options)
    #expect(free.paths[0] != arch)
    #expect(guarded.paths.contains(obstacle) && guarded.paths.contains(exterior))
    #expect(guarded.paths[0] == arch)
  }

  @Test("Unavailable or weak landmarks retain every base point and report fallback")
  func unavailable() throws {
    let fixture = try regionalFixture()
    let absent = PortraitRaster(width: fixture.width, height: fixture.height, luminance: fixture.luminance,
      provenance: "without-face", analysisSummary: "No face")
    let weak = try PortraitSemanticHeadGeometryTests().fixture(confidence: 0.1)
    let base = [[CGPoint(x: 20, y: 10), CGPoint(x: 80, y: 80)]]
    let options = PortraitPrototypeRecipe.angularComic.options()
    for raster in [absent, weak] {
      let result = try PortraitRegionalTreatment.apply(base, raster: raster, options: options)
      #expect(result.paths == base)
      #expect(result.manifest?.statuses.allSatisfy { $0.contains("unavailable") } == true)
      #expect(PortraitRegionalTreatment.summary(raster: raster, options: options)?.contains("unavailable") == true)
    }
  }

  @Test("Fixed-width graphic shadows add actual ordered strokes and respect material floor")
  func shadowConstructionAndMaterial() throws {
    let raster = try regionalFixture(uniform: true)
    let outside = [CGPoint(x: 3, y: 3), CGPoint(x: 25, y: 5)]
    var fine = PortraitVectorOptions.flowDefaults
    fine.regionalTreatment = .init(skinSuppression: 0, featureProtection: 1, shadowStrength: 1)
    var broad = fine
    broad.materialContext = try .init(profile: .init(name: "Regional broad", nominalWidthMM: 2.0), drawingHeightMM: 80)
    let first = try PortraitRegionalTreatment.apply([outside], raster: raster, options: fine)
    let second = try PortraitRegionalTreatment.apply([outside], raster: raster, options: broad)
    #expect(first.paths.contains(outside) && second.paths.contains(outside))
    #expect(first.paths.count > second.paths.count)
    #expect(second.paths.count > 1)
    let rows = second.paths.dropFirst().map { $0[0].y }.sorted()
    let minimum = try PortraitFlowRenderer.minimumSpacing(raster: raster, options: broad)
    for (a, b) in zip(rows, rows.dropFirst()) where a != b { #expect(b-a >= minimum) }
    #expect(first.manifest!.addedPaths <= 256)
    #expect(first.paths.dropFirst().allSatisfy { $0.count == 2 && $0.first!.y == $0.last!.y })
  }

  @Test("Measured 2D eye expansion works without 3D pose and has disjoint nonfolding support")
  func measuredEyeExpansion() throws {
    let raster = try PortraitSemanticHeadGeometryTests().fixture(yaw: nil, pitch: nil)
    #expect(PortraitHeadTransform(raster: raster, parameters: .init()).manifest.status == .unavailable)
    let transform = PortraitEyeTransform(raster: raster, parameters: .init(amount: 0.3))
    #expect(transform.manifest.applied)
    #expect(transform.manifest.minimumJacobianDeterminant > 0.8)
    #expect(transform.manifest.supports.count == 2)
    let left = transform.manifest.supports[0], right = transform.manifest.supports[1]
    let separation = hypot(left.measuredCenter.x-right.measuredCenter.x, left.measuredCenter.y-right.measuredCenter.y)
    #expect(left.radiusDecodedPixels + right.radiusDecodedPixels < separation)
    let eye = CGPoint(x: left.measuredCenter.x/2.5-0.5, y: left.measuredCenter.y/2.5-0.5)
    let a = CGPoint(x: eye.x-1, y: eye.y), b = CGPoint(x: eye.x+1, y: eye.y)
    let ratio = (transform.point(b).x-transform.point(a).x)/(b.x-a.x)
    #expect(ratio > 1.25 && ratio <= 1.3)
    for y in stride(from: 48.0, through: 90, by: 2) {
      for x in stride(from: 40.0, through: 118, by: 2) {
        let p = CGPoint(x: x, y: y), q = transform.point(p), epsilon = 0.0001
        let dx = transform.point(.init(x: x+epsilon, y: y))
        let dy = transform.point(.init(x: x, y: y+epsilon))
        let determinant = ((dx.x-q.x)*(dy.y-q.y)-(dx.y-q.y)*(dy.x-q.x))/(epsilon*epsilon)
        #expect(determinant >= transform.manifest.minimumJacobianDeterminant-0.0001)
        #expect(hypot(q.x-p.x, q.y-p.y)*2.5 <= transform.manifest.maximumDisplacementDecodedPixels+1e-8)
      }
    }
    for value in stride(from: -0.5, through: 159.5, by: 4) {
      for p in [CGPoint(x: value, y: -0.5), CGPoint(x: value, y: 159.5),
        CGPoint(x: -0.5, y: value), CGPoint(x: 159.5, y: value)] { #expect(transform.point(p) == p) }
    }
  }

  @Test("Eye warp bends long crossing strokes, preserves exterior and retains revisioned evidence")
  func eyeWarpPathsAndFallback() throws {
    let raster = try regionalFixture()
    let transform = PortraitEyeTransform(raster: raster, parameters: .init())
    let exterior = [CGPoint(x: 2, y: 2), CGPoint(x: 20, y: 12)]
    let crossing = [CGPoint(x: 30, y: 70.5), CGPoint(x: 125, y: 70.5)]
    let first = try transform.paths([exterior, crossing])
    #expect(first[0] == exterior)
    #expect(first[1].count > crossing.count)
    #expect(first[1].contains { abs($0.y-70.5) > 0.1 })
    #expect(try transform.paths([exterior, crossing]) == first)
    #expect(transform.manifest.analysisSHA256?.count == 64 && transform.manifest.geometrySHA256?.count == 64)
    #expect(try JSONDecoder().decode(PortraitEyeExaggerationManifest.self,
      from: PortraitCandidateCoding.encoder().encode(transform.manifest)) == transform.manifest)
    let missing = PortraitRaster(width: raster.width, height: raster.height, luminance: raster.luminance,
      provenance: "no-face", analysisSummary: "No retained landmarks")
    let unavailable = PortraitEyeTransform(raster: missing, parameters: .init())
    #expect(!unavailable.manifest.applied)
    #expect(try unavailable.paths([exterior, crossing]) == [exterior, crossing])
    #expect(unavailable.manifest.summary.contains("unavailable"))
    let zero = PortraitEyeTransform(raster: raster, parameters: .init(amount: 0))
    #expect(try zero.paths([exterior, crossing]) == [exterior, crossing])
  }

  @Test("Repeated regional overlays have explicit refusal, never silent truncation")
  func overlayBudget() throws {
    let raster = try regionalFixture()
    var options = PortraitVectorOptions.flowDefaults
    options.regionalAdjustments = Array(repeating: .init(), count: 9)
    #expect(throws: PortraitDrawingError.self) {
      try PortraitRegionalTreatment.apply([[.zero, .init(x: 10, y: 10)]], raster: raster, options: options)
    }
  }
}

func regionalFixture(uniform: Bool = false) throws -> PortraitRaster {
  let base = try PortraitSemanticHeadGeometryTests().fixture()
  let size = base.width
  var values = [Double](repeating: 1, count: size * size)
  for y in 0..<size { for x in 0..<size {
    let dx = (Double(x)-80)/31, dy = (Double(y)-77)/51
    guard dx*dx + dy*dy < 1 else { continue }
    var value = x > 83 ? 0.27 : 0.78
    if y < 53 { value = 0.15 }
    if (abs(x-67) <= 5 || abs(x-92) <= 5) && abs(y-68) <= 1 { value = 0.05 }
    if abs(x-80) <= 8 && abs(y-88) <= 1 { value = 0.10 }
    if abs(x-80) < 2 && (73...81).contains(y) { value = 0.35 }
    if (x+y).isMultiple(of: 11) && (54...62).contains(y) { value -= 0.08 }
    values[y*size+x] = value
  } }
  return PortraitRaster(width: size, height: size,
    luminance: uniform ? Array(repeating: 0.3, count: size*size) : values,
    provenance: "regional-synthetic-v1", analysisSummary: "Synthetic regional evidence, not likeness validation",
    sourceCropExtent: base.sourceCropExtent, analysisGeometry: base.analysisGeometry, faceAnalysis: base.faceAnalysis)
}
