import AppKit
import Testing

@testable import PlotterApp

@Suite("Local application lifecycle")
struct ApplicationLifecycleTests {
  @Test("operator window has a stable restoration identifier")
  func singletonOperatorWindow() {
    #expect(AdaptivePlotterScenePolicy.singletonWindowID == "operator-workspace")
  }

  @Test("closing the last window terminates the local application")
  @MainActor
  func lastWindowCloseTerminates() {
    let delegate = AdaptivePlotterApplicationDelegate()

    #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
  }

  @Test("saved window state cannot suppress a fresh operator window")
  @MainActor
  func savedApplicationStateIsDisabled() {
    let delegate = AdaptivePlotterApplicationDelegate()

    #expect(!delegate.applicationShouldRestoreApplicationState(NSApplication.shared))
    #expect(!delegate.applicationShouldSaveApplicationState(NSApplication.shared))
  }

  @Test("workspace drain has a bounded application-termination deadline")
  @MainActor
  func applicationTerminationIsBounded() {
    #expect(
      AdaptivePlotterApplicationDelegate.terminationDeadlineNanoseconds
        == 3_000_000_000
    )
  }
}
