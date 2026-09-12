import Foundation
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Permanent canvas")
struct WorkbenchCanvasTests {
  @Test("missing video falls back while frozen evidence and selected portrait images stay visible")
  func sourceSelection() {
    func select(portrait: Bool = false, video: Bool = false, photo: Bool = false,
      frame: Bool = false, retained: Bool = false, live: Bool = false, simulated: Bool = false) -> WorkbenchCanvasContent {
      .select(portrait: portrait, portraitVideoAvailable: video, portraitPhotoAvailable: photo,
        plotterFrameAvailable: frame, retainedPlotterFrame: retained, plotterLive: live, simulated: simulated)
    }
    #expect(select() == .simulationPreview)
    #expect(select(frame: true) == .simulationPreview)
    #expect(select(frame: true, live: true) == .plotter)
    #expect(select(frame: true, retained: true) == .plotter)
    #expect(select(frame: true, simulated: true) == .plotter)
    #expect(select(portrait: true, photo: true) == .portraitPhoto)
    #expect(select(portrait: true, video: true, photo: true) == .portraitVideo)
    #expect(select(portrait: true, frame: true, live: true) == .simulationPreview)
  }

  @MainActor
  @Test("fallback image leaves live execution, Learning and semantic publications unchanged")
  func fallbackHasNoOperationalEffects() async throws {
    let application = makeCausalSimulatorAppFixture().workspace
    let mode = application.frameMode
    let projection = application.testPlotterUIProjection(includesLearningPath: true).semantic
    let episode = application.learningEpisodeRecord
    let draft = application.drawingDraftSnapshot
    let before = application.semanticPresentationRevision
    let frame = try #require(await application.canvasSimulationPreview())
    guard case .simulated = frame.source else { Issue.record("Fallback must be identified as simulation"); return }
    #expect(application.frameMode == mode)
    #expect(application.semanticPresentationRevision == before)
    #expect(application.learningEpisodeRecord.entries == episode.entries)
    #expect(application.drawingDraftSnapshot == draft)
    #expect(application.testPlotterUIProjection(includesLearningPath: true).semantic.actions == projection.actions)
    await application.shutdown()
  }

  @Test("passive simulator rendering preserves causal frame counters")
  func previewDoesNotCapture() async throws {
    let runtime = SimulatedLearningRuntime()
    let before = await runtime.snapshot()
    _ = try await runtime.previewSceneFrame().get()
    _ = try await runtime.previewSceneFrame().get()
    #expect(await runtime.snapshot() == before)
  }
}
