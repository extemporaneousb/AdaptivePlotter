import Darwin
import Foundation
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterRuntime

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
    let snapshot = await controller.snapshot()
    #expect(snapshot.connection == .connected)
    let events = try await waitForLedgerEvent(
      "machine.passive_probe.finished",
      ledger: fixture.ledger,
      runID: fixture.runID
    )
    #expect(events.filter { $0.kind == "machine.raw_io" }.count >= 10)
    #expect(events.contains(where: { $0.kind == "machine.passive_probe.started" }))
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
    #expect(second.blockers == [.transport("another controller operation is already in flight")])
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
    #expect((await controller.snapshot()).connection == .disconnected)
  }

  @Test("late bytes from a failed probe cannot satisfy a reopened probe or jog")
  func failedProbeDropsLateBytesBeforeRetry() async throws {
    let fixture = try await Fixture.make()
    let request = try jog(dx: 1, dy: 0, feed: 60)
    var exchanges = [
      SimulatedCommandExchange(
        expectedWrite: PassiveQuery.buildInfo.wireBytes,
        reads: [
          ScheduledMachineRead(
            delayNanoseconds: 100,
            outcome: .bytes(Data("[VER:1.1h:]\r\nok\r\n".utf8))
          )
        ]
      )
    ]
    exchanges.append(contentsOf: ControllerTranscriptFixtures.successfulPassiveProbe(delayNanoseconds: 0))
    exchanges.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    exchanges.append(contentsOf: successfulPenCommands(.raise))
    exchanges.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    exchanges.append(exchange(request, ["ok\r\n"]))
    exchanges.append(statusExchange("<Idle|MPos:1.000,0.000,0.000>"))
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock)
    let controller = MachineController(
      link: link,
      motionLimits: try limits(),
      clock: fixture.clock,
      queryTimeoutNanoseconds: 10
    )

    let failed = await controller.runPassiveProbe()
    #expect(failed.blockers == [.timeout(.buildInfo)])
    #expect((await controller.snapshot()).connection == .disconnected)

    let retried = await controller.runPassiveProbe()
    #expect(retried.blockers.isEmpty)
    #expect(
      await controller.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )
    #expect(
      await controller.requestRelativeJog(request)
        == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0))
    )
    #expect(link.completedWriteCount == 12)
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

  @Test("disconnect after write stops later queries")
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

  @Test("closed session log does not block the probe")
  func storageDoesNotBlockWrite() async throws {
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
    #expect(result.blockers.isEmpty)
    #expect(result.exchanges.count == PassiveQuery.allCases.count)
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

@Suite("Bounded relative jog")
struct RelativeJogTests {
  @Test("GRBL jog bytes are closed and locale independent for every axis direction")
  func exactWireBytes() throws {
    let cases: [(Double, Double, Double, String)] = [
      (1.25, 0, 60, "$J=G91 G21 X1.250 F60.000\n"),
      (-1.25, 0, 60, "$J=G91 G21 X-1.250 F60.000\n"),
      (0, 2.5, 125.5, "$J=G91 G21 Y2.500 F125.500\n"),
      (0, -2.5, 125.5, "$J=G91 G21 Y-2.500 F125.500\n"),
    ]
    for (dx, dy, feed, expected) in cases {
      let request = try jog(dx: dx, dy: dy, feed: feed)
      #expect(MachineController.encodeRelativeJog(request) == Data(expected.utf8))
    }
  }

  @Test("typed geometry rejects nonfinite deltas and controller refuses zero or invalid feed")
  func numericRefusals() async throws {
    #expect(throws: GeometryError.nonFiniteCoordinate) {
      _ = try Vector2<MachineSpace>(dx: .nan, dy: 0)
    }
    #expect(throws: GeometryError.nonFiniteCoordinate) {
      _ = try Vector2<MachineSpace>(dx: 0, dy: .infinity)
    }

    let ready = try await readyController()
    #expect(await ready.controller.requestRelativeJog(try jog(dx: 0, dy: 0, feed: 60)) == .refused(.zeroDelta))
    #expect(
      await ready.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: 0))
        == .refused(.nonPositiveFeed(0)))
    #expect(
      await ready.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: -1))
        == .refused(.nonPositiveFeed(-1)))
    #expect(
      await ready.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: .infinity))
        == .refused(.nonPositiveFeed(.infinity)))
    #expect(
      await ready.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: 201))
        == .refused(.feedExceedsMaximum(requested: 201, maximum: 200)))
    #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 3)
  }

  @Test("distance and projected bounds are checked without clamping; boundary is accepted")
  func distanceAndBounds() async throws {
    let tooFar = try await readyController()
    #expect(
      await tooFar.controller.requestRelativeJog(try jog(dx: 5.01, dy: 0, feed: 60))
        == .refused(.distanceExceedsMaximum(requested: 5.01, maximum: 5)))

    let outside = try await readyController(status: "<Idle|MPos:9.000,0.000,0.000>")
    let outsideRequest = try jog(dx: 1.001, dy: 0, feed: 60)
    let outsidePosition = try MachinePosition(x: 10.001, y: 0)
    #expect(
      await outside.controller.requestRelativeJog(outsideRequest)
        == .refused(.destinationOutsideBounds(outsidePosition)))

    let boundaryRequest = try jog(dx: 1, dy: 0, feed: 60)
    let boundary = try await readyController(
      status: "<Idle|MPos:9.000,0.000,0.000>",
      motion: [
        exchange(boundaryRequest, ["ok\r\n"]),
        statusExchange("<Idle|MPos:10.000,0.000,0.000>"),
      ]
    )
    #expect(
      await boundary.controller.requestRelativeJog(boundaryRequest)
        == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 10, y: 0)))
  }

  @Test("completed jog returns its exact fresh-start and final-Idle controller evidence")
  func completedMotionEvidence() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let ready = try await readyController(motion: [
      exchange(request, ["ok\r\n"]),
      statusExchange("<Idle|MPos:1.000,0.000,0.000>"),
    ])

    let execution = await ready.controller.requestRelativeJogWithEvidence(request)

    #expect(
      execution.outcome
        == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)))
    let evidence = try #require(execution.completedEvidence)
    let expectedStart = try MachinePosition(x: 0, y: 0)
    let expectedFinal = try MachinePosition(x: 1, y: 0)
    #expect(evidence.request == request)
    #expect(evidence.startPosition == expectedStart)
    #expect(evidence.finalPosition == expectedFinal)
    #expect(evidence.startSampleNanoseconds > 0)
    #expect(evidence.finalSampleNanoseconds >= evidence.startSampleNanoseconds)
  }

  @Test("refused and ambiguous jogs cannot manufacture completed motion evidence")
  func incompleteMotionHasNoCompletedEvidence() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let refused = try await readyController(
      freshStatusExchange: statusExchange("<Idle|MPos:0.000,0.000,0.000|Pn:X>")
    )
    let refusedExecution = await refused.controller.requestRelativeJogWithEvidence(request)
    #expect(refusedExecution.completedEvidence == nil)
    #expect(refusedExecution.outcome == .refused(.relevantLimitAsserted("X")))

    let ambiguous = try await readyController(motion: [
      exchange(request, ["ok\r\n"]),
      disconnectingStatusExchange(),
    ])
    let ambiguousExecution = await ambiguous.controller.requestRelativeJogWithEvidence(request)
    #expect(ambiguousExecution.completedEvidence == nil)
    #expect(ambiguousExecution.outcome == .ambiguous(.disconnected))
  }

  @Test("wire quantization is the single safety and encoding identity")
  func wireQuantizationSafety() async throws {
    let roundedToZero = try await readyController()
    let tinyDelta = try jog(dx: 0.0004, dy: 0, feed: 60)
    #expect(
      await roundedToZero.controller.requestRelativeJog(tinyDelta) == .refused(.zeroDelta)
    )
    #expect(roundedToZero.link.completedWriteCount == PassiveQuery.allCases.count + 3)

    let tinyFeedController = try await readyController()
    let tinyFeed = try jog(dx: 1, dy: 0, feed: 0.0004)
    #expect(
      await tinyFeedController.controller.requestRelativeJog(tinyFeed)
        == .refused(.nonPositiveFeed(0))
    )
    #expect(tinyFeedController.link.completedWriteCount == PassiveQuery.allCases.count + 3)

    let roundedOutside = try await readyController(
      status: "<Idle|MPos:9.9995,0.000,0.000>"
    )
    let roundedUp = try jog(dx: 0.0006, dy: 0, feed: 60)
    #expect(MachineController.encodeRelativeJog(roundedUp) == Data("$J=G91 G21 X0.001 F60.000\n".utf8))
    let roundedOutcome = await roundedOutside.controller.requestRelativeJog(roundedUp)
    guard case .refused(.destinationOutsideBounds(let destination)) = roundedOutcome else {
      Issue.record("Expected quantized destination refusal, got \(roundedOutcome)")
      return
    }
    #expect(abs(destination.point.x - 10.0005) < 1e-12)
    #expect(roundedOutside.link.completedWriteCount == PassiveQuery.allCases.count + 4)
  }

  @Test("fresh pre-jog status failures close the stream before any jog bytes")
  func freshStatusFailuresSendNoJog() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let cases: [(SimulatedCommandExchange, MotionRefusal)] = [
      (
        statusExchange("<Alarm|MPos:0.000,0.000,0.000>"),
        .controllerAlarm("controller is in Alarm")
      ),
      (
        statusExchange("<Idle|MPos:0.000,0.000,0.000|Pn:X>"),
        .relevantLimitAsserted("X")
      ),
      (
        statusExchange("<Idle|MPos:9.500,0.000,0.000>"),
        .destinationOutsideBounds(try MachinePosition(x: 10.5, y: 0))
      ),
      (
        SimulatedCommandExchange(
          expectedWrite: PassiveQuery.status.wireBytes,
          reads: [ScheduledMachineRead(outcome: .bytes(Data("not-status\r\n".utf8)))]
        ),
        .freshStatusUnavailable(
          "fresh status reply was malformed: not-status"
        )
      ),
      (
        emptyStatusExchange(),
        .freshStatusUnavailable("fresh status query timed out")
      ),
      (
        disconnectingStatusExchange(),
        .freshStatusUnavailable("controller disconnected during the fresh status query")
      ),
    ]

    for (freshStatus, refusal) in cases {
      let ready = try await readyController(
        freshStatusExchange: freshStatus,
        queryTimeoutNanoseconds: 10
      )
      let outcome = await ready.controller.requestRelativeJog(request)
      #expect(outcome == .refused(refusal))
      #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 4)
      let snapshot = await ready.controller.snapshot()
      #expect(snapshot.connection == .disconnected)
      #expect(snapshot.controllerState == nil)
      #expect(snapshot.position == nil)
      #expect(snapshot.penState == .unknown)
      #expect(snapshot.stickyAmbiguity == nil)

      let directRetry = await ready.controller.requestRelativeJog(request)
      #expect(directRetry == .refused(.notConnected))
      #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 4)
    }
  }

  @Test("preflight discards stale buffered Idle before requesting current status")
  func staleBufferedIdleCannotAuthorizeJog() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let cases: [(String, MotionRefusal)] = [
      (
        "<Alarm|MPos:0.000,0.000,0.000>",
        .controllerAlarm("controller is in Alarm")
      ),
      (
        "<Idle|MPos:0.000,0.000,0.000|Pn:X>",
        .relevantLimitAsserted("X")
      ),
    ]

    for (currentStatus, refusal) in cases {
      let ready = try await readyController(
        freshStatusExchange: statusExchange(currentStatus)
      )
      ready.link.preloadPendingInput(Data("<Idle|MPos:0.000,0.000,0.000>\r\n".utf8))

      let outcome = await ready.controller.requestRelativeJog(request)

      #expect(outcome == .refused(refusal))
      #expect(ready.link.pendingInputDiscardCount == 2)
      #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 4)
      #expect((await ready.controller.snapshot()).connection == .disconnected)
    }
  }

  @Test("pending-input discard failure closes preflight without status or jog writes")
  func pendingInputDiscardFailure() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let ready = try await readyController()
    ready.link.preloadPendingInput(Data("<Idle|MPos:0.000,0.000,0.000>\r\n".utf8))
    ready.link.failNextPendingInputDiscard(
      with: .operatingSystem(code: EIO, operation: "simulated discard")
    )

    let outcome = await ready.controller.requestRelativeJog(request)

    guard case .refused(.freshStatusUnavailable(let reason)) = outcome else {
      Issue.record("Expected discard refusal, got \(outcome)")
      return
    }
    #expect(reason.contains("could not discard pending controller input"))
    #expect(ready.link.pendingInputDiscardCount == 2)
    #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 3)
    let snapshot = await ready.controller.snapshot()
    #expect(snapshot.connection == .disconnected)
    #expect(snapshot.position == nil)
    #expect(snapshot.penState == .unknown)
    #expect(snapshot.stickyAmbiguity == nil)
  }

  @Test("missing and malformed MPos refuse before any jog write")
  func missingPosition() async throws {
    for status in [
      "<Idle|WPos:0.000,0.000,0.000>",
      "<Idle|MPos:not-a-number,0.000,0.000>",
    ] {
      let ready = try await readyController(status: status)
      #expect(
        await ready.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: 60))
          == .refused(.machinePositionUnknown))
      #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 4)
      #expect((await ready.controller.snapshot()).connection == .disconnected)
    }
  }

  @Test("alarm, asserted limits, unknown pen, and missing limits refuse before write")
  func stateRefusals() async throws {
    let alarm = try await readyController(
      freshStatusExchange: statusExchange("<Alarm|MPos:0.000,0.000,0.000>")
    )
    #expect(
      await alarm.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: 60))
        == .refused(.controllerAlarm("controller is in Alarm")))

    let limit = try await readyController(status: "<Idle|MPos:0.000,0.000,0.000|Pn:X>")
    #expect(
      await limit.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: 60))
        == .refused(.relevantLimitAsserted("X")))

    let unknownPen = try await readyController(raisePen: false)
    #expect(
      await unknownPen.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: 60))
        == .refused(.penNotUp(.unknown)))

    let noLimits = try await readyController(configureLimits: false)
    #expect(
      await noLimits.controller.requestRelativeJog(try jog(dx: 1, dy: 0, feed: 60))
        == .refused(.motionLimitsMissing))
  }

  @Test("ok is acceptance only; Jog is polled until Idle supplies final MPos")
  func acceptanceThenCompletion() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let ready = try await readyController(motion: [
      exchange(request, ["ok\r\n"]),
      statusExchange("<Jog|MPos:0.400,0.000,0.000>"),
      statusExchange("<Idle|MPos:1.000,0.000,0.000>"),
    ])

    let outcome = await ready.controller.requestRelativeJog(request)

    #expect(outcome == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)))
    #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 7)
    let snapshot = await ready.controller.snapshot()
    #expect(snapshot.position == (try MachinePosition(x: 1, y: 0)))
    #expect(snapshot.controllerState == .idle)
  }

  @Test("completion timeout is derived from bounded distance and feed")
  func derivedTimeout() throws {
    let oneSecond = try jog(dx: 2, dy: 0, feed: 120)
    #expect(
      MachineController.completionTimeoutNanoseconds(
        for: oneSecond,
        graceNanoseconds: 250_000_000
      ) == 1_250_000_000)
    let halfSecond = try jog(dx: 1, dy: 0, feed: 120)
    #expect(
      MachineController.completionTimeoutNanoseconds(
        for: halfSecond,
        graceNanoseconds: 1
      ) == 500_000_001)

    let extreme = try jog(dx: 1e300, dy: 0, feed: 0.001)
    #expect(
      MachineController.completionTimeoutNanoseconds(for: extreme)
        == MachineController.maximumCompletionTimeoutNanoseconds
    )
    #expect(
      MachineController.completionTimeoutNanoseconds(
        for: try jog(dx: 1, dy: 0, feed: 60),
        graceNanoseconds: .max
      ) == MachineController.maximumCompletionTimeoutNanoseconds
    )
  }

  @Test("completion timeout respects controller axis feed caps and acceleration")
  func controllerAwareTimeout() throws {
    let request = try jog(dx: 10, dy: 0, feed: 900)
    let timing = MachineController.ControllerMotionTiming(
      maximumXFeedMMPerMinute: 500,
      maximumYFeedMMPerMinute: 500,
      xAccelerationMMPerSecondSquared: 10,
      yAccelerationMMPerSecondSquared: 10
    )
    let timeout = MachineController.completionTimeoutNanoseconds(
      for: request,
      controllerMotionTiming: timing,
      graceNanoseconds: 1_000_000_000
    )

    #expect(timeout > 3_000_000_000)
    #expect(timeout < 3_100_000_000)
    #expect(
      timeout
        > MachineController.completionTimeoutNanoseconds(
          for: request,
          graceNanoseconds: 1_000_000_000
        )
    )
  }

  @Test("passive configuration yields controller motion timing without using travel settings")
  func parsesControllerMotionTiming() {
    let exchange = PassiveProbeExchange(
      query: .configuration,
      commandID: UUID(),
      rawIO: [],
      lines: [
        parsedConfiguration("$110", "500"),
        parsedConfiguration("$111", "450"),
        parsedConfiguration("$120", "10"),
        parsedConfiguration("$121", "12"),
        parsedConfiguration("$130", "400"),
      ],
      completed: true,
      blocker: nil
    )

    #expect(
      MachineController.controllerMotionTiming(from: [exchange])
        == MachineController.ControllerMotionTiming(
          maximumXFeedMMPerMinute: 500,
          maximumYFeedMMPerMinute: 450,
          xAccelerationMMPerSecondSquared: 10,
          yAccelerationMMPerSecondSquared: 12
        )
    )
  }

  @Test("probed controller timing drives the live jog deadline")
  func probedTimingDrivesJogDeadline() async throws {
    let fixture = try await Fixture.make()
    let request = try jog(dx: 10, dy: 0, feed: 900)
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe(delayNanoseconds: 0)
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    exchanges[3] = ControllerTranscriptFixtures.exchange(
      .configuration,
      chunks: [
        "$110=500\r\n$111=500\r\n$120=10\r\n$121=10\r\n$130=400\r\n$131=215.9\r\nok\r\n"
      ]
    )
    exchanges.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    exchanges.append(contentsOf: successfulPenCommands(.raise))
    exchanges.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    exchanges.append(exchange(request, ["ok\r\n"]))
    exchanges.append(emptyStatusExchange())
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock)
    let controller = MachineController(
      link: link,
      motionLimits: try MotionLimits(
        bounds: AxisAlignedBounds<MachineSpace>(minX: -20, minY: -20, maxX: 20, maxY: 20),
        maximumDistanceMM: 10,
        maximumFeedMMPerMinute: 900
      ),
      clock: fixture.clock,
      queryTimeoutNanoseconds: 10,
      statusPollIntervalNanoseconds: 1,
      completionGraceNanoseconds: 1_000_000_000
    )
    _ = await controller.runPassiveProbe()
    #expect(
      await controller.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )

    guard case .ambiguous(.completionTimedOut(let deadline)) =
      await controller.requestRelativeJog(request)
    else {
      Issue.record("Expected the empty status exchange to expose the derived deadline")
      return
    }
    #expect(deadline > 3_000_000_000)
    #expect(deadline < 3_100_000_000)
  }

  @Test("one controller operation in flight rejects duplicate taps")
  func duplicateInFlight() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let clock = DeterministicRuntimeClock()
    var passive = ControllerTranscriptFixtures.successfulPassiveProbe()
    passive[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    passive.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    passive.append(contentsOf: successfulPenCommands(.raise))
    passive.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    passive.append(
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(request),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      )
    )
    passive.append(statusExchange("<Idle|MPos:1.000,0.000,0.000>"))
    let scriptedLink = SimulatedGRBLLink(exchanges: passive, clock: clock)
    let gate = MachineWriteGate()
    let link = BlockingMachineLink(
      base: scriptedLink,
      blockedWrite: MachineController.encodeRelativeJog(request),
      gate: gate
    )
    let controller = MachineController(
      link: link,
      motionLimits: try limits(),
      clock: clock,
      queryTimeoutNanoseconds: 100_000_000
    )
    _ = await controller.runPassiveProbe()
    #expect(
      await controller.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )

    let firstStarted = ControllerTaskStartHandshake()
    let firstTask = Task {
      await firstStarted.markStarted()
      return await controller.requestRelativeJog(request)
    }
    defer { firstTask.cancel() }

    await firstStarted.waitUntilStarted()
    await Task.yield()
    let (duplicate, firstOutcome) = await withTaskCancellationHandler {
      await gate.waitUntilBlockedWrite()
      let duplicate = await controller.requestRelativeJog(request)
      await gate.release()
      return (duplicate, await firstTask.value)
    } onCancel: {
      firstTask.cancel()
      Task { await gate.release() }
    }

    #expect(duplicate == .refused(.operationInFlight))
    #expect(
      firstOutcome == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)))
    #expect(scriptedLink.completedWriteCount == PassiveQuery.allCases.count + 6)
  }

  @Test("partial write is sticky and the same request is never resent")
  func stickyPartialWrite() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let total = MachineController.encodeRelativeJog(request).count
    let ready = try await readyController(motion: [
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(request),
        reads: [],
        writeError: .writeTimedOut(bytesWritten: 4, totalBytes: total)
      )
    ])

    let first = await ready.controller.requestRelativeJog(request)
    #expect(first == .ambiguous(.partialWrite(bytesWritten: 4, totalBytes: total)))
    let writesAfterFirst = ready.link.completedWriteCount
    let second = await ready.controller.requestRelativeJog(request)
    #expect(
      second == .refused(
        .stickyAmbiguity(.partialWrite(bytesWritten: 4, totalBytes: total))))
    #expect(ready.link.completedWriteCount == writesAfterFirst)
    #expect((await ready.controller.snapshot()).penState == .unknown)
  }

  @Test("disconnect, alarm, Hold, unexpected state, and malformed Idle are ambiguous")
  func postAcceptanceAmbiguities() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let cases: [([SimulatedCommandExchange], MotionAmbiguity)] = [
      ([exchange(request, ["ok\r\n"]), disconnectingStatusExchange()], .disconnected),
      (
        [exchange(request, ["ok\r\n"]), statusExchange("<Alarm|MPos:0.500,0.000,0.000>")],
        .controllerAlarm("Alarm")
      ),
      (
        [exchange(request, ["ok\r\n"]), statusExchange("<Hold:0|MPos:0.500,0.000,0.000>")],
        .controllerHold
      ),
      (
        [exchange(request, ["ok\r\n"]), statusExchange("<Door|MPos:0.500,0.000,0.000>")],
        .unexpectedControllerState(.door)
      ),
      (
        [exchange(request, ["ok\r\n"]), statusExchange("<Idle|MPos:bad,0.000,0.000>")],
        .malformedReply("Idle status omitted a valid MPos")
      ),
    ]

    for (motion, expected) in cases {
      let ready = try await readyController(motion: motion)
      #expect(await ready.controller.requestRelativeJog(request) == .ambiguous(expected))
      #expect((await ready.controller.snapshot()).stickyAmbiguity == expected)
    }
  }

  @Test("accepted jog with no final status reaches sticky bounded timeout")
  func completionTimeout() async throws {
    let request = try jog(dx: 0.001, dy: 0, feed: 200)
    let ready = try await readyController(
      motion: [exchange(request, ["ok\r\n"]), emptyStatusExchange()],
      queryTimeoutNanoseconds: 10,
      completionGraceNanoseconds: 10
    )
    let outcome = await ready.controller.requestRelativeJog(request)
    guard case .ambiguous(.completionTimedOut) = outcome else {
      Issue.record("Expected completion timeout, got \(outcome)")
      return
    }
    guard case .completionTimedOut = (await ready.controller.snapshot()).stickyAmbiguity else {
      Issue.record("Expected sticky completion timeout")
      return
    }
  }

  @Test("explicit controller rejection is retryable immediately")
  func correctedRefusalRetries() async throws {
    let request = try jog(dx: 1, dy: 0, feed: 60)
    let ready = try await readyController(motion: [
      exchange(request, ["error:15\r\n"]),
      statusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      exchange(request, ["ok\r\n"]),
      statusExchange("<Idle|MPos:1.000,0.000,0.000>"),
    ])
    #expect(
      await ready.controller.requestRelativeJog(request)
        == .refused(.controllerRejected("error:15")))
    #expect(
      await ready.controller.requestRelativeJog(request)
        == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)))
  }

  @Test("closed diagnostic log does not block an otherwise valid jog")
  func loggingFailureDoesNotBlockMotion() async throws {
    let fixture = try await Fixture.make()
    await fixture.ledger.close()
    let request = try jog(dx: 1, dy: 0, feed: 60)
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    exchanges.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    exchanges.append(contentsOf: successfulPenCommands(.raise))
    exchanges.append(statusExchange("<Idle|MPos:0.000,0.000,0.000>"))
    exchanges.append(contentsOf: [
      exchange(request, ["ok\r\n"]),
      statusExchange("<Idle|MPos:1.000,0.000,0.000>"),
    ])
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock)
    let controller = MachineController(
      link: link,
      motionLimits: try limits(),
      ledger: fixture.ledger,
      runID: fixture.runID,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 1_000
    )
    _ = await controller.runPassiveProbe()
    #expect(
      await controller.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )
    #expect(
      await controller.requestRelativeJog(request)
        == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)))
  }

  @Test("passive probes are repeatable through one persistent open session")
  func repeatablePassiveProbe() async throws {
    let fixture = try await Fixture.make()
    let transcripts = ControllerTranscriptFixtures.successfulPassiveProbe()
      + ControllerTranscriptFixtures.successfulPassiveProbe()
    let link = SimulatedGRBLLink(exchanges: transcripts, clock: fixture.clock)
    let controller = MachineController(
      link: link,
      clock: fixture.clock,
      queryTimeoutNanoseconds: 1_000
    )
    let first = await controller.runPassiveProbe()
    let second = await controller.runPassiveProbe()
    #expect(first.blockers.isEmpty)
    #expect(second.blockers.isEmpty)
    #expect(link.completedWriteCount == PassiveQuery.allCases.count * 2)
    #expect((await controller.snapshot()).connection == .connected)
  }
}

