import Foundation
@testable import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing
@testable import PlotterRuntime
@testable import PlotterApp

@Suite("Drawing issuance durable service boundaries", .serialized)
@MainActor struct DrawingIssuanceServiceTests {
  @Test("Duplicate pending Submit, Status and Cancel remain responsive before raw stage")
  func pendingDuplicateAndCancel() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture), gate = DrawingRunHoldGate()
    h.destination.publicationProbe.proposalGate = gate
    let ready = await h.runtime.synchronize(environment: .live)
    let request = PlotterDrawingRunSubmission(projection: ready.projection, intent: .start)
    let start = Task { await h.runtime.submit(request) }
    await gate.waitUntilHeld()
    let key = try #require(h.destination.lastKey), ticket = try #require(h.destination.lastTicket)
    guard case .pending(let original) = try await h.destination.service.handle(.status(.request(key))) else { Issue.record("No pending metadata"); return }
    #expect(await h.runtime.lookupIssuance(original.binding) == .unknown)
    #expect(try await h.destination.service.handle(.submit(key, ticket)) == .pending(original))
    #expect(try await h.destination.service.handle(.submit(key, DrawingPreparedTicket(facts: ticket.facts))) == .refused(.requestConflict))
    let otherNamespace = DrawingRequestKey(namespace: UUID(), request: key.request)
    guard case .decision(let other) = try await h.destination.service.handle(.submit(otherNamespace, ticket)) else { Issue.record("Independent namespace collided"); return }
    #expect(other.reason == .nativePlotRequired && other.job.handle != original.binding.job)
    #expect(try await h.destination.service.handle(.status(.request(key))) == .pending(original))
    let diagnostics = DrawingLibraryDiagnostics.shared.snapshot()
    _ = try await h.destination.service.handle(.status(.job(original.binding.job)))
    let after = DrawingLibraryDiagnostics.shared.snapshot()
    #expect(after["storageObjectReads", default: 0] == diagnostics["storageObjectReads", default: 0])
    guard case .cancellation(let acknowledged, let settled) = try await h.destination.service.handle(.cancel(.request(key))) else { Issue.record("No cancellation ACK"); return }
    #expect(acknowledged && !settled)
    await gate.release(); _ = await start.value
    let terminal = try await issuanceSettled(h.runtime)
    #expect(terminal.activeRunID == nil && terminal.terminal == nil)
    #expect(await h.evidence.archive.attempts.isEmpty)
    #expect(await h.events.values.isEmpty)
    guard case .decision(let refusal) = try await h.destination.service.handle(.submit(key, ticket)) else { Issue.record("No durable cancellation refusal"); return }
    #expect(refusal.reason == .cancelled)
    #expect(try ExchangeJobReceipt(originalJSON: refusal.receipt).issuance == nil)
    await h.destination.close()
  }

  @Test("Lost admission ACK retries the original job while a held Run remains cancellable")
  func lostACKAndResponsiveRun() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load(), plan = DrawingRunPlanGate()
    let h = await drawingRunHarness(fixture: fixture, planGate: plan)
    let ready = await h.runtime.synchronize(environment: .live)
    let request = PlotterDrawingRunSubmission(projection: ready.projection, intent: .start)
    let ack = await h.runtime.submit(request)
    #expect(ack.disposition == .applied)
    await plan.waitUntilStarted()
    let key = try #require(h.destination.lastKey), ticket = try #require(h.destination.lastTicket)
    guard case .decision(let accepted) = try await h.destination.service.handle(.status(.request(key))) else { Issue.record("No accepted link before Run"); return }
    #expect(accepted.reason == nil)
    #expect(await h.runtime.submit(request).disposition == ack.disposition)
    for _ in 0..<3 {
      guard case .decision(let replay) = try await h.destination.service.handle(.submit(key, ticket)) else { Issue.record("Lost ACK replay missing"); return }
      #expect(replay.job == accepted.job && replay.receipt == accepted.receipt)
    }
    #expect(try await h.destination.service.handle(.exportResult(accepted.job.handle)) == .refused(.preparationUnavailable))
    let refusalKey = DrawingRequestKey(namespace: UUID())
    guard case .decision(let refusal) = try await h.destination.service.handle(.submit(refusalKey, ticket)) else { Issue.record("No genuine refusal to export"); return }
    let exportGate = DestinationArtifactGate()
    DrawingDestinationArtifactObservation.shared.install { job, boundary in
      if job == refusal.job.handle, boundary == .beforePublication { exportGate.hold() }
    }
    defer { exportGate.release(); DrawingDestinationArtifactObservation.shared.install(nil) }
    let export = Task { try await h.destination.service.handle(.exportResult(refusal.job.handle)) }
    try await exportGate.waitUntilEntered()
    #expect(!exportGate.snapshot().mainThread)
    guard case .decision(let whileExporting) = try await h.destination.service.handle(.status(.request(key))) else { Issue.record("Export blocked Status"); return }
    #expect(whileExporting.receipt == accepted.receipt)
    guard case .cancellation(let acknowledged, _) = try await h.destination.service.handle(.cancel(.job(accepted.job.handle))) else { Issue.record("No cancel ACK"); return }
    #expect(acknowledged)
    _ = try await issuanceSettled(h.runtime)
    exportGate.release()
    guard case .result(let artifact) = try await export.value else { Issue.record("Held refusal export did not finish"); return }
    #expect(FileManager.default.fileExists(atPath: artifact.path))
    guard case .decision(let terminal) = try await h.destination.service.handle(.status(.request(key))) else { Issue.record("No settled job"); return }
    #expect(terminal.phase == .settled && terminal.receipt == accepted.receipt)
    #expect(await h.interpreter.planRequests.count == 1)
    #expect(await h.evidence.archive.attempts.count == 1)
    await h.destination.close()
  }

  @Test("Lost accepted-link and terminal-link publication recover through actual retry/startup without another dispatch", arguments: [false, true])
  func publicationRetry(_ terminalCut: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture)
    if terminalCut { h.destination.publicationProbe.settlementFailures = 1 }
    else { h.destination.publicationProbe.linkFailures = 1 }
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.runtime.submit(.init(projection: ready.projection, intent: .start))
    // Wait until the live original continuation has released pending ownership
    // before exercising a fresh service/runtime restart.
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while (await h.runtime.currentSnapshot(environment: .live)).pendingRequestID != nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require((await h.runtime.currentSnapshot(environment: .live)).pendingRequestID == nil)
    try #require(await h.evidence.archive.records.count == 1)
    let key = try #require(h.destination.lastKey), ticket = try #require(h.destination.lastTicket)
    let original = try #require(await h.evidence.archive.attempts.first?.intent)
    let before = await h.interpreter.planRequests.count
    _ = await h.runtime.beginShutdown(environment: .live)
    await h.destination.service.close(); await h.destination.collection.shutdown(); await h.destination.library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: h.destination.root.appendingPathComponent("library"), payloadValidators: DrawingDestinationResult.payloadValidators)
    let collection = PortraitSketchCollection(library: reopened)
    let port = DrawingRunEvidencePort(store: DrawingRunEvidenceStore(fileURL: h.evidence.archiveURL))
    let events = DrawingRunEventProbe()
    let interpreter = DrawingRunInterpreterProbe(ready: drawingRunReadySnapshot(position: fixture.finalPosition), events: events)
    let facts = ReopenedIssuanceFacts(facts: fixture.facts(), library: reopened, collection: collection, evidence: port)
    let runtime = PlotterDrawingRunRuntime(facts: facts, interpreter: interpreter, camera: h.camera, vision: h.vision, evidence: port)
    let control = DrawingRunServiceControl(); control.runtime = runtime
    let restarted = DrawingDestinationService(library: reopened, returnDirectory: h.destination.root.appendingPathComponent("results"),
      prepare: { _, _, _ in nil }, current: { $0 }, control: control)
    try await restarted.recoverPendingJobs()
    guard case .decision(let recovered) = try await restarted.handle(.submit(key, ticket)) else { Issue.record("No recovered exact job"); return }
    #expect(recovered.phase == .settled && recovered.reason == nil)
    #expect(try ExchangeJobReceipt(originalJSON: recovered.receipt).issuance == original.issuance?.issuance)
    #expect(await h.interpreter.planRequests.count == before)
    #expect(before == (terminalCut ? 1 : 0))
    #expect(await h.evidence.archive.attempts.map(\.intent) == [original])
    #expect(await events.values.isEmpty)
    await restarted.close(); _ = await runtime.beginShutdown(environment: .live)
    await collection.shutdown(); await reopened.closeLibrary()
    try? FileManager.default.removeItem(at: h.destination.root)
  }

  @Test("Library pending commit cuts recover exact original identity with zero automatic reissue", arguments: [false, true])
  func pendingCommitCut(_ afterCommit: Bool) async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let h = await drawingRunHarness(fixture: fixture)
    try await h.destination.library.installIssuanceCommitFault(afterCommit: afterCommit)
    let ready = await h.runtime.synchronize(environment: .live)
    _ = await h.runtime.submit(.init(projection: ready.projection, intent: .start))
    await h.destination.library.clearIssuanceCommitFault()
    _ = try await issuanceSettled(h.runtime)
    let key = try #require(h.destination.lastKey), ticket = try #require(h.destination.lastTicket)
    #expect(await h.evidence.archive.attempts.isEmpty)
    #expect(await h.events.values.isEmpty)
    try await h.destination.service.recoverPendingJobs()
    // The Library journal is durable before SQL publication. Its normal
    // recovery finishes both cuts using the original pending request.
    guard case .decision(let refusal) = try await h.destination.service.handle(.submit(key, ticket)) else { Issue.record("Journaled pending did not reconcile"); return }
    #expect(refusal.key == key && refusal.ticket == ticket)
    #expect(refusal.reason == .interrupted)
    #expect(try ExchangeJobReceipt(originalJSON: refusal.receipt).issuance == nil)
    #expect(try await h.destination.service.handle(.status(.request(key))) == .decision(refusal))
    await h.destination.close()
  }
}

