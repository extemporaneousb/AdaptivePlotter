import Foundation
import PortraitCore
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing
@testable import PlotterRuntime
@testable import PlotterApp

@Suite("Drawing issuance Run and raw boundaries", .serialized)
@MainActor struct PlotterDrawingIssuanceTests {
  @Test("Canonical raw stage deduplicates exact concurrency, rejects changed body and never accepts job stageIntent")
  func atomicRawStage() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunHoldGate()
    let h = await drawingRunHarness(fixture: fixture, normalizationGate: gate)
    let ready = await h.runtime.synchronize(environment: .live)
    let start = Task { await h.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilHeld()
    let intent = try #require(await h.evidence.archive.attempts.first?.intent)
    let binding = try #require(intent.issuance)
    let proposal = try DrawingRunIssuanceProposal(body: intent.body, binding: binding)
    let url = h.destination.root.appendingPathComponent("atomic-raw.json")
    let store = DrawingRunEvidenceStore(fileURL: url)
    async let a = store.stageIssuance(proposal)
    async let b = store.stageIssuance(proposal)
    let receipts = try await (a, b)
    #expect(receipts.0.intent == receipts.1.intent)
    #expect([receipts.0.disposition, receipts.1.disposition].filter { $0 == .newlyStaged }.count == 1)
    #expect(try await store.lookupIssuance(binding)?.intent == receipts.0.intent)
    do {
      _ = try DrawingRunEvidenceArchive(revision: 0, records: [], attempts: [DrawingRunAttemptState(intent: receipts.0.intent),
        DrawingRunAttemptState(intent: DrawingRunIntent(runID: RunID(), body: intent.body, issuance: binding))])
      Issue.record("Archive admitted two RunIDs for one issuance")
    } catch {}
    do { _ = try await store.stageIntent(receipts.0.intent); Issue.record("Job intent bypassed canonical stage") } catch {}
    let changed = try DrawingRunIntentBody(requestID: intent.requestID, plan: intent.plan,
      placementID: intent.placementID, role: intent.role, context: intent.context,
      observationPlan: intent.observationPlan, recordedAt: .init(monotonicNanoseconds: intent.recordedAt.monotonicNanoseconds + 1))
    do { _ = try await store.stageIssuance(.init(body: changed, binding: binding)); Issue.record("Changed body reused issuance") } catch {}
    let uncertain = DrawingRunEvidenceStore(fileURL: h.destination.root.appendingPathComponent("uncertain-raw.json"),
      publicationFault: { _ in throw DrawingRunEvidenceProbeError.stageFailed })
    let recovered = try await uncertain.stageIssuance(proposal)
    #expect(recovered.disposition == .existing)
    #expect(try await uncertain.lookupIssuance(binding)?.intent == recovered.intent)
    #expect(try await uncertain.stageIssuance(proposal).intent == recovered.intent)
    await gate.release(); _ = await start.value
    await h.destination.close()
  }

