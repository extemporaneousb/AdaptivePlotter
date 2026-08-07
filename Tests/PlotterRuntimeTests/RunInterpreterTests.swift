import Darwin
import Foundation
import PlotterModel
@testable import PlotterRuntime
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
    exchanges.append(contentsOf: [
      interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(.raise),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
    ])
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
    #expect(await fixture.interpreter.activateMotionGuard() == .activated)
    #expect(
      await fixture.interpreter.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )

    let outcome = await fixture.interpreter.requestRelativeJog(request)
    let snapshot = await fixture.interpreter.snapshot()

    #expect(outcome == .acceptedThenCompleted(finalPosition: try MachinePosition(x: 1, y: 0)))
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastMotionOutcome == outcome)
  }

  @Test("priority Jog Cancel passes through while the interpreter is awaiting Idle")
  func priorityJogCancel() async throws {
    let ready = try await readyInterpreterCancellationFixture()
    #expect(await ready.interpreter.requestJogCancel() == .refused(.noActiveJog))
    let motionTask = Task {
      await ready.interpreter.requestRelativeJog(ready.request)
    }
    defer { motionTask.cancel() }
    await ready.gate.waitUntilBlockedRead()

    let cancelTask = Task { await ready.interpreter.requestJogCancel() }
    defer { cancelTask.cancel() }
    await waitForInterpreterWriteCount(ready.link, atLeast: ready.writesThroughCancel)
    await waitForInterpreterCancelTransmission(ready.interpreter)

    var snapshot = await ready.interpreter.snapshot()
    #expect(snapshot.currentOperation == .relativeJog(ready.request))
    #expect(snapshot.jogCancellationInFlight)
    #expect(snapshot.lastJogCancelOutcome == .transmitted)
    #expect(await ready.interpreter.requestJogCancel() == .refused(.alreadyRequested))

    await ready.gate.release()
    let finalPosition = try MachinePosition(x: 0.4, y: 0)
    #expect(await cancelTask.value == .completed(finalPosition: finalPosition))
    #expect(await motionTask.value == .cancelled(finalPosition: finalPosition))
    snapshot = await ready.interpreter.snapshot()
    #expect(snapshot.currentOperation == .idle)
    #expect(!snapshot.jogCancellationInFlight)
    #expect(snapshot.lastJogCancelOutcome == .completed(finalPosition: finalPosition))
    #expect(snapshot.lastMotionOutcome == .cancelled(finalPosition: finalPosition))
  }

  @Test("interpreter projects the controller refusal when no session is connected")
  func disconnectedJogCancelRefusal() async throws {
    let fixture = try await InterpreterFixture.make()

    #expect(await fixture.interpreter.requestJogCancel() == .refused(.notConnected))
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastJogCancelOutcome == .refused(.notConnected))
    #expect(fixture.link.completedWriteCount == 0)
  }

  @Test("typed pen actuation records controller-commanded state and outcome")
  func typedPenActuation() async throws {
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    exchanges.append(contentsOf: [
      interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(.raise),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
    ])
    let fixture = try await InterpreterFixture.make(exchanges: exchanges)
    _ = try await fixture.interpreter.requestPassiveProbe()
    #expect(await fixture.interpreter.activateMotionGuard() == .activated)

    let outcome = await fixture.interpreter.requestPenActuation(.raise)
    let snapshot = await fixture.interpreter.snapshot()

    #expect(outcome == .commandedAndSettled(command: .raise, commandedState: .up))
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastPenOutcome == outcome)
    #expect(snapshot.machine.lastPenOutcome == outcome)
    #expect(snapshot.machine.penState == .up)
  }

  @Test("pen operation serializes against jog")
  func penSerializesAgainstJog() async throws {
    let clock = DeterministicRuntimeClock()
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe(
      delayNanoseconds: 0
    )
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    exchanges.append(contentsOf: [
      interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(.raise),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
    ])
    let scriptedLink = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
    let gate = MachineWriteGate()
    let link = BlockingMachineLink(
      base: scriptedLink,
      blockedWrite: MachineController.encodePenActuation(.raise),
      gate: gate
    )
    let controller = MachineController(
      link: link,
      clock: clock,
      queryTimeoutNanoseconds: 100_000_000
    )
    let interpreter = RunInterpreter(machineController: controller)
    _ = try await interpreter.requestPassiveProbe()
    #expect(await interpreter.activateMotionGuard() == .activated)
    let jog = RelativeJogRequest(
      delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
      feedMMPerMinute: 60
    )

    let penStarted = TaskStartHandshake()
    let penTask = Task {
      await penStarted.markStarted()
      return await interpreter.requestPenActuation(.raise)
    }
    defer { penTask.cancel() }

    await penStarted.waitUntilStarted()
    await Task.yield()
    let (jogOutcome, penOutcome) = await withTaskCancellationHandler {
      await gate.waitUntilBlockedWrite()
      let jogOutcome = await interpreter.requestRelativeJog(jog)
      await gate.release()
      return (jogOutcome, await penTask.value)
    } onCancel: {
      penTask.cancel()
      Task { await gate.release() }
    }

    #expect(jogOutcome == .refused(.operationInFlight))
    #expect(penOutcome == .commandedAndSettled(command: .raise, commandedState: .up))
    #expect(scriptedLink.completedWriteCount == PassiveQuery.allCases.count + 3)
  }

  @Test("failed before observation sends no machine writes")
  func failedBeforeObservationSendsNoMachineWrites() async throws {
    let fixture = try await InterpreterFixture.make()
    let request = try physicalJogRequest()

    let outcome = await fixture.interpreter.requestObservedJog(
      request,
      observe: { phase, newerThan in
        #expect(phase == .beforeMotion)
        #expect(newerThan == 0)
        return .failure(.frameUnavailable(.beforeMotion))
      }
    )

    #expect(
      outcome == .notRecorded(
        motionOutcome: nil,
        failure: .frameUnavailable(.beforeMotion)
      )
    )
    #expect(fixture.link.completedWriteCount == 0)
    #expect(await fixture.interpreter.snapshot().lastMotionOutcome == nil)
  }

  @Test("observed jog captures strictly ordered evidence around one motion")
  func observedJogCapturesStrictlyOrderedEvidence() async throws {
    let request = try physicalJogRequest()
    let before = try await visibleObservation(
      id: "before", sequence: 1, captureNanoseconds: 100)
    let midMotion = try await visibleObservation(
      id: "mid-motion", sequence: 2, captureNanoseconds: 200, capOffsetX: 1)
    let after = try await visibleObservation(
      id: "after", sequence: 3, captureNanoseconds: 350, capOffsetX: 3, capOffsetY: -2)
    let script = FreshObservationScript(before: before, postCandidates: [midMotion, after])
    let fixture = try await readyObservedJogFixture(
      request: request.motion,
      clockStartNanoseconds: 100,
      finalStatusDelayNanoseconds: 150
    )
    let writesBeforeMotion = fixture.link.completedWriteCount

    let outcome = await fixture.interpreter.requestObservedJog(
      request,
      observe: { phase, newerThan in
        await script.next(phase: phase, newerThan: newerThan)
      }
    )

    guard case .recorded(let observation) = outcome else {
      Issue.record("Expected a recorded observed jog, got \(outcome)")
      return
    }
    let expectedStart = try MachinePosition(x: 0, y: 0)
    let expectedFinal = try MachinePosition(x: 1, y: 0)
    let expectedCameraDelta = try Vector2<CameraPixelSpace>(dx: 3, dy: -2)
    #expect(observation.startPosition == expectedStart)
    #expect(observation.finalPosition == expectedFinal)
    #expect(observation.startControllerSampleNanoseconds == 150)
    #expect(observation.finalControllerSampleNanoseconds == 300)
    #expect(observation.before.captureNanoseconds <= observation.startControllerSampleNanoseconds)
    #expect(observation.after.captureNanoseconds > observation.finalControllerSampleNanoseconds)
    #expect(observation.before == before)
    #expect(observation.after == after)
    #expect(observation.cameraDelta == expectedCameraDelta)
    #expect(
      await script.calls == [
        ObservationCall(phase: .beforeMotion, newerThan: 0),
        ObservationCall(phase: .afterMotion, newerThan: 300),
      ]
    )
    #expect(fixture.link.completedWriteCount == writesBeforeMotion + 3)
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastMotionOutcome == .acceptedThenCompleted(
      finalPosition: try MachinePosition(x: 1, y: 0)))
    #expect(snapshot.lastPhysicalJogObservationOutcome == outcome)
  }

  @Test("motion refusal skips after observation and preserves the refusal")
  func motionRefusalSkipsAfterObservation() async throws {
    let fixture = try await InterpreterFixture.make()
    let before = try await visibleObservation(
      id: "before", sequence: 1, captureNanoseconds: 10)
    let script = ObservationScript(results: [.success(before)])
    let request = try physicalJogRequest()

    let outcome = await fixture.interpreter.requestObservedJog(
      request,
      observe: { phase, newerThan in
        await script.next(phase: phase, newerThan: newerThan)
      }
    )
    let refusal = MotionOutcome.refused(.notConnected)

    #expect(
      outcome == .notRecorded(
        motionOutcome: refusal,
        failure: .motionNotCompleted(refusal)
      )
    )
    #expect(await script.calls.count == 1)
    #expect(fixture.link.completedWriteCount == 0)
  }

  @Test("missing post-completion frame preserves completed motion without resend")
  func missingPostCompletionFramePreservesCompletedMotion() async throws {
    let request = try physicalJogRequest()
    let before = try await visibleObservation(
      id: "before", sequence: 1, captureNanoseconds: 100)
    let midMotion = try await visibleObservation(
      id: "mid-motion", sequence: 2, captureNanoseconds: 200, capOffsetX: 1)
    let script = FreshObservationScript(before: before, postCandidates: [midMotion])
    let fixture = try await readyObservedJogFixture(
      request: request.motion,
      clockStartNanoseconds: 100,
      finalStatusDelayNanoseconds: 150
    )
    let writesBeforeMotion = fixture.link.completedWriteCount
    let completed = MotionOutcome.acceptedThenCompleted(
      finalPosition: try MachinePosition(x: 1, y: 0))

    let outcome = await fixture.interpreter.requestObservedJog(
      request,
      observe: { phase, newerThan in
        await script.next(phase: phase, newerThan: newerThan)
      }
    )

    #expect(
      outcome == .notRecorded(
        motionOutcome: completed,
        failure: .frameUnavailable(.afterMotion)
      )
    )
    #expect(
      await script.calls == [
        ObservationCall(phase: .beforeMotion, newerThan: 0),
        ObservationCall(phase: .afterMotion, newerThan: 300),
      ]
    )
    #expect(fixture.link.completedWriteCount == writesBeforeMotion + 3)
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.lastMotionOutcome == completed)
    #expect(snapshot.machine.stickyAmbiguity == nil)
    let expectedFinal = try MachinePosition(x: 1, y: 0)
    #expect(snapshot.machine.position == expectedFinal)
  }

  @Test("observed operation refuses duplicate jog pen and probe requests")
  func observedOperationSerializesAllPhysicalRequests() async throws {
    let fixture = try await InterpreterFixture.make()
    let request = try physicalJogRequest()
    let gate = BlockingObservation()
    let observedTask = Task {
      await fixture.interpreter.requestObservedJog(
        request,
        observe: { phase, newerThan in
          await gate.observe(phase: phase, newerThan: newerThan)
        }
      )
    }
    await gate.waitUntilRequested()

    #expect(
      await fixture.interpreter.requestRelativeJog(request.motion)
        == .refused(.operationInFlight)
    )
    #expect(
      await fixture.interpreter.requestPenActuation(.raise)
        == .refused(.operationInFlight)
    )
    await #expect(throws: RunInterpreterError.transitionAlreadyInFlight) {
      try await fixture.interpreter.requestPassiveProbe()
    }
    let duplicate = await fixture.interpreter.requestObservedJog(
      request,
      observe: { _, _ in
        Issue.record("A duplicate observed jog must not request a camera frame")
        return .failure(.frameUnavailable(.beforeMotion))
      }
    )
    let refused = MotionOutcome.refused(.operationInFlight)
    #expect(
      duplicate == .notRecorded(
        motionOutcome: refused,
        failure: .motionNotCompleted(refused)
      )
    )

    await gate.release(with: .failure(.frameUnavailable(.beforeMotion)))
    #expect(
      await observedTask.value == .notRecorded(
        motionOutcome: nil,
        failure: .frameUnavailable(.beforeMotion)
      )
    )
    #expect(fixture.link.completedWriteCount == 0)
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

