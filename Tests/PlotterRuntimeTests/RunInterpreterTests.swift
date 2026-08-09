import Darwin
import Foundation
import PlotterModel
@testable import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Run interpreter shell")
struct RunInterpreterTests {
  @Test("visibility target plan is an exact forward and reverse 4 mm octagon")
  func visibilityTargetGeometry() throws {
    let plan = VisibilityTargetPlanV2()
    #expect(plan.diameterMM == 4)
    #expect(plan.radiusMM == 2)
    #expect(plan.perimeterSegmentCount == 8)
    #expect(plan.passCount == 2)
    #expect(plan.relativeVertices.count == 8)
    #expect(plan.drawingStepCount == 16)
    #expect(plan.approachDelta == (try Vector2<MachineSpace>(dx: 2, dy: 0)))
    let forward = Array(plan.traversalSteps.prefix(8))
    let reverse = Array(plan.traversalSteps.suffix(8))
    #expect(forward.map(\.passIndex) == Array(repeating: 0, count: 8))
    #expect(forward.map(\.direction) == Array(repeating: .forward, count: 8))
    #expect(forward.map(\.segmentIndex) == Array(0..<8))
    #expect(reverse.map(\.passIndex) == Array(repeating: 1, count: 8))
    #expect(reverse.map(\.direction) == Array(repeating: .reverse, count: 8))
    #expect(reverse.map(\.segmentIndex) == Array((0..<8).reversed()))
    for (forwardStep, reverseStep) in zip(forward, reverse.reversed()) {
      #expect(reverseStep.delta.dx == -forwardStep.delta.dx)
      #expect(reverseStep.delta.dy == -forwardStep.delta.dy)
    }
    let forwardSum = forward.reduce((dx: 0.0, dy: 0.0)) {
      ($0.dx + $1.delta.dx, $0.dy + $1.delta.dy)
    }
    let reverseSum = reverse.reduce((dx: 0.0, dy: 0.0)) {
      ($0.dx + $1.delta.dx, $0.dy + $1.delta.dy)
    }
    #expect(abs(forwardSum.dx) < 1e-12)
    #expect(abs(forwardSum.dy) < 1e-12)
    #expect(abs(reverseSum.dx) < 1e-12)
    #expect(abs(reverseSum.dy) < 1e-12)
    #expect(plan.algorithmRevision == "visibility-target-octagon-double-trace-v2")
  }

