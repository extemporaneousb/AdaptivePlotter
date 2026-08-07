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

  @Test("top bar owns camera, plotter, and explicit motion guard indicators")
  func connectionIndicatorsAreFocused() {
    #expect(WorkbenchConnectionIndicator.allCases == [.camera, .plotter, .motionGuard])
  }

  @Test("connection labels never imply a false positive")
  func connectionLabelsTrackTheirBooleanEvidence() {
    #expect(WorkbenchConnectionIndicator.camera.label(isActive: true) == "CAMERA LIVE")
    #expect(WorkbenchConnectionIndicator.camera.label(isActive: false) == "CAMERA OFF")
    #expect(WorkbenchConnectionIndicator.plotter.label(isActive: true) == "PLOTTER CONNECTED")
    #expect(
      WorkbenchConnectionIndicator.plotter.label(isActive: false) == "PLOTTER DISCONNECTED"
    )
    #expect(
      WorkbenchConnectionIndicator.motionGuard.label(isActive: true) == "MOTION READY"
    )
    #expect(
      WorkbenchConnectionIndicator.motionGuard.label(isActive: false) == "MOTION BLOCKED"
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
