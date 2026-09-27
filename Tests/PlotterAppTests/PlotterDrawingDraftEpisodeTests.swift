import CoreGraphics
import CryptoKit
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Drawing Studio draft episode", .serialized)
@MainActor
struct PlotterDrawingDraftEpisodeTests {
  @Test("unsealed preview preserves accepted paper context without manufacturing exact evidence")
  func unsealedPreviewPreservesPaperContext() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100))
    let opened = try await open(runtime, facts: fixture.facts())
    let asserted = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .assertPaperCoverage), facts: fixture.facts()))
    let original = fixture.frame.frame
    let unsealed = try DisplayedFrame(source: fixture.frame.source,
      frame: StampedFrame(sequence: original.sequence + 1, captureNanoseconds: original.captureNanoseconds + 1,
        cameraConfigurationID: original.cameraConfigurationID, width: original.width, height: original.height,
        rowBytes: original.rowBytes, pixelFormat: original.pixelFormat, bytes: original.bytes,
        eagerlyMaterializeContentHash: false))
    let facts = fixture.facts(displayedFrame: unsealed)
    #expect(facts.displayedFrame == nil)
    let next = await runtime.synchronize(facts)
    #expect(next.paperCoverageIsCurrent)
    #expect(next.plan == asserted.plan)
    #expect(next.paperCoverageObservation == asserted.paperCoverageObservation)
    #expect(next.paperCoverageDisplay == nil)
    #expect(!unsealed.frame.contentHashIsMaterialized)
    let app = makeCausalSimulatorAppFixture()
    #expect(try app.workspace.cameraOpticalConfiguration(for: unsealed)
      == app.workspace.cameraOpticalConfiguration(for: fixture.frame))
    #expect(!unsealed.frame.contentHashIsMaterialized)
    await app.workspace.shutdown()
    let changedSource = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "other")), frame: unsealed.frame)
    #expect(!(await runtime.synchronize(fixture.facts(displayedFrame: changedSource))).paperCoverageIsCurrent)
    let changedPaper = await runtime.synchronize(fixture.facts(paper: .init(
      instance: PaperInstanceRevision(), contactPlane: fixture.paper.contactPlane)))
    #expect(!changedPaper.paperCoverageIsCurrent)
  }

  @Test("framed portraits preserve candidate source identity")
  func framedDrawingRetainsOriginalArtwork() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let style = try StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue))
    let program = try DrawingProgramCatalog.program(for: .square, style: style)
    let built = PlotterDrawingPlanningAdapter.buildDraft(program: program,
      machineCenter: nil,
      uniformScale: 0.02, rotationDegrees: 30, drawableRegion: fixture.drawableRegion,
      registration: fixture.registration, drawBorder: true)
    let execution = try #require(built.program)
    let plan = try #require(built.plan)
    let reference = DrawingRunCandidateReference(candidateID: program.contentHash.description,
      contentHash: program.contentHash, sourceProgram: program)
    #expect(reference.matches(execution))
    #expect(execution.strokes.dropFirst().map(\.id) == program.strokes.map(\.id))
    #expect(execution.strokes.dropFirst().map { $0.path.points.count } == program.strokes.map { $0.path.points.count })
    #expect(plan.sourceProgramContentHash == execution.contentHash)
    #expect(plan.strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
    #expect(plan.strokes.first?.path.points.count == 5)
    #expect(plan.strokes.dropFirst().map(\.logicalStrokeID) == program.strokes.map(\.id))
    #expect(execution.fieldExtent == program.fieldExtent)
  }

  @Test("metric and coverage targets retain strict boundary rejection")
  func calibrationTargetsDoNotClip() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let style = try StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue))
    let metric = try DrawingProgramCatalog.program(for: .metricSquare40, style: style)
    let coverage = try DrawingProgram(id: ProgramID(), fieldExtent: metric.fieldExtent,
      strokes: metric.strokes, source: .init(kind: "adaptive-coverage-v1", sourceIdentifier: "strict-test"))
    let bounds = fixture.drawableRegion.effectiveBounds
    for program in [metric, coverage] {
      let built = PlotterDrawingPlanningAdapter.buildDraft(program: program,
        machineCenter: try Point2(x: bounds.minX, y: (bounds.minY + bounds.maxY) / 2),
        uniformScale: 0.2, rotationDegrees: 30, drawableRegion: fixture.drawableRegion,
        registration: fixture.registration)
      #expect(built.plan == nil)
      #expect(built.failure != nil)
    }
  }

  @Test("Center uses the authored frame despite asymmetric ink and repeats without drift", arguments: [false, true])
  func centerAuthoredFrame(drawBorder: Bool) async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    let style = try #require(snapshot.program?.strokes.first?.style)
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100),
      strokes: [.init(id: StrokeID(), path: .init(points: [Point2(x: 60, y: 20),
        Point2(x: 90, y: 25), Point2(x: 65, y: 30)]), style: style, ordering: 0)],
      source: .init(kind: "test", sourceIdentifier: "asymmetric-ink"))
    let intents: [PlotterDrawingDraftIntent] = [.selectProgram(program), .setRotationDegrees(47),
      .setDrawBorder(drawBorder), .centerInDrawableRegion]
    for intent in intents {
      snapshot = try applied(await runtime.submit(.init(projection: snapshot.projection, intent: intent), facts: facts))
    }
    let plan = try #require(snapshot.artworkPlan)
    let points = try DrawingFrameGeometry(extent: program.fieldExtent, placement: plan.placement).machineCorners
    let bounds = fixture.drawableRegion.effectiveBounds
    #expect(abs(points.map(\.x).min()! + points.map(\.x).max()! - bounds.minX - bounds.maxX) < 1e-9)
    #expect(abs(points.map(\.y).min()! + points.map(\.y).max()! - bounds.minY - bounds.maxY) < 1e-9)
    let repeated = try applied(await runtime.submit(.init(projection: snapshot.projection,
      intent: .centerInDrawableRegion), facts: facts))
    #expect(repeated.machineCenter == snapshot.machineCenter)
    #expect(repeated.artworkPlan == snapshot.artworkPlan)
    #expect(repeated.uniformScale == snapshot.uniformScale)
    #expect(repeated.rotationDegrees == 47)
  }

  @Test("rotation preserves the whole authored frame inside Boundary at every angle")
  func rotationContainsFrame() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    snapshot = try applied(await runtime.submit(.init(projection: snapshot.projection,
      intent: .fitInDrawableRegion), facts: facts))
    let scale = snapshot.uniformScale
    for degrees in stride(from: -180.0, through: 180.0, by: 15.0) {
      snapshot = try applied(await runtime.submit(.init(projection: snapshot.projection,
        intent: .setRotationDegrees(degrees)), facts: facts))
      let plan = try #require(snapshot.plan)
      #expect(snapshot.uniformScale <= scale)
      #expect(snapshot.allowedScale.contains(snapshot.uniformScale))
      #expect(try #require(snapshot.frame).geometry.isContained(in: fixture.drawableRegion))
      #expect(plan.strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
      #expect(snapshot.planningRefusal == nil)
    }
  }

  @Test("optional border shares plan identity, preview and containment while calibration stays independent")
  func optionalBorderIsCanonicalOrdinaryGeometry() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    #expect(!opened.drawBorder)
    let original = try #require(opened.plan)
    let bordered = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .setDrawBorder(true)), facts: facts))
    let plan = try #require(bordered.plan)
    #expect(bordered.drawBorder)
    #expect(bordered.evidenceRole == .ordinaryDrawing)
    #expect(plan.revisionID != original.revisionID)
    #expect(bordered.program?.contentHash != opened.program?.contentHash)
    #expect(plan.sourceProgramContentHash == bordered.program?.contentHash)
    #expect(plan.strokes.count == original.strokes.count + 1)
    #expect(plan.checkpoints.count == plan.strokes.count)
    for (composed, source) in zip(plan.strokes.dropFirst(), original.strokes) {
      #expect(composed.path.points.count == source.path.points.count)
      #expect(zip(composed.path.points, source.path.points).allSatisfy { $0.distance(to: $1) < 1e-10 })
    }
    #expect(plan.strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
    #expect(bordered.preview?.strokes.count == plan.strokes.count)
    let border = try #require(plan.strokes.first)
    #expect(border.path.points.first == border.path.points.last)
    #expect(border.semanticRole == .drawing)
    let fitted = try applied(await runtime.submit(.init(projection: bordered.projection,
      intent: .fitInDrawableRegion), facts: facts))
    #expect(fitted.plan!.strokes.first!.path != border.path)
    let fittedCorners = try #require(fitted.frame).geometry.machineCorners
    #expect(zip(fitted.plan!.strokes.first!.path.points, fittedCorners + [fittedCorners[0]])
      .allSatisfy { $0.distance(to: $1) < 1e-9 })
    #expect(fitted.projection.externalFacts.drawingBorderBounds == opened.projection.externalFacts.drawingBorderBounds)
    let restored = try applied(await runtime.submit(.init(projection: fitted.projection,
      intent: .setDrawBorder(false)), facts: facts))
    #expect(restored.program == opened.program)
    #expect(restored.plan?.strokes.count == original.strokes.count)
    #expect(restored.projection.externalFacts.registrationRevisionID == opened.projection.externalFacts.registrationRevisionID)
  }

  @Test("a new drawing defaults border off while edits preserve its explicit choice")
  func newDrawingDefaultsBorderOff() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let selected = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .setDrawBorder(true)), facts: facts))
    let edited = try applied(await runtime.submit(.init(projection: selected.projection,
      intent: .centerInDrawableRegion), facts: facts))
    #expect(edited.drawBorder)
    let next = try applied(await runtime.submit(.init(projection: edited.projection,
      intent: .beginNewPlan), facts: facts))
    #expect(!next.drawBorder)
    #expect(next.placementID != edited.placementID)
    #expect(next.program == opened.program)
    #expect(next.plan?.strokes.count == opened.plan?.strokes.count)
    #expect(next.projection.externalFacts.registrationRevisionID == opened.projection.externalFacts.registrationRevisionID)
  }

  @Test("border selection cannot mutate active or retained terminal drawings", arguments: [false, true])
  func optionalBorderRespectsRunOwnership(terminal: Bool) async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let opened = try await open(runtime, facts: fixture.facts())
    let facts = fixture.facts(runInProgress: !terminal, terminalRequiresNewPlan: terminal)
    let result = await runtime.submit(.init(projection: opened.projection,
      intent: .setDrawBorder(true)), facts: facts)
    #expect(try refusal(result).reason == (terminal ? .terminalRunRequiresHandoff : .retainedRunOwnsMutation))
    #expect(!result.snapshot.drawBorder)
    #expect(result.snapshot.plan?.revisionID == opened.plan?.revisionID)
  }

  @Test("a frame outside Boundary cannot bypass planning even when its ink is sparse")
  func frameContainmentFailure() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let program = try DrawingProgramCatalog.program(for: .circle,
      style: StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue)))
    let bounds = fixture.drawableRegion.effectiveBounds
    let built = PlotterDrawingPlanningAdapter.buildDraft(program: program,
      machineCenter: try Point2(x: bounds.minX, y: (bounds.minY + bounds.maxY) / 2),
      uniformScale: 0.02, rotationDegrees: 0, drawableRegion: fixture.drawableRegion,
      registration: fixture.registration, drawBorder: true)
    #expect(built.plan == nil)
    #expect(built.failure != nil)
  }

  @Test("automatic fit keeps upright when it wins or the orientations tie", arguments: [false, true])
  func uprightAndTieFit(square: Bool) async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let opened = try await open(runtime, facts: fixture.facts())
    let style = try #require(opened.program?.strokes.first?.style)
    let bounds = fixture.drawableRegion.effectiveBounds
    let isWide = bounds.maxX - bounds.minX > bounds.maxY - bounds.minY
    let width = square || isWide ? 100.0 : 20.0
    let height = square || !isWide ? 100.0 : 20.0
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: width, height: height),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: [
        Point2(x: 0, y: 0), Point2(x: width, y: 0), Point2(x: width, y: height),
        Point2(x: 0, y: height), Point2(x: 0, y: 0)]), style: style, ordering: 0)],
      source: DrawingSourceProvenance(kind: "portrait-fit-test", sourceIdentifier: square ? "tie" : "upright"))
    let selected = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .selectProgram(program)), facts: fixture.facts()))
    let fitted = try applied(await runtime.submit(.init(projection: selected.projection,
      intent: .fitInDrawableRegion), facts: fixture.facts()))
    #expect(fitted.rotationDegrees == 0)
    #expect(fitted.uniformScale == fitted.allowedScale.upperBound)
    #expect(try #require(fitted.plan).strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
  }

  @Test("Fit retains explicit rotation and creates a new immutable plan", arguments: [30.0, 90.0, -45.0])
  func fitRetainsExplicitRotation(degrees: Double) async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let rotated = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .setRotationDegrees(degrees)), facts: facts))
    let before = rotated.plan
    let fitted = try applied(await runtime.submit(.init(projection: rotated.projection,
      intent: .fitInDrawableRegion), facts: facts))
    #expect(fitted.rotationDegrees == degrees)
    #expect(fitted.uniformScale == fitted.allowedScale.upperBound)
    let plan = try #require(fitted.plan)
    #expect(abs(plan.placement.rotationRadians - degrees * .pi / 180) < 1e-12)
    #expect(plan.strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
    #expect(rotated.plan == before)
    #expect(fitted.placementID != rotated.placementID)
    #expect(try JSONDecoder().decode(ExecutionPlanRevision.self,
      from: JSONEncoder().encode(plan)) == plan)
  }

  @Test("artwork preserves camera proportions and metric targets preserve command distances through Fit and border")
  func primitiveMetricThroughPlanAndBorder() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let style = try StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue))
    for size in [(240.0, 120.0), (100.0, 250.0), (160.0, 160.0)] {
      let region = try DrawableMachineRegion(bounds: AxisAlignedBounds(
        minX: -30, minY: 40, maxX: -30 + size.0, maxY: 40 + size.1))
      for entry in DrawingCatalogEntryID.allCases {
        let program = try DrawingProgramCatalog.program(for: entry, style: style)
        let cameraGeometry = try PlotterDrawingPlanningAdapter.cameraGeometry(for: program, registration: fixture.registration)
        for angle in [0.0, 30.0, 90.0, -45.0] {
          let scale = PlotterDrawingPlanningAdapter.scaleRange(extent: program.fieldExtent,
            rotationDegrees: angle, region: region, cameraGeometry: cameraGeometry).upperBound
          let plain = PlotterDrawingPlanningAdapter.buildDraft(program: program,
            machineCenter: nil, uniformScale: scale, rotationDegrees: angle,
            drawableRegion: region, registration: fixture.registration)
          let plan = try #require(plain.plan)
          let bordered = PlotterDrawingPlanningAdapter.buildDraft(program: program,
            machineCenter: nil, uniformScale: scale, rotationDegrees: angle,
            drawableRegion: region, registration: fixture.registration,
            drawBorder: true)
          let borderPlan = try #require(bordered.plan)
          let reference = DrawingRunCandidateReference(candidateID: program.contentHash.description,
            contentHash: program.contentHash, sourceProgram: program)
          let executionProgram = try #require(bordered.program)
          #expect(reference.matches(executionProgram))
          if entry == .rectangle && angle == 0 {
            let first = executionProgram.strokes[1]
            var points = first.path.points
            points[2] = try Point2(x: points[2].x + 0.1, y: points[2].y)
            let distorted = LogicalStroke(id: first.id, path: try Polyline(points: points), style: first.style,
              semanticRole: first.semanticRole, ordering: first.ordering)
            let forged = try DrawingProgram(id: executionProgram.id, fieldExtent: executionProgram.fieldExtent,
              strokes: [executionProgram.strokes[0], distorted] + executionProgram.strokes.dropFirst(2), source: executionProgram.source)
            #expect(!reference.matches(forged))
          }
          #expect(borderPlan.strokes.count == plan.strokes.count + 1)
          for (plainStroke, borderedStroke) in zip(plan.strokes, borderPlan.strokes.dropFirst()) {
            #expect(plainStroke.path.points.count == borderedStroke.path.points.count)
            for (a, b) in zip(plainStroke.path.points, borderedStroke.path.points) {
              #expect(a.distance(to: b) < 1e-10)
            }
          }
          #expect(borderPlan.contentHash != plan.contentHash)
          #expect(plan.placement.cameraGeometry == cameraGeometry)
          func observed(_ point: Point2<MachineSpace>) throws -> Point2<CameraPixelSpace> {
            if let cameraGeometry { return try cameraGeometry.cameraFromMachine.applying(to: point) }
            return try Point2(x: point.x, y: point.y)
          }
          let imageScale = scale * (cameraGeometry?.referencePixelsPerUnit ?? 1)
          let origin = try observed(plan.placement.applying(to: Point2(x: 0, y: 0)))
          let x = try observed(plan.placement.applying(to: Point2(x: 1, y: 0)))
          let y = try observed(plan.placement.applying(to: Point2(x: 0, y: 1)))
          #expect(abs(origin.distance(to: x) - imageScale) < 1e-10)
          #expect(abs(origin.distance(to: y) - imageScale) < 1e-10)
          #expect(abs((x.x-origin.x)*(y.x-origin.x) + (x.y-origin.y)*(y.y-origin.y)) < 1e-10)
          for (source, placed) in zip(program.strokes, plan.strokes) {
            for index in source.path.points.indices.dropFirst() {
              let expected = source.path.points[index-1].distance(to: source.path.points[index]) * imageScale
              let actual = try observed(placed.path.points[index-1]).distance(to: observed(placed.path.points[index]))
              #expect(abs(actual - expected) < 1e-9)
            }
          }
        }
      }
    }
  }

  @Test("portrait fixture retains exact source through crop, plan and camera projection")
  func portraitGeometryTrace() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let width = 901, height = 1600
    let pixels = Data((0..<(width * height)).map { index in
      UInt8(index % width < width / 2 ? 0 : 255)
    })
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
      bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
      shouldInterpolate: false, intent: .defaultIntent))
    let source = try PortraitImageAnalyzer.encodedImage(image)
    let raster = try PortraitImageAnalyzer.analyze(data: source,
      options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false))
    let style = try StrokeStyle(nominalLineWidth: 0.4,
      penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue))
    let program = try PortraitVectorizer.program(from: raster, pose: .front,
      style: .contours, strokeStyle: style)
    let scale = try PlotterDrawingPlanningAdapter.scaleRange(extent: program.fieldExtent,
      rotationDegrees: 0, region: fixture.drawableRegion,
      cameraGeometry: PlotterDrawingPlanningAdapter.cameraGeometry(for: program, registration: fixture.registration)).upperBound
    let build = PlotterDrawingPlanningAdapter.buildDraft(program: program, machineCenter: nil,
      uniformScale: scale, rotationDegrees: 0, drawableRegion: fixture.drawableRegion,
      registration: fixture.registration)
    let plan = try #require(build.plan)
    let cameraPoints = try plan.strokes.flatMap { stroke in
      try stroke.path.points.map { try fixture.registration.cameraFromMachine.applying(to: $0) }
    }
    for (authored, planned) in zip(program.strokes, plan.strokes) {
      for (a, b) in zip(authored.path.points, planned.path.points) {
        #expect(try plan.placement.applying(to: a).distance(to: b) < 1e-10)
      }
    }
    if let directory = ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_GEOMETRY_EVIDENCE_DIRECTORY"] {
      let root = URL(fileURLWithPath: directory).appendingPathComponent("source-to-plan")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
      let assets: [(String, Data)] = [
        ("source.png", source), ("raster.json", try encoder.encode(raster)),
        ("program.json", try encoder.encode(program)), ("plan.json", try encoder.encode(plan)),
        ("registration.json", try encoder.encode(fixture.registration)),
        ("camera-points.json", try encoder.encode(cameraPoints))]
      var hashes: [String: String] = [:]
      for (name, bytes) in assets {
        try bytes.write(to: root.appendingPathComponent(name), options: .atomic)
        hashes[name] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      }
      hashes["evidenceClass"] = "synthetic source, simulated learned registration; software only"
      hashes["displayTransform"] = "ActionSurface camera pixel aspect-fit; uniform scale and translation"
      hashes["controllerTransform"] = "RunInterpreter plan deltas; MachineController G91 G21 three-decimal quantization"
      hashes["physicalMetric"] = "unmeasured; camera affine is not independent physical geometry"
      try encoder.encode(hashes).write(to: root.appendingPathComponent("trace.json"), options: .atomic)
    }
  }

  @Test("panel visibility survives preview advancement without admitting stale draft edits")
  func panelVisibilitySurvivesPreviewAdvancement() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let initial = await runtime.synchronize(fixture.facts())
    let next = try replacingFrame(fixture.frame, id: "open-preview", sequenceDelta: 1)
    let opened = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: initial.projection, intent: .showTarget),
      facts: fixture.facts(displayedFrame: next)))
    #expect(opened.isTargetVisible)
    let latest = try replacingFrame(fixture.frame, id: "close-preview", sequenceDelta: 2)
    let latestFacts = fixture.facts(displayedFrame: latest)
    let edit = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: opened.projection, intent: .assertPaperCoverage),
      facts: latestFacts)
    #expect(try refusal(edit).reason == .staleProjection)
    let closed = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: opened.projection, intent: .hideTarget),
      facts: latestFacts))
    #expect(!closed.isTargetVisible)
    let stale = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: initial.projection, intent: .showTarget),
      facts: latestFacts)
    #expect(try applied(stale).isTargetVisible)
    #expect(stale.snapshot.projection.draftRevision == initial.projection.draftRevision)
  }

  @Test("cancelled draft edits leave a held paper save promptly without cancelling its owner")
  func cancelledQueuedEditDoesNotWaitForPersistence() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(blocksSave: true)
    let runtime = PlotterDrawingDraftRuntime(paperPersistence: persistence,
      clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100))
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let owner = Task { await runtime.submit(.init(projection: opened.projection,
      intent: .assertPaperCoverage), facts: facts) }
    await persistence.waitUntilSaveStarted()
    let completion = DraftSubmissionInterleavingProbe()
    let waiter = Task {
      let result = await runtime.submit(.init(projection: opened.projection,
        intent: .setRotationDegrees(15)), facts: facts)
      await completion.markCompleted()
      return result
    }
    do { try await waitUntilAsync { await runtime.pendingMutationCount == 1 } }
    catch { await persistence.releaseSave(); _ = await owner.value; _ = await waiter.value; throw error }
    waiter.cancel()
    do { try await waitUntilAsync { await completion.completed } }
    catch { await persistence.releaseSave(); _ = await owner.value; throw error }
    #expect(try refusal(await waiter.value).reason == .cancelled)
    #expect(await runtime.pendingMutationCount == 0)
    #expect(await persistence.storedObservation == nil)
    await persistence.releaseSave()
    let saved = try applied(await owner.value)
    let edited = try applied(await runtime.submit(.init(projection: saved.projection,
      intent: .setRotationDegrees(15)), facts: facts))
    #expect(edited.rotationDegrees == 15)
    #expect(edited.paperCoverageObservation == saved.paperCoverageObservation)
  }

  @Test("portrait fit preserves authored orientation and survives camera restart")
  func portraitFitAndCameraRestart() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100))
    let opened = try await open(runtime, facts: fixture.facts())
    let style = try #require(opened.program?.strokes.first?.style)
    let bounds = fixture.drawableRegion.effectiveBounds
    let isWide = bounds.maxX - bounds.minX >= bounds.maxY - bounds.minY
    let width = isWide ? 20.0 : 100.0, height = isWide ? 100.0 : 20.0
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: width, height: height),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: [Point2(x: 0, y: 0),
        Point2(x: width, y: height)]), style: style, ordering: 0)],
      source: DrawingSourceProvenance(kind: "portrait-fit-test", sourceIdentifier: "opposite-aspect"))
    let selected = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .selectProgram(program)), facts: fixture.facts()))
    let fitted = try applied(await runtime.submit(.init(projection: selected.projection,
      intent: .fitInDrawableRegion), facts: fixture.facts()))
    #expect(fitted.rotationDegrees == 0)
    #expect(fitted.uniformScale == fitted.allowedScale.upperBound)
    #expect(try #require(fitted.plan).strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
    let asserted = try applied(await runtime.submit(.init(projection: fitted.projection,
      intent: .assertPaperCoverage), facts: fixture.facts()))
    let restartedFrame = try replacingFrame(fixture.frame, id: "new-capture-session",
      sequenceDelta: 10, cameraConfigurationID: CameraConfigurationID())
    let resumed = await runtime.synchronize(fixture.facts(displayedFrame: restartedFrame))
    #expect(resumed.paperCoverageIsCurrent)
    #expect(resumed.paperCoverageObservation == asserted.paperCoverageObservation)
    #expect(resumed.plan?.revisionID == asserted.plan?.revisionID)
    #expect(resumed.preview?.displayedFrame == restartedFrame)
    #expect(resumed.paperCoverageDisplay == nil)
    let newPaper = await runtime.synchronize(fixture.facts(paper: PaperRevisionContext(
      instance: PaperInstanceRevision(), contactPlane: fixture.paper.contactPlane)))
    #expect(!newPaper.paperCoverageIsCurrent)
  }

  @Test("ordinary authoring uses current facts across Learning and camera publication while retained runs keep their authority")
  func authoringSurvivesPreviewOnlyChanges() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let next = try replacingFrame(fixture.frame, id: "authoring-preview", sequenceDelta: 1)
    for intent: PlotterDrawingDraftIntent in [
      .selectCatalogItem(.circle), .setUniformScale(0.5), .setRotationDegrees(10),
      .setRotationDegrees(15), .centerInDrawableRegion,
    ] {
      let runtime = PlotterDrawingDraftRuntime()
      let opened = try await open(runtime, facts: fixture.facts())
      _ = try applied(await runtime.submit(
        PlotterDrawingDraftSubmission(projection: opened.projection, intent: intent),
        facts: fixture.facts(displayedFrame: next)))
    }

    let changedCamera = try replacingFrame(fixture.frame, id: "changed-camera",
      sequenceDelta: 2, cameraConfigurationID: CameraConfigurationID())
    for facts in [fixture.facts(displayedFrame: changedCamera), fixture.facts(learningComplete: false)] {
      let runtime = PlotterDrawingDraftRuntime()
      let opened = try await open(runtime, facts: fixture.facts())
      let result = try applied(await runtime.submit(
        PlotterDrawingDraftSubmission(projection: opened.projection, intent: .setUniformScale(0.5)),
        facts: facts))
      #expect(result.uniformScale == 0.5)
      #expect(result.projection.externalFacts == facts.revisions)
    }
    let runtime = PlotterDrawingDraftRuntime()
    let opened = try await open(runtime, facts: fixture.facts())
    let running = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: opened.projection, intent: .setUniformScale(0.5)),
      facts: fixture.facts(runInProgress: true))
    #expect(try refusal(running).reason == .retainedRunOwnsMutation)
    #expect(running.snapshot.uniformScale == opened.uniformScale)
  }

  @Test("large drawing geometry is derived once across preview and status changes")
  func unchangedGeometryIsNotReplanned() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let opened = try await open(runtime, facts: fixture.facts())
    let style = try #require(opened.program?.strokes.first?.style)
    let points: [Point2<FieldSpace>] = try (0...2_000).map { index in
      let angle = Double(index) * 2 * Double.pi / 2_000
      return try Point2(x: 50 + 40 * cos(angle), y: 50 + 40 * sin(angle))
    }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 100, height: 100),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: points), style: style, ordering: 0)],
      source: DrawingSourceProvenance(kind: "geometry-reuse-test", sourceIdentifier: "2001-point-circle"))
    let selected = try applied(await runtime.submit(
      .init(projection: opened.projection, intent: .selectProgram(program)), facts: fixture.facts()))
    let planID = try #require(selected.plan?.revisionID)
    let derivations = await runtime.derivationBuildCount
    for index in 1...120 {
      let nextFrame = try replacingFrame(fixture.frame, id: "cached-preview-\(index)",
        sequenceDelta: UInt64(index))
      let snapshot = await runtime.synchronize(fixture.facts(displayedFrame: nextFrame))
      #expect(snapshot.plan?.revisionID == planID)
      #expect(snapshot.preview?.displayedFrame.frame.id == nextFrame.frame.id)
      #expect(snapshot.preview?.strokes.first?.points.count == points.count)
    }
    _ = await runtime.synchronize(fixture.facts(learningComplete: false, runInProgress: true))
    let ready = await runtime.synchronize(fixture.facts())
    #expect(await runtime.derivationBuildCount == derivations)
    let resized = try applied(await runtime.submit(
      .init(projection: ready.projection, intent: .setUniformScale(0.2)), facts: fixture.facts()))
    #expect(resized.plan?.revisionID != planID)
    #expect(await runtime.derivationBuildCount == derivations + 1)
    let oldPreview = try #require(ready.preview)
    #expect(oldPreview.strokes != resized.preview?.strokes)
    // Unavailable derivations remain unavailable on cache hits; restoring the
    // exact authority must rebuild even if the artwork has not changed.
    let missingRegion = fixture.facts(displayedFrame: fixture.frame,
      opticalConfiguration: fixture.opticalConfiguration,
      registration: fixture.registration, drawableRegion: nil)
    let unavailable = await runtime.synchronize(missingRegion)
    let repeated = await runtime.synchronize(missingRegion)
    #expect(unavailable.plan == nil && unavailable.preview == nil)
    #expect(repeated.plan == nil && repeated.preview == nil)
    let restored = await runtime.synchronize(fixture.facts())
    #expect(restored.plan?.revisionID == resized.plan?.revisionID)
    #expect(restored.preview != nil)

  }

  @Test("wide artwork retains a reachable exact fractional maximum scale in the production UI")
  func fractionalMaximumScaleRemainsReachable() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime,
      workspace: workspace, environment: .simulated)
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)
    _ = await workspace.currentDrawingRunFacts(for: .simulated)
    let item = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let initial = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
    let openRequest = try #require(initial.semantic.request(for: PlotterAppUIActionID.drawingDraft(.showTarget)))
    #expect(await workspace.submitPlotterUIRequest(openRequest) == .accepted(requestID: openRequest.id))
    let base = try #require(workspace.drawingDraftSnapshot.program)
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 1003, height: 100),
      strokes: base.strokes, source: DrawingSourceProvenance(kind: "wide-artwork-test", sourceIdentifier: "fractional-scale-regression"))
    let selection = workspace.plotterUIProjection(selectedItemID: item, manualDraft: ManualMotionDraft(),
      includesLearningPath: true, pendingDrawingProgram: program)
    let selectRequest = try #require(selection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
    #expect(await workspace.submitPlotterUIRequest(selectRequest) == .accepted(requestID: selectRequest.id))
    let projection = workspace.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
    let placement = projection.drawingStudio.canvas.placement
    #expect(placement.uniformScale == placement.allowedScale.upperBound)
    #expect(placement.uniformScale != (placement.uniformScale * 100).rounded() / 100)
    let resize = try #require(projection.semantic.request(matching: .drawingDraft(.setUniformScale(placement.allowedScale.upperBound))))
    #expect(await workspace.submitPlotterUIRequest(resize) == .accepted(requestID: resize.id))
    #expect(workspace.drawingDraftSnapshot.program == program)
    await workspace.shutdown()
  }

  @Test("portrait authoring survives unavailable calibration and builds the same program after Learning")
  func portraitBeforeCalibration() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let unavailable = PlotterDrawingDraftExternalFacts(
      environment: .simulated, interactiveLearningIsComplete: false,
      displayedFrame: nil, opticalConfiguration: nil, registration: nil,
      drawableRegion: nil, toolAssemblyRevision: fixture.registration.applicability.toolAssembly,
      paper: fixture.paper, runInProgress: false, terminalRequiresNewPlan: false)
    var snapshot = try await open(runtime, facts: unavailable)
    let style = try #require(snapshot.program?.strokes.first?.style)
    let portrait = try PortraitVectorizer.program(
      from: portraitTestRaster(), pose: .front, style: .contours, strokeStyle: style)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .selectProgram(portrait)),
      facts: unavailable))
    #expect(snapshot.program == portrait)
    #expect(snapshot.plan == nil)
    #expect(snapshot.planningRefusal?.reason == .registrationUnavailable)
    #expect(!snapshot.paperCoverageIsCurrent)

    let ready = await runtime.synchronize(fixture.facts())
    #expect(ready.program == portrait)
    #expect(ready.plan?.sourceProgramContentHash == portrait.contentHash)
    #expect(ready.plan?.strokes.count == portrait.strokes.count)
    let lostCalibration = await runtime.synchronize(unavailable)
    #expect(lostCalibration.program == portrait)
    #expect(lostCalibration.plan == nil)
    let restored = await runtime.synchronize(fixture.facts())
    #expect(restored.plan == ready.plan)
  }

  @Test("portrait vectors retain exact identity through placement and the ordinary drawing plan")
  func portraitProgramIntegration() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    let program = try PortraitVectorizer.program(
      from: portraitTestRaster(), pose: .right, style: .hatch,
      strokeStyle: StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue)))
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .selectProgram(program)),
      facts: facts))
    #expect(snapshot.selectedCatalogItemID == nil)
    #expect(snapshot.program == program)
    let plan = try #require(snapshot.plan)
    #expect(plan.strokes.count == program.strokes.count)
    #expect(snapshot.preview?.programContentHash == program.contentHash)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .setUniformScale(0.1)), facts: facts))
    #expect(snapshot.program == program)
    #expect(snapshot.plan?.contentHash != plan.contentHash)
    let roundTrip = try JSONDecoder().decode(ExecutionPlanRevision.self, from: JSONEncoder().encode(try #require(snapshot.plan)))
    #expect(roundTrip == snapshot.plan)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: .selectCatalogItem(.circle)), facts: facts))
    #expect(snapshot.selectedCatalogItemID == .circle)
    #expect(snapshot.program?.source.kind != "portrait")
    #expect(snapshot.program?.contentHash != program.contentHash)
  }

  @Test("target visibility is independent of Learning and active drawing identity")
  func targetVisibilityDoesNotMutateDrawingAuthority() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let incompleteFacts = fixture.facts(learningComplete: false)
    let initial = await runtime.synchronize(incompleteFacts)
    let opened = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: initial.projection, intent: .showTarget),
      facts: incompleteFacts
    ))
    #expect(opened.isTargetVisible)
    let readyFacts = fixture.facts()

    let busyFacts = fixture.facts(runInProgress: true)
    let busy = await runtime.synchronize(busyFacts)
    let refusedClose = await runtime.submit(
      PlotterDrawingDraftSubmission(projection: busy.projection, intent: .hideTarget),
      facts: busyFacts
    )
    #expect(!((try applied(refusedClose)).isTargetVisible))
    #expect(refusedClose.snapshot.projection.draftRevision == busy.projection.draftRevision)
    #expect(refusedClose.snapshot.plan?.revisionID == busy.plan?.revisionID)

    let readyAgain = await runtime.synchronize(readyFacts)
    let closed = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(projection: readyAgain.projection, intent: .hideTarget),
      facts: readyFacts
    ))
    #expect(!closed.isTargetVisible)

    let refusedEdit = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: closed.projection,
        intent: .selectCatalogItem(.circle)
      ),
      facts: readyFacts
    )
    let hiddenEdit = try applied(refusedEdit)
    #expect(hiddenEdit.selectedCatalogItemID == .circle)
    #expect(!hiddenEdit.isTargetVisible)
  }

  @Test("request identity and both draft and external fact revisions reject stale submissions")
  func requestAndProjectionStaleness() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let staleProjection = opened.projection
    let selected = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: staleProjection,
        intent: .selectCatalogItem(.elephant)
      ),
      facts: facts
    ))
    let staleRequestID = PlotterDrawingDraftRequestID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
    )
    let staleDraft = await runtime.submit(
      PlotterDrawingDraftSubmission(
        requestID: staleRequestID,
        projection: staleProjection,
        intent: .setRotationDegrees(15)
      ),
      facts: facts
    )
    let draftRefusal = try refusal(staleDraft)

    #expect(draftRefusal.requestID == staleRequestID)
    #expect(draftRefusal.reason == .staleProjection)
    #expect(draftRefusal.comparedDraftRevision == selected.projection.draftRevision)
    #expect(staleDraft.snapshot.selectedCatalogItemID == .elephant)

    let newerFrame = try replacingFrame(fixture.frame, id: "draft-newer", sequenceDelta: 1)
    let newerFacts = fixture.facts(displayedFrame: newerFrame)
    let externalRequestID = PlotterDrawingDraftRequestID(
      rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!
    )
    let staleExternal = await runtime.submit(
      PlotterDrawingDraftSubmission(
        requestID: externalRequestID,
        projection: selected.projection,
        intent: .assertPaperCoverage
      ),
      facts: newerFacts
    )
    let externalRefusal = try refusal(staleExternal)
    #expect(externalRefusal.requestID == externalRequestID)
    #expect(externalRefusal.reason == .staleProjection)
    #expect(externalRefusal.comparedExternalFacts.displayedFrame == newerFrame.plotterExactFrameReference)
  }

  @Test("catalog program placement and plan identities are deterministic")
  func deterministicContentIdentity() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let facts = fixture.facts()
    let firstRuntime = PlotterDrawingDraftRuntime()
    let secondRuntime = PlotterDrawingDraftRuntime()
    let first = await firstRuntime.synchronize(facts)
    let second = await secondRuntime.synchronize(facts)

    #expect(first.catalog == DrawingProgramCatalog.entries)
    #expect(first.catalog.map(\.id) == DrawingCatalogEntryID.allCases)
    #expect(first.program == second.program)
    #expect(first.program?.contentHash == second.program?.contentHash)
    #expect(first.plan?.placement == second.plan?.placement)
    #expect(first.plan?.revisionID == second.plan?.revisionID)
    #expect(first.plan?.contentHash == second.plan?.contentHash)

    let opened = try await open(firstRuntime, facts: facts)
    let priorPlacementID = opened.placementID
    let selected = try applied(await firstRuntime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .selectCatalogItem(.circle)
      ),
      facts: facts
    ))
    let expectedCircle = try DrawingProgramCatalog.program(
      for: .circle,
      style: StrokeStyle(
        nominalLineWidth: 0.4,
        penProfileID: PenProfileID(fixture.registration.applicability.toolAssembly.rawValue)
      )
    )
    #expect(selected.placementID != priorPlacementID)
    #expect(selected.program?.id == expectedCircle.id)
    #expect(selected.plan?.sourceProgramContentHash == selected.program?.contentHash)
  }

  @Test("ordinary drawing needs no pre-run role choice and invalid transforms do not mutate")
  func ordinaryRoleAndParameterValidation() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let snapshot = try await open(runtime, facts: facts)
    #expect(snapshot.evidenceRole == .ordinaryDrawing)

    let revisionBeforeInvalid = snapshot.projection.draftRevision
    let placementBeforeInvalid = snapshot.placementID
    let invalidScale = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setUniformScale(.nan)
      ),
      facts: facts
    )
    let invalidScaleRefusal = try refusal(invalidScale)
    #expect(invalidScaleRefusal.reason == .invalidScale)
    #expect(invalidScale.snapshot.projection.draftRevision == revisionBeforeInvalid)
    #expect(invalidScale.snapshot.placementID == placementBeforeInvalid)

    let invalidRotation = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: invalidScale.snapshot.projection,
        intent: .setRotationDegrees(.infinity)
      ),
      facts: facts
    )
    let invalidRotationRefusal = try refusal(invalidRotation)
    #expect(invalidRotationRefusal.reason == .invalidRotation)
    #expect(invalidRotation.snapshot.projection.draftRevision == revisionBeforeInvalid)
    #expect(invalidRotation.snapshot.placementID == placementBeforeInvalid)
  }

  @Test("camera placement requires the current exact frame and accepted registration")
  func exactFrameAndRegistrationPlacementRefusals() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let staleFrame = try replacingFrame(fixture.frame, id: "stale-placement", sequenceDelta: 1)
    let point = try Point2<CameraPixelSpace>(x: 100, y: 100)
    let stalePlacement = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .placeAtCameraPoint(PlotterDrawingDraftCameraPlacement(
          frame: staleFrame.plotterExactFrameReference,
          point: point
        ))
      ),
      facts: facts
    )
    let frameRefusal = try refusal(stalePlacement)
    #expect(frameRefusal.owner.rawValue == "CameraEvidenceAuthority")
    #expect(frameRefusal.reason == .exactFrameMismatch)
    #expect(frameRefusal.remedy == "Place the target from the currently displayed exact frame.")

    let missingRegistrationFacts = fixture.facts(
      displayedFrame: fixture.frame,
      opticalConfiguration: fixture.opticalConfiguration,
      registration: nil,
      drawableRegion: fixture.drawableRegion
    )
    let missing = await runtime.synchronize(missingRegistrationFacts)
    let registrationPlacement = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: missing.projection,
        intent: .placeAtCameraPoint(PlotterDrawingDraftCameraPlacement(
          frame: fixture.frame.plotterExactFrameReference,
          point: point
        ))
      ),
      facts: missingRegistrationFacts
    )
    let registrationRefusal = try refusal(registrationPlacement)
    #expect(registrationRefusal.owner.rawValue == "TipCameraRegistration")
    #expect(registrationRefusal.reason == .registrationUnavailable)
    #expect(
      registrationRefusal.remedy
        == "Restore a current accepted pen-tip registration before placing the target."
    )
  }

  @Test("scale rotation and center rebuild one immutable planned placement")
  func scaleRotationAndCenterPlanning() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    let requestedScale = snapshot.allowedScale.upperBound + 1
    let beforeInvalidScale = snapshot
    let invalidScale = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setUniformScale(requestedScale)
      ),
      facts: facts
    )
    let scaleRefusal = try refusal(invalidScale)
    #expect(scaleRefusal.owner.rawValue == "PlotterModel.ExecutionPlanRevision")
    #expect(scaleRefusal.reason == .invalidScale)
    #expect(
      scaleRefusal.remedy
        == "Choose a positive finite scale within the published allowed range."
    )
    #expect(invalidScale.snapshot.projection.draftRevision == beforeInvalidScale.projection.draftRevision)
    #expect(invalidScale.snapshot.placementID == beforeInvalidScale.placementID)
    #expect(invalidScale.snapshot.uniformScale == beforeInvalidScale.uniformScale)
    #expect(invalidScale.snapshot.program == beforeInvalidScale.program)
    #expect(invalidScale.snapshot.plan == beforeInvalidScale.plan)

    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: invalidScale.snapshot.projection,
        intent: .setUniformScale(invalidScale.snapshot.allowedScale.upperBound)
      ),
      facts: facts
    ))
    #expect(snapshot.uniformScale == snapshot.allowedScale.upperBound)

    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setRotationDegrees(450)
      ),
      facts: facts
    ))
    #expect(snapshot.rotationDegrees == 90)

    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .centerInDrawableRegion
      ),
      facts: facts
    ))
    let bounds = fixture.drawableRegion.effectiveBounds
    let expectedCenter = try Point2<MachineSpace>(
      x: (bounds.minX + bounds.maxX) / 2,
      y: (bounds.minY + bounds.maxY) / 2
    )
    let plan = try #require(snapshot.plan)
    let machineCenter = try #require(snapshot.machineCenter)
    #expect(abs(machineCenter.x - expectedCenter.x) < 1e-9)
    #expect(abs(machineCenter.y - expectedCenter.y) < 1e-9)
    #expect(abs(plan.placement.machineAnchor.x - expectedCenter.x) < 1e-9)
    #expect(abs(plan.placement.machineAnchor.y - expectedCenter.y) < 1e-9)
    #expect(plan.placement.uniformScale == snapshot.uniformScale)
    #expect(abs(plan.placement.uniformScale - snapshot.allowedScale.upperBound) < 1e-12)
    #expect(abs(plan.placement.rotationRadians - .pi / 2) < 1e-12)
  }

  @Test("ordinary frame crossing Boundary is refused without clipping or replacing the prior plan")
  func outsideRegionPreservesPriorFrame() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let snapshot = try applied(await runtime.submit(.init(projection: opened.projection,
      intent: .setUniformScale(0.02)), facts: facts))
    let bounds = fixture.drawableRegion.effectiveBounds
    let outsideCenter = try Point2<MachineSpace>(x: bounds.minX, y: (bounds.minY + bounds.maxY) / 2)
    let cameraPoint = try fixture.registration.cameraFromMachine.applying(to: outsideCenter)
    let rejected = await runtime.submit(.init(projection: snapshot.projection,
      intent: .placeAtCameraPoint(.init(frame: fixture.frame.plotterExactFrameReference,
        point: cameraPoint))), facts: facts)
    #expect(try refusal(rejected).reason == .planningFailed("Frame outside Boundary"))
    #expect(rejected.snapshot.machineCenter == snapshot.machineCenter)
    #expect(rejected.snapshot.plan == snapshot.plan)
    #expect(rejected.snapshot.preview == snapshot.preview)
    #expect(rejected.snapshot.projection.draftRevision == snapshot.projection.draftRevision)
    #expect(rejected.snapshot.placementID == snapshot.placementID)
  }

  @Test("retained Drawing Border planning uses the adapter without draft mutation authority")
  func retainedBorderPlanningDoesNotMutateDraft() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    let before = await runtime.synchronize(facts)
    let program = try #require(before.program)
    let draftPlan = try #require(before.plan)

    let retained = try PlotterDrawingPlanningAdapter.planRetainedDrawingBorder(
      program: program,
      placement: draftPlan.placement,
      drawableRegion: fixture.drawableRegion,
      provenance: draftPlan.provenance
    )
    let after = await runtime.synchronize(facts)

    #expect(retained == draftPlan)
    #expect(after.projection == before.projection)
    #expect(after.placementID == before.placementID)
    #expect(!after.isTargetVisible)
    #expect(after.lastSubmissionRefusal == nil)
  }

  @Test("target persists on compatible frames and outside tip applicability remains diagnostic only")
  func previewExactFrameAndDiagnosticApplicability() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let facts = fixture.facts()
    var snapshot = try await open(runtime, facts: facts)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .setUniformScale(0.02)
      ),
      facts: facts
    ))
    let bounds = fixture.drawableRegion.effectiveBounds
    let diagnosticCenter = try Point2<MachineSpace>(
      x: bounds.minX + 5,
      y: (bounds.minY + bounds.maxY) / 2
    )
    #expect(diagnosticCenter.x < fixture.registration.applicabilityRectangle.minX)
    let cameraPoint = try fixture.registration.cameraFromMachine.applying(to: diagnosticCenter)
    snapshot = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: snapshot.projection,
        intent: .placeAtCameraPoint(PlotterDrawingDraftCameraPlacement(
          frame: fixture.frame.plotterExactFrameReference,
          point: cameraPoint
        ))
      ),
      facts: facts
    ))
    let preview = try #require(snapshot.preview)
    guard case .diagnosticOnly(let limitation) = preview.status else {
      Issue.record("Expected a diagnostic-only tip-applicability preview.")
      return
    }
    #expect(limitation.registrationRevisionID == fixture.registration.acceptedRevisionID)
    #expect(preview.planRevisionID == snapshot.plan?.revisionID)
    #expect(preview.programContentHash == snapshot.program?.contentHash)
    #expect(preview.displayedFrame == fixture.frame)
    #expect(facts.revisions.environment == .simulated)

    let presentationPreview = DrawingStudioTargetPreview(
      provenance: ExactFrameOverlayProvenance(preview.displayedFrame),
      strokes: preview.strokes,
      bounds: preview.bounds,
      programContentHash: preview.programContentHash.description,
      executionPlanContentHash: preview.planRevisionID?.description,
      status: .diagnosticOnly(reason: "SIMULATED diagnostic projection; not physical evidence.")
    )
    let newer = try replacingFrame(fixture.frame, id: "preview-newer", sequenceDelta: 1)
    #expect(presentationPreview.matches(fixture.frame))
    #expect(presentationPreview.matches(newer))
  }

  @Test("nominal paper save completes before the accepted snapshot is published")
  func paperPersistenceSaveBeforePublish() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(blocksSave: true)
    let runtime = PlotterDrawingDraftRuntime(
      paperPersistence: persistence,
      clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100)
    )
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let completion = DraftSubmissionCompletionProbe()
    let task = Task {
      let result = await runtime.submit(
        PlotterDrawingDraftSubmission(
          projection: opened.projection,
          intent: .assertPaperCoverage
        ),
        facts: facts
      )
      await completion.markCompleted()
      return result
    }

    await persistence.waitUntilSaveStarted()
    let completedBeforeSave = await completion.completed
    #expect(!completedBeforeSave)
    await persistence.releaseSave()
    let result = await task.value
    let published = try applied(result)
    let saved = await persistence.storedObservation
    let saveCount = await persistence.saveCount

    #expect(saved?.id == published.paperCoverageObservation?.id)
    #expect(published.paperCoverageObservation != nil)
    #expect(published.paperCoverageIsCurrent)
    #expect(saveCount == 1)
    #expect(fixture.frame.source == .simulated)
  }

  @Test("paper save serializes a queued same-projection edit through the runtime FIFO")
  func paperPersistenceSerializesQueuedEdit() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(blocksSave: true)
    let runtime = PlotterDrawingDraftRuntime(
      paperPersistence: persistence,
      clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100)
    )
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let assertionCompletion = DraftSubmissionCompletionProbe()
    let assertionTask = Task {
      let result = await runtime.submit(
        PlotterDrawingDraftSubmission(
          projection: opened.projection,
          intent: .assertPaperCoverage
        ),
        facts: facts
      )
      await assertionCompletion.markCompleted()
      return result
    }

    await persistence.waitUntilSaveStarted()
    let queuedEdit = DraftSubmissionInterleavingProbe()
    let editTask = Task {
      await queuedEdit.markStarted()
      let result = await runtime.submit(
        PlotterDrawingDraftSubmission(
          projection: opened.projection,
          intent: .setRotationDegrees(15)
        ),
        facts: facts
      )
      await queuedEdit.markCompleted()
      return result
    }
    await queuedEdit.waitUntilStarted()

    #expect(!(await assertionCompletion.completed))
    #expect(!(await queuedEdit.completed))
    #expect(await persistence.storedObservation == nil)
    #expect(await persistence.saveCount == 1)

    await persistence.releaseSave()
    let asserted = try applied(await assertionTask.value)
    let staleEditResult = await editTask.value
    let staleEdit = try refusal(staleEditResult)
    let final = await runtime.synchronize(facts)

    #expect(staleEdit.owner.rawValue == "PlotterDrawingDraftRuntime")
    #expect(staleEdit.reason == .staleProjection)
    #expect(staleEdit.comparedDraftRevision == asserted.projection.draftRevision)
    #expect(
      staleEdit.remedy
        == "Use the current Drawing Studio projection and retry the requested edit."
    )
    #expect(staleEditResult.snapshot.evidenceRole == opened.evidenceRole)
    #expect(staleEditResult.snapshot.paperCoverageObservation == asserted.paperCoverageObservation)
    #expect(staleEditResult.snapshot.projection.draftRevision == asserted.projection.draftRevision)
    #expect(final.evidenceRole == opened.evidenceRole)
    #expect(final.paperCoverageObservation == asserted.paperCoverageObservation)
    #expect(final.paperCoverageIsCurrent)
    #expect(await persistence.storedObservation == asserted.paperCoverageObservation)
  }

  @Test("paper persistence failure refuses without publishing an assertion")
  func paperPersistenceFailureDoesNotPublish() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let persistence = DraftPaperPersistenceProbe(failsSave: true)
    let runtime = PlotterDrawingDraftRuntime(paperPersistence: persistence)
    let facts = fixture.facts(environment: .live)
    let opened = try await open(runtime, facts: facts)
    let result = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .assertPaperCoverage
      ),
      facts: facts
    )
    let persistenceRefusal = try refusal(result)

    #expect(persistenceRefusal.owner.rawValue == "PlotterPaperCoverageAuthority")
    guard case .paperPersistenceFailed = persistenceRefusal.reason else {
      Issue.record("Expected typed paperPersistenceFailed refusal.")
      return
    }
    #expect(result.snapshot.paperCoverageObservation == nil)
    #expect(result.snapshot.projection.draftRevision == opened.projection.draftRevision)
    let storedObservation = await persistence.storedObservation
    #expect(storedObservation == nil)
  }

  @Test("paper polygon displays only on its exact frame but remains current on a newer frame")
  func paperExactFrameDisplayAndNewerFrameCurrentness() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(
      now: fixture.frame.frame.captureNanoseconds + 100
    ))
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    let accepted = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .assertPaperCoverage
      ),
      facts: facts
    ))
    let exactDisplay = try #require(accepted.paperCoverageDisplay)
    #expect(accepted.paperCoverageIsCurrent)
    #expect(exactDisplay.frame == ExactFrameProvenance(frame: fixture.frame.frame))
    #expect(exactDisplay.polygon.count == 4)

    let newerFrame = try replacingFrame(fixture.frame, id: "paper-newer", sequenceDelta: 1)
    let newer = await runtime.synchronize(fixture.facts(displayedFrame: newerFrame))
    #expect(newer.paperCoverageObservation?.id == accepted.paperCoverageObservation?.id)
    #expect(newer.paperCoverageIsCurrent)
    #expect(newer.paperCoverageDisplay == nil)
  }

  @Test("paper currentness rejects paper source configuration and contact-plane changes")
  func paperCurrentnessInvalidations() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(
      now: fixture.frame.frame.captureNanoseconds + 100
    ))
    let facts = fixture.facts()
    let opened = try await open(runtime, facts: facts)
    _ = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: opened.projection,
        intent: .assertPaperCoverage
      ),
      facts: facts
    ))

    let newPaper = PaperRevisionContext(
      instance: PaperInstanceRevision(),
      contactPlane: fixture.paper.contactPlane
    )
    #expect(!(await runtime.synchronize(fixture.facts(paper: newPaper))).paperCoverageIsCurrent)

    let newPlane = PaperRevisionContext(
      instance: fixture.paper.instance,
      contactPlane: PaperContactPlaneRevision()
    )
    #expect(!(await runtime.synchronize(fixture.facts(paper: newPlane))).paperCoverageIsCurrent)

    let newSourceFrame = try replacingFrame(
      fixture.frame,
      id: "paper-source",
      sequenceDelta: 1,
      source: .live(CameraDeviceID(rawValue: "different-source"))
    )
    #expect(
      !(await runtime.synchronize(fixture.facts(displayedFrame: newSourceFrame)))
        .paperCoverageIsCurrent
    )

    let newConfigurationFrame = try replacingFrame(
      fixture.frame,
      id: "paper-configuration",
      sequenceDelta: 2,
      cameraConfigurationID: CameraConfigurationID()
    )
    #expect(
      (await runtime.synchronize(fixture.facts(displayedFrame: newConfigurationFrame)))
        .paperCoverageIsCurrent
    )
  }

  @Test("retained terminal requires an EA-08B-authorized new-plan handoff")
  func retainedTerminalNewPlanHandoff() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let normalFacts = fixture.facts()
    let opened = try await open(runtime, facts: normalFacts)
    let terminalFacts = fixture.facts(terminalRequiresNewPlan: true)
    let terminal = await runtime.synchronize(terminalFacts)

    let editResult = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: terminal.projection,
        intent: .selectCatalogItem(.star)
      ),
      facts: terminalFacts
    )
    let editRefusal = try refusal(editResult)
    #expect(editRefusal.owner.rawValue == "PlotterDrawingRunAuthority")
    #expect(editRefusal.reason == .terminalRunRequiresHandoff)
    #expect(
      editRefusal.remedy
        == "Use Prepare Next Drawing to clear the retained terminal before editing a new plan."
    )

    let directNewPlan = await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: terminal.projection,
        intent: .beginNewPlan
      ),
      facts: terminalFacts
    )
    let directNewPlanRefusal = try refusal(directNewPlan)
    #expect(directNewPlanRefusal.reason == .terminalRunRequiresHandoff)

    let authorizedFacts = fixture.facts(terminalRequiresNewPlan: false)
    let authorized = await runtime.synchronize(authorizedFacts)
    let handedOff = try applied(await runtime.submit(
      PlotterDrawingDraftSubmission(
        projection: authorized.projection,
        intent: .beginNewPlan
      ),
      facts: authorizedFacts
    ))
    #expect(handedOff.placementID != opened.placementID)
    #expect(handedOff.lastSubmissionRefusal == nil)
    #expect(handedOff.plan?.revisionID == authorized.plan?.revisionID)
  }

  @Test("draft actions invoke no machine Stop camera Vision run evidence or physical effect")
  func draftActionsHaveNoPhysicalOrEvidenceEffects() async throws {
    let draftRuntime = PlotterDrawingDraftRuntime()
    let harness = makeCausalSimulatorAppFixture(drawingDraftRuntime: draftRuntime)
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)
    let fixture = try draftAuthorityFixture(from: workspace)
    let facts = fixture.facts()
    let simulatorBefore = await harness.simulator.snapshot()
    let inkBefore = await harness.simulator.persistentInk()
    let visionBefore = workspace.visionAnalysisSnapshot
    let drawingEvidenceErrorBefore = workspace.drawingEvidenceError
    let comparisonAvailableBefore = workspace.completedDrawingComparisonReviewIsAvailable
    let comparisonPinnedBefore = workspace.completedDrawingComparisonReviewIsPinned
    let stopMutationsBefore =
      workspace.computationDiagnosticsForTesting.stoppableOperationMutationCount

    var snapshot = try await open(draftRuntime, facts: facts)
    let intents: [PlotterDrawingDraftIntent] = [
      .selectCatalogItem(.triangle),
      .setUniformScale(0.03),
      .setRotationDegrees(15),
      .centerInDrawableRegion,
      .assertPaperCoverage,
    ]
    for intent in intents {
      snapshot = try applied(await draftRuntime.submit(
        PlotterDrawingDraftSubmission(projection: snapshot.projection, intent: intent),
        facts: facts
      ))
    }

    #expect(await harness.simulator.snapshot() == simulatorBefore)
    #expect(await harness.simulator.persistentInk() == inkBefore)
    #expect(workspace.visionAnalysisSnapshot == visionBefore)
    let retainedRunSideEffect: Bool = switch workspace.testDrawingStudioPresentation.runState {
    case .running, .processing, .terminal, .publicationFailed, .publicationIncomplete, .reviewAvailable, .reviewing: true
    case .unavailable, .ready: false
    }
    #expect(!retainedRunSideEffect)
    #expect(workspace.drawingEvidenceError == drawingEvidenceErrorBefore)
    #expect(workspace.completedDrawingComparisonReviewIsAvailable == comparisonAvailableBefore)
    #expect(workspace.completedDrawingComparisonReviewIsPinned == comparisonPinnedBefore)
    #expect(
      workspace.computationDiagnosticsForTesting.stoppableOperationMutationCount
        == stopMutationsBefore
    )
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.frameMode == .simulated)
    #expect(facts.revisions.environment == .simulated)
    #expect(snapshot.paperCoverageObservation?.source == .simulated)
    await workspace.shutdown()
  }
}

