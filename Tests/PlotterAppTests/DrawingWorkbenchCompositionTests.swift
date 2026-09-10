import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Drawing workbench production composition", .serialized)
@MainActor
struct DrawingWorkbenchCompositionTests {
  @Test("Show, fit, adjust and Draw use current readiness; persisted ordinary drawing and retrospective UI settle")
  func portraitRunAndRetrospectivePublication() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .contours, strokeStyle: app.drawingStrokeStyle)
    let selectProjection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
    let show = try #require(selectProjection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
    let showOutcome = await app.submitPlotterUIRequest(show)
    if case .refused(let refusal) = showOutcome {
      Issue.record("Show on Plotter refused: \(refusal); draft refusal: \(String(describing: app.drawingDraftSnapshot.lastSubmissionRefusal))")
      await app.shutdown()
      return
    }
    #expect(showOutcome == .accepted(requestID: show.id))
    try await f.submit(.fitInDrawableRegion)
    #expect(app.drawingTargetIsVisible)
    let target = try #require(app.testPlotterUIProjection().actionSurface.drawingStudioCanvas?.targetPreview)
    #expect(!target.strokes.isEmpty)
    let fitScale = app.drawingDraftSnapshot.uniformScale
    try await f.submit(.setUniformScale(floor(fitScale * 80) / 100))
    try await f.submit(.setRotationDegrees(0))
    try await f.submit(.centerInDrawableRegion)
    // Start the analysis phase, then deliver another exact analysis frame
    // without a semantic transition to refresh the cached Draft for us.
    f.camera.analysis.inject(revision: 1_000)
    try await waitUntil { app.visionAnalysisSnapshot.revision == 1_000 }
    await app.drawingDraftSynchronizationTask?.value
    let paperFrame = try await f.camera.publishNextFrame()
    f.camera.analysis.inject(revision: 1_001, result: PlotterSceneAnalysisResult(
      displayedFrame: paperFrame,
      measurement: PlotterSceneMeasurement(
        frameID: paperFrame.frame.id, frameSHA256: paperFrame.frame.contentSHA256,
        cameraConfigurationID: paperFrame.frame.cameraConfigurationID,
        penCap: .notRequested, armatureEnvelope: .notRequested, overlays: [],
        algorithmRevision: "paper-assertion-test", diagnosticSHA256: paperFrame.frame.contentSHA256,
        computation: SceneVisionComputationDiagnostics(requestedFeatures: [], expandedFeatures: [],
          executionCounts: [:], inspectedPixelCounts: [:])),
      analysisDurationNanoseconds: 1, completedNanoseconds: f.clock.read()))
    try await waitUntil { app.visionAnalysisSnapshot.revision == 1_001 }
    #expect(app.drawingDraftExternalFacts.revisions.displayedFrame
      != app.drawingDraftSnapshot.projection.externalFacts.displayedFrame)
    let blocked = app.testPlotterUIProjection()
    let blockedDiagnostics = WorkbenchDebugSnapshot(application: app, projection: blocked.semantic)
    #expect(blockedDiagnostics.diagnostics.contains {
      $0.contains("Drawing run:") && $0.contains("Confirm that the current sheet covers the drawing area.")
    })
    try await f.submit(.assertPaperCoverage)
    #expect(app.drawingDraftSnapshot.paperCoverageObservation?.frame.frameID == paperFrame.frame.id)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let retainedPlan = try #require(app.drawingDraftSnapshot.plan)
    let ready = app.testPlotterUIProjection()
    #expect(ready.drawingStudio.runState.isReadyForCompositionTest)
    let readyRevision = app.drawingRunSnapshot?.projection.runRevision
    let readyDraw = try #require(ready.semantic.request(matching: .drawingRun(.start)))
    // The lower controller changes after Ready was rendered. Draw itself must
    // refresh readiness and publish the refusal through the existing revision;
    // no pre-synchronize or unrelated UI change is allowed to repair this cache.
    await f.machine.deactivateMotionGuard()
    let refusedDraw = await app.submitPlotterUIRequest(readyDraw)
    guard case .refused(let userRefusal) = refusedDraw else {
      await f.planGate.release(.cancelled)
      await app.shutdown()
      Issue.record("Draw did not reject changed lower readiness: \(refusedDraw)")
      return
    }
    let failed = app.testPlotterUIProjection()
    let issue: PlotterDrawingRunReadinessIssue
    if case .unavailable(let value) = app.drawingRunSnapshot?.readiness { issue = value }
    else { throw DrawingWorkbenchFixtureError.missingReadinessIssue }
    #expect(failed.drawingStudio.runState == .unavailable(reason: issue.detail))
    #expect(!failed.drawingStudio.runState.isReadyForCompositionTest)
    #expect(app.drawingRunSnapshot?.projection.runRevision != readyRevision)
    #expect(app.drawingRunSnapshot?.lastRefusal?.reason == issue.reason)
    #expect(app.drawingRunSnapshot?.lastRefusal?.remedy == issue.remedy)
    #expect(userRefusal.remedy.contains(issue.detail))
    #expect(await f.planGate.request == nil)
    #expect(app.drawingDraftSnapshot.plan?.revisionID == retainedPlan.revisionID)
    _ = await f.machine.activateMotionGuard()
    _ = await f.runRuntime.synchronize(environment: .live)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    #expect(app.testPlotterUIProjection().drawingStudio.runState.isReadyForCompositionTest)
    let drawing = try #require(app.testPlotterUIProjection().semantic.actions.first {
      if case .drawingRun(.start) = $0.intent { return true }; return false
    })
    let drawRequest = try #require(app.testPlotterUIProjection().semantic.request(for: drawing.id))
    let run = Task { await app.submitPlotterUIRequest(drawRequest) }
    do { try await waitUntilAsync { await f.planGate.request != nil } }
    catch {
      await f.planGate.release(.cancelled)
      await app.shutdown()
      _ = await run.value
      throw error
    }
    let admitted = try #require(await f.planGate.request)
    #expect(admitted.plan.revisionID == retainedPlan.revisionID)
    #expect(await f.machine.requestedPenCommands.first == .raise)
    var layout = WorkbenchLayoutState()
    layout.setPresented(.motion, false)
    layout.setPresented(.portraitStudio, false)
    let stops = WorkbenchStopPresentation.actions(in: app.testPlotterUIProjection().semantic)
    #expect(stops.count == 1)
    if case .drawingRun(.stop(let capability)) = stops.first?.intent {
      #expect(capability == app.drawingRunSnapshot?.stopCapabilityID)
    } else { Issue.record("Actual held drawing lost its Stop capability with panels hidden") }
    await f.planGate.release(.completed)
    #expect(await run.value == .accepted(requestID: drawRequest.id))
    let terminal = try #require(app.drawingRunSnapshot?.terminal)
    #expect(terminal.disposition == .succeeded)
    try await waitUntil { app.drawingDraftSnapshot.residualRecords.contains { $0.recordID == terminal.record.recordID } }
    let originalPlanRevision = app.drawingDraftSnapshot.projection.draftRevision
    let originalPlanHash = app.drawingDraftSnapshot.plan?.contentHash
    _ = app.testPlotterUIProjection() // warm the prior unchecked archive row
    try await f.submit(.selectResidualRecord(terminal.record.recordID, selected: true))
    let selected = app.testPlotterUIProjection()
    #expect(selected.drawingStudio.residualRecords.first { $0.recordID == terminal.record.recordID }?.isSelected == true)
    #expect(selected.semantic.request(matching: .drawingDraft(.analyzeSelectedResiduals)) != nil)
    try await f.submit(.analyzeSelectedResiduals)
    let analysis = try #require(app.testPlotterUIProjection().drawingStudio.residualAnalysis)
    #expect(analysis.candidate != nil)
    #expect(analysis.constraints.allSatisfy { $0.recordID == terminal.record.recordID })
    #expect(app.drawingDraftSnapshot.projection.draftRevision == originalPlanRevision)
    #expect(app.drawingDraftSnapshot.plan?.contentHash == originalPlanHash)
    guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
      Issue.record("Ordinary drawing was not persisted to the configured archive")
      await app.shutdown(); return
    }
    #expect(archive.records.last == terminal.record)
    #expect(archive.records.last?.role == .ordinaryDrawing)
    // The archive row proves the reload installed its archive and scheduled
    // the Draft consumer. Join that consumer's retained chain, including its
    // later Run -> Draft publication, before measuring subsequent video.
    let synchronization = try #require(app.drawingDraftSynchronizationTask)
    await synchronization.value
    try await waitForExecutorTurns(conditionDescription: "drawing camera preview subscription") {
      f.camera.previewFrames.subscriptionCount > 0
    }
    let baselineTime = f.clock.read()
    let baselineProjection = app.testPlotterUIProjection()
    #expect(baselineProjection.observationConfiguration.cameraIsLive)
    #expect(f.clock.read() == baselineTime)
    let loads = await f.stores.evidencePort.loadCount
    let diagnostics = app.computationDiagnosticsForTesting
    let revision = app.drawingRunSnapshot?.projection.runRevision
    let previewPublications = app.previewIsolationDiagnostics.previewPublicationCount
    var receipts = [drawingCompositionReceipt(app, projection: baselineProjection, label: "baseline")]
    var lastSemanticRevision = diagnostics.semanticPresentationRevision
    for _ in 0..<30 {
      let frame = try await f.camera.publishNextFrame()
      let capturedAt = f.clock.read()
      #expect(frame.frame.captureNanoseconds == capturedAt)
      try await waitForExecutorTurns(conditionDescription: "post-drawing frame \(frame.frame.sequence)") {
        app.actionSurfacePreview.displayedFrame?.frame.id == frame.frame.id
      }
      let projection = app.testPlotterUIProjection()
      #expect(projection.observationConfiguration.cameraIsLive)
      #expect(f.clock.read() == capturedAt)
      let semanticRevision = app.computationDiagnosticsForTesting.semanticPresentationRevision
      if semanticRevision != lastSemanticRevision, receipts.count < 8 {
        receipts.append(drawingCompositionReceipt(app, projection: projection,
          label: "acknowledged frame \(frame.frame.sequence), semantic \(lastSemanticRevision) -> \(semanticRevision)"))
      }
      lastSemanticRevision = semanticRevision
    }
    if app.computationDiagnosticsForTesting.semanticPresentationRevision != diagnostics.semanticPresentationRevision {
      FileHandle.standardError.write(Data(("Drawing composition semantic transitions:\n"
        + receipts.joined(separator: "\n") + "\n").utf8))
    }
    #expect(app.previewIsolationDiagnostics.previewPublicationCount == previewPublications + 30)
    #expect(await f.stores.evidencePort.loadCount == loads)
    #expect(app.computationDiagnosticsForTesting.drawingDraftSynchronizationCount == diagnostics.drawingDraftSynchronizationCount)
    #expect(app.computationDiagnosticsForTesting.plotterUIProjectionBuildCount == diagnostics.plotterUIProjectionBuildCount)
    #expect(app.computationDiagnosticsForTesting.semanticPresentationRevision == diagnostics.semanticPresentationRevision)
    #expect(app.drawingRunSnapshot?.projection.runRevision == revision)
    #expect(app.drawingDraftSnapshot.plan?.contentHash == originalPlanHash)
    #expect(app.testPlotterUIProjection().drawingStudio.residualAnalysis == analysis)
    await app.shutdown()
  }

  @Test("quiescence baseline joins the retained nested publication while paper persistence is held")
  func quiescenceBaselineWaitsForNestedPublication() async throws {
    let loadGate = DrawingRunHoldGate()
    let clearGate = DrawingRunHoldGate()
    let paper = ComputationPaperPersistenceProbe(loadGate: loadGate, clearGate: clearGate)
    let draft = nominalDrawingDraftRuntime(paperPersistence: paper)
    let app = drawingDraftSynchronizationTestWorkspace(draft: draft)
    if app.drawingDraftSynchronizationTask == nil { app.markSemanticPresentationChangedForTesting() }
    await loadGate.waitUntilHeld()
    let synchronization = try #require(app.drawingDraftSynchronizationTask)
    let scheduled = app.computationDiagnosticsForTesting.drawingDraftSynchronizationCount
    let facts = app.drawingDraftExternalFacts
    let clearing = Task { await draft.clearPaperCoverageForRetainedPaperLifecycle(facts: facts) }
    var baselineAwaitEntered = false
    var baselineBegan = false
    var baselineTask: Task<Void, Never>?
    do {
      try await waitForExecutorTurnsAsync(conditionDescription: "paper clear queued behind initial load") {
        await draft.pendingMutationCount == 1
      }
      await loadGate.release()
      await clearGate.waitUntilHeld()
      // Only this one synchronization exists. Its first Draft publication is
      // visible, but Run's nested Draft read is now queued behind actual clear.
      try await waitForExecutorTurnsAsync(conditionDescription: "retained Run-to-Draft publication tail") {
        await draft.pendingMutationCount == 1
      }
      #expect(app.computationDiagnosticsForTesting.drawingDraftSynchronizationCount == scheduled)
      #expect(app.drawingDraftSnapshot.program != nil)
      #expect(app.drawingDraftSnapshot.projection.externalFacts == app.drawingDraftExternalFacts.revisions)
      let firstPublication = app.drawingDraftSnapshot.projection
      baselineTask = Task {
        baselineAwaitEntered = true
        // The current-facts predicate above is already true. Without this
        // exact join, baselineBegan becomes true while the real tail is held.
        await synchronization.value
        baselineBegan = true
        _ = app.testPlotterUIProjection()
      }
      try await waitForExecutorTurns(conditionDescription: "baseline awaiting retained synchronization") {
        baselineAwaitEntered
      }
      #expect(!baselineBegan)
      #expect(await draft.pendingMutationCount == 1)
      #expect(app.drawingDraftSnapshot.projection == firstPublication)

      await clearGate.release()
      let cleared = await clearing.value
      #expect(cleared.disposition == .applied)
      await baselineTask?.value
      #expect(baselineBegan)
      #expect(await draft.pendingMutationCount == 0)
      #expect(app.drawingDraftSnapshot.projection.draftRevision == cleared.snapshot.projection.draftRevision)
      let run = try #require(app.drawingRunSnapshot)
      #expect(run.readiness != .synchronizing)
      await app.shutdown()
    } catch {
      await loadGate.release()
      await clearGate.release()
      _ = await clearing.value
      await baselineTask?.value
      await app.shutdown()
      throw error
    }
  }
}

