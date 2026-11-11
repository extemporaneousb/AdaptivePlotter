@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Native portrait controls and historical shared recipes")
struct PortraitDrawingParametersTests {
  @Test("Shared detail changes actual paths in both kernels", arguments: [PortraitStyle.contours, .flowEdges])
  func detailGeometry(style: PortraitStyle) throws {
    let raster = try regionalFixture()
    let pen = try portraitTestStyle()
    let coarse = PortraitVectorOptions(drawingParameters: .init(detail: 0.1))
    let fine = PortraitVectorOptions(drawingParameters: .init(detail: 0.9))
    let a = try PortraitVectorizer.program(from: raster, pose: .front, style: style,
      strokeStyle: pen, vectorOptions: coarse)
    let b = try PortraitVectorizer.program(from: raster, pose: .front, style: style,
      strokeStyle: pen, vectorOptions: fine)
    #expect(a.strokes.map(\.path) != b.strokes.map(\.path))
    #expect(a.source.sourceIdentifier.contains("drawingParameters=v1"))
    #expect(!a.strokes.isEmpty && !b.strokes.isEmpty)
  }

  @Test("Spatial controls resolve at the actual raster scale and preserve regional/material options")
  func resolutionAndCoding() throws {
    var options = PortraitVectorOptions(drawingParameters: .init(detail: 0.3, tone: 1.25,
      smoothness: 0.4, minimumLine: 0.025))
    options.setTreatment(.init(scope: .eyes, angularity: 0.6))
    for height in [160, 512] {
      let resolved = options.resolved(rasterHeight: height)
      #expect(abs(resolved.minimumContourLength / Double(height) - 0.025) < 1e-12)
      #expect(abs(resolved.smoothing / Double(height) - 0.002) < 1e-12)
      #expect(resolved.tonalStrength == 1.25)
      #expect(resolved.regionalAdjustments == options.regionalAdjustments)
    }
    let bytes = try PortraitCandidateCoding.encoder().encode(options)
    #expect(try JSONDecoder().decode(PortraitVectorOptions.self, from: bytes) == options)
  }

  @Test("Cached Flow layers and direct vectorization consume the same resolved parameters", arguments: [false, true])
  func cachedFlow(shared: Bool) async throws {
    let parameters = PortraitDrawingParameters(detail: 0.8, tone: 1.4, smoothness: 0.2, minimumLine: 0.01)
    let options = shared ? PortraitVectorOptions(drawingParameters: parameters)
      : PortraitVectorOptions.nativeDefaults(for: .flowEdges)
    let pen = try portraitTestStyle()
    let result = try await PortraitImageAnalyzer().render(.init(data: portraitTestImage(), pose: .front,
      style: .flowEdges, options: .init(cropToFace: false, removeBackground: false), cachedRaster: nil,
      strokeStyle: pen, vectorOptions: options))
    let direct = try PortraitVectorizer.program(from: result.raster, pose: .front, style: .flowEdges,
      strokeStyle: pen, vectorOptions: options)
    #expect(result.program == direct)
  }