@Suite("Typed pen actuation")
struct PenActuationTests {
  @Test("legacy pen profile is a closed exact wire surface")
  func exactWireBytes() {
    let profile = PenActuationProfile.legacyServo
    #expect(profile.raisedSpindleValue == 40)
    #expect(profile.loweredSpindleValue == 720)
    #expect(profile.settleSeconds == 0.3)
    #expect(MachineController.encodePenActuation(.raise) == Data("M3 S40\n".utf8))
    #expect(MachineController.encodePenActuation(.lower) == Data("M3 S720\n".utf8))
    #expect(MachineController.encodePenSettle == Data("G4 P0.3\n".utf8))
  }

  @Test("raising requires fresh Idle but not limits or a known position")
  func raiseIsRecoveryAction() async throws {
    let ready = try await penReadyController(
      status: "<Idle|WPos:0.000,0.000,0.000>",
      configureLimits: false,
      commands: successfulPenCommands(.raise)
    )

    let outcome = await ready.controller.requestPenActuation(.raise)

    #expect(outcome == .commandedAndSettled(command: .raise, commandedState: .up))
    let snapshot = await ready.controller.snapshot()
    #expect(snapshot.penState == .up)
    #expect(snapshot.lastPenOutcome == outcome)
    #expect(snapshot.connection == .connected)
    #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 3)
  }

