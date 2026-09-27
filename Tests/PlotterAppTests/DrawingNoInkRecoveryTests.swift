import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Stopped drawing no-ink recovery", .serialized)
@MainActor
struct DrawingNoInkRecoveryTests {
  @Test("operator confirmation preserves the attempt and placement, persists, and never starts motion")
  func durableRetry() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .circle)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan), outcome: .cancelled)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(run.snapshot.terminal)
    #expect(terminal.record.allowsNoInkConfirmation)
    let before = await harness.evidence.archive
    let events = await harness.events.values
    let retry = await harness.runtime.submit(.init(projection: run.snapshot.projection,
      intent: .confirmNoInkAndPrepareRetry(terminal.runID)))
    #expect(retry.disposition == .applied)
    #expect(retry.snapshot.terminal == nil)
    #expect(await harness.events.values == events)
    #expect(await harness.interpreter.planRequests.count == 1)
    let archive = try #require(await harness.evidence.reopenedArchive())
    #expect(archive.records == before.records)
    #expect(archive.attempts == before.attempts)
    #expect(archive.confirmedNoInkRunIDs == [terminal.runID])
    let next = await harness.runtime.synchronize(environment: .live)
    #expect(next.readiness == .ready)
    #expect(next.projection.planIdentity == plan.identity)
    let reopened = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan),
      archiveLoadResult: .loaded(archive))
    #expect(await reopened.runtime.synchronize(environment: .live).readiness == .ready)
    #expect(await reopened.events.values.isEmpty)
    let duplicate = try archive.confirmingNoInk(.init(runID: terminal.runID))
    #expect(duplicate == archive)
  }

  @Test("confirmation of one cancelled run does not erase another run at the same placement")
  func unrelatedAttemptStillBlocks() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .circle)
    let first = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan), outcome: .cancelled)
    let second = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan), outcome: .cancelled)
    let a = await first.runtime.synchronize(environment: .live)
    let b = await second.runtime.synchronize(environment: .live)
    let run = await first.runtime.submit(.init(projection: a.projection, intent: .start))
    _ = await second.runtime.submit(.init(projection: b.projection, intent: .start))
    let archiveA = await first.evidence.archive, archiveB = await second.evidence.archive
    let combined = try DrawingRunEvidenceArchive(revision: 2, records: archiveA.records + archiveB.records,
      attempts: archiveA.attempts + archiveB.attempts)
      .confirmingNoInk(.init(runID: try #require(run.snapshot.terminal).runID))
    let restored = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan),
      archiveLoadResult: .loaded(combined))
    let state = await restored.runtime.synchronize(environment: .live)
    let blocked = await restored.runtime.submit(.init(projection: state.projection, intent: .start))
    #expect(try #require(blocked.snapshot.lastRefusal).reason == .planMayAlreadyContainInk)
    #expect(await restored.events.values.isEmpty)
  }

  @Test("unsettled pen and failed confirmation persistence do not release the terminal")
  func unavailableControllerAndSaveFailure() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .circle)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan), outcome: .cancelled)
    let ready = await harness.runtime.synchronize(environment: .live)
    let run = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(run.snapshot.terminal)
    await harness.interpreter.setPenState(.down)
    let refused = await harness.runtime.submit(.init(projection: run.snapshot.projection,
      intent: .confirmNoInkAndPrepareRetry(terminal.runID)))
    #expect(try #require(refused.snapshot.lastRefusal).reason == .controllerUnavailable)
    #expect(refused.snapshot.terminal == terminal)
    #expect(await harness.evidence.reopenedArchive()?.noInkConfirmations.isEmpty == true)
    await harness.interpreter.setPenState(.up)
    await harness.evidence.failNextNoInkConfirmation()
    let failed = await harness.runtime.submit(.init(projection: refused.snapshot.projection,
      intent: .confirmNoInkAndPrepareRetry(terminal.runID)))
    #expect(try #require(failed.snapshot.lastRefusal).reason == .evidenceArchiveUnavailable)
    #expect(failed.snapshot.terminal == terminal)
    #expect(await harness.evidence.reopenedArchive()?.noInkConfirmations.isEmpty == true)
  }

  @Test("completed attempts cannot be relabeled uninked")
  func completedRunRefuses() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .circle)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan))
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.runtime.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(result.snapshot.terminal)
    let retry = await harness.runtime.submit(.init(projection: result.snapshot.projection,
      intent: .confirmNoInkAndPrepareRetry(terminal.runID)))
    #expect(try #require(retry.snapshot.lastRefusal).reason == .runIdentityMismatch)
    let archive = await harness.evidence.archive
    #expect(throws: DrawingRunEvidenceArchiveError.self) {
      try archive.confirmingNoInk(.init(runID: terminal.runID))
    }
  }
}
