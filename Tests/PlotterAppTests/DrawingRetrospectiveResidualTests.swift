import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Ordinary portrait retrospective learning", .serialized)
@MainActor
struct DrawingRetrospectiveResidualTests {
  @Test("cancellation after rank-sufficient rematching never publishes a partial candidate")
  func cancellationDuringRematchingDoesNotFitSubset() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let program = try orthogonalProgram(style: f.plan.program.strokes[0].style)
    let record = try makeRecord(f, program: program, xError: 0.2, yError: 0.1)
    let task = Task {
      var rematched: [DrawingNormalResidualSample] = []
      let analysis = DrawingRetrospectiveResidualAnalysis.evaluate(records: [record], registration: f.registration,
        samplingCheckpoint: { iteration, sample in
          guard iteration > 0 else { return }
          rematched.append(sample)
          if (try? DrawingTranslationResidualCandidate(samples: rematched)) != nil {
            withUnsafeCurrentTask { $0?.cancel() }
          }
        })
      return (analysis, rematched)
    }
    let (analysis, rematched) = await task.value
    #expect(task.isCancelled)
    #expect(try DrawingTranslationResidualCandidate(samples: rematched).sampleCount >= 3)
    #expect(analysis.candidate == nil)
    #expect(analysis.summary.contains("cancelled"))
    #expect(record.role == .ordinaryDrawing)
  }

  @Test("constant XY fitting retains its existing two-millimeter vector range", arguments: [1.4, 1.5])
  func translationRangeIsNotExpanded(component: Double) async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let record = try makeRecord(f, program: orthogonalProgram(style: f.plan.program.strokes[0].style),
      xError: component, yError: component)
    let analysis = DrawingRetrospectiveResidualAnalysis.evaluate(records: [record], registration: f.registration)
    if hypot(component, component) < 2 {
      let candidate = try #require(analysis.candidate)
      #expect(abs(candidate.xMM - component) < 1e-8)
      #expect(abs(candidate.yMM - component) < 1e-8)
    } else {
      #expect(analysis.candidate == nil)
      #expect(!analysis.constraints.isEmpty)
      #expect(analysis.summary.contains("2 mm"))
    }
  }

  private func orthogonalProgram(style: StrokeStyle) throws -> DrawingProgram {
    try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 100, height: 100),
      strokes: [
        LogicalStroke(id: StrokeID(), path: Polyline(points: [Point2(x: 10, y: 20), Point2(x: 90, y: 20)]),
          style: style, ordering: 0),
        LogicalStroke(id: StrokeID(), path: Polyline(points: [Point2(x: 20, y: 10), Point2(x: 20, y: 90)]),
          style: style, ordering: 1)],
      source: DrawingSourceProvenance(kind: "residual-test", sourceIdentifier: "two-normal-directions"))
  }

  @Test("mismatched raw archive provenance is retained and excluded from residual fitting",
    arguments: RetrospectiveMismatch.allCases)
  func mismatchedProvenanceIsDiagnostic(_ mismatch: RetrospectiveMismatch) async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .contours, strokeStyle: f.plan.program.strokes[0].style)
    let record = try makeRecord(f, program: program, xError: 0.20, yError: -0.12, mismatch: mismatch)
    let encoded = try JSONEncoder().encode(record)
    let retained = try JSONDecoder().decode(DrawingRunEvidenceRecord.self, from: encoded)
    let result = DrawingRetrospectiveResidualAnalysis.evaluate(records: [retained], registration: f.registration)
    #expect(result.candidate == nil)
    #expect(result.constraints.isEmpty)
    #expect(result.supportedStrokeCount == 0)
    #expect(result.summary.contains(mismatch.reason))
    #expect(retained == record)
    #expect(retained.role == .ordinaryDrawing)
  }

  @Test("a dense ordinary portrait archive learns a known XY residual after drawing without role mutation",
    arguments: [0.20, 0.60])
  func curvedPortraitLearnsTranslation(xError: Double) async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .contours, strokeStyle: f.plan.program.strokes[0].style)
    #expect(program.source.kind == "portrait")
    #expect(program.strokes.reduce(0) { $0 + $1.path.points.count } > 100)
    #expect(program.strokes.contains { $0.path.points.count > 4 })
    let yError = -0.6 * xError
    let record = try makeRecord(f, program: program, xError: xError, yError: yError)
    if case .observed(let observed) = record.observation {
      #expect(observed.frames.source == f.registration.applicability.opticalConfiguration.source)
      #expect(observed.frames.baseline.width == f.registration.applicability.opticalConfiguration.width)
      #expect(observed.frames.baseline.height == f.registration.applicability.opticalConfiguration.height)
      #expect(observed.frames.baseline.pixelFormat == f.registration.applicability.opticalConfiguration.pixelFormat)
    }
    let bytes = try JSONEncoder().encode(record)
    let archived = try JSONDecoder().decode(DrawingRunEvidenceRecord.self, from: bytes)
    let runtime = PlotterDrawingDraftRuntime()
    let facts = PlotterDrawingDraftExternalFacts(environment: .live,
      interactiveLearningIsComplete: true, displayedFrame: f.previewFrame,
      opticalConfiguration: f.registration.applicability.opticalConfiguration,
      registration: f.registration, drawableRegion: f.drawableRegion,
      toolAssemblyRevision: f.registration.applicability.toolAssembly, paper: f.paper,
      runInProgress: false, terminalRequiresNewPlan: true, coverageRecords: [archived])
    let original = await runtime.synchronize(facts)
    let selected = await runtime.submit(.init(projection: original.projection,
      intent: .selectResidualRecord(archived.recordID, selected: true)), facts: facts)
    #expect(selected.disposition == .applied)
    let analyzed = await runtime.submit(.init(projection: selected.snapshot.projection,
      intent: .analyzeSelectedResiduals), facts: facts)
    #expect(analyzed.disposition == .applied)
    let result = try #require(analyzed.snapshot.residualAnalysis)
    let fit = try #require(result.candidate)
    #expect(abs(fit.xMM - xError) < 0.035)
    #expect(abs(fit.yMM - yError) < 0.035)
    #expect(fit.fittedRMSMM < fit.priorRMSMM)
    #expect(result.supportedStrokeCount > 0)
    #expect(result.constraints.allSatisfy { $0.recordID == record.recordID && $0.planRevisionID == record.plan.revisionID
      && $0.planContentHash == record.plan.contentHash
      && $0.registration == record.tipCalibration })
    #expect(result.constraints.contains { abs($0.sample.normalX) > 0.1 && abs($0.sample.normalY) > 0.1 })
    #expect(result.summary.contains("no independent holdout"))
    #expect(analyzed.snapshot.projection.draftRevision == original.projection.draftRevision)
    #expect(analyzed.snapshot.plan?.revisionID == original.plan?.revisionID)
    #expect(analyzed.snapshot.placementID == original.placementID)
    #expect(archived == record)
    #expect(archived.role == .ordinaryDrawing)
  }

  @Test("single-direction observations retain residuals and report unidentifiable XY")
  func parallelPathsDoNotInventSecondComponent() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: Size2(width: 100, height: 100),
      strokes: [LogicalStroke(id: StrokeID(), path: Polyline(points: [Point2(x: 10, y: 50),
        Point2(x: 90, y: 50)]), style: f.plan.program.strokes[0].style, ordering: 0)],
      source: DrawingSourceProvenance(kind: "residual-test", sourceIdentifier: "parallel-paths"))
    let record = try makeRecord(f, program: program, xError: 0, yError: 0.3)
    let result = DrawingRetrospectiveResidualAnalysis.evaluate(records: [record], registration: f.registration)
    #expect(result.candidate == nil)
    #expect(!result.constraints.isEmpty)
    #expect(result.constraints.allSatisfy { abs($0.sample.errorMM - 0.3) < 1e-8 })
    #expect(result.summary.contains("unidentifiable"))
    #expect(result.summary.contains("Tangential error"))
  }

  @Test("reserved holdouts remain reserved and mismatched calibration stays diagnostic")
  func holdoutAndCalibrationProvenance() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let holdout = try makeRecord(f, program: f.plan.program, xError: 0.2, yError: 0.1, role: .reservedHoldout)
    #expect(DrawingResidualRecordSummary(record: holdout, isSelected: false).role == .reservedHoldout)
    let excluded = DrawingRetrospectiveResidualAnalysis.evaluate(records: [holdout], registration: f.registration)
    #expect(excluded.constraints.isEmpty)
    #expect(excluded.candidate == nil)
    #expect(excluded.summary.contains("retain their original role"))
    #expect(holdout.role == .reservedHoldout)
    let ordinary = try makeRecord(f, program: f.plan.program, xError: 0.2, yError: 0.1)
    #expect(DrawingResidualRecordSummary(record: ordinary, isSelected: true).role == .ordinaryDrawing)
    let unavailable = DrawingRetrospectiveResidualAnalysis.evaluate(records: [ordinary], registration: nil)
    #expect(unavailable.constraints.isEmpty)
    #expect(unavailable.summary.contains("current accepted calibration"))
  }

  private func makeRecord(_ f: DrawingRunEpisodeFixture, program: DrawingProgram,
                          xError: Double, yError: Double,
                          role: BorderValidationEvidenceRole = .ordinaryDrawing,
                          mismatch: RetrospectiveMismatch? = nil) throws -> DrawingRunEvidenceRecord {
    let plan = try #require(PlotterDrawingPlanningAdapter.buildDraft(program: program,
      machineCenter: nil, uniformScale: 0.25, rotationDegrees: 0,
      drawableRegion: f.drawableRegion, registration: f.registration).plan)
    var intended = try plan.strokes.map { try f.registration.cameraFromMachine.applying(to: $0.path) }
    if mismatch == .intendedGeometry, let last = intended.last {
      intended[intended.count - 1] = try Polyline(points: last.points.map { try Point2(x: $0.x + 1, y: $0.y) })
    }
    let measured = try plan.strokes.map { stroke in
      try f.registration.cameraFromMachine.applying(to: Polyline<MachineSpace>(points:
        stroke.path.points.map { try Point2(x: $0.x + xError, y: $0.y + yError) }))
    }
    let optical = f.registration.applicability.opticalConfiguration
    let width = optical.width + (mismatch == .imageGeometry ? 1 : 0)
    let pixelFormat: FramePixelFormat = mismatch == .pixelFormat
      ? (optical.pixelFormat == .gray8 ? .bgra8 : .gray8) : optical.pixelFormat
    let configuration = CameraConfigurationID()
    func frame(_ sequence: UInt64) throws -> StampedFrame {
      try StampedFrame(id: FrameID(), sequence: sequence, captureNanoseconds: sequence,
        cameraConfigurationID: configuration, width: width, height: optical.height,
        rowBytes: width * pixelFormat.bytesPerPixel, pixelFormat: pixelFormat,
        bytes: OwnedFrameBytes(Array(repeating: UInt8(sequence), count: width * optical.height * pixelFormat.bytesPerPixel)))
    }
    let frames = try DrawingObservationFramePair(source: mismatch == .cameraSource
      ? .live(CameraDeviceID(rawValue: "mismatched-archive-camera")) : optical.source,
      baseline: ExactFrameProvenance(frame: frame(10)), post: ExactFrameProvenance(frame: frame(20)))
    let observation = try DrawingObservedInkEvidence(frames: frames, intendedInk: intended, observedInk: measured,
      residual: DrawingResidualEvidence(correspondenceCount: UInt32(measured.count), rootMeanSquarePixels: 0.4,
        maximumPixels: 0.5, rootMeanSquareCrossTrackPixels: 0.3),
      algorithmRevisions: [AlgorithmRevisionEvidence(component: "synthetic-translated-portrait", revision: "1")])
    let count = UInt32(plan.strokes.count + (mismatch == .frontiers ? 1 : 0))
    let differentHash = try Digest(bytes: Array(repeating: 3, count: 32))
    let provenance = mismatch == .planProvenance ? DrawingPlanningProvenance(
      modelRevisionID: plan.provenance.modelRevisionID, modelContentHash: differentHash,
      registrationRevisionID: plan.provenance.registrationRevisionID,
      registrationContentHash: plan.provenance.registrationContentHash) : plan.provenance
    let placement = try DrawingPlacementEvidenceReference(placementID: UUID(), placement: plan.placement)
    let paper = mismatch == .contactPlane ? PaperRevisionContext(instance: f.paper.instance,
      contactPlane: PaperContactPlaneRevision()) : f.paper
    return try DrawingRunEvidenceRecord(runID: RunID(), requestID: UUID(), role: role,
      evidenceDisposition: .attributable, requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: count, commandedStrokeCount: count,
        controllerCompletedStrokeCount: count, inkVerifiedStrokeCount: count), executionDisposition: .completed,
      program: DrawingProgramEvidenceReference(programID: mismatch == .programID ? ProgramID() : program.id,
        contentHash: mismatch == .programHash ? differentHash : program.contentHash, source: program.source),
      placement: mismatch == .placementHash ? DrawingPlacementEvidenceReference(
        placementID: placement.placementID, contentHash: differentHash) : placement,
      plan: DrawingExecutionPlanEvidenceReference(plan: plan), planningProvenance: provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(acceptedRevisionID: f.registration.acceptedRevisionID,
        registrationEvidenceSHA256: mismatch == .registrationDigest ? String(repeating: "0", count: 64)
          : plan.provenance.registrationContentHash.description,
        applicability: f.registration.applicability, estimatorRevision: f.registration.estimatorRevision),
      paper: paper, observation: .observed(observation),
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: 21))
  }
}

enum RetrospectiveMismatch: String, CaseIterable, Sendable {
  case cameraSource, imageGeometry, pixelFormat, registrationDigest, contactPlane
  case programID, programHash, placementHash, planProvenance, frontiers, intendedGeometry

  var reason: String {
    switch self {
    case .cameraSource, .imageGeometry, .pixelFormat: "camera source or image geometry"
    case .registrationDigest, .contactPlane: "current accepted calibration"
    case .programID, .programHash, .placementHash, .planProvenance: "differs from its immutable plan"
    case .frontiers: "completed attributable paths"
    case .intendedGeometry: "intended path differs"
    }
  }
}
