import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Drawing reviewer deletion", .serialized)
@MainActor
struct DrawingReviewDeletionTests {
  @Test("Deleting an ordinary result keeps terminal, paper, no-redraw and shared media intact")
  func deletionDoesNotChangeLiveAuthority() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    do {
      try await f.submit(.fitInDrawableRegion)
      try await f.submit(.assertPaperCoverage)
      try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      await f.planGate.release(.possibleInk)
      let draw = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      #expect(await app.submitPlotterUIRequest(draw) == .accepted(requestID: draw.id))
      let terminal = try #require(app.drawingRunSnapshot?.terminal)
      let record = terminal.record
      try await waitUntil { app.drawingReviewRecords.contains(record) }
      #expect(record.attemptEvidence?.intent.context.candidate == nil)
      let attempt = try #require(record.attemptEvidence)
      let paper = app.currentPaperRevisionContext
      let noRedraw = app.drawingRunSnapshot?.noRedraw
      if case .planMayContainInk = noRedraw {} else {
        Issue.record("The fixture must establish possible ink before review deletion")
      }
      let plan = app.drawingDraftSnapshot.plan
      let coverage = app.drawingDraftSnapshot.paperCoverageObservation
      let feeds = await f.machine.requestedFeeds
      let penCommands = await f.machine.requestedPenCommands
      let originals = try await app.physicalAttemptImages(record)
      #expect(!originals.isEmpty)

      let preDeletionArchive = app.drawingEvidenceArchive
      try await app.deleteDrawingReview(recordID: record.recordID)
      // An already-started load may finish after the delete operation.
      app.installDrawingEvidenceArchive(preDeletionArchive)
      #expect(!app.drawingReviewRecords.contains(record))
      #expect(!app.drawingDraftExternalFacts.coverageRecords.contains(record))
      #expect(app.drawingRunSnapshot?.terminal == terminal)
      #expect(app.drawingRunSnapshot?.noRedraw == noRedraw)
      #expect(app.currentPaperRevisionContext == paper)
      #expect(app.drawingDraftSnapshot.plan == plan)
      #expect(app.drawingDraftSnapshot.paperCoverageObservation == coverage)
      #expect(await f.machine.requestedFeeds == feeds)
      #expect(await f.machine.requestedPenCommands == penCommands)
      await #expect(throws: DrawingRunEvidenceError.invalidAttemptContext) {
        try await app.physicalAttemptImages(record)
      }
      guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
        Issue.record("Review deletion must preserve a readable archive")
        await app.shutdown(); return
      }
      #expect(archive.records.contains(record))
      #expect(!archive.reviewRecords.contains(record))
      #expect(archive.attempts.first { $0.intent.runID == record.runID }?.inkDispatchPossible == true)
      for reference in attempt.baselines + attempt.terminalFrames {
        let frame = try await f.stores.evidenceStore.readMedia(reference)
        #expect(ExactFrameProvenance(frame: frame) == reference.frame)
      }
      // Startup restoration reads raw execution facts, even after review deletion.
      let restored = await f.runRuntime.restoreNoRedrawTruth(from: archive, paper: paper, environment: .live)
      #expect(restored.noRedraw == noRedraw)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
}
