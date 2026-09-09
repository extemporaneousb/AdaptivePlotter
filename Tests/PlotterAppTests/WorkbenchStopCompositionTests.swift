import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing
@testable import PlotterApp

/// Software projection/owner proof. Native docking, visibility and input are
/// exercised by the signed application's native-workbench gate, not SwiftPM's
/// command-line runner, which does not run the AppKit application event loop.
@Suite("Workbench Stop projection and runtime", .serialized)
@MainActor
struct WorkbenchStopCompositionTests {
  @Test("Learning, Motion, and Drawing Stops retain exact projected authority with panels hidden")
  func globalStopsPreserveProjectedCapabilities() throws {
    for action in stopActions() {
      var layout = WorkbenchLayoutState()
      for panel in WorkbenchPanel.allCases {
        layout.move(panel, to: .bottom)
        layout.setPresented(panel, false)
      }
      let projection = stopProjection(action)
      let stops = WorkbenchStopPresentation.actions(in: projection)
      #expect(stops.count == 1)
      let selected = try #require(stops.first)
      let request = try #require(projection.request(for: selected.id))
      #expect(!layout.hasVisiblePanels)
      #expect(selected == action)
      #expect(request.intent == action.intent)
      #expect(request.uiRevision == projection.revision)
    }
  }