private func interpreterStatusExchange(
  _ status: String,
  delayNanoseconds: UInt64 = 0
) -> SimulatedCommandExchange {
  SimulatedCommandExchange(
    expectedWrite: PassiveQuery.status.wireBytes,
    reads: [
      ScheduledMachineRead(
        delayNanoseconds: delayNanoseconds,
        outcome: .bytes(Data("\(status)\r\n".utf8))
      )
    ]
  )
}

private func physicalJogRequest() throws -> PhysicalJogObservationRequest {
  PhysicalJogObservationRequest(
    motion: RelativeJogRequest(
      delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
      feedMMPerMinute: 60
    ),
    split: .training
  )
}

private func visibleObservation(
  id: String,
  sequence: UInt64,
  captureNanoseconds: UInt64,
  configurationID: CameraConfigurationID = CameraConfigurationID(
    UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
  ),
  capOffsetX: Int = 0,
  capOffsetY: Int = 0
) async throws -> VisibleToolFrameObservation {
  let frame = try observedJogCapFrame(
    id: FrameID(rawValue: id),
    sequence: sequence,
    captureNanoseconds: captureNanoseconds,
    configurationID: configurationID,
    capOffsetX: capOffsetX,
    capOffsetY: capOffsetY
  )
  return try VisibleToolFrameObservation(
    phase: sequence == 1 ? .beforeMotion : .afterMotion,
    displayedFrame: DisplayedFrame(
      source: .live(CameraDeviceID(rawValue: "observed-jog-camera")),
      frame: frame
    ),
    measurement: try await observedJogSceneMeasurement(frame)
  )
}

