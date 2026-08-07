import Testing

@testable import PlotterApp

@Suite("Native workbench toolbar")
struct WorkbenchTopBarLayoutTests {
  @Test("toolbar owns camera, plotter, and explicit motion guard indicators")
  func connectionIndicatorsAreFocused() {
    #expect(WorkbenchConnectionIndicator.allCases == [.camera, .plotter, .motionGuard])
    #expect(WorkbenchConnectionIndicator.camera.title == "Camera")
    #expect(WorkbenchConnectionIndicator.plotter.title == "Plotter")
    #expect(WorkbenchConnectionIndicator.motionGuard.title == "Motion")
  }

  @Test("connection labels never imply a false positive")
  func connectionLabelsTrackTheirBooleanEvidence() {
    #expect(WorkbenchConnectionIndicator.camera.label(isActive: true) == "Camera Live")
    #expect(WorkbenchConnectionIndicator.camera.label(isActive: false) == "Camera Off")
    #expect(WorkbenchConnectionIndicator.plotter.label(isActive: true) == "Plotter Connected")
    #expect(
      WorkbenchConnectionIndicator.plotter.label(isActive: false) == "Plotter Disconnected"
    )
    #expect(
      WorkbenchConnectionIndicator.motionGuard.label(isActive: true) == "Motion Ready"
    )
    #expect(
      WorkbenchConnectionIndicator.motionGuard.label(isActive: false) == "Motion Blocked"
    )
  }

  @Test("persistent status attention uses an actionable warning symbol")
  func statusSymbolReflectsAttention() {
    #expect(
      WorkbenchTopBarStatusStyle.systemImage(needsAttention: true)
        == "exclamationmark.triangle.fill"
    )
    #expect(
      WorkbenchTopBarStatusStyle.systemImage(needsAttention: false)
        == "info.circle"
    )
  }
}
