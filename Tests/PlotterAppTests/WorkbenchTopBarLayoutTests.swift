import Testing

@testable import PlotterApp

@Suite("Native workbench toolbar")
struct WorkbenchTopBarLayoutTests {
  @Test("simulated mode keeps the controller slot without serial selection")
  func simulatedControllerSlotPreservesToolbarOrder() {
    let live = WorkbenchControllerSlotPresentation(mode: .live)
    let simulated = WorkbenchControllerSlotPresentation(mode: .simulated)

    #expect(live.title == "Controller")
    #expect(live.isSerialSelectionEnabled)
    #expect(simulated.title == "Learning Simulator")
    #expect(!simulated.isSerialSelectionEnabled)
  }

  @Test("motion authorization labels follow authorization")
  func motionAuthorizationActionTracksAuthorization() {
    let enable = WorkbenchMotionAuthorizationActionPresentation(isAuthorized: false)
    let disable = WorkbenchMotionAuthorizationActionPresentation(isAuthorized: true)

    #expect(enable.title == "Enable Motion & Raise Pen")
    #expect(disable.title == "Disable Motion")
  }

  @Test("disabled Motion exposes its full reason as visible toolbar text")
  func motionUnavailableReasonIsVisibleText() throws {
    let reason =
      "Connect the selected controller before enabling motion. Resolve Alarm if it remains blocked."
    let presentation = try #require(WorkbenchMotionUnavailablePresentation(reason))

    #expect(presentation.text == reason)
    #expect(WorkbenchMotionUnavailablePresentation(nil) == nil)
    #expect(WorkbenchMotionUnavailablePresentation("") == nil)
  }

  @Test("connection labels retain their exact semantic action")
  func controllerConnectionActionOwnsItsColor() {
    let connect = WorkbenchConnectionActionPresentation(action: .connect)
    let disconnect = WorkbenchConnectionActionPresentation(action: .disconnect)

    #expect(connect.title == "Connect")
    #expect(disconnect.title == "Disconnect")
  }
}
