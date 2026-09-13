import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Semantic head production integration")
@MainActor
struct PortraitSemanticHeadIntegrationTests {
  @Test("explicit semantic generation refreshes legacy analysis once then local proposals reuse it exactly")
  func refreshAndFreezeAnalysis() async throws {
    let renderer = SemanticRoutingRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.style = .hatch
    model.setPhoto(Data([19]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = try #require(model.selectedCandidate)
    #expect(original.raster.faceAnalysis == nil)
    model.vectorOptions.semanticHead = PortraitSemanticHeadParameters()
    model.render(strokeStyle: pen)
    await model.awaitRendering()
    let semantic = try #require(model.selectedCandidate)
    #expect(await renderer.requests.last?.cachedRaster == nil)
    #expect(semantic.producerRevision == "portrait-v4")
    #expect(semantic.warpManifest?.status == .unavailable)
    #expect(semantic.raster.faceAnalysis?.status == .noFace)
    #expect(semantic.program.strokes.map(\.path) == original.program.strokes.map(\.path))
    #expect(semantic.id != original.id)
    #expect(model.keepSelection() == nil)
    model.removePhoto(semantic.photoID, strokeStyle: pen)
    model.moreLikeThis(seed: 82)
    await model.awaitRendering()
    let child = try #require(model.selectedCandidate)
    let request = try #require(await renderer.requests.last)
    #expect(request.cachedRaster?.faceAnalysis == semantic.raster.faceAnalysis)
    #expect(child.rasterSHA256 == semantic.rasterSHA256)
    #expect(child.recipe.vectorOptions.semanticHead == semantic.recipe.vectorOptions.semanticHead)
    #expect(child.warpManifest == semantic.warpManifest)
    #expect(model.sketches.entries.map(\.id) == [semantic.id])
    model.historyParent()
    #expect(model.selectedCandidate?.id == semantic.id)
    #expect(model.selectedCandidate?.program == semantic.program)
    await model.shutdown()
  }


}

private actor SemanticRoutingRenderer: PortraitRendering {
  var requests: [PortraitRenderRequest] = []
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    let fixture = try portraitPersistenceCandidate().raster
    let face = request.vectorOptions.semanticHead == nil ? nil : PortraitFaceLandmarkAnalyzer.retain(
      observations: [], width: fixture.width, height: fixture.height)
    let raster = request.cachedRaster ?? PortraitRaster(width: fixture.width, height: fixture.height,
      luminance: fixture.luminance, provenance: "semantic-routing-fixture", analysisSummary: "Synthetic source",
      faceAnalysis: face)
    let manifest = request.vectorOptions.semanticHead.map { PortraitHeadTransform(raster: raster, parameters: $0.bounded).manifest }
    return PortraitRenderResult(raster: raster,
      program: try PortraitVectorizer.program(from: raster, pose: request.pose, style: request.style,
        strokeStyle: request.strokeStyle, vectorOptions: request.vectorOptions),
      transformationSummary: manifest?.summary, warpManifest: manifest)
  }
}