  @Test("lowering requires fresh in-bounds MPos, limits, and no XY limit")
  func lowerSafetyBoundary() async throws {
    let accepted = try await penReadyController(commands: successfulPenCommands(.lower))
    let acceptedOutcome = await accepted.controller.requestPenActuation(.lower)
    #expect(acceptedOutcome == .commandedAndSettled(command: .lower, commandedState: .down))
    #expect((await accepted.controller.snapshot()).penState == .down)

    let noLimits = try await penReadyController(configureLimits: false)
    #expect(
      await noLimits.controller.requestPenActuation(.lower)
        == .refused(.motionLimitsMissing)
    )
    #expect(noLimits.link.completedWriteCount == PassiveQuery.allCases.count)

    let noPosition = try await penReadyController(status: "<Idle|WPos:0.000,0.000,0.000>")
    #expect(
      await noPosition.controller.requestPenActuation(.lower)
        == .refused(.machinePositionUnknown)
    )
    #expect((await noPosition.controller.snapshot()).connection == .disconnected)

    let outsidePosition = try MachinePosition(x: 11, y: 0)
    let outside = try await penReadyController(status: "<Idle|MPos:11.000,0.000,0.000>")
    #expect(
      await outside.controller.requestPenActuation(.lower)
        == .refused(.machinePositionOutsideBounds(outsidePosition))
    )

    let asserted = try await penReadyController(
      status: "<Idle|MPos:0.000,0.000,0.000|Pn:X>"
    )
    #expect(
      await asserted.controller.requestPenActuation(.lower)
        == .refused(.relevantLimitAsserted("X"))
    )
  }

  @Test("fresh non-Idle or alarm state closes before pen bytes")
  func freshStateRefusals() async throws {
    let cases: [(String, PenRefusal)] = [
      ("<Run|MPos:0.000,0.000,0.000>", .controllerNotIdle(.run)),
      ("<Alarm|MPos:0.000,0.000,0.000>", .controllerAlarm("controller is in Alarm")),
    ]
    for (status, refusal) in cases {
      let ready = try await penReadyController(freshStatus: status)
      #expect(await ready.controller.requestPenActuation(.raise) == .refused(refusal))
      #expect(ready.link.completedWriteCount == PassiveQuery.allCases.count + 1)
      let snapshot = await ready.controller.snapshot()
      #expect(snapshot.connection == .disconnected)
      #expect(snapshot.penState == .unknown)
    }
  }

  @Test("partial actuation write is sticky, unknown, and never resent")
  func partialWriteIsSticky() async throws {
    let bytes = MachineController.encodePenActuation(.raise)
    let ready = try await penReadyController(commands: [
      SimulatedCommandExchange(
        expectedWrite: bytes,
        reads: [],
        writeError: .writeTimedOut(bytesWritten: 3, totalBytes: bytes.count)
      )
    ])

    let first = await ready.controller.requestPenActuation(.raise)
    let ambiguity = MotionAmbiguity.partialWrite(bytesWritten: 3, totalBytes: bytes.count)
    #expect(first == .ambiguous(ambiguity))
    let writes = ready.link.completedWriteCount
    #expect(
      await ready.controller.requestPenActuation(.raise)
        == .refused(.stickyAmbiguity(ambiguity))
    )
    #expect(ready.link.completedWriteCount == writes)
    let snapshot = await ready.controller.snapshot()
    #expect(snapshot.penState == .unknown)
    #expect(snapshot.stickyAmbiguity == ambiguity)
  }

  @Test("accepted actuation with rejected settle is sticky and not physical proof")
  func settleRejectionIsSticky() async throws {
    let ready = try await penReadyController(commands: [
      penExchange(.raise, chunks: ["ok\r\n"]),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("error:20\r\n".utf8)))]
      ),
    ])

    let ambiguity = MotionAmbiguity.settleCommandRejected("error:20")
    #expect(await ready.controller.requestPenActuation(.raise) == .ambiguous(ambiguity))
    let snapshot = await ready.controller.snapshot()
    #expect(snapshot.penState == .unknown)
    #expect(snapshot.stickyAmbiguity == ambiguity)
  }

  @Test("controller reset after pen write is sticky and clears commanded state")
  func resetAfterWriteIsSticky() async throws {
    let ready = try await penReadyController(commands: [
      penExchange(.raise, chunks: ["Grbl 1.1h ['$' for help]\r\n"])
    ])

    let ambiguity = MotionAmbiguity.malformedReply(
      "controller reset greeting arrived after pen actuation"
    )
    #expect(await ready.controller.requestPenActuation(.raise) == .ambiguous(ambiguity))
    let snapshot = await ready.controller.snapshot()
    #expect(snapshot.penState == .unknown)
    #expect(snapshot.stickyAmbiguity == ambiguity)
  }

  @Test("pre-actuation controller rejection is retryable")
  func rejectionBeforeActuationRetries() async throws {
    let ready = try await penReadyController(commands: [
      penExchange(.raise, chunks: ["error:15\r\n"]),
      statusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      penExchange(.raise, chunks: ["ok\r\n"]),
      penSettleExchange(chunks: ["ok\r\n"]),
    ])

    #expect(
      await ready.controller.requestPenActuation(.raise)
        == .refused(.controllerRejected("error:15"))
    )
    #expect(
      await ready.controller.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )
  }

  @Test("disconnect clears commanded pen state")
  func disconnectClearsState() async throws {
    let ready = try await penReadyController(commands: successfulPenCommands(.raise))
    _ = await ready.controller.requestPenActuation(.raise)
    #expect((await ready.controller.snapshot()).penState == .up)

    await ready.controller.disconnect()

    let snapshot = await ready.controller.snapshot()
    #expect(snapshot.connection == .disconnected)
    #expect(snapshot.penState == .unknown)
  }
}

