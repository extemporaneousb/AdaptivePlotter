import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("production simulator renders both prior and accepted-model variants")
func productionSimulatorVariantsRender() async throws {
  #expect(SimulatorModelMode.trained.rawValue == "ACCEPTED MODEL")

  let prior = try await CameraComposition.actions.simulatedContent(.prior)
  let trained = try await CameraComposition.actions.simulatedContent(.trained)

  #expect(prior.displayedFrame.source == .simulated)
  #expect(trained.displayedFrame.source == .simulated)
  #expect(prior.displayedFrame.frame.id != trained.displayedFrame.frame.id)
  #expect(!prior.overlays.isEmpty)
  #expect(!trained.overlays.isEmpty)
  #expect(prior.evidenceLabel == SimulatedOverlaySceneContent.evidenceLabel)
  #expect(trained.evidenceLabel == SimulatedOverlaySceneContent.evidenceLabel)
  #expect(trained.learningSummary.contains("accepted"))
}
