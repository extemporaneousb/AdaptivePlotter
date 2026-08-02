import Foundation

public enum MachineConnectionState: String, Codable, Hashable, Sendable {
  case disconnected
  case connecting
  case connectedPassiveOnly
  case probing
  case blocked
}

public struct MachineSnapshot: Codable, Hashable, Sendable {
  public let connection: MachineConnectionState
  public let link: MachineLinkDescriptor
  public let armFacts: MachineArmFacts
  public let lastProbe: PassiveProbeResult?
  public let blockers: [MachineBlocker]

  public init(
    connection: MachineConnectionState,
    link: MachineLinkDescriptor,
    armFacts: MachineArmFacts = .passiveOnly,
    lastProbe: PassiveProbeResult?,
    blockers: [MachineBlocker]
  ) {
    self.connection = connection
    self.link = link
    self.armFacts = armFacts
    self.lastProbe = lastProbe
    self.blockers = blockers
  }
}

public enum SerialSelectionResult: Sendable, Equatable {
  case selected(MachineLinkDescriptor)
  case blocked(MachineBlocker)

  public static func resolve(
    _ descriptors: [MachineLinkDescriptor],
    selectedIdentifier: String? = nil
  ) -> SerialSelectionResult {
    if let selectedIdentifier,
      let selected = descriptors.first(where: { $0.identifier == selectedIdentifier })
    {
      return .selected(selected)
    }
    if descriptors.isEmpty { return .blocked(.noSerialDevice) }
    if descriptors.count == 1, let only = descriptors.first { return .selected(only) }
    return .blocked(.multipleSerialDevices(descriptors))
  }
}

