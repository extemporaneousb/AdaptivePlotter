import Foundation
import Testing

@testable import PlotterApp

@Suite("Retained portrait analysis inputs")
struct PortraitAnalysisEvidenceTests {
  @Test("analyzer owns exact numeric crop, sampling, contrast and not-requested mask state")
  func analyzedGeometry() throws {
    let raster = try PortraitImageAnalyzer.analyze(data: portraitTestImage(),
      options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false))
    let geometry = try #require(raster.analysisGeometry)
    #expect(geometry.sourcePixelExtent.widthPixels == 60)
    #expect(geometry.sourcePixelExtent.heightPixels == 80)
    #expect(geometry.decodedWidth == 60 && geometry.decodedHeight == 80)
    #expect(geometry.crop == PortraitAnalysisCrop(x: 0, y: 0, width: 60, height: 80))
    #expect(geometry.rasterWidth == raster.width && geometry.rasterHeight == raster.height)
    #expect(geometry.sampling == .pixelCentersV1)
    #expect(geometry.preprocessingRevision == "portrait-analysis-v2")
    #expect(geometry.contrastLow == 0 && geometry.contrastHigh == 1)
    #expect(geometry.contrastApplied)
    #expect(raster.personMask?.status == .notRequested)
    #expect(raster.personMask?.alpha == nil)
    let restored = try JSONDecoder().decode(PortraitRaster.self, from: JSONEncoder().encode(raster))
    #expect(restored.analysisGeometry == raster.analysisGeometry)
    #expect(restored.personMask == raster.personMask)
    #expect(restored.luminance == raster.luminance)
  }

  @Test("requested Vision mask owns actual alpha or an explicit unavailable result")
  func requestedMaskEvidence() throws {
    let raster = try PortraitImageAnalyzer.analyze(data: portraitTestImage(),
      options: PortraitAnalysisOptions(cropToFace: false, removeBackground: true))
    let mask = try #require(raster.personMask)
    #expect(mask.status != .notRequested)
    #expect(try #require(mask.requestRevision) > 0)
    #expect(!mask.platformVersion.isEmpty)
    if mask.status == .applied {
      #expect(try #require(mask.alpha).count == raster.width * raster.height)
      #expect(mask.sourceMaskCrop != nil)
      #expect(mask.unavailableReason == nil)
    } else { #expect(mask.unavailableReason?.isEmpty == false) }
    try raster.validateAnalysisEvidence()
  }

  @Test("applied soft alpha and exact transforms round trip without rerunning Vision")
  func exactAppliedMask() throws {
    let raster = try fixture()
    let restored = try JSONDecoder().decode(PortraitRaster.self, from: JSONEncoder().encode(raster))
    #expect(restored.personMask == raster.personMask)
    #expect(restored.analysisGeometry == raster.analysisGeometry)
    #expect(restored.analysisGeometry?.preprocessingRevision == "portrait-analysis-v1")
    #expect(restored.luminance == raster.luminance)
    let alpha = try #require(restored.personMask?.alpha)
    #expect(alpha[3] == 3.0 / 63.0)
    // Restore the exact input sent into vector preprocessing without a detector.
    let program = try PortraitVectorizer.program(from: restored, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle())
    #expect(program == (try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle())))
  }

  @Test("corrupt mask, incompatible sampling metadata and mismatched crops fail decoding")
  func corruptAnalysisRefused() throws {
    let encoded = try JSONEncoder().encode(fixture())
    let original = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    for mutation in 0..<4 {
      var json = original
      var mask = try #require(json["personMask"] as? [String: Any])
      var geometry = try #require(json["analysisGeometry"] as? [String: Any])
      switch mutation {
      case 0: mask["alpha"] = [0.5]
      case 1: mask["schemaVersion"] = 99
      case 2: geometry["sampling"] = "unknown-sampling"
      default: geometry["crop"] = ["x": 0, "y": 0, "width": 999, "height": 8]
      }
      json["personMask"] = mask
      json["analysisGeometry"] = geometry
      let bad = try JSONSerialization.data(withJSONObject: json)
      #expect(throws: (any Error).self) { try JSONDecoder().decode(PortraitRaster.self, from: bad) }
    }
  }

  @Test("legacy raster remains explicit about missing exact analysis and mask data")
  func legacyAvailability() throws {
    var json = try #require(JSONSerialization.jsonObject(
      with: JSONEncoder().encode(fixture())) as? [String: Any])
    json["schemaVersion"] = 1
    json.removeValue(forKey: "analysisGeometry")
    json.removeValue(forKey: "personMask")
    let legacy = try JSONDecoder().decode(PortraitRaster.self,
      from: JSONSerialization.data(withJSONObject: json))
    #expect(legacy.analysisGeometry == nil)
    #expect(legacy.personMask == nil)
    #expect(legacy.sourceCropExtent != nil)
  }

  private func fixture() throws -> PortraitRaster {
    let extent = try PortraitSourceCropExtent(widthPixels: 8, heightPixels: 8)
    let crop = PortraitAnalysisCrop(x: 0, y: 0, width: 8, height: 8)
    let geometry = PortraitAnalysisGeometry(sourcePixelExtent: extent,
      decodedWidth: 8, decodedHeight: 8, crop: crop, rasterWidth: 8, rasterHeight: 8,
      contrastLow: 0, contrastHigh: 1, contrastApplied: true)
    let alpha = (0..<64).map { Double($0) / 63 }
    let mask = PortraitPersonMask(status: .applied, requestRevision: 1,
      platformVersion: "synthetic-test-fixture", width: 8, height: 8,
      sourceMaskWidth: 8, sourceMaskHeight: 8, sourceMaskCrop: crop, alpha: alpha)
    return PortraitRaster(width: 8, height: 8, luminance: alpha.map { 1 - $0 * 0.9 },
      provenance: "retained-alpha-fixture", analysisSummary: "Synthetic exact alpha fixture",
      sourceCropExtent: extent, analysisGeometry: geometry, personMask: mask)
  }
}
