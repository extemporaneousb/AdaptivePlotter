import Foundation
import PlotterModel
@testable import PlotterRuntime
import PlotterTestSupport
import Testing

@Suite("Owner-bound drawing plan runner")
struct DrawingPlanRunInterpreterTests {
  @Test("sub-wire start residue does not issue a zero-delta jog or reject settled drawing")
  func subWireStartResidue() async throws {
    let request = try drawingPlanRequest([[(0.0004, 0), (1.0004, 0)]])
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += strokeExchanges(try strokeRequest(from: (0.0004, 0), to: (1.0004, 0), request: request),
      from: (0, 0), to: (1, 0))
    exchanges += penExchanges(.raise, at: (1, 0), profile: request.penActuationProfile)
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)
    guard case .completed = await fixture.interpreter.requestDrawingPlan(request) else {
      Issue.record("Wire-zero travel should retain normal drawing and settlement tolerance")
      return
    }
    #expect(fixture.link.completedWriteCount == exchanges.count)
  }

  @Test("interior sub-wire geometry coalesces without aborting or changing the immutable plan")
  func interiorSubWireSegment() async throws {
    let request = try drawingPlanRequest([[
      (0, 0), (1, 1), (1.000361052301912, 1.000244040715259),
      (2.000361052301912, 2.000244040715259),
    ]])
    let original = try JSONEncoder().encode(request.plan)
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += strokeExchanges(try strokeRequest(from: (0, 0), to: (1, 1), request: request),
      from: (0, 0), to: (1, 1))
    exchanges += strokeExchanges(try strokeRequest(from: (1, 1), to: (2, 2), request: request),
      from: (1, 1), to: (2, 2))
    exchanges += penExchanges(.raise, at: (2, 2), profile: request.penActuationProfile)
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)
    guard case .completed(let progress, let position) = await fixture.interpreter.requestDrawingPlan(request) else {
      Issue.record("The reproduced interior wire-zero segment should coalesce and finish")
      return
    }
    #expect(position == (try MachinePosition(x: 2, y: 2)))
    #expect(progress.planRevisionID == request.plan.revisionID)
    #expect(progress.plannedSegmentCount == 2)
    #expect(progress.submittedSegmentCount == 2)
    #expect(progress.controllerCompletedSegmentCount == 2)
    #expect(progress.completedCheckpointIDs == request.plan.checkpoints.map(\.id))
    #expect(try JSONDecoder().decode(ExecutionPlanRevision.self, from: original) == request.plan)
    #expect(fixture.link.completedWriteCount == exchanges.count)
  }

  @Test("a wholly sub-wire stroke refuses the entire plan before travel or Pen Down")
  func whollySubWireStrokeRefusesBeforeActuation() async throws {
    let request = try drawingPlanRequest([[(0, 0), (1, 0)], [(2, 2), (2.000361, 2.000244)]])
    let exchanges = drawingPlanProbeExchanges(position: (0, 0))
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)
    guard case .refused(let progress, .unrepresentableStroke(let id)) =
      await fixture.interpreter.requestDrawingPlan(request) else {
      Issue.record("No plan actuation is allowed when a whole stroke cannot be represented")
      return
    }
    #expect(id == request.plan.strokes[1].logicalStrokeID)
    #expect(progress.commandedStrokeCount == 0)
    #expect(progress.submittedSegmentCount == 0)
    #expect(progress.completedCheckpointIDs.isEmpty)
    #expect(fixture.link.completedWriteCount == exchanges.count)
  }

  @Test("cumulative rounding preserves thousands of tiny displacements and source mapping")
  func cumulativeWireDisplacement() throws {
    let points = (0...3_000).map { (Double($0) * 0.0004, -Double($0) * 0.000244040715259) }
    let request = try drawingPlanRequest([points])
    let schedule = try DrawingWireSchedule(plan: request.plan)
    let segments = try #require(schedule.strokes.first?.segments)
    #expect(segments.count < points.count - 1)
    var xUnits: Int64 = 0, yUnits: Int64 = 0
    var coveredSourceCount = 0
    for segment in segments {
      xUnits += try #require(MachineWirePrecision.units(segment.delta.dx))
      yUnits += try #require(MachineWirePrecision.units(segment.delta.dy))
      #expect(segment.delta.dx != 0 || segment.delta.dy != 0)
      #expect(segment.sourceSegmentRange.lowerBound == coveredSourceCount)
      coveredSourceCount = segment.sourceSegmentRange.upperBound + 1
      #expect(abs(Double(xUnits) / 1_000 - segment.intendedEndpoint.x) <= 0.000500000001)
      #expect(abs(Double(yUnits) / 1_000 - segment.intendedEndpoint.y) <= 0.000500000001)
    }
    #expect(coveredSourceCount == 3_000)
    #expect(xUnits == 1_200)
    #expect(yUnits == -732)
  }

  @Test("closed and inverse paths retain reversals and terminal residue without bridging strokes")
  func reversalsAndTerminalResidue() throws {
    let request = try drawingPlanRequest([
      [(0, 0), (0.0004, 0.0002), (1.0006, -1.0006), (0, 0), (0.0003, -0.0002)],
      [(3, 3), (2.0006, 3.0004), (3, 3)],
    ])
    let schedule = try DrawingWireSchedule(plan: request.plan)
    #expect(schedule.strokes.map(\.strokeID) == request.plan.strokes.map(\.logicalStrokeID))
    for stroke in schedule.strokes {
      #expect(stroke.segments.count == 2)
      #expect(stroke.segments.reduce(0) { $0 + $1.delta.dx } == 0)
      #expect(stroke.segments.reduce(0) { $0 + $1.delta.dy } == 0)
    }
    #expect(schedule.strokes[0].segments[0].sourceSegmentRange == 0...1)
    #expect(schedule.strokes[0].segments[1].sourceSegmentRange == 2...3)
    #expect(schedule.strokes[0].segments[1].intendedEndpoint == request.plan.strokes[0].path.end)
    #expect(MachineWirePrecision.number(-0.0001)?.text == "0.000")
  }

  @Test("near-boundary wire endpoints round inward from either stroke-start origin",
    arguments: [-1.0, 1.0])
  func boundaryRoundingBound(sign: Double) throws {
    let request = try drawingPlanRequest([[(sign * 9.0004, 0), (sign * 10, 0)]])
    let schedule = try DrawingWireSchedule(plan: request.plan)
    let segment = try #require(schedule.strokes.first?.segments.first)
    let wireEnd = request.plan.strokes[0].path.start.x + segment.delta.dx
    #expect(abs(wireEnd - sign * 10) < 0.001)
    #expect(abs(wireEnd - sign * 10) > 0.0005)
    #expect(request.plan.drawableRegion.contains(try Point2(x: wireEnd, y: 0)))
    #expect(abs(wireEnd) <= 10)
  }

  @Test("non-grid minimum maximum and corner targets remain contained with inverse displacement",
    arguments: [-1.0, 1.0])
  func nonGridBoundaryWireSchedule(sign: Double) throws {
    let region = try DrawableMachineRegion(bounds: .init(minX: -10.0006, minY: -10.0006,
      maxX: 10.0006, maxY: 10.0006))
    let request = try drawingPlanRequest([[
      (0, 0), (sign * 10.0006, 0), (sign * 10.0006, -sign * 10.0006), (0, 0),
    ]], region: region)
    let schedule = try DrawingWireSchedule(plan: request.plan)
    var xUnits: Int64 = 0, yUnits: Int64 = 0
    for segment in schedule.strokes[0].segments {
      xUnits += try #require(MachineWirePrecision.units(segment.delta.dx))
      yUnits += try #require(MachineWirePrecision.units(segment.delta.dy))
      let endpoint = try Point2<MachineSpace>(x: Double(xUnits) / 1_000, y: Double(yUnits) / 1_000)
      #expect(region.contains(endpoint))
      #expect(abs(endpoint.x - segment.intendedEndpoint.x) < 0.001)
      #expect(abs(endpoint.y - segment.intendedEndpoint.y) < 0.001)
    }
    #expect(xUnits == 0 && yUnits == 0)
    #expect(schedule.strokes[0].segments.count == 3)
  }

  @Test("a negative displacement from a non-grid maximum respects the opposite minimum")
  func boundaryOriginNegativeDisplacement() throws {
    let region = try DrawableMachineRegion(bounds: .init(minX: 0, minY: 0, maxX: 10.0006, maxY: 10.0006))
    let request = try drawingPlanRequest([[(10.0006, 10.0006), (0, 0)]], region: region)
    let schedule = try DrawingWireSchedule(plan: request.plan)
    let segment = try #require(schedule.strokes.first?.segments.first)
    let endpoint = try Point2<MachineSpace>(x: 10.0006 + segment.delta.dx, y: 10.0006 + segment.delta.dy)
    #expect(region.contains(endpoint))
    #expect(endpoint.x >= 0 && endpoint.x < 0.001)
    #expect(endpoint.y >= 0 && endpoint.y < 0.001)
  }

  @Test("a whole thin stroke with no nonzero contained wire displacement refuses without actuation")
  func thinRegionCannotRoundOutside() async throws {
    let region = try DrawableMachineRegion(bounds: .init(minX: 0, minY: 0, maxX: 0.0006, maxY: 0.0006))
    let request = try drawingPlanRequest([[(0, 0), (0.0006, 0.0006)]], region: region)
    let exchanges = drawingPlanProbeExchanges(position: (0, 0))
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)
    guard case .refused(let progress, .unrepresentableStroke(let id)) =
      await fixture.interpreter.requestDrawingPlan(request) else {
      Issue.record("A tiny non-grid region cannot authorize an outward rounded stroke")
      return
    }
    #expect(id == request.plan.strokes[0].logicalStrokeID)
    #expect(progress.submittedSegmentCount == 0)
    #expect(fixture.link.completedWriteCount == exchanges.count)
  }

  @Test("nonfinite cumulative displacement and wire-integer overflow refuse before motion",
    arguments: [0, 1])
  func wireScheduleOverflowRefuses(caseIndex: Int) async throws {
    let points: [(Double, Double)] = caseIndex == 0
      ? [(-1e308, 0), (1e308, 0)] : [(0, 0), (9e15, 0), (-9e15, 0)]
    let request = try drawingPlanRequest([points], boundary: caseIndex == 0 ? 1e308 : 9e15)
    let exchanges = drawingPlanProbeExchanges(position: (0, 0))
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)
    guard case .refused(let progress, .invalidWireGeometry(let id)) =
      await fixture.interpreter.requestDrawingPlan(request) else {
      Issue.record("Unrepresentable finite-range arithmetic must fail before actuation")
      return
    }
    #expect(id == request.plan.strokes[0].logicalStrokeID)
    #expect(progress.submittedSegmentCount == 0)
    #expect(fixture.link.completedWriteCount == exchanges.count)
  }

  @Test("portrait stroke gaps within settlement tolerance command Pen-Up travel",
    arguments: [-0.4, 0.001, 0.4, 1.0])
  func submillimetreStrokeTravel(gap: Double) async throws {
    let request = try drawingPlanRequest([
      [(0, 0), (2, 0)], [(2, gap), (0, gap)],
    ])
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += strokeExchanges(try strokeRequest(from: (0, 0), to: (2, 0), request: request),
      from: (0, 0), to: (2, 0))
    exchanges += penExchanges(.raise, at: (2, 0), profile: request.penActuationProfile)
    exchanges += travelExchanges(try travelRequest(from: (2, 0), to: (2, gap), request: request),
      from: (2, 0), to: (2, gap))
    exchanges += penExchanges(.lower, at: (2, gap), profile: request.penActuationProfile)
    exchanges += strokeExchanges(try strokeRequest(from: (2, gap), to: (0, gap), request: request),
      from: (2, gap), to: (0, gap))
    exchanges += penExchanges(.raise, at: (0, gap), profile: request.penActuationProfile)
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)
    let outcome = await fixture.interpreter.requestDrawingPlan(request)
    guard case .completed(let progress, let position) = outcome else {
      Issue.record("Expected both distinct hatch strokes with their travel, got \(outcome)")
      return
    }
    #expect(position == (try MachinePosition(x: 0, y: gap)))
    #expect(progress.completedCheckpointIDs == request.plan.checkpoints.map(\.id))
    #expect(fixture.link.completedWriteCount == exchanges.count)
  }

  @Test("plan redundantly commands Pen Up before travel when Pen Up was already commanded")
  func planNormalizesKnownPenUp() async throws {
    let request = try drawingPlanRequest([[(0, 0), (1, 0)]])
    let stroke = try strokeRequest(from: (0, 0), to: (1, 0), request: request)
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += strokeExchanges(stroke, from: (0, 0), to: (1, 0))
    exchanges += penExchanges(.raise, at: (1, 0), profile: request.penActuationProfile)
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)

    #expect(
      await fixture.interpreter.requestPenActuation(
        .raise,
        profile: request.penActuationProfile
      ) == .commandedAndSettled(command: .raise, commandedState: .up)
    )

    guard case .completed = await fixture.interpreter.requestDrawingPlan(request) else {
      Issue.record("plan should execute after redundantly normalizing Pen Up")
      return
    }
    #expect(fixture.link.completedWriteCount == exchanges.count)
  }

  @Test("two strokes execute in plan order and commit checkpoints only after Pen Up")
  func twoStrokeOrderingAndCheckpoints() async throws {
    let request = try drawingPlanRequest([
      [(2, 0), (4, 0)],
      [(4, 2), (4, 4)],
    ])
    let travel1 = try travelRequest(from: (0, 0), to: (2, 0), request: request)
    let stroke1 = try strokeRequest(from: (2, 0), to: (4, 0), request: request)
    let travel2 = try travelRequest(from: (4, 0), to: (4, 2), request: request)
    let stroke2 = try strokeRequest(from: (4, 2), to: (4, 4), request: request)
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += travelExchanges(travel1, from: (0, 0), to: (2, 0))
    exchanges += penExchanges(.lower, at: (2, 0), profile: request.penActuationProfile)
    exchanges += strokeExchanges(stroke1, from: (2, 0), to: (4, 0))
    exchanges += penExchanges(.raise, at: (4, 0), profile: request.penActuationProfile)
    exchanges += travelExchanges(travel2, from: (4, 0), to: (4, 2))
    exchanges += penExchanges(.lower, at: (4, 2), profile: request.penActuationProfile)
    exchanges += strokeExchanges(stroke2, from: (4, 2), to: (4, 4))
    exchanges += penExchanges(.raise, at: (4, 4), profile: request.penActuationProfile)
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)

    let outcome = await fixture.interpreter.requestDrawingPlan(request)

    guard case .completed(let progress, let finalPosition) = outcome else {
      Issue.record("expected completed two-stroke plan, got \(outcome)")
      return
    }
    #expect(finalPosition == (try MachinePosition(x: 4, y: 4)))
    #expect(progress.completedStrokeIDs == request.plan.strokes.map(\.logicalStrokeID))
    #expect(progress.completedCheckpointIDs == request.plan.checkpoints.map(\.id))
    #expect(progress.commandedStrokeCount == 2)
    #expect(progress.controllerCompletedStrokeCount == 2)
    #expect(progress.submittedSegmentCount == 2)
    #expect(progress.controllerCompletedSegmentCount == 2)
    let restored = try JSONDecoder().decode(
      DrawingPlanProgressSnapshot.self,
      from: JSONEncoder().encode(progress)
    )
    #expect(restored == progress)
    #expect(Set([restored, progress]).count == 1)
    #expect(fixture.link.completedWriteCount == exchanges.count)
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.currentOperation == .idle)
    #expect(snapshot.lastDrawingPlanOutcome == outcome)
    #expect(snapshot.drawingPlanProgress == progress)
    #expect(snapshot.machine.penState == .up)
  }

  @Test("Stop cancels one plan owner, rejects competitors, and never resends a segment")
  func stopAndNoResend() async throws {
    let request = try drawingPlanRequest([[(0, 0), (0.000361, 0.000244), (2, 0)]])
    let segment = try strokeRequest(from: (0, 0), to: (2, 0), request: request)
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += [
      planStatusExchange((0, 0)),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeDrawingStroke(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      planStatusExchange((0.5, 0), state: "Jog"),
      SimulatedCommandExchange(expectedWrite: MachineController.encodeJogCancel, reads: []),
      planStatusExchange((0.5, 0)),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(
          .raise,
          profile: request.penActuationProfile
        ),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenSettle(profile: request.penActuationProfile),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
      ),
    ]
    let clock = DeterministicRuntimeClock()
    let base = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
    let gate = DrawingPlanReadGate()
    let blocking = DrawingPlanPostWriteBlockingLink(
      base: base,
      blockedCommand: MachineController.encodeDrawingStroke(segment),
      gate: gate
    )
    let interpreter = try await readyDrawingPlanInterpreter(link: blocking, clock: clock)
    let admission = await interpreter.beginDrawingPlan(request)
    guard case .admitted(let operation) = admission else {
      Issue.record("plan should be admitted")
      return
    }
    await gate.waitUntilBlockedRead()

    let competingJog = await interpreter.requestRelativeJog(try travelRequest(
      from: (0, 0),
      to: (1, 0),
      request: request
    ))
    #expect(competingJog == .refused(.operationInFlight))
    let competingRequest = try drawingPlanRequest([[(0, 0), (1, 1)]])
    guard case .rejected(let competingPlan) = await interpreter.beginDrawingPlan(competingRequest)
    else {
      Issue.record("second plan owner must be rejected")
      return
    }
    guard case .refused(_, .operationInFlight) = competingPlan else {
      Issue.record("second plan should report operationInFlight")
      return
    }
    let ownedSnapshot = await interpreter.snapshot()
    #expect(ownedSnapshot.currentOperation == .drawingPlan(request.operationID))
    #expect(ownedSnapshot.drawingPlanProgress?.operationID == request.operationID)
    #expect(ownedSnapshot.drawingPlanProgress?.plannedSegmentCount == 1)
    #expect(ownedSnapshot.drawingPlanProgress?.activeSegmentIndex == 1)

    let cancelTask = Task { await interpreter.requestJogCancel(.operatorStop) }
    await waitForPlanWriteCount(base, atLeast: exchanges.count - 3)
    await gate.release()
    let outcome = await operation.outcome()
    let finalPosition = try MachinePosition(x: 0.5, y: 0)
    #expect(await cancelTask.value == .completed(finalPosition: finalPosition))
    guard case .cancelled(
      let progress,
      .operatorStop,
      let jogCancelOutcome,
      let outcomePosition,
      let penRaiseOutcome
    ) = outcome else {
      Issue.record("expected operator cancellation, got \(outcome)")
      return
    }
    #expect(jogCancelOutcome == .completed(finalPosition: finalPosition))
    #expect(outcomePosition == finalPosition)
    #expect(progress.completedCheckpointIDs.isEmpty)
    #expect(progress.commandedStrokeCount == 1)
    #expect(progress.controllerCompletedStrokeCount == 0)
    #expect(progress.submittedSegmentCount == 1)
    #expect(progress.controllerCompletedSegmentCount == 0)
    #expect(
      penRaiseOutcome == .commandedAndSettled(command: .raise, commandedState: .up)
    )
    #expect(base.completedWriteCount == exchanges.count)
    #expect(await interpreter.snapshot().machine.penState == .up)
  }

  @Test("pre-motion refusal and post-write ambiguity remain distinct")
  func refusalAndAmbiguity() async throws {
    let request = try drawingPlanRequest([[(0, 0), (1, 0)]])
    let disconnected = RunInterpreter(
      machineController: MachineController(
        link: SimulatedGRBLLink(exchanges: [], clock: DeterministicRuntimeClock())
      )
    )
    let refused = await disconnected.requestDrawingPlan(request)
    guard case .refused(_, .initialPenRaise(.notConnected)) = refused else {
      Issue.record("expected pre-motion notConnected refusal, got \(refused)")
      return
    }

    let segment = try strokeRequest(from: (0, 0), to: (1, 0), request: request)
    let command = MachineController.encodeDrawingStroke(segment)
    let ambiguity = MotionAmbiguity.partialWrite(
      bytesWritten: 1,
      totalBytes: command.count
    )
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += [
      planStatusExchange((0, 0)),
      SimulatedCommandExchange(
        expectedWrite: command,
        reads: [],
        writeError: .writeTimedOut(bytesWritten: 1, totalBytes: command.count)
      ),
    ]
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)
    let ambiguous = await fixture.interpreter.requestDrawingPlan(request)

    guard case .ambiguous(let progress, .stroke(let reason)) = ambiguous else {
      Issue.record("expected sticky stroke ambiguity, got \(ambiguous)")
      return
    }
    #expect(reason == ambiguity)
    #expect(progress.commandedStrokeCount == 1)
    #expect(progress.controllerCompletedStrokeCount == 0)
    #expect(progress.submittedSegmentCount == 1)
    #expect(progress.controllerCompletedSegmentCount == 0)
    #expect(fixture.link.completedWriteCount == exchanges.count)
    let snapshot = await fixture.interpreter.snapshot()
    #expect(snapshot.machine.penState == .unknown)
    #expect(snapshot.machine.motionGuardState == .inactive)
  }

  @Test("stroke refusal becomes possible ink and performs one Pen Up cleanup")
  func possibleInkRaisesPen() async throws {
    let request = try drawingPlanRequest([[(0, 0), (1, 0)]])
    let segment = try strokeRequest(from: (0, 0), to: (1, 0), request: request)
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += [
      planStatusExchange((0, 0)),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeDrawingStroke(segment),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("error:15\r\n".utf8)))]
      ),
    ]
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)

    let outcome = await fixture.interpreter.requestDrawingPlan(request)

    guard case .possibleInk(
      let progress,
      .strokeRefused(.controllerRejected("error:15")),
      let raiseOutcome
    ) = outcome else {
      Issue.record("expected possible-ink refusal, got \(outcome)")
      return
    }
    #expect(progress.completedCheckpointIDs.isEmpty)
    #expect(progress.commandedStrokeCount == 1)
    #expect(progress.controllerCompletedStrokeCount == 0)
    #expect(progress.submittedSegmentCount == 1)
    #expect(progress.controllerCompletedSegmentCount == 0)
    #expect(raiseOutcome == .commandedAndSettled(command: .raise, commandedState: .up))
    #expect(fixture.link.completedWriteCount == exchanges.count)
    #expect(await fixture.interpreter.snapshot().machine.penState == .up)
  }

  @Test("travel and Pen Down refusals do not cross the commanded-stroke frontier")
  func preStrokeRefusals() async throws {
    let travelRequestPlan = try drawingPlanRequest([[(2, 0), (4, 0)]])
    let travel = try travelRequest(from: (0, 0), to: (2, 0), request: travelRequestPlan)
    var travelExchanges = drawingPlanProbeExchanges(position: (0, 0))
    travelExchanges += penExchanges(
      .raise,
      at: (0, 0),
      profile: travelRequestPlan.penActuationProfile
    )
    travelExchanges += [
      planStatusExchange((0, 0)),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodeRelativeJog(travel),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("error:15\r\n".utf8)))]
      ),
    ]
    let travelFixture = try await DrawingPlanInterpreterFixture.make(
      exchanges: travelExchanges
    )

    let travelOutcome = await travelFixture.interpreter.requestDrawingPlan(travelRequestPlan)

    guard case .refused(let travelProgress, .travel(.controllerRejected("error:15"))) =
      travelOutcome
    else {
      Issue.record("expected travel refusal, got \(travelOutcome)")
      return
    }
    #expect(travelProgress.commandedStrokeCount == 0)
    #expect(travelProgress.controllerCompletedStrokeCount == 0)
    #expect(travelProgress.submittedSegmentCount == 0)
    #expect(travelProgress.controllerCompletedSegmentCount == 0)

    let lowerRequest = try drawingPlanRequest([[(0, 0), (1, 0)]])
    var lowerExchanges = drawingPlanProbeExchanges(position: (0, 0))
    lowerExchanges += penExchanges(
      .raise,
      at: (0, 0),
      profile: lowerRequest.penActuationProfile
    )
    lowerExchanges += [
      planStatusExchange((0, 0)),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(
          .lower,
          profile: lowerRequest.penActuationProfile
        ),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("error:15\r\n".utf8)))]
      ),
    ]
    let lowerFixture = try await DrawingPlanInterpreterFixture.make(exchanges: lowerExchanges)

    let lowerOutcome = await lowerFixture.interpreter.requestDrawingPlan(lowerRequest)

    guard case .refused(let lowerProgress, .penLower(.controllerRejected("error:15"))) =
      lowerOutcome
    else {
      Issue.record("expected Pen Down refusal, got \(lowerOutcome)")
      return
    }
    #expect(lowerProgress.commandedStrokeCount == 0)
    #expect(lowerProgress.controllerCompletedStrokeCount == 0)
    #expect(lowerProgress.submittedSegmentCount == 0)
    #expect(lowerProgress.controllerCompletedSegmentCount == 0)
  }

  @Test("completed segments cross the controller stroke frontier before Pen Up")
  func raiseRefusalPreservesControllerCompletion() async throws {
    let request = try drawingPlanRequest([[(0, 0), (1, 0)]])
    let segment = try strokeRequest(from: (0, 0), to: (1, 0), request: request)
    var exchanges = drawingPlanProbeExchanges(position: (0, 0))
    exchanges += penExchanges(.raise, at: (0, 0), profile: request.penActuationProfile)
    exchanges += penExchanges(.lower, at: (0, 0), profile: request.penActuationProfile)
    exchanges += strokeExchanges(segment, from: (0, 0), to: (1, 0))
    exchanges += [
      planStatusExchange((1, 0)),
      SimulatedCommandExchange(
        expectedWrite: MachineController.encodePenActuation(
          .raise,
          profile: request.penActuationProfile
        ),
        reads: [ScheduledMachineRead(outcome: .bytes(Data("error:15\r\n".utf8)))]
      ),
    ]
    let fixture = try await DrawingPlanInterpreterFixture.make(exchanges: exchanges)

    let outcome = await fixture.interpreter.requestDrawingPlan(request)

    guard case .possibleInk(
      let progress,
      .penRaiseRefused(.controllerRejected("error:15")),
      .refused(.controllerRejected("error:15"))
    ) = outcome else {
      Issue.record("expected final Pen Up refusal, got \(outcome)")
      return
    }
    #expect(progress.commandedStrokeCount == 1)
    #expect(progress.controllerCompletedStrokeCount == 1)
    #expect(progress.submittedSegmentCount == 1)
    #expect(progress.controllerCompletedSegmentCount == 1)
    #expect(progress.completedStrokeIDs.isEmpty)
    #expect(progress.completedCheckpointIDs.isEmpty)
  }
}

