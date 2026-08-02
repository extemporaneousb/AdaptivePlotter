import Foundation
import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Passive machine controller")
struct MachineControllerTests {
  @Test("fixed passive probe records exact fragmented TX and RX")
  func passiveProbe() async throws {
    let fixture = try await Fixture.make()
    let link = SimulatedGRBLLink(
      exchanges: ControllerTranscriptFixtures.successfulPassiveProbe(),
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 1_000
    )

    let result = await controller.runPassiveProbe()
    #expect(result.blockers.isEmpty)
    #expect(result.exchanges.map(\.query) == PassiveQuery.allCases)
    #expect(result.exchanges.allSatisfy { $0.completed })
    #expect(
      result.exchanges.flatMap(\.rawIO).filter { $0.direction == .transmit }.map(\.bytes)
        == PassiveQuery.allCases.map(\.wireBytes))
    #expect(result.armFacts == .passiveOnly)
    let snapshot = await controller.snapshot()
    #expect(snapshot.connection == .connectedPassiveOnly)
    #expect(snapshot.armFacts == .passiveOnly)
    let events = try await fixture.ledger.events(runID: fixture.runID)
    #expect(events.filter { $0.kind == "machine.raw_io" }.count >= 10)
    #expect(events.first?.kind == "machine.passive_probe.started")
    #expect(events.last?.kind == "machine.passive_probe.finished")
    let finishedEvent = try #require(
      events.first(where: { $0.kind == "machine.passive_probe.finished" })
    )
    #expect(finishedEvent.schemaVersion == 1)
    let finished = try JSONDecoder().decode(
      PassiveProbeFinishedRecord.self,
      from: finishedEvent.payload
    )
    #expect(finished.blockers.isEmpty)
    #expect(finished.exchanges.map(\.query) == PassiveQuery.allCases)
    #expect(finished.exchanges[0].parsedLines.contains(where: { $0.text.hasPrefix("[VER:") }))
  }

  @Test("alarm is preserved and stops later passive queries")
  func alarmStopsProbe() async throws {
    let fixture = try await Fixture.make()
    let link = SimulatedGRBLLink(
      exchanges: [ControllerTranscriptFixtures.exchange(.buildInfo, chunks: ["ALARM:2\r\n"])],
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 100
    )
    let result = await controller.runPassiveProbe()
    #expect(result.exchanges.count == 1)
    #expect(result.exchanges[0].lines.first?.kind == .alarm(code: "2"))
    #expect(result.blockers == [.controllerAlarm("ALARM:2")])
  }

  @Test("error reply is preserved and blocks")
  func errorStopsProbe() async throws {
    let fixture = try await Fixture.make()
    let link = SimulatedGRBLLink(
      exchanges: [ControllerTranscriptFixtures.exchange(.buildInfo, chunks: ["error:20\r\n"])],
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock
    )
    let result = await controller.runPassiveProbe()
    #expect(result.blockers == [.controllerError("error:20")])
    #expect(result.exchanges[0].lines.first?.kind == .error(code: "20"))
  }

  @Test("alarm status cannot complete the realtime status query")
  func alarmStatusBlocks() async throws {
    let fixture = try await Fixture.make()
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Alarm|MPos:0.000,0.000,0.000|Pn:XYZ>\r\n"]
    )
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock)
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock
    )
    let result = await controller.runPassiveProbe()
    #expect(result.exchanges.count == 3)
    #expect(result.blockers == [.controllerAlarm("<Alarm|MPos:0.000,0.000,0.000|Pn:XYZ>")])
    #expect(result.exchanges[2].completed == false)
  }

  @Test("reentrant passive probe is rejected before a second write")
  func inFlightGuard() async throws {
    let fixture = try await Fixture.make()
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[0] = ControllerTranscriptFixtures.exchange(
      .buildInfo,
      chunks: ["[VER:1.1h:]\r\nok\r\n"],
      delay: 50_000_000
    )
    let systemClock = SystemRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: systemClock)
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: systemClock,
      queryTimeoutNanoseconds: 100_000_000
    )
    async let first = controller.runPassiveProbe()
    try await Task.sleep(nanoseconds: 5_000_000)
    let second = await controller.runPassiveProbe()
    #expect(second.blockers == [.transport("passive probe already in flight")])
    #expect(second.exchanges.isEmpty)
    _ = await first
  }

  @Test("timeout after write is explicit and does not advance to another query")
  func timeout() async throws {
    let fixture = try await Fixture.make()
    let link = SimulatedGRBLLink(
      exchanges: [
        SimulatedCommandExchange(expectedWrite: PassiveQuery.buildInfo.wireBytes, reads: [])
      ],
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 100
    )
    let result = await controller.runPassiveProbe()
    #expect(result.blockers == [.timeout(.buildInfo)])
    #expect(result.exchanges[0].rawIO.first?.bytes == PassiveQuery.buildInfo.wireBytes)
  }

  @Test("terminal acknowledgement cannot substitute for query-specific evidence")
  func querySpecificCompletionEvidence() async throws {
    let cases: [(PassiveQuery, [String])] = [
      (.buildInfo, ["ok\r\n"]),
      (.parserState, ["[FUTURE:G0 G54]\r\nok\r\n"]),
      (.configuration, ["$Future=opaque\r\nok\r\n"]),
      (.coordinateOffsets, ["[FUTURE:0.000,0.000,0.000]\r\nok\r\n"]),
    ]
    let successful = ControllerTranscriptFixtures.successfulPassiveProbe()

    for (query, chunks) in cases {
      let fixture = try await Fixture.make()
      let targetIndex = try #require(PassiveQuery.allCases.firstIndex(of: query))
      var exchanges = Array(successful.prefix(targetIndex))
      exchanges.append(ControllerTranscriptFixtures.exchange(query, chunks: chunks))
      let controller = MachineController(
        link: SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock),
        ledger: fixture.ledger,
        runID: fixture.runID,
        clock: fixture.clock,
        queryTimeoutNanoseconds: 100
      )

      let result = await controller.runPassiveProbe()

      #expect(result.exchanges.count == targetIndex + 1)
      guard case let .invalidReply(blockedQuery, reason) = result.blockers.first else {
        Issue.record("Expected query-specific invalid reply for \(query)")
        continue
      }
      #expect(blockedQuery == query)
      #expect(reason.contains("expected \(query.rawValue) report"))
    }
  }

  @Test("build options and axis metadata do not substitute for VER identity")
  func buildIdentityRequiresVersionReport() async throws {
    for metadata in ["[OPT:VN,15,128]", "[AXS:3:XYZ]"] {
      let fixture = try await Fixture.make()
      let link = SimulatedGRBLLink(
        exchanges: [
          ControllerTranscriptFixtures.exchange(
            .buildInfo,
            chunks: ["\(metadata)\r\nok\r\n"]
          )
        ],
        clock: fixture.clock
      )
      let controller = MachineController(
        link: link,
        ledger: fixture.ledger,
        runID: fixture.runID,
        clock: fixture.clock,
        queryTimeoutNanoseconds: 100
      )

      let result = await controller.runPassiveProbe()

      guard case .invalidReply(.buildInfo, _) = result.blockers.first else {
        Issue.record("Expected OPT/AXS-only build response to fail closed")
        continue
      }
      #expect(result.exchanges[0].lines.contains(where: { $0.text == metadata }))
    }
  }

  @Test("a shifted stale ok fails before a later valid report")
  func shiftedAcknowledgementFailsClosed() async throws {
    let fixture = try await Fixture.make()
    let link = SimulatedGRBLLink(
      exchanges: [
        ControllerTranscriptFixtures.exchange(
          .buildInfo,
          chunks: ["ok\r\n", "[VER:1.1h:]\r\nok\r\n"]
        )
      ],
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 100
    )

    let result = await controller.runPassiveProbe()

    guard case .invalidReply(.buildInfo, _) = result.blockers.first else {
      Issue.record("Expected stale acknowledgement blocker")
      return
    }
    #expect(result.exchanges[0].lines.map(\.kind) == [.acknowledgement])
    #expect(result.exchanges[0].rawIO.filter { $0.direction == .receive }.count == 1)
  }

  @Test("status requires a recognized nonempty controller state")
  func malformedStatusFailsClosed() async throws {
    let fixture = try await Fixture.make()
    var exchanges = Array(ControllerTranscriptFixtures.successfulPassiveProbe().prefix(2))
    exchanges.append(
      ControllerTranscriptFixtures.exchange(
        .status,
        chunks: ["<FutureState|MPos:0.000,0.000,0.000>\r\n"]
      )
    )
    let controller = MachineController(
      link: SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock),
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 100
    )

    let result = await controller.runPassiveProbe()

    guard case let .invalidReply(.status, reason) = result.blockers.first else {
      Issue.record("Expected malformed status blocker")
      return
    }
    #expect(reason.contains("unrecognized controller state"))
  }

  @Test("arbitrary bracket reports cannot complete status")
  func bracketDoesNotCompleteStatus() async throws {
    let fixture = try await Fixture.make()
    var exchanges = Array(ControllerTranscriptFixtures.successfulPassiveProbe().prefix(2))
    exchanges.append(
      ControllerTranscriptFixtures.exchange(
        .status,
        chunks: ["[GC:G0 G54]\r\n"]
      )
    )
    let controller = MachineController(
      link: SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock),
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 100
    )

    let result = await controller.runPassiveProbe()

    #expect(result.blockers == [.timeout(.status)])
    let statusExchange = try #require(result.exchanges.last)
    #expect(statusExchange.query == .status)
    #expect(statusExchange.lines.first?.kind == .bracketReport(name: "GC", value: "G0 G54"))
  }

  @Test("continuous noise cannot extend the absolute query deadline")
  func absoluteQueryDeadline() async throws {
    let fixture = try await Fixture.make()
    let reads = (0..<100).map { _ in
      ScheduledMachineRead(delayNanoseconds: 4, outcome: .bytes(Data("noise\r\n".utf8)))
    }
    let link = SimulatedGRBLLink(
      exchanges: [
        SimulatedCommandExchange(expectedWrite: PassiveQuery.buildInfo.wireBytes, reads: reads)
      ],
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 10,
      maximumRawReceiveBytesPerQuery: 1_024,
      maximumRawReceiveChunksPerQuery: 100
    )

    let result = await controller.runPassiveProbe()

    #expect(result.blockers == [.timeout(.buildInfo)])
    let received = result.exchanges[0].rawIO.filter { $0.direction == .receive }
    #expect(received.count == 2)
    #expect(result.completedAt.monotonicNanoseconds == result.startedAt.monotonicNanoseconds + 10)
  }

  @Test("continuous zero-delay noise is bounded by transcript bytes and chunks")
  func responseTranscriptBound() async throws {
    let fixture = try await Fixture.make()
    let reads = (0..<100).map { _ in
      ScheduledMachineRead(outcome: .bytes(Data("noise\r\n".utf8)))
    }
    let controller = MachineController(
      link: SimulatedGRBLLink(
        exchanges: [
          SimulatedCommandExchange(expectedWrite: PassiveQuery.buildInfo.wireBytes, reads: reads)
        ],
        clock: fixture.clock
      ),
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 1_000,
      maximumRawReceiveBytesPerQuery: 20,
      maximumRawReceiveChunksPerQuery: 3
    )

    let result = await controller.runPassiveProbe()

    #expect(
      result.blockers == [
        .responseLimitExceeded(.buildInfo, maximumBytes: 20, maximumChunks: 3)
      ])
    let received = result.exchanges[0].rawIO.filter { $0.direction == .receive }
    #expect(received.count == 3)
    #expect(received.reduce(0) { $0 + $1.bytes.count } == 20)
  }

  @Test("disconnect after write is ambiguous and blocks later queries")
  func disconnect() async throws {
    let fixture = try await Fixture.make()
    let link = SimulatedGRBLLink(
      exchanges: [
        SimulatedCommandExchange(
          expectedWrite: PassiveQuery.buildInfo.wireBytes,
          reads: [ScheduledMachineRead(outcome: .disconnect)]
        )
      ],
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock
    )
    let result = await controller.runPassiveProbe()
    #expect(result.exchanges.count == 1)
    #expect(result.exchanges[0].completed == false)
    guard case .transport = result.blockers.first else {
      Issue.record("expected transport blocker")
      return
    }
    let unresolved = try await fixture.ledger.unresolvedCommandIntents(runID: fixture.runID)
    #expect(unresolved.map(\.lifecycle) == [.ambiguous])
  }

  @Test("recorded transcript uses the same exact passive probe surface")
  func transcriptReplay() async throws {
    let fixture = try await Fixture.make()
    let link = try TranscriptReplayLink(
      entries: OfflineRuntimePrototype.simulatedPassiveTranscript(),
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 10_000_000
    )
    let result = await controller.runPassiveProbe()
    #expect(result.blockers.isEmpty)
    #expect(result.exchanges.map(\.query) == PassiveQuery.allCases)
  }

  @Test("closed ledger blocks before any bytes are written")
  func storageBlocksWrite() async throws {
    let fixture = try await Fixture.make()
    await fixture.ledger.close()
    let link = SimulatedGRBLLink(
      exchanges: ControllerTranscriptFixtures.successfulPassiveProbe(),
      clock: fixture.clock
    )
    let controller = MachineController(
      link: link,
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock
    )
    let result = await controller.runPassiveProbe()
    #expect(result.exchanges.isEmpty)
    guard case .storage = result.blockers.first else {
      Issue.record("expected storage blocker")
      return
    }
  }

  @Test("multiple serial ports never auto-select")
  func ambiguousPorts() {
    let descriptors = ["a", "b"].map {
      MachineLinkDescriptor(
        identifier: $0, displayName: $0, bsdPath: "/dev/cu.\($0)", transport: .bsdSerial)
    }
    #expect(SerialSelectionResult.resolve([]) == .blocked(.noSerialDevice))
    #expect(
      SerialSelectionResult.resolve(descriptors) == .blocked(.multipleSerialDevices(descriptors)))
    #expect(
      SerialSelectionResult.resolve(descriptors, selectedIdentifier: "b")
        == .selected(descriptors[1]))
  }
}

private struct Fixture {
  let directory: URL
  let ledger: RunLedger
  let runID: LedgerRunID
  let clock: DeterministicRuntimeClock

  static func make() async throws -> Fixture {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("adaptiveplotter-machine-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let ledger = try RunLedger(databaseURL: directory.appendingPathComponent("run.sqlite"))
    let clock = DeterministicRuntimeClock()
    let runID = LedgerRunID()
    let timestamp = RuntimeTimestamp(monotonicNanoseconds: clock.nowNanoseconds())
    _ = try await ledger.createRun(id: runID, buildID: "test", createdAt: timestamp)
    return Fixture(directory: directory, ledger: ledger, runID: runID, clock: clock)
  }
}
