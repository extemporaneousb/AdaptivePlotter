import DrawingLibrary
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing
@testable import PlotterApp

private struct UnsupportedDrawingCarrier {
  let bag: DrawingExchangeCarrierTestBag
  let reference: DrawingRef
  let recordBytes: Data
  let programBytes: Data
  let recordPath: String
  let programPath: String
  init(program: DrawingProgram) throws {
    let value = try Drawing(program: program, input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.capability-admission", version: "1", recordJSON: Data("{}".utf8)))
    let frozen = try DrawingExchangeCodec.freeze(value, identity: .init(issuer: UUID()), createdAt: Date())
    var record = try #require(JSONSerialization.jsonObject(with: frozen.originalJSON) as? [String: Any])
    record["requiredFeatures"] = ["example.unsupported-drawing-semantics/1"]
    recordBytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    reference = DrawingRef(issuer: frozen.reference.issuer, revision: frozen.reference.revision, digest: .hash(recordBytes))
    programBytes = frozen.originalProgramJSON
    let programAsset = try ExchangeAsset(bytes: programBytes, mediaType: "application/json", encoding: DrawingExchangeCodec.strokeProfile)
    let receiptAsset = try ExchangeAsset(bytes: value.producer.originalJSON, mediaType: "application/json", encoding: "utf8-json")
    let encoder = DrawingArtifactCoding.encoder()
    let index: [String: Any] = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](),
      "kind": "drawing", "roots": try JSONSerialization.jsonObject(with: encoder.encode([reference])),
      "includedAsOf": "2026-11-08T00:00:00Z", "attempts": [String](), "assessments": [String](),
      "assets": try JSONSerialization.jsonObject(with: encoder.encode([ExchangeAssetDescriptor(asset: programAsset), ExchangeAssetDescriptor(asset: receiptAsset)]))]
    recordPath = "data/drawings/" + reference.issuer.uuidString.lowercased() + "/" + reference.revision.uuidString.lowercased() + "/drawing.json"
    programPath = "data/objects/sha256/" + programAsset.object.description
    bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": JSONSerialization.data(withJSONObject: index, options: [.sortedKeys]),
      recordPath: recordBytes, programPath: programBytes,
      "data/objects/sha256/" + receiptAsset.object.description: value.producer.originalJSON])
  }
}