private func observedJogCapFrame(
  id: FrameID,
  sequence: UInt64,
  captureNanoseconds: UInt64,
  configurationID: CameraConfigurationID,
  capOffsetX: Int,
  capOffsetY: Int
) throws -> StampedFrame {
  let width = 12
  let height = 12
  var bytes = Array(repeating: UInt8(0), count: width * height * 4)
  for y in (4 + capOffsetY)...(5 + capOffsetY) {
    for x in (4 + capOffsetX)...(5 + capOffsetX) {
      let offset = (y * width + x) * 4
      bytes[offset + 1] = 255
      bytes[offset + 3] = 255
    }
  }
  return try StampedFrame(
    id: id,
    sequence: sequence,
    captureNanoseconds: captureNanoseconds,
    cameraConfigurationID: configurationID,
    width: width,
    height: height,
    rowBytes: width * 4,
    pixelFormat: .bgra8,
    bytes: OwnedFrameBytes(bytes)
  )
}

private func observedJogSceneMeasurement(
  _ frame: StampedFrame
) async throws -> PlotterSceneMeasurement {
  let priors = try PlotterSceneVisionPriors(
    capSearchRegion: PixelRect(x: 0, y: 0, width: frame.width, height: frame.height),
    topFrameSideRegion: PixelRect(x: 0, y: 0, width: frame.width, height: 3),
    rightFrameSideRegion: PixelRect(
      x: frame.width - 3,
      y: 0,
      width: 3,
      height: frame.height
    ),
    minimumCapPixels: 3,
    maximumCapPixels: 16,
    lineResidualLimitPixels: 2,
    algorithmRevision: "observed-jog-test-v1"
  )
  return try await VisionWorker().inspectPlotterScene(in: frame, priors: priors)
}

