import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Learned overlay presentation")
struct LearnedOverlayPresentationTests {
  @Test("learned geometry uses explicit non-measurement semantics")
  func learnedLabels() {
    #expect(
      ActionSurfaceOverlayPresentationGrammar.semanticLabel(
        for: .calibratedDrawableRegion
      ) == "CALIBRATED DRAWABLE REGION"
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

  @Test("drawable paper and predicted-contact overlays remain visually distinct")
  func distinctStyles() {
    let tokens = Set([
      ActionSurfaceOverlayPresentationGrammar.styleToken(for: .calibratedDrawableRegion),
      ActionSurfaceOverlayPresentationGrammar.styleToken(for: .paperCoverage),
      ActionSurfaceOverlayPresentationGrammar.styleToken(for: .predictedContactPoint),
    ])

    #expect(tokens.count == 3)
    #expect(
      ActionSurfaceOverlayPresentationGrammar.styleToken(for: .predictedContactPoint)
        != ActionSurfaceOverlayPresentationGrammar.styleToken(for: .observedInk)
    )
  }
}
