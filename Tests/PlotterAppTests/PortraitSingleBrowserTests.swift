import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Single portrait browser")
@MainActor
struct PortraitSingleBrowserTests {
  @Test("opening modes is idle and Next creates at most one retained result")
  func boundedDemandAndExactNavigation() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 918)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.selectedCandidate)
    let initialCalls = await renderer.requests.count
    let initialAttempts = model.sketches.attempts.count
    model.selectStudioMode(.explorer, strokeStyle: pen)
    await model.awaitRendering()
    #expect(await renderer.requests.count == initialCalls)
    #expect(model.explorationRound == nil)
    model.nextPortrait(strokeStyle: pen)
    #expect(model.selectedCandidate?.id == first.id)
    await model.awaitRendering()
    let next = try #require(model.selectedCandidate)
    #expect(next.id != first.id)
    #expect(next.recipe.style == first.recipe.style)
    #expect(model.sketches.attempts.count == initialAttempts + 1)
    let completedCalls = await renderer.requests.count
    #expect(completedCalls - initialCalls <= PortraitExplorationPolicy.maximumAttemptsPerSlot)
    #expect(!model.isExploring)
    #expect(model.canGoBackExploration)
    model.previousPortrait()
    #expect(model.selectedCandidate?.id == first.id)
    #expect(model.selectedCandidate?.program == first.program)
    #expect(model.canGoForwardPortrait)
    model.nextPortrait(strokeStyle: pen)
    #expect(model.selectedCandidate?.id == next.id)
    #expect(model.selectedCandidate?.program == next.program)
    await model.awaitRendering()
    #expect(await renderer.requests.count == completedCalls)
    var navigationMS: [Double] = []
    for _ in 0..<20 {
      let started = ProcessInfo.processInfo.systemUptime
      model.previousPortrait()
      model.nextPortrait(strokeStyle: pen)
      navigationMS.append((ProcessInfo.processInfo.systemUptime - started) * 1000 / 2)
    }
    print("Single portrait retained navigation: mean=\(navigationMS.reduce(0, +) / Double(navigationMS.count)) ms, max-pair-per-step=\(navigationMS.max() ?? 0) ms; excludes paint")
    #expect(await renderer.requests.count == completedCalls)
    #expect(model.keepSelection() == nil)
    await model.shutdown()
  }

  @Test("cancel and Contour selection cannot publish an obsolete next result")
  func cancelLateCompletion() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 918)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.selectedCandidate)
    let count = model.sketches.attempts.count
    model.selectStudioMode(.explorer, strokeStyle: pen)
    await renderer.holdNext()
    model.nextPortrait(strokeStyle: pen)
    try await renderer.waitUntilHeld()
    model.selectStudioMode(.contour, strokeStyle: pen)
    #expect(!model.isExploring)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == first.id)
    #expect(model.sketches.attempts.count == count)
    #expect(!model.canGoBackExploration)
    await model.shutdown()
  }

  @Test("exhausted single search keeps the drawing and does not archive failed probes")
  func exhaustedSearch() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.selectedCandidate)
    let count = model.sketches.attempts.count
    let calls = await renderer.requests.count
    await renderer.rejectFutureRequests()
    model.nextPortrait(strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == first.id)
    #expect(model.sketches.attempts.count == count)
    #expect(model.singlePortraitStatus != nil)
    #expect(!model.isExploring)
    #expect(await renderer.requests.count - calls <= PortraitExplorationPolicy.maximumAttemptsPerSlot)
    await model.shutdown()
  }

  @Test("similar geometry probes do not grow history")
  func similarProbesStayTransient() async throws {
    let model = PortraitStudioModel(renderer: UnchangedPortraitRenderer())
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.selectedCandidate)
    let count = model.sketches.attempts.count
    model.nextPortrait(strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.selectedCandidate?.id == first.id)
    #expect(model.sketches.attempts.count == count)
    #expect(model.explorationRejections["similarGeometry", default: 0] > 0)
    #expect(model.singlePortraitStatus != nil)
    await model.shutdown()
  }

  @Test("history navigation across source poses preserves Forward without rendering")
  func crossSourceNavigation() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let pen = try portraitTestStyle()
    model.pose = .left
    model.setPhoto(Data([1]), for: .left, strokeStyle: pen)
    await model.awaitRendering()
    let first = try #require(model.selectedCandidate)
    model.pose = .right
    model.setPhoto(Data([2]), for: .right, strokeStyle: pen)
    await model.awaitRendering()
    let second = try #require(model.selectedCandidate)
    let calls = await renderer.requests.count
    model.inspectAttempt(first.id, strokeStyle: pen)
    #expect(model.selectedCandidate?.id == first.id)
    model.previousPortrait()
    #expect(model.selectedCandidate?.id == second.id)
    #expect(model.canGoForwardPortrait)
    model.nextPortrait(strokeStyle: pen)
    #expect(model.selectedCandidate?.id == first.id)
    await model.awaitRendering()
    #expect(await renderer.requests.count == calls)
    await model.shutdown()
  }

  @Test("editing after Back abandons forward demand without rerendering a retained result")
  func branchInvalidation() async throws {
    let renderer = ExplorationTestRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 918)
    let pen = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    model.nextPortrait(strokeStyle: pen)
    await model.awaitRendering()
    #expect(model.canGoBackExploration)
    model.previousPortrait()
    #expect(model.canGoForwardPortrait)
    model.vectorOptions.smoothing += 0.2
    model.renderIfConfigurationChanged(strokeStyle: pen)
    #expect(!model.canGoForwardPortrait)
    await model.awaitRendering()
    #expect(!model.isExploring)
    await model.shutdown()
  }
}

private actor UnchangedPortraitRenderer: PortraitRendering {
  private var retained: PortraitRenderResult?
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    if let retained { return retained }
    let raster = portraitTestRaster()
    let result = PortraitRenderResult(raster: raster, program: try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions))
    retained = result
    return result
  }
}