  @Test("compound target owns approach one lower two opposite passes and one final Pen Up")
  func compoundVisibilityTargetSuccess() async throws {
    let plan = VisibilityTargetPlanV2()
    let request = VisibilityTargetOperationRequest(
      plan: plan,
      approachFeedMMPerMinute: 60,
      drawingFeedMMPerMinute: 60
    )
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    exchanges[3] = interpreterDrawingConfigurationExchange()
    exchanges.append(contentsOf: [
      interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(.raise),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]),
      interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(
          plan.approachRequest(feedMMPerMinute: 60)
        ),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]),
      interpreterStatusExchange("<Idle|MPos:2.000,0.000,0.000>"),
      interpreterStatusExchange("<Idle|MPos:2.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(.lower),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]),
    ])
    var position = try Point2<MachineSpace>(x: 2, y: 0)
    for traversal in plan.traversalRequests(feedMMPerMinute: 60) {
      let stroke = traversal.drawingRequest
      let start = position
      position = try position.translated(by: stroke.delta)
      exchanges.append(interpreterStatusExchange(machineStatus(start)))
      exchanges.append(SimulatedCommandExchange(
        expectedWrite: MachineController.encodeDrawingStroke(stroke),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ))
      exchanges.append(interpreterStatusExchange(machineStatus(position)))
    }
    exchanges.append(contentsOf: [
      interpreterStatusExchange(machineStatus(position)),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(.raise),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]),
    ])
    let fixture = try await InterpreterFixture.make(exchanges: exchanges)
    _ = try await fixture.interpreter.requestPassiveProbe()
    #expect(await fixture.interpreter.activateMotionGuard() == .activated)
    #expect(
      await fixture.interpreter.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )

    let outcome = await fixture.interpreter.requestVisibilityTarget(request)
    #expect(
      outcome == .completed(
        finalPosition: try MachinePosition(x: 2, y: 0),
        scene: .inkPossible,
        progress: completedVisibilityTargetProgress(plan)
      )
    )
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.machine.penState == .up)
    #expect(snapshot.lastVisibilityTargetOutcome == outcome)
  }

  @Test("target Stop during Pen Down settles before any drawing segment")
  func visibilityTargetStopBetweenPhases() async throws {
    let ready = try await readyVisibilityTargetLowerPhaseFixture()
    guard case .admitted(let operation) = await ready.interpreter.beginVisibilityTarget(
      ready.request
    ) else {
      Issue.record("expected target admission")
      return
    }
    await ready.gate.waitUntilBlockedWrite()
    #expect(
      await ready.interpreter.requestVisibilityTargetIntent(
        .stop,
        operationID: operation.id
      ) == .accepted(intent: .stop, jogCancelOutcome: nil)
    )
    await ready.gate.release()

    #expect(
      await operation.outcome()
        == .stopped(
          scene: .inkPossible,
          jogCancelOutcome: nil,
          progress: visibilityTargetDispositionProgress(
            plan: ready.request.plan,
            intentPhase: .lowerPen,
            completedSteps: []
          )
        )
    )
    #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
    let snapshot = await ready.interpreter.snapshot()
    #expect(snapshot.machine.penState == .up)
    #expect(snapshot.currentOperation == .idle)
  }

  @Test("Stop versus next target segment latches first and emits no next drawing command")
  func visibilityTargetStopAdmissionRace() async throws {
    let ready = try await readyVisibilityTargetAdmissionRaceFixture()
    guard case .admitted(let operation) = await ready.interpreter.beginVisibilityTarget(
      ready.request
    ) else {
      Issue.record("expected target admission")
      return
    }
    await ready.gate.waitUntilBlockedRead()

    #expect(
      await ready.interpreter.requestVisibilityTargetIntent(
        .stop,
        operationID: operation.id
      ) == .accepted(intent: .stop, jogCancelOutcome: .refused(.noActiveJog))
    )
    #expect(
      await ready.interpreter.requestVisibilityTargetIntent(
        .stop,
        operationID: operation.id
      ) == .alreadyLatched(.stop)
    )
    await ready.gate.release()

    #expect(
      await operation.outcome()
        == .stopped(
          scene: .inkPossible,
          jogCancelOutcome: .refused(.noActiveJog),
          progress: visibilityTargetDispositionProgress(
            plan: ready.request.plan,
            intentPhase: .draw(ready.request.plan.traversalSteps[1]),
            completedSteps: [ready.request.plan.traversalSteps[0]]
          )
        )
    )
    #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
    let snapshot = await ready.interpreter.snapshot()
    #expect(snapshot.machine.penState == .up)
    #expect(snapshot.currentOperation == .idle)
  }

  @Test("target Stop during an active segment emits one cancel and settles Pen Up")
  func visibilityTargetStopDuringSegment() async throws {
    let ready = try await readyVisibilityTargetCancellationFixture()
    guard case .admitted(let operation) = await ready.interpreter.beginVisibilityTarget(
      ready.request
    ) else {
      Issue.record("expected target admission")
      return
    }
    await ready.gate.waitUntilBlockedRead()
    let stopTask = Task {
      await ready.interpreter.requestVisibilityTargetIntent(
        .stop,
        operationID: operation.id
      )
    }
    defer { stopTask.cancel() }
    await waitForInterpreterCancelTransmission(ready.interpreter)
    #expect(
      await ready.interpreter.requestVisibilityTargetIntent(
        .stop,
        operationID: operation.id
      ) == .alreadyLatched(.stop)
    )
    await ready.gate.release()

    #expect(
      await stopTask.value
        == .accepted(
          intent: .stop,
          jogCancelOutcome: .completed(finalPosition: ready.finalPosition)
        )
    )
    #expect(
      await operation.outcome()
        == .stopped(
          scene: .inkPossible,
          jogCancelOutcome: .completed(finalPosition: ready.finalPosition),
          progress: visibilityTargetDispositionProgress(
            plan: ready.request.plan,
            intentPhase: .draw(ready.request.plan.traversalSteps[0]),
            completedSteps: []
          )
        )
    )
    #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
    #expect(await ready.interpreter.snapshot().machine.penState == .up)
  }

  @Test("target Cancel records cancelled disposition and no later segment")
  func visibilityTargetCancelDuringSegment() async throws {
    let ready = try await readyVisibilityTargetCancellationFixture()
    guard case .admitted(let operation) = await ready.interpreter.beginVisibilityTarget(
      ready.request
    ) else {
      Issue.record("expected target admission")
      return
    }
    await ready.gate.waitUntilBlockedRead()
    let cancelTask = Task {
      await ready.interpreter.requestVisibilityTargetIntent(
        .cancel,
        operationID: operation.id
      )
    }
    defer { cancelTask.cancel() }
    await waitForInterpreterCancelTransmission(ready.interpreter)
    await ready.gate.release()

    #expect(
      await cancelTask.value
        == .accepted(
          intent: .cancel,
          jogCancelOutcome: .completed(finalPosition: ready.finalPosition)
        )
    )
    #expect(
      await operation.outcome()
        == .cancelled(
          scene: .inkPossible,
          jogCancelOutcome: .completed(finalPosition: ready.finalPosition),
          progress: visibilityTargetDispositionProgress(
            plan: ready.request.plan,
            intentPhase: .draw(ready.request.plan.traversalSteps[0]),
            completedSteps: []
          )
        )
    )
    #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
    #expect(await ready.interpreter.snapshot().machine.penState == .up)
  }

  @Test("shutdown latches target owner, settles once, and disconnects")
  func visibilityTargetShutdownDuringSegment() async throws {
    let ready = try await readyVisibilityTargetCancellationFixture()
    guard case .admitted(let operation) = await ready.interpreter.beginVisibilityTarget(
      ready.request
    ) else {
      Issue.record("expected target admission")
      return
    }
    await ready.gate.waitUntilBlockedRead()
    let disconnectTask = Task { await ready.interpreter.disconnect() }
    defer { disconnectTask.cancel() }
    await waitForInterpreterCancelTransmission(ready.interpreter)
    await ready.gate.release()
    await disconnectTask.value

    #expect(
      await operation.outcome()
        == .shutdown(
          scene: .inkPossible,
          jogCancelOutcome: .completed(finalPosition: ready.finalPosition),
          progress: visibilityTargetDispositionProgress(
            plan: ready.request.plan,
            intentPhase: .draw(ready.request.plan.traversalSteps[0]),
            completedSteps: []
          )
        )
    )
    #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
    #expect(await ready.interpreter.snapshot().machine.connection == .disconnected)
  }

  @Test("target approach refusal remains pristine and emits no target command")
  func visibilityTargetApproachRefusal() async throws {
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    let fixture = try await InterpreterFixture.make(exchanges: exchanges)
    _ = try await fixture.interpreter.requestPassiveProbe()
    let request = visibilityTargetRequest()

    #expect(
      await fixture.interpreter.requestVisibilityTarget(request)
        == .needsAttention(
          phase: .approach,
          scene: .pristine,
          failure: .approach(.refused(.motionGuardInactive)),
          progress: initialVisibilityTargetProgress(request.plan)
        )
    )
    #expect(fixture.link.completedWriteCount == exchanges.count)
    #expect(await fixture.interpreter.snapshot().machine.penState == .unknown)
  }

  @Test("ambiguous accepted target approach is sticky and emits no lower or drawing command")
  func visibilityTargetApproachAmbiguity() async throws {
    let plan = VisibilityTargetPlanV2()
    let request = visibilityTargetRequest(plan: plan)
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
        expectedWrite: MachineController.encodeRelativeJog(
          plan.approachRequest(feedMMPerMinute: 60)
        ),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      interpreterStatusExchange("untrusted controller text"),
    ])
    let fixture = try await InterpreterFixture.make(exchanges: exchanges)
    _ = try await fixture.interpreter.requestPassiveProbe()
    #expect(await fixture.interpreter.activateMotionGuard() == .activated)
    #expect(
      await fixture.interpreter.requestPenActuation(.raise)
        == .commandedAndSettled(command: .raise, commandedState: .up)
    )

    let outcome = await fixture.interpreter.requestVisibilityTarget(request)
    guard case .needsAttention(.approach, .pristine, .approach(.ambiguous), let progress) = outcome
    else {
      Issue.record("expected ambiguous approach with pristine scene; got \(outcome)")
      return
    }
    #expect(progress == initialVisibilityTargetProgress(plan))
    #expect(fixture.link.completedWriteCount == exchanges.count)
    let snapshot = await fixture.interpreter.snapshot()
    // Accepted motion followed by ambiguous controller state invalidates the
    // previously observed Pen Up fact; the runtime must not manufacture pose.
    #expect(snapshot.machine.penState == .unknown)
    #expect(snapshot.machine.stickyAmbiguity != nil)
  }

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

  @Test("typed drawing stroke is distinct and ordinary jog still refuses Pen Down")
  func typedDrawingStroke() async throws {
    let request = DrawingStrokeRequest(
      delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
      feedMMPerMinute: 60
    )
    let jogRequest = RelativeJogRequest(
      delta: request.delta,
      feedMMPerMinute: request.feedMMPerMinute
    )
    var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
    exchanges[2] = ControllerTranscriptFixtures.exchange(
      .status,
      chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
    )
    exchanges[3] = interpreterDrawingConfigurationExchange()
    exchanges.append(contentsOf: [
      interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(.lower),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle,
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeDrawingStroke(request),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      interpreterStatusExchange("<Idle|MPos:1.000,0.000,0.000>"),
    ])
    let fixture = try await InterpreterFixture.make(exchanges: exchanges)
    _ = try await fixture.interpreter.requestPassiveProbe()
    #expect(await fixture.interpreter.activateMotionGuard() == .activated)
    #expect(
      await fixture.interpreter.requestPenActuation(.lower)
        == .commandedAndSettled(command: .lower, commandedState: .down)
    )
    #expect(
      await fixture.interpreter.requestRelativeJog(jogRequest)
        == .refused(.penNotUp(.down))
    )

    let outcome = await fixture.interpreter.requestDrawingStroke(request)
    guard case .completed(let evidence) = outcome else {
      Issue.record("Expected completed drawing stroke, got \(outcome)")
      return
    }
    #expect(evidence.startPosition == (try MachinePosition(x: 0, y: 0)))
    #expect(evidence.finalPosition == (try MachinePosition(x: 1, y: 0)))
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastDrawingStrokeOutcome == outcome)
    #expect(snapshot.machine.lastDrawingStrokeOutcome == outcome)
    #expect(snapshot.machine.penState == .down)
  }

  @Test("drawing STOP remains subordinate until Idle and the automatic Pen Up settles")
  func drawingStrokeCancel() async throws {
    let ready = try await readyInterpreterDrawingCancellationFixture()
    let strokeTask = Task {
      await ready.interpreter.requestDrawingStroke(ready.request)
    }
    defer { strokeTask.cancel() }
    await ready.gate.waitUntilBlockedRead()

    let cancelTask = Task { await ready.interpreter.requestJogCancel() }
    defer { cancelTask.cancel() }
    await waitForInterpreterWriteCount(ready.link, atLeast: ready.writesThroughCancel)
    await waitForInterpreterCancelTransmission(ready.interpreter)
    #expect(
      await ready.interpreter.requestDrawingStroke(ready.request)
        == .refused(.operationInFlight)
    )
    await ready.gate.release()

    let finalPosition = try MachinePosition(x: 0.4, y: 0)
    #expect(await cancelTask.value == .completed(finalPosition: finalPosition))
    let outcome = await strokeTask.value
    guard case .cancelled(let evidence, let penRaiseOutcome) = outcome else {
      Issue.record("Expected cancelled drawing stroke, got \(outcome)")
      return
    }
    #expect(evidence.finalPosition == finalPosition)
    #expect(
      penRaiseOutcome == .commandedAndSettled(command: .raise, commandedState: .up)
    )
    let snapshot = await ready.interpreter.snapshot()
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastDrawingStrokeOutcome == outcome)
    #expect(snapshot.machine.penState == .up)
    #expect(ready.link.completedWriteCount == ready.writesThroughCancel + 3)
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

  @Test("boundary natural segment completion renews the same logical owner and records no result")
  func boundaryNaturalCompletionRenewsSameOwner() async throws {
    let ready = try await readyBoundaryCancellationFixture(naturalCompletionsBeforeBlock: 1)
    let boundaryTask = Task {
      await ready.interpreter.requestBoundaryMotion(ready.request)
    }
    defer { boundaryTask.cancel() }
    await ready.gate.waitUntilBlockedRead()

    let snapshot = await ready.interpreter.snapshot()
    #expect(snapshot.currentOperation == .boundaryMotion(ready.request))
    #expect(snapshot.lastBoundaryMotionOutcome == nil)
    #expect(ready.link.completedWriteCount == ready.writesThroughActiveStatus)

    let cancelTask = Task {
      await ready.interpreter.requestJogCancel(.cancelAttempt)
    }
    defer { cancelTask.cancel() }
    await waitForInterpreterWriteCount(ready.link, atLeast: ready.writesThroughCancel)
    await ready.gate.release()

    let finalPosition = try MachinePosition(x: 1.4, y: 0)
    #expect(await cancelTask.value == .completed(finalPosition: finalPosition))
    guard case .settled(let settlement) = await boundaryTask.value else {
      Issue.record("Expected the renewed boundary owner to settle")
      return
    }
    #expect(settlement.ownerID == ready.request.ownerID)
    #expect(settlement.intent == .cancelAttempt)
    #expect(settlement.completedSegmentCount == 1)
    #expect(settlement.finalPosition == finalPosition)
  }

  @Test("Stop racing renewed-segment admission prevents the renewal write")
  func boundaryStopAdmissionRace() async throws {
    let ready = try await readyBoundaryAdmissionRaceFixture()
    let boundaryTask = Task {
      await ready.interpreter.requestBoundaryMotion(ready.request)
    }
    defer { boundaryTask.cancel() }
    await ready.gate.waitUntilBlockedRead()

    #expect(
      await ready.interpreter.requestJogCancel(.operatorStop)
        == .refused(.noActiveJog)
    )
    await ready.gate.release()

    guard case .settled(let settlement) = await boundaryTask.value else {
      Issue.record("Expected the Stop latch to settle the owner at the previous segment")
      return
    }
    #expect(settlement.intent == .operatorStop)
    #expect(settlement.completedSegmentCount == 1)
    #expect(settlement.finalPosition == (try MachinePosition(x: 1, y: 0)))
    #expect(settlement.jogCancelOutcome == .refused(.noActiveJog))
    #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
  }

  @Test("Stop while camera renewal planning is suspended prevents another wire request")
  func boundaryStopDuringRenewalPlanning() async throws {
    let ready = try await readyBoundaryCancellationFixture(naturalCompletionsBeforeBlock: 1)
    let plannerGate = InterpreterMachineReadGate()
    let planner = BoundaryMotionRenewalPlanner { _ in
      await plannerGate.block()
      return 40
    }
    let admission = await ready.interpreter.beginBoundaryMotion(
      ready.request,
      renewalPlanner: planner
    )
    guard case .admitted(let operation) = admission else {
      Issue.record("Expected Boundary admission")
      return
    }
    await plannerGate.waitUntilBlockedRead()
    let writesBeforeStop = ready.link.completedWriteCount

    #expect(
      await ready.interpreter.requestJogCancel(.operatorStop)
        == .refused(.noActiveJog)
    )
    await plannerGate.release()

    guard case .settled(let settlement) = await operation.outcome() else {
      Issue.record("Expected Stop to settle at the completed probe segment")
      return
    }
    #expect(settlement.intent == .operatorStop)
    #expect(settlement.completedSegmentCount == 1)
    #expect(settlement.finalPosition == (try MachinePosition(x: 1, y: 0)))
    #expect(ready.link.completedWriteCount == writesBeforeStop)
  }

  @Test("boundary Stop latches once, cancels once, and settles the original owner")
  func boundaryStopSettlesOnce() async throws {
    let ready = try await readyBoundaryCancellationFixture(naturalCompletionsBeforeBlock: 0)
    let boundaryTask = Task {
      await ready.interpreter.requestBoundaryMotion(ready.request)
    }
    defer { boundaryTask.cancel() }
    await ready.gate.waitUntilBlockedRead()

    let stopTask = Task {
      await ready.interpreter.requestJogCancel(.operatorStop)
    }
    defer { stopTask.cancel() }
    await waitForInterpreterWriteCount(ready.link, atLeast: ready.writesThroughCancel)
    #expect(
      await ready.interpreter.requestJogCancel(.operatorStop)
        == .refused(.alreadyRequested)
    )
    #expect(ready.link.completedWriteCount == ready.writesThroughCancel)
    await ready.gate.release()

    let finalPosition = try MachinePosition(x: 0.4, y: 0)
    #expect(await stopTask.value == .completed(finalPosition: finalPosition))
    guard case .settled(let settlement) = await boundaryTask.value else {
      Issue.record("Expected operator-stopped boundary settlement")
      return
    }
    #expect(settlement.intent == .operatorStop)
    #expect(settlement.completedSegmentCount == 0)
    #expect(settlement.finalPosition == finalPosition)
    #expect(settlement.jogCancelOutcome == .completed(finalPosition: finalPosition))
    #expect(ready.link.completedWriteCount == ready.writesThroughCancel + 1)
  }

  @Test("Boundary Cancel settles once without an operator-Stop disposition")
  func boundaryCancelDisposition() async throws {
    let ready = try await readyBoundaryCancellationFixture(naturalCompletionsBeforeBlock: 0)
    let boundaryTask = Task {
      await ready.interpreter.requestBoundaryMotion(ready.request)
    }
    defer { boundaryTask.cancel() }
    await ready.gate.waitUntilBlockedRead()
    let cancelTask = Task {
      await ready.interpreter.requestJogCancel(.cancelAttempt)
    }
    defer { cancelTask.cancel() }
    await waitForInterpreterWriteCount(ready.link, atLeast: ready.writesThroughCancel)
    await ready.gate.release()

    _ = await cancelTask.value
    guard case .settled(let settlement) = await boundaryTask.value else {
      Issue.record("Expected cancelled-attempt boundary settlement")
      return
    }
    #expect(settlement.intent == .cancelAttempt)
    #expect(settlement.intent != .operatorStop)
    #expect(ready.link.completedWriteCount == ready.writesThroughCancel + 1)
  }

  @Test("shutdown closes boundary renewal and settles once")
  func boundaryShutdownSettlement() async throws {
    let ready = try await readyBoundaryCancellationFixture(naturalCompletionsBeforeBlock: 0)
    let boundaryTask = Task {
      await ready.interpreter.requestBoundaryMotion(ready.request)
    }
    defer { boundaryTask.cancel() }
    await ready.gate.waitUntilBlockedRead()
    let disconnectTask = Task { await ready.interpreter.disconnect() }
    defer { disconnectTask.cancel() }
    await waitForInterpreterWriteCount(ready.link, atLeast: ready.writesThroughCancel)
    await ready.gate.release()

    await disconnectTask.value
    guard case .settled(let settlement) = await boundaryTask.value else {
      Issue.record("Expected shutdown boundary settlement")
      return
    }
    #expect(settlement.intent == .shutdown)
    #expect(ready.link.completedWriteCount == ready.writesThroughCancel + 1)
    #expect(await ready.interpreter.snapshot().machine.connection == .disconnected)
  }

  @Test("shutdown during renewed-segment admission awaits the owner without a renewal write")
  func boundaryShutdownAdmissionRace() async throws {
    let ready = try await readyBoundaryAdmissionRaceFixture()
    let boundaryTask = Task {
      await ready.interpreter.requestBoundaryMotion(ready.request)
    }
    defer { boundaryTask.cancel() }
    await ready.gate.waitUntilBlockedRead()
    let disconnectTask = Task { await ready.interpreter.disconnect() }
    defer { disconnectTask.cancel() }
    await waitForInterpreterJogCancelOutcome(
      ready.interpreter,
      expected: .refused(.noActiveJog)
    )
    await ready.gate.release()

    await disconnectTask.value
    guard case .settled(let settlement) = await boundaryTask.value else {
      Issue.record("Expected shutdown to await the pre-transmission boundary owner")
      return
    }
    #expect(settlement.intent == .shutdown)
    #expect(settlement.completedSegmentCount == 1)
    #expect(settlement.jogCancelOutcome == .refused(.noActiveJog))
    #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
    #expect(await ready.interpreter.snapshot().machine.connection == .disconnected)
  }

  @Test("boundary controller terminals become Needs Attention and never renew")
  func boundaryTerminalOutcomes() async throws {
    let cases: [(BoundaryTerminalScript, BoundaryMotionTerminal)] = [
      (
        .limit,
        .limitAsserted(
          pins: "X",
          finalPosition: try MachinePosition(x: 1, y: 0)
        )
      ),
      (.alarm, .alarm("ALARM:1")),
      (.refusal, .refusal(.controllerRejected("error:15"))),
      (.disconnect, .disconnected),
      (.fault, .fault(.malformedReply("untrusted controller text"))),
    ]

    for (script, expectedTerminal) in cases {
      let ready = try await readyBoundaryTerminalFixture(script)
      let outcome = await ready.interpreter.requestBoundaryMotion(ready.request)

      #expect(
        outcome == .needsAttention(
          ownerID: ready.request.ownerID,
          terminal: expectedTerminal
        )
      )
      #expect(ready.link.completedWriteCount == ready.expectedWriteCount)
      #expect(await ready.interpreter.snapshot().currentOperation == .idle)
    }
  }

  @Test("ambiguous boundary segment is sticky and is never renewed or resent")
  func ambiguousBoundaryDoesNotRenew() async throws {
    let ready = try await readyBoundaryTerminalFixture(.fault)
    let outcome = await ready.interpreter.requestBoundaryMotion(ready.request)
    let writesAfterAmbiguity = ready.link.completedWriteCount

    #expect(
      outcome == .needsAttention(
        ownerID: ready.request.ownerID,
        terminal: .fault(.malformedReply("untrusted controller text"))
      )
    )
    #expect(
      await ready.interpreter.requestBoundaryMotion(ready.request)
        == .needsAttention(
          ownerID: ready.request.ownerID,
          terminal: .fault(.malformedReply("untrusted controller text"))
        )
    )
    #expect(ready.link.completedWriteCount == writesAfterAmbiguity)
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