private func jog(dx: Double, dy: Double, feed: Double) throws -> RelativeJogRequest {
  RelativeJogRequest(
    delta: try Vector2<MachineSpace>(dx: dx, dy: dy),
    feedMMPerMinute: feed
  )
}

private func penExchange(_ command: PenCommand, chunks: [String]) -> SimulatedCommandExchange {
  SimulatedCommandExchange(
    expectedWrite: MachineController.encodePenActuation(command),
    reads: chunks.map { ScheduledMachineRead(outcome: .bytes(Data($0.utf8))) }
  )
}

private func penSettleExchange(chunks: [String]) -> SimulatedCommandExchange {
  SimulatedCommandExchange(
    expectedWrite: MachineController.encodePenSettle,
    reads: chunks.map { ScheduledMachineRead(outcome: .bytes(Data($0.utf8))) }
  )
}

private func successfulPenCommands(_ command: PenCommand) -> [SimulatedCommandExchange] {
  [
    penExchange(command, chunks: ["ok\r\n"]),
    penSettleExchange(chunks: ["ok\r\n"]),
  ]
}

private func parsedConfiguration(_ key: String, _ value: String) -> ParsedControllerLine {
  let text = "\(key)=\(value)"
  return ParsedControllerLine(
    rawBytes: Data(text.utf8),
    text: text,
    kind: .configuration(key: key, value: value)
  )
}

