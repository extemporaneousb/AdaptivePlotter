import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing
@testable import PlotterApp

@Suite("Drawing overlay lifecycle", .serialized)
@MainActor
struct DrawingOverlayLifecycleTests {
  @Test("restart retains same-calibration archive evidence without painting it onto live video")
  func restartDoesNotSelectArchivedDrawings() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    await f.application.shutdown()
    let machine = f.machine
    let clock = f.clock
    let app = plotterApplicationRuntime(machine: machine,
      observationSessionOverride: f.camera, statePersistencePort: f.stores.persistence,
      drawingEvidencePort: f.stores.evidencePort, tipCalibrationSemanticIdentities: f.accepted.identities,
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [machine.descriptor] }, readNanoseconds: { clock.read() }),
      loadPenCapAppearanceSelection: { nil }, log: EventLog())
    do {
      await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
      await submitObservationConfigurationForTest(app, .selectSource(.live, f.camera.device.id))
      let saved = try #require(app.artifactResetEpisodeSnapshot.savedLearning.candidate?.checkpoint)
      #expect(saved.tipCalibration?.registration.applicability == f.accepted.borderRecord.tipCalibration.applicability)
      #expect(saved.semanticIdentity.paperInstance == f.accepted.borderRecord.paper.instance)
      #expect(f.accepted.borderRecord.plan.executionPlan?.strokes.isEmpty == false)
      assertNoArtwork(app)
      try await applyCompleteSavedLearning(app)
      assertNoArtwork(app)
      assertReferenceFrames(app.testActionSurfacePresentation)
      guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
        Issue.record("The drawing archive must remain available")
        await app.shutdown(); return
      }
      #expect(archive.records == [f.accepted.borderRecord])
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  @Test("hide and show clear only the target and retain placement, paper and ink protection while disconnected")
  func hideRetainsDrawingAuthority() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    do {
      let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
        style: .contours, strokeStyle: app.drawingStrokeStyle)
      let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
        manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
      let select = try #require(projection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
      #expect(await app.submitPlotterUIRequest(select) == .accepted(requestID: select.id))
      try await f.submit(.fitInDrawableRegion)
      try await f.submit(.assertPaperCoverage)
      try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      await f.planGate.release(.possibleInk)
      let draw = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      #expect(await app.submitPlotterUIRequest(draw) == .accepted(requestID: draw.id))
      let record = try #require(app.drawingRunSnapshot?.terminal?.record)
      await submitControllerSession(app, .toggleConnection)
      await app.drawingDraftSynchronizationTask?.value
      let before = app.drawingDraftSnapshot
      let plan = try #require(before.plan)
      let beforePreview = try #require(ActionSurfaceOverlayContent(presentation: app.testActionSurfacePresentation).targetPreview)
      let guidesBeforeHide = referenceFrameGeometry(app.testActionSurfacePresentation)
      assertReferenceFrames(app.testActionSurfacePresentation)
      let inkProtection = app.drawingRunSnapshot?.noRedraw
      if case .planMayContainInk = inkProtection {} else {
        Issue.record("The stopped drawing must establish ink protection before Hide Drawing")
      }
      let paper = app.currentPaperRevisionContext
      let feeds = await f.machine.requestedFeeds
      let penCommands = await f.machine.requestedPenCommands
      let savedLearning = app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint

      try await f.submit(.hideTarget)
      assertNoArtwork(app)
      assertReferenceFrames(app.testActionSurfacePresentation)
      #expect(referenceFrameGeometry(app.testActionSurfacePresentation) == guidesBeforeHide)
      let advancedFrame = try await f.camera.publishNextFrame()
      let advanced = app.testActionSurfacePresentation.resolvingAmbientPreviewFrame(advancedFrame)
      #expect(ActionSurfaceOverlayContent(presentation: advanced).targetPreview == nil)
      #expect(!advanced.renderedOverlays.contains { $0.provenance.kind == .intendedPath })
      #expect(advanced.renderedOverlays.contains { $0.provenance.kind == .drawingRegion })
      #expect(app.drawingDraftSnapshot.program == before.program)
      #expect(app.drawingDraftSnapshot.plan == plan)
      #expect(app.drawingDraftSnapshot.projection.draftRevision == before.projection.draftRevision)
      #expect(app.drawingDraftSnapshot.paperCoverageObservation == before.paperCoverageObservation)
      #expect(app.currentPaperRevisionContext == paper)
      #expect(app.drawingRunSnapshot?.noRedraw == inkProtection)
      #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == savedLearning)

      try await f.submit(.showTarget)
      let shown = try #require(ActionSurfaceOverlayContent(presentation: app.testActionSurfacePresentation).targetPreview)
      #expect(shown.strokes == beforePreview.strokes)
      assertReferenceFrames(app.testActionSurfacePresentation)
      #expect(referenceFrameGeometry(app.testActionSurfacePresentation) == guidesBeforeHide)
      #expect(shown.executionPlanContentHash == plan.revisionID.description)
      #expect(!app.testActionSurfacePresentation.overlays.contains { $0.provenance.kind == .intendedPath })
      #expect(await f.machine.requestedFeeds == feeds)
      #expect(await f.machine.requestedPenCommands == penCommands)
      guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
        Issue.record("Hide Drawing must retain the archive")
        await app.shutdown(); return
      }
      #expect(archive.records == [f.accepted.borderRecord, record])
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }

  private func referenceFrameGeometry(_ surface: ActionSurfacePresentation) -> [CameraPixelGeometry] {
    surface.overlays.filter { [.acceptedBoundary, .drawingRegion].contains($0.provenance.kind) }.map(\.geometry)
  }

  private func assertReferenceFrames(_ surface: ActionSurfacePresentation) {
    let guides = surface.overlays.filter { [.acceptedBoundary, .drawingRegion].contains($0.provenance.kind) }
    // Normal video retains the two reference frames independently of artwork.
    #expect(guides.count == 2)
    #expect(guides.allSatisfy { if case .polyline = $0.geometry { return true }; return false })
    #expect(!surface.overlays.contains { $0.provenance.kind == .calibrationGuide })
  }

  private func assertNoArtwork(_ app: PlotterApplicationRuntime) {
    let surface = app.testActionSurfacePresentation
    #expect(!app.drawingTargetIsVisible)
    #expect(ActionSurfaceOverlayContent(presentation: surface).targetPreview == nil)
    #expect(!surface.renderedOverlays.contains { $0.provenance.kind == .intendedPath })
    #expect(surface.overlays.contains { $0.provenance.kind == .acceptedBoundary })
    #expect(surface.overlays.contains { $0.provenance.kind == .drawingRegion })
  }
}
