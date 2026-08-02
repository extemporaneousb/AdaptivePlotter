import Foundation
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("Offline replay renders recorded authority and frontiers without promoting ink")
@MainActor
func offlineReplayUsesRecordedFacts() async {
  let workspace = OperatorWorkspace()

  #expect(workspace.authority.allowed == false)
  #expect(workspace.frontiers.commandedThrough == nil)
  #expect(workspace.simulatorTaskState == .idle)

  await workspace.runOfflinePrototype()

  #expect(workspace.simulatorTaskState == .complete(sequence: 4))
  #expect(workspace.authority.allowed == false)
  #expect(workspace.authority.operation == nil)
  #expect(workspace.authority.blockers.map(\.code) == ["offline_simulation_only"])
  #expect(workspace.frontiers.commandedThrough != nil)
  #expect(workspace.frontiers.controllerCompletedThrough == workspace.frontiers.commandedThrough)
  #expect(workspace.frontiers.inkBySlice.count == 1)
  let disposition = workspace.frontiers.inkBySlice.values.first?.disposition
  guard case let .some(.ambiguous(reasons)) = disposition else {
    Issue.record("Expected simulated ink to remain ambiguous")
    return
  }
  #expect(reasons == ["Offline simulation cannot verify physical ink."])
}

@Test("Presentation visibility cannot alter runtime authority")
@MainActor
func presentationStateDoesNotAlterAuthority() {
  let workspace = OperatorWorkspace()
  let authority = workspace.authority
  let frontiers = workspace.frontiers

  workspace.setLayer(.observed, visible: false)
  workspace.setPane(.facts, visible: false)
  workspace.selection = .event(3)

  #expect(workspace.visibleLayers.contains(.observed) == false)
  #expect(workspace.visiblePanes.contains(.facts) == false)
  #expect(workspace.authority == authority)
  #expect(workspace.frontiers == frontiers)
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

@Test("A powered passive attempt is one-shot even after failure")
@MainActor
func passiveProbeIsOneShot() async {
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
  #expect(invocationCount == 1)
  #expect(workspace.passiveProbeAttempted)
  #expect(workspace.passiveProbeResult == nil)
  #expect(workspace.passiveProbeUnavailableReason?.contains("one-shot session") == true)
}

@Test("Cross-launch recovery blocker is explicit and remains one-shot")
@MainActor
func recoveryBlockerIsVisible() async {
  let device = MachineLinkDescriptor(
    identifier: "test-serial",
    displayName: "Test serial",
    bsdPath: "/dev/cu.test",
    transport: .bsdSerial
  )
  let databaseURL = URL(fileURLWithPath: "/tmp/passive-prior.sqlite")
  let runID = LedgerRunID(UUID())
  let recovery = PassiveRunRecoveryScan(
    inspectedDatabaseURLs: [databaseURL],
    issues: [.unfinishedRun(databaseURL: databaseURL, runID: runID)]
  )
  let workspace = OperatorWorkspace(
    passiveProbeRunner: { _ in
      throw PassiveRunRecoveryRequiredError(scan: recovery)
    },
    serialDevices: [device]
  )
  workspace.selectSerialDevice(device)

  await workspace.requestPassiveProbe()

  #expect(workspace.passiveProbeAttempted)
  #expect(workspace.passiveProbeResult == nil)
  #expect(workspace.passiveProbeFailure?.hasPrefix("RECOVERY BLOCKED:") == true)
  #expect(workspace.passiveProbeFailure?.contains("No powered probe was started") == true)
  #expect(workspace.passiveProbeFailure?.contains("replayed or mutated") == true)
}

@Test("Production composition preflight blocks before creating another ledger")
func compositionRecoveryPreflight() async throws {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("adaptiveplotter-app-recovery-\(UUID().uuidString)", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let databaseURL = directory.appendingPathComponent("passive-prior.sqlite")
  let ledger = try RunLedger(databaseURL: databaseURL)
  await ledger.close()

  do {
    try await PassiveProbeComposition.requireRecoveryClear(in: directory)
    Issue.record("empty prior passive ledger must block production composition")
  } catch let error as PassiveRunRecoveryRequiredError {
    #expect(error.scan.issues == [.emptyDatabase(databaseURL: databaseURL)])
    #expect(
      try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sqlite" }.count == 1
    )
  }
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