private enum DrawingDraftEpisodeTestError: Error {
  case expectedApplied
  case expectedRefusal
}

private func applied(
  _ result: PlotterDrawingDraftSubmissionResult
) throws -> PlotterDrawingDraftSnapshot {
  guard case .applied = result.disposition else {
    Issue.record("Expected an applied drawing-draft submission; got \(result.disposition).")
    throw DrawingDraftEpisodeTestError.expectedApplied
  }
  return result.snapshot
}

private func refusal(
  _ result: PlotterDrawingDraftSubmissionResult
) throws -> PlotterDrawingDraftRefusal {
  guard case .refused(let refusal) = result.disposition else {
    Issue.record("Expected a refused drawing-draft submission; got \(result.disposition).")
    throw DrawingDraftEpisodeTestError.expectedRefusal
  }
  return refusal
}

private func open(
  _ runtime: PlotterDrawingDraftRuntime,
  facts: PlotterDrawingDraftExternalFacts
) async throws -> PlotterDrawingDraftSnapshot {
  let current = await runtime.synchronize(facts)
  return try applied(await runtime.submit(
    PlotterDrawingDraftSubmission(projection: current.projection, intent: .showTarget),
    facts: facts
  ))
}

private struct DrawingDraftAuthorityFixture: Sendable {
  let frame: DisplayedFrame
  let opticalConfiguration: CameraOpticalConfigurationIdentity
  let registration: TipCameraRegistration
  let drawableRegion: DrawableMachineRegion
  let paper: PaperRevisionContext