  @Test("Missing, corrupt or mismatched canonical stage fails publication and retains the exact recovery cursor", arguments: [0, 1, 2])
  func publicationRequiresExactExistingStage(_ fault: Int) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, evidenceFailures: 1)
    let ready = await h.runtime.synchronize(environment: .live)
    let failed = await h.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(failed.snapshot.terminal)
    let intent = try #require(terminal.record.attemptEvidence?.intent)
    guard case .failed(_, let cursor, _) = failed.snapshot.evidencePersistence else { Issue.record("No publication cursor"); return }
    let manifest = try Data(contentsOf: h.evidence.archiveURL)
    let before = await h.events.values
    if fault == 0 { try FileManager.default.removeItem(at: h.evidence.archiveURL) }
    else if fault == 1 { try Data("corrupt raw manifest".utf8).write(to: h.evidence.archiveURL, options: .atomic) }
    else { await h.evidence.replaceLookupIntent(try DrawingRunIntent(runID: RunID(), body: intent.body, issuance: intent.issuance)) }
    let rejected = await h.runtime.submit(.init(projection: failed.snapshot.projection, intent: .recoverPublication(cursor)))
    guard case .failed(let record, let retained, _) = rejected.snapshot.evidencePersistence else { Issue.record("Unverified stage allowed publication"); return }
    #expect(record == terminal.record.recordID && retained == cursor)
    #expect(rejected.snapshot.terminal?.record == terminal.record)
    #expect(rejected.snapshot.terminal?.disposition == .publicationIncomplete)
    #expect(await h.events.values == before)
    try manifest.write(to: h.evidence.archiveURL, options: .atomic)
    await h.evidence.replaceLookupIntent(nil)
    let repaired = await h.runtime.submit(.init(projection: rejected.snapshot.projection, intent: .recoverPublication(cursor)))
    #expect(repaired.snapshot.terminal?.record == terminal.record)
    if case .persisted = repaired.snapshot.evidencePersistence {} else { Issue.record("Exact original publication did not recover") }
    #expect(await h.evidence.archive.attempts.count == 1)
    #expect(await h.interpreter.planRequests.count == 1)
    #expect(await h.events.values.filter { $0 == "stage-intent" }.count == 1)
    await h.destination.close()
  }

  @Test("Pending Stop and synchronous shutdown survive held accepted link without a first effect", arguments: [false, true])
  func closeDuringAcceptedLink(_ shutdown: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let gate = DrawingRunHoldGate()
    let h = await drawingRunHarness(fixture: fixture)
    h.destination.publicationProbe.linkGate = gate
    let ready = await h.runtime.synchronize(environment: .live)
    let start = Task { await h.runtime.submit(.init(projection: ready.projection, intent: .start)) }
    await gate.waitUntilHeld()
    let held = await h.runtime.currentSnapshot(environment: .live)
    let stop = try #require(held.stopCapabilityID)
    #expect(held.ownsWorkflow && held.activeRunID != nil)
    var joined = false
    let closing = Task {
      if shutdown { _ = await h.runtime.beginShutdown(environment: .live) }
      else { _ = await h.runtime.submit(.init(projection: held.projection, intent: .stop(stop))) }
      joined = true
    }
    if shutdown { h.runtime.closeAdmissionAndCancel() }
    await Task.yield()
    if shutdown { #expect(!joined) }
    else { #expect((await h.runtime.currentSnapshot(environment: .live)).ownsWorkflow) }
    await gate.release()
    _ = await start.value; await closing.value
    _ = try await issuanceSettled(h.runtime)
    #expect(await h.interpreter.planRequests.isEmpty)
    #expect(await h.events.values.filter { $0 == "normalize" || $0 == "travel" || $0 == "execute" }.isEmpty)
    #expect(await h.evidence.archive.attempts.count == 1)
    #expect(await h.evidence.archive.records.count == 1)
    let record = try #require(await h.evidence.archive.records.first)
    #expect(record.executionFrontiers.commandedStrokeCount == 0)
    let unstaged = DrawingRunEvidenceStore(fileURL: h.destination.root.appendingPathComponent("unstaged-append.json"))
    do { _ = try await unstaged.append(record); Issue.record("Terminal append staged a job without canonical stage") } catch {}
    await h.destination.close()
  }

  @Test("An uncertain raw commit acknowledgement enters real Run/service reconciliation with zero first effects")
  func uncertainAcknowledgementNeverDispatches() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, uncertainStageAcknowledgement: true)
    let ready = await h.runtime.synchronize(environment: .live)
    let ack = await h.runtime.submit(.init(projection: ready.projection, intent: .start))
    #expect(ack.disposition == .applied)
    let state = try await issuanceSettled(h.runtime)
    if case .intentPublicationIncomplete = state.evidencePersistence {} else { Issue.record("Uncertain commit recovered dispatch permission") }
    #expect(state.activeRunID == nil && state.terminal == nil)
    let intent = try #require(await h.evidence.archive.attempts.first?.intent)
    let binding = try #require(intent.issuance)
    try await h.destination.service.recoverPendingJobs()
    guard case .decision(let reconciled) = try await h.destination.service.handle(.submit(try #require(h.destination.lastKey), try #require(h.destination.lastTicket))) else { Issue.record("Uncertain commit lost its job"); return }
    #expect(reconciled.phase == .reconciling && reconciled.reason == nil)
    #expect(try ExchangeJobReceipt(originalJSON: reconciled.receipt).issuance == binding.issuance)
    #expect(await h.evidence.archive.attempts.map(\.intent) == [intent])
    #expect(await h.evidence.archive.records.isEmpty)
    #expect(await h.events.values == ["stage-intent"])
    #expect(await h.interpreter.planRequests.isEmpty)
    await h.destination.close()
  }

  @Test("Terminal handoff and no-ink retry wait for the original retained settlement and failed job-link publication", arguments: [false, true])
  func handoffWaitsForJobSettlement(_ failure: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let gate = DrawingRunHoldGate()
    h.destination.publicationProbe.settlementGate = gate
    h.destination.publicationProbe.settlementFailures = failure ? 1 : 0
    let ready = await h.runtime.synchronize(environment: .live)
    #expect(await h.runtime.submit(.init(projection: ready.projection, intent: .start)).disposition == .applied)
    await gate.waitUntilHeld()
    let held = await h.runtime.currentSnapshot(environment: .live)
    let terminal = try #require(held.terminal)
    #expect(held.ownsWorkflow && terminal.record.allowsNoInkConfirmation)
    let restored = await h.runtime.restoreNoRedrawTruth(from: DrawingRunEvidenceArchive(), paper: fixture.paper, environment: .live)
    #expect(restored.noRedraw == held.noRedraw && restored.terminal == held.terminal)
    for intent in [PlotterDrawingRunIntent.beginNewRun(terminal.runID), .confirmNoInkAndPrepareRetry(terminal.runID)] {
      let current = await h.runtime.currentSnapshot(environment: .live)
      let refused = await h.runtime.submit(.init(projection: current.projection, intent: intent))
      if case .refused(let reason) = refused.disposition { #expect(reason.reason == .activeRunOwnsWorkflow) }
      else { Issue.record("Retained settlement lost its terminal to a handoff") }
      #expect(refused.snapshot.terminal == terminal)
    }
    await gate.release()
    let settled = try await issuanceSettled(h.runtime)
    if failure {
      #expect(settled.jobPublicationRecoveryCapabilityID != nil)
      let refused = await h.runtime.submit(.init(projection: settled.projection, intent: .beginNewRun(terminal.runID)))
      if case .refused(let reason) = refused.disposition { #expect(reason.reason == .evidencePublicationInProgress) }
      else { Issue.record("Unpublished job link allowed handoff") }
      try await h.destination.service.recoverPendingJobs()
    }
    let complete = await h.runtime.currentSnapshot(environment: .live)
    #expect(complete.jobPublicationRecoveryCapabilityID == nil)
    #expect(await h.runtime.submit(.init(projection: complete.projection, intent: .beginNewRun(terminal.runID))).disposition == .applied)
    #expect(await h.interpreter.planRequests.count == 1)
    await h.destination.close()
  }

  @Test("A late lower admission after Stop is retained and joined without a second dispatch")
  func lateLowerHandle() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let admission = DrawingRunHoldGate(), plan = DrawingRunPlanGate()
    let h = await drawingRunHarness(fixture: fixture, planGate: plan, releasePlanOnStop: false)
    await h.interpreter.holdNextPlanAdmission(at: admission)
    let ready = await h.runtime.synchronize(environment: .live)
    let ack = await h.runtime.submit(.init(projection: ready.projection, intent: .start))
    #expect(ack.disposition == .applied)
    await admission.waitUntilHeld(); await plan.waitUntilStarted()
    let active = await h.runtime.currentSnapshot(environment: .live)
    let stop = Task { await h.runtime.submit(.init(projection: active.projection, intent: .stop(try #require(active.stopCapabilityID)))) }
    await Task.yield()
    #expect((await h.runtime.currentSnapshot(environment: .live)).ownsWorkflow)
    await admission.release(); await plan.release(.cancelled)
    _ = try await stop.value
    _ = try await issuanceSettled(h.runtime)
    #expect(await h.interpreter.planRequests.count == 1)
    #expect(await h.evidence.archive.records.count == 1)
    #expect(await h.interpreter.stopIntents.count >= 1)
    await h.destination.close()
  }
}