private extension DrawingStudioRunState {
  var isReadyForCompositionTest: Bool { if case .ready = self { true } else { false } }
}
private enum DrawingWorkbenchFixtureError: Error { case missingReadinessIssue }

@MainActor
private func drawingCompositionReceipt(_ app: PlotterApplicationRuntime,
  projection: PlotterAppUIProjection, label: String) -> String {
  func frameMetadata(_ frame: DisplayedFrame?) -> String {
    guard let frame else { return "nil" }
    return "\(frame.source):\(frame.frame.id)/seq=\(frame.frame.sequence)/capture=\(frame.frame.captureNanoseconds)"
      + "/config=\(frame.frame.cameraConfigurationID)/\(frame.frame.width)x\(frame.frame.height)/\(frame.frame.pixelFormat)"
  }
  let diagnostics = app.computationDiagnosticsForTesting
  let draft = app.drawingDraftSnapshot
  let run = app.drawingRunSnapshot
  // This is outside Observation tracking and uses the camera-live value from
  // the projection already requested by the test, without another clock read.
  return "\(label): semantic=\(diagnostics.semanticPresentationRevision), scheduled=\(diagnostics.drawingDraftSynchronizationCount), "
    + "UI=\(diagnostics.plotterUIProjectionBuildCount), learningWrites=\(diagnostics.learningSessionWriteCount); "
    + "cameraLive=\(projection.observationConfiguration.cameraIsLive), mode=\(app.frameMode), role=\(app.workbenchCameraRole), "
    + "available=\(app.displayedFrameAvailable), cameraState=\(String(describing: app.cameraSnapshot?.state)), "
    + "cameraError=\(String(describing: app.cameraError)), vision=\(app.visionAnalysisSnapshot.phase), "
    + "visionError=\(String(describing: app.visionError)), exactOwner=\(String(describing: app.exactWorkflowVisionOwner)); "
    + "preview=\(frameMetadata(app.actionSurfacePreview.displayedFrame)); latestLive=\(frameMetadata(app.latestLiveCameraFrame)); "
    + "displayed=\(frameMetadata(app.displayedFrame)); "
    + "draft=\(draft.projection.draftRevision)/\(String(describing: draft.projection.externalFacts.displayedFrame)), "
    + "target=\(draft.isTargetVisible), rows=\(draft.residualRecords), analysis=\(String(describing: draft.residualAnalysis?.summary)); "
    + "run=\(String(describing: run?.projection.runRevision))/\(String(describing: run?.phase))/\(String(describing: run?.readiness)); "
    + "applied=\(String(describing: app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID)), "
    + "comparison=\(String(describing: app.artifactResetEpisodeSnapshot.savedLearning.candidate?.opticalComparison))"
}