  func facts(
    environment: PlotterEnvironment = .simulated,
    learningComplete: Bool = true,
    runInProgress: Bool = false,
    terminalRequiresNewPlan: Bool = false,
    paper: PaperRevisionContext? = nil
  ) -> PlotterDrawingDraftExternalFacts {
    facts(
      environment: environment,
      learningComplete: learningComplete,
      displayedFrame: frame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan,
      paper: paper ?? self.paper
    )
  }

  func facts(
    displayedFrame: DisplayedFrame
  ) -> PlotterDrawingDraftExternalFacts {
    facts(
      environment: .simulated,
      learningComplete: true,
      displayedFrame: displayedFrame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      runInProgress: false,
      terminalRequiresNewPlan: false,
      paper: paper
    )
  }

  func facts(
    displayedFrame: DisplayedFrame,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    registration: TipCameraRegistration?,
    drawableRegion: DrawableMachineRegion?
  ) -> PlotterDrawingDraftExternalFacts {
    facts(
      environment: .simulated,
      learningComplete: true,
      displayedFrame: displayedFrame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      runInProgress: false,
      terminalRequiresNewPlan: false,
      paper: paper
    )
  }

  private func facts(
    environment: PlotterEnvironment,
    learningComplete: Bool,
    displayedFrame: DisplayedFrame?,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    registration: TipCameraRegistration?,
    drawableRegion: DrawableMachineRegion?,
    runInProgress: Bool,
    terminalRequiresNewPlan: Bool,
    paper: PaperRevisionContext
  ) -> PlotterDrawingDraftExternalFacts {
    PlotterDrawingDraftExternalFacts(
      environment: environment,
      interactiveLearningIsComplete: learningComplete,
      displayedFrame: displayedFrame,
      opticalConfiguration: opticalConfiguration,
      registration: registration,
      drawableRegion: drawableRegion,
      toolAssemblyRevision: self.registration.applicability.toolAssembly,
      paper: paper,
      runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan,
      drawingBorderBounds: registration?.applicabilityRectangle
    )
  }
}

