import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Shared portrait drawing parameters")
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

  @Test("Cached Flow layers and direct vectorization consume the same resolved parameters")
  func cachedFlow() async throws {
    let parameters = PortraitDrawingParameters(detail: 0.8, tone: 1.4, smoothness: 0.2, minimumLine: 0.01)
    let options = PortraitVectorOptions(drawingParameters: parameters)
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

  @Test("Legacy feature fitting refuses shared recipes instead of reading inactive kernel fields")
  func legacyFeatureBoundary() throws {
    let (scope, _) = try portraitTrainingFixture(sourceCount: 1, samplesPerSource: 1)
    let options = PortraitVectorOptions(drawingParameters: .init())
    let recipe = PortraitStyleRecipe(id: "shared", title: "Shared", seed: 0, style: .hatch,
      vectorOptions: options, analysisOptions: .init())
    let raster = portraitTestRaster()
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
    let candidate = try PortraitCandidate(sourceData: Data([1]), sourcePixelExtent: nil, raster: raster,
      recipe: recipe, program: program, photoID: UUID(), captureSessionID: UUID(), pose: .front)
    do {
      try PortraitTrainingFeatures.validateCandidate(candidate, scope: scope)
      Issue.record("Legacy features accepted inactive kernel fields")
    } catch PortraitTrainingError.incompatible(let reason) {
      #expect(reason.contains("new feature schema"))
    }
  }

  @Test("Cancel preserves saved recipes and selection; style switching preserves shared and feature edits")
  @MainActor
  func cancelAndStyleSwitch() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 918)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.saveStyle(name: "Kept recipe")
    let saved = try #require(model.sketches.savedStyles.first)
    let candidate = try #require(model.selectedCandidate)
    await renderer.holdNext()
    model.nextPortrait(strokeStyle: pen)
    try await renderer.waitUntilHeld()
    #expect(model.isExploring)
    model.cancelPortraitStep()
    #expect(model.sketches.savedStyles.map(\.id) == [saved.id])
    #expect(model.sketches.savedStyles.first?.recipe == saved.recipe)
    #expect(model.selectedCandidate?.id == candidate.id)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.sketches.savedStyles.map(\.id) == [saved.id])
    #expect(model.sketches.savedStyles.first?.recipe == saved.recipe)
    #expect(model.selectedCandidate?.id == candidate.id)
    model.drawingParameters = .init(detail: 0.8, tone: 1.4, smoothness: 0.3, minimumLine: 0.02)
    model.vectorOptions.setTreatment(.init(scope: .eyes, angularity: 0.5))
    let shared = model.drawingParameters
    let regions = model.vectorOptions.regionalAdjustments
    model.selectStyle(.flowEdges, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.drawingParameters == shared)
    #expect(model.vectorOptions.regionalAdjustments == regions)
    model.applySavedStyle(saved, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.recipe == saved.recipe)
    await model.shutdown()
  }
}
