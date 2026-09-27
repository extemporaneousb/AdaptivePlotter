import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing
@testable import PlotterApp

@Suite("Portrait drawing plane preview", .serialized)
@MainActor
struct PortraitPlanePreviewTests {
  @Test("sealed plans render stored machine paths without borrowing the current authored program",
    arguments: [0.0, 90.0, 37.0])
  func exactPlanOnlyGeometry(rotation: Double) throws {
    let fixture = try PlanePreviewFixture(rotation: rotation)
    let first = try #require(fixture.plan.strokes.first)
    let start = first.path.points[0], end = first.path.points[1]
    // A shortened admitted segment must remain shortened in the preview. The
    // authored rectangle still contains its full original stroke.
    let midpoint = try Point2<MachineSpace>(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    let shortened = PlannedMachineStroke(logicalStrokeID: first.logicalStrokeID,
      path: try Polyline(points: [start, midpoint]), style: first.style,
      semanticRole: first.semanticRole, ordering: first.ordering,
      endingCheckpointID: first.endingCheckpointID)
    let plan = try ExecutionPlanRevision(sourceProgramID: fixture.plan.sourceProgramID,
      sourceProgramContentHash: fixture.plan.sourceProgramContentHash,
      placement: fixture.plan.placement, drawableRegion: fixture.region,
      provenance: fixture.plan.provenance,
      strokes: [shortened] + Array(fixture.plan.strokes.dropFirst()), checkpoints: fixture.plan.checkpoints)
    let preview = PortraitPlanePreview.planned(plan)
    #expect(preview.program == nil)
    #expect(preview.plannedStrokes == plan.strokes)
    #expect(preview.evidence?.planContentHash == plan.contentHash.description)
    let geometry = try #require(preview.geometry(in: CGSize(width: 600, height: 600)))
    let bounds = fixture.region.effectiveBounds
    for (path, stroke) in zip(geometry.paths, plan.strokes) {
      #expect(path.count == stroke.path.points.count)
      for (screen, machine) in zip(path, stroke.path.points) {
        #expect(abs(screen.x - (machine.x - bounds.minX) * 3) < 1e-10)
        #expect(abs(screen.y - (480 - (machine.y - bounds.minY) * 3)) < 1e-10)
      }
    }
    #expect(geometry.paths.first?.count == 2)
    #expect(geometry.regionRect == CGRect(x: 0, y: 120, width: 600, height: 360))
  }

  @Test("Drawing preview prefers retained run geometry over later draft and authoring changes")
  func retainedRunPreviewOwnership() throws {
    let run = try PlanePreviewFixture(rotation: 37)
    let newerDraft = try PlanePreviewFixture(rotation: 90)
    let retained = try #require(DrawingStudioPreview.resolve(draftProgram: newerDraft.program,
      draftPlan: newerDraft.plan, retainedPlan: run.plan, runOwnsPlan: true))
    #expect(retained.title == "Run drawing")
    #expect(retained.plan == run.plan)
    #expect(retained.plane.plannedStrokes == run.plan.strokes)
    #expect(retained.plane.evidence?.placement == run.plan.placement)
    #expect(DrawingStudioPreview.resolve(draftProgram: newerDraft.program,
      draftPlan: newerDraft.plan, retainedPlan: nil, runOwnsPlan: true) == nil)
    let idle = try #require(DrawingStudioPreview.resolve(draftProgram: newerDraft.program,
      draftPlan: newerDraft.plan, retainedPlan: run.plan, runOwnsPlan: false))
    #expect(idle.title == "Planned drawing")
    #expect(idle.plan == newerDraft.plan)
    let reference = try #require(DrawingStudioPreview.resolve(draftProgram: newerDraft.program,
      draftPlan: nil, retainedPlan: nil, runOwnsPlan: false))
    #expect(reference.title == "Reference drawing")
    #expect(reference.plan == nil)
    #expect(reference.plane.evidence?.mode == .reference)
    #expect(reference.plane.actualDrawingHeightMM == nil)
    #expect(reference.plane.geometry(in: CGSize(width: 270, height: 160)) != nil)
  }

  @Test("Camera Fit contains corrected field corners in a translated narrow region",
    arguments: [0.0, 90.0, 37.0])
  func cameraFit(rotation: Double) throws {
    let camera = try DrawingCameraGeometry(cameraFromMachine: .init(
      m11: -1.7, m12: 0.2, m21: 0.04, m22: -1.34, tx: 1600, ty: 280))
    let region = try DrawableMachineRegion(bounds: AxisAlignedBounds(minX: 100, minY: -90, maxX: 310, maxY: -10))
    let extent = try Size2<FieldSpace>(width: 100, height: 160)
    let scale = PlotterDrawingPlanningAdapter.scaleRange(extent: extent, rotationDegrees: rotation,
      region: region, cameraGeometry: camera).upperBound
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 50, y: 80), machineAnchor: Point2(x: 205, y: -50),
      uniformScale: scale, rotationRadians: rotation * .pi / 180, cameraGeometry: camera)
    let field = try AxisAlignedBounds<FieldSpace>(minX: 0, minY: 0, maxX: 100, maxY: 160)
    let points = try field.corners.map { try placement.applying(to: $0) }
    #expect(points.allSatisfy { region.contains($0) })
    let width = try #require(points.map(\.x).max()) - #require(points.map(\.x).min())
    let height = try #require(points.map(\.y).max()) - #require(points.map(\.y).min())
    #expect(abs(max(width / 210, height / 80) - 1.0) < 1e-12)
  }

  @Test("Camera preview preserves proportions, shows the projected region, and replays its saved mapping",
    arguments: [0.0, 90.0, 37.0])
  func cameraGeometryAndHistoricalReplay(rotation: Double) throws {
    let camera = try DrawingCameraGeometry(cameraFromMachine: .init(
      m11: -1.7, m12: 0.2, m21: 0.04, m22: -1.34, tx: 1600, ty: 280))
    let fixture = try PlanePreviewFixture(rotation: rotation, cameraGeometry: camera)
    let preview = fixture.source.resolve(program: fixture.program, nominalWidth: 0.4)
    let size = CGSize(width: 600, height: 600)
    let rendered = try #require(preview.geometry(in: size))
    #expect(rendered.regionOutline?.count == 4)
    #expect(preview.statusText.contains("Camera-proportioned"))
    let scale = fixture.plan.placement.uniformScale * camera.referencePixelsPerUnit * rendered.screenScale
    for (source, screen) in zip(fixture.program.strokes, rendered.paths) {
      for index in screen.indices.dropFirst() {
        let expected = source.path.points[index - 1].distance(to: source.path.points[index]) * scale
        #expect(abs(hypot(screen[index].x - screen[index - 1].x,
          screen[index].y - screen[index - 1].y) - expected) < 1e-9)
      }
    }
    let context = try #require(preview.presentationContext)
    #expect(context.rendererRevision == "portrait-camera-preview-v3")
    try context.validateDisplayEvidence(program: fixture.program)
    let saved = try JSONDecoder().decode(PortraitPresentationContext.self, from: JSONEncoder().encode(context))
    let replay = try #require(PortraitPlanePreview.historical(program: fixture.program, presentation: saved).geometry(in: size))
    #expect(replay.paths == rendered.paths)
    #expect(replay.regionOutline == rendered.regionOutline)
    #expect(replay.lineWidth == rendered.lineWidth)
    #expect(preview.materialReferenceHeight == fixture.program.fieldExtent.height * fixture.plan.placement.minimumScale)
    let sourcePoints: [Point2<FieldSpace>] = try [Point2(x: 0, y: 0), Point2(x: 40, y: 0),
      Point2(x: 0, y: 40), Point2(x: 30, y: 20)]
    let origin = try fixture.plan.placement.applying(to: sourcePoints[0])
    let expectedHeight = try #require(preview.actualDrawingHeightMM)
    for point in sourcePoints.dropFirst() {
      let target = try fixture.plan.placement.applying(to: point)
      let recoveredHeight = try cameraArtworkControllerHeight(sourceDelta: sourcePoints[0].vector(to: point),
        machineDelta: origin.vector(to: target), fieldHeight: fixture.program.fieldExtent.height, camera: camera)
      #expect(abs(recoveredHeight - expectedHeight) < 1e-9)
    }
  }

  @Test("Translated non-square region maps exact planned points with one scale at every authored rotation",
    arguments: [0.0, 90.0, 37.0])
  func plannedGeometry(rotation: Double) throws {
    let fixture = try PlanePreviewFixture(rotation: rotation)
    let preview = fixture.source.resolve(program: fixture.program, nominalWidth: 9)
    let geometry = try #require(preview.geometry(in: CGSize(width: 600, height: 600)))
    #expect(geometry.regionRect == CGRect(x: 0, y: 120, width: 600, height: 360))
    #expect(abs(preview.aspectRatio - 200.0 / 120) < 1e-12)
    #expect(geometry.screenScale == 3)
    #expect(preview.actualDrawingWidthMM == fixture.program.fieldExtent.width * 0.5)
    #expect(preview.actualDrawingHeightMM == fixture.program.fieldExtent.height * 0.5)
    #expect(abs(geometry.lineWidth - 0.4 * geometry.screenScale) < 1e-12)
    #expect(preview.evidence?.mode == .planned)
    #expect(preview.evidence?.planContentHash == fixture.plan.contentHash.description)
    #expect(preview.statusText.contains("physical dimensions unverified"))
    let bounds = fixture.region.effectiveBounds
    for (rendered, stroke) in zip(geometry.paths, fixture.plan.strokes) {
      #expect(rendered.count == stroke.path.points.count)
      for (screen, machine) in zip(rendered, stroke.path.points) {
        #expect(abs(screen.x - (machine.x - bounds.minX) * 3) < 1e-10)
        #expect(abs(screen.y - (480 - (machine.y - bounds.minY) * 3)) < 1e-10)
      }
      for index in 1..<rendered.count {
        let a = stroke.path.points[index - 1], b = stroke.path.points[index]
        let s = rendered[index - 1], t = rendered[index]
        #expect(abs(hypot(t.x - s.x, t.y - s.y) - hypot(b.x - a.x, b.y - a.y) * 3) < 1e-10)
      }
    }
    // The off-centre anchor must remain offset; fitting artwork to its own box
    // would erase this deliberate placement inside the larger drawing plane.
    let anchor = fixture.plan.placement.machineAnchor
    #expect(anchor.x != (bounds.minX + bounds.maxX) / 2)
    #expect(anchor.y != (bounds.minY + bounds.maxY) / 2)
    let presentation = try #require(preview.presentationContext)
    try presentation.validateDisplayEvidence(program: fixture.program)
    #expect(presentation.displayEvidence?.placement == fixture.plan.placement)
  }

  @Test("Mismatched program or region and missing plan use explicit reference geometry without actual dimensions")
  func unmatchedAndMissingInputs() throws {
    let fixture = try PlanePreviewFixture()
    let other = try DrawingProgramCatalog.program(for: .square, style: fixture.program.strokes[0].style)
    let otherRegion = try DrawableMachineRegion(bounds: AxisAlignedBounds(minX: -300, minY: -200, maxX: -80, maxY: -80))
    let inputs: [(PortraitPlanePreviewSource, DrawingProgram)] = [
      (fixture.source, other),
      (.init(region: otherRegion, artworkPlan: fixture.plan), fixture.program),
      (.init(region: fixture.region), fixture.program),
      (.init(artworkPlan: fixture.plan), fixture.program),
      (.init(), fixture.program),
    ]
    for (source, program) in inputs {
      let preview = source.resolve(program: program, nominalWidth: 8)
      #expect(preview.evidence?.mode == .reference)
      #expect(preview.plannedStrokes == nil)
      #expect(preview.actualDrawingWidthMM == nil && preview.actualDrawingHeightMM == nil)
      #expect(preview.geometry(in: CGSize(width: 500, height: 350)) != nil)
      #expect(preview.statusText.contains("reference preview"))
      let context = try #require(preview.presentationContext)
      #expect(context.displayEvidence?.placement == nil)
      #expect(context.displayEvidence?.planContentHash == nil)
      #expect(context.drawingHeightMM == 100) // v2 reference normalization, not physical size.
      try context.validateDisplayEvidence(program: program)
    }
    let absent = fixture.source.resolve(program: nil, nominalWidth: 0.7)
    #expect(absent.evidence == nil && absent.presentationContext == nil)
    #expect(absent.geometry(in: CGSize(width: 500, height: 350)) == nil)
    #expect(absent.actualDrawingHeightMM == nil)
    let valid = fixture.source.resolve(program: fixture.program, nominalWidth: 0.7)
    for size in [CGSize.zero, CGSize(width: -1, height: 10), CGSize(width: CGFloat.infinity, height: 10)] {
      #expect(valid.geometry(in: size) == nil)
    }
  }

  @Test("Reference ratings retain the display context without inventing a placed drawing height")
  func referenceRating() throws {
    let candidate = try portraitPersistenceCandidate()
    let preview = PortraitPlanePreviewSource().resolve(program: candidate.program, nominalWidth: 0.4)
    let presentation = try #require(preview.presentationContext)
    let label = try PortraitLabelRevision(candidate: candidate, rating: 1, scope: .screenSketch, presentation: presentation)
    #expect(preview.actualDrawingHeightMM == nil)
    #expect(label.presentation.displayEvidence?.mode == .reference)
    #expect(label.presentation.rendererRevision == "portrait-plane-preview-v2")
    #expect(try JSONDecoder().decode(PortraitLabelRevision.self,
      from: PortraitCandidateCoding.encoder().encode(label)) == label)
  }

  @Test("Saved geometry and material width remain immutable when live placement and active material change")
  func historicalPresentation() throws {
    let first = try PlanePreviewFixture(rotation: 37)
    let profile = try DrawingMaterialProfileRevision(name: "Saved nominal marker", nominalWidthMM: 1.25)
    let original = PortraitPlanePreviewSource(region: first.region, artworkPlan: first.plan, material: profile)
      .resolve(program: first.program, nominalWidth: 0.4)
    let presentation = try #require(original.presentationContext)
    let encoded = try PortraitCandidateCoding.encoder().encode(presentation)
    let restored = try JSONDecoder().decode(PortraitPresentationContext.self, from: encoded)
    let saved = PortraitPlanePreview.historical(program: first.program, presentation: restored)
    let before = try #require(original.geometry(in: CGSize(width: 600, height: 600)))
    let historical = try #require(saved.geometry(in: CGSize(width: 600, height: 600)))
    #expect(historical.paths == before.paths)
    #expect(historical.regionRect == before.regionRect)
    #expect(historical.lineWidth == before.lineWidth)
    #expect(saved.presentationContext == presentation)
    #expect(saved.materialRevision == profile.key)
    #expect(saved.inkDescription.contains("Saved material width"))
    let second = try PlanePreviewFixture(rotation: 90, program: first.program)
    let changed = try PortraitPlanePreviewSource(region: second.region, artworkPlan: second.plan,
      material: DrawingMaterialProfileRevision(name: "New nominal marker", nominalWidthMM: 3))
      .resolve(program: first.program, nominalWidth: 0.4)
    #expect(changed.evidence?.planContentHash != saved.evidence?.planContentHash)
    #expect(changed.materialRevision != saved.materialRevision)
    #expect(changed.inkWidthMM != saved.inkWidthMM)
    #expect(saved.geometry(in: CGSize(width: 600, height: 600)).map { $0.paths } == historical.paths)
    #expect(saved.presentationContext == presentation)
    #expect(try PortraitCandidateCoding.encoder().encode(restored) == encoded)
    let unrelated = try DrawingProgramCatalog.program(for: .triangle, style: first.program.strokes[0].style)
    let mismatched = PortraitPlanePreview.historical(program: unrelated, presentation: presentation)
    #expect(mismatched.geometry(in: CGSize(width: 600, height: 600)) == nil)
    #expect(mismatched.statusText == "Saved preview context unavailable")
  }

  @Test("Applicable material sets one physical line width and unavailable material falls back to the program nominal width")
  func widthSources() throws {
    let fixture = try PlanePreviewFixture()
    let distribution = try DepositedWidthDistribution(medianMM: 1, lowerBoundMM: 0.8,
      upperBoundMM: 1.2, uncertaintyMM: 0.1, sampleCount: 10)
    let measured = try DrawingMaterialProfileRevision(name: "Synthetic measured width", nominalWidthMM: 0.6,
      qualification: .controllerCoordinateEstimate, depositedWidth: distribution, measurementEvidenceID: UUID())
    let preview = PortraitPlanePreviewSource(region: fixture.region, artworkPlan: fixture.plan, material: measured)
      .resolve(program: fixture.program, nominalWidth: 9)
    #expect(abs(preview.inkWidthMM - 1.3) < 1e-12)
    #expect(!preview.inkWidthIsMeasured) // A controller-coordinate estimate is not independent physical measurement.
    #expect(preview.evidence?.widthSource == .applicableMaterial)
    #expect(abs(try #require(preview.geometry(in: CGSize(width: 600, height: 600))).lineWidth - 3.9) < 1e-12)
    let unavailable = try DrawingMaterialProfileRevision(name: "Unavailable", nominalWidthMM: 5, qualification: .unavailable)
    let fallback = PortraitPlanePreviewSource(region: fixture.region, artworkPlan: fixture.plan, material: unavailable,
      materialUnavailableReason: "Current geometry differs").resolve(program: fixture.program, nominalWidth: 9)
    #expect(fallback.inkWidthMM == fixture.program.strokes[0].style.nominalLineWidth)
    #expect(fallback.evidence?.widthSource == .nominalProgram)
    #expect(fallback.inkDescription.contains("Current geometry differs"))
  }

  @Test("Production Draft retains the source artwork plan through border composition, rotation and scale; stale material and missing geometry cannot masquerade as current")
  func productionDraftAndMaterial() async throws {
    let materials = DrawingMaterialLibrary()
    #expect(materials.createNominal(name: "Preview fixture marker", widthMM: 0.8) == nil)
    let fixture = try await DrawingWorkbenchApplicationFixture.make(drawingMaterials: materials, verifyPhysicalPose: false)
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let program = try DrawingProgramCatalog.program(for: .rectangle, style: app.drawingStrokeStyle)
      let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
        manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
      let request = try #require(projection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
      #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
      try await fixture.submit(.fitInDrawableRegion)
      try await fixture.submit(.setUniformScale(0.2))
      try await fixture.submit(.setRotationDegrees(37))
      try await fixture.submit(.centerInDrawableRegion)
      if app.drawingDraftSnapshot.drawBorder { try await fixture.submit(.setDrawBorder(false)) }
      let plain = try #require(app.drawingDraftSnapshot.artworkPlan)
      #expect(plain.sourceProgramContentHash == program.contentHash)
      #expect(plain.placement.uniformScale == 0.2)
      #expect(abs(plain.placement.rotationRadians - 37 * .pi / 180) < 1e-12)
      #expect(app.drawingDraftSnapshot.plan == plain)
      try await fixture.submit(.setDrawBorder(true))
      let artwork = try #require(app.drawingDraftSnapshot.artworkPlan)
      let execution = try #require(app.drawingDraftSnapshot.plan)
      #expect(artwork == plain)
      #expect(execution.sourceProgramContentHash != program.contentHash)
      #expect(execution.strokes.count == artwork.strokes.count + 1)
      let preview = app.portraitPlanePreviewSource.resolve(program: program, nominalWidth: 0.4)
      #expect(preview.evidence?.planContentHash == artwork.contentHash.description)
      #expect(preview.plannedStrokes == artwork.strokes)
      #expect(preview.materialProfile == materials.activeRecord?.profile)
      app.materialPaperStock = "Preview fixture paper"
      app.drawingMaterialSelectionDidChange()
      let measured = try await makeStudioCampaignMeasuredMaterial(fixture)
      let eligible = app.portraitPlanePreviewSource.resolve(program: program, nominalWidth: 0.4)
      #expect(eligible.materialRevision == measured.profile.key)
      #expect(eligible.inkWidthMM == measured.profile.conservativeWidthMM)
      app.materialPaperStock = "Different preview fixture paper"
      app.drawingMaterialSelectionDidChange()
      let stale = app.portraitPlanePreviewSource.resolve(program: program, nominalWidth: 0.4)
      #expect(stale.materialProfile == nil)
      #expect(stale.inkWidthMM == program.strokes[0].style.nominalLineWidth)
      #expect(stale.materialUnavailableReason != nil)
      await submitObservationConfigurationForTest(app, .selectSource(.simulated, nil))
      await app.drawingDraftSynchronizationTask?.value
      #expect(app.drawingDraftSnapshot.plan == nil)
      #expect(app.drawingDraftSnapshot.artworkPlan == nil)
      #expect(app.portraitPlanePreviewSource.resolve(program: program, nominalWidth: 0.4).actualDrawingHeightMM == nil)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
}

private struct PlanePreviewFixture {
  let program: DrawingProgram
  let region: DrawableMachineRegion
  let plan: ExecutionPlanRevision
  var source: PortraitPlanePreviewSource { .init(region: region, artworkPlan: plan) }
  init(rotation: Double = 0, program: DrawingProgram? = nil, cameraGeometry: DrawingCameraGeometry? = nil) throws {
    self.program = try program ?? DrawingProgramCatalog.program(for: .rectangle,
      style: StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID()))
    region = try DrawableMachineRegion(bounds: AxisAlignedBounds(minX: -310, minY: -210, maxX: -90, maxY: -70), edgeClearance: 10)
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: self.program.fieldExtent.width / 2, y: self.program.fieldExtent.height / 2),
      machineAnchor: Point2(x: -185, y: -135), uniformScale: 0.5, rotationRadians: rotation * .pi / 180,
      cameraGeometry: cameraGeometry)
    let hash = self.program.contentHash
    plan = try DrawingPlanner.plan(program: self.program, placement: placement, drawableRegion: region,
      provenance: DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(), modelContentHash: hash,
        registrationRevisionID: DrawingRegistrationRevisionID(), registrationContentHash: hash))
  }
}