@MainActor
private enum DrawingDraftAuthorityFixtureCache {
  private static var cached: DrawingDraftAuthorityFixture?

  static func load() async throws -> DrawingDraftAuthorityFixture {
    if let cached { return cached }
    let harness = makeCausalSimulatorAppFixture()
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(
      harness.workspace,
      simulator: harness.simulator
    )
    let fixture = try draftAuthorityFixture(from: harness.workspace)
    await harness.workspace.shutdown()
    cached = fixture
    return fixture
  }
}

@MainActor
private func draftAuthorityFixture(
  from workspace: PlotterApplicationRuntime
) throws -> DrawingDraftAuthorityFixture {
  let registration = try #require(workspace.tipCameraRegistration)
  return DrawingDraftAuthorityFixture(
    frame: try #require(workspace.displayedFrame),
    opticalConfiguration: registration.applicability.opticalConfiguration,
    registration: registration,
    drawableRegion: try #require(workspace.currentDrawableMachineRegion),
    paper: workspace.currentPaperRevisionContext
  )
}

private func replacingFrame(
  _ frame: DisplayedFrame,
  id: String,
  sequenceDelta: UInt64,
  source: FrameSourceIdentity? = nil,
  cameraConfigurationID: CameraConfigurationID? = nil
) throws -> DisplayedFrame {
  DisplayedFrame(
    source: source ?? frame.source,
    frame: try StampedFrame(
      id: FrameID(rawValue: id),
      sequence: frame.frame.sequence + sequenceDelta,
      captureNanoseconds: frame.frame.captureNanoseconds + sequenceDelta,
      cameraConfigurationID: cameraConfigurationID ?? frame.frame.cameraConfigurationID,
      width: frame.frame.width,
      height: frame.frame.height,
      rowBytes: frame.frame.rowBytes,
      pixelFormat: frame.frame.pixelFormat,
      bytes: frame.frame.bytes
    )
  )
}