private struct DrawingPlanInterpreterFixture {
  let link: SimulatedGRBLLink
  let interpreter: RunInterpreter

  static func make(
    exchanges: [SimulatedCommandExchange]
  ) async throws -> Self {
    let clock = DeterministicRuntimeClock()
    let link = SimulatedGRBLLink(exchanges: exchanges, clock: clock)
    return Self(
      link: link,
      interpreter: try await readyDrawingPlanInterpreter(link: link, clock: clock)
    )
  }
}

private func readyDrawingPlanInterpreter(
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
  return interpreter
}

private func drawingPlanRequest(
  _ strokePoints: [[(Double, Double)]], boundary: Double = 10, region: DrawableMachineRegion? = nil
) throws -> DrawingPlanRequest {
  let programHash = try planDigest(1)
  let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
  var strokes: [PlannedMachineStroke] = []
  var checkpoints: [ExecutionCheckpoint] = []
  for (index, points) in strokePoints.enumerated() {
    let strokeID = StrokeID()
    let checkpointID = PlanCheckpointID()
    let ordering = UInt32(index)
    let path = try Polyline<MachineSpace>(points: points.map { point in
      try Point2(x: point.0, y: point.1)
    })
    strokes.append(PlannedMachineStroke(
      logicalStrokeID: strokeID,
      path: path,
      style: style,
      semanticRole: .drawing,
      ordering: ordering,
      endingCheckpointID: checkpointID
    ))
    checkpoints.append(ExecutionCheckpoint(
      id: checkpointID,
      afterStrokeID: strokeID,
      ordering: ordering
    ))
  }
  let plan = try ExecutionPlanRevision(
    sourceProgramID: ProgramID(),
    sourceProgramContentHash: programHash,
    placement: DrawingPlacement(
      fieldAnchor: Point2(x: 0, y: 0),
      machineAnchor: Point2(x: 0, y: 0),
      uniformScale: 1
    ),
    drawableRegion: region ?? DrawableMachineRegion(
      bounds: AxisAlignedBounds(minX: -boundary, minY: -boundary, maxX: boundary, maxY: boundary)
    ),
    provenance: DrawingPlanningProvenance(
      modelRevisionID: DrawingModelRevisionID(),
      modelContentHash: try planDigest(2),
      registrationRevisionID: DrawingRegistrationRevisionID(),
      registrationContentHash: try planDigest(3)
    ),
    strokes: strokes,
    checkpoints: checkpoints
  )
  return try DrawingPlanRequest(
    plan: plan,
    travelFeedMMPerMinute: 120,
    drawingFeedMMPerMinute: 60,
    penActuationProfile: .initialDefaults
  )
}

