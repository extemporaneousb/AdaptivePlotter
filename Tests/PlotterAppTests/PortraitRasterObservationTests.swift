import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterTestSupport
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

/// Software evidence only. The real vectorizer and observer see independently
/// rasterized paper pixels. The controller port supplies completed commands,
/// not observed paths; the Drawing Run owner builds and persists the record.
@Suite("Portrait raster observation and retrospective evidence", .serialized)
@MainActor
struct PortraitRasterObservationTests {
  @Test("an isolated crossing retains the unique support of both intended strokes")
  func crossingUsesUniqueSupport() async throws {
    let request = try crossingRequest(duplicated: false)
    let outcome = await VisionWorker().observePlannedDrawingInk(request)
    guard case .observed(let observation) = outcome else {
      Issue.record("Two 49-pixel strokes share only their center pixel: \(outcome)")
      return
    }
    #expect(observation.evidence.observedInk.count == 2)
    #expect(observation.evidence.observedInk.allSatisfy { $0.points.count >= 8 })
    #expect(observation.observedPixelCount == 97)
    #expect(observation.evidence.detectedPixelCount == 97)
    #expect(observation.evidence.ambiguousPixelCount == 1)
    #expect(observation.evidence.frames == request.frames)
    let encoded = try JSONEncoder().encode(observation.evidence)
    #expect(try JSONDecoder().decode(DrawingObservedInkEvidence.self, from: encoded) == observation.evidence)
    var legacy = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    legacy.removeValue(forKey: "detectedPixelCount")
    legacy.removeValue(forKey: "ambiguousPixelCount")
    let decodedLegacy = try JSONDecoder().decode(DrawingObservedInkEvidence.self,
      from: JSONSerialization.data(withJSONObject: legacy))
    #expect(decodedLegacy.detectedPixelCount == nil)
    #expect(decodedLegacy.ambiguousPixelCount == nil)
    #expect(decodedLegacy.observedInk == observation.evidence.observedInk)
  }

  @Test("wholly duplicated paths remain unidentifiable from the same raster")
  func duplicatedPathsRemainAmbiguous() async throws {
    let request = try crossingRequest(duplicated: true)
    let outcome = await VisionWorker().observePlannedDrawingInk(request)
    guard case .rejected(let rejection) = outcome,
      case .inkAmbiguous(let count) = rejection.reason else {
      Issue.record("Duplicated paths have no unique support: \(outcome)")
      return
    }
    #expect(count == 49)
    #expect(rejection.detectedPixelCount == 49)
    #expect(rejection.frames == request.frames)
  }

