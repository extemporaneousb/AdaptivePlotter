import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait authoring")
@MainActor
struct PortraitAuthoringTests {
  @Test("authoring renders only the chosen algorithm for source, tuning and pen changes")
  func foldedWorkload() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .flowEdges
    model.vectorOptions = .flowDefaults
    let pen = try portraitTestStyle()
    model.style = .sketch
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 1)
    model.vectorOptions.simplificationTolerance += 0.2
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 2)
    let wider = try StrokeStyle(nominalLineWidth: 1.2, penProfileID: pen.penProfileID)
    model.renderIfNeeded(strokeStyle: wider)
    await model.awaitRendering()
    #expect(await renderer.requests.count == 3)
    model.setPhoto(Data([2]), for: .front, strokeStyle: wider)
    await model.awaitRendering()
    let requests = await renderer.requests
    #expect(requests.count == 4)
    #expect(requests.allSatisfy { $0.style == .sketch })
    #expect(requests[1].cachedRaster != nil && requests[2].cachedRaster != nil)
    #expect(model.selectedCandidate?.sourceData == Data([2]))
    await model.shutdown()
  }

  @Test("new eye and regional modifiers survive explicit prototype, local tuning and saved-style application")
  func newModifierRecipeApplications() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .flowEdges
    model.vectorOptions = .flowDefaults
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.applySavedStyle(.init(id: UUID(), name: "Fixture",
      recipe: PortraitPrototypeRecipe.landmarkExaggeration.recipe(), createdAt: Date()), strokeStyle: pen)
    await model.awaitRendering()
    let prototype = try #require(model.selectedCandidate)
    #expect(prototype.recipe.vectorOptions == PortraitPrototypeRecipe.landmarkExaggeration.options())
    #expect(prototype.recipe.vectorOptions.eyeExaggeration != nil)
    #expect(prototype.recipe.vectorOptions.regionalTreatment != nil)
    #expect(prototype.recipe.vectorOptions.headScale == 1)
    #expect(prototype.recipe.vectorOptions.semanticHead == nil)

    model.vectorOptions.regionalAdjustments = [.init(scope: .eyes, contourEmphasis: 0.45)]
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await model.awaitRendering()
    let layered = try #require(model.selectedCandidate)
    #expect(layered.recipe.vectorOptions.eyeExaggeration == prototype.recipe.vectorOptions.eyeExaggeration)
    #expect(layered.recipe.vectorOptions.regionalTreatment == prototype.recipe.vectorOptions.regionalTreatment)
    #expect(layered.recipe.vectorOptions.regionalAdjustments == model.vectorOptions.regionalAdjustments)
    model.saveStyle(name: "Measured eyes with contour")
    let saved = try #require(model.sketches.savedStyles.first)
    #expect(saved.recipe == layered.recipe)

    model.applySavedStyle(.init(id: UUID(), name: "Fixture",
      recipe: PortraitPrototypeRecipe.angularComic.recipe(), createdAt: Date()), strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.recipe.vectorOptions.eyeExaggeration == nil)
    model.applySavedStyle(saved, strokeStyle: pen)
    await model.awaitRendering()
    let restored = try #require(model.selectedCandidate)
    #expect(restored.recipe.vectorOptions == layered.recipe.vectorOptions)
    #expect(restored.program == layered.program)
    #expect(restored.sourceData == layered.sourceData)
    #expect(model.sketches.savedStyles.first?.recipe == saved.recipe)
    try restored.validateIntegrity()
    await model.shutdown()
  }

  @Test("saving and projection retain exact drawings without changing authoring selection")
  func retentionDoesNotNavigate() async throws {
    let model = PortraitStudioModel(renderer: ComparisonRenderer())
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let candidate = try #require(model.selectedCandidate)
    #expect(model.keepSelection() == nil)
    #expect(model.sketches.selectedID == nil)
    #expect(model.selectedCandidate?.id == candidate.id)
    #expect(await model.acceptProjection(candidate) { nil } == nil)
    #expect(model.sketches.selectedID == nil)
    #expect(model.projectedCandidate?.id == candidate.id)
    #expect(model.sketches.entries.map(\.id) == [candidate.id])
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.sketches.selectedID = candidate.id
    #expect(model.selectedPhoto == candidate.sourceData)
    #expect(model.selectedPhoto != model.recentPhotos.last?.data)
    await model.shutdown()
  }

  @Test("deleting a burst cancels its selected held render and does not resurrect its source")
  func deleteHeldBurst() async throws {
    let renderer = ComparisonRenderer(heldCall: 1)
    let model = PortraitStudioModel(renderer: renderer)
    model.style = .flowEdges
    model.vectorOptions = .flowDefaults
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.removeSelectedBurst(strokeStyle: pen)
    #expect(model.recentPhotos.isEmpty)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedPhoto == nil)
    #expect(model.currentProgram == nil)
    #expect(model.selectedCandidate == nil)
    #expect(await renderer.requests.count == 1)
    #expect(model.workDiagnostics.activeWorkerCount == 0)
    await model.shutdown()
  }
}

private actor ComparisonRenderer: PortraitRendering {
  private(set) var requests: [PortraitRenderRequest] = []
  private(set) var cancelledStyles: [PortraitStyle] = []
  private var heldCalls: Set<Int>
  private var waiter: CheckedContinuation<Void, Never>?

  init(heldCall: Int? = nil, heldCalls: Set<Int> = []) {
    self.heldCalls = heldCalls.union(heldCall.map { [$0] } ?? [])
  }

  func holdNextCall() { heldCalls.insert(requests.count + 1) }

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    let raster = request.cachedRaster ?? portraitTestRaster()
    let result = PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
    if heldCalls.contains(requests.count) {
      await withCheckedContinuation { waiter = $0 }
    }
    if Task.isCancelled { cancelledStyles.append(request.style) }
    // Return an already-completed result even after cancellation, so these
    // tests exercise the model's revision/source publication guards.
    return result
  }

  func waitUntilHeld() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while waiter == nil {
      try #require(ContinuousClock.now < deadline)
      try await Task.sleep(for: .milliseconds(1))
    }
  }

  func release() { waiter?.resume(); waiter = nil }
}