public actor MachineController {
  private let link: any MachineLink
  private let ledger: RunLedger
  private let runID: LedgerRunID
  private let clock: any RuntimeClock
  private let queryTimeoutNanoseconds: UInt64
  private let maximumRawReceiveBytesPerQuery: Int
  private let maximumRawReceiveChunksPerQuery: Int
  private var connection: MachineConnectionState = .disconnected
  private var lastProbe: PassiveProbeResult?
  private var blockers: [MachineBlocker] = []
  private var probeInFlight = false

  public init(
    link: any MachineLink,
    ledger: RunLedger,
    runID: LedgerRunID,
    clock: any RuntimeClock = SystemRuntimeClock(),
    queryTimeoutNanoseconds: UInt64 = 2_000_000_000,
    maximumRawReceiveBytesPerQuery: Int = 64 * 1_024,
    maximumRawReceiveChunksPerQuery: Int = 256
  ) {
    self.link = link
    self.ledger = ledger
    self.runID = runID
    self.clock = clock
    self.queryTimeoutNanoseconds = queryTimeoutNanoseconds
    self.maximumRawReceiveBytesPerQuery = max(1, maximumRawReceiveBytesPerQuery)
    self.maximumRawReceiveChunksPerQuery = max(1, maximumRawReceiveChunksPerQuery)
  }

  public static func bsdSerial(
    descriptor: MachineLinkDescriptor,
    ledger: RunLedger,
    runID: LedgerRunID,
    clock: any RuntimeClock = SystemRuntimeClock(),
    queryTimeoutNanoseconds: UInt64 = 2_000_000_000,
    maximumRawReceiveBytesPerQuery: Int = 64 * 1_024,
    maximumRawReceiveChunksPerQuery: Int = 256,
    writeTimeoutNanoseconds: UInt64 = 500_000_000
  ) throws -> MachineController {
    MachineController(
      link: try BSDSerialLink(
        descriptor: descriptor,
        writeTimeoutNanoseconds: writeTimeoutNanoseconds
      ),
      ledger: ledger,
      runID: runID,
      clock: clock,
      queryTimeoutNanoseconds: queryTimeoutNanoseconds,
      maximumRawReceiveBytesPerQuery: maximumRawReceiveBytesPerQuery,
      maximumRawReceiveChunksPerQuery: maximumRawReceiveChunksPerQuery
    )
  }

  public func snapshot() -> MachineSnapshot {
    MachineSnapshot(
      connection: connection,
      link: link.descriptor,
      lastProbe: lastProbe,
      blockers: blockers
    )
  }

  public func disconnect() async {
    await link.close()
    connection = .disconnected
  }

  /// The only physical command surface in Phase 2. The exact fixed query set
  /// is sent in declaration order; callers cannot provide arbitrary bytes.
  public func runPassiveProbe() async -> PassiveProbeResult {
    let started = timestamp()
    guard !probeInFlight else {
      return PassiveProbeResult(
        link: link.descriptor,
        startedAt: started,
        completedAt: timestamp(),
        exchanges: [],
        blockers: [.transport("passive probe already in flight")]
      )
    }
    probeInFlight = true
    defer { probeInFlight = false }
    blockers = []
    var exchanges: [PassiveProbeExchange] = []
    let probeID = UUID()

    do {
      try await recordProbeStarted(probeID: probeID, started: started)
    } catch {
      blockers = [.storage(String(describing: error))]
      connection = .blocked
      return finishProbeWithoutDurableFinish(started: started, exchanges: exchanges)
    }

    do {
      if connection == .disconnected || connection == .blocked {
        connection = .connecting
        try await link.open()
      }
      connection = .probing
    } catch {
      blockers = [.transport(String(describing: error))]
      connection = .blocked
      return await finishProbe(probeID: probeID, started: started, exchanges: exchanges)
    }

    for query in PassiveQuery.allCases {
      let exchange = await execute(query)
      exchanges.append(exchange)
      if let blocker = exchange.blocker { blockers.append(blocker) }
      if exchange.blocker != nil { break }
    }
    connection = blockers.isEmpty ? .connectedPassiveOnly : .blocked
    return await finishProbe(probeID: probeID, started: started, exchanges: exchanges)
  }

  private func execute(_ query: PassiveQuery) async -> PassiveProbeExchange {
    let commandID = UUID()
    let bytes = query.wireBytes
    var rawIO: [RawMachineIO] = []
    var parsed: [ParsedControllerLine] = []
    var parser = GRBLParser()
    var validator = PassiveReplyValidator(query: query)
    var wasWritten = false
    var rawReceiveBytes = 0
    var rawReceiveChunks = 0
    let deadline = addingClamped(clock.nowNanoseconds(), queryTimeoutNanoseconds)

    do {
      let preparedAt = timestamp()
      try await ledger.prepareCommand(
        runID: runID,
        commandID: commandID,
        query: query,
        bytes: bytes,
        timestamp: preparedAt
      )
      try await link.write(bytes)
      wasWritten = true
      let transmitted = RawMachineIO(direction: .transmit, bytes: bytes, timestamp: timestamp())
      rawIO.append(transmitted)
      try await ledger.markCommandWritten(commandID: commandID, timestamp: transmitted.timestamp)
      try await recordRawIO(transmitted)

      while true {
        guard rawReceiveBytes < maximumRawReceiveBytesPerQuery,
          rawReceiveChunks < maximumRawReceiveChunksPerQuery
        else {
          try await ledger.markCommandOutcome(
            commandID: commandID,
            lifecycle: .ambiguous,
            outcome: "passive response exceeded transcript limit",
            timestamp: timestamp()
          )
          return exchange(
            query: query,
            commandID: commandID,
            rawIO: rawIO,
            lines: parsed,
            blocker: .responseLimitExceeded(
              query,
              maximumBytes: maximumRawReceiveBytesPerQuery,
              maximumChunks: maximumRawReceiveChunksPerQuery
            )
          )
        }
        let now = clock.nowNanoseconds()
        guard now < deadline else { throw MachineLinkError.timedOut }
        let remainingNanoseconds = deadline - now
        let remainingBytes = maximumRawReceiveBytesPerQuery - rawReceiveBytes
        let receivedBytes = try await link.read(
          maximumBytes: min(4_096, remainingBytes),
          timeoutNanoseconds: remainingNanoseconds
        )
        guard receivedBytes.count <= remainingBytes else {
          throw MachineLinkError.readExceededMaximum(
            expected: remainingBytes,
            actual: receivedBytes.count
          )
        }
        rawReceiveBytes += receivedBytes.count
        rawReceiveChunks += 1
        let received = RawMachineIO(
          direction: .receive,
          bytes: receivedBytes,
          timestamp: timestamp()
        )
        rawIO.append(received)
        try await recordRawIO(received)
        guard clock.nowNanoseconds() <= deadline else { throw MachineLinkError.timedOut }
        let newLines = parser.consume(receivedBytes)
        for line in newLines {
          parsed.append(line)
          switch validator.consume(line) {
          case .continueReading:
            continue
          case .complete:
            try await ledger.markCommandOutcome(
              commandID: commandID,
              lifecycle: .completed,
              outcome: "passive reply complete with query-specific evidence",
              timestamp: timestamp()
            )
            return PassiveProbeExchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              completed: true,
              blocker: nil
            )
          case let .invalid(reason):
            try await ledger.markCommandOutcome(
              commandID: commandID,
              lifecycle: .ambiguous,
              outcome: reason,
              timestamp: timestamp()
            )
            return exchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              blocker: .invalidReply(query, reason: reason)
            )
          case let .alarm(text):
            try await ledger.markCommandOutcome(
              commandID: commandID,
              lifecycle: .failed,
              outcome: text,
              timestamp: timestamp()
            )
            return exchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              blocker: .controllerAlarm(text)
            )
          case let .controllerError(text):
            try await ledger.markCommandOutcome(
              commandID: commandID,
              lifecycle: .failed,
              outcome: text,
              timestamp: timestamp()
            )
            return exchange(
              query: query,
              commandID: commandID,
              rawIO: rawIO,
              lines: parsed,
              blocker: .controllerError(text)
            )
          }
        }
      }
    } catch MachineLinkError.timedOut {
      if let unterminated = parser.finishUnterminatedLine() { parsed.append(unterminated) }
      if wasWritten {
        try? await ledger.markCommandOutcome(
          commandID: commandID,
          lifecycle: .ambiguous,
          outcome: "timeout",
          timestamp: timestamp()
        )
      }
      return exchange(
        query: query,
        commandID: commandID,
        rawIO: rawIO,
        lines: parsed,
        blocker: .timeout(query)
      )
    } catch let error as RunLedgerError {
      if wasWritten {
        try? await ledger.markCommandPossiblyWrittenAmbiguous(
          commandID: commandID,
          outcome: "storage failure after physical write: \(error)",
          timestamp: timestamp()
        )
      }
      return exchange(
        query: query,
        commandID: commandID,
        rawIO: rawIO,
        lines: parsed,
        blocker: .storage(String(describing: error))
      )
    } catch {
      if wasWritten {
        try? await ledger.markCommandOutcome(
          commandID: commandID,
          lifecycle: .ambiguous,
          outcome: String(describing: error),
          timestamp: timestamp()
        )
      }
      return exchange(
        query: query,
        commandID: commandID,
        rawIO: rawIO,
        lines: parsed,
        blocker: .transport(String(describing: error))
      )
    }
  }

  private func exchange(
    query: PassiveQuery,
    commandID: UUID,
    rawIO: [RawMachineIO],
    lines: [ParsedControllerLine],
    blocker: MachineBlocker
  ) -> PassiveProbeExchange {
    PassiveProbeExchange(
      query: query,
      commandID: commandID,
      rawIO: rawIO,
      lines: lines,
      completed: false,
      blocker: blocker
    )
  }

  private func recordRawIO(_ io: RawMachineIO) async throws {
    let payload = try JSONEncoder().encode(io)
    try await ledger.appendEvent(
      runID: runID,
      timestamp: io.timestamp,
      kind: "machine.raw_io",
      payload: payload
    )
  }

  private func timestamp() -> RuntimeTimestamp {
    RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
  }

  private func recordProbeStarted(probeID: UUID, started: RuntimeTimestamp) async throws {
    let record = PassiveProbeStartedRecord(
      probeID: probeID,
      link: link.descriptor,
      startedAt: started,
      queries: PassiveQuery.allCases
    )
    try await ledger.appendEvent(
      runID: runID,
      timestamp: started,
      kind: "machine.passive_probe.started",
      schemaVersion: 1,
      payload: try JSONEncoder().encode(record)
    )
  }

  private func finishProbe(
    probeID: UUID,
    started: RuntimeTimestamp,
    exchanges: [PassiveProbeExchange]
  ) async -> PassiveProbeResult {
    var result = PassiveProbeResult(
      link: link.descriptor,
      startedAt: started,
      completedAt: timestamp(),
      exchanges: exchanges,
      blockers: blockers
    )
    do {
      let record = PassiveProbeFinishedRecord(probeID: probeID, result: result)
      try await ledger.appendEvent(
        runID: runID,
        timestamp: result.completedAt,
        kind: "machine.passive_probe.finished",
        schemaVersion: 1,
        payload: try JSONEncoder().encode(record)
      )
    } catch {
      blockers.append(.storage(String(describing: error)))
      connection = .blocked
      result = PassiveProbeResult(
        link: link.descriptor,
        startedAt: started,
        completedAt: timestamp(),
        exchanges: exchanges,
        blockers: blockers
      )
    }
    lastProbe = result
    return result
  }

  private func finishProbeWithoutDurableFinish(
    started: RuntimeTimestamp,
    exchanges: [PassiveProbeExchange]
  ) -> PassiveProbeResult {
    let result = PassiveProbeResult(
      link: link.descriptor,
      startedAt: started,
      completedAt: timestamp(),
      exchanges: exchanges,
      blockers: blockers
    )
    lastProbe = result
    return result
  }
}