private func machineStatus(_ point: Point2<MachineSpace>) -> String {
  String(
    format: "<Idle|MPos:%.3f,%.3f,0.000>",
    locale: Locale(identifier: "en_US_POSIX"),
    point.x,
    point.y
  )
}

private func interpreterDrawingConfigurationExchange() -> SimulatedCommandExchange {
  ControllerTranscriptFixtures.exchange(
    .configuration,
    chunks: [
      "$110=500\r\n$111=500\r\n$120=10\r\n$121=10\r\nok\r\n"
    ]
  )
}

private func visibilityTargetRequest(
  plan: VisibilityTargetPlanV2 = VisibilityTargetPlanV2()
) -> VisibilityTargetOperationRequest {
  VisibilityTargetOperationRequest(
    plan: plan,
    approachFeedMMPerMinute: 60,
    drawingFeedMMPerMinute: 60
  )
}

private func initialVisibilityTargetProgress(
  _ plan: VisibilityTargetPlanV2
) -> VisibilityTargetOperationProgress {
  VisibilityTargetOperationProgress(
    planRevision: plan.algorithmRevision,
    phase: .approach,
    completedTraversalStepCount: 0,
    lastCompletedTraversalStep: nil
  )
}

private func completedVisibilityTargetProgress(
  _ plan: VisibilityTargetPlanV2
) -> VisibilityTargetOperationProgress {
  VisibilityTargetOperationProgress(
    planRevision: plan.algorithmRevision,
    phase: .raisePen,
    completedTraversalStepCount: plan.drawingStepCount,
    lastCompletedTraversalStep: plan.traversalSteps.last
  )
}

