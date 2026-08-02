import Darwin
import Foundation
import PlotterModel
import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Run interpreter shell")
struct RunInterpreterTests {
  @Test("stale transition completion is rejected")
  func staleTransition() async throws {
    let fixture = try await InterpreterFixture.make()
    let token = try await fixture.interpreter.beginPassiveProbe()
    await fixture.interpreter.invalidatePendingTransition()
    let result = PassiveProbeResult(
      link: fixture.link.descriptor,
      startedAt: RuntimeTimestamp(monotonicNanoseconds: 1),
      completedAt: RuntimeTimestamp(monotonicNanoseconds: 2),
      exchanges: [],
      blockers: []
    )
    await #expect(throws: RunInterpreterError.staleTransition) {
      try await fixture.interpreter.completePassiveProbe(token: token, result: result)
    }
  }

  @Test("prepared command intent blocks recovery as ambiguous physical work")
  func unresolvedCommandRecovery() async throws {
    let fixture = try await InterpreterFixture.make()
    let commandID = UUID()
    try await fixture.ledger.prepareCommand(
      runID: fixture.runID,
      commandID: commandID,
      query: .status,
      bytes: PassiveQuery.status.wireBytes,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 3)
    )
    try await fixture.interpreter.reconcileRecordedCommandIntents()
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.authority.allowed == false)
    #expect(snapshot.authority.operation == nil)
    #expect(snapshot.unresolvedCommandIntents.map(\.commandID) == [commandID])
    #expect(snapshot.authority.blockers.map(\.code) == ["machine.command_outcome_ambiguous"])
  }

  @Test("successful passive probe cannot clear an unresolved command outcome")
  func successfulProbeRetainsAmbiguity() async throws {
    let fixture = try await InterpreterFixture.make(
      exchanges: ControllerTranscriptFixtures.successfulPassiveProbe()
    )
    let unresolvedCommandID = UUID()
    try await fixture.ledger.prepareCommand(
      runID: fixture.runID,
      commandID: unresolvedCommandID,
      query: .status,
      bytes: PassiveQuery.status.wireBytes,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: 3)
    )
    try await fixture.interpreter.reconcileRecordedCommandIntents()

    let result = try await fixture.interpreter.requestPassiveProbe()
    let snapshot = await fixture.interpreter.snapshot()

    #expect(result.blockers.isEmpty)
    #expect(snapshot.authority.allowed == false)
    #expect(snapshot.authority.operation == nil)
    #expect(snapshot.unresolvedCommandIntents.map(\.commandID) == [unresolvedCommandID])
    #expect(snapshot.authority.blockers.map(\.code) == ["machine.command_outcome_ambiguous"])
    let events = try await fixture.ledger.events(runID: fixture.runID)
    let transitionEvents = events.filter { $0.kind == "runtime.authority.transition" }
    #expect(transitionEvents.count == 2)
    let lastTransition = try JSONDecoder().decode(
      AuthorityTransitionRecord.self,
      from: try #require(transitionEvents.last).payload
    )
    #expect(lastTransition.reason == .passiveProbeCompleted)
    #expect(lastTransition.unresolvedCommandIDs == [unresolvedCommandID])
    #expect(lastTransition.resultingAuthority.allowed == false)
  }

  @Test("pre-command open failure records probe finish and blocked authority transition")
  func openFailureIsDurable() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "adaptiveplotter-open-failure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ledger = try RunLedger(databaseURL: directory.appendingPathComponent("run.sqlite"))
    let runID = LedgerRunID()
    _ = try await ledger.createRun(
      id: runID,
      buildID: "test",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let link = OpenFailureLink()
    let controller = MachineController(link: link, ledger: ledger, runID: runID)
    let interpreter = RunInterpreter(
      machineController: controller,
      ledger: ledger,
      runID: runID,
      initialAuthority: try OfflineRuntimePrototype.passiveAuthority(
        safetyPolicyID: SafetyPolicyID())
    )

    let result = try await interpreter.requestPassiveProbe()
    let snapshot = await interpreter.snapshot()
    let events = try await ledger.events(runID: runID)

    #expect(result.exchanges.isEmpty)
    guard case .transport = result.blockers.first else {
      Issue.record("Expected transport blocker from open failure")
      return
    }
    #expect(snapshot.authority.allowed == false)
    #expect(
      events.map(\.kind) == [
        "machine.passive_probe.started",
        "machine.passive_probe.finished",
        "runtime.authority.transition",
      ])
    let finished = try JSONDecoder().decode(
      PassiveProbeFinishedRecord.self,
      from: events[1].payload
    )
    #expect(finished.exchanges.isEmpty)
    #expect(finished.blockers == result.blockers)
    let transition = try JSONDecoder().decode(
      AuthorityTransitionRecord.self,
      from: events[2].payload
    )
    #expect(transition.reason == .passiveProbeCompleted)
    #expect(transition.machineBlockers == result.blockers)
    #expect(transition.resultingAuthority.allowed == false)
  }
}

private struct InterpreterFixture {
  let ledger: RunLedger
  let runID: LedgerRunID
  let link: SimulatedGRBLLink
  let interpreter: RunInterpreter

  static func make(
    exchanges: [SimulatedCommandExchange] = []
  ) async throws -> InterpreterFixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("adaptiveplotter-interpreter-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ledger = try RunLedger(databaseURL: directory.appendingPathComponent("run.sqlite"))
    let runID = LedgerRunID()
    _ = try await ledger.createRun(
      id: runID,
      buildID: "test",
      createdAt: RuntimeTimestamp(monotonicNanoseconds: 1)
    )
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
    let controller = MachineController(
      link: link,
      ledger: ledger,
      runID: runID,
      clock: clock,
      queryTimeoutNanoseconds: 1_000
    )
    let interpreter = RunInterpreter(
      machineController: controller,
      ledger: ledger,
      runID: runID,
      initialAuthority: try OfflineRuntimePrototype.passiveAuthority(
        safetyPolicyID: SafetyPolicyID()
      )
    )
    return InterpreterFixture(
      ledger: ledger,
      runID: runID,
      link: link,
      interpreter: interpreter
    )
  }
}

private final class OpenFailureLink: MachineLink, @unchecked Sendable {
  let descriptor = MachineLinkDescriptor(
    identifier: "open-failure",
    displayName: "Open Failure",
    bsdPath: nil,
    transport: .simulated
  )

  func open() async throws {
    throw MachineLinkError.operatingSystem(code: EIO, operation: "open")
  }

  func close() async {}

  func write(_: Data) async throws {
    Issue.record("Open failure must occur before write")
    throw MachineLinkError.notOpen
  }

  func read(maximumBytes _: Int, timeoutNanoseconds _: UInt64) async throws -> Data {
    Issue.record("Open failure must occur before read")
    throw MachineLinkError.notOpen
  }
}
