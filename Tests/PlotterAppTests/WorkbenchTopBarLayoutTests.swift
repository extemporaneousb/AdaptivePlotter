import Testing

@testable import PlotterApp

@Suite("Workbench top bar layout")
struct WorkbenchTopBarLayoutTests {
  @Test("bar is flush with the window content top edge")
  func barHasNoExternalTopInset() {
    #expect(WorkbenchTopBarLayoutMetrics.externalTopInset == 0)
  }

  @Test("flush placement does not remove useful internal spacing")
  func contentRetainsInternalPadding() {
    #expect(WorkbenchTopBarLayoutMetrics.horizontalContentPadding > 0)
    #expect(WorkbenchTopBarLayoutMetrics.verticalContentPadding > 0)
    #expect(WorkbenchTopBarLayoutMetrics.rowSpacing > 0)
  }

  @Test("persistent facts distinguish controller link from motion permission")
  func statusFactsAreTruthfulAndCompact() {
    #expect(
      WorkbenchTopBarStatusFact.allCases == [
        .source,
        .camera,
        .frame,
        .link,
        .motor,
        .motion,
        .operation,
      ]
    )
  }

  @Test("persistent status attention uses an actionable warning symbol")
  func statusSymbolReflectsAttention() {
    #expect(
      WorkbenchTopBarStatusStyle.systemImage(needsAttention: true)
        == "exclamationmark.triangle"
    )
    #expect(
      WorkbenchTopBarStatusStyle.systemImage(needsAttention: false)
        == "info.circle"
    )
  }
}