private enum PassiveReplyDecision {
  case continueReading
  case complete
  case invalid(String)
  case alarm(String)
  case controllerError(String)
}

private struct PassiveReplyValidator {
  private static let recognizedStatusStates: Set<String> = [
    "idle", "run", "hold", "jog", "alarm", "door", "check", "home", "sleep", "tool",
  ]
  private static let coordinateReportNames: Set<String> = [
    "G54", "G55", "G56", "G57", "G58", "G59", "G28", "G30", "G92", "TLO", "PRB",
  ]

  let query: PassiveQuery
  private var hasExpectedEvidence = false

  init(query: PassiveQuery) {
    self.query = query
  }

  mutating func consume(_ line: ParsedControllerLine) -> PassiveReplyDecision {
    switch line.kind {
    case .alarm:
      return .alarm(line.text)
    case .error:
      return .controllerError(line.text)
    case let .status(status)
    where status.state.split(separator: ":", maxSplits: 1).first?.lowercased() == "alarm":
      return .alarm(line.text)
    default:
      break
    }

    if query == .status {
      switch line.kind {
      case let .status(status):
        let state = status.state.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        guard !state.isEmpty, Self.recognizedStatusStates.contains(state.lowercased()) else {
          return .invalid("status report has an empty or unrecognized controller state")
        }
        return .complete
      case .acknowledgement:
        return .invalid("status query received terminal acknowledgement instead of status")
      default:
        return .continueReading
      }
    }

    if isExpectedEvidence(line.kind) { hasExpectedEvidence = true }
    guard line.kind == .acknowledgement else { return .continueReading }
    guard hasExpectedEvidence else {
      return .invalid("terminal acknowledgement arrived before expected \(query.rawValue) report")
    }
    return .complete
  }