private func visibilityTargetDispositionProgress(
  plan: VisibilityTargetPlanV2,
  intentPhase: VisibilityTargetOperationPhase,
  completedSteps: [VisibilityTargetTraversalStep]
) -> VisibilityTargetOperationProgress {
  VisibilityTargetOperationProgress(
    planRevision: plan.algorithmRevision,
    phase: .raisePen,
    dispositionRequestedDuringPhase: intentPhase,
    completedTraversalStepCount: completedSteps.count,
    lastCompletedTraversalStep: completedSteps.last
  )
}

private func visibilityTargetPreparedExchanges(
  plan: VisibilityTargetPlanV2
) throws -> [SimulatedCommandExchange] {
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
  exchanges[2] = ControllerTranscriptFixtures.exchange(
    .status,
    chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
  )
  exchanges[3] = interpreterDrawingConfigurationExchange()
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
      expectedWrite: MachineController.encodeRelativeJog(
        plan.approachRequest(feedMMPerMinute: 60)
      ),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Idle|MPos:2.000,0.000,0.000>"),
    interpreterStatusExchange("<Idle|MPos:2.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.lower),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
  ])
  return exchanges
}

private func makeVisibilityTargetInterpreter(
  exchanges: [SimulatedCommandExchange],
  link: any MachineLink,
  clock: DeterministicRuntimeClock
) async throws -> RunInterpreter {
  let controller = MachineController(
    link: link,
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
  return interpreter
}

private func readyVisibilityTargetLowerPhaseFixture() async throws -> (
  interpreter: RunInterpreter,
  request: VisibilityTargetOperationRequest,
  link: SimulatedGRBLLink,
  gate: MachineWriteGate,
  expectedWriteCount: Int
) {
  let plan = VisibilityTargetPlanV2()
  let request = visibilityTargetRequest(plan: plan)
  var exchanges = try visibilityTargetPreparedExchanges(plan: plan)
  exchanges.append(contentsOf: [
    interpreterStatusExchange("<Idle|MPos:2.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.raise),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
  ])
  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let gate = MachineWriteGate()
  let blocking = BlockingMachineLink(
    base: link,
    blockedWrite: MachineController.encodePenActuation(.lower),
    gate: gate
  )
  let interpreter = try await makeVisibilityTargetInterpreter(
    exchanges: exchanges,
    link: blocking,
    clock: clock
  )
  return (interpreter, request, link, gate, exchanges.count)
}

private func readyVisibilityTargetAdmissionRaceFixture() async throws -> (
  interpreter: RunInterpreter,
  request: VisibilityTargetOperationRequest,
  link: SimulatedGRBLLink,
  gate: InterpreterMachineReadGate,
  expectedWriteCount: Int
) {
  let plan = VisibilityTargetPlanV2()
  let request = visibilityTargetRequest(plan: plan)
  let firstStroke = plan.traversalRequests(feedMMPerMinute: 60)[0].drawingRequest
  let firstFinal = try Point2<MachineSpace>(
    x: 2 + firstStroke.delta.dx,
    y: firstStroke.delta.dy
  )
  var exchanges = try visibilityTargetPreparedExchanges(plan: plan)
  exchanges.append(contentsOf: [
    interpreterStatusExchange("<Idle|MPos:2.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeDrawingStroke(firstStroke),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange(machineStatus(firstFinal)),
    interpreterStatusExchange(machineStatus(firstFinal)),
    interpreterStatusExchange(machineStatus(firstFinal)),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.raise),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
  ])
  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let gate = InterpreterMachineReadGate()
  let blocking = BoundaryRenewalAdmissionBlockingLink(
    base: link,
    jogBytes: MachineController.encodeDrawingStroke(firstStroke),
    gate: gate
  )
  let interpreter = try await makeVisibilityTargetInterpreter(
    exchanges: exchanges,
    link: blocking,
    clock: clock
  )
  return (interpreter, request, link, gate, exchanges.count)
}

private func readyVisibilityTargetCancellationFixture() async throws -> (
  interpreter: RunInterpreter,
  request: VisibilityTargetOperationRequest,
  link: SimulatedGRBLLink,
  gate: InterpreterMachineReadGate,
  finalPosition: MachinePosition,
  expectedWriteCount: Int
) {
  let plan = VisibilityTargetPlanV2()
  let request = visibilityTargetRequest(plan: plan)
  let firstStroke = plan.traversalRequests(feedMMPerMinute: 60)[0].drawingRequest
  let finalPosition = try MachinePosition(x: 1.7, y: 0.7)
  var exchanges = try visibilityTargetPreparedExchanges(plan: plan)
  exchanges.append(contentsOf: [
    interpreterStatusExchange("<Idle|MPos:2.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeDrawingStroke(firstStroke),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Jog|MPos:1.850,0.350,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeJogCancel,
      reads: []
    ),
    interpreterStatusExchange("<Idle|MPos:1.700,0.700,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.raise),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
  ])
  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let gate = InterpreterMachineReadGate()
  let blocking = InterpreterPostJogReadBlockingLink(
    base: link,
    jogBytes: MachineController.encodeDrawingStroke(firstStroke),
    gate: gate
  )
  let interpreter = try await makeVisibilityTargetInterpreter(
    exchanges: exchanges,
    link: blocking,
    clock: clock
  )
  return (interpreter, request, link, gate, finalPosition, exchanges.count)
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

private func readyInterpreterDrawingCancellationFixture() async throws -> (
  interpreter: RunInterpreter,
  request: DrawingStrokeRequest,
  link: SimulatedGRBLLink,
  gate: InterpreterMachineReadGate,
  writesThroughCancel: Int
) {
  let request = DrawingStrokeRequest(
    delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
    feedMMPerMinute: 60
  )
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
  exchanges[2] = ControllerTranscriptFixtures.exchange(
    .status,
    chunks: ["<Idle|MPos:0.000,0.000,0.000>\r\n"]
  )
  exchanges[3] = interpreterDrawingConfigurationExchange()
  exchanges.append(contentsOf: [
    interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.lower),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Idle|MPos:0.000,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeDrawingStroke(request),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Jog|MPos:0.200,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeJogCancel,
      reads: []
    ),
  ])
  let writesThroughCancel = exchanges.count
  exchanges.append(contentsOf: [
    interpreterStatusExchange("<Idle|MPos:0.400,0.000,0.000>"),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(.raise),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle,
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
  ])

  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let gate = InterpreterMachineReadGate()
  let blockingLink = InterpreterPostJogReadBlockingLink(
    base: link,
    jogBytes: MachineController.encodeDrawingStroke(request),
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
    await interpreter.requestPenActuation(.lower)
      == .commandedAndSettled(command: .lower, commandedState: .down)
  )
  return (interpreter, request, link, gate, writesThroughCancel)
}

private func readyBoundaryCancellationFixture(
  naturalCompletionsBeforeBlock: Int
) async throws -> (
  interpreter: RunInterpreter,
  request: BoundaryMotionRequest,
  link: SimulatedGRBLLink,
  gate: InterpreterMachineReadGate,
  writesThroughActiveStatus: Int,
  writesThroughCancel: Int
) {
  precondition(naturalCompletionsBeforeBlock >= 0)
  let segment = RelativeJogRequest(
    delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
    feedMMPerMinute: 60
  )
  let request = BoundaryMotionRequest(direction: .positiveX, segment: segment)
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
  for completedIndex in 0..<naturalCompletionsBeforeBlock {
    let start = Double(completedIndex)
    let final = Double(completedIndex + 1)
    exchanges.append(contentsOf: [
      interpreterStatusExchange(
        String(format: "<Idle|MPos:%.3f,0.000,0.000>", start)
      ),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      interpreterStatusExchange(
        String(format: "<Idle|MPos:%.3f,0.000,0.000>", final)
      ),
    ])
  }
  let start = Double(naturalCompletionsBeforeBlock)
  exchanges.append(contentsOf: [
    interpreterStatusExchange(
      String(format: "<Idle|MPos:%.3f,0.000,0.000>", start)
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeRelativeJog(segment),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange(
      String(format: "<Jog|MPos:%.3f,0.000,0.000>", start + 0.2)
    ),
  ])
  let writesThroughActiveStatus = exchanges.count
  exchanges.append(
    SimulatedCommandExchange(expectedWrite: MachineController.encodeJogCancel, reads: [])
  )
  let writesThroughCancel = exchanges.count
  exchanges.append(
    interpreterStatusExchange(
      String(format: "<Idle|MPos:%.3f,0.000,0.000>", start + 0.4)
    )
  )

  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let gate = InterpreterMachineReadGate()
  let blockingLink = InterpreterPostJogReadBlockingLink(
    base: link,
    jogBytes: MachineController.encodeRelativeJog(segment),
    gate: gate,
    blockAfterJogNumber: naturalCompletionsBeforeBlock + 1
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
  return (
    interpreter,
    request,
    link,
    gate,
    writesThroughActiveStatus,
    writesThroughCancel
  )
}

private func readyBoundaryAdmissionRaceFixture() async throws -> (
  interpreter: RunInterpreter,
  request: BoundaryMotionRequest,
  link: SimulatedGRBLLink,
  gate: InterpreterMachineReadGate,
  expectedWriteCount: Int
) {
  let segment = RelativeJogRequest(
    delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
    feedMMPerMinute: 60
  )
  let request = BoundaryMotionRequest(direction: .positiveX, segment: segment)
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
      expectedWrite: MachineController.encodeRelativeJog(segment),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    interpreterStatusExchange("<Idle|MPos:1.000,0.000,0.000>"),
    interpreterStatusExchange("<Idle|MPos:1.000,0.000,0.000>"),
  ])
  let expectedWriteCount = exchanges.count
  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let gate = InterpreterMachineReadGate()
  let blockingLink = BoundaryRenewalAdmissionBlockingLink(
    base: link,
    jogBytes: MachineController.encodeRelativeJog(segment),
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
  return (interpreter, request, link, gate, expectedWriteCount)
}

private enum BoundaryTerminalScript {
  case limit
  case alarm
  case refusal
  case disconnect
  case fault
}

private func readyBoundaryTerminalFixture(
  _ script: BoundaryTerminalScript
) async throws -> (
  interpreter: RunInterpreter,
  request: BoundaryMotionRequest,
  link: SimulatedGRBLLink,
  expectedWriteCount: Int
) {
  let segment = RelativeJogRequest(
    delta: try Vector2<MachineSpace>(dx: 1, dy: 0),
    feedMMPerMinute: 60
  )
  let request = BoundaryMotionRequest(direction: .positiveX, segment: segment)
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
  ])
  switch script {
  case .refusal:
    exchanges.append(
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("error:15\r\n".utf8)))]
      )
    )
  case .limit:
    exchanges.append(contentsOf: [
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      interpreterStatusExchange("<Idle|MPos:1.000,0.000,0.000|Pn:X>"),
    ])
  case .alarm:
    exchanges.append(contentsOf: [
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      interpreterStatusExchange("ALARM:1"),
    ])
  case .disconnect:
    exchanges.append(contentsOf: [
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      SimulatedCommandExchange(
        expectedWrite: PassiveQuery.status.wireBytes,
        reads: [ScheduledMachineRead(outcome: .disconnect)]
      ),
    ])
  case .fault:
    exchanges.append(contentsOf: [
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      interpreterStatusExchange("untrusted controller text"),
    ])
  }
  let expectedWriteCount = exchanges.count
  let clock = DeterministicRuntimeClock()
  let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
  let controller = MachineController(
    link: link,
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
  return (interpreter, request, link, expectedWriteCount)
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

private func waitForInterpreterJogCancelOutcome(
  _ interpreter: RunInterpreter,
  expected: JogCancelOutcome
) async {
  for _ in 0..<1_000 {
    if await interpreter.snapshot().lastJogCancelOutcome == expected { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for interpreter Jog Cancel outcome \(expected)")
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
  private let blockAfterJogNumber: Int
  private var jogWriteCount = 0
  private var blockNextRead = false
  private var didBlock = false

  init(jogBytes: Data, blockAfterJogNumber: Int) {
    precondition(blockAfterJogNumber > 0)
    self.jogBytes = jogBytes
    self.blockAfterJogNumber = blockAfterJogNumber
  }

  func noteWrite(_ bytes: Data) {
    if bytes == jogBytes {
      jogWriteCount += 1
    } else if jogWriteCount == blockAfterJogNumber,
      bytes == PassiveQuery.status.wireBytes, !didBlock
    {
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

  init(
    base: any MachineLink,
    jogBytes: Data,
    gate: InterpreterMachineReadGate,
    blockAfterJogNumber: Int = 1
  ) {
    self.base = base
    state = InterpreterPostJogReadState(
      jogBytes: jogBytes,
      blockAfterJogNumber: blockAfterJogNumber
    )
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

private actor BoundaryRenewalAdmissionBlockState {
  private let jogBytes: Data
  private var jogWriteCount = 0
  private var statusWritesAfterFirstJog = 0
  private var blockNextRead = false
  private var didBlock = false

  init(jogBytes: Data) {
    self.jogBytes = jogBytes
  }

  func noteWrite(_ bytes: Data) {
    if bytes == jogBytes {
      jogWriteCount += 1
    } else if jogWriteCount == 1, bytes == PassiveQuery.status.wireBytes {
      statusWritesAfterFirstJog += 1
      if statusWritesAfterFirstJog == 2, !didBlock {
        blockNextRead = true
      }
    }
  }

  func consumeBlockFlag() -> Bool {
    guard blockNextRead, !didBlock else { return false }
    blockNextRead = false
    didBlock = true
    return true
  }
}

private final class BoundaryRenewalAdmissionBlockingLink: MachineLink, @unchecked Sendable {
  let descriptor: MachineLinkDescriptor
  private let base: any MachineLink
  private let state: BoundaryRenewalAdmissionBlockState
  private let gate: InterpreterMachineReadGate

  init(base: any MachineLink, jogBytes: Data, gate: InterpreterMachineReadGate) {
    self.base = base
    state = BoundaryRenewalAdmissionBlockState(jogBytes: jogBytes)
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