@MainActor
struct DrawingWorkbenchApplicationFixture {
  let application: PlotterApplicationRuntime
  let machine: LowerMachineSessionFixture
  let stores: CompleteAcceptedLearningStores
  let accepted: CompleteAcceptedLearningFixture
  let camera: AcceptedDrawingCameraSession
  let clock: ComputationTestClock
  let planGate: DrawingRunPlanGate
  let runRuntime: PlotterDrawingRunRuntime

  static func make(releasePlanOnStop: Bool = true) async throws -> Self {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    try await stores.save(accepted)
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log,
      relativeJogSettlementOffset: Vector2(dx: 0, dy: 0))
    await machine.setPenState(.unknown)
    let clock = ComputationTestClock()
    clock.set(max(clock.read(), accepted.frame.frame.captureNanoseconds))
    let camera = try AcceptedDrawingCameraSession(frame: accepted.frame, clock: clock)
    let planGate = DrawingRunPlanGate()
    var runRuntime: PlotterDrawingRunRuntime?
    let app = plotterApplicationRuntime(machine: machine, observationSessionOverride: camera,
      drawingPlanBegin: { request in
        .admitted(DrawingPlanOperation(id: request.operationID, planRevisionID: request.plan.revisionID,
          task: Task { drawingRunOutcome(await planGate.wait(request), request: request) }))
      }, drawingRunRuntimeAccess: { runRuntime = $0 },
      jogCancel: { _ in
        if releasePlanOnStop { await planGate.release(.cancelled) }
        return .transmitted
      },
      statePersistencePort: stores.persistence, drawingEvidencePort: stores.evidencePort,
      tipCalibrationSemanticIdentities: accepted.identities,
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [machine.descriptor] }, readNanoseconds: { clock.read() }),
      loadPenCapAppearanceSelection: { nil }, log: log)
    await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    await submitObservationConfigurationForTest(app, .selectSource(.live, camera.device.id))
    try await applyCompleteSavedLearning(app)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.tipCameraRegistration == accepted.registration)
    return Self(application: app, machine: machine, stores: stores, accepted: accepted, camera: camera, clock: clock,
      planGate: planGate, runRuntime: try #require(runRuntime))
  }

  func submit(_ intent: PlotterDrawingDraftIntent) async throws {
    let request = try #require(application.testPlotterUIProjection().semantic.request(matching: .drawingDraft(intent)))
    #expect(await application.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
  }
}

