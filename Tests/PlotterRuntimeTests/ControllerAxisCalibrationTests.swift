import Foundation
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

@Suite("Controller axis calibration")
struct ControllerAxisCalibrationTests {
  @Test("two axis settings are individually acknowledged and exact unchanged context is read back")
  func successfulApplication() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands()
      + proposal.commands.map { calibrationCommand($0, reply: "ok\r\n") }
      + calibrationProbeCommands(x: proposal.proposedXStepsPerMM, y: proposal.proposedYStepsPerMM), clock: clock)
    let controller = MachineController(link: link, clock: clock)
    let preparation = CalibrationPreparation()
    let outcome = await controller.applyAxisCalibration(proposal) { await preparation.record() }
    #expect(outcome.status == .applied)
    #expect(outcome.attemptedCommands == proposal.commands)
    #expect(outcome.acknowledgedCommands == proposal.commands)
    #expect(outcome.baselineProbe?.exchanges.count == 5)
    #expect(outcome.verificationProbe?.exchanges.count == 5)
    #expect(outcome.commandTransfers.count == 2)
    #expect(outcome.commandTransfers.allSatisfy { $0.writtenByteCount == $0.command.utf8.count + 1 })
    #expect(outcome.commandTransfers.allSatisfy { $0.acknowledgement == "ok" && $0.received.map(\.bytes) == [Data("ok\r\n".utf8)] })
    #expect(outcome.verifiedContext?.configuration.contains("$Future=opaque") == true)
    #expect(outcome.verifiedContext?.configuration.contains("$110=500") == true)
    #expect(await preparation.count == 1)
    #expect(link.completedWriteCount == 12)
    #expect(await controller.snapshot().motionGuardState == .inactive)
    #expect(try JSONDecoder().decode(ControllerAxisCalibrationOutcome.self, from: JSONEncoder().encode(outcome)) == outcome)
  }

  @Test("fresh stale settings refuse before durable preparation or any setting write")
  func staleBaseline() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands(extra: "$110=501"), clock: clock)
    let preparation = CalibrationPreparation()
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {
      await preparation.record()
    }
    #expect(outcome.status == .refused)
    #expect(outcome.attemptedCommands.isEmpty)
    #expect(await preparation.count == 0)
    #expect(link.completedWriteCount == 5)
  }

  @Test("non-Idle baseline refuses before settings preparation")
  func nonIdleBaseline() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands(state: "Run"), clock: clock)
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {
      Issue.record("Preparation must not be called for a running controller.")
    }
    #expect(outcome.status == .refused)
    #expect(outcome.attemptedCommands.isEmpty)
  }

  @Test("durable preparation failure refuses with no setting bytes")
  func preparationFailure() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands(), clock: clock)
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {
      throw CalibrationPreparationFailure.failed
    }
    #expect(outcome.status == .refused)
    #expect(outcome.attemptedCommands.isEmpty)
    #expect(outcome.reason.contains("preparation failed"))
    #expect(link.completedWriteCount == 5)
  }

  @Test("partial first write retains transferred count and never sends the second axis")
  func partialWrite() async throws {
    let proposal = try await calibrationProposal()
    let command = proposal.commands[0]
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands() + [
      SimulatedCommandExchange(expectedWrite: Data((command + "\n").utf8), reads: [],
        writeError: .writeFailed(bytesWritten: 4, totalBytes: command.utf8.count + 1,
          reason: .operatingSystem(code: 5, operation: "fixture write")))
    ], clock: clock)
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {}
    #expect(outcome.status == .ambiguous)
    #expect(outcome.attemptedCommands == [command])
    #expect(outcome.acknowledgedCommands.isEmpty)
    #expect(outcome.commandTransfers.first?.writtenByteCount == 4)
    #expect(outcome.commandTransfers.first?.writeError != nil)
    #expect(outcome.verificationProbe == nil)
    #expect(link.completedWriteCount == 6)
  }

  @Test("acknowledgement timeout retains lower partial receive bytes and never advances")
  func acknowledgementPartialReadFailure() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let base = SimulatedGRBLLink(exchanges: calibrationProbeCommands() + [
      calibrationCommand(proposal.commands[0], reply: "ok\r\n")
    ], clock: clock)
    let partial = MachineLinkReadReceipt(bytes: Data("o".utf8), receivedAtMonotonicNanoseconds: 73)
    let link = CalibrationPartialReadLink(base: base,
      command: Data((proposal.commands[0] + "\n").utf8), partial: partial)
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {}
    #expect(outcome.status == .ambiguous)
    #expect(outcome.attemptedCommands == [proposal.commands[0]])
    #expect(outcome.acknowledgedCommands.isEmpty)
    #expect(outcome.commandTransfers.first?.received == [partial])
    #expect(outcome.commandTransfers.first?.acknowledgement == nil)
    #expect(base.completedWriteCount == 6)
  }

  @Test("an existing session discards old input before the fresh baseline")
  func staleInputCannotSatisfyFreshBaseline() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands() + calibrationProbeCommands()
      + proposal.commands.map { calibrationCommand($0, reply: "ok\r\n") }
      + calibrationProbeCommands(x: proposal.proposedXStepsPerMM, y: proposal.proposedYStepsPerMM), clock: clock)
    let controller = MachineController(link: link, clock: clock)
    #expect((await controller.runPassiveProbe()).blockers.isEmpty)
    link.preloadPendingInput(Data("error:9\r\n".utf8))
    let outcome = await controller.applyAxisCalibration(proposal) {}
    #expect(outcome.status == .applied)
    #expect(link.completedWriteCount == 17)
  }

  @Test("second-axis rejection preserves the first acknowledgement without retry or rollback")
  func secondAxisRejected() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands() + [
      calibrationCommand(proposal.commands[0], reply: "ok\r\n"),
      calibrationCommand(proposal.commands[1], reply: "error:3\r\n")
    ], clock: clock)
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {}
    #expect(outcome.status == .ambiguous)
    #expect(outcome.attemptedCommands == proposal.commands)
    #expect(outcome.acknowledgedCommands == [proposal.commands[0]])
    #expect(outcome.commandTransfers.last?.acknowledgement == "error:3")
    #expect(outcome.verificationProbe == nil)
    #expect(link.completedWriteCount == 7)
  }

  @Test("acknowledged settings with changed unrelated readback remain ambiguous")
  func readbackMismatch() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands()
      + proposal.commands.map { calibrationCommand($0, reply: "ok\r\n") }
      + calibrationProbeCommands(x: proposal.proposedXStepsPerMM, y: proposal.proposedYStepsPerMM, extra: "$110=501"), clock: clock)
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {}
    #expect(outcome.status == .ambiguous)
    #expect(outcome.acknowledgedCommands == proposal.commands)
    #expect(outcome.verificationProbe != nil)
    #expect(outcome.verifiedContext == nil)
    #expect(link.completedWriteCount == 12)
  }

  @Test("readback of old axis value cannot report application")
  func axisReadbackMismatch() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands()
      + proposal.commands.map { calibrationCommand($0, reply: "ok\r\n") }
      + calibrationProbeCommands(x: proposal.proposedXStepsPerMM), clock: clock)
    let outcome = await MachineController(link: link, clock: clock).applyAxisCalibration(proposal) {}
    #expect(outcome.status == .ambiguous)
    #expect(outcome.verifiedContext == nil)
  }

  @Test("preparation holds exclusive admission and caller cancellation prevents all setting bytes")
  func exclusivePreparationCancellation() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands(), clock: clock)
    let controller = MachineController(link: link, clock: clock)
    let interpreter = RunInterpreter(machineController: controller)
    let gate = CalibrationPreparationGate()
    let task = Task { await interpreter.applyAxisCalibration(proposal) { await gate.hold() } }
    await gate.waitUntilEntered()
    #expect(await interpreter.snapshot().currentOperation == .axisCalibration(proposal.proposalID))
    let duplicate = await interpreter.applyAxisCalibration(proposal) { Issue.record("Duplicate preparation") }
    #expect(duplicate.status == .refused)
    #expect((await controller.runPassiveProbe()).exchanges.isEmpty)
    task.cancel()
    await gate.release()
    let outcome = await task.value
    #expect(outcome.status == .cancelled)
    #expect(outcome.attemptedCommands.isEmpty)
    #expect(link.completedWriteCount == 5)
    #expect(await interpreter.snapshot().currentOperation == .idle)
  }

  @Test("disconnect joins the exact admitted setting transfer and preserves its terminal receipt")
  func interpreterDisconnectJoinsTransfer() async throws {
    let proposal = try await calibrationProposal()
    let clock = DeterministicRuntimeClock()
    let base = SimulatedGRBLLink(exchanges: calibrationProbeCommands() + [
      calibrationCommand(proposal.commands[0], reply: "ok\r\n")
    ], clock: clock)
    let gate = MachineWriteGate()
    let link = CalibrationCloseTrackingLink(base: BlockingMachineLink(base: base,
      blockedWrite: Data((proposal.commands[0] + "\n").utf8), gate: gate))
    let interpreter = RunInterpreter(machineController: MachineController(link: link, clock: clock))
    let task = Task { await interpreter.applyAxisCalibration(proposal) {} }
    await gate.waitUntilBlockedWrite()
    let disconnect = Task { await interpreter.disconnect() }
    // This actor rendezvous is after disconnect begins and waits for the retained task.
    await link.waitUntilCancellationObserved()
    #expect(await link.closeCount == 0)
    await gate.release()
    let outcome = await task.value
    await disconnect.value
    #expect(outcome.status == .ambiguous)
    #expect(outcome.attemptedCommands == [proposal.commands[0]])
    #expect(outcome.commandTransfers.first?.writtenByteCount == proposal.commands[0].utf8.count + 1)
    #expect(base.completedWriteCount == 6)
    #expect(await link.closeCount > 0)
  }
}

