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

  @Test("successful passive probe becomes the current snapshot")
  func successfulProbeBecomesCurrentSnapshot() async throws {
    let fixture = try await InterpreterFixture.make(
      exchanges: ControllerTranscriptFixtures.successfulPassiveProbe()
    )

    let result = try await fixture.interpreter.requestPassiveProbe()
    let snapshot = await fixture.interpreter.snapshot()

    #expect(result.blockers.isEmpty)
    #expect(snapshot.lastProbe == result)
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.machine.lastProbe == result)
  }

  @Test("typed jog passes through the interpreter without a camera dependency")
  func typedJog() async throws {
    let request = RelativeJogRequest(
      delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
      feedMMPerMinute: 60
    )
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    exchanges.append(
      SimulatedCommandExchange(
        expectedWrite: PassiveQuery.status.wireBytes,
        reads: [
          ScheduledMachineRead(
            outcome: .bytes(Data("<Idle|MPos:0.000,0.000,0.000>\r\n".utf8))
          )
        ]
      )
    )
    exchanges.append(
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(request),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      )
    )
    exchanges.append(
      SimulatedCommandExchange(
        expectedWrite: PassiveQuery.status.wireBytes,
        reads: [
          ScheduledMachineRead(
            outcome: .bytes(Data("<Idle|MPos:1.000,0.000,0.000>\r\n".utf8))
          )
        ]
      )
    )
    let fixture = try await InterpreterFixture.make(exchanges: exchanges)
    _ = try await fixture.interpreter.requestPassiveProbe()
    let limits = try MotionLimits(
      bounds: AxisAlignedBounds<MachineSpace>(minX: -2, minY: -2, maxX: 2, maxY: 2),
      maximumDistanceMM: 1,
      maximumFeedMMPerMinute: 60
    )
    await fixture.interpreter.updateMotionLimits(limits)
    await fixture.interpreter.confirmPenUp()

    let outcome = await fixture.interpreter.requestRelativeJog(request)
    let snapshot = await fixture.interpreter.snapshot()

    #expect(outcome == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)))
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastMotionOutcome == outcome)
  }

  @Test("pre-command open failure records the current failure and probe finish")
  func openFailureIsRecorded() async throws {
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
    let interpreter = RunInterpreter(machineController: controller)

    let result = try await interpreter.requestPassiveProbe()
    let snapshot = await interpreter.snapshot()
    let events = try await waitForInterpreterLedgerEvent(
      "machine.passive_probe.finished",
      ledger: ledger,
      runID: runID
    )

    #expect(result.exchanges.isEmpty)
    guard case .transport = result.blockers.first else {
      Issue.record("Expected transport blocker from open failure")
      return
    }
    #expect(snapshot.lastProbe == result)
    #expect(snapshot.machine.blockers == result.blockers)
    #expect(events.contains(where: { $0.kind == "machine.passive_probe.started" }))
    #expect(events.contains(where: { $0.kind == "machine.passive_probe.finished" }))
    let finishedEvent = try #require(
      events.first(where: { $0.kind == "machine.passive_probe.finished" })
    )
    let finished = try JSONDecoder().decode(
      PassiveProbeFinishedRecord.self,
      from: finishedEvent.payload
    )
    #expect(finished.exchanges.isEmpty)
    #expect(finished.blockers == result.blockers)
  }
}

private func waitForInterpreterLedgerEvent(
  _ kind: String,
  ledger: RunLedger,
  runID: LedgerRunID
) async throws -> [LedgerEvent] {
  for _ in 0..<100 {
    let events = try await ledger.events(runID: runID)
    if events.contains(where: { $0.kind == kind }) { return events }
    await Task.yield()
  }
  return try await ledger.events(runID: runID)
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
    let interpreter = RunInterpreter(machineController: controller)
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

  func discardPendingInput() async throws {
    Issue.record("Open failure must occur before pending input discard")
    throw MachineLinkError.notOpen
  }

  func write(_: Data) async throws {
    Issue.record("Open failure must occur before write")
    throw MachineLinkError.notOpen
  }

  func read(maximumBytes _: Int, timeoutNanoseconds _: UInt64) async throws -> Data {
    Issue.record("Open failure must occur before read")
    throw MachineLinkError.notOpen
  }
}
