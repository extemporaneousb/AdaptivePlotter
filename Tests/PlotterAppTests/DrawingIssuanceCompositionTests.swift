import Foundation
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing
@testable import PlotterRuntime
@testable import PlotterApp

@Suite("Drawing issuance actual native composition", .serialized)
@MainActor struct DrawingIssuanceCompositionTests {
  @Test("Original public-sink Plot binds source-free and Photo closure before effects and replays lost ACK", arguments: [false, true])
  func nativeOriginalRequest(_ photo: Bool) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application, library = app.receivedDrawings.sketches.library
    var expected: DrawingRef?
    var expectedInput: ImageInputRef?
    var expectedParent: DrawingRef?
    if photo {
      let pixels = try DrawingImageAsset.gray8(Data([0, 64, 128, 255]), width: 2, height: 2)
      let source = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels, width: 2, height: 2,
        acquired: .unknown(provenance: "synthetic issuance fixture"), imported: .unknown(provenance: "synthetic issuance fixture"), captureFactsJSON: Data("{}".utf8))
      let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: source, raster: pixels,
        width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
        inputToField: ExchangeTransform([1,0,0,0,1,0,0,0,1]), mask: .none,
        operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8))],
        preparation: .init(id: "example.issuance-input", version: "1", recordJSON: Data("{}".utf8)))
      try await library.commitRecords([], closure: .init(input: input))
      expectedInput = input.reference
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      let parent = try Drawing(program: program, input: .present(input.reference), parent: .none,
        producer: .init(id: "example.issuance-parent", version: "1", recordJSON: Data("{}".utf8)))
      expectedParent = try await library.retain(parent, reason: "issuance fixture parent").reference
      let drawing = try Drawing(program: program, input: .present(input.reference), parent: .present(try #require(expectedParent)),
        producer: .init(id: "example.issuance-child", version: "1", recordJSON: Data("{}".utf8)))
      let retained = try await app.receivedDrawings.sketches.retain(drawing, reason: "issuance fixture")
      expected = retained.reference
      #expect(await app.projectDrawing(retained) == nil)
    }
    try await f.submit(.fitInDrawableRegion)
    try await f.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let reviewed = try #require(app.drawingDraftSnapshot.plan)
    guard case .loaded(let initialArchive) = await f.stores.evidenceStore.load() else { Issue.record("Missing retained Learning evidence"); await app.shutdown(); return }
    let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    let original = Task { await app.submitPlotterUIRequest(request) }
    await f.planGate.waitUntilStarted()
    #expect(await original.value == .accepted(requestID: request.id))
    guard case .loaded(let staged) = await f.stores.evidenceStore.load() else { Issue.record("No raw staged intent"); await app.shutdown(); return }
    let intent = try #require(staged.attempts.first?.intent), binding = try #require(intent.issuance)
    #expect(intent.requestID == request.id.rawValue && binding.key.request == request.id.rawValue)
    #expect(intent.plan == reviewed && binding.physicalPlanID == reviewed.revisionID)
    if let expected { #expect(binding.drawing == expected) }
    let authored = try await library.drawing(binding.drawing)
    #expect(authored.reference == binding.drawing && authored.units.nominalPenWidthMM == nil)
    if let expectedInput { #expect(authored.input == .present(expectedInput)); #expect(authored.parent == .present(try #require(expectedParent))) }
    guard case .decision(let accepted) = try await app.drawingDestination.handle(.status(.request(binding.key))) else { Issue.record("No accepted link before lower Run"); await app.shutdown(); return }
    #expect(accepted.reason == nil)
    #expect(try ExchangeJobReceipt(originalJSON: accepted.receipt).issuance == binding.issuance)
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    #expect(try await app.drawingDestination.handle(.exportResult(accepted.job.handle)) == .refused(.preparationUnavailable))
    await f.planGate.release(.completed)
    let terminal = try await issuanceSettled(f.runRuntime)
    #expect(terminal.terminal?.runID == intent.runID)
    #expect(terminal.terminal?.record.attemptEvidence?.intent == intent)
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    guard case .loaded(let sealed) = await f.stores.evidenceStore.load() else { Issue.record("No terminal raw archive"); await app.shutdown(); return }
    #expect(sealed.attempts.count == initialArchive.attempts.count + 1)
    let record = try #require(terminal.terminal?.record)
    #expect(sealed.records == initialArchive.records + [record])
    #expect(sealed.records.filter { $0.runID == intent.runID } == [record])
    #expect(try await app.drawingDestination.handle(.status(.request(binding.key))) == .decision(.init(key: accepted.key,
      requestDigest: accepted.requestDigest, job: accepted.job, ticket: accepted.ticket, reason: accepted.reason, receipt: accepted.receipt, phase: .settled)))
    await app.shutdown()
  }

  @Test("Unpublished terminal job metadata blocks paper/reset before durable mutation and recovers without dispatch", arguments: [false, true])
  func jobPublicationBlocksPaperMutation(_ afterCommit: Bool) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application, library = app.receivedDrawings.sketches.library
    try await f.submit(.fitInDrawableRegion); try await f.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    try await library.failNextSettledDrawingJobCommit(afterCommit: afterCommit)
    await f.planGate.release(.cancelled)
    let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    let failed = try await issuanceSettled(f.runRuntime)
    let recovery = try #require(failed.jobPublicationRecoveryCapabilityID)
    try await waitUntil { app.drawingRunSnapshot?.jobPublicationRecoveryCapabilityID == recovery }
    let terminal = try #require(failed.terminal)
    let paper = app.currentPaperRevisionContext
    let checkpoint = f.stores.checkpointStore.load()
    let effects = await f.machine.requestedDrawingStrokes
    #expect(app.paperManagementUnavailableReason?.contains("job publication") == true)
    #expect(app.artifactResetUnavailableReason?.contains("job publication") == true)
    await app.recordNewPaperSheetOnCurrentPlane()
    #expect(app.currentPaperRevisionContext == paper)
    #expect(app.drawingRunSnapshot?.terminal == terminal)
    #expect(app.drawingRunSnapshot?.noRedraw == failed.noRedraw)
    guard case .loaded(let before) = checkpoint, case .loaded(let after) = f.stores.checkpointStore.load() else {
      Issue.record("Rejected paper mutation changed the accepted checkpoint"); await app.shutdown(); return
    }
    #expect(after == before)
    #expect(await f.machine.requestedDrawingStrokes == effects)
    await library.clearSettledDrawingJobFault()
    try await app.drawingDestination.recoverPendingJobs()
    try await waitUntil { app.drawingRunSnapshot?.jobPublicationRecoveryCapabilityID == nil }
    #expect(app.currentPaperRevisionContext == paper)
    #expect(app.paperManagementUnavailableReason == nil)
    #expect(await f.machine.requestedDrawingStrokes == effects)
    guard case .loaded(let archive) = await f.stores.evidenceStore.load() else { Issue.record("Job recovery lost raw evidence"); await app.shutdown(); return }
    #expect(archive.records.contains(terminal.record))
    await app.shutdown()
  }

  @Test("A stale original public projection refuses rather than refreshing the reviewed plan")
  func staleOriginalProjection() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    try await f.submit(.fitInDrawableRegion); try await f.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let original = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    try await f.submit(.setRotationDegrees(5))
    let before = await f.machine.requestedPenCommands
    if case .refused = await app.submitPlotterUIRequest(original) {} else { Issue.record("Stale projection was replaced with current plan") }
    #expect(await f.planGate.request == nil)
    #expect(await f.machine.requestedPenCommands == before)
    #expect(try await app.receivedDrawings.sketches.library.records(kind: "adaptiveplotter.destination.job").isEmpty)
    await app.shutdown()
  }
}

private extension DrawingLibrary {
  func failNextSettledDrawingJobCommit(afterCommit: Bool) throws {
    let catalog = try commonCatalog()
    var armed = true
    catalog.injectFault = { boundary in
      guard armed, boundary == (afterCommit ? .afterSQLCommit : .beforeSQLCommit) else { return }
      for row in try catalog.database.rows("SELECT payload FROM domain_record WHERE kind='adaptiveplotter.destination.job'") {
        guard let json = row[0],
          let record = try? JSONDecoder().decode(DrawingLibraryRecord.self, from: Data(json.utf8)),
          let decision = try? JSONDecoder().decode(DrawingJobDecision.self, from: record.payload), decision.phase == .settled else { continue }
        armed = false
        throw DrawingRunEvidenceProbeError.appendFailed
      }
    }
  }
  func clearSettledDrawingJobFault() { cachedExchangeCatalog?.injectFault = nil }
}
