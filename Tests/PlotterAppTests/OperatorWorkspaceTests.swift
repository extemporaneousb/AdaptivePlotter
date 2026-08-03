import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("Preview layers are ordinary presentation state")
@MainActor
func previewLayerVisibility() {
  let workspace = OperatorWorkspace()

  workspace.setLayer(.observed, visible: false)

  #expect(workspace.visibleLayers.contains(.observed) == false)
  #expect(workspace.visibleLayers.contains(.logical))
}

@Test("Passive probe requires explicit device selection")
@MainActor
func passiveProbeRequiresSelection() async {
  let workspace = OperatorWorkspace(passiveProbeRunner: { _ in
    Issue.record("Runner must not be called without explicit selection")
    throw TestProbeError.unexpectedCall
  })

  await workspace.requestPassiveProbe()

  #expect(workspace.passiveProbeResult == nil)
  #expect(
    workspace.passiveProbeFailure == "Select one serial device before requesting the passive probe."
  )
}

@Test("A passive probe can be retried without restarting the app")
@MainActor
func passiveProbeCanRetry() async {
  let device = MachineLinkDescriptor(
    identifier: "test-serial",
    displayName: "Test serial",
    bsdPath: "/dev/cu.test",
    transport: .bsdSerial
  )
  let counter = InvocationCounter()
  let workspace = OperatorWorkspace(
    passiveProbeRunner: { _ in
      await counter.increment()
      throw TestProbeError.unexpectedCall
    },
    serialDevices: [device]
  )
  workspace.selectSerialDevice(device)

  await workspace.requestPassiveProbe()
  await workspace.requestPassiveProbe()

  let invocationCount = await counter.value
  #expect(invocationCount == 2)
  #expect(workspace.passiveProbeResult == nil)
  #expect(workspace.passiveProbeUnavailableReason == nil)
}

private actor InvocationCounter {
  private(set) var value = 0

  func increment() {
    value += 1
  }
}

private enum TestProbeError: Error {
  case unexpectedCall
}
