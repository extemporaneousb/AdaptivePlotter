import Foundation
import PlotterEpisodeModel
import PlotterModel
import Testing
@testable import PlotterApp
@testable import PlotterEpisodeRuntime
@testable import PlotterRuntime

@Suite("Drawing Run publication ordering", .serialized)
@MainActor
struct DrawingRunPublicationOrderingTests {
  enum PollSettlement: Sendable, CaseIterable { case stop, terminal, newRun }

  @Test("a suspended lower progress poll cannot restore state before Stop or settlement",
    arguments: PollSettlement.allCases)
  func heldProgressPoll(_ settlement: PollSettlement) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let planGate = DrawingRunPlanGate()
    let pollGate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: planGate,
      releasePlanOnStop: false)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await planGate.waitUntilStarted()
    let executing = await harness.runtime.snapshot(environment: .live)
    let capability = try #require(executing.stopCapabilityID)
    await harness.interpreter.holdNextSnapshot(at: pollGate)
    let poll = Task { await harness.runtime.snapshot(environment: .live) }
    // This is the actual lower snapshot continuation, after the runtime has
    // captured executing state. No scheduling delay stands in for the barrier.
    await pollGate.waitUntilHeld()
    let stopped = await harness.runtime.submit(.init(projection: executing.projection,
      intent: .stop(capability)))
    #expect(stopped.disposition == .applied)
    #expect(stopped.snapshot.activeRunID == executing.activeRunID)
    #expect(stopped.snapshot.projection.runRevision > executing.projection.runRevision)
    var expected = stopped.snapshot
    if settlement != .stop {
      await planGate.release(.cancelled)
      expected = await run.value.snapshot
      #expect(expected.terminal?.disposition == .cancelled)
      if settlement == .newRun {
        let terminal = try #require(expected.terminal)
        let next = await harness.runtime.submit(.init(projection: expected.projection,
          intent: .beginNewRun(terminal.runID)))
        #expect(next.disposition == .applied)
        #expect(next.snapshot.phase == .idle)
        expected = next.snapshot
      }
    }
    await pollGate.release()
    #expect(await poll.value == expected)
    #expect(await harness.runtime.snapshot(environment: .live) == expected)
    if settlement == .stop {
      await planGate.release(.cancelled)
      #expect(await run.value.snapshot.terminal?.disposition == .cancelled)
    }
    #expect(await harness.interpreter.stopIntents == [.operatorStop])
    #expect(await harness.interpreter.planRequests.count == 1)
    #expect(await harness.evidence.attempts.count == 1)
  }

  @Test("same-state lower progress updates preserve the existing run revision")
  func progressDoesNotInventSemanticRevision() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunPlanGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: gate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilStarted()
    let request = try #require(await gate.request)
    let before = await harness.runtime.snapshot(environment: .live)
    let progress = drawingRunOutcome(.completed, request: request).progress
    await harness.interpreter.setDrawingProgress(progress)
    let after = await harness.runtime.snapshot(environment: .live)
    #expect(after.projection == before.projection)
    #expect(after.progress == progress)
    #expect(after.progress != before.progress)
    #expect(after.activeRunID == before.activeRunID)
    await gate.release(.completed)
    #expect(await run.value.snapshot.terminal?.disposition == .succeeded)
  }

  @Test("overlapping polls retain the later same-revision execution frontier")
  func earlierHeldPollCannotReplaceLaterProgress() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let planGate = DrawingRunPlanGate()
    let pollGate = DrawingRunHoldGate()
    let harness = await drawingRunHarness(fixture: fixture, planGate: planGate)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = Task { await harness.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await planGate.waitUntilStarted()
    let request = try #require(await planGate.request)
    let earlyProgress = drawingRunOutcome(.cancelled, request: request).progress
    let laterProgress = drawingRunOutcome(.completed, request: request).progress
    await harness.interpreter.setDrawingProgress(earlyProgress)
    let early = await harness.runtime.snapshot(environment: .live)
    #expect(early.progress == earlyProgress)
    await harness.interpreter.holdNextSnapshot(at: pollGate)
    let pollA = Task { await harness.runtime.snapshot(environment: .live) }
    await pollGate.waitUntilHeld() // A has captured the nonnil earlier progress.
    await harness.interpreter.setDrawingProgress(laterProgress)
    let pollB = await harness.runtime.snapshot(environment: .live)
    #expect(pollB.projection == early.projection)
    #expect(pollB.progress == laterProgress)
    await pollGate.release()
    // Assert A's returned state before any subsequent poll could repair it.
    let releasedA = await pollA.value
    #expect(releasedA == pollB)
    await planGate.release(.completed)
    #expect(await run.value.snapshot.terminal?.disposition == .succeeded)
  }

  @Test("execution frontiers preserve command, controller and pen-up commit distinctions")
  func frontierOrderingPreservesStageBoundaries() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let stroke = try #require(fixture.plan.plan.strokes.first)
    let operationID = DrawingPlanOperationID()
    func progress(commanded: Int = 0, submitted: Int = 0, completed: Int = 0,
      committed: Bool = false, active: Bool = false, segment: Int? = nil,
      operation: DrawingPlanOperationID? = nil, checkpoint: PlanCheckpointID? = nil
    ) -> DrawingPlanProgressSnapshot {
      DrawingPlanProgressSnapshot(operationID: operation ?? operationID,
        planRevisionID: fixture.plan.plan.revisionID, plannedStrokeCount: 1, plannedSegmentCount: 2,
        commandedStrokeCount: commanded, controllerCompletedStrokeCount: completed == 2 ? 1 : 0,
        submittedSegmentCount: submitted, controllerCompletedSegmentCount: completed,
        completedStrokeIDs: committed ? [stroke.logicalStrokeID] : [],
        completedCheckpointIDs: committed ? [checkpoint ?? stroke.endingCheckpointID] : [],
        activeStrokeID: active ? stroke.logicalStrokeID : nil, activeSegmentIndex: segment)
    }
    let states = [progress(), progress(active: true),
      progress(commanded: 1, submitted: 1, active: true, segment: 0),
      progress(commanded: 1, submitted: 1, completed: 1, active: true, segment: 0),
      progress(commanded: 1, submitted: 2, completed: 1, active: true, segment: 1),
      progress(commanded: 1, submitted: 2, completed: 2, active: true, segment: 1),
      progress(commanded: 1, submitted: 2, completed: 2, committed: true)]
    for (index, current) in states.enumerated() {
      #expect(current.isExecutionFrontier(atLeastAsAdvancedAs: current))
      for earlier in states.prefix(index) {
        #expect(current.isExecutionFrontier(atLeastAsAdvancedAs: earlier))
        #expect(!earlier.isExecutionFrontier(atLeastAsAdvancedAs: current))
      }
    }
    #expect(!progress(operation: DrawingPlanOperationID()).isExecutionFrontier(atLeastAsAdvancedAs: states[0]))
    let divergentCommit = progress(commanded: 1, submitted: 2, completed: 2,
      committed: true, checkpoint: PlanCheckpointID())
    #expect(!divergentCommit.isExecutionFrontier(atLeastAsAdvancedAs: states[6]))
  }

  @Test("a fresh application accepts its new runtime's initial revision")
  func freshLifetimeStartsAtZero() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    var runtime: PlotterDrawingRunRuntime?
    let application = plotterApplicationRuntime(machine: machine,
      drawingRunRuntimeAccess: { runtime = $0 }, log: log)
    let owner = try #require(runtime)
    let initial = await owner.snapshot(environment: .live)
    #expect(initial.projection.runRevision.rawValue == 0)
    application.installDrawingRunSnapshot(initial)
    #expect(application.drawingRunSnapshot == initial)
    await application.shutdown()
  }
}