@Suite("Per-Drawing capability admission at App boundaries", .serialized)
@MainActor
struct DrawingCapabilityAdmissionTests {
  @Test("Unknown Drawing requirements preserve bytes and browsing but refuse preview and handoff without changing selection")
  func importExportAndHandoff() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, library = app.receivedDrawings.library
    do {
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      let prior = try drawingTestValue(program: program)
      #expect(await app.projectDrawing(prior) == nil)
      let carrier = try UnsupportedDrawingCarrier(program: program)
      defer { carrier.bag.dispose() }
      #expect(try await library.importDrawings(from: carrier.bag.source) == [carrier.reference])
      let unsupported = try await library.drawing(carrier.reference)
      #expect(unsupported.reference == carrier.reference && unsupported.program == program)
      #expect(unsupported.capabilities.supported.isEmpty)
      #expect(try await library.drawings().entries.contains { $0.reference == carrier.reference })
      #expect(throws: DrawingExchangeError.unsupportedFeature("example.unsupported-drawing-semantics/1")) {
        try unsupported.capabilities.require(.preview)
      }
      #expect(unsupported.executionReference(for: program) == nil)
      let before = app.drawingDraftSnapshot
      let priorRef = app.receivedDrawings.projectedDrawing?.reference
      let priorSelected = app.receivedDrawings.sketches.selected?.reference
      let references = try await library.drawings().entries.map(\.reference)
      #expect(await app.projectDrawing(unsupported) != nil)
      #expect(app.drawingDraftSnapshot.projection.draftRevision == before.projection.draftRevision)
      #expect(app.drawingDraftSnapshot.authoredProgram == before.authoredProgram && app.drawingDraftSnapshot.plan == before.plan)
      #expect(app.receivedDrawings.projectedDrawing?.reference == priorRef)
      #expect(app.receivedDrawings.sketches.selected?.reference == priorSelected)
      #expect(try await library.drawings().entries.map(\.reference) == references)
      #expect(await fixture.planGate.request == nil)
      let exported = carrier.bag.root.appendingPathComponent("preserved")
      try await library.exportDrawing(carrier.reference, to: exported)
      let staged = try DrawingExchangeCarrier.stageDirectory(exported, stagingParent: carrier.bag.root)
      #expect(try staged.files.record(at: carrier.recordPath) == carrier.recordBytes)
      #expect(try staged.files.record(at: carrier.programPath) == carrier.programBytes)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("A known unsupported authored value cannot fall back to a fresh source-free drawing at Run", arguments: [false, true])
  func runCannotStripRequirements(border: Bool) async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application, library = app.receivedDrawings.library
    do {
      try await fixture.submit(.showTarget)
      if border { try await fixture.submit(.setDrawBorder(true)) }
      try await fixture.submit(.assertPaperCoverage)
      try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      let program = try #require(app.drawingDraftSnapshot.authoredProgram)
      #expect(program.source.kind != "portrait", "Exercise the source-free fallback that could strip required semantics.")
      let carrier = try UnsupportedDrawingCarrier(program: program)
      defer { carrier.bag.dispose() }
      _ = try await library.importDrawings(from: carrier.bag.source)
      let unsupported = try await library.drawing(carrier.reference)
      // Save legitimately preserves unsupported bytes. It also supplies an
      // existing public path to a known denied projection, without a test setter.
      _ = try await app.receivedDrawings.receiveForInspection(unsupported, isStillCurrent: { true })
      #expect(app.receivedDrawings.projectedDrawing?.reference == carrier.reference)
      #expect(app.receivedDrawings.projectedDrawing?.capabilities.supported.isEmpty == true)
      let execution = try #require(app.drawingDraftSnapshot.program)
      if border { #expect(execution != program) }
      #expect(app.authoredDrawing(for: execution) == nil)
      let references = try await library.drawings().entries.map(\.reference)
      let bindings = try DrawingArtifactCoding.encoder().encode(await library.records(kind: PortraitDrawingAttemptBinding.kind))
      let before = app.drawingDraftSnapshot
      let archive = app.drawingEvidenceArchive
      let penCommands = await fixture.machine.requestedPenCommands
      let strokes = await fixture.machine.requestedDrawingStrokes
      let run = try #require(app.drawingRunSnapshot)
      let submission = PlotterDrawingRunSubmission(projection: run.projection, intent: .start)
      let result = try #require(await app.submitDrawingRun(submission))
      guard case .refused(let refusal) = result.disposition else { Issue.record("Unsupported Drawing was admitted"); await app.shutdown(); return }
      #expect(refusal.requestID == submission.requestID)
      #expect(refusal.owner.rawValue == "PlotterDrawingRunRuntime")
      #expect(refusal.detail == "This drawing is not admitted for plotting.")
      #expect(result.snapshot.planIdentity == run.planIdentity)
      #expect(app.drawingDraftSnapshot.projection.draftRevision == before.projection.draftRevision)
      #expect(app.drawingDraftSnapshot.plan == before.plan)
      #expect(app.receivedDrawings.projectedDrawing?.reference == carrier.reference)
      #expect(try await library.drawings().entries.map(\.reference) == references)
      #expect(try DrawingArtifactCoding.encoder().encode(await library.records(kind: PortraitDrawingAttemptBinding.kind)) == bindings)
      #expect(app.drawingEvidenceArchive == archive)
      #expect(await fixture.planGate.request == nil)
      #expect(await fixture.machine.requestedPenCommands == penCommands)
      #expect(await fixture.machine.requestedDrawingStrokes == strokes)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
}