private func planDigest(_ byte: UInt8) throws -> Digest {
  try Digest(bytes: Array(repeating: byte, count: Digest.byteCount))
}

private func travelRequest(
  from: (Double, Double),
  to: (Double, Double),
  request: DrawingPlanRequest
) throws -> RelativeJogRequest {
  RelativeJogRequest(
    delta: try Vector2(dx: to.0 - from.0, dy: to.1 - from.1),
    feedMMPerMinute: request.travelFeedMMPerMinute
  )
}

private func strokeRequest(
  from: (Double, Double),
  to: (Double, Double),
  request: DrawingPlanRequest
) throws -> DrawingStrokeRequest {
  DrawingStrokeRequest(
    delta: try Vector2(dx: to.0 - from.0, dy: to.1 - from.1),
    feedMMPerMinute: request.drawingFeedMMPerMinute
  )
}

private func drawingPlanProbeExchanges(
  position: (Double, Double)
) -> [SimulatedCommandExchange] {
  var exchanges = ControllerTranscriptFixtures.successfulPassiveProbe()
  exchanges[2] = ControllerTranscriptFixtures.exchange(
    .status,
    chunks: ["<Idle|MPos:\(position.0),\(position.1),0.000>\r\n"]
  )
  exchanges[3] = ControllerTranscriptFixtures.exchange(
    .configuration,
    chunks: ["$110=500\r\n$111=500\r\n$120=10\r\n$121=10\r\nok\r\n"]
  )
  return exchanges
}