private struct DraftRuntimeClock: RuntimeClock {
  let now: UInt64

  func nowNanoseconds() -> UInt64 { now }

  func sleep(nanoseconds: UInt64) async throws {
    try await Task.sleep(nanoseconds: nanoseconds)
  }
}

private enum DraftPaperPersistenceError: Error {
  case saveFailed
}

private actor DraftPaperPersistenceProbe: PlotterDrawingDraftPaperPersistence {
  private var blocksSave: Bool
  private let failsSave: Bool
  private var saveStarted = false
  private var saveStartedWaiters: [CheckedContinuation<Void, Never>] = []
  private var saveRelease: CheckedContinuation<Void, Never>?
  private var saveWasReleased = false
  private(set) var storedObservation: PaperCoverageObservation?
  private(set) var saveCount = 0

  init(blocksSave: Bool = false, failsSave: Bool = false) {
    self.blocksSave = blocksSave
    self.failsSave = failsSave
  }

  func load() -> PaperCoverageObservation? { storedObservation }

  func save(_ observation: PaperCoverageObservation) async throws {
    saveCount += 1
    saveStarted = true
    let waiters = saveStartedWaiters
    saveStartedWaiters.removeAll()
    waiters.forEach { $0.resume() }
    if blocksSave, !saveWasReleased {
      await withCheckedContinuation { continuation in
        saveRelease = continuation
      }
    }
    if failsSave { throw DraftPaperPersistenceError.saveFailed }
    storedObservation = observation
  }

  func clear() {
    storedObservation = nil
  }

  func waitUntilSaveStarted() async {
    if saveStarted { return }
    await withCheckedContinuation { continuation in
      saveStartedWaiters.append(continuation)
    }
  }

  func holdNextSave() {
    blocksSave = true
    saveStarted = false
    saveWasReleased = false
  }

  func releaseSave() {
    saveWasReleased = true
    saveRelease?.resume()
    saveRelease = nil
  }
}