  @Test("Next varies shared coordinates while regional Next freezes global drawing intent")
  func proposals() throws {
    let raster = try regionalFixture()
    let options = PortraitVectorOptions(drawingParameters: .init())
    for style in [PortraitStyle.contours, .flowEdges] {
      let recipe = PortraitStyleRecipe(id: "shared", title: "Shared", seed: 0, style: style,
        vectorOptions: options, analysisOptions: .init())
      let program = try PortraitVectorizer.program(from: raster, pose: .front, style: style,
        strokeStyle: portraitTestStyle(), vectorOptions: options)
      let center = try PortraitCandidate(sourceData: Data([1]), sourcePixelExtent: nil, raster: raster,
        recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), pose: .front)
      let next = PortraitExplorationPolicy.recipe(around: center, seed: 918)
      #expect(next.vectorOptions.drawingParameters != options.drawingParameters)
      #expect(next.vectorOptions.contourLevels == options.contourLevels)
      #expect(next.vectorOptions.tonalStrength == options.tonalStrength)
      let regional = PortraitExplorationPolicy.regionalRecipe(around: center, region: .eyes, seed: 918, attempt: 0)
      #expect(regional.vectorOptions.drawingParameters == options.drawingParameters)
      #expect(regional.vectorOptions.treatment(for: .eyes) != options.treatment(for: .eyes))
    }
  }

  @Test("Historical shared geometry survives conversion to independent native controls",
    arguments: [PortraitStyle.contours, .flowEdges])
  func nativeConversion(style: PortraitStyle) throws {
    let raster = try regionalFixture()
    var original = PortraitVectorOptions(drawingParameters: .init(detail: 0.65, tone: 1.2,
      smoothness: 0.35, minimumLine: 0.02))
    original.setTreatment(.init(scope: .eyes, angularity: 0.3))
    let converted = original.nativeOptions(rasterHeight: raster.height)
    #expect(converted.drawingParameters == nil)
    #expect(converted.regionalAdjustments == original.regionalAdjustments)
    let shared = try PortraitVectorizer.program(from: raster, pose: .front, style: style,
      strokeStyle: portraitTestStyle(), vectorOptions: original)
    let native = try PortraitVectorizer.program(from: raster, pose: .front, style: style,
      strokeStyle: portraitTestStyle(), vectorOptions: converted)
    #expect(native.strokes.map(\.path) == shared.strokes.map(\.path))
    #expect(original.drawingParameters != nil)
  }





  @Test("Native Next and recovery vary only controls used by their renderer",
    arguments: [PortraitStyle.contours, .flowEdges, .sketch])
  func nativeProposals(style: PortraitStyle) throws {
    let raster = portraitTestRaster()
    let options = PortraitVectorOptions(drawingParameters: .init(detail: 0.6))
    let native = options.nativeOptions(rasterHeight: raster.height)
    let recipe = PortraitStyleRecipe(id: "shared-center", title: "Shared", seed: 0, style: style,
      vectorOptions: options, analysisOptions: .init())
    let center = try PortraitCandidate(sourceData: Data([1]), sourcePixelExtent: nil, raster: raster,
      recipe: recipe, program: PortraitVectorizer.program(from: raster, pose: .front, style: style,
        strokeStyle: portraitTestStyle(), vectorOptions: options), photoID: UUID(), captureSessionID: UUID(), pose: .front)
    var proposals: [PortraitVectorOptions] = []
    for seed in 0..<96 {
      let next = PortraitExplorationPolicy.nativeRecipe(around: center, seed: UInt64(seed))
      #expect(next.vectorOptions.drawingParameters == nil)
      let recovery = PortraitExplorationPolicy.nativeRecoveryRecipe(around: center, failed: next,
        rejection: .noLines, neighbor: 0, seed: UInt64(seed), variation: 0.35)
      #expect(recovery.vectorOptions.drawingParameters == nil)
      for value in [next.vectorOptions, recovery.vectorOptions] {
        if style == .contours {
          #expect(value.hatchSpacing == native.hatchSpacing)
          #expect(value.sketchThreshold == native.sketchThreshold)
        } else {
          #expect(value.contourLevels == native.contourLevels)
          if style == .flowEdges { #expect(value.simplificationTolerance == native.simplificationTolerance) }
        }
      }
      proposals.append(next.vectorOptions)
    }
    if style == .contours { #expect(proposals.contains { $0.contourLevels != native.contourLevels }) }
    if style == .flowEdges {
      #expect(proposals.contains { $0.hatchSpacing != native.hatchSpacing })
      #expect(proposals.contains { $0.sketchThreshold != native.sketchThreshold })
    }
    #expect(center.recipe == recipe)
  }



}

private actor ApplicablePortraitRasterRenderer: PortraitRendering {
  private var holdsNext = false
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func holdNext() { holdsNext = true }
  func waitUntilHeld() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while releaseWaiter == nil {
      try #require(ContinuousClock.now < deadline, "Renderer did not reach the held analysis.")
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { releaseWaiter?.resume(); releaseWaiter = nil }

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    if holdsNext {
      holdsNext = false
      await withCheckedContinuation { releaseWaiter = $0 }
    }
    let landscape = request.data == Data([2]) || !request.options.cropToFace
    let width = landscape ? 200 : 80, height = landscape ? 60 : 100
    let raster = PortraitRaster(width: width, height: height,
      luminance: (0..<(width * height)).map { Double($0 % width) / Double(width - 1) },
      provenance: "applicable-source-crop-fixture", analysisSummary: "Synthetic matching raster")
    return .init(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