private func planStatusExchange(
  _ point: (Double, Double),
  state: String = "Idle"
) -> SimulatedCommandExchange {
  SimulatedCommandExchange(
    expectedWrite: PassiveQuery.status.wireBytes,
    reads: [ScheduledMachineRead(outcome: .bytes(Data(
      String(
        format: "<%@|MPos:%.3f,%.3f,0.000>\r\n",
        locale: Locale(identifier: "en_US_POSIX"),
        state,
        point.0,
        point.1
      ).utf8
    )))]
  )
}

private func penExchanges(
  _ command: PenCommand,
  at point: (Double, Double),
  profile: PenActuationProfile
) -> [SimulatedCommandExchange] {
  [
    planStatusExchange(point),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenActuation(command, profile: profile),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodePenSettle(profile: profile),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
  ]
}

private func travelExchanges(
  _ request: RelativeJogRequest,
  from: (Double, Double),
  to: (Double, Double)
) -> [SimulatedCommandExchange] {
  [
    planStatusExchange(from),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeRelativeJog(request),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    planStatusExchange(to),
  ]
}

private func strokeExchanges(
  _ request: DrawingStrokeRequest,
  from: (Double, Double),
  to: (Double, Double)
) -> [SimulatedCommandExchange] {
  [
    planStatusExchange(from),
    SimulatedCommandExchange(
      expectedWrite: MachineController.encodeDrawingStroke(request),
      reads: [ScheduledMachineRead(outcome: .bytes(Data("ok\r\n".utf8)))]
    ),
    planStatusExchange(to),
  ]
}