private actor DraftSubmissionCompletionProbe {
  private(set) var completed = false

  func markCompleted() {
    completed = true
  }
}

private actor DraftSubmissionInterleavingProbe {
  private var started = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var completed = false

  func markStarted() {
    started = true
    let waiters = startWaiters
    startWaiters.removeAll()
    waiters.forEach { $0.resume() }
  }

  func waitUntilStarted() async {
    if started { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func markCompleted() {
    completed = true
  }
}

extension PlotterDrawingDraftEpisodeTests {
  @Test("active material revises exact plan identity without changing artwork or placement")
  func physicalMaterialPlanIdentity() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let candidate = try portraitPersistenceCandidate()
    let material = try PlotterModel.Digest(bytes: Array(repeating: 7, count: 32))
    let ordinary = PlotterDrawingPlanningAdapter.buildDraft(program: candidate.program,
      machineCenter: nil, uniformScale: 0.5, rotationDegrees: 15,
      drawableRegion: fixture.drawableRegion, registration: fixture.registration)
    let adapted = PlotterDrawingPlanningAdapter.buildDraft(program: candidate.program,
      machineCenter: ordinary.center, uniformScale: 0.5, rotationDegrees: 15,
      drawableRegion: fixture.drawableRegion, registration: fixture.registration,
      materialContextHash: material)
    let before = try #require(ordinary.plan), after = try #require(adapted.plan)
    #expect(before.contentHash != after.contentHash)
    #expect(before.placement == after.placement)
    #expect(before.strokes.map(\.path) == after.strokes.map(\.path))
    #expect(before.strokes.map(\.style) == after.strokes.map(\.style))
    #expect(before.strokes.map(\.logicalStrokeID) == after.strokes.map(\.logicalStrokeID))
    #expect(before.strokes.map(\.endingCheckpointID) != after.strokes.map(\.endingCheckpointID))
    #expect(ordinary.program == adapted.program)
    #expect(after.provenance.materialContextHash == material)
    let model = PortraitStudioModel()
    #expect(await model.acceptProjection(candidate, perform: { nil }) == nil)
    let bordered = PlotterDrawingPlanningAdapter.buildDraft(program: candidate.program,
      machineCenter: ordinary.center, uniformScale: 0.5, rotationDegrees: 15,
      drawableRegion: fixture.drawableRegion, registration: fixture.registration,
      drawBorder: true,
      materialContextHash: material)
    let program = try #require(bordered.program)
    let reference = try #require(model.projectedReference(for: program))
    #expect(reference.sourceProgram == candidate.program)
    #expect(reference.matches(program))
    #expect(program.contentHash != candidate.program.contentHash)
    #expect(bordered.plan?.provenance.materialContextHash == material)
    await model.shutdown()
  }
}

extension PlotterDrawingDraftEpisodeTests {
  @Test("pre-tip sheet placement is exact-context assertion, never calibrated paper coverage")
  func qualifiedSheetPlacement() async throws {
    let f = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let guide = PlotterDrawingDraftPlacementGuide(opticalConfiguration: f.opticalConfiguration,
      machineCameraRevision: f.registration.machineCameraRegistrationRevisionID,
      region: f.drawableRegion, geometry: [.point(try Point2(x: 10, y: 10))])
    func facts(paper: PaperRevisionContext? = nil, guide: PlotterDrawingDraftPlacementGuide? = guide,
      frame: DisplayedFrame? = f.frame, optical: CameraOpticalConfigurationIdentity? = f.opticalConfiguration,
      tool: ToolAssemblyRevision? = nil, busy: Bool = false, terminal: Bool = false) -> PlotterDrawingDraftExternalFacts {
      PlotterDrawingDraftExternalFacts(environment: .simulated, interactiveLearningIsComplete: false,
        displayedFrame: frame, opticalConfiguration: optical, registration: nil, drawableRegion: nil,
        toolAssemblyRevision: tool ?? f.registration.applicability.toolAssembly, paper: paper ?? f.paper,
        runInProgress: busy, terminalRequiresNewPlan: terminal, placementGuide: guide)
    }
    let current = facts()
    #expect(current.paperAcceptanceUnavailableReason == nil)
    let before = await runtime.synchronize(current)
    let accepted = try applied(await runtime.submit(.init(projection: before.projection,
      intent: .assertPaperCoverage), facts: current))
    #expect(accepted.sheetPlacementIsCurrent)
    #expect(accepted.sheetPlacementAssertion?.frame == current.revisions.displayedFrame)
    #expect(accepted.sheetPlacementAssertion?.guide == guide)
    #expect(!accepted.paperCoverageIsCurrent)
    #expect(accepted.paperCoverageObservation == nil)
    #expect(accepted.plan == nil)
    let replacement = PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: f.paper.contactPlane)
    #expect(!(await runtime.synchronize(facts(paper: replacement))).sheetPlacementIsCurrent)
    #expect(!(await runtime.synchronize(facts(tool: ToolAssemblyRevision()))).sheetPlacementIsCurrent)
    #expect(!(await runtime.synchronize(facts(guide: nil))).sheetPlacementIsCurrent)
    #expect(!(await runtime.synchronize(facts(optical: nil))).sheetPlacementIsCurrent)
    let changedMap = PlotterDrawingDraftPlacementGuide(opticalConfiguration: f.opticalConfiguration,
      machineCameraRevision: LearningArtifactRevisionID(), region: f.drawableRegion, geometry: guide.geometry)
    #expect(!(await runtime.synchronize(facts(guide: changedMap))).sheetPlacementIsCurrent)
    let stale = await runtime.submit(.init(projection: accepted.projection,
      intent: .assertPaperCoverage), facts: facts(paper: replacement))
    #expect(try refusal(stale).reason == .staleProjection)
    for unavailable in [facts(frame: nil), facts(guide: nil), facts(optical: nil), facts(busy: true), facts(terminal: true)] {
      #expect(unavailable.paperAcceptanceUnavailableReason != nil)
      let snapshot = await runtime.synchronize(unavailable)
      let result = await runtime.submit(.init(projection: snapshot.projection,
        intent: .assertPaperCoverage), facts: unavailable)
      #expect(try refusal(result).remedy == unavailable.paperAcceptanceUnavailableReason)
    }
  }

  @Test("calibrated sheet acceptance refuses optical and plane mismatches without weakening registration")
  func paperAcceptanceContextMismatch() async throws {
    let f = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let mismatchedPlane = PaperRevisionContext(instance: f.paper.instance, contactPlane: PaperContactPlaneRevision())
    let facts = f.facts(paper: mismatchedPlane)
    #expect(facts.paperAcceptanceUnavailableReason != nil)
    let snapshot = await runtime.synchronize(facts)
    let result = await runtime.submit(.init(projection: snapshot.projection,
      intent: .assertPaperCoverage), facts: facts)
    #expect(try refusal(result).remedy == facts.paperAcceptanceUnavailableReason)
    #expect(result.snapshot.paperCoverageObservation == nil)
    #expect(!result.snapshot.sheetPlacementIsCurrent)
  }
}

