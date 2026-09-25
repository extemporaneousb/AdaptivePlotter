import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Material adaptation production integration")
@MainActor
struct PortraitMaterialIntegrationTests {
  @Test("explicit material adaptation retains exact source analysis and preserves saved drawings")
  func immutableAdaptation() async throws {
    let renderer = MaterialRoutingRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([11]), for: .front, strokeStyle: pen)
    // Reproduce the historical renderer before retaining its candidate. New
    // capture/import intentionally defaults retired styles back to Flow Edge.
    model.style = .hatch
    model.render(strokeStyle: pen)
    await model.awaitRendering()
    let parent = try #require(model.selectedCandidate)
    #expect(parent.recipe.style == .hatch)
    #expect(model.keepSelection() == nil)
    let savedParent = try #require(model.sketches.entries.first { $0.id == parent.id })
    let priorSavedParent = try PortraitCandidateCoding.encoder().encode(savedParent)
    let priorIDs = Set(model.sketches.entries.map(\.id))
    let profile = try DrawingMaterialProfileRevision(name: "Nominal test marker", nominalWidthMM: 1.2)
    #expect(await model.applyMaterial(profile, drawingHeightMM: 20) == nil)
    let adapted = try #require(model.selectedCandidate)
    #expect(adapted.id != parent.id)
    #expect(adapted.lineage.parentID == parent.id)
    #expect(adapted.rasterSHA256 == parent.rasterSHA256)
    #expect(adapted.sourceData == parent.sourceData)
    #expect(adapted.recipe.vectorOptions.materialContext?.profile == profile)
    #expect(adapted.recipe.vectorOptions.materialContext?.drawingHeightMM == 20)
    #expect(adapted.program.contentHash != parent.program.contentHash)
    #expect(adapted.program.strokes.first?.style.nominalLineWidth == 1.2)
    #expect(try PortraitCandidateCoding.encoder().encode(
      #require(model.sketches.entries.first { $0.id == parent.id })) == priorSavedParent)
    #expect(model.sketches.sketches.map(\.id) == [parent.id])
    let adaptedAttempt = try #require(model.sketches.entries.first { $0.id == adapted.id })
    #expect(adaptedAttempt.reasons.isEmpty)
    #expect(adaptedAttempt.attempt?.feedback == .unknown)
    #expect(Set(model.sketches.entries.map(\.id)) == priorIDs.union([adapted.id]))
    model.renderIfConfigurationChanged(strokeStyle: pen)
    #expect(model.selectedCandidate?.id == adapted.id)
    #expect(model.selectedCandidate?.program == adapted.program)
    #expect(try PortraitCandidateCoding.encoder().encode(await renderer.requests.last?.cachedRaster) == PortraitCandidateCoding.encoder().encode(parent.raster))
    #expect(await model.applyMaterial(profile, drawingHeightMM: 40) == nil)
    let resized = try #require(model.selectedCandidate)
    #expect(resized.id != adapted.id)
    #expect(resized.lineage.parentID == adapted.id)
    #expect(adapted.recipe.vectorOptions.materialContext?.drawingHeightMM == 20)
    #expect(resized.recipe.vectorOptions.materialContext?.drawingHeightMM == 40)
    #expect(try PortraitCandidateCoding.encoder().encode(
      #require(model.sketches.entries.first { $0.id == parent.id })) == priorSavedParent)
    #expect(model.sketches.sketches.map(\.id) == [parent.id])
    let resizedAttempt = try #require(model.sketches.entries.first { $0.id == resized.id })
    #expect(resizedAttempt.reasons.isEmpty)
    #expect(resizedAttempt.attempt?.feedback == .unknown)
    #expect(Set(model.sketches.entries.map(\.id)) == priorIDs.union([adapted.id, resized.id]))
    await model.shutdown()
  }
}

private actor MaterialRoutingRenderer: PortraitRendering {
  var requests: [PortraitRenderRequest] = []
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    let raster = try request.cachedRaster ?? portraitPersistenceCandidate().raster
    return PortraitRenderResult(raster: raster,
      program: try PortraitVectorizer.program(from: raster, pose: request.pose, style: request.style,
        strokeStyle: request.strokeStyle, vectorOptions: request.vectorOptions))
  }
}