private extension DrawingLibrary {
  func installIssuanceCommitFault(afterCommit: Bool) throws {
    let catalog = try commonCatalog()
    var armed = true
    catalog.injectFault = { boundary in
      guard armed, boundary == (afterCommit ? .afterSQLCommit : .beforeSQLCommit),
        (Int(try catalog.database.scalar("SELECT COUNT(*) FROM domain_record WHERE kind='adaptiveplotter.destination.job-pending'") ?? "0") ?? 0) > 0 else { return }
      armed = false
      throw DrawingRunEvidenceProbeError.stageFailed
    }
  }
  func clearIssuanceCommitFault() { cachedExchangeCatalog?.injectFault = nil }
}

private struct ReopenedIssuanceFacts: PlotterDrawingRunFactSource {
  let facts: PlotterDrawingRunExternalFacts
  let library: DrawingLibrary
  let collection: PortraitSketchCollection
  let evidence: DrawingRunEvidencePort
  func drawingRunFacts(for _: PlotterEnvironment) async -> PlotterDrawingRunExternalFacts { facts }
  func retainCandidateForAttempt(_ intent: DrawingRunIntent) async throws {
    guard let binding = intent.issuance,
      let staged = try await evidence.lookupIssuance(binding), staged.intent == intent else { throw DrawingRunEvidenceError.invalidAttemptContext }
    let drawing = try await library.drawing(binding.drawing)
    try await collection.bindDrawingAttempt(intent, drawing: drawing, archive: staged.archive, archiveURL: evidence.archiveURL)
  }
}