extension PlotterDrawingDraftEpisodeTests {
  @Test("atomic camera frame edits retain Boundary and paper coverage and refuse invalid or stale edits")
  func atomicFramePlacement() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let facts = fixture.facts()
    let runtime = PlotterDrawingDraftRuntime(clock: DraftRuntimeClock(now: fixture.frame.frame.captureNanoseconds + 100))
    let opened = try await open(runtime, facts: facts)
    let covered = try applied(await runtime.submit(.init(projection: opened.projection, intent: .assertPaperCoverage), facts: facts))
    let frame = try #require(covered.frame)
    let resized = try frame.resized(scale: covered.uniformScale * 0.6, minimumScale: covered.allowedScale.lowerBound)
    let center = try resized.cameraCenter
    let staged = try resized.translated(to: Point2(x: center.x + 4, y: center.y + 3))
    let placement = PlotterDrawingDraftCameraPlacement(frame: fixture.frame.plotterExactFrameReference,
      point: try staged.cameraCenter, uniformScale: staged.geometry.placement.uniformScale,
      draftRevision: covered.projection.draftRevision)
    let edited = try applied(await runtime.submit(.init(projection: covered.projection,
      intent: .placeAtCameraPoint(placement)), facts: facts))
    #expect(edited.uniformScale == staged.geometry.placement.uniformScale)
    #expect(try #require(edited.machineCenter).distance(to: staged.geometry.placement.machineAnchor) < 1e-9)
    #expect(edited.paperCoverageObservation == covered.paperCoverageObservation)
    #expect(edited.paperCoverageIsCurrent)
    #expect(edited.projection.externalFacts.drawableRegion == covered.projection.externalFacts.drawableRegion)
    #expect(edited.projection.externalFacts.drawingBorderBounds == covered.projection.externalFacts.drawingBorderBounds)
    #expect(edited.projection.externalFacts.registrationRevisionID == covered.projection.externalFacts.registrationRevisionID)
    #expect(edited.plan?.drawableRegion == covered.plan?.drawableRegion)
    let stale = await runtime.submit(.init(projection: edited.projection,
      intent: .placeAtCameraPoint(placement)), facts: facts)
    #expect(try refusal(stale).reason == .staleProjection)
    #expect(stale.snapshot.plan == edited.plan)
    let outside = PlotterDrawingDraftCameraPlacement(frame: placement.frame,
      point: try fixture.registration.cameraFromMachine.applying(to: Point2(x: 100_000, y: 100_000)),
      uniformScale: edited.uniformScale * 0.9, draftRevision: edited.projection.draftRevision)
    let rejected = await runtime.submit(.init(projection: edited.projection,
      intent: .placeAtCameraPoint(outside)), facts: facts)
    #expect(try refusal(rejected).reason == .planningFailed("Frame outside Boundary"))
    #expect(rejected.snapshot.plan == edited.plan)
    #expect(rejected.snapshot.uniformScale == edited.uniformScale)
    #expect(rejected.snapshot.placementID == edited.placementID)
    let staleFacts = fixture.facts(displayedFrame: try replacingFrame(fixture.frame, id: "frame-advanced", sequenceDelta: 1))
    let wrongFrame = await runtime.submit(.init(projection: edited.projection,
      intent: .placeAtCameraPoint(outside)), facts: staleFacts)
    #expect(try refusal(wrongFrame).reason == .staleProjection)
    #expect(wrongFrame.snapshot.plan == edited.plan)
  }

  @Test("all corner resize maxima pass the same atomic runtime admission", arguments: [0.0, 17, 45, 90])
  func maximumResizeAdmission(degrees: Double) async throws {
    let f = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    var snapshot = try await open(runtime, facts: f.facts())
    snapshot = try applied(await runtime.submit(.init(projection: snapshot.projection,
      intent: .setRotationDegrees(degrees)), facts: f.facts()))
    snapshot = try applied(await runtime.submit(.init(projection: snapshot.projection,
      intent: .centerInDrawableRegion), facts: f.facts()))
    let frame = try #require(snapshot.frame)
    let expanded = try frame.resized(scale: 100_000, minimumScale: snapshot.allowedScale.lowerBound)
    let placement = PlotterDrawingDraftCameraPlacement(frame: f.frame.plotterExactFrameReference,
      point: try expanded.cameraCenter, uniformScale: expanded.geometry.placement.uniformScale,
      draftRevision: snapshot.projection.draftRevision)
    let result = try applied(await runtime.submit(.init(projection: snapshot.projection,
      intent: .placeAtCameraPoint(placement)), facts: f.facts()))
    #expect(try #require(result.frame).geometry.isContained(in: f.drawableRegion))
    #expect(abs(result.uniformScale - expanded.geometry.placement.uniformScale) < 1e-12)
  }

  @Test("metric targets retain their video frame and strict controller geometry")
  func metricVideoFrameRemainsAvailable() async throws {
    let fixture = try await DrawingDraftAuthorityFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    var snapshot = try await open(runtime, facts: fixture.facts())
    for id in [DrawingCatalogEntryID.metricSquare40, .metricRectangle40x20] {
      snapshot = try applied(await runtime.submit(.init(projection: snapshot.projection,
        intent: .selectCatalogItem(id)), facts: fixture.facts()))
      let frame = try #require(snapshot.frame)
      #expect(frame.geometry.placement.cameraGeometry == nil)
      let center = try frame.cameraCenter
      let moved = try frame.translated(to: Point2(x: center.x + 1, y: center.y))
      snapshot = try applied(await runtime.submit(.init(projection: snapshot.projection,
        intent: .placeAtCameraPoint(.init(frame: fixture.frame.plotterExactFrameReference,
          point: try moved.cameraCenter))), facts: fixture.facts()))
      #expect(snapshot.plan?.placement.cameraGeometry == nil)
      #expect(try #require(snapshot.frame).geometry.isContained(in: fixture.drawableRegion))
    }
  }

  @Test("production frame edit seals one unsealed preview and applies while ambient frames advance")
  func productionFrozenFrameEdit() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let app = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(app)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime, workspace: app, environment: .simulated)
    try await completeSimulatedTipCalibration(app, simulator: harness.simulator)
    _ = await app.currentDrawingRunFacts(for: .simulated)
    let show = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.showTarget)))
    #expect(await app.submitPlotterUIRequest(show) == .accepted(requestID: show.id))
    let source = try #require(app.displayedFrame)
    func unsealed(_ delta: UInt64) throws -> DisplayedFrame {
      DisplayedFrame(source: source.source, frame: try StampedFrame(sequence: source.frame.sequence + delta,
        captureNanoseconds: source.frame.captureNanoseconds + delta, cameraConfigurationID: source.frame.cameraConfigurationID,
        width: source.frame.width, height: source.frame.height, rowBytes: source.frame.rowBytes,
        pixelFormat: source.frame.pixelFormat, bytes: source.frame.bytes, eagerlyMaterializeContentHash: false))
    }
    let initial = try unsealed(1), advanced = try unsealed(2)
    #expect(!initial.frame.contentHashIsMaterialized)
    app.actionSurfacePreview.publish(initial)
    let before = app.drawingDraftSnapshot
    let sessionID = UUID()
    #expect(await app.beginDrawingFrameEdit(id: sessionID, on: initial))
    let session = try #require(app.drawingFrameEditSession)
    #expect(session.frame.frame.contentHashIsMaterialized)
    #expect(initial.frame.contentHashIsMaterialized) // The selected frame shares its sealed digest storage.
    #expect(app.drawingDraftSnapshot.plan == before.plan)
    app.actionSurfacePreview.publish(advanced)
    let pinned = app.testActionSurfacePresentation.resolvingAmbientPreviewFrame(session.frame, forceRetainedFrame: true)
    #expect(pinned.displayedFrame == session.frame)
    #expect(!advanced.frame.contentHashIsMaterialized)
    _ = await app.currentDrawingRunFacts(for: .simulated)
    #expect(app.drawingDraftSnapshot.projection.externalFacts.displayedFrame == session.frame.plotterExactFrameReference)
    let frame = try #require(app.drawingDraftSnapshot.frame)
    let resized = try frame.resized(scale: before.uniformScale * 0.8, minimumScale: before.allowedScale.lowerBound)
    let placement = PlotterDrawingDraftCameraPlacement(frame: session.frame.plotterExactFrameReference,
      point: try resized.cameraCenter, uniformScale: resized.geometry.placement.uniformScale,
      draftRevision: app.drawingDraftSnapshot.projection.draftRevision)
    let ui = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingPlacement: placement)
    let request = try #require(ui.semantic.request(matching: .drawingDraft(.placeAtCameraPoint(placement))))
    #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    #expect(app.drawingDraftSnapshot.uniformScale == resized.geometry.placement.uniformScale)
    #expect(app.drawingDraftSnapshot.projection.externalFacts.drawableRegion == before.projection.externalFacts.drawableRegion)
    #expect(app.drawingDraftSnapshot.projection.externalFacts.registrationRevisionID == before.projection.externalFacts.registrationRevisionID)
    #expect(app.drawingFrameEditSession == nil)
    app.endDrawingFrameEdit(id: sessionID)
    #expect(app.actionSurfacePreview.displayedFrame == advanced)
    #expect(!advanced.frame.contentHashIsMaterialized)
    #expect(await app.beginDrawingFrameEdit(id: UUID(), on: advanced))
    let nextID = try #require(app.drawingFrameEditSession?.id)
    app.endDrawingFrameEdit(id: sessionID)
    #expect(app.drawingFrameEditSession?.id == nextID)
    let capRequest = try #require(app.testPlotterUIProjection(
      selectedItemID: .humanGuidedDiscovery(.penInteraction), includesLearningPath: true)
      .semantic.request(for: PlotterAppUIActionID.reidentifyPenCap))
    #expect(await app.submitPlotterUIRequest(capRequest) == .accepted(requestID: capRequest.id))
    #expect(app.drawingFrameEditSession == nil)
    let selection = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
    let capSurface = app.testActionSurfacePresentation
    #expect(capSurface.pointSelectionRequest == selection)
    #expect(try selection.matchesExactDisplayedFrame(#require(capSurface.displayedFrame)))
    app.endDrawingFrameEdit(id: nextID)
    #expect(app.drawingFrameEditSession == nil)
    await app.shutdown()
  }
}

