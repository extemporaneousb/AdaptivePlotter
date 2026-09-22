import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait cached candidate preparation")
@MainActor
struct PortraitCachedPreparationTests {
  @Test("restoring a cached setting prepares asynchronously without another renderer call")
  func cachedSetting() async throws {
    let renderer = CachedPreparationRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.style = .sketch
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.selectedCandidate)
    let original = model.vectorOptions
    model.vectorOptions.tonalStrength += 0.25
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.calls == 2)
    let previousWork = model.workDiagnostics.startedWorkerCount

    model.vectorOptions = original
    model.renderIfConfigurationChanged(strokeStyle: pen)
    // There has been no suspension: a cached candidate must not be hashed or
    // published synchronously on the UI actor during the setting callback.
    #expect(model.isProcessing)
    #expect(model.currentProgram == nil)
    await model.awaitRendering()

    #expect(await renderer.calls == 2)
    #expect(model.renderDiagnostics.startedWorkerCount == 2)
    #expect(model.renderCacheHits == 1)
    #expect(model.workDiagnostics.startedWorkerCount == previousWork + 1)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.workDiagnostics.startedWorkerCount == model.workDiagnostics.settledWorkerCount)
    #expect(model.selectedCandidate?.program == first.program)
    #expect(model.selectedCandidate?.photoID == first.photoID)
    #expect(!model.isProcessing)
    await model.shutdown()
  }

  @Test("source replacement supersedes a queued cached setting without publishing it")
  func supersededCachedSetting() async throws {
    let renderer = CachedPreparationRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.style = .sketch
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let original = model.vectorOptions
    model.vectorOptions.tonalStrength += 0.25
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()

    model.vectorOptions = original
    model.renderIfConfigurationChanged(strokeStyle: pen)
    #expect(model.isProcessing)
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    #expect(model.currentProgram == nil)
    #expect(model.algorithmCandidates.isEmpty)
    await model.awaitRendering()

    #expect(await renderer.calls == 3)
    #expect(model.selectedCandidate?.sourceData == Data([2]))
    #expect(model.selectedCandidate?.photoID == model.selectedPhotoID)
    #expect(model.algorithmCandidates.allSatisfy { $0.sourceData == Data([2]) })
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.workDiagnostics.startedWorkerCount == model.workDiagnostics.settledWorkerCount)
    await model.shutdown()
  }
}

private actor CachedPreparationRenderer: PortraitRendering {
  private(set) var calls = 0

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    calls += 1
    let raster = request.cachedRaster ?? portraitTestRaster()
    return PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
  }
}