private func limits() throws -> MotionLimits {
  try MotionLimits(
    bounds: AxisAlignedBounds<MachineSpace>(minX: -10, minY: -10, maxX: 10, maxY: 10),
    maximumDistanceMM: 5,
    maximumFeedMMPerMinute: 200
  )
}

private func exchange(_ request: RelativeJogRequest, _ chunks: [String]) -> SimulatedCommandExchange {
  SimulatedCommandExchange(
    expectedWrite: MachineController.encodeRelativeJog(request),
    reads: chunks.map { ScheduledMachineRead(outcome: .bytes(Data($0.utf8))) }
  )
}

private func statusExchange(_ status: String) -> SimulatedCommandExchange {
  SimulatedCommandExchange(
    expectedWrite: PassiveQuery.status.wireBytes,
    reads: [ScheduledMachineRead(outcome: .bytes(Data("\(status)\r\n".utf8)))]
  )
}

private func disconnectingStatusExchange() -> SimulatedCommandExchange {
  SimulatedCommandExchange(
    expectedWrite: PassiveQuery.status.wireBytes,
    reads: [ScheduledMachineRead(outcome: .disconnect)]
  )
}

private func emptyStatusExchange() -> SimulatedCommandExchange {
  SimulatedCommandExchange(expectedWrite: PassiveQuery.status.wireBytes, reads: [])
}

