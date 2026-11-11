import AppKit
import Foundation
import PlotterModel
import PlotterRuntime
import PlotterEpisodeRuntime
import PortraitStudioUI
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Current Drawing reviewer hosted layout", .serialized)
@MainActor
struct DrawingReviewerLayoutTests {
  @Test("Deleted and dismissed terminal review rows never reappear as possible-ink incomplete attempts")
  func hiddenTerminalDoesNotBecomeIncomplete() async throws {
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let plan = try fixture.makePlan(catalogItemID: .circle)
    let harness = await drawingRunHarness(fixture: fixture, facts: fixture.facts(plan: plan))
    let ready = await harness.runtime.synchronize(environment: .live)
    let result = await harness.submit(.init(projection: ready.projection, intent: .start))
    let terminal = try #require(result.snapshot.terminal)
    let archive = await harness.evidence.archive
    #expect(DrawingReviewRawRows.resolve(run: terminal.runID, archive: archive).records.count == 1)
    for hidden in [try archive.deletingReview(recordID: terminal.record.recordID),
                   try archive.dismissingAttemptReview(runID: terminal.runID)] {
      let rows = DrawingReviewRawRows.resolve(run: terminal.runID, archive: hidden)
      #expect(rows.records.isEmpty && rows.incomplete == nil)
      #expect(hidden.records == archive.records && hidden.attempts == archive.attempts)
      #expect(hidden.confirmedNoInkRunIDs == archive.confirmedNoInkRunIDs)
      #expect(hidden.revision == archive.revision)
      #expect(DrawingReviewRefreshKey(hidden) != DrawingReviewRefreshKey(archive))
    }
    // A genuine nonterminal possible-ink attempt still remains reviewable.
    let unsettled = try DrawingRunEvidenceArchive(archiveID: archive.archiveID, revision: 0,
      records: [], attempts: archive.attempts)
    let liveRows = DrawingReviewRawRows.resolve(run: terminal.runID, archive: unsettled)
    #expect(liveRows.records.isEmpty && liveRows.incomplete?.inkDispatchPossible == true)
    let possibleInk = try #require(liveRows.incomplete)
    let staged = try DrawingRunEvidenceArchive(archiveID: archive.archiveID, revision: 0, records: [],
      attempts: [.init(intent: possibleInk.intent, baselines: possibleInk.baselines, inkDispatchPossible: false)])
    #expect(staged.revision == unsettled.revision)
    #expect(DrawingReviewRefreshKey(staged) != DrawingReviewRefreshKey(unsettled))
    #expect(await harness.interpreter.planRequests.count == 1)
  }
  @Test("Empty and source-free current-format reviewer fit an offscreen owned window")
  func currentReviewer() async throws {
    _ = NSApplication.shared
    let studio = DrawingFirstTestStorage.studio()
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: studio)
    defer { fixture.stores.remove() }
    for populated in [false, true] {
        let program = try DrawingProgramCatalog.program(for: .line, style: portraitTestStyle())
        let value = try drawingTestValue(program: program)
        let selected = populated ? try await studio.sketches.retain(value, reason: "save") : value
      let size = NSSize(width: 1000, height: 700)
      let host = NSHostingController(rootView: DrawingReviewerView(application: fixture.application, drawing: selected)
        .frame(width: size.width, height: size.height))
      let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false; window.contentViewController = host
      window.orderFront(nil)
      host.view.layoutSubtreeIfNeeded()
      #expect(host.view.fittingSize.width <= size.width + 1)
      #expect(host.view.fittingSize.height <= size.height + 1)
      window.orderOut(nil); window.contentViewController = nil; window.close()
    }
    await fixture.application.shutdown(); await studio.library.closeLibrary()
  }
}