private func readyObservedJogFixture(
  request: RelativeJogRequest,
  clockStartNanoseconds: UInt64 = 1_000_000,
  finalStatusDelayNanoseconds: UInt64 = 0
) async throws -> InterpreterFixture {
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
  exchanges[2] = ControllerTranscriptFixtures.exchange(
    .status,
    chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
  )
  exchanges.append(contentsOf: [
    interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.raise),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeRelativeJog(request),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange(
      "<Idle|MPos:1.000,0.000,0.000>",
      delayNanoseconds: finalStatusDelayNanoseconds
    ),
  ])
  let fixture = try await InterpreterFixture.make(
    exchanges: exchanges,
    clock: DeterministicRuntimeClock(startNanoseconds: clockStartNanoseconds)
  )
  _ = try await fixture.interpreter.requestPassiveProbe()
  #expect(await fixture.interpreter.activateMotionGuard() == .activated)
  #expect(
    await fixture.interpreter.requestPenActuation(.raise)
      == .commandedAndSettled(command: .raise, commandedState: .up)
  )
  return fixture
}

private func readyInterpreterCancellationFixture() async throws -> (
  interpreter: RunInterpreter,
  request: RelativeJogRequest,
  link: SimulatedGRBLLink,
  gate: InterpreterMachineReadGate,
  writesThroughCancel: Int
) {
  let request = RelativeJogRequest(
    delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
    feedMMPerMinute: 60
  )
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
  exchanges[2] = ControllerTranscriptFixtures.exchange(
    .status,
    chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
  )
  exchanges.append(contentsOf: [
    interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.raise),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeRelativeJog(request),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Jog|MPos:0.200,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeJogCancel,
      reads: []
    ),
  ])
  let writesThroughCancel = exchanges.count
  exchanges.append(interpreterStatusExchange("<Idle|MPos:0.400,0.000,0.000>"))

  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let gate = InterpreterMachineReadGate()
  let blockingLink = InterpreterPostJogReadBlockingLink(
    base: link,
    jogBytes: MachineController.encodeRelativeJog(request),
    gate: gate
  )
  let controller = MachineController(
    link: blockingLink,
    clock: clock,
    queryTimeoutNanoseconds: 1_000,
    statusPollIntervalNanoseconds: 1,
    completionGraceNanoseconds: 1_000
  )
  let interpreter = RunInterpreter(machineController: controller)
  _ = try await interpreter.requestPassiveProbe()
  #expect(await interpreter.activateMotionGuard() == .activated)
  #expect(
    await interpreter.requestPenActuation(.raise)
      == .commandedAndSettled(command: .raise, commandedState: .up)
  )
  return (interpreter, request, link, gate, writesThroughCancel)
}

