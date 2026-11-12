@testable import PortraitStudioUI
import AppKit
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import SwiftUI
import Testing
@testable import PlotterApp

@MainActor
@Suite("Video reference frames", .serialized)
struct FrameReferencePresentationTests {
  @Test("frame visibility migrates independently without enabling Vision or changing persisted off choices")
  func preferenceMigration() throws {
    let name = "AdaptivePlotter.reference-frame-test.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let port = UserDefaultsObservationPreferencePort(defaults: defaults)
    #expect(port.loadOverlayPreference() == nil)
    defaults.set([UserSceneOverlay.penCap.rawValue], forKey: "AdaptivePlotter.userSceneOverlays")
    #expect(port.loadOverlayPreference() == [.penCap, .machineBoundary, .drawingRegion])
    try port.persistOverlayPreference([.drawingRegion])
    #expect(port.loadOverlayPreference() == [.drawingRegion])
    #expect(SceneFeatureSet(preference: .loaded(port.loadOverlayPreference())).isEmpty)
    try port.persistOverlayPreference([])
    #expect(port.loadOverlayPreference() == [])
  }

  @Test("reference toggles filter passive frames, preserve actual paths, and positioning replaces one region")
  func layerRouting() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    try await fixture.submit(.showTarget)
    let surface = app.testActionSurfacePresentation
    let frame = try #require(surface.displayedFrame)
    let references = surface.renderedOverlays.filter { [.acceptedBoundary, .drawingRegion].contains($0.provenance.kind) }
    #expect(references.count == 2)
    #expect(Set(references.map(\.provenance.kind)) == [.acceptedBoundary, .drawingRegion])
    #expect(surface.renderedOverlays.allSatisfy { $0.provenance.kind != .drawingBorder && $0.provenance.kind != .paperCoverage })
    #expect(surface.renderedOverlays.allSatisfy { $0.provenance.kind != .calibrationGuide })
    #expect(ActionSurfaceOverlayContent(presentation: surface).simulatedAnnotations.isEmpty)
    let shape = try #require(references.first?.geometry)
    let actual = CameraOverlayMeasurement(frameID: frame.frame.id, cameraConfigurationID: frame.frame.cameraConfigurationID,
      geometry: shape, provenance: .init(kind: .intendedPath, source: .planned, algorithmRevision: "actual-border-test"))
    let legacy = CameraOverlayMeasurement(frameID: frame.frame.id, cameraConfigurationID: frame.frame.cameraConfigurationID,
      geometry: shape, provenance: .init(kind: .drawingBorder, source: .inferred, algorithmRevision: "legacy-passive-test"))
    for boundary in [false, true] {
      for region in [false, true] {
        let p = ActionSurfacePresentation(displayedFrame: frame, overlays: references + [actual, legacy],
          drawingStudioCanvas: surface.drawingStudioCanvas, showsMachineBoundary: boundary, showsDrawingRegion: region)
        let visible = ActionSurfaceOverlayContent(presentation: p)
        #expect(visible.overlays.contains(actual))
        #expect(!visible.overlays.contains(legacy))
        #expect(visible.overlays.filter { $0.provenance.kind == .acceptedBoundary }.count == (boundary ? 1 : 0))
        #expect(visible.overlays.filter { $0.provenance.kind == .drawingRegion }.count == (region ? 1 : 0))
        #expect(visible.targetPreview?.strokes == surface.drawingStudioCanvas?.targetPreview?.strokes)
      }
    }
    let editing = ActionSurfaceOverlayContent(presentation: surface, replacesDrawingRegion: true)
    #expect(editing.overlays.filter { $0.provenance.kind == .acceptedBoundary }.count == 1)
    #expect(editing.overlays.allSatisfy { $0.provenance.kind != .drawingRegion })
    #expect(app.drawingPositioningUnavailableReason == nil)
    let editID = UUID()
    #expect(await app.beginDrawingFrameEdit(id: editID, on: frame))
    #expect(!app.paperCoverageOutlineIsVisible)
    #expect(app.videoViewportAdjustmentUnavailableReason != nil)
    app.endDrawingFrameEdit(id: editID)
    #expect(app.paperCoverageOutlineIsVisible)
    #expect(app.videoViewportAdjustmentUnavailableReason == nil)
    await app.shutdown()
  }

  @Test("active and parked Drawings expose the sheet outline independently of passive Video Settings")
  func hiddenRegionAdmission() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    try await fixture.submit(.showTarget)
    try await fixture.submit(.assertPaperCoverage)
    let cached = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.assertPaperCoverage)))
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let before = app.drawingDraftSnapshot
    let registration = app.tipCameraRegistration
    let guides = app.displayedFrame.map { app.sparseTipGuideOverlays(on: $0) }
    let features = SceneFeatureSet(preference: app.overlayPreferenceState)
    let inkProtection = app.drawingRunSnapshot?.noRedraw
    await submitObservationConfigurationForTest(app, .setOverlay(.drawingRegion, enabled: false))
    await app.drawingDraftSynchronizationTask?.value
    let passiveOff = app.drawingDraftSnapshot
    #expect(!app.overlayPreferenceState.enabled.contains(.drawingRegion))
    #expect(app.paperCoverageOutlineIsVisible)
    #expect(passiveOff.projection.externalFacts.paperCoverageOutlineIsVisible)
    #expect(ActionSurfaceOverlayContent(presentation: app.testActionSurfacePresentation).overlays.contains { $0.provenance.kind == .drawingRegion })
    #expect(passiveOff.paperCoverageObservation == before.paperCoverageObservation)
    #expect(passiveOff.plan == before.plan && passiveOff.authoredProgram == before.authoredProgram)
    #expect(passiveOff.paperCoverageIsCurrent)
    #expect(app.tipCameraRegistration == registration)
    #expect(app.displayedFrame.map { app.sparseTipGuideOverlays(on: $0) } == guides)
    #expect(SceneFeatureSet(preference: app.overlayPreferenceState) == features)
    #expect(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)) != nil)
    #expect(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.assertPaperCoverage)) != nil)
    guard case .refused(let refusal) = await app.submitPlotterUIRequest(cached) else {
      Issue.record("Cached sheet assertion bypassed its original UI revision"); await app.shutdown(); return
    }
    #expect(refusal.reason == .staleUIRevision)
    #expect(app.drawingDraftSnapshot.paperCoverageObservation == before.paperCoverageObservation)
    #expect(app.drawingDraftSnapshot.plan == before.plan)
    #expect(app.paperAcceptanceUnavailableReason == nil)
    // The same Draft owner receives a truthful visible-outline fact even when
    // the passive preference is off; it still binds the exact frame and paper.
    let owner = nominalDrawingDraftRuntime()
    let facts = app.drawingDraftExternalFacts
    let snapshot = await owner.synchronize(facts)
    let result = await owner.submit(.init(projection: snapshot.projection, intent: .assertPaperCoverage), facts: facts)
    #expect(result.snapshot.lastSubmissionRefusal == nil)
    #expect(result.snapshot.paperCoverageObservation?.paper == facts.revisions.paper)
    try await fixture.submit(.assertPaperCoverage)
    let confirmed = app.drawingDraftSnapshot
    try await fixture.submit(.hideTarget)
    #expect(app.paperCoverageOutlineIsVisible)
    #expect(ActionSurfaceOverlayContent(presentation: app.testActionSurfacePresentation).overlays.contains { $0.provenance.kind == .drawingRegion })
    #expect(app.drawingDraftSnapshot.authoredProgram == before.authoredProgram)
    #expect(app.drawingDraftSnapshot.plan == confirmed.plan)
    #expect(app.drawingDraftSnapshot.paperCoverageObservation == confirmed.paperCoverageObservation)
    #expect(app.drawingRunSnapshot?.noRedraw == inkProtection)
    try await fixture.submit(.showTarget)
    await submitObservationConfigurationForTest(app, .setOverlay(.drawingRegion, enabled: true))
    await app.drawingDraftSynchronizationTask?.value
    #expect(app.drawingDraftSnapshot.paperCoverageObservation == confirmed.paperCoverageObservation)
    #expect(app.drawingDraftSnapshot.plan == before.plan)
    #expect(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.assertPaperCoverage)) != nil)
    await app.shutdown()
  }

  @Test("Drawing and calibration editor geometry survives begin, drag, Apply and Cancel with passive reference on or off", arguments: [false, true])
  func editorGeometryRemainsVisible(passive: Bool) async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    try await fixture.submit(.showTarget)
    await submitObservationConfigurationForTest(app, .setOverlay(.drawingRegion, enabled: passive))
    await app.drawingDraftSynchronizationTask?.value
    let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
    let id = UUID()
    #expect(await app.beginDrawingFrameEdit(id: id, on: frame))
    let editing = app.testActionSurfacePresentation
    #expect(editing.showsDrawingRegion && !app.paperCoverageOutlineIsVisible)
    #expect(app.paperAcceptanceUnavailableReason != nil)
    let canvas = try #require(editing.drawingStudioCanvas)
    #expect(canvas.targetPreview(for: editing.displayedFrame) != nil)
    let authoredFrame = try #require(canvas.frame)
    let center = try authoredFrame.cameraCenter
    let transform = try #require(CameraPixelToViewTransform(frameWidth: frame.frame.width, frameHeight: frame.frame.height, viewWidth: 800, viewHeight: 600))
    let drag = try #require(DrawingFrameDrag(frame: authoredFrame, start: transform.point(center), transform: transform))
    let moved = try drag.updated(at: .init(x: center.x + 1, y: center.y + 1), minimumScale: canvas.placement.allowedScale.lowerBound)
    let session = try #require(app.drawingFrameEditSession)
    let placement = PlotterDrawingDraftCameraPlacement(frame: try #require(session.frame.plotterExactFrameReferenceIfMaterialized),
      point: try moved.cameraCenter, uniformScale: moved.geometry.placement.uniformScale, draftRevision: canvas.draftProjection.draftRevision)
    #expect(app.testActionSurfacePresentation.showsDrawingRegion)
    let projected = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID, manualDraft: .init(),
      includesLearningPath: false, pendingDrawingPlacement: placement)
    let request = try #require(projected.semantic.request(matching: .drawingDraft(.placeAtCameraPoint(placement))))
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    app.endDrawingFrameEdit(id: id)
    #expect(app.drawingDraftSnapshot.frame?.geometry == moved.geometry)
    #expect(app.testActionSurfacePresentation.showsDrawingRegion && app.paperCoverageOutlineIsVisible)
    let appliedFrame = app.drawingDraftSnapshot.frame
    let cancelID = UUID()
    #expect(await app.beginDrawingFrameEdit(id: cancelID, on: frame))
    #expect(app.testActionSurfacePresentation.showsDrawingRegion && !app.paperCoverageOutlineIsVisible)
    app.endDrawingFrameEdit(id: cancelID)
    #expect(app.drawingDraftSnapshot.frame == appliedFrame && app.testActionSurfacePresentation.showsDrawingRegion)
    let tip = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    await app.performTestExerciseAction(.redoThisStep, for: tip)
    let working = try #require(app.calibrationWorkingRegionPresentation)
    #expect(working.unavailableReason == nil)
    let regionFrame = try #require(app.testActionSurfacePresentation.displayedFrame)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: regionFrame))
    let regionEdit = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    #expect(app.testActionSurfacePresentation.showsDrawingRegion && !app.paperCoverageOutlineIsVisible)
    #expect(app.paperAcceptanceUnavailableReason != nil)
    let bounds = try CalibrationWorkingRegionGeometry.smaller(working.bounds)
    let workingCenter = try working.context.machineMap.fit.cameraPoint(from: .init(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2))
    let regionDrag = try #require(CalibrationWorkingRegionDrag(bounds: bounds, context: working.context, start: transform.point(workingCenter), transform: transform))
    let movedRegion = try regionDrag.updated(at: .init(x: workingCenter.x + 1, y: workingCenter.y + 1))
    #expect(app.applyCalibrationWorkingRegion(regionEdit, bounds: movedRegion) == nil)
    #expect(app.calibrationWorkingRegionPresentation?.bounds == movedRegion && app.testActionSurfacePresentation.showsDrawingRegion)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: regionFrame))
    let canceled = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    #expect(app.testActionSurfacePresentation.showsDrawingRegion)
    app.cancelCalibrationWorkingRegionEdit(id: canceled.id)
    #expect(app.calibrationWorkingRegionPresentation?.bounds == movedRegion && app.testActionSurfacePresentation.showsDrawingRegion)
    #expect(app.tipCalibrationRuntime.workingRegionEdit == nil && !app.paperCoverageOutlineIsVisible)
    await app.shutdown()
  }

  @Test("Calibration sheet confirmation without a selected Drawing exposes its admitted guide with passive region preference off")
  func calibrationGuideIgnoresPassivePreference() async throws {
    let checkpoint = ArtifactResetCheckpointStoreFixture()
    let clock = TestClock()
    let harness = makeCausalSimulatorAppFixture(
      statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: { checkpoint.load() },
        saveCheckpoint: { checkpoint.save($0) }, clearCheckpoint: { checkpoint.clear() }),
      residualEffectPort: TestApplicationResidualEffectPort(discoverDevices: { [] }, readNanoseconds: { clock.next() }))
    let app = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(app)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime, workspace: app, environment: .simulated)
    let camera = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    await app.performTestExerciseAction(.cameraCalibration(.buildFivePositionProposal), for: camera)
    await app.performTestExerciseAction(.cameraCalibration(.acceptProposal), for: camera)
    #expect(app.tipCameraRegistration == nil && app.machineCameraRegistration != nil)
    #expect(app.receivedDrawings.projectedDrawing == nil && app.receivedDrawings.sketches.selected == nil)
    #expect(try await app.receivedDrawings.library.drawings().entries.isEmpty)
    // Draft's built-in source exists before a canonical Drawing is selected.
    // This calibration guide must stand on its own registration and exact frame.
    #expect(app.drawingDraftSnapshot.selectedCatalogItemID == .square)
    let noRedraw = app.drawingRunSnapshot?.noRedraw
    await submitObservationConfigurationForTest(app, .setOverlay(.drawingRegion, enabled: false))
    await app.drawingDraftSynchronizationTask?.value
    #expect(!app.overlayPreferenceState.enabled.contains(.drawingRegion))
    let facts = app.drawingDraftExternalFacts.revisions
    let guide = try #require(facts.placementGuide)
    #expect(app.paperCoverageOutlineIsVisible && app.paperAcceptanceUnavailableReason == nil)
    #expect(ActionSurfaceOverlayContent(presentation: app.testActionSurfacePresentation).overlays.contains { $0.provenance.kind == .drawingRegion })
    let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.assertPaperCoverage)))
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    #expect(app.drawingDraftSnapshot.sheetPlacementIsCurrent)
    #expect(app.drawingDraftSnapshot.sheetPlacementAssertion?.guide == guide)
    #expect(app.drawingDraftSnapshot.sheetPlacementAssertion?.paper == facts.paper)
    #expect(app.drawingDraftSnapshot.sheetPlacementAssertion?.frame == app.drawingDraftSnapshot.projection.externalFacts.displayedFrame)
    #expect(app.drawingRunSnapshot?.noRedraw == noRedraw)
    #expect(app.receivedDrawings.projectedDrawing == nil && app.receivedDrawings.sketches.selected == nil)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 0)
    await app.shutdown()
  }

  @Test("pending calibration extent cannot attest the retained accepted paper extent")
  func pendingCalibrationCoverage() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    try await fixture.submit(.showTarget)
    try await fixture.submit(.assertPaperCoverage)
    let cached = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.assertPaperCoverage)))
    let tip = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    await app.performTestExerciseAction(.redoThisStep, for: tip)
    let before = app.drawingDraftSnapshot
    let accepted = app.tipCameraRegistration
    let preview = try #require(app.calibrationWorkingRegionPresentation)
    let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    let edit = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    let b = preview.context.boundary
    let smaller = try AxisAlignedBounds<MachineSpace>(minX: b.minX+20, minY: b.minY+20, maxX: b.maxX-20, maxY: b.maxY-20)
    #expect(app.applyCalibrationWorkingRegion(edit, bounds: smaller) == nil)
    await app.drawingDraftSynchronizationTask?.value
    #expect(app.calibrationWorkingRegionPresentation?.bounds == smaller)
    #expect(!app.paperCoverageOutlineIsVisible)
    #expect(app.paperAcceptanceUnavailableReason == "Finish calibration before confirming sheet coverage.")
    #expect(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.assertPaperCoverage)) == nil)
    guard case .refused(let refusal) = await app.submitPlotterUIRequest(cached) else {
      Issue.record("Pending extent attested retained accepted area"); await app.shutdown(); return
    }
    #expect(refusal.reason == .staleUIRevision)
    #expect(app.tipCameraRegistration == accepted)
    #expect(app.drawingDraftSnapshot.paperCoverageObservation == before.paperCoverageObservation)
    #expect(app.drawingDraftSnapshot.plan == before.plan)
    await app.shutdown()
  }

  @Test("Boundary focus uses compatible projected geometry and preserves evidence through fit and full video")
  func viewportFit() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    let surface = app.testActionSurfacePresentation
    let frame = try #require(surface.displayedFrame)
    let fitted = try #require(app.learnedBoundsPresentationRegion(frame))
    let outline = try #require(surface.renderedOverlays.first { $0.provenance.kind == .acceptedBoundary })
    guard case .polyline(let path) = outline.geometry else { Issue.record("Expected projected Boundary"); return }
    let minX = Int(floor(path.points.map(\.x).min()!)), minY = Int(floor(path.points.map(\.y).min()!))
    let maxX = Int(ceil(path.points.map(\.x).max()!)), maxY = Int(ceil(path.points.map(\.y).max()!))
    #expect(fitted == cameraFrameIntersection(PixelRect(x: minX, y: minY, width: maxX-minX, height: maxY-minY),
      frameWidth: frame.frame.width, frameHeight: frame.frame.height))
    let other = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "incompatible-camera")), frame: frame.frame)
    #expect(app.learnedBoundsPresentationRegion(other) == nil)
    #expect(surface.resolvingAmbientPreviewFrame(other).viewportContext == nil)
    var viewport = ActionSurfaceViewportState()
    viewport.synchronize(with: surface.viewportContext)
    viewport.showFittedBounds()
    #expect(viewport.visibleRegion(frameWidth: frame.frame.width, frameHeight: frame.frame.height) != nil)
    viewport.showFullFrame()
    #expect(viewport.visibleRegion(frameWidth: frame.frame.width, frameHeight: frame.frame.height) == nil)
    #expect(app.testActionSurfacePresentation.renderedOverlays == surface.renderedOverlays)
    // A deliberately off-center focus remains off center; clipping never invents pixels.
    viewport.synchronize(with: ActionSurfaceViewportContext(source: .simulated, cameraConfigurationID: .init(),
      frameWidth: 800, frameHeight: 600, fittedRegion: PixelRect(x: 420, y: 100, width: 300, height: 250),
      preferredInitialZoom: 0, presentationRevisionToken: "off-center-test"))
    viewport.showFittedBounds()
    #expect(viewport.visibleRegion(frameWidth: 800, frameHeight: 600) == PixelRect(x: 420, y: 100, width: 300, height: 250))
    await app.shutdown()
  }

  @Test("controller geometry Fit and Size reach the actual bounds without a hidden ninety-percent inset")
  func fullControllerFit() throws {
    let region = try DrawableMachineRegion(bounds: .init(minX: 20, minY: -40, maxX: 220, maxY: 80))
    let extent = try Size2<FieldSpace>(width: 200, height: 120)
    #expect(PlotterDrawingPlanningAdapter.scaleRange(extent: extent, rotationDegrees: 0, region: region).upperBound == 1)
    for rotation in [0.0, 17, 90] {
      let maximum = PlotterDrawingPlanningAdapter.scaleRange(extent: extent, rotationDegrees: rotation, region: region).upperBound
      let placement = try DrawingPlacement(fieldAnchor: .init(x: 100, y: 60),
        machineAnchor: .init(x: 120, y: 20), uniformScale: maximum, rotationRadians: rotation * .pi / 180)
      let geometry = DrawingFrameGeometry(extent: extent, placement: placement)
      #expect(geometry.isContained(in: region))
      #expect(try !geometry.replacing(scale: maximum * 1.001).isContained(in: region))
    }
  }

  @Test("reference settings and default, hidden, and positioning layers render on white paper",
    .enabled(if: ProcessInfo.processInfo.environment["ACTION_SURFACE_RENDER_TEST"] == "1"))
  func rendersReferenceFrames() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    try await fixture.submit(.showTarget)
    let projection = app.testPlotterUIProjection()
    let displayedFrame = try #require(projection.actionSurface.displayedFrame)
    let surface = projection.actionSurface.resolvingAmbientPreviewFrame(displayedFrame, forceRetainedFrame: true)
    try await render(ActionSurface(presentation: surface, plotterUIProjection: projection.semantic,
      plotterUIIntentSink: app), path: "/tmp/reference-frames-default.png", width: 800, height: 600)
    try await render(WorkbenchVideoSettings(application: app, projection: app.observationConfigurationProjection,
      semantic: projection.semantic, viewport: .constant(.init())), path: "/tmp/reference-frames-settings.png", width: 440, height: 650)
    let frame = try #require(surface.drawingStudioCanvas?.frame)
    let displayed = try #require(surface.displayedFrame)
    let transform = try #require(CameraPixelToViewTransform(frameWidth: displayed.frame.width,
      frameHeight: displayed.frame.height, viewWidth: 800, viewHeight: 600))
    let content = ActionSurfaceOverlayContent(presentation: surface, replacesDrawingRegion: true)
    let editing = ZStack {
      Color.white
      ActionSurfaceOverlayCanvas(content: content, transform: transform, diagnostics: nil)
      DrawingFrameOverlay(frame: frame, transform: transform, editing: true, staged: false)
    }
    try await render(editing, path: "/tmp/reference-frames-positioning.png", width: 800, height: 600)
    await submitObservationConfigurationForTest(app, .setOverlay(.machineBoundary, enabled: false))
    await submitObservationConfigurationForTest(app, .setOverlay(.drawingRegion, enabled: false))
    await app.drawingDraftSynchronizationTask?.value
    let hidden = app.testPlotterUIProjection()
    let hiddenSurface = hidden.actionSurface.resolvingAmbientPreviewFrame(displayedFrame, forceRetainedFrame: true)
    #expect(hiddenSurface.displayedFrame?.frame.id == surface.displayedFrame?.frame.id)
    #expect(hiddenSurface.displayedFrame?.frame.contentSHA256 == surface.displayedFrame?.frame.contentSHA256)
    #expect(app.drawingTargetIsVisible)
    let hiddenTarget = try #require(ActionSurfaceOverlayContent(presentation: hiddenSurface).targetPreview)
    #expect(hiddenTarget.strokes == ActionSurfaceOverlayContent(presentation: surface).targetPreview?.strokes)
    #expect(!hiddenSurface.showsMachineBoundary && hiddenSurface.showsDrawingRegion)
    try await render(ActionSurface(presentation: hiddenSurface, plotterUIProjection: hidden.semantic,
      plotterUIIntentSink: app), path: "/tmp/reference-frames-hidden.png", width: 800, height: 600)
    await app.shutdown()
  }

  private func render<V: View>(_ view: V, path: String, width: CGFloat, height: CGFloat) async throws {
    _ = NSApplication.shared
    let host = NSHostingView(rootView: view.frame(width: width, height: height).background(Color.white).environment(\.colorScheme, .light))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: width, height: height),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua); host.appearance = NSAppearance(named: .aqua)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); window.display()
    try await Task.sleep(for: .milliseconds(100))
    host.display()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: path))
    #expect(data.count > 2000)
  }
}