private func readyController(
  status: String = "<Idle|MPos:0.000,0.000,0.000>",
  motion: [SimulatedCommandExchange] = [],
  freshStatusExchange: SimulatedCommandExchange? = nil,
  raisePen: Bool = true,
  configureLimits: Bool = true,
  queryTimeoutNanoseconds: UInt64 = 1_000,
  completionGraceNanoseconds: UInt64 = 1_000
) async throws -> (controller: MachineController, link: SimulatedGRBLLink) {
  let fixture = try await Fixture.make()
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe(delayNanoseconds: 0)
  exchanges[2] = ControllerTranscriptFixtures.exchange(.status, chunks: ["\(status)\r\n"])
  if raisePen {
    exchanges.append(statusExchange(status))
    exchanges.append(contentsOf: successfulPenCommands(.raise))
  }
  exchanges.append(freshStatusExchange ?? statusExchange(status))
  exchanges.append(contentsOf: motion)
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock)
  let controller = MachineController(
    link: link,
    motionLimits: configureLimits ? try limits() : nil,
    ledger: fixture.ledger,
    runID: fixture.runID,
    clock: fixture.clock,
    queryTimeoutNanoseconds: queryTimeoutNanoseconds,
    statusPollIntervalNanoseconds: 1,
    completionGraceNanoseconds: completionGraceNanoseconds
  )
  _ = await controller.runPassiveProbe()
  if raisePen {
    #expect(
      await controller.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )
  }
  return (controller, link)
}

