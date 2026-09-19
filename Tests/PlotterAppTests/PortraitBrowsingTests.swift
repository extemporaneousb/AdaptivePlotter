import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Portrait source browsing and cache identity")
struct PortraitBrowsingTests {
  @Test("frame navigation preserves tuning and algorithm selection and reuses cached drawings")
  @MainActor
  func independentBrowsing() async throws {
    let renderer = BrowsingRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let firstID = try #require(model.selectedPhotoID)
    model.selectAlgorithm(.hatch, strokeStyle: pen)
    let firstProgram = try #require(model.currentProgram)
    model.setPhoto(Data([2]), for: .left, strokeStyle: pen)
    model.selectPhoto(try #require(model.recentPhotos.last?.id), strokeStyle: pen)
    await model.awaitRendering()
    let config = model.renderConfiguration
    let calls = await renderer.calls
    model.movePhoto(by: -1, strokeStyle: pen)
    #expect(model.selectedPhotoID == firstID)
    #expect(model.renderConfiguration == config)
    #expect(model.currentProgram == firstProgram)
    #expect(!model.isProcessing)
    #expect(await renderer.calls == calls)
    #expect(model.algorithmCandidates.map(\.recipe.style) == PortraitStyle.allCases)
    await model.shutdown()
  }

  @Test("manual edits disable save and projection admission until the exact result completes")
  @MainActor
  func staleCandidateAdmission() async throws {
    let model = PortraitStudioModel(renderer: BrowsingRenderer())
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let previous = try #require(model.completedCandidate)
    model.vectorOptions.hatchSpacing += 1
    #expect(model.currentProgram == nil)
    #expect(model.selectedCandidate == nil)
    #expect(model.keepSelection() != nil)
    #expect(model.sketches.entries.isEmpty)
    model.renderIfNeeded(strokeStyle: pen)
    #expect(model.completedCandidate?.id == previous.id)
    #expect(model.selectedCandidate == nil)
    await model.awaitRendering()
    #expect(model.keepSelection() == nil)
    #expect(model.sketches.entries.count == 1)
    #expect(model.sketches.entries.first?.candidate.recipe.vectorOptions.hatchSpacing
      != previous.recipe.vectorOptions.hatchSpacing)
    await model.shutdown()
  }

  @Test("render cache keys include analysis and pen style, and source removal invalidates every version")
  func cacheIdentityAndRemoval() throws {
    var cache = PortraitRenderCache()
    let source = UUID()
    let config = PortraitRenderConfiguration(style: .hatch, vectors: .init(), analysis: .init())
    let key = PortraitRenderCacheKey(photoID: source, configuration: config, strokeStyle: try portraitTestStyle())
    let raster = portraitTestRaster()
    let result = PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: .front, style: .hatch, strokeStyle: portraitTestStyle()))
    cache.insert(result, for: key)
    let otherPen = try StrokeStyle(nominalLineWidth: key.strokeStyle.nominalLineWidth + 1,
      penProfileID: key.strokeStyle.penProfileID)
    #expect(cache.result(for: .init(photoID: source, configuration: config, strokeStyle: otherPen)) == nil)
    var otherAnalysis = PortraitAnalysisOptions(); otherAnalysis.cropToFace = false
    #expect(cache.raster(for: .init(photoID: source, analysis: otherAnalysis)) == nil)
    #expect(cache.result(for: key)?.program == result.program)
    cache.remove(photoID: source)
    #expect(cache.result(for: key) == nil)
    #expect(cache.raster(for: .init(photoID: source, analysis: config.analysis)) == nil)
    for _ in 0..<40 {
      cache.insert(result, for: .init(photoID: UUID(), configuration: config, strokeStyle: key.strokeStyle))
    }
    #expect(cache.renders.count == PortraitRenderCache.maximumRenders)
    #expect(cache.renders.reduce(0) { total, item in
      total + item.1.program.strokes.reduce(0) { $0 + $1.path.points.count }
    } <= PortraitRenderCache.maximumPoints)
  }
}

private actor BrowsingRenderer: PortraitRendering {
  private(set) var calls = 0
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    calls += 1
    let basis = portraitTestRaster()
    let raster = request.cachedRaster ?? PortraitRaster(width: basis.width, height: basis.height,
      luminance: basis.luminance, provenance: "browsing-\(request.data.first ?? 0)",
      analysisSummary: "fixture")
    return PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