/// Synthetic lower camera/vision effect for application composition tests.
/// Lifecycle frame publication itself is covered by CameraSourceSession tests.
actor AcceptedDrawingCameraSession: PlotterObservationCameraSessionPort {
  nonisolated let device: CameraDevice
  nonisolated let previewFrames = TestPreviewFrameUpdateSource()
  nonisolated let analysis = TestAnalysisUpdateSource()
  private var frame: DisplayedFrame
  private let clock: ComputationTestClock
  private let fallback: any PlotterObservationCameraSessionPort
  private let vision = DrawingRunVisionProbe(events: DrawingRunEventProbe())

  init(frame: DisplayedFrame, clock: ComputationTestClock) throws {
    guard case .live(let id) = frame.source else { throw DrawingWorkbenchFixtureError.missingReadinessIssue }
    device = CameraDevice(id: id, name: "Synthetic accepted drawing camera")
    self.frame = frame
    self.clock = clock
    fallback = resolvedObservationSession(try TestObservationCameraSession())
  }

  func snapshot() -> CameraCaptureSnapshot {
    CameraCaptureSnapshot(devices: [device], selectedDeviceID: device.id,
      state: .running, latestFrame: frame, error: nil)
  }
  func discover() -> CameraCaptureSnapshot { snapshot() }
  func select(_: CameraDeviceID) -> CameraCaptureSnapshot { snapshot() }
  func start() -> CameraCaptureSnapshot { snapshot() }
  func stop() -> CameraCaptureSnapshot { snapshot() }
  func restart() -> CameraCaptureSnapshot { snapshot() }
  func frames() -> AsyncStream<DisplayedFrame> { previewFrames.updates() }
  func publishNextFrame() throws -> DisplayedFrame {
    _ = try captureFrame(newerThanNanoseconds: frame.frame.captureNanoseconds)
    previewFrames.inject(frame)
    return frame
  }
  func captureFrame(newerThanNanoseconds boundary: UInt64) throws -> DisplayedFrame? {
    let previous = frame.frame
    // Capture advances the fixture's one monotonic timeline. Application/UI
    // reads observe this same instant and never advance time themselves.
    let captureNanoseconds = max(max(previous.captureNanoseconds, boundary), clock.read()) + 100
    clock.set(captureNanoseconds)
    frame = DisplayedFrame(source: frame.source, frame: try StampedFrame(id: FrameID(),
      sequence: previous.sequence + 1, captureNanoseconds: captureNanoseconds,
      cameraConfigurationID: previous.cameraConfigurationID, width: previous.width, height: previous.height,
      rowBytes: previous.rowBytes, pixelFormat: previous.pixelFormat, bytes: previous.bytes))
    return frame
  }
  func inspectWorkflowScene(newerThanNanoseconds: UInt64, requestedFeatures: SceneFeatureSet,
    analysisRegion: PixelRect?) async throws -> LiveSceneInspection? { nil }
  func captureStableWorkflowCap(_ request: StableWorkflowCapCaptureRequest) async throws -> StableWorkflowCapInspection {
    try await fallback.captureStableWorkflowCap(request)
  }
  func setSceneAnalysisRegion(_: PixelRect?) {}
  func setPenCapColor(_: PenCapColor) {}
  func setAutomaticInspection(_ cadence: VisionAnalysisCadence?, requestedFeatures: SceneFeatureSet) async -> PlotterSceneAnalysisSnapshot {
    await fallback.setAutomaticInspection(cadence, requestedFeatures: requestedFeatures)
  }
  func analysisUpdates() -> AsyncStream<PlotterSceneAnalysisSnapshot> { analysis.updates() }
  func visionDiagnostics() async -> CameraSourceSessionVisionDiagnostics { await fallback.visionDiagnostics() }
  func observePlannedDrawingInk(_ request: PlannedDrawingObservationRequest) async -> PlannedDrawingObservationOutcome {
    await vision.observePlannedDrawingInk(request)
  }
}
