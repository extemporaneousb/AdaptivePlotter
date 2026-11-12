import Foundation
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Permanent canvas")
struct WorkbenchCanvasTests {
  @Test("last plotter image remains visible regardless of freshness, while missing video falls back")
  func sourceSelection() {
    #expect(WorkbenchCanvasContent.select(plotterFrameAvailable: false) == .simulationPreview)
    #expect(WorkbenchCanvasContent.select(plotterFrameAvailable: true) == .plotter)
  }

  @MainActor
  @Test("fallback image leaves live execution, Learning and semantic publications unchanged")
  func fallbackHasNoOperationalEffects() async throws {
    let application = makeCausalSimulatorAppFixture().workspace
    // Compose and settle the existing Draft -> Run publication chain before
    // taking the baseline. Rendering awaits must not include fixture startup.
    await application.drawingDraftSynchronizationTask?.value
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
