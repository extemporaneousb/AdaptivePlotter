import AppKit
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import SwiftUI
import Testing
@testable import PlotterApp

@MainActor
@Suite("Calibration working region", .serialized)
struct CalibrationWorkingRegionTests {
  private func prepare() async throws -> CausalSimulatorAppFixture {
    let harness = makeCausalSimulatorAppFixture()
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime,
      workspace: harness.workspace, environment: .simulated)
    let camera = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    await harness.workspace.performTestExerciseAction(.cameraCalibration(.buildFivePositionProposal), for: camera)
    await harness.workspace.performTestExerciseAction(.cameraCalibration(.acceptProposal), for: camera)
    return harness
  }

  private func asymmetricRegion(_ context: PlotterTipWorkingRegionContext) throws -> AxisAlignedBounds<MachineSpace> {
    let b = context.boundary
    return try AxisAlignedBounds(minX: b.minX + 13, minY: b.minY + 21,
      maxX: b.maxX - 31, maxY: b.maxY - 17)
  }

  @Test("Apply binds the exact frame and Cancel preserves selection; context changes refuse")
  func ownerAdmission() async throws {
    let harness = try await prepare(), app = harness.workspace
    let preview = try #require(app.calibrationWorkingRegionPresentation)
    let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
    let bounds = try asymmetricRegion(preview.context)
    let before = await harness.simulator.snapshot()
    let id = UUID()
    #expect(app.beginCalibrationWorkingRegionEdit(id: id, on: frame))
    let edit = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    #expect(app.calibrationWorkingRegionFrame?.plotterExactFrameReferenceIfMaterialized == edit.exactFrame)
    #expect(app.tipCalibrationRuntime.freezeWorkingRegion(context: preview.context, defaultBounds: bounds).isRegionRefused)
    let forged = PlotterTipWorkingRegionEdit(id: UUID(), exactFrame: edit.exactFrame, selection: edit.selection)
    #expect(app.tipCalibrationRuntime.submitWorkingRegion(.apply(forged, bounds), currentContext: preview.context).isRegionRefused)
    #expect(app.tipCalibrationRuntime.workingRegionEdit == edit)
    #expect(app.tipCalibrationRuntime.submitWorkingRegion(.begin(forged), currentContext: preview.context).isRegionRefused)
    #expect(app.tipCalibrationRuntime.workingRegionEdit == edit)
    #expect(app.tipCalibrationRuntime.submitWorkingRegion(.begin(edit), currentContext: preview.context) == .completed)
    let tip = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    #expect(app.testPlotterUIProjection(selectedItemID: tip, includesLearningPath: true).semantic.request(
      for: learningActionID(.tipCalibration(.beginFourMarkBatch), owner: tip)) == nil)
    let current = edit
    #expect(app.applyCalibrationWorkingRegion(current, bounds: bounds) == nil)
    #expect(app.currentSparseTipBatchPlan?.workingRegion == bounds)
    #expect(app.calibrationWorkingRegionFrame == nil)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    let cancelled = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    app.cancelCalibrationWorkingRegionEdit(id: cancelled.id)
    #expect(app.tipCalibrationRuntime.selectedWorkingRegion?.bounds == bounds)
    #expect(await harness.simulator.snapshot() == before)

    let context = preview.context
    func changedContext(map: MachineCameraRegistration? = nil, mapRevision: LearningArtifactRevisionID? = nil,
      session: UUID? = nil, paper: PaperRevisionContext? = nil, tool: ToolAssemblyRevision? = nil,
      pen: PenContactProfileRevision? = nil, boundary: AxisAlignedBounds<MachineSpace>? = nil,
      boundaryIDs: Set<LearningArtifactRevisionID>? = nil, configuration: CameraConfigurationID? = nil) -> PlotterTipWorkingRegionContext {
      .init(boundary: boundary ?? context.boundary, machineMap: map ?? context.machineMap,
        machineMapRevision: mapRevision ?? context.machineMapRevision, controllerSessionID: session ?? context.controllerSessionID,
        paper: paper ?? context.paper, toolAssembly: tool ?? context.toolAssembly, penContactProfile: pen ?? context.penContactProfile,
        cameraConfigurationID: configuration ?? context.cameraConfigurationID, boundaryRevisionIDs: boundaryIDs ?? context.boundaryRevisionIDs)
    }
    let map = context.machineMap, optical = map.opticalConfiguration
    let changedOptical = try CameraOpticalConfigurationIdentity(source: optical.source,
      sensorFormat: optical.sensorFormat, width: optical.width, height: optical.height, pixelFormat: optical.pixelFormat,
      orientation: optical.orientation, mirrored: optical.mirrored, captureCrop: optical.captureCrop,
      digitalZoomFactor: optical.digitalZoomFactor, lensIdentity: optical.lensIdentity, focusConfiguration: optical.focusConfiguration,
      mountRevision: UUID(), reframingRevision: optical.reframingRevision)
    let changedMap = try MachineCameraRegistration(candidateFit: map.candidateFit, fit: map.fit,
      source: map.source, opticalConfiguration: changedOptical, machineGeometry: map.machineGeometry,
      controllerSessionID: map.controllerSessionID, coordinateRevision: map.coordinateRevision,
      cameraConfigurationID: map.cameraConfigurationID, fitCorrespondenceProvenance: map.fitCorrespondenceProvenance,
      holdoutCorrespondenceProvenance: map.holdoutCorrespondenceProvenance, maximumHoldoutResidualPixels: map.maximumHoldoutResidualPixels,
      estimatorRevision: map.estimatorRevision, uncertaintyPixels: map.uncertaintyPixels,
      applicabilityRectangle: map.applicabilityRectangle, applicabilityDerivation: map.applicabilityDerivation)
    let alternatives = [changedContext(session: UUID()), changedContext(mapRevision: .init()),
      changedContext(paper: .init(instance: .init(), contactPlane: context.paper.contactPlane)),
      changedContext(paper: .init(instance: context.paper.instance, contactPlane: .init())),
      changedContext(tool: .init()), changedContext(pen: .init()), changedContext(map: changedMap),
      changedContext(map: try map.rebasedForKnownMachineCoordinateChange(to: map.coordinateRevision+1, delta: .init(dx: 1, dy: 2))),
      changedContext(boundaryIDs: [.init()]), changedContext(configuration: CameraConfigurationID()),
      changedContext(boundary: try .init(minX: context.boundary.minX+1, minY: context.boundary.minY,
        maxX: context.boundary.maxX, maxY: context.boundary.maxY))]
    for changed in alternatives {
      #expect(app.tipCalibrationRuntime.submitWorkingRegion(.begin(current), currentContext: context) == .completed)
      #expect(app.tipCalibrationRuntime.submitWorkingRegion(.apply(current, bounds), currentContext: changed).isRegionRefused)
      #expect(app.tipCalibrationRuntime.freezeWorkingRegion(context: changed, defaultBounds: changed.boundary).isRegionRefused)
      #expect(app.tipCalibrationRuntime.selectedWorkingRegion?.bounds == bounds)
    }
    #expect(app.tipCalibrationRuntime.freezeWorkingRegion(context: context, defaultBounds: context.boundary) == .completed)
    let frozen = app.tipCalibrationRuntime.frozenWorkingRegion
    await app.tipCalibrationRuntime.prepareForNewAttempt()
    #expect(app.tipCalibrationRuntime.selectedWorkingRegion?.bounds == bounds)
    #expect(app.tipCalibrationRuntime.frozenWorkingRegion == frozen)
    app.tipCalibrationRuntime.replaceBlacklistedLocations([.init(calibrationPosition: .negativeX,
      machinePosition: try .init(x: bounds.minX + 10, y: bounds.minY + 10), markRadiusMM: 2,
      paperInstance: context.paper.instance)])
    #expect(app.tipCalibrationRuntime.submitWorkingRegion(.begin(current), currentContext: context).isRegionRefused)
    #expect(app.tipCalibrationRuntime.frozenWorkingRegion == frozen)
  }

  @Test("a changed cap registration makes a frozen batch unavailable without substituting Boundary guides")
  func staleFrozenBatch() async throws {
    let harness = try await prepare(), app = harness.workspace
    let preview = try #require(app.calibrationWorkingRegionPresentation)
    let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
    let bounds = try asymmetricRegion(preview.context)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    let edit = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    #expect(app.applyCalibrationWorkingRegion(edit, bounds: bounds) == nil)
    #expect(app.tipCalibrationRuntime.freezeWorkingRegion(context: preview.context, defaultBounds: bounds) == .completed)
    let frozen = app.tipCalibrationRuntime.frozenWorkingRegion
    let camera = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    await app.performTestExerciseAction(.redoThisStep, for: camera)
    await app.performTestExerciseAction(.cameraCalibration(.buildFivePositionProposal), for: camera)
    await app.performTestExerciseAction(.cameraCalibration(.acceptProposal), for: camera)
    let current = try #require(app.displayedFrame)
    let context = try #require(app.calibrationWorkingRegionContext(on: current))
    #expect(context.machineMapRevision != preview.context.machineMapRevision)
    #expect(app.tipCalibrationRuntime.frozenWorkingRegion == frozen)
    #expect(app.currentSparseTipBatchPlan == nil)
    #expect(app.sparseTipGuideOverlays(on: current).isEmpty)
    #expect(!app.testActionSurfacePresentation.renderedOverlays.contains {
      [.acceptedBoundary, .drawingRegion, .calibrationGuide].contains($0.provenance.kind)
    })
  }

  @Test("Boundary-forward and Reset All discard working-region transients", arguments: [false, true])
  func resetsRegion(resetAll: Bool) async throws {
    let harness = try await prepare(), app = harness.workspace
    let preview = try #require(app.calibrationWorkingRegionPresentation)
    let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    let edit = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    #expect(app.applyCalibrationWorkingRegion(edit, bounds: try asymmetricRegion(preview.context)) == nil)
    #expect(app.tipCalibrationRuntime.freezeWorkingRegion(context: preview.context, defaultBounds: preview.bounds) == .completed)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    if resetAll {
      let plan = try #require(app.resetAllLearningPlan)
      #expect(await app.submitResetAllLearning(plan))
    } else {
      let plan = try #require(app.learningVacatePlan(from: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)))
      #expect(await app.performLearningVacate(plan))
    }
    #expect(app.tipCalibrationRuntime.workingRegionEdit == nil)
    #expect(app.tipCalibrationRuntime.selectedWorkingRegion == nil)
    #expect(app.tipCalibrationRuntime.frozenWorkingRegion == nil)
    #expect(app.calibrationWorkingRegionFrame == nil)
  }

  @Test("cap inverse dragging preserves machine-axis rectangle and bounds every resize corner")
  func gestures() async throws {
    let harness = try await prepare(), app = harness.workspace
    let context = try #require(app.calibrationWorkingRegionPresentation?.context)
    let bounds = try asymmetricRegion(context)
    let transform = try #require(CameraPixelToViewTransform(frameWidth: context.machineMap.opticalConfiguration.width,
      frameHeight: context.machineMap.opticalConfiguration.height, viewWidth: 800, viewHeight: 600))
    let corners = try DrawingBorderPlan(bounds: bounds).pathPositions.dropLast()
    for (index, position) in corners.enumerated() {
      let pixel = try context.machineMap.fit.cameraPoint(from: position.point)
      let drag = try #require(CalibrationWorkingRegionDrag(bounds: bounds, context: context,
        start: transform.point(pixel), transform: transform))
      #expect(drag.corner == index)
      for vector in [(10000.0,10000.0),(-10000.0,-10000.0)] {
        let changed = try drag.updated(at: .init(x: pixel.x+vector.0, y: pixel.y+vector.1))
        #expect(context.contains(changed))
        #expect(changed.maxX-changed.minX >= TipCalibrationWorkingRegionPolicy.minimumSpanMM)
        #expect(changed.maxY-changed.minY >= TipCalibrationWorkingRegionPolicy.minimumSpanMM)
      }
    }
    let center = try context.machineMap.fit.cameraPoint(from: .init(x: (bounds.minX+bounds.maxX)/2,
      y: (bounds.minY+bounds.maxY)/2))
    let drag = try #require(CalibrationWorkingRegionDrag(bounds: bounds, context: context,
      start: transform.point(center), transform: transform))
    #expect(drag.corner == nil)
    let moved = try drag.updated(at: .init(x: center.x+10000, y: center.y-10000))
    #expect(context.contains(moved))
    #expect(abs((moved.maxX-moved.minX)-(bounds.maxX-bounds.minX)) < 1e-9)
    #expect(abs((moved.maxY-moved.minY)-(bounds.maxY-bounds.minY)) < 1e-9)
  }

  @Test("Smaller recovers a default region whose resize handles are outside the video")
  func offscreenDefaultRegion() async throws {
    let harness = try await prepare()
    let context = try #require(harness.workspace.calibrationWorkingRegionPresentation?.context)
    let centerX = (context.boundary.minX+context.boundary.maxX)/2
    let centerY = (context.boundary.minY+context.boundary.maxY)/2
    var region = try AxisAlignedBounds<MachineSpace>(minX: centerX-5000, minY: centerY-4000,
      maxX: centerX+5000, maxY: centerY+4000)
    func cornersVisible(_ bounds: AxisAlignedBounds<MachineSpace>) throws -> Bool {
      try DrawingBorderPlan(bounds: bounds).pathPositions.dropLast().allSatisfy {
        let point = try context.machineMap.fit.cameraPoint(from: $0.point)
        return point.x >= 0 && point.y >= 0 && point.x < Double(context.machineMap.opticalConfiguration.width)
          && point.y < Double(context.machineMap.opticalConfiguration.height)
      }
    }
    #expect(try !cornersVisible(region))
    for _ in 0..<40 {
      region = try CalibrationWorkingRegionGeometry.smaller(region)
    }
    #expect(try cornersVisible(region))
    #expect(abs((region.minX+region.maxX)/2-centerX) < 1e-9)
    #expect(abs((region.minY+region.maxY)/2-centerY) < 1e-9)
    #expect(region.maxX-region.minX >= TipCalibrationWorkingRegionPolicy.minimumSpanMM)
    #expect(region.maxY-region.minY >= TipCalibrationWorkingRegionPolicy.minimumSpanMM)
  }

  @Test("selected region survives fit and rebase while paper assertion and artwork remain bounded")
  func selectedRegionEndToEnd() async throws {
    let harness = makeCausalSimulatorAppFixture(), app = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(app)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime, workspace: app, environment: .simulated)
    let boundary = try SparseTipBatchMarkPlan.boundaryEnvelope(for: app.testAcceptedBoundaryAggregates)
    let bounds = try AxisAlignedBounds<MachineSpace>(minX: boundary.minX+13, minY: boundary.minY+21,
      maxX: boundary.maxX-31, maxY: boundary.maxY-17)
    try await completeSimulatedTipCalibration(app, simulator: harness.simulator, workingRegion: bounds)
    let registration = try #require(app.tipCameraRegistration)
    let batch = try #require(app.currentSparseTipBatchPlan)
    #expect(batch.workingRegion == bounds)
    #expect(registration.applicabilityRectangle == batch.applicabilityRectangle)
    #expect(app.currentDrawableMachineRegion?.bounds == bounds)
    #expect(registration.estimatorRevision == SparseTipCircularMarkPlan.registrationEstimatorRevision)
    #expect(!app.paperCoverageIsCurrent)
    let decoded = try JSONDecoder().decode(TipCameraRegistration.self, from: JSONEncoder().encode(registration))
    #expect(try SparseTipBatchMarkPlan.selectedWorkingRegion(for: decoded) == bounds)
    let historicalRevisions = [SparseTipCircularMarkPlan.cardinalRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.boundaryCornerRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.insetFiveCircleRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.boundaryExtremeFourCircleRegistrationEstimatorRevision,
      SparseTipCircularMarkPlan.boundaryInsetFourCircleRegistrationEstimatorRevision]
    let encoded = try #require(String(data: JSONEncoder().encode(registration), encoding: .utf8))
    for revision in historicalRevisions {
      let historical = try JSONDecoder().decode(TipCameraRegistration.self,
        from: Data(encoded.replacingOccurrences(of: registration.estimatorRevision, with: revision).utf8))
      #expect(try SparseTipBatchMarkPlan.selectedWorkingRegion(for: historical) == nil)
      #expect(try JSONDecoder().decode(TipCameraRegistration.self, from: JSONEncoder().encode(historical)) == historical)
    }
    let outside = try Point2<MachineSpace>(x: bounds.minX+1, y: bounds.minY+1)
    #expect(try registration.diagnosticProjection(at: outside).applicability == .outsideRecordedApplicability)
    let evidenceProjection = try TipApplicabilityEvidencePolicy.project(paths: [Polyline(points: [outside,
      Point2(x: outside.x+2, y: outside.y+2)])], using: registration)
    #expect(evidenceProjection.attributableCameraPolylines == nil)
    #expect(evidenceProjection.diagnosticLimitation != nil)
    let delta = try Vector2<MachineSpace>(dx: 37.25, dy: -12.5)
    let rebased = try decoded.rebasedForKnownMachineCoordinateChange(to: .init(rawValue: 19), delta: delta)
    let translated = try #require(try SparseTipBatchMarkPlan.selectedWorkingRegion(for: rebased))
    #expect(abs(translated.minX-bounds.minX-delta.dx) < 1e-9)
    #expect(abs(translated.maxY-bounds.maxY-delta.dy) < 1e-9)
    let borderOwner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    await app.performTestExerciseAction(.start, for: borderOwner)
    let border = try #require(app.borderValidationSnapshot.drawingBorderPlan)
    let path = try #require(border.strokes.first?.path)
    let expected = try DrawingBorderPlan(bounds: registration.applicabilityRectangle)
    #expect(path.points == expected.pathPositions.map(\.point))
    await app.drawingDraftSynchronizationTask?.value
    func submitDraft(_ intent: PlotterDrawingDraftIntent) async throws {
      let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(intent)))
      #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    }
    try await submitDraft(.assertPaperCoverage)
    let coverage = try #require(app.drawingDraftSnapshot.paperCoverageObservation)
    #expect(coverage.drawableRegion?.bounds == bounds)
    let inverse = try registration.cameraFromMachine.inverted()
    let coveredMachine = try coverage.polygon.map { try inverse.applying(to: $0) }
    #expect(abs(coveredMachine.map(\.x).min()! - bounds.minX) < 1e-9)
    #expect(abs(coveredMachine.map(\.y).max()! - bounds.maxY) < 1e-9)
    #expect(coverage.drawableRegion?.bounds != boundary)
    #expect(app.interactiveLearningIsComplete)
    let style = try StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(registration.applicability.toolAssembly.rawValue))
    let program = try DrawingProgramCatalog.program(for: .square, style: style)
    let handoff = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
    let select = try #require(handoff.semantic.request(matching: .drawingDraft(.selectProgram(program))))
    #expect(await app.submitPlotterUIRequest(select) == .accepted(requestID: select.id))
    #expect(app.drawingDraftSnapshot.isTargetVisible)
    try await submitDraft(.fitInDrawableRegion)
    let artwork = try #require(app.drawingDraftSnapshot.frame)
    #expect(artwork.boundary.bounds == bounds)
    #expect(artwork.geometry.isContained(in: artwork.boundary))
    let resize = (app.drawingDraftSnapshot.uniformScale*60).rounded() / 100
    try await submitDraft(.setUniformScale(resize))
    try await submitDraft(.centerInDrawableRegion)
    let smaller = try #require(app.drawingDraftSnapshot.frame)
    #expect(smaller.geometry.isContained(in: smaller.boundary))
    let shifted = try smaller.translated(to: registration.diagnosticProjection(at: .init(x: bounds.minX-50,
      y: bounds.maxY+50)).cameraPoint)
    #expect(shifted.geometry.isContained(in: smaller.boundary))
    #expect(app.drawingDraftExternalFacts.revisions.drawingBorderBounds == registration.applicabilityRectangle)
    await app.recordNewPaperSheetOnCurrentPlane()
    #expect(app.currentDrawableMachineRegion?.bounds == bounds)
    #expect(!app.paperCoverageIsCurrent)
  }

  @Test("working-region editing and Drawing frame editing exclude each other and cached Draw")
  func excludesDrawing() async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    try await fixture.submit(.showTarget)
    try await fixture.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let cachedDraw = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    let acceptedBeforeEdit = try #require(app.tipCameraRegistration)
    let tip = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    let frame = try #require(app.displayedFrame)
    let drawingEditID = UUID()
    #expect(await app.beginDrawingFrameEdit(id: drawingEditID, on: frame))
    #expect(!app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    app.endDrawingFrameEdit(id: drawingEditID)
    await app.performTestExerciseAction(.redoThisStep, for: tip)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    let edit = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    #expect(!(await app.beginDrawingFrameEdit(id: UUID(), on: frame)))
    guard case .refused(let refusal) = await app.submitPlotterUIRequest(cachedDraw) else {
      await fixture.planGate.release(.cancelled)
      await app.shutdown()
      Issue.record("A cached Draw request bypassed working-region editing."); return
    }
    #expect(refusal.reason == .unavailableAction)
    #expect(refusal.remedy == "Apply or Cancel the working-region edit before drawing.")
    #expect(await fixture.planGate.request == nil)
    app.cancelCalibrationWorkingRegionEdit(id: edit.id)
    #expect(app.tipCameraRegistration == acceptedBeforeEdit)
    await app.shutdown()
  }

  @Test("Action Surface renders the working-region control and three-part legend offscreen",
    .enabled(if: ProcessInfo.processInfo.environment["ACTION_SURFACE_RENDER_TEST"] == "1"))
  func rendersFullSurface() async throws {
    let harness = try await prepare(), app = harness.workspace
    let initial = try #require(app.calibrationWorkingRegionPresentation)
    let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
    #expect(app.beginCalibrationWorkingRegionEdit(id: UUID(), on: frame))
    let edit = try #require(app.tipCalibrationRuntime.workingRegionEdit)
    #expect(app.applyCalibrationWorkingRegion(edit, bounds: try asymmetricRegion(initial.context)) == nil)
    let projection = app.testPlotterUIProjection()
    let working = try #require(app.calibrationWorkingRegionPresentation)
    _ = NSApplication.shared
    let view = ActionSurface(presentation: projection.actionSurface,
      plotterUIProjection: projection.semantic, plotterUIIntentSink: app, workingRegion: working)
      .frame(width: 800, height: 600).background(.black).environment(\.colorScheme, .light)
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .aqua)
    host.appearance = NSAppearance(named: .aqua)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded(); window.display()
    try await Task.sleep(for: .milliseconds(100))
    host.display()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: "/tmp/calibration-working-region-action-surface.png"))
    #expect(data.count > 2000)
  }

  @Test("working-region view renders handles and circle clearances offscreen",
    .enabled(if: ProcessInfo.processInfo.environment["ACTION_SURFACE_RENDER_TEST"] == "1"))
  func rendersOffscreen() async throws {
    let harness = try await prepare()
    let context = try #require(harness.workspace.calibrationWorkingRegionPresentation?.context)
    let bounds = try asymmetricRegion(context)
    let transform = try #require(CameraPixelToViewTransform(frameWidth: context.machineMap.opticalConfiguration.width,
      frameHeight: context.machineMap.opticalConfiguration.height, viewWidth: 800, viewHeight: 600))
    _ = NSApplication.shared
    let view = CalibrationWorkingRegionOverlay(context: context, bounds: bounds, transform: transform, editing: true)
      .frame(width: 800, height: 600).background(.black)
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.close() }
    host.layoutSubtreeIfNeeded()
    window.display()
    try await Task.sleep(for: .milliseconds(100))
    host.display()
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: "/tmp/calibration-working-region-overlay.png"))
    #expect(data.count > 2000)
    let scale = Double(bitmap.pixelsWide) / 800
    for corner in try DrawingBorderPlan(bounds: bounds).pathPositions.dropLast() {
      let point = transform.point(try context.machineMap.fit.cameraPoint(from: corner.point))
      let x = Int(point.x * scale), y = Int(point.y * scale)
      var colored = 0
      for row in (y-Int(7*scale))...(y+Int(7*scale)) {
        for column in (x-Int(7*scale))...(x+Int(7*scale)) {
          guard row >= 0, row < bitmap.pixelsHigh, column >= 0, column < bitmap.pixelsWide,
            let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { continue }
          if color.redComponent > 0.6 && color.greenComponent > 0.5 && color.blueComponent < 0.4 { colored += 1 }
        }
      }
      #expect(colored > 10, "Missing working-region handle at \(point)")
    }
  }
}

private extension PlotterTipCalibrationSubmissionOutcome {
  var isRegionRefused: Bool { if case .refused = self { return true }; return false }
}
