import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Material adaptation and portrait presentation")
struct PortraitMaterialContextTests {
  @Test("spacing uses actual source metric and selected drawing height")
  func physicalPitch() throws {
    let profile = try DrawingMaterialProfileRevision(name: "Broad", nominalWidthMM: 3)
    let raster = PortraitRaster(width: 160, height: 80,
      luminance: Array(repeating: 0.4, count: 160 * 80), provenance: "metric-fixture", analysisSummary: "synthetic",
      sourceCropExtent: try .init(widthPixels: 4000, heightPixels: 100))
    var options = PortraitVectorOptions()
    options.hatchSpacing = 1; options.minimumContourLength = 0.5
    let small = try PortraitMaterialContext(profile: profile, drawingHeightMM: 80).adapting(options, raster: raster)
    let large = try PortraitMaterialContext(profile: profile, drawingHeightMM: 160).adapting(options, raster: raster)
    #expect(small.hatchSpacing == 5)
    #expect(large.hatchSpacing == 3)
    #expect(small.minimumContourLength == 3)
    #expect(large.minimumContourLength == 1.5)
    #expect(options.hatchSpacing == 1)
    #expect(options.minimumContourLength == 0.5)
  }

  @Test("material floor preserves deliberate coarsening and may exceed style slider range")
  func materialFloor() throws {
    let profile = try DrawingMaterialProfileRevision(name: "Very broad", nominalWidthMM: 5)
    let raster = PortraitRaster(width: 160, height: 160,
      luminance: Array(repeating: 0.4, count: 160 * 160), provenance: "fixture", analysisSummary: "synthetic",
      sourceCropExtent: try .init(widthPixels: 1000, heightPixels: 1000))
    let context = try PortraitMaterialContext(profile: profile, drawingHeightMM: 20)
    var options = PortraitVectorOptions()
    options.hatchSpacing = 16; options.minimumContourLength = 40
    let adapted = try context.adapting(options, raster: raster)
    #expect(adapted.hatchSpacing == 60)
    #expect(adapted.minimumContourLength == 40)
  }

  @Test("context identity includes exact profile value and scale, with stale matching explicit")
  func provenanceAndApplicability() throws {
    let profile = try DrawingMaterialProfileRevision(name: "Original", nominalWidthMM: 1)
    let changed = try DrawingMaterialProfileRevision(id: profile.id, name: "Changed", nominalWidthMM: 2,
      createdAt: profile.createdAt)
    let context = try PortraitMaterialContext(profile: profile, drawingHeightMM: 100)
    let resized = try PortraitMaterialContext(profile: profile, drawingHeightMM: 101)
    let replaced = try PortraitMaterialContext(profile: changed, drawingHeightMM: 100)
    #expect(context.provenance != resized.provenance)
    #expect(context.provenance != replaced.provenance)
    #expect(context.matches(drawingHeightMM: 100, profileKey: profile.key))
    #expect(!context.matches(drawingHeightMM: 101, profileKey: profile.key))
    #expect(!context.matches(drawingHeightMM: 100, profileKey: nil))
    #expect(!context.matches(drawingHeightMM: .nan, profileKey: profile.key))
    var options = PortraitVectorOptions()
    let prior = options.provenance
    options.materialContext = context
    #expect(options.provenance != prior)
    #expect(options.provenance.contains(context.provenance))
    #expect(try JSONDecoder().decode(PortraitMaterialContext.self, from: JSONEncoder().encode(context)) == context)
  }

  @Test("malformed decoded material context and unsupported revision are refused")
  func malformedDecode() throws {
    let context = try PortraitMaterialContext(profile: .init(name: "Valid", nominalWidthMM: 1), drawingHeightMM: 100)
    let bytes = try JSONEncoder().encode(context)
    let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var invalidHeight = original; invalidHeight["drawingHeightMM"] = 0
    var invalidRevision = original; invalidRevision["revision"] = "future-version"
    var invalidProfile = original
    var profile = try #require(original["profile"] as? [String: Any])
    profile["nominalWidthMM"] = -1; invalidProfile["profile"] = profile
    for malformed in [invalidHeight, invalidRevision, invalidProfile] {
      let encoded = try JSONSerialization.data(withJSONObject: malformed)
      #expect(throws: (any Error).self) { try JSONDecoder().decode(PortraitMaterialContext.self, from: encoded) }
    }
  }

  @Test("absent material context preserves legacy recipe encoding")
  func legacyEncoding() throws {
    let original = PortraitVectorOptions()
    let bytes = try PortraitCandidateCoding.encoder().encode(original)
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    #expect(object["materialContext"] == nil)
    let restored = try JSONDecoder().decode(PortraitVectorOptions.self, from: bytes)
    #expect(restored.materialContext == nil)
    #expect(try PortraitCandidateCoding.encoder().encode(restored) == bytes)
  }

  @Test("preview and rating share material defaults while explicit width overrides remain estimates")
  func presentation() throws {
    let distribution = try DepositedWidthDistribution(medianMM: 0.8, lowerBoundMM: 0.7,
      upperBoundMM: 0.9, uncertaintyMM: 0.1, sampleCount: 20)
    let measured = try DrawingMaterialProfileRevision(name: "Measured", nominalWidthMM: 0.5,
      qualification: .independentlyMeasured, depositedWidth: distribution,
      measurementEvidenceID: UUID(), physicalMetricRevision: "test-independent-metric")
    let context = try PortraitMaterialContext(profile: measured, drawingHeightMM: 145)
    let defaults = try #require(PortraitPreviewPresentation.context(material: context, nominalWidthMM: 0.4))
    #expect(defaults.drawingHeightMM == 145)
    #expect(defaults.inkWidthMM == 1)
    #expect(defaults.inkWidthIsMeasured)
    #expect(defaults.materialRevision == measured.key)
    let overrides = try #require(PortraitPreviewPresentation.context(material: context, nominalWidthMM: 0.4,
      widthOverrideMM: 2, heightOverrideMM: 90))
    #expect(overrides.drawingHeightMM == 90)
    #expect(overrides.inkWidthMM == 2)
    #expect(!overrides.inkWidthIsMeasured)
    #expect(overrides.materialRevision == measured.key)
    let estimated = try DrawingMaterialProfileRevision(name: "Estimated", nominalWidthMM: 0.5,
      qualification: .controllerCoordinateEstimate, depositedWidth: distribution, measurementEvidenceID: UUID())
    #expect(PortraitPreviewPresentation.context(material: try .init(profile: estimated, drawingHeightMM: 100),
      nominalWidthMM: 0.4)?.inkWidthIsMeasured == false)
    let legacy = try #require(PortraitPreviewPresentation.context(material: nil, nominalWidthMM: 0.4))
    #expect(legacy.drawingHeightMM == 100)
    #expect(legacy.inkWidthMM == 0.4)
    #expect(!legacy.inkWidthIsMeasured)
    #expect(legacy.materialRevision == nil)
  }
}
