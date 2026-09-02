import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Learned overlay presentation")
struct LearnedOverlayPresentationTests {
  @Test("learned geometry uses explicit non-measurement semantics")
  func learnedLabels() {
    #expect(
      ActionSurfaceOverlayPresentationGrammar.semanticLabel(
        for: .drawingBorder
      ) == "DRAWING BORDER · 10 MM INSET"
    )
    #expect(
      ActionSurfaceOverlayPresentationGrammar.semanticLabel(
        for: .acceptedBoundary
      ) == "ACCEPTED DRAWING BOUNDARY"
    )
    #expect(
      ActionSurfaceOverlayPresentationGrammar.semanticLabel(
        for: .predictedContactPoint
      ) == "PREDICTED CONTACT POINT · NOT OBSERVED"
    )
    #expect(
      ActionSurfaceOverlayPresentationGrammar.semanticLabel(for: .paperCoverage)
        == "CURRENT PAPER COVERAGE"
    )
  }
}