private func penReadyController(
  status: String = "<Idle|MPos:0.000,0.000,0.000>",
  freshStatus: String? = nil,
  configureLimits: Bool = true,
  commands: [SimulatedCommandExchange] = [],
  queryTimeoutNanoseconds: UInt64 = 1_000
) async throws -> (controller: MachineController, link: SimulatedGRBLLink) {
  let fixture = try await Fixture.make()
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe(delayNanoseconds: 0)
  exchanges[2] = ControllerTranscriptFixtures.exchange(.status, chunks: ["\(status)\r\n"])
  exchanges.append(statusExchange(freshStatus ?? status))
  exchanges.append(contentsOf: commands)
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: fixture.clock)
  let controller = MachineController(
    link: link,
    motionLimits: configureLimits ? try limits() : nil,
    ledger: fixture.ledger,
    runID: fixture.runID,
    clock: fixture.clock,
    queryTimeoutNanoseconds: queryTimeoutNanoseconds,
    statusPollIntervalNanoseconds: 1,
    completionGraceNanoseconds: 1_000
  )
  _ = await controller.runPassiveProbe()
  return (controller, link)
}

private func waitForLedgerEvent(
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

private actor ControllerTaskStartHandshake {
  private var started = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func markStarted() {
    started = true
    let pending = waiters
    waiters.removeAll(keepingCapacity: false)
    for waiter in pending { waiter.resume() }
  }

  func waitUntilStarted() async {
    guard !started else { return }
    await withCheckedContinuation { waiters.append($0) }
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
