import AppKit
import Foundation
import SwiftUI
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Coverage selection and fitting integration", .serialized)
@MainActor
struct DrawingCoverageExperimentTests {
  @Test("sealed nonoverlapping coverage is deterministic and survives archive provenance round-trip")
  func sealedDesign() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let e = try experiment(f)
    #expect(e.trials.count == 48)
    #expect(e.trials.filter { $0.role == .training }.count == 32)
    #expect(e.trials.filter { $0.role == .reservedHoldout }.count == 16)
    var hashes: Set<Digest> = []
    for trial in e.trials {
      let p = try e.program(for: trial)
      #expect(hashes.insert(p.contentHash).inserted)
      #expect(try e.program(for: trial) == p)
      let descriptor = try #require(DrawingCoverageTrialDescriptor.decode(p.source))
      #expect(descriptor.experiment == e)
      #expect(descriptor.trialIndex == trial.index)
      let plan = try #require(PlotterDrawingPlanningAdapter.buildDraft(program: p,
        machineCenter: e.center, uniformScale: 1, rotationDegrees: 0,
        drawableRegion: f.drawableRegion, registration: f.registration).plan)
      #expect(plan.strokes.allSatisfy { f.drawableRegion.contains($0.path) })
      #expect(try TipApplicabilityEvidencePolicy.project(paths: plan.strokes.map(\.path),
        using: f.registration).attributableCameraPolylines != nil)
      for other in e.trials where other.index != trial.index {
        #expect(trial.fieldCenter.distance(to: other.fieldCenter) >= min(trial.lengthMM, other.lengthMM) + 5 - 1e-9)
      }
    }
  }

  @Test("fractional minimum-area bounds tolerate arithmetic residue, not an undersized region", arguments: [0.1, 0.2, 0.3, 0.7])
  func minimumAreaTolerance(_ fraction: Double) async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let b = f.registration.applicabilityRectangle
    let x = b.minX + fraction, y = b.minY + fraction
    let region = try DrawableMachineRegion(bounds: AxisAlignedBounds<MachineSpace>(
      minX: x, minY: y, maxX: (x + 76).nextDown, maxY: (y + 58).nextDown))
    let e = try DrawingCoverageExperiment(region: region, registration: f.registration,
      prior: f.plan.plan.provenance, paper: f.paper, style: f.plan.program.strokes[0].style)
    #expect(abs(e.extent.width - 72) < 1e-9)
    #expect(abs(e.extent.height - 54) < 1e-9)
    let undersized = try DrawableMachineRegion(bounds: AxisAlignedBounds<MachineSpace>(
      minX: x, minY: y, maxX: x + 75.99, maxY: y + 58))
    #expect(throws: (any Error).self) {
      try DrawingCoverageExperiment(region: undersized, registration: f.registration,
        prior: f.plan.plan.provenance, paper: f.paper, style: f.plan.program.strokes[0].style)
    }
  }

  @Test("all 48 canonical drafts select once, fit training only, compare holdouts, and resume from archive")
  func completeExperiment() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    var records: [DrawingRunEvidenceRecord] = []
    var snapshot = await runtime.synchronize(facts(f, records: records))
    snapshot = try await submit(.open, runtime, snapshot, facts(f, records: records))
    snapshot = try await submit(.prepareCoverageExperiment, runtime, snapshot, facts(f, records: records))
    let e = try #require(snapshot.coverageExperiment)
    var selected: Set<Int> = []
    var sealedCandidate: CrossTrackResidualCandidate?
    for index in 0..<48 {
      let descriptor = try #require(DrawingCoverageTrialDescriptor.decode(snapshot.program?.source))
      let trial = e.trials[descriptor.trialIndex]
      #expect(selected.insert(trial.index).inserted)
      #expect(snapshot.evidenceRole == (index < 32 ? .training : .reservedHoldout))
      #expect(snapshot.plan?.placement == e.placement)
      records.append(try record(f, e, trial))
      snapshot = await runtime.synchronize(facts(f, records: records))
      #expect(snapshot.plan == nil) // recorded geometry cannot run again
      if index < 31 { #expect(snapshot.coverageAssessment?.candidate == nil) }
      if index == 31 { sealedCandidate = try #require(snapshot.coverageAssessment?.candidate) }
      if index >= 31 { #expect(snapshot.coverageAssessment?.candidate == sealedCandidate) }
      if index < 47 {
        snapshot = try await submit(.nextCoverageTrial, runtime, snapshot, facts(f, records: records))
      }
    }
    let result = try #require(snapshot.coverageAssessment)
    #expect(result.trainingCount == 32 && result.holdoutCount == 16)
    #expect(result.blocker == nil)
    #expect(result.nextTrial == nil)
    #expect(result.comparison?.passed == true)
    var archive = DrawingRunEvidenceArchive()
    for record in records { archive = try archive.appending(record) }
    let restored = try JSONDecoder().decode(DrawingRunEvidenceArchive.self, from: JSONEncoder().encode(archive))
    let reopened = PlotterDrawingDraftRuntime()
    let restoredFacts = facts(f, records: restored.records)
    var restoredSnapshot = await reopened.synchronize(restoredFacts)
    restoredSnapshot = try await submit(.open, reopened, restoredSnapshot, restoredFacts)
    restoredSnapshot = try await submit(.prepareCoverageExperiment, reopened, restoredSnapshot, restoredFacts)
    #expect(restoredSnapshot.coverageExperiment == e)
    #expect(restoredSnapshot.coverageAssessment == result)
    #expect(restoredSnapshot.plan == nil)
  }

  @Test("role leakage, duplicate attempts, changed geometry and non-attributable trials stop selection")
  func rejectsInvalidEvidence() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let e = try experiment(f)
    let training = e.trials.first { $0.role == .training }!
    let holdout = e.trials.first { $0.role == .reservedHoldout }!
    let good = try record(f, e, training)
    let variants: [[DrawingRunEvidenceRecord]] = [
      [try record(f, e, holdout)],
      [good, good],
      [try record(f, e, training, role: .ordinaryDrawing)],
      [try record(f, e, training, scale: 0.95)],
      [try record(f, e, training, failed: true)],
      [try record(f, e, training, shortObservedLine: true)],
      [try record(f, experiment(f), training)],
      [good, try record(f, e, e.trials[1], frameIdentityIndex: training.index)],
    ]
    for records in variants {
      let result = DrawingCoverageAssessment.evaluate(experiment: e, records: records, registration: f.registration)
      #expect(result.blocker != nil)
      #expect(result.nextTrial == nil)
      #expect(result.candidate == nil)
    }
  }

  @Test("resuming a failed experiment cannot leave a runnable default drawing behind")
  func failedResumeHasNoPlan() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let e = try experiment(f)
    let failed = try record(f, e, e.trials[0], failed: true)
    let current = facts(f, records: [failed])
    let runtime = PlotterDrawingDraftRuntime()
    var snapshot = await runtime.synchronize(current)
    snapshot = try await submit(.open, runtime, snapshot, current)
    let result = await runtime.submit(.init(projection: snapshot.projection, intent: .prepareCoverageExperiment), facts: current)
    guard case .refused = result.disposition else { Issue.record("Failed experiment resumed"); return }
    let synchronized = await runtime.synchronize(current)
    #expect(synchronized.coverageAssessment?.blocker != nil)
    #expect(synchronized.plan == nil)
  }

  @Test("archive loading must finish before an experiment can reserve a sheet")
  func archiveMustBeKnown() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let unavailable = facts(f, records: [], archiveAvailable: false)
    var snapshot = await runtime.synchronize(unavailable)
    snapshot = try await submit(.open, runtime, snapshot, unavailable)
    let result = await runtime.submit(.init(projection: snapshot.projection, intent: .prepareCoverageExperiment),
                                     facts: unavailable)
    if case .refused(let refusal) = result.disposition {
      #expect(refusal.reason == .coverageExperimentUnavailable)
    } else { Issue.record("An unknown archive allowed coverage reservation") }
    #expect(result.snapshot.coverageExperiment == nil)
    let available = facts(f, records: [])
    snapshot = await runtime.synchronize(available)
    snapshot = try await submit(.prepareCoverageExperiment, runtime, snapshot, available)
    let planID = try #require(snapshot.plan?.revisionID)
    snapshot = await runtime.synchronize(unavailable)
    let interrupted = await runtime.submit(
      .init(projection: snapshot.projection, intent: .prepareCoverageExperiment), facts: unavailable)
    #expect(interrupted.snapshot.plan == nil)
    let recovered = await runtime.synchronize(available)
    #expect(recovered.plan?.revisionID == planID)

  }

  @Test("an observed line exactly spanning the central 60 percent remains measurable")
  func exactMeasurementBoundary() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let e = try experiment(f)
    let trial = e.trials[0]
    let result = DrawingCoverageAssessment.evaluate(experiment: e,
      records: [try record(f, e, trial, observedRange: 0.2...0.8)], registration: f.registration)
    #expect(result.blocker == nil)
    #expect(result.trainingCount == 1)
  }

  @Test("sealed experiment blocks editor mutations, stale evidence and changed paper")
  func locksAndInvalidates() async throws {
    let f = try await DrawingRunEpisodeFixtureCache.load()
    let runtime = PlotterDrawingDraftRuntime()
    let initialFacts = facts(f, records: [])
    var snapshot = await runtime.synchronize(initialFacts)
    snapshot = try await submit(.open, runtime, snapshot, initialFacts)
    snapshot = try await submit(.prepareCoverageExperiment, runtime, snapshot, initialFacts)
    let program = snapshot.program
    for intent in [PlotterDrawingDraftIntent.setEvidenceRole(.reservedHoldout), .setUniformScale(0.2),
                   .setRotationDegrees(90), .selectCatalogItem(.circle)] {
      let result = await runtime.submit(.init(projection: snapshot.projection, intent: intent), facts: initialFacts)
      guard case .refused(let refusal) = result.disposition else { Issue.record("Sealed edit accepted"); continue }
      #expect(refusal.reason == .coverageExperimentUnavailable)
      #expect(result.snapshot.program == program)
      snapshot = result.snapshot
    }
    let e = try #require(snapshot.coverageExperiment)
    let trial = e.trials[try #require(DrawingCoverageTrialDescriptor.decode(program?.source)).trialIndex]
    let updatedFacts = facts(f, records: [try record(f, e, trial)])
    let stale = await runtime.submit(.init(projection: snapshot.projection, intent: .nextCoverageTrial), facts: updatedFacts)
    if case .refused(let refusal) = stale.disposition { #expect(refusal.reason == .staleProjection) }
    else { Issue.record("Stale archive projection accepted") }
    let changedPaper = PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: f.paper.contactPlane)
    let invalidated = await runtime.synchronize(facts(f, records: [], paper: changedPaper))
    #expect(invalidated.plan == nil)
    #expect(invalidated.coverageUnavailableReason != nil)
  }

  @Test("production UI exposes active learning without starting motion or falsely claiming readiness")
  func productionUI() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let app = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(app)
    try await installAcceptedBoundaryTestProjection(runtime: harness.boundaryRuntime, workspace: app, environment: .simulated)
    try await completeSimulatedTipCalibration(app, simulator: harness.simulator)
    _ = await app.currentDrawingRunFacts(for: .simulated)
    let item = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    func request(_ intent: PlotterDrawingDraftIntent) throws -> PlotterUIRequest {
      try #require(app.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
        .semantic.request(matching: .drawingDraft(intent)))
    }
    let open = try request(.open)
    #expect(await app.submitPlotterUIRequest(open) == .accepted(requestID: open.id))
    let before = await harness.simulator.persistentInk()
    let prepare = try request(.prepareCoverageExperiment)
    #expect(await app.submitPlotterUIRequest(prepare) == .accepted(requestID: prepare.id))
    #expect(app.drawingStudioPresentation.coverageExperiment != nil)
    #expect(app.drawingDraftSnapshot.preview?.status == .ready)
    #expect(app.drawingStudioPresentation.coverageAssessment?.trainingCount == 0)
    #expect(!app.drawingStudioPresentation.authoringIsEnabled)
    if let path = ProcessInfo.processInfo.environment["ACTIVE_LEARNING_SNAPSHOT"] {
      let projection = app.testPlotterUIProjection(selectedItemID: item, includesLearningPath: true)
      let view = DrawingStudioView(presentation: projection.drawingStudio,
        plotterUIProjection: projection.semantic, plotterUIIntentSink: app)
      _ = NSApplication.shared
      let host = NSHostingView(rootView: view.frame(width: 390)
        .environment(\.colorScheme, .light).background(Color(nsColor: .windowBackgroundColor)))
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 1000),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.appearance = NSAppearance(named: .aqua)
      window.contentView = host
      host.frame = NSRect(x: 0, y: 0, width: 390, height: 1000)
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(for: .milliseconds(100))
      host.layoutSubtreeIfNeeded()
      window.display()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let image = try #require(bitmap.cgImage)
      try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: path))
      window.close()
    }
    #expect(await harness.simulator.persistentInk() == before)
    let leave = try request(.leaveCoverageExperiment)
    #expect(await app.submitPlotterUIRequest(leave) == .accepted(requestID: leave.id))
    #expect(app.drawingStudioPresentation.authoringIsEnabled)
    await app.shutdown()
  }

  private func experiment(_ f: DrawingRunEpisodeFixture) throws -> DrawingCoverageExperiment {
    try DrawingCoverageExperiment(region: f.drawableRegion, registration: f.registration,
      prior: f.plan.plan.provenance, paper: f.paper, style: f.plan.program.strokes[0].style)
  }

  private func facts(_ f: DrawingRunEpisodeFixture, records: [DrawingRunEvidenceRecord],
                     paper: PaperRevisionContext? = nil, archiveAvailable: Bool = true) -> PlotterDrawingDraftExternalFacts {
    PlotterDrawingDraftExternalFacts(environment: .simulated, interactiveLearningIsComplete: true,
      displayedFrame: nil, opticalConfiguration: f.registration.applicability.opticalConfiguration,
      registration: f.registration, drawableRegion: f.drawableRegion,
      toolAssemblyRevision: f.registration.applicability.toolAssembly, paper: paper ?? f.paper,
      runInProgress: false, terminalRequiresNewPlan: false, coverageRecords: records,
      drawingArchiveIsAvailable: archiveAvailable)
  }

  private func submit(_ intent: PlotterDrawingDraftIntent, _ runtime: PlotterDrawingDraftRuntime,
                      _ snapshot: PlotterDrawingDraftSnapshot, _ facts: PlotterDrawingDraftExternalFacts)
    async throws -> PlotterDrawingDraftSnapshot {
    let result = await runtime.submit(.init(projection: snapshot.projection, intent: intent), facts: facts)
    guard case .applied = result.disposition else {
      Issue.record("Unexpected refusal: \(result.disposition)")
      throw PlotterModelError.invalidValue("coverage draft refused")
    }
    return result.snapshot
  }

  private func record(_ f: DrawingRunEpisodeFixture, _ e: DrawingCoverageExperiment,
                      _ trial: DrawingCoverageTrial, role: BorderValidationEvidenceRole? = nil,
                      scale: Double = 1, failed: Bool = false, shortObservedLine: Bool = false,
                      observedRange: ClosedRange<Double> = 0.1...0.9, frameIdentityIndex: Int? = nil) throws -> DrawingRunEvidenceRecord {
    let program = try e.program(for: trial)
    let plan = try #require(PlotterDrawingPlanningAdapter.buildDraft(program: program,
      machineCenter: e.center, uniformScale: scale, rotationDegrees: 0,
      drawableRegion: f.drawableRegion, registration: f.registration).plan)
    let path = plan.strokes[0].path
    let intended = try f.registration.cameraFromMachine.applying(to: path)
    let error = 0.35 + trial.normalizedX * 0.08 - trial.normalizedY * 0.05 + trial.direction.sign * 0.07
    let observed = try Polyline<CameraPixelSpace>(points: (0..<9).map { i in
      let fraction = shortObservedLine ? 0.4 + Double(i) / 40
        : observedRange.lowerBound + Double(i) / 8 * (observedRange.upperBound - observedRange.lowerBound)
      let p = path.points[0], q = path.points[1]
      let machine = try Point2<MachineSpace>(
        x: p.x + (q.x - p.x) * fraction + (trial.direction.horizontal ? 0 : error),
        y: p.y + (q.y - p.y) * fraction + (trial.direction.horizontal ? error : 0))
      return try f.registration.cameraFromMachine.applying(to: machine)
    })
    let config = CameraConfigurationID()
    let source = f.registration.applicability.opticalConfiguration.source
    let optical = f.registration.applicability.opticalConfiguration
    func frame(_ suffix: String, sequence: UInt64) throws -> StampedFrame {
      try StampedFrame(id: FrameID(rawValue: "coverage-\(frameIdentityIndex ?? trial.index)-\(suffix)"),
        sequence: sequence, captureNanoseconds: sequence, cameraConfigurationID: config,
        width: optical.width, height: optical.height,
        rowBytes: optical.width * optical.pixelFormat.bytesPerPixel, pixelFormat: optical.pixelFormat,
        bytes: OwnedFrameBytes(Array(repeating: 0,
          count: optical.width * optical.height * optical.pixelFormat.bytesPerPixel)))
    }
    let baseline = try frame("before", sequence: UInt64(trial.index * 2 + 1))
    let post = try frame("after", sequence: UInt64(trial.index * 2 + 2))
    let frames = try DrawingObservationFramePair(source: source,
      baseline: ExactFrameProvenance(frame: baseline), post: ExactFrameProvenance(frame: post))
    let observation: DrawingRunObservationOutcome = failed ? .notAttempted(.executionFailedBeforeObservation)
      : .observed(try DrawingObservedInkEvidence(frames: frames, intendedInk: [intended], observedInk: [observed],
        residual: DrawingResidualEvidence(correspondenceCount: 9, rootMeanSquarePixels: 0.5,
          maximumPixels: 1, rootMeanSquareCrossTrackPixels: 0.5),
        algorithmRevisions: [AlgorithmRevisionEvidence(component: "synthetic-coverage-test", revision: "1")]))
    return try DrawingRunEvidenceRecord(runID: RunID(), requestID: UUID(), role: role ?? trial.role,
      evidenceDisposition: failed ? .possibleInk : .attributable, requestFrontier: .admitted,
      executionFrontiers: DrawingRunExecutionFrontiers(plannedStrokeCount: 1, commandedStrokeCount: 1,
        controllerCompletedStrokeCount: failed ? 0 : 1, inkVerifiedStrokeCount: failed ? 0 : 1),
      executionDisposition: failed ? .ambiguous(reason: "Synthetic Stop with possible ink") : .completed,
      program: DrawingProgramEvidenceReference(program: program),
      placement: DrawingPlacementEvidenceReference(placementID: UUID(), placement: plan.placement),
      plan: DrawingExecutionPlanEvidenceReference(plan: plan), planningProvenance: e.prior,
      tipCalibration: e.tip, paper: e.paper, observation: observation,
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: UInt64(trial.index + 1)))
  }
}