private func waitForInterpreterWriteCount(
  _ link: SimulatedGRBLLink,
  atLeast expected: Int
) async {
  for _ in 0..<1_000 {
    if link.completedWriteCount >= expected { return }
    await Task.yield()
  }
  Issue.record(
    "Timed out waiting for \(expected) interpreter writes; observed \(link.completedWriteCount)"
  )
}

private func waitForInterpreterCancelTransmission(_ interpreter: RunInterpreter) async {
  for _ in 0..<1_000 {
    if await interpreter.snapshot().lastJogCancelOutcome == .transmitted { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for the interpreter to project Jog Cancel transmission")
}

private actor InterpreterMachineReadGate {
  private var reached = false
  private var released = false
  private var reachedWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func waitUntilBlockedRead() async {
    guard !reached else { return }
    await withCheckedContinuation { reachedWaiters.append($0) }
  }

  func block() async {
    reached = true
    let observers = reachedWaiters
    reachedWaiters.removeAll(keepingCapacity: false)
    for observer in observers { observer.resume() }
    guard !released else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func release() {
    released = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }
}

private actor InterpreterPostJogReadState {
  private let jogBytes: Data
  private var jogWritten = false
  private var blockNextRead = false
  private var didBlock = false

  init(jogBytes: Data) {
    self.jogBytes = jogBytes
  }

  func noteWrite(_ bytes: Data) {
    if bytes == jogBytes {
      jogWritten = true
    } else if jogWritten, bytes == PassiveQuery.status.wireBytes, !didBlock {
      blockNextRead = true
    }
  }

  func consumeBlockFlag() -> Bool {
    guard blockNextRead, !didBlock else { return false }
    blockNextRead = false
    didBlock = true
    return true
  }
}

private final class InterpreterPostJogReadBlockingLink: MachineLink, @unchecked Sendable {
  let descriptor: MachineLinkDescriptor
  private let base: any MachineLink
  private let state: InterpreterPostJogReadState
  private let gate: InterpreterMachineReadGate

  init(base: any MachineLink, jogBytes: Data, gate: InterpreterMachineReadGate) {
    self.base = base
    state = InterpreterPostJogReadState(jogBytes: jogBytes)
    self.gate = gate
    descriptor = base.descriptor
  }

  func open() async throws { try await base.open() }
  func close() async { await base.close() }
  func discardPendingInput() async throws { try await base.discardPendingInput() }

  func write(_ bytes: Data) async throws {
    try await base.write(bytes)
    await state.noteWrite(bytes)
  }

  func read(maximumBytes: Int, timeoutNanoseconds: UInt64) async throws -> Data {
    if await state.consumeBlockFlag() { await gate.block() }
    return try await base.read(
      maximumBytes: maximumBytes,
      timeoutNanoseconds: timeoutNanoseconds
    )
  }
}

private struct ObservationCall: Equatable, Sendable {
  let phase: PhysicalObservationPhase
  let newerThan: UInt64
}

private actor TaskStartHandshake {
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

private actor ObservationScript {
  private var results: [
    Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
  ]
  private(set) var calls: [ObservationCall] = []

  init(
    results: [Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>]
  ) {
    self.results = results
  }

  func next(
    phase: PhysicalObservationPhase,
    newerThan: UInt64
  ) -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure> {
    calls.append(ObservationCall(phase: phase, newerThan: newerThan))
    guard !results.isEmpty else { return .failure(.frameUnavailable(phase)) }
    return results.removeFirst()
  }
}

private actor FreshObservationScript {
  private let before: VisibleToolFrameObservation
  private var postCandidates: [VisibleToolFrameObservation]
  private(set) var calls: [ObservationCall] = []

  init(
    before: VisibleToolFrameObservation,
    postCandidates: [VisibleToolFrameObservation]
  ) {
    self.before = before
    self.postCandidates = postCandidates
  }

  func next(
    phase: PhysicalObservationPhase,
    newerThan: UInt64
  ) -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure> {
    calls.append(ObservationCall(phase: phase, newerThan: newerThan))
    switch phase {
    case .beforeMotion:
      return .success(before)
    case .afterMotion:
      guard let index = postCandidates.firstIndex(where: {
        $0.captureNanoseconds > newerThan
      }) else {
        return .failure(.frameUnavailable(.afterMotion))
      }
      return .success(postCandidates.remove(at: index))
    }
  }
}

private actor BlockingObservation {
  private var requested = false
  private var requestedWaiters: [CheckedContinuation<Void, Never>] = []
  private var result: Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>?
  private var resultWaiters: [
    CheckedContinuation<
      Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>, Never
    >
  ] = []

  func observe(
    phase _: PhysicalObservationPhase,
    newerThan _: UInt64
  ) async -> Result<VisibleToolFrameObservation, PhysicalJogObservationFailure> {
    requested = true
    let waiters = requestedWaiters
    requestedWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if let result { return result }
    return await withCheckedContinuation { continuation in
      resultWaiters.append(continuation)
    }
  }

  func waitUntilRequested() async {
    if requested { return }
    await withCheckedContinuation { continuation in
      requestedWaiters.append(continuation)
    }
  }

  func release(
    with result: Result<VisibleToolFrameObservation, PhysicalJogObservationFailure>
  ) {
    self.result = result
    let waiters = resultWaiters
    resultWaiters.removeAll()
    waiters.forEach { $0.resume(returning: result) }
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
    exchanges: [SimulatedCommandExchange] = [],
    clock: DeterministicRuntimeClock = DeterministicRuntimeClock()
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