private actor DrawingPlanReadGate {
  private var blocked = false
  private var released = false
  private var blockWaiters: [CheckedContinuation<Void, Never>] = []
  private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

  func waitUntilBlockedRead() async {
    guard !blocked else { return }
    await withCheckedContinuation { blockWaiters.append($0) }
  }

  func block() async {
    blocked = true
    let waiters = blockWaiters
    blockWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    guard !released else { return }
    await withCheckedContinuation { releaseWaiters.append($0) }
  }

  func release() {
    released = true
    let waiters = releaseWaiters
    releaseWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

private actor DrawingPlanPostWriteState {
  let blockedCommand: Data
  var didWriteBlockedCommand = false
  var shouldBlockNextRead = false
  var didBlock = false

  init(blockedCommand: Data) {
    self.blockedCommand = blockedCommand
  }

  func noteWrite(_ bytes: Data) {
    if bytes == blockedCommand {
      didWriteBlockedCommand = true
    } else if didWriteBlockedCommand,
      bytes == PassiveQuery.status.wireBytes,
      !didBlock
    {
      shouldBlockNextRead = true
    }
  }

  func consumeBlock() -> Bool {
    guard shouldBlockNextRead, !didBlock else { return false }
    shouldBlockNextRead = false
    didBlock = true
    return true
  }
}

private final class DrawingPlanPostWriteBlockingLink: MachineLink, @unchecked Sendable {
  let descriptor: MachineLinkDescriptor
  private let base: any MachineLink
  private let state: DrawingPlanPostWriteState
  private let gate: DrawingPlanReadGate

  init(base: any MachineLink, blockedCommand: Data, gate: DrawingPlanReadGate) {
    self.base = base
    state = DrawingPlanPostWriteState(blockedCommand: blockedCommand)
    self.gate = gate
    descriptor = base.descriptor
  }

  func open() async throws -> MachineLinkOpenReceipt { try await base.open() }
  func close() async throws { try await base.close() }
  func discardPendingInput() async throws -> MachineLinkDiscardReceipt {
    try await base.discardPendingInput()
  }

  func write(_ bytes: Data) async throws -> MachineLinkWriteReceipt {
    let receipt = try await base.write(bytes)
    await state.noteWrite(bytes)
    return receipt
  }

  func read(
    maximumBytes: Int,
    timeoutNanoseconds: UInt64
  ) async throws -> MachineLinkReadReceipt {
    if await state.consumeBlock() { await gate.block() }
    return try await base.read(
      maximumBytes: maximumBytes,
      timeoutNanoseconds: timeoutNanoseconds
    )
  }
}

private func waitForPlanWriteCount(
  _ link: SimulatedGRBLLink,
  atLeast expected: Int
) async {
  while link.completedWriteCount < expected { await Task.yield() }
}
