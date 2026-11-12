import Testing
import PlotterUI

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

  @Test("disabled Motion preserves its full reason for the toolbar warning")
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

  @Test("Plotter offers only execution and device panels")
  func executionPanels() {
    #expect(WorkbenchPanel.allCases.map(\.rawValue) == ["guidedLearning", "videoSettings", "motion", "activeLearning", "drawing"])
  }

  @Test("toolbar Saved Learning follows connection, motion and canonical action availability")
  func savedLearningToolbarPrerequisites() {
    // Intent is opaque to this presentation: availability must preserve the
    // canonical action's refusal after the toolbar-specific prerequisites.
    let available = PlotterUIAction(id: .init(rawValue: "test.savedLearning"),
      title: "Use Saved Learning", intent: .requestIncidentPackage)
    func project(_ action: PlotterUIAction? = available, mode: OperatorFrameMode = .live,
      selected: Bool = true, connected: Bool = true, authorized: Bool = true)
      -> WorkbenchSavedLearningPresentation {
      .init(action: action, environment: mode, controllerIsSelected: selected,
        sessionEstablished: connected, motionAuthorized: authorized)
    }
    #expect(project().isAvailable)
    #expect(project(nil).unavailableReason == "No Saved Learning package is available.")
    #expect(!project(mode: .simulated).isAvailable)
    #expect(project(selected: false).unavailableReason?.contains("Select a controller") == true)
    #expect(project(connected: false).unavailableReason?.contains("Connect") == true)
    #expect(project(authorized: false).unavailableReason == "Enable Motion & Raise Pen before using Saved Learning.")
    let refused = PlotterUIAction(id: available.id, title: available.title, intent: available.intent,
      unavailableReason: "Finish the active operation first.")
    #expect(project(refused).unavailableReason == refused.unavailableReason)
  }

}
