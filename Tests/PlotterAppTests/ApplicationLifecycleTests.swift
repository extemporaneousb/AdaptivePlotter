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

  @Test("launch policy recognizes only the explicit nonpersistent simulated argument")
  func launchPolicy() {
    #expect(AdaptivePlotterLaunchPolicy(arguments: []).startupRoute == .preferredCamera)
    #expect(
      AdaptivePlotterLaunchPolicy(arguments: ["AdaptivePlotter"]).startupRoute
        == .preferredCamera
    )
    #expect(
      AdaptivePlotterLaunchPolicy(arguments: [
        "AdaptivePlotter", "-AdaptivePlotterStartSimulated", "YES",
      ]).startupRoute == .simulated
    )
    #expect(
      AdaptivePlotterLaunchPolicy(arguments: [
        "AdaptivePlotter", "-AdaptivePlotterStartSimulated", "NO",
      ]).startupRoute == .preferredCamera
    )
  }

  @Test("simulated startup bypasses camera discovery selection and start")
  @MainActor
  func simulatedStartupIsCameraSafe() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)
    let policy = AdaptivePlotterLaunchPolicy(arguments: [
      "AdaptivePlotter", "-AdaptivePlotterStartSimulated", "YES",
    ])

    await workspace.performApplicationStartup(policy)

    #expect(camera.startupActionCounts.discover == 0)
    #expect(camera.startupActionCounts.select == 0)
    #expect(camera.startupActionCounts.start == 0)
    #expect(workspace.frameMode == .simulated)
    #expect(workspace.displayedFrame?.source == .simulated)
    #expect(workspace.overlayStatus(for: .penCap).state == .available)
    #expect(
      workspace.overlayStatus(for: .penCap).message.contains("causal simulated pen-cap geometry")
    )
    #expect(await log.values.isEmpty)
    await workspace.shutdown()
  }

  @Test("normal startup retains preferred-camera discovery and start")
  @MainActor
  func normalStartupRemainsCameraFirst() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(machine: machine, camera: camera, log: log)

    await workspace.performApplicationStartup(
      AdaptivePlotterLaunchPolicy(arguments: ["AdaptivePlotter"])
    )

    #expect(camera.startupActionCounts.discover == 1)
    #expect(camera.startupActionCounts.select == 0)
    #expect(camera.startupActionCounts.start == 1)
    #expect(workspace.frameMode == .live)
    #expect(workspace.displayedFrame?.source == .live(camera.device.id))
    #expect(await log.values.isEmpty)
    await workspace.shutdown()
  }
}