extension PlotterDrawingDraftEpisodeTests {
  @Test("pending and staged frame edits exclude Draw until Apply or Cancel, while active Run excludes editing")
  func frameEditExcludesDrawingRun() async throws {
    let persistence = DraftPaperPersistenceProbe()
    let fixture = try await DrawingWorkbenchApplicationFixture.make(paperPersistence: persistence)
    defer { fixture.stores.remove() }
    let app = fixture.application
    try await fixture.submit(.showTarget)
    try await fixture.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let appliedBeforeEdit = try #require(app.drawingDraftSnapshot.plan)
    let cachedDraw = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    let frame = try #require(app.displayedFrame)

    // Hold an existing persistence await, so Edit installs its pending session
    // before it can finish preparing the exact Draft projection.
    await persistence.holdNextSave()
    let coverage = Task { try await fixture.submit(.assertPaperCoverage) }
    await persistence.waitUntilSaveStarted()
    let pendingID = UUID()
    let semanticBeforeBegin = app.semanticPresentationRevision
    let beginning = Task { @MainActor in await app.beginDrawingFrameEdit(id: pendingID, on: frame) }
    do {
      try await waitUntil { app.drawingFrameEditSession?.id == pendingID }
      #expect(app.semanticPresentationRevision > semanticBeforeBegin)
      let refused = await app.submitPlotterUIRequest(cachedDraw)
      guard case .refused(let reason) = refused else {
        throw FrameEditRunExclusionTestError.drawWasNotRefused
      }
      #expect(reason.reason == .unavailableAction)
      #expect(reason.remedy == "Apply or Cancel Frame Edit before drawing.")
      let pending = app.testPlotterUIProjection()
      #expect(pending.drawingStudio.runState == .unavailable(reason: reason.remedy))
      #expect(pending.semantic.request(matching: .drawingRun(.start)) == nil)
      #expect(await fixture.planGate.request == nil)
      let semanticBeforeCancel = app.semanticPresentationRevision
      app.endDrawingFrameEdit(id: pendingID)
      #expect(app.semanticPresentationRevision > semanticBeforeCancel)
      await persistence.releaseSave()
      try await coverage.value
      #expect(!(await beginning.value))
    } catch {
      app.endDrawingFrameEdit(id: pendingID)
      await persistence.releaseSave()
      _ = try? await coverage.value
      _ = await beginning.value
      await app.shutdown()
      throw error
    }
    #expect(app.drawingDraftSnapshot.plan == appliedBeforeEdit)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let afterCancel = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))

    let editID = UUID()
    #expect(await app.beginDrawingFrameEdit(id: editID, on: try #require(app.displayedFrame)))
    let session = try #require(app.drawingFrameEditSession)
    let draft = app.drawingDraftSnapshot
    let resized = try #require(draft.frame).resized(scale: draft.uniformScale * 0.8,
      minimumScale: draft.allowedScale.lowerBound)
    let placement = PlotterDrawingDraftCameraPlacement(frame: session.frame.plotterExactFrameReference,
      point: try resized.cameraCenter, uniformScale: resized.geometry.placement.uniformScale,
      draftRevision: draft.projection.draftRevision)
    let staged = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingPlacement: placement)
    #expect(staged.semantic.request(matching: .drawingRun(.start)) == nil)
    #expect(app.drawingDraftSnapshot.plan == appliedBeforeEdit)
    guard case .refused(let stagedRefusal) = await app.submitPlotterUIRequest(afterCancel) else {
      await app.shutdown()
      throw FrameEditRunExclusionTestError.drawWasNotRefused
    }
    #expect(stagedRefusal.remedy == "Apply or Cancel Frame Edit before drawing.")
    #expect(await fixture.planGate.request == nil)
    let apply = try #require(staged.semantic.request(matching: .drawingDraft(.placeAtCameraPoint(placement))))
    #expect(await app.submitPlotterUIRequest(apply) == .accepted(requestID: apply.id))
    #expect(app.drawingFrameEditSession == nil)
    let applied = try #require(app.drawingDraftSnapshot.plan)
    #expect(applied.placement == resized.geometry.placement)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let draw = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    let running = Task { await app.submitPlotterUIRequest(draw) }
    do {
      try await waitUntilAsync { await fixture.planGate.request != nil }
      #expect(await fixture.planGate.request?.plan == applied)
      #expect(!(await app.beginDrawingFrameEdit(id: UUID(), on: frame)))
      #expect(app.drawingFrameEditSession == nil)
      let capability = try #require(app.drawingRunSnapshot?.stopCapabilityID)
      #expect(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.stop(capability))) != nil)
    } catch {
      await fixture.planGate.release(.cancelled)
      _ = await running.value
      await app.shutdown()
      throw error
    }
    await fixture.planGate.release(.completed)
    #expect(await running.value == .accepted(requestID: draw.id))
    await app.shutdown()
  }

  @Test("cancelling a frame edit while Draft synchronization waits cannot resurrect retained video")
  func cancelledPendingFrameEdit() async throws {
    let persistence = DraftPaperPersistenceProbe(blocksSave: true)
    let runtime = PlotterDrawingDraftRuntime(paperPersistence: persistence)
    let harness = makeCausalSimulatorAppFixture(drawingDraftRuntime: runtime)
    let app = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(app)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime, workspace: app, environment: .simulated)
    try await completeSimulatedTipCalibration(app, simulator: harness.simulator)
    _ = await app.currentDrawingRunFacts(for: .simulated)
    let show = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.showTarget)))
    #expect(await app.submitPlotterUIRequest(show) == .accepted(requestID: show.id))
    let fixture = try draftAuthorityFixture(from: app)
    // Occupy the existing actor mutation boundary with a persistence await in
    // the other source state. No camera, controller or physical effect is used.
    let heldFacts = fixture.facts(environment: .live)
    let heldSnapshot = await runtime.synchronize(heldFacts)
    let held = Task { await runtime.submit(.init(projection: heldSnapshot.projection,
      intent: .assertPaperCoverage), facts: heldFacts) }
    await persistence.waitUntilSaveStarted()
    let id = UUID()
    let beginning = Task { @MainActor in await app.beginDrawingFrameEdit(id: id, on: fixture.frame) }
    do {
      try await waitUntilAsync { await runtime.pendingMutationCount > 0 }
      #expect(app.drawingFrameEditSession?.id == id)
      app.endDrawingFrameEdit(id: id)
      #expect(app.drawingFrameEditSession == nil)
    } catch {
      await persistence.releaseSave()
      _ = await held.value
      _ = await beginning.value
      await app.shutdown()
      throw error
    }
    await persistence.releaseSave()
    _ = await held.value
    #expect(!(await beginning.value))
    #expect(app.drawingFrameEditSession == nil)
    await app.shutdown()
  }
}

private enum FrameEditRunExclusionTestError: Error {
  case drawWasNotRefused
}
