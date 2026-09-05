import Testing

@testable import PlotterApp

@Suite("Workbench capability presentation")
struct WorkbenchCapabilityPresentationTests {
  @Test("learning capability vocabulary states exactly what has been established")
  func capabilityVocabulary() {
    #expect(WorkbenchLearningCapabilityState.mapReady.systemImage == "graduationcap")
    #expect(WorkbenchLearningCapabilityState.interactiveLearningComplete.systemImage == "graduationcap.fill")
    #expect(
      WorkbenchLearningCapabilityState.allCases.map(\.title) == [
        "Pen-tip calibration required",
        "Saved calibration needs revalidation",
        "Pen-tip calibration ready",
        "Learning complete",
        "Adaptive drawing ready",
      ]
    )
    #expect(
      WorkbenchLearningCapabilityState.interactiveLearningComplete.detail
        .contains("adaptive readiness is not established")
    )
    #expect(
      WorkbenchLearningCapabilityState.savedMapNeedsRevalidation.detail
        .contains("cannot be used")
    )
  }

  @Test("paper setup remains independent from map capability")
  func paperStatusIsIndependent() {
    let required = WorkbenchCapabilityPresentation(
      learning: .adaptiveDrawingReady,
      paper: .setupRequired(reason: "No current paper-coverage observation.")
    )
    let current = WorkbenchCapabilityPresentation(
      learning: .learningNeeded,
      paper: .current(detail: "Paper instance 7 has current coverage evidence.")
    )

    #expect(required.paper.title == "Paper setup required")
    #expect(required.paper.colorToken == .needsAttention)
    #expect(required.accessibilityValue.contains("No current paper-coverage observation"))
    #expect(current.paper.title == "Paper current")
    #expect(current.paper.colorToken == .available)
    #expect(current.learning == .learningNeeded)
  }
}
