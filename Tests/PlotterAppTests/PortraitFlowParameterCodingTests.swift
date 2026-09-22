import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Additive Flow parameter compatibility")
struct PortraitFlowParameterCodingTests {
  @Test("The pre-support default recipe bytes and provenance survive absent and explicit zero controls")
  func legacyBytes() throws {
    let bytes = Data(#"{"contourLevels":6,"hatchAngleDegrees":0,"hatchSpacing":8,"headScale":1,"minimumContourLength":6,"simplificationTolerance":0.25,"sketchThreshold":0.012,"smoothing":1.5,"tonalStrength":1}"#.utf8)
    let legacy = try JSONDecoder().decode(PortraitVectorOptions.self, from: bytes)
    let encoder = PortraitCandidateCoding.encoder()
    #expect(legacy == .flowDefaults)
    #expect(try encoder.encode(legacy) == bytes)
    var zero = legacy
    zero.flowSupport = 0
    zero.flowStructureSupport = 0
    zero.flowSupportScale = 0
    zero.flowSeedIrregularity = 0
    #expect(zero.bounded == legacy)
    #expect(zero.provenance == legacy.provenance)
    #expect(try encoder.encode(zero) == bytes)
    #expect(try JSONDecoder().decode(PortraitVectorOptions.self, from: encoder.encode(zero)) == legacy)
  }

  @Test("All additive amounts canonicalize invalid endpoints without contaminating legacy provenance")
  func finiteBounds() throws {
    let keys: [WritableKeyPath<PortraitVectorOptions, Double?>] = [
      \.flowSupport, \.flowStructureSupport, \.flowSupportScale, \.flowSeedIrregularity]
    for key in keys {
      for value in [Double.nan, .infinity, -.infinity, -1, 0, 0.25, 1, 2] {
        var options = PortraitVectorOptions.flowDefaults
        options[keyPath: key] = value
        let expected: Double? = value.isFinite && value > 0 ? min(1, value) : nil
        #expect(options.bounded[keyPath: key] == expected)
        let decoded = try JSONDecoder().decode(PortraitVectorOptions.self,
          from: PortraitCandidateCoding.encoder().encode(options))
        #expect(decoded == options.bounded)
      }
    }
  }

  @Test("An exact candidate retains active and dormant support controls across archive coding")
  func candidateRoundTrip() throws {
    let raster = portraitTestRaster()
    var options = PortraitVectorOptions.flowDefaults
    options.flowSupport = 0.35
    options.flowStructureSupport = 0.4
    options.flowSupportScale = 0.7
    options.flowSeedIrregularity = 0.8
    let recipe = PortraitStyleRecipe(id: "support-archive", title: "Supported Flow", seed: 42,
      style: .flowEdges, vectorOptions: options, analysisOptions: .init())
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .flowEdges,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    let candidate = try PortraitCandidate(sourceData: Data("local-fixture".utf8), sourcePixelExtent: nil,
      raster: raster, recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), pose: .front)
    let bytes = try PortraitCandidateCoding.encoder().encode(candidate)
    let restored = try JSONDecoder().decode(PortraitCandidate.self, from: bytes)
    try restored.validateIntegrity()
    #expect(restored.id == candidate.id)
    #expect(restored.recipe == recipe)
    #expect(restored.program == program)
    #expect(try PortraitCandidateCoding.encoder().encode(restored) == bytes)
    options.flowSupport = nil; options.flowStructureSupport = nil
    let dormant = try JSONDecoder().decode(PortraitVectorOptions.self,
      from: PortraitCandidateCoding.encoder().encode(options))
    #expect(dormant.flowSupportScale == 0.7)
  }
}