  private func isExpectedEvidence(_ kind: ControllerLineKind) -> Bool {
    switch (query, kind) {
    case let (.buildInfo, .bracketReport(name?, value)):
      return name.caseInsensitiveCompare("VER") == .orderedSame && !value.isEmpty
    case let (.parserState, .bracketReport(name?, value)):
      return name.caseInsensitiveCompare("GC") == .orderedSame && !value.isEmpty
    case let (.configuration, .configuration(key, value)):
      let digits = key.dropFirst()
      return key.first == "$" && !digits.isEmpty && digits.allSatisfy(\.isNumber)
        && Double(value)?.isFinite == true
    case let (.coordinateOffsets, .bracketReport(name?, value)):
      return Self.coordinateReportNames.contains(name.uppercased())
        && Self.isValidCoordinateReport(name: name, value: value)
    default:
      return false
    }
  }

  private static func isValidCoordinateReport(name: String, value: String) -> Bool {
    let name = name.uppercased()
    if name == "TLO" { return Double(value)?.isFinite == true }
    let coordinateText = value.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    let components = coordinateText.split(separator: ",", omittingEmptySubsequences: false)
    guard components.count >= 3 else { return false }
    return components.prefix(3).allSatisfy { Double($0)?.isFinite == true }
  }
}

private func addingClamped(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
  let (sum, overflow) = lhs.addingReportingOverflow(rhs)
  return overflow ? UInt64.max : sum
}