  @Test("typed Stop acknowledges a held Drawing Run before lower settlement and preserves exact ownership")
  func heldDrawingStopAcknowledgesBeforeSettlement() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make(releasePlanOnStop: false)
    defer { fixture.stores.remove() }
    let application = fixture.application
    var run: Task<PlotterUIRequestDisposition, Never>?
    do {
      let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
        style: .contours, strokeStyle: application.drawingStrokeStyle)
      let showProjection = application.plotterUIProjection(
        selectedItemID: application.testCurrentLearningPathItemID, manualDraft: ManualMotionDraft(),
        includesLearningPath: true, pendingDrawingProgram: program)
      let show = try #require(showProjection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
      try #require(await application.submitPlotterUIRequest(show) == .accepted(requestID: show.id))
      try await fixture.submit(.fitInDrawableRegion)
      try await fixture.submit(.assertPaperCoverage)
      try await waitUntil { application.drawingRunSnapshot?.readiness == .ready }
      let publications = await fixture.runRuntime.snapshots(environment: .live)
      let draw = try #require(application.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      let pendingRun = Task { await application.submitPlotterUIRequest(draw) }
      run = pendingRun
      try await waitUntilAsync { await fixture.planGate.request != nil }
      let admitted = try #require(await fixture.planGate.request)
      let held = try #require(application.drawingRunSnapshot)
      let heldPlan = try #require(held.planIdentity)
      let capability = try #require(held.stopCapabilityID)
      let runID = try #require(held.activeRunID)
      #expect(heldPlan.planRevisionID == admitted.plan.revisionID)
      #expect(heldPlan.planContentHash == admitted.plan.contentHash)
      // Progress-only publications legitimately reuse the run revision.
      // Exercise that producer path through the configured lower fixture.
      let progressPublications = await fixture.runRuntime.snapshots(environment: .live)
      let earlierProgress = drawingRunOutcome(.refused, request: admitted).progress
      await fixture.machine.setDrawingPlanProgress(earlierProgress)
      let beforeProgress = await fixture.runRuntime.snapshot(environment: .live)
      let progress = drawingRunOutcome(.cancelled, request: admitted).progress
      await fixture.machine.setDrawingPlanProgress(progress)
      let afterProgress = await fixture.runRuntime.snapshot(environment: .live)
      #expect(afterProgress.projection == beforeProgress.projection)
      #expect(beforeProgress.progress != afterProgress.progress)
      var progressIterator = progressPublications.makeAsyncIterator()
      var earlierPublication: PlotterDrawingRunSnapshot?
      while let value = await progressIterator.next() {
        if value.progress == earlierProgress { earlierPublication = value }
        if value.progress == progress { break }
      }
      let queuedEarlier = try #require(earlierPublication)
      #expect(queuedEarlier.projection == afterProgress.projection)
      application.installDrawingRunSnapshot(afterProgress)
      #expect(application.drawingRunSnapshot?.progress == progress)
      application.installDrawingRunSnapshot(queuedEarlier)
      // Immediate assertion: no lower poll or UI turn may repair this replay.
      #expect(application.drawingRunSnapshot?.progress == progress)
      let simulatedProgressSource = await fixture.runRuntime.snapshot(environment: .simulated)
      application.frameMode = .simulated
      application.installDrawingRunSnapshot(simulatedProgressSource)
      application.frameMode = .live
      application.installDrawingRunSnapshot(queuedEarlier)
      #expect(application.drawingRunSnapshot == simulatedProgressSource)
      application.installDrawingRunSnapshot(afterProgress)
      #expect(application.drawingRunSnapshot?.progress == progress)
      #expect(application.drawingRunSnapshot?.projection.environment == .live)
      var layout = WorkbenchLayoutState()
      layout.setPresented(.motion, false)
      layout.setPresented(.portraitStudio, false)
      let projection = application.testPlotterUIProjection().semantic
      let stops = WorkbenchStopPresentation.actions(in: projection)
      try #require(stops.count == 1)
      let stop = try #require(projection.request(for: stops[0].id))
      #expect(stop.intent == .drawingRun(.stop(capability)))
      let pen = await fixture.machine.requestedPenCommands
      let feeds = await fixture.machine.requestedFeeds
      let strokes = await fixture.machine.requestedDrawingStrokes
      let boundaries = await fixture.machine.requestedBoundaryRequests
      let started = ContinuousClock.now
      #expect(await application.submitPlotterUIRequest(stop) == .accepted(requestID: stop.id))
      #expect(started.duration(to: .now) < .milliseconds(250))
      // Software ingress acknowledgment is deliberately separate from native
      // input and from the still-held lower operation's eventual terminal.
      #expect(application.drawingRunSnapshot?.activeRunID == runID)
      #expect(application.drawingRunSnapshot?.stopCapabilityID == capability)
      #expect(application.drawingRunSnapshot?.terminal == nil)
      #expect(application.drawingRunSnapshot?.projection.runRevision != held.projection.runRevision)
      #expect(await fixture.planGate.request?.plan == admitted.plan)
      #expect(application.drawingRunSnapshot?.planIdentity == heldPlan)
      await fixture.planGate.release(.cancelled)
      #expect(await pendingRun.value == .accepted(requestID: draw.id))
      // Capture before the lower await: allowing another UI turn here could
      // conceal a queued earlier publication overwriting the returned result.
      let immediatelyPublished = try #require(application.drawingRunSnapshot)
      let lowerSettled = await fixture.runRuntime.snapshot(environment: .live)
      #expect(immediatelyPublished.projection.runRevision == lowerSettled.projection.runRevision)
      #expect(immediatelyPublished.terminal == lowerSettled.terminal)
      #expect(immediatelyPublished.evidencePersistence == lowerSettled.evidencePersistence)
      let terminal = try #require(immediatelyPublished.terminal)
      #expect(terminal.runID == runID)
      #expect(terminal.planIdentity == heldPlan)
      #expect(terminal.disposition == .cancelled)
      #expect(terminal.record.observation == .notAttempted(.executionCancelledBeforeObservation))
      #expect(await fixture.machine.requestedPenCommands == pen)
      #expect(await fixture.machine.requestedFeeds == feeds)
      #expect(await fixture.machine.requestedDrawingStrokes == strokes)
      #expect(await fixture.machine.requestedBoundaryRequests == boundaries)
      guard case .loaded(let archive) = await fixture.stores.evidenceStore.load() else {
        Issue.record("Cancelled Stop did not persist its evidence record.")
        await application.shutdown(); return
      }
      #expect(archive.records.filter { $0.recordID == terminal.record.recordID }.count == 1)
      #expect(!layout.isPresented(.motion) && !layout.isPresented(.portraitStudio))
      try await verifyDrawingRunPublicationOrdering(
        application: application, runtime: fixture.runRuntime,
        publications: publications, terminalRunID: runID)
      await application.shutdown()
    } catch {
      await fixture.planGate.release(.cancelled)
      await application.shutdown()
      _ = await run?.value
      throw error
    }
  }

  private func stopActions() -> [PlotterUIAction] {
    let learning = PlotterLearningActionRequest(item: .init(rawValue: "pen"),
      action: .stopPenInteraction(.init()))
    let drawing = PlotterDrawingRunIntent.stop(.init())
    return [
      .init(id: .init(learningRequest: learning), title: "Stop Pen Interaction", intent: .learningAction(learning)),
      .init(id: PlotterAppUIActionID.manualStop, title: "Stop Motion", intent: .manualStop(capabilityID: UUID())),
      .init(id: PlotterAppUIActionID.drawingRun(drawing), title: "Stop Drawing", intent: .drawingRun(drawing))
    ]
  }

  private func stopProjection(_ action: PlotterUIAction) -> PlotterUIProjection {
    .init(revision: .init(rawValue: 42), runtimeRevisions: [], actions: [action], learning: nil,
      incidentPackage: .unavailable(reason: "Native rendering fixture"), diagnostics: [], visitedCandidateCount: 1)
  }

}