private enum CalibrationPreparationFailure: Error { case failed }

private actor CalibrationPreparation {
  private(set) var count = 0
  func record() { count += 1 }
}

private actor CalibrationPreparationGate {
  private var entered = false
  private var released = false
  private var observers: [CheckedContinuation<Void, Never>] = []
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func hold() async {
    entered = true
    let ready = observers; observers.removeAll()
    for observer in ready { observer.resume() }
    guard !released else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func waitUntilEntered() async {
    guard !entered else { return }
    await withCheckedContinuation { observers.append($0) }
  }
  func release() {
    released = true
    let ready = waiters; waiters.removeAll()
    for waiter in ready { waiter.resume() }
  }
}

private actor CalibrationCloseTrackingLink: MachineLink {
  nonisolated let descriptor: MachineLinkDescriptor
  let base: any MachineLink
  private(set) var closeCount = 0
  private var cancellationObserved = false
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
  init(base: any MachineLink) { self.base = base; descriptor = base.descriptor }
  func open() async throws -> MachineLinkOpenReceipt { try await base.open() }
  func close() async throws { closeCount += 1; try await base.close() }
  func discardPendingInput() async throws -> MachineLinkDiscardReceipt { try await base.discardPendingInput() }
  func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    try await withTaskCancellationHandler {
      try await base.write(bytes)
    } onCancel: {
      Task { await self.recordCancellation() }
    }
  }
  func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> MachineLinkReadReceipt {
    try await base.read(maximumBytes: maximumBytes, timeoutNanoseconds: timeoutNanoseconds)
  }
  func waitUntilCancellationObserved() async {
    guard !cancellationObserved else { return }
    await withCheckedContinuation { cancellationWaiters.append($0) }
  }
  private func recordCancellation() {
    cancellationObserved = true
    let waiters = cancellationWaiters; cancellationWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

private actor CalibrationPartialReadLink: MachineLink {
  nonisolated let descriptor: MachineLinkDescriptor
  let base: any MachineLink
  let command: Data
  let partial: MachineLinkReadReceipt
  var failNextRead = false
  init(base: any MachineLink, command: Data, partial: MachineLinkReadReceipt) {
    self.base = base; self.command = command; self.partial = partial; descriptor = base.descriptor
  }
  func open() async throws -> MachineLinkOpenReceipt { try await base.open() }
  func close() async throws { try await base.close() }
  func discardPendingInput() async throws -> MachineLinkDiscardReceipt { try await base.discardPendingInput() }
  func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    let receipt = try await base.write(bytes)
    if bytes == command { failNextRead = true }
    return receipt
  }
  func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> MachineLinkReadReceipt {
    if failNextRead {
      failNextRead = false
      throw MachineLinkError.readFailed(partialReceipts: [partial], maximumBytes: maximumBytes, reason: .timedOut)
    }
    return try await base.read(maximumBytes: maximumBytes, timeoutNanoseconds: timeoutNanoseconds)
  }
}

private struct CalibrationProposalFixture: Encodable {
  let schemaVersion = 1
  let proposalID = UUID()
  let measurementID = UUID()
  let baseline: ControllerCheckpointContext
  let oldMachineGeometry = MachineGeometryIdentity()
  let proposedMachineGeometry = MachineGeometryIdentity()
  let xFactor: ControllerAxisMetricFactor
  let yFactor: ControllerAxisMetricFactor
}

private func calibrationProposal() async throws -> ControllerAxisCalibrationProposal {
  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: calibrationProbeCommands(), clock: clock)
  let baseline = try ControllerCheckpointContext(probe: await MachineController(link: link, clock: clock).runPassiveProbe())
  let encoded = try JSONEncoder().encode(CalibrationProposalFixture(baseline: baseline,
    xFactor: ControllerAxisMetricFactor(estimate: 1.25, lowerBound: 1.24, upperBound: 1.26),
    yFactor: ControllerAxisMetricFactor(estimate: 0.8, lowerBound: 0.79, upperBound: 0.81)))
  return try JSONDecoder().decode(ControllerAxisCalibrationProposal.self, from: encoded)
}

private func calibrationProbeCommands(x: Double = 40, y: Double = 50, extra: String = "$110=500", state: String = "Idle") -> [SimulatedCommandExchange] {
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe(fragmented: false, delayNanoseconds: 0)
  exchanges[2] = ControllerTranscriptFixtures.exchange(.status, chunks: ["<\(state)|MPos:0.000,0.000,0.000>\r\n"])
  exchanges[3] = ControllerTranscriptFixtures.exchange(.configuration,
    chunks: ["$100=\(x)\r\n$101=\(y)\r\n$Future=opaque\r\n\(extra)\r\nok\r\n"])
  return exchanges
}

private func calibrationCommand(_ command: String, reply: String) -> SimulatedCommandExchange {
  SimulatedCommandExchange(expectedWrite: Data((command + "\n").utf8),
    reads: [ScheduledMachineRead(outcome: .bytes(Data(reply.utf8)))])
}