  @Test("vectorized portrait pixels pass ordinary Draw observation, archive and retrospective analysis",
    arguments: PortraitRasterWorkload.allCases)
  func vectorizedPortraitThroughRealObservation(_ workload: PortraitRasterWorkload) async throws {
    rasterReceipt("Portrait raster \(workload.rawValue): starting")
    // Production Drawing Run deliberately refuses SIM motion. This fixture
    // tests its LIVE route with synthetic, mutually consistent accepted data;
    // it supplies no physical evidence and never opens a hardware transport.
    let fixture = try await PortraitAcceptedPackageCache.load()
    let registration = try workload.registration(from: fixture)
    let optical = registration.applicability.opticalConfiguration
    #expect(optical.source == .live(CameraDeviceID(rawValue: "accepted-learning-fixture-camera")))
    #expect(optical.pixelFormat == .bgra8)
    let raster = workload.raster
    let program = try PortraitVectorizer.program(from: raster, pose: .front,
      style: workload.style, strokeStyle: StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(registration.applicability.toolAssembly.rawValue)))
    let bounds = registration.applicabilityRectangle
    let center = try Point2<MachineSpace>(x: (bounds.minX + bounds.maxX) / 2,
      y: (bounds.minY + bounds.maxY) / 2)
    var scale = 0.8 * min((bounds.maxX - bounds.minX) / program.fieldExtent.width,
      (bounds.maxY - bounds.minY) / program.fieldExtent.height)
    let executionPlan: ExecutionPlanRevision
    if workload == .fullResolutionDenseCrosshatch {
      // Exercise the same authoring intents as Show on Plotter Video. Retain
      // every vectorized stroke and use the largest canonical 0/90 fit.
      let draftRuntime = PlotterDrawingDraftRuntime()
      let authoringFacts = PlotterDrawingDraftExternalFacts(environment: .live,
        interactiveLearningIsComplete: true, displayedFrame: nil,
        opticalConfiguration: optical, registration: registration,
        drawableRegion: fixture.drawableRegion,
        toolAssemblyRevision: registration.applicability.toolAssembly,
        paper: fixture.borderRecord.paper, runInProgress: false, terminalRequiresNewPlan: false)
      let initial = await draftRuntime.synchronize(authoringFacts)
      let selected = await draftRuntime.submit(.init(projection: initial.projection,
        intent: .selectProgram(program)), facts: authoringFacts)
      #expect(selected.disposition == .applied)
      let fitted = await draftRuntime.submit(.init(projection: selected.snapshot.projection,
        intent: .fitInDrawableRegion), facts: authoringFacts)
      #expect(fitted.disposition == .applied)
      #expect(fitted.snapshot.rotationDegrees == 90)
      #expect(fitted.snapshot.uniformScale == fitted.snapshot.allowedScale.upperBound)
      scale = fitted.snapshot.uniformScale
      executionPlan = try #require(fitted.snapshot.plan)
      #expect(executionPlan.strokes.map(\.logicalStrokeID) == program.strokes.map(\.id))
      #expect(executionPlan.strokes.allSatisfy { fixture.drawableRegion.contains($0.path) })
      #expect(program.strokes.count == 191)
    } else {
      let draft = PlotterDrawingPlanningAdapter.buildDraft(program: program,
        machineCenter: center, uniformScale: scale, rotationDegrees: 0,
        drawableRegion: fixture.drawableRegion, registration: registration)
      executionPlan = try #require(draft.plan)
    }
    let intended = try #require(TipApplicabilityEvidencePolicy.project(
      paths: executionPlan.strokes.map(\.path), using: registration).attributableCameraPolylines)
    let xError = workload.hasSmallResidual ? 0.15 : 0.6
    let yError = workload.hasSmallResidual ? -0.1 : -0.4
    let hatchPitchMM = 2 * 100 / Double(raster.height - 1) * scale
    if workload.hasSmallResidual {
      #expect(max(abs(xError), abs(yError)) < hatchPitchMM / 4)
    } else if workload == .fullResolutionDenseCrosshatchAliased {
      #expect(abs(xError) > hatchPitchMM / 2)
    }
    if workload.style == .contours {
      #expect(xError == 0.6)
      #expect(yError == -0.4)
    }
    let realized = try executionPlan.strokes.map { stroke in
      try registration.cameraFromMachine.applying(to: Polyline<MachineSpace>(points:
        stroke.path.points.map { try Point2(x: $0.x + xError, y: $0.y + yError) }))
    }
    let configuration = CameraConfigurationID()
    let renderer = PaperSceneSimulator(width: optical.width, height: optical.height)
    let baseline = try renderer.render(strokes: [], sequence: 10,
      captureNanoseconds: 10, cameraConfigurationID: configuration)
    let post = workload == .fullResolutionDenseCrosshatch
      ? try finiteWidthPortraitRaster(plan: executionPlan, registration: registration,
        baseline: baseline, xError: xError, yError: yError)
      : try renderer.render(strokes: rasterStrokes(realized), sequence: 20,
        captureNanoseconds: 20, cameraConfigurationID: configuration)
    let baselineDisplayed = DisplayedFrame(source: optical.source, frame: baseline)
    let postDisplayed = DisplayedFrame(source: optical.source, frame: post)
    let paper = fixture.borderRecord.paper
    let paperCoverage = try PaperCoverageObservation(paper: paper,
      source: optical.source, frame: ExactFrameProvenance(frame: baseline),
      polygon: [Point2(x: 1, y: 1), Point2(x: Double(optical.width - 2), y: 1),
        Point2(x: Double(optical.width - 2), y: Double(optical.height - 2)),
        Point2(x: 1, y: Double(optical.height - 2))], method: .operatorAccepted,
      observedAt: RuntimeTimestamp(monotonicNanoseconds: 10),
      algorithmRevision: "synthetic-portrait-paper-v1",
      opticalConfiguration: optical, drawableRegion: fixture.drawableRegion)
    let plan = PlotterDrawingRunPlan(draftRevision: .init(rawValue: 1), program: program,
      placementID: UUID(), plan: executionPlan, evidenceRole: .ordinaryDrawing,
      paperCoverage: paperCoverage, registration: registration)
    let ready = drawingRunReadySnapshot(position: MachinePosition(
      point: try #require(executionPlan.strokes.last?.path.points.last)))
    let events = DrawingRunEventProbe()
    let interpreter = DrawingRunInterpreterProbe(ready: ready, events: events)
    let facts = DrawingRunFactProbe(PlotterDrawingRunExternalFacts(environment: .live,
      interactiveLearningIsComplete: true, plan: plan, paperCoverageIsCurrent: true,
      displayedFrame: baselineDisplayed, interpreter: ready, penActuationProfile: .initialDefaults))
    let camera = DrawingRunCameraProbe(frames: [baselineDisplayed, postDisplayed], events: events)
    let vision = PortraitRasterVisionPort()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = DrawingRunEvidenceStore(fileURL: directory.appendingPathComponent("ordinary-portrait.json"))
    let runtime = PlotterDrawingRunRuntime(facts: facts, interpreter: interpreter,
      camera: camera, vision: vision, evidence: DrawingRunEvidencePort(store: store),
      clock: DrawingRunEpisodeClock())
    _ = await runtime.restoreNoRedrawTruth(from: .absent, paper: paper, environment: .live)
    let projection = await runtime.synchronize(environment: .live)
    #expect(projection.readiness == .ready)
    let submission = await runtime.submit(.init(projection: projection.projection, intent: .start))
    let terminal = try #require(submission.snapshot.terminal)
    let record = terminal.record
    guard case .loaded(let archive) = await store.load() else {
      Issue.record("Actual Drawing Run record was not persisted")
      return
    }
    #expect(archive.records == [record])
    #expect(record.role == .ordinaryDrawing)
    #expect(record.plan.executionPlan == executionPlan)
    #expect(record.program.contentHash == program.contentHash)
    let request = try #require(await vision.request)
    let elapsed = await vision.elapsedSeconds
    rasterReceipt("Portrait raster \(workload.rawValue), \(optical.width)×\(optical.height): observer \(elapsed) seconds")
    #expect(request.intendedCameraPolylines == intended)
    #expect(request.frames.source == optical.source)
    #expect(request.maximumAssociationEvaluationCount == 5_000_000)
    #expect(request.maximumIntendedPointCount == 25_000)
    let analysis = DrawingRetrospectiveResidualAnalysis.evaluate(records: archive.records,
      registration: registration)
    let segments = intended.reduce(0) { $0 + $1.points.count - 1 }
    let points = intended.reduce(0) { $0 + $1.points.count }
    let actualOutcome = try #require(await vision.outcome)
    guard case .observed(let observation) = actualOutcome else {
      let rejectedPixels: Int
      if case .rejected(let rejection) = record.observation {
        rejectedPixels = rejection.detectedPixelCount ?? 0
        #expect(rejection.frames == request.frames)
      } else { rejectedPixels = 0 }
      #expect(analysis.constraints.isEmpty)
      #expect(analysis.candidate == nil)
      let support = try await rasterSupportDiagnostic(request)
      let diagnostic = "\(workload.rawValue): \(program.strokes.count) strokes, \(points) points, "
        + "\(segments) segments, \(rejectedPixels) detected pixels, all-pairs \(rejectedPixels * segments), "
        + "unchanged budget \(request.maximumAssociationEvaluationCount); \(support.summary); "
        + "actual Draw observation \(record.observation)"
      rasterReceipt(diagnostic)
      // These are explicit unresolved negatives: the 320-pixel camera cannot
      // distinguish all small/closely spaced paths, and the large dense hatch
      // translation exceeds half its physical pitch at either resolution.
      // The same full-resolution dense programs also have identifiable cases.
      if workload.expectsUnresolvedObservation, !support.unsupported.isEmpty {
        guard case .rejected(let rejection) = record.observation else {
          Issue.record("Unresolved geometry did not retain its typed rejection")
          return
        }
        switch rejection.reason {
        case .inkAmbiguous, .correspondenceUnavailable: break
        default: Issue.record("Unresolved paths do not explain \(rejection.reason)")
        }
        #expect(record.evidenceDisposition == .visionUnclear)
        #expect(record.executionFrontiers.inkVerifiedStrokeCount == 0)
        return
      }
      Issue.record("\(diagnostic)")
      return
    }
    #expect(record.evidenceDisposition == .attributable)
    #expect(!workload.expectsUnresolvedObservation)
    #expect(record.executionFrontiers.inkVerifiedStrokeCount == UInt32(program.strokes.count))
    #expect(observation.evidence.frames == request.frames)
    #expect(observation.evidence.observedInk.count == program.strokes.count)
    #expect(observation.evidence.observedInk != intended)
    let computation = try #require(observation.computation)
    rasterReceipt("Portrait raster \(workload.rawValue): \(program.strokes.count) strokes, \(segments) segments, "
      + "\(observation.observedPixelCount) pixels, \(observation.observedPixelCount * segments) all-pairs; "
      + "actual association bounds+projections \(computation.associationEvaluationCount)")
    #expect(computation.associationEvaluationCount <= request.maximumAssociationEvaluationCount)
    #expect(computation.maximumEvaluationCountBetweenCancellationChecks
      <= max(optical.width, VisionWorker.plannedDrawingCancellationEvaluationChunkSize))
    #expect(analysis.supportedStrokeCount == program.strokes.count)
    let candidate = try #require(analysis.candidate, "\(analysis.summary)")
    if workload == .fullResolutionDenseContours {
      rasterReceipt("Dense contour alignment (\(observation.alignment.shiftX),\(observation.alignment.shiftY)) "
        + "background MAD \(observation.alignment.backgroundMeanAbsoluteDifference); actual \(analysis.summary)")
      try await contourCorrespondenceDiagnostic(request: request, record: record,
        observed: observation.evidence, realized: realized, registration: registration,
        shiftX: observation.alignment.shiftX, shiftY: observation.alignment.shiftY)
    }
    // Pixel quantization and the observer's 4-pixel centreline bins are real
    // measurement limits; the separate exact-geometry fitter test is tighter.
    let tolerance = workload.isFullResolution ? 0.1 : 0.35
    #expect(abs(candidate.xMM - xError) < tolerance)
    #expect(abs(candidate.yMM - yError) < tolerance)
    if workload == .crosshatch {
      #expect(program.strokes.count == 41)
      #expect(xError == 0.6 && yError == -0.4)
      let inverse = try registration.cameraFromMachine.inverted()
      // A half-pixel coordinate cell maps through this exact calibration to
      // these per-axis quantization bounds. Keep the existing 0.35 mm ceiling.
      let xQuantizationMM = 0.5 * (abs(inverse.m11) + abs(inverse.m12))
      let yQuantizationMM = 0.5 * (abs(inverse.m21) + abs(inverse.m22))
      #expect(abs(candidate.xMM - xError) < min(tolerance, xQuantizationMM))
      #expect(abs(candidate.yMM - yError) < min(tolerance, yQuantizationMM))
      rasterReceipt("Resolved 41-stroke crosshatch: injected X \(xError), Y \(yError) mm; "
        + "fitted X \(candidate.xMM), Y \(candidate.yMM) mm; "
        + "half-pixel bounds X \(xQuantizationMM), Y \(yQuantizationMM) mm; "
        + "normal RMS \(candidate.priorRMSMM) → \(candidate.fittedRMSMM) mm.")
    }
    #expect(candidate.fittedRMSMM < candidate.priorRMSMM)
    #expect(analysis.constraints.allSatisfy { $0.frames == request.frames
      && $0.recordID == record.recordID && $0.planContentHash == executionPlan.contentHash })
  }

  private func crossingRequest(duplicated: Bool) throws -> PlannedDrawingObservationRequest {
    let horizontal = try Polyline<CameraPixelSpace>(points: [Point2(x: 8, y: 32), Point2(x: 56, y: 32)])
    let vertical = try Polyline<CameraPixelSpace>(points: [Point2(x: 32, y: 8), Point2(x: 32, y: 56)])
    let intended = [horizontal, duplicated ? horizontal : vertical]
    let configuration = CameraConfigurationID()
    let renderer = PaperSceneSimulator(width: 64, height: 64)
    let baseline = try renderer.render(strokes: [], sequence: 1,
      captureNanoseconds: 1, cameraConfigurationID: configuration)
    let post = try renderer.render(strokes: rasterStrokes(intended), sequence: 2,
      captureNanoseconds: 2, cameraConfigurationID: configuration)
    return try PlannedDrawingObservationRequest(frames: DrawingObservationFramePair(source: .simulated,
      baseline: ExactFrameProvenance(frame: baseline), post: ExactFrameProvenance(frame: post)),
      localPreDrawingBaseline: SamePoseFrameSample(displayedFrame: DisplayedFrame(source: .simulated,
        frame: baseline), controllerPosition: MachinePosition(x: 0, y: 0)),
      postDrawing: SamePoseFrameSample(displayedFrame: DisplayedFrame(source: .simulated,
        frame: post), controllerPosition: MachinePosition(x: 0, y: 0)),
      region: PixelRect(x: 4, y: 4, width: 56, height: 56), intendedCameraPolylines: intended,
      thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20), controllerPositionToleranceMM: 0.001,
      alignmentSearchRadiusPixels: 8, maximumAlignmentShiftPixels: 4,
      maximumBackgroundMeanAbsoluteDifference: 12,
      observerRevision: AlgorithmRevisionEvidence(component: "planned-drawing-observer",
        revision: VisionWorker.plannedDrawingObserverRevision))
  }
}

