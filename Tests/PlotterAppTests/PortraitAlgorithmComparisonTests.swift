import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait algorithm comparison")
@MainActor
struct PortraitAlgorithmComparisonTests {
  @Test("five deterministic algorithms share one source analysis and selecting installs the exact tile")
  func exactSelectionAndSharedAnalysis() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.vectorOptions.headScale = 1.4
    model.vectorOptions.semanticHead = .init()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.algorithmCandidates.map(\.recipe.style) == PortraitStyle.allCases)
    #expect(model.algorithmCandidates.allSatisfy { $0.sourceData == Data([1]) })
    #expect(Set(model.algorithmCandidates.map(\.rasterSHA256)).count == 1)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.checkpointID == nil && $0.proposal == nil && $0.warpManifest == nil
        && $0.recipe.vectorOptions.headScale == 1 && $0.recipe.vectorOptions.semanticHead == nil
    })
    let requests = await renderer.requests
    #expect(requests.count == PortraitStyle.allCases.count)
    #expect(requests.filter { $0.cachedRaster == nil }.count == 1)
    #expect(!model.hasSelectedAlgorithm)
    for tile in model.algorithmCandidates {
      model.selectAlgorithm(tile.recipe.style, strokeStyle: pen)
      model.renderIfConfigurationChanged(strokeStyle: pen)
      #expect(model.hasSelectedAlgorithm)
      #expect(model.selectedCandidate?.id == tile.id)
      #expect(model.selectedCandidate?.createdAt == tile.createdAt)
      #expect(model.currentProgram == tile.program)
      #expect(model.selectedPhoto == tile.sourceData)
      #expect(model.renderConfiguration == .init(style: tile.recipe.style,
        vectors: tile.recipe.vectorOptions, analysis: tile.recipe.analysisOptions))
    }
    // Returning to the Studio does not reset selection or enqueue more work.
    model.renderIfNeeded(strokeStyle: pen)
    #expect(await renderer.requests.count == requests.count)
    #expect(model.selectedAlgorithm == .sketchHatch)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(!model.isComparingAlgorithms)
    await model.shutdown()
  }

  @Test("source and framing supersession discard held work and all stale algorithm jobs")
  func supersededComparison() async throws {
    let renderer = ComparisonRenderer(heldCall: 1)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.options.cropToFace = false
    model.vectorOptions.hatchSpacing = 7
    model.renderIfConfigurationChanged(strokeStyle: pen)
    model.setPhoto(Data([2]), for: .front, strokeStyle: pen)
    #expect(model.algorithmCandidates.isEmpty)
    #expect(model.currentProgram == nil)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.algorithmCandidates.count == PortraitStyle.allCases.count)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.sourceData == Data([2]) && !$0.recipe.analysisOptions.cropToFace
        && $0.recipe.vectorOptions.hatchSpacing == 7
        && $0.photoID == model.selectedPhotoID
    })
    let requests = await renderer.requests
    #expect(requests.count == PortraitStyle.allCases.count + 1)
    #expect(requests.dropFirst().allSatisfy { $0.data == Data([2]) })
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.workDiagnostics.startedWorkerCount == model.workDiagnostics.settledWorkerCount)
    await model.shutdown()
  }

  @Test("late comparison tiles cannot change the selected drawing")
  func selectionDuringComparison() async throws {
    let renderer = ComparisonRenderer(heldCall: 3)
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    let tile = try #require(model.algorithmCandidates.first { $0.recipe.style == .hatch })
    model.selectAlgorithm(.hatch, strokeStyle: pen)
    model.renderIfConfigurationChanged(strokeStyle: pen)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == tile.id)
    #expect(model.selectedCandidate?.createdAt == tile.createdAt)
    #expect(model.currentProgram == tile.program)
    #expect(model.algorithmCandidates.count == 5)
    #expect(await renderer.requests.count == 5)
    await model.shutdown()
  }

  @Test("pen changes replace every algorithm result while preserving current source analysis")
  func penInvalidation() async throws {
    let renderer = ComparisonRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let oldIDs = model.algorithmCandidates.map(\.id)
    let wider = try StrokeStyle(nominalLineWidth: 1.2, penProfileID: pen.penProfileID)
    model.renderIfNeeded(strokeStyle: wider)
    #expect(model.algorithmCandidates.isEmpty)
    await model.awaitRendering()
    #expect(model.algorithmCandidates.count == 5)
    #expect(model.algorithmCandidates.map(\.id) != oldIDs)
    #expect(model.algorithmCandidates.allSatisfy {
      $0.program.strokes.allSatisfy { $0.style == wider }
    })
    let requests = await renderer.requests
    #expect(requests.count == 10)
    #expect(requests.dropFirst(5).allSatisfy { $0.cachedRaster != nil })
    let selected = model.selectedCandidate?.id
    model.selectAlgorithm(.hatch, strokeStyle: pen)
    #expect(model.selectedCandidate?.id == selected)
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
    let pen = try portraitTestStyle()
    model.renderIfNeeded(strokeStyle: pen)
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.removeSelectedBurst(strokeStyle: pen)
    #expect(model.algorithmCandidates.isEmpty)
    #expect(model.recentPhotos.isEmpty)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedPhoto == nil)
    #expect(model.currentProgram == nil)
    #expect(model.selectedCandidate == nil)
    #expect(model.algorithmCandidates.isEmpty)
    #expect(await renderer.requests.count == 1)
    #expect(!model.isComparingAlgorithms)
    #expect(model.workDiagnostics.activeWorkerCount == 0)
    await model.shutdown()
  }
}

private actor ComparisonRenderer: PortraitRendering {
  private(set) var requests: [PortraitRenderRequest] = []
  private let heldCall: Int?
  private var waiter: CheckedContinuation<Void, Never>?

  init(heldCall: Int? = nil) { self.heldCall = heldCall }

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    requests.append(request)
    let raster = request.cachedRaster ?? portraitTestRaster()
    let result = PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(from: raster,
      pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
    if requests.count == heldCall {
      await withCheckedContinuation { waiter = $0 }
    }
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