/// Called by the real application held-Stop fixture after its immediate
/// settlement assertions. Replay the producer's actual buffered publications
/// out of order; do not fabricate active/terminal phases or poll for repair.
@MainActor
func verifyDrawingRunPublicationOrdering(
  application: PlotterApplicationRuntime,
  runtime: PlotterDrawingRunRuntime,
  publications: AsyncStream<PlotterDrawingRunSnapshot>,
  terminalRunID: RunID
) async throws {
  var iterator = publications.makeAsyncIterator()
  var earlier: [PlotterDrawingRunSnapshot] = []
  while let value = await iterator.next() {
    if value.terminal?.runID == terminalRunID, case .persisted = value.evidencePersistence { break }
    earlier.append(value)
  }
  #expect(earlier.contains { $0.phase == .appendingEvidence && $0.terminal == nil })
  let settled = await runtime.snapshot(environment: .live)
  application.installDrawingRunSnapshot(settled)
  let publishedTerminal = try #require(application.drawingRunSnapshot)
  for value in earlier where value.projection.runRevision < publishedTerminal.projection.runRevision {
    application.installDrawingRunSnapshot(value)
    #expect(application.drawingRunSnapshot == publishedTerminal)
  }

  // Sample the other environment before capturing the publication under test.
  // Awaiting afterward permits a legitimate newer LIVE publication to arrive.
  let simulated = await runtime.snapshot(environment: .simulated)
  let next = await runtime.submit(.init(projection: settled.projection,
    intent: .beginNewRun(terminalRunID)))
  #expect(next.disposition == .applied)
  application.installDrawingRunSnapshot(next.snapshot)
  let newRun = try #require(application.drawingRunSnapshot)
  #expect(newRun.phase == .idle)
  #expect(newRun.terminal == nil)
  #expect(newRun.projection.runRevision > settled.projection.runRevision)
  application.installDrawingRunSnapshot(settled)
  #expect(application.drawingRunSnapshot == newRun)

  // SIM has its own revision sequence. Returning to LIVE must retain the
  // consumed LIVE revision even though the displayed snapshot was replaced.
  application.frameMode = .simulated
  application.installDrawingRunSnapshot(simulated)
  #expect(application.drawingRunSnapshot == simulated)
  application.frameMode = .live
  application.installDrawingRunSnapshot(settled)
  #expect(application.drawingRunSnapshot == simulated)
  application.installDrawingRunSnapshot(newRun)
  #expect(application.drawingRunSnapshot == newRun)
}