private func rasterReceipt(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

private actor PortraitRasterVisionPort: PlotterDrawingRunVisionPort {
  private(set) var request: PlannedDrawingObservationRequest?
  private(set) var outcome: PlannedDrawingObservationOutcome?
  private(set) var elapsedSeconds = 0.0
  private let worker = VisionWorker()

  func observePlannedDrawingInk(_ request: PlannedDrawingObservationRequest) async -> PlannedDrawingObservationOutcome {
    self.request = request
    let started = Date()
    let result = await worker.observePlannedDrawingInk(request)
    elapsedSeconds = Date().timeIntervalSince(started)
    outcome = result
    return result
  }
}

@MainActor
private enum PortraitAcceptedPackageCache {
  private static var value: CompleteAcceptedLearningFixture?

  static func load() async throws -> CompleteAcceptedLearningFixture {
    if let value { return value }
    let accepted = try await CompleteAcceptedLearningFixture.make()
    value = accepted
    return accepted
  }
}

private func rasterStrokes(_ paths: [Polyline<CameraPixelSpace>]) -> [SimulatedPaperStroke] {
  paths.flatMap { path in
    zip(path.points, path.points.dropFirst()).map { a, b in
      SimulatedPaperStroke(start: PaperPixelPoint(x: Int(a.x.rounded()), y: Int(a.y.rounded())),
        end: PaperPixelPoint(x: Int(b.x.rounded()), y: Int(b.y.rounded())))
    }
  }
}

/// Independent geometric ink fixture. A round pen covers a machine-space
/// capsule of its planned nominal width; the calibrated affine mapping turns
/// that footprint into camera pixels. No observed paths enter the renderer.
private func finiteWidthPortraitRaster(
  plan: ExecutionPlanRevision, registration: TipCameraRegistration,
  baseline: StampedFrame, xError: Double, yError: Double
) throws -> StampedFrame {
  let cameraFromMachine = registration.cameraFromMachine
  let machineFromCamera = try cameraFromMachine.inverted()
  var bytes = [UInt8](baseline.bytes.data)
  for stroke in plan.strokes {
    let radius = stroke.style.nominalLineWidth / 2
    let cameraRadiusX = radius * hypot(cameraFromMachine.m11, cameraFromMachine.m12)
    let cameraRadiusY = radius * hypot(cameraFromMachine.m21, cameraFromMachine.m22)
    for (start, end) in zip(stroke.path.points, stroke.path.points.dropFirst()) {
      let a = try Point2<MachineSpace>(x: start.x + xError, y: start.y + yError)
      let b = try Point2<MachineSpace>(x: end.x + xError, y: end.y + yError)
      let ca = try cameraFromMachine.applying(to: a), cb = try cameraFromMachine.applying(to: b)
      let minX = max(0, Int(floor(min(ca.x, cb.x) - cameraRadiusX)))
      let maxX = min(baseline.width - 1, Int(ceil(max(ca.x, cb.x) + cameraRadiusX)))
      let minY = max(0, Int(floor(min(ca.y, cb.y) - cameraRadiusY)))
      let maxY = min(baseline.height - 1, Int(ceil(max(ca.y, cb.y) + cameraRadiusY)))
      guard minX <= maxX, minY <= maxY else { continue }
      let dx = b.x - a.x, dy = b.y - a.y
      let squaredLength = dx * dx + dy * dy
      for y in minY...maxY {
        for x in minX...maxX {
          let sample = try machineFromCamera.applying(to: Point2(x: Double(x), y: Double(y)))
          let t = squaredLength == 0 ? 0
            : min(1, max(0, ((sample.x - a.x) * dx + (sample.y - a.y) * dy) / squaredLength))
          let ex = sample.x - a.x - t * dx, ey = sample.y - a.y - t * dy
          if ex * ex + ey * ey <= radius * radius {
            let offset = y * baseline.rowBytes + x * baseline.pixelFormat.bytesPerPixel
            bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0
          }
        }
      }
    }
  }
  return try StampedFrame(sequence: 20, captureNanoseconds: 20,
    cameraConfigurationID: baseline.cameraConfigurationID,
    width: baseline.width, height: baseline.height, rowBytes: baseline.rowBytes,
    pixelFormat: baseline.pixelFormat, bytes: OwnedFrameBytes(bytes))
}

enum PortraitRasterWorkload: String, CaseIterable, Sendable {
  case contours, crosshatch, denseContours, denseCrosshatch
  case fullResolutionDenseContours, fullResolutionDenseCrosshatch
  case fullResolutionDenseCrosshatchAliased
  case fullResolutionDenseCrosshatchThin

  var isFullResolution: Bool {
    isIdentifiableDensePositive || self == .fullResolutionDenseCrosshatchAliased
      || self == .fullResolutionDenseCrosshatchThin
  }

  var isIdentifiableDensePositive: Bool {
    self == .fullResolutionDenseContours || self == .fullResolutionDenseCrosshatch
  }

  var hasSmallResidual: Bool {
    self == .fullResolutionDenseCrosshatch || self == .fullResolutionDenseCrosshatchThin
  }

  var expectsUnresolvedObservation: Bool {
    self == .denseContours || self == .denseCrosshatch
      || self == .fullResolutionDenseCrosshatchAliased
      || self == .fullResolutionDenseCrosshatchThin
  }

  var style: PortraitStyle {
    self == .contours || self == .denseContours || self == .fullResolutionDenseContours
      ? .contours : .crosshatch
  }

  func registration(from fixture: CompleteAcceptedLearningFixture) throws -> TipCameraRegistration {
    guard isFullResolution else { return fixture.registration }
    let old = fixture.registration.applicability.opticalConfiguration
    // Explicit synthetic resample to the inventoried C920 output dimensions.
    // Preserve aspect ratio and pad horizontally; this is generated test
    // geometry, not a claim of having measured the physical C920 calibration.
    let width = 1_920, height = 1_080
    let scale = min(Double(width) / Double(old.width), Double(height) / Double(old.height))
    let transform = try AffineTransform2<CameraPixelSpace, CameraPixelSpace>(
      m11: scale, m12: 0, m21: 0, m22: scale,
      tx: (Double(width) - scale * Double(old.width)) / 2,
      ty: (Double(height) - scale * Double(old.height)) / 2)
    let optical = try CameraOpticalConfigurationIdentity(source: old.source,
      sensorFormat: old.sensorFormat, width: width, height: height,
      pixelFormat: old.pixelFormat, orientation: old.orientation, mirrored: old.mirrored,
      digitalZoomFactor: old.digitalZoomFactor, lensIdentity: old.lensIdentity,
      focusConfiguration: old.focusConfiguration, mountRevision: old.mountRevision,
      reframingRevision: old.reframingRevision)
    let evidence = try KnownCameraPixelRebaseEvidence(fromOpticalConfiguration: old,
      toOpticalConfiguration: optical, transform: transform,
      captureSessionID: CameraCaptureSessionID(),
      evidenceSHA256: canonicalDigest(of: transform).description,
      algorithmRevision: "synthetic-aspect-preserving-resample-1920x1080-v1")
    return try fixture.registration.applyingKnownPixelTransform(evidence)
  }

  var raster: PortraitRaster {
    if self == .contours || self == .crosshatch { return portraitTestRaster() }
    // The analyzer's full 160-pixel long edge, ordinary six contour levels,
    // curved facial shading, eyes, lips and textured hair. No vectorizer or
    // observer budget is reduced or increased for this dense software image.
    let width = 128, height = 160
    let luminance = (0..<(width * height)).map { index -> Double in
      let x = (Double(index % width) - 63.5) / 49
      let y = (Double(index / width) - 79.5) / 70
      let radius = x*x + y*y
      guard radius < 1 else { return 1 }
      var value = 0.28 + 0.45 * radius + 0.09 * x
      let eyes = exp(-pow((abs(x) - 0.34) / 0.17, 2) - pow((y + 0.18) / 0.09, 2))
      let lips = exp(-pow(x / 0.32, 2) - pow((y - 0.42) / 0.045, 2))
      value -= 0.3 * eyes + 0.25 * lips
      if y < -0.42 {
        value = 0.26 + 0.18 * sin(28 * x + 6 * y) + 0.09 * cos(31 * y - 4 * x)
      }
      return min(0.95, max(0.03, value))
    }
    return PortraitRaster(width: width, height: height, luminance: luminance,
      provenance: "synthetic-dense-face-128x160-v1", analysisSummary: "Synthetic dense face raster")
  }
}

private struct PortraitUnsupportedStroke {
  let index: Int
  let length: Double
  let uniquePixels: Int
  let occupiedBins: Int
  let totalBins: Int
}

private struct PortraitSupportDiagnostic {
  let detectedPixels: Int
  let ambiguousPixels: Int
  let unsupported: [PortraitUnsupportedStroke]
  var budgetExceeded = false

  var summary: String {
    if budgetExceeded { return "support diagnosis not repeated beyond the existing association budget" }
    let detail = unsupported.prefix(16).map {
      String(format: "stroke%d length%.2fpx unique%d bins%d/%d", $0.index,
        $0.length, $0.uniquePixels, $0.occupiedBins, $0.totalBins)
    }.joined(separator: "; ")
    return "support: \(detectedPixels) detected, \(ambiguousPixels) tied, \(unsupported.count) unsupported [\(detail)]"
  }
}

/// Diagnose the same core association on these independent raster pixels only.
/// Their identical white background and bounded ink exclusion imply the exact
/// zero shift (the production alignment tie-break prefers zero). This never
/// fabricates an observed path or changes the archived production result.
private func rasterSupportDiagnostic(_ request: PlannedDrawingObservationRequest) async throws -> PortraitSupportDiagnostic {
  let ink = try await VisionWorker.cancellableNewInkPixelEvaluation(
    from: request.localPreDrawingBaseline.frame, to: request.postDrawing.frame,
    region: request.region, thresholds: request.thresholds,
    baseComputation: .zero, checkpointHandler: nil)
  let evaluation: VisionWorker.CancellablePlannedInkAssociationEvaluation
  do {
    evaluation = try await VisionWorker.cancellableCorrespondenceAssociation(ink.pixels,
      with: request.intendedCameraPolylines, region: request.region, observationShiftX: 0, observationShiftY: 0,
      ambiguityTolerance: request.associationAmbiguityTolerancePixels,
      maximumEvaluationCount: request.maximumAssociationEvaluationCount,
      baseComputation: .zero, checkpointHandler: nil)
  } catch VisionWorker.PlannedAssociationError.evaluationBudgetExceeded {
    return PortraitSupportDiagnostic(detectedPixels: ink.pixels.count, ambiguousPixels: 0,
      unsupported: [], budgetExceeded: true)
  }
  var unsupported: [PortraitUnsupportedStroke] = []
  for index in request.intendedCameraPolylines.indices {
    let path = request.intendedCameraPolylines[index]
    let pixels = evaluation.association.byPolyline[index]
    let binCount = min(request.maximumCentrelineSampleCountPerPolyline,
      max(2, Int(ceil(path.length / request.centrelineSampleSpacingPixels))))
    let occupied = Set(pixels.map { pixel in
      min(binCount - 1, max(0, Int(floor(pixel.alongDistance / path.length * Double(binCount)))))
    }).count
    if pixels.count < request.minimumInkPixelsPerPolyline || occupied < 2 {
      unsupported.append(PortraitUnsupportedStroke(index: index, length: path.length,
        uniquePixels: pixels.count, occupiedBins: occupied, totalBins: binCount))
    }
  }
  return PortraitSupportDiagnostic(detectedPixels: ink.pixels.count,
    ambiguousPixels: evaluation.association.ambiguousPixelCount, unsupported: unsupported)
}

/// Temporary causal diagnosis: independently render each known realization in
/// a small image to retain its generating stroke identity. These labels never
/// enter Vision, the actual archive, or the production residual result.
private func contourCorrespondenceDiagnostic(
  request: PlannedDrawingObservationRequest, record: DrawingRunEvidenceRecord,
  observed: DrawingObservedInkEvidence, realized: [Polyline<CameraPixelSpace>],
  registration: TipCameraRegistration, shiftX: Int, shiftY: Int
) async throws {
  var sources: [VisionWorker.InkPixel: Set<Int>] = [:]
  for (index, path) in realized.enumerated() {
    let left = Int(floor(path.points.map(\.x).min()!)) - 1
    let top = Int(floor(path.points.map(\.y).min()!)) - 1
    let width = Int(ceil(path.points.map(\.x).max()!)) - left + 2
    let height = Int(ceil(path.points.map(\.y).max()!)) - top + 2
    let local = try Polyline<CameraPixelSpace>(points: path.points.map {
      try Point2(x: $0.x - Double(left), y: $0.y - Double(top))
    })
    let frame = try PaperSceneSimulator(width: width, height: height).render(
      strokes: rasterStrokes([local]), sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: CameraConfigurationID())
    let bytes = [UInt8](frame.bytes.data)
    for y in 0..<height {
      for x in 0..<width where bytes[y * frame.rowBytes + x * 4] == 0 {
        sources[.init(x: x + left, y: y + top), default: []].insert(index)
      }
    }
  }
  let ink = try await VisionWorker.cancellableNewInkPixelEvaluation(
    from: request.localPreDrawingBaseline.frame, to: request.postDrawing.frame,
    region: request.region, thresholds: request.thresholds,
    observationShiftX: shiftX, observationShiftY: shiftY,
    baseComputation: .zero, checkpointHandler: nil)
  #expect(shiftX == 0 && shiftY == 0)
  #expect(Set(ink.pixels) == Set(sources.keys))
  let association = try await VisionWorker.cancellableCorrespondenceAssociation(ink.pixels,
    with: request.intendedCameraPolylines, region: request.region, observationShiftX: shiftX,
    observationShiftY: shiftY, ambiguityTolerance: request.associationAmbiguityTolerancePixels,
    maximumEvaluationCount: request.maximumAssociationEvaluationCount,
    baseComputation: .zero, checkpointHandler: nil)
  var assigned = 0, wrongSource = 0
  var wrongByPath: [(index: Int, wrong: Int, count: Int)] = []
  for (index, pixels) in association.association.byPolyline.enumerated() {
    let wrong = pixels.filter { pixel in
      let key = VisionWorker.InkPixel(x: Int(pixel.point.x) - shiftX,
        y: Int(pixel.point.y) - shiftY)
      return sources[key]?.contains(index) != true
    }.count
    assigned += pixels.count
    wrongSource += wrong
    wrongByPath.append((index, wrong, pixels.count))
  }
  var intendedSquared = 0.0, realizedSquared = 0.0
  var sampleCount = 0
  for index in observed.observedInk.indices {
    for point in observed.observedInk[index].points {
      intendedSquared += pow(VisionWorker.nearestProjection(of: point,
        onto: request.intendedCameraPolylines[index]).distance, 2)
      realizedSquared += pow(VisionWorker.nearestProjection(of: point,
        onto: realized[index]).distance, 2)
      sampleCount += 1
    }
  }
  let pathDetail = wrongByPath.sorted { $0.wrong > $1.wrong }.prefix(8).map {
    "stroke\($0.index) \($0.wrong)/\($0.count)"
  }.joined(separator: ", ")
  rasterReceipt("Dense contour source correspondence: \(wrongSource)/\(assigned) assigned pixels "
    + "came from another realized stroke; \(association.association.ambiguousPixelCount) excluded ties; \(pathDetail). "
    + "Binned sample RMS to intended \(sqrt(intendedSquared / Double(sampleCount)))px, "
    + "to its true realization \(sqrt(realizedSquared / Double(sampleCount)))px; "
    + "correspondence reference (\(association.matchingTranslationX),\(association.matchingTranslationY)).")
  // This synthetic counterfactual bypasses raster association solely to isolate
  // the existing fitter. It is never persisted or substituted for actual ink.
  let ideal = try DrawingObservedInkEvidence(frames: observed.frames,
    intendedInk: observed.intendedInk, observedInk: realized, residual: nil,
    algorithmRevisions: [AlgorithmRevisionEvidence(component: "synthetic-ideal-path-counterfactual", revision: "1")])
  let counterfactual = try DrawingRunEvidenceRecord(runID: record.runID,
    requestID: record.requestID, role: record.role, evidenceDisposition: record.evidenceDisposition,
    requestFrontier: record.requestFrontier, executionFrontiers: record.executionFrontiers,
    executionDisposition: record.executionDisposition, program: record.program,
    placement: record.placement, plan: record.plan, planningProvenance: record.planningProvenance,
    tipCalibration: record.tipCalibration, paper: record.paper, observation: .observed(ideal),
    recordedAt: record.recordedAt)
  let idealAnalysis = DrawingRetrospectiveResidualAnalysis.evaluate(records: [counterfactual],
    registration: registration)
  rasterReceipt("Dense contour ideal-path counterfactual (not actual evidence): \(idealAnalysis.summary)")
  let idealFit = try #require(idealAnalysis.candidate)
  #expect(abs(idealFit.xMM - 0.6) < 0.02)
  #expect(abs(idealFit.yMM + 0.4) < 0.02)
}
