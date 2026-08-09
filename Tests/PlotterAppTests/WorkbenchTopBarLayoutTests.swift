import Testing

@testable import PlotterApp

@Suite("Native workbench toolbar")
struct WorkbenchTopBarLayoutTests {
  @Test("toolbar owns camera plotter and motion indicators")
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
      WorkbenchConnectionIndicator.motionGuard.label(isActive: true) == "Motion Enabled"
    )
    #expect(
      WorkbenchConnectionIndicator.motionGuard.label(isActive: false) == "Motion Disabled"
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

  @Test("enabled authorization is not rewritten by transient request state")
  func motionAuthorizationRemainsTruthfulWhileBusy() {
    let authorizationLabel = WorkbenchConnectionIndicator.motionGuard.label(isActive: true)
    let requestState = MotionRequestStatusPresentation.busy(
      "The current controller operation is settling."
    )

    #expect(authorizationLabel == "Motion Enabled")
    #expect(requestState.label == "Busy")
    #expect(requestState.detail == "The current controller operation is settling.")
  }

  @Test("request faults project Needs Attention separately from authorization")
  func requestAttentionIsSeparate() {
    let authorizationLabel = WorkbenchConnectionIndicator.motionGuard.label(isActive: true)
    let requestState = MotionRequestStatusPresentation.needsAttention(
      "Controller Alarm blocks a carriage request."
    )

    #expect(authorizationLabel == "Motion Enabled")
    #expect(requestState.label == "Needs Attention")
    #expect(requestState.detail == "Controller Alarm blocks a carriage request.")
  }

  @Test("simulated mode keeps the controller slot without serial selection")
  func simulatedControllerSlotPreservesToolbarOrder() {
    let live = WorkbenchControllerSlotPresentation(mode: .live)
    let simulated = WorkbenchControllerSlotPresentation(mode: .simulated)

    #expect(live.title == "Controller")
    #expect(live.isSerialSelectionEnabled)
    #expect(simulated.title == "Learning Simulator")
    #expect(!simulated.isSerialSelectionEnabled)
  }
}
