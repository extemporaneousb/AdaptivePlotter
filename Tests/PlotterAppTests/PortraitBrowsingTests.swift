import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait frame and style browsing")
struct PortraitBrowsingTests {
  @Test("frame and style navigation are independent and revisits reuse exact cached drawings")
  @MainActor
  func independentBrowsing() async throws {
    let renderer = BrowsingRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.configureRecipes(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let firstID = try #require(model.selectedPhotoID)
    let firstProgram = try #require(model.currentProgram)
    model.setPhoto(Data([2]), for: .left, strokeStyle: pen)
    model.selectPhoto(try #require(model.recentPhotos.last?.id), strokeStyle: pen)
    await model.awaitRendering()
    let config = model.renderConfiguration
    let initialCalls = await renderer.calls
    model.movePhoto(by: -1, strokeStyle: pen)
    #expect(model.selectedPhotoID == firstID)
    #expect(model.renderConfiguration == config)
    #expect(model.currentProgram == firstProgram)
    #expect(!model.isProcessing)
    #expect(await renderer.calls == initialCalls)
    model.moveStyle(by: 1, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedPhotoID == firstID)
    let recipe = model.currentRecipe
    let recipeProgram = try #require(model.currentProgram)
    model.movePhoto(by: 1, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.currentRecipe == recipe)
    model.movePhoto(by: -1, strokeStyle: pen)
    #expect(model.currentProgram == recipeProgram)
    #expect(model.renderCacheHits >= 2)
    await model.shutdown()
  }

  @Test("manual edits cannot grade or expose the prior drawing before their render request")
  @MainActor
  func staleCandidateAdmission() async throws {
    let model = PortraitStudioModel(renderer: BrowsingRenderer())
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.rateCurrent(4) == nil)
    let previous = try #require(model.preferences.examples.first)
    model.vectorOptions.hatchSpacing += 1
    #expect(model.currentProgram == nil)
    #expect(model.rateCurrent(5) != nil)
    #expect(model.preferences.examples.count == 1)
    model.renderIfNeeded(strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.rateCurrent(5) == nil)
    #expect(model.preferences.examples.count == 2)
    #expect(model.preferences.examples.last?.recipe.vectorOptions.hatchSpacing != previous.recipe.vectorOptions.hatchSpacing)
    let id = try #require(model.selectedPhotoID)
    model.removePhoto(id, strokeStyle: pen)
    #expect(model.currentProgram == nil)
    #expect(model.rateCurrent(2) != nil)
    // Rated examples deliberately retain their own exact source until removed.
    #expect(model.preferences.examples.first?.photoData == Data([1]))
    await model.shutdown()
  }

  @Test("random styles retain custom edits in bounded history and big-head candidates keep the frame")
  @MainActor
  func boundedHistory() async throws {
    let model = PortraitStudioModel(renderer: BrowsingRenderer())
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let source = model.selectedPhotoID
    let config = model.renderConfiguration
    model.randomStyle(strokeStyle: pen, bigHead: true)
    #expect(model.selectedPhotoID == source)
    #expect(model.vectorOptions.headScale > 1)
    model.moveStyle(by: -1, strokeStyle: pen)
    #expect(model.renderConfiguration == config)
    let named = try #require(model.styleRecipes.first)
    model.applyRecipe(named, strokeStyle: pen)
    model.randomStyle(strokeStyle: pen)
    model.moveStyle(by: -1, strokeStyle: pen)
    #expect(model.currentRecipe == named)
    for _ in 0..<30 {
      model.vectorOptions.minimumContourLength = 13.123
      model.randomStyle(strokeStyle: pen)
      #expect(model.styleRecipes.count <= 24)
    }
    await model.awaitRendering()
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("saved sketches grade their original source and explicit thumbnail selection returns to editing")
  @MainActor
  func savedSketchSource() async throws {
    let model = PortraitStudioModel(renderer: BrowsingRenderer())
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let source = try #require(model.selectedPhotoID)
    #expect(model.keepSelection() == nil)
    let candidateID = try #require(model.selectedCandidate?.id)
    #expect(model.rateSelection(5) == nil)
    #expect(model.preferences.examples.last?.photoID == source)
    model.selectPhoto(source, strokeStyle: pen)
    #expect(model.sketches.selected == nil)
    #expect(model.keepSelection() == nil)
    model.removePhoto(source, strokeStyle: pen)
    #expect(model.canRateSelection)
    #expect(model.rateSelection(4) == nil)
    #expect(model.selectedCandidate?.sourceData == Data([1]))
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let replacement = try #require(model.selectedPhotoID)
    model.selectPhoto(replacement, strokeStyle: pen)
    #expect(model.keepSelection() == nil)
    #expect(model.sketches.entries.count == 1)
    #expect(model.sketches.selectedID == candidateID)
    // Identical content deduplicates without rewriting the retained provenance.
    #expect(model.sketches.selected?.photoID == source)
    #expect(model.rateSelection(3) == nil)
    #expect(model.preferences.examples.count == 3)
    #expect(model.preferences.examples.map(\.rating) == [5, 4, 3])
    await model.shutdown()
  }

  @Test("generation is transient and successful projection retains the pre-await candidate")
  @MainActor
  func projectionQualification() async throws {
    let model = PortraitStudioModel(renderer: BrowsingRenderer())
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let accepted = try #require(model.selectedCandidate)
    #expect(model.sketches.entries.isEmpty)
    let refused = await model.acceptProjection(accepted) { "Fit refused" }
    #expect(refused == "Fit refused")
    #expect(model.sketches.entries.isEmpty)
    let result = await model.acceptProjection(accepted) {
      model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
      await model.awaitRendering()
      return nil
    }
    #expect(result == nil)
    #expect(model.sketches.entries.count == 1)
    #expect(model.sketches.entries.first?.candidate.id == accepted.id)
    #expect(model.sketches.entries.first?.candidate.sourceData == Data([1]))
    #expect(model.sketches.labels.isEmpty)
    await model.shutdown()
  }

  @Test("labels preserve the actual displayed size and ink context independently of later controls")
  @MainActor
  func presentationContext() async throws {
    let model = PortraitStudioModel(renderer: BrowsingRenderer())
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let narrow = try PortraitPresentationContext(drawingHeightMM: 73, inkWidthMM: 0.3)
    let wide = try PortraitPresentationContext(drawingHeightMM: 140, inkWidthMM: 1.2)
    #expect(model.rateSelection(1, presentation: narrow) == nil)
    #expect(model.rateSelection(5, presentation: wide) == nil)
    #expect(model.sketches.entries.count == 1)
    #expect(model.sketches.labels.map(\.presentation) == [narrow, wide])
    #expect(model.sketches.labels.last?.previousRevisionID == model.sketches.labels.first?.id)
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
    let raster = PortraitRaster(width: 16, height: 16, luminance: Array(repeating: 0.15, count: 256),
      provenance: "browsing-\(request.data.first ?? 0)", analysisSummary: "fixture")
    return PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: .hatch, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
