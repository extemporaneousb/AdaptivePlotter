import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
@testable import PlotterRuntime
import PlotterUI
import Testing
@testable import PlotterApp

@MainActor
@Suite("Pen-cap recovery production requests", .serialized)
struct PenCapRecoveryRegressionTests {
  @Test("template loss exposes numeric match and prediction diagnostics in the video status")
  func templateLossStatusRetainsDiagnostics() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession()
    let traffic = TestAnalysisUpdateSource()
    let app = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log),
      observationSessionOverride: resolvedObservationSession(camera,
        analysisUpdates: { traffic.updates() }), log: log)
    await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
    try await waitForExecutorTurns { traffic.subscriptionCount == 1 }
    let inspection = try camera.inspection(after: 100)
    let frame = inspection.displayedFrame.frame
    let diagnostics = PenCapDiagnostics(inspectedPixelCount: 576, thresholdPixelCount: 0,
      componentCount: 0, candidates: [], template: PenCapTemplateDiagnostics(candidates: [
        PenCapTemplateCandidateDiagnostic(score: 0.73, boundingBox: PixelRect(x: 1, y: 1, width: 12, height: 12),
          anchor: try Point2(x: 5, y: 7))], acceptanceThreshold: 0.82, requiredMargin: 0.06,
          competitorScore: 0.71, predictionResidualPixels: 12.5, confirmedExampleCount: 1))
    let measurement = PlotterSceneMeasurement(frameID: frame.id, frameSHA256: frame.contentSHA256,
      cameraConfigurationID: frame.cameraConfigurationID, penCap: .notFound(diagnostics),
      armatureEnvelope: .notRequested, overlays: [], algorithmRevision: "template-status-fixture",
      diagnosticSHA256: frame.contentSHA256, computation: inspection.measurement.computation)
    traffic.inject(revision: 10, result: PlotterSceneAnalysisResult(displayedFrame: inspection.displayedFrame,
      measurement: measurement, analysisDurationNanoseconds: 1_000, completedNanoseconds: 101))
    try await waitForExecutorTurns { app.visionAnalysisSnapshot.revision == 10 }
    let message = app.overlayStatus(for: .penCap).message
    #expect(message.contains("template score 0.730 (minimum 0.820)"))
    #expect(message.contains("competing-match margin 0.020 (minimum 0.060)"))
    #expect(message.contains("prediction residual 12.50 camera pixels"))
    traffic.finish()
    await app.shutdown()
  }

  @Test("fractional recovery clicks retain crop size and the independent operator anchor")
  func fractionalRecoveryDoesNotGrowReference() throws {
    var pixels = [UInt8](repeating: 255, count: 64 * 64 * 4)
    for y in 0..<64 {
      for x in 0..<64 {
        let i = (y * 64 + x) * 4
        pixels[i] = UInt8((x * 23 + y * 13) % 251)
        pixels[i + 1] = UInt8((x * 17 + y * 29) % 253)
        pixels[i + 2] = UInt8((x * 37 + y * 7) % 249)
      }
    }
    let frame = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "fractional-cap")),
      frame: try StampedFrame(sequence: 1, captureNanoseconds: 1,
        cameraConfigurationID: CameraConfigurationID(), width: 64, height: 64,
        rowBytes: 256, pixelFormat: .rgba8, bytes: OwnedFrameBytes(pixels)))
    var geometry = PlotterPenCapReferenceGeometry(width: 24, height: 28,
      anchorOffsetX: 7.2, anchorOffsetY: 19.3)
    for index in 0..<10 {
      let point = try Point2<CameraPixelSpace>(x: 24.17 + Double(index) * 0.13,
        y: 35.28 + Double(index) * 0.19)
      let region = try #require(geometry.region(around: point))
      let sample = try PlotterPenCapPointSampler.sample(frame: frame,
        submission: PlotterPointSelectionSubmission(selectionID: PlotterPointSelectionID(),
          frame: exactPointSelectionFrame(frame), point: point,
          presentationTransformRevision: PlotterPresentationTransformRevision(), referenceRegion: region))
      let reference = try #require(sample.visualReference)
      #expect(reference.region.width == 24 && reference.region.height == 28)
      #expect(reference.anchor == point)
      geometry = PlotterPenCapReferenceGeometry(width: reference.region.width,
        height: reference.region.height, anchorOffsetX: point.x - Double(reference.region.x),
        anchorOffsetY: point.y - Double(reference.region.y))
    }
  }

  @Test("LIVE Camera Redo stages new reference lineage atomically after recovery", arguments: [false, true])
  func newCameraAcceptanceSupersedesRecoveryLineage(saveFails: Bool) async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession()
    let machine = try LowerMachineSessionFixture(log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0),
      positionObserver: { camera.trackMachinePosition($0) })
    let store = CameraReplacementSaveStore()
    let boundary = TestBoundaryRuntimeAccess()
    let app = plotterApplicationRuntime(machine: machine, camera: camera,
      statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: { store.load() },
        saveCheckpoint: { try store.save($0) }, clearCheckpoint: { store.clear() }),
      boundaryRuntimeAccess: boundary, log: log)
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
    let pen = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await app.performTestExerciseAction(.start, for: pen)
    let initial = try #require(app.testActionSurfacePresentation.pointSelectionRequest)
    submitPointSelection(app, request: initial, point: try Point2(x: 11.5, y: 11.5))
    try await waitUntil { app.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await app.performTestExerciseAction(.choice(.yes), for: pen) }
    try await installAcceptedBoundaryTestProjection(runtime: #require(boundary.runtime),
      workspace: app, environment: .live, centerArrivalIsAccepted: false)
    try await machine.setPosition(x: 100, y: 50)
    await submitControllerSession(app, .requestPassiveProbe)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await app.performTestExerciseAction(.boundary(.moveToEstimatedCenter(retry: false)), for: boundaryOwner)
    try await waitForAcceptedBoundaryCenterArrival(workspace: app)
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    await app.performTestExerciseAction(.cameraCalibration(.buildFivePositionProposal), for: cameraOwner)
    await app.performTestExerciseAction(.cameraCalibration(.acceptProposal), for: cameraOwner)
    let oldMap = try #require(app.machineCameraRegistration)
    await app.performTestExerciseAction(.reidentifyPenCap, for: pen)
    let selection = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
    let point = try oldMap.fit.cameraPoint(from: #require(app.machineSnapshot?.machine.position).point)
    let clicked = PlotterPointSelectionSubmission(selectionID: selection.id, frame: selection.frame,
      point: point, presentationTransformRevision: selection.presentationTransformRevision,
      referenceRegion: try AxisAlignedBounds(minX: 0, minY: 0, maxX: 12, maxY: 12))
    let clickProjection = app.plotterUIProjection(selectedItemID: pen, manualDraft: ManualMotionDraft(),
      includesLearningPath: true, pendingPointSelection: clicked).semantic
    let clickRequest = try #require(clickProjection.request(for: PlotterAppUIActionID.pointSelection(clicked)))
    guard case .accepted = await app.submitPlotterUIRequest(clickRequest) else {
      Issue.record("Recovery did not accept: \(app.discoveryError ?? "no detail")"); await app.shutdown(); return
    }
    let recovered = try #require(app.penCapAppearanceSelection)
    try #require(recovered.operatorObservation != nil)
    let previousCheckpoint = try #require(store.checkpoint)
    let redo = try productionLearningRequest(app, .redoThisStep, owner: cameraOwner)
    #expect(await app.submitPlotterUIRequest(redo) == .accepted(requestID: redo.id))
    await app.performTestExerciseAction(.cameraCalibration(.buildFivePositionProposal), for: cameraOwner)
    let proposal = try #require(app.proposedMachineCameraRegistration)
    let expectedEstimator = "selected-cap-anchor-v4:\(try #require(recovered.visualReference).identity)"
    #expect(proposal.capAnchorEstimatorRevision == expectedEstimator)
    #expect(proposal.capAnchorEstimatorRevision != recovered.operatorObservation?.preservedAnchorEstimatorRevision)
    if saveFails { store.rejectReplacement(of: previousCheckpoint.machineCamera?.revision.id) }
    let accept = try productionLearningRequest(app, .cameraCalibration(.acceptProposal), owner: cameraOwner)
    let outcome = await app.submitPlotterUIRequest(accept)
    if saveFails {
      guard case .refused = outcome else {
        Issue.record("Rejected new-map save falsely returned accepted"); await app.shutdown(); return
      }
      #expect(app.machineCameraRegistration == oldMap)
      #expect(app.penCapAppearanceSelection == recovered)
      #expect(store.checkpoint == previousCheckpoint)
    } else {
      #expect(outcome == .accepted(requestID: accept.id))
      #expect(app.machineCameraRegistration == proposal)
      #expect(app.penCapAppearanceSelection?.operatorObservation == nil)
      #expect(app.penCapAppearanceSelection?.visualReference == recovered.visualReference)
      #expect(store.checkpoint?.penCapAppearance?.operatorObservation == nil)
      #expect(store.checkpoint?.machineCamera?.registration.capAnchorEstimatorRevision == expectedEstimator)
      #expect(app.capRecoveryDetail == nil)
      try #require(store.checkpoint).validate()
    }
    await app.shutdown()
  }

  @Test("partial two-circle failure releases Learning ownership and retains exactly the contacted locations")
  func partialBatchFailureAllowsObservationOnlyRecovery() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession()
    let observed = PartialCapCaptureFailure(base: resolvedObservationSession(camera))
    let store = ArtifactResetCheckpointStoreFixture()
    let machine = try LowerMachineSessionFixture(log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0),
      positionObserver: { camera.trackMachinePosition($0) })
    let boundary = TestBoundaryRuntimeAccess()
    let clock = TestClock()
    let app = plotterApplicationRuntime(machine: machine, observationSessionOverride: observed,
      statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: { store.load() },
        saveCheckpoint: { store.save($0) }, clearCheckpoint: { store.clear() }),
      residualEffectPort: TestApplicationResidualEffectPort(discoverDevices: { [machine.descriptor] },
        readNanoseconds: { clock.next() }, recordTelemetry: { await observed.record($0) }),
      boundaryRuntimeAccess: boundary, log: log)
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
    let pen = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await app.performTestExerciseAction(.start, for: pen)
    let initial = try #require(app.testActionSurfacePresentation.pointSelectionRequest)
    submitPointSelection(app, request: initial, point: try Point2(x: 11.5, y: 11.5))
    try await waitUntil { app.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await app.performTestExerciseAction(.choice(.yes), for: pen) }
    try await installAcceptedBoundaryTestProjection(runtime: #require(boundary.runtime),
      workspace: app, environment: .live, centerArrivalIsAccepted: false)
    try await machine.setPosition(x: 100, y: 50)
    await submitControllerSession(app, .requestPassiveProbe)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    await app.performTestExerciseAction(.boundary(.moveToEstimatedCenter(retry: false)), for: boundaryOwner)
    try await waitForAcceptedBoundaryCenterArrival(workspace: app)
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    await app.performTestExerciseAction(.cameraCalibration(.buildFivePositionProposal), for: cameraOwner)
    await app.performTestExerciseAction(.cameraCalibration(.acceptProposal), for: cameraOwner)
    let map = app.machineCameraRegistration
    let graph = app.learningArtifactGraph.revisions
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    let mark = try productionLearningRequest(app, .tipCalibration(.beginFourMarkBatch), owner: tipOwner)
    let penBeforeMark = await machine.requestedPenCommands
    let savedBeforeMark = store.checkpoint
    let markOutcome = await app.submitPlotterUIRequest(mark)
    guard case .refused = markOutcome else {
      let completed = await observed.completedCircles
      let state = await machine.snapshot()
      Issue.record("Failed partial batch outcome \(markOutcome); completed=\(completed), state=\(state), error=\(app.explorationError ?? "none")"); await app.shutdown(); return
    }
    #expect(await observed.completedCircles == 2)
    #expect(await observed.injectedLossCount == 1)
    #expect(app.activeExerciseAttemptID == nil)
    #expect(app.activeExerciseAttemptOwnerID == nil)
    #expect(app.contextualStopPresentation == nil)
    #expect(app.tipCalibrationRuntime.activeOperationID == nil)
    let locations = app.blacklistedToolContactLocations
    #expect(Set(locations.map(\.calibrationPosition)) == Set(PlotterTipCalibrationRuntime.orderedPositions.prefix(2)))
    #expect(locations.count == 2)
    #expect(!locations.contains { $0.calibrationPosition == PlotterTipCalibrationRuntime.orderedPositions[2] })
    let before = await machine.snapshot()
    let beforeStrokes = await machine.requestedDrawingStrokes
    let beforePen = await machine.requestedPenCommands
    let beforeFeeds = await machine.requestedFeeds
    #expect(beforeStrokes.count == 32)
    #expect(beforePen.dropFirst(penBeforeMark.count).filter { $0 == .lower }.count == 2)
    #expect(app.learningArtifactGraph.revisions == graph)
    #expect(app.machineCameraRegistration == map)

    // Possible ink forbids marking, but the explicit capture-only recovery is available.
    let recoveryProjection = app.testPlotterUIProjection(selectedItemID: tipOwner,
      includesLearningPath: true).semantic
    let recoveryRequest = recoveryProjection.request(for: PlotterAppUIActionID.reidentifyPenCap)
    let recovery = try #require(recoveryRequest, "Capture-only recovery unavailable: \(recoveryProjection.actions.first { $0.id == PlotterAppUIActionID.reidentifyPenCap }?.unavailableReason ?? "unknown")")
    guard case .accepted = await app.submitPlotterUIRequest(recovery) else {
      Issue.record("Settled possible-ink state blocked capture-only recovery"); await app.shutdown(); return
    }
    let selection = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
    #expect(selection.referenceGeometry != nil)
    #expect(app.activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction))
    let captured = await machine.snapshot()
    #expect(captured.machine.position == before.machine.position)
    #expect(captured.machine.penState == before.machine.penState)
    #expect(await machine.requestedDrawingStrokes == beforeStrokes)
    #expect(await machine.requestedPenCommands == beforePen)
    #expect(await machine.requestedFeeds == beforeFeeds)
    #expect(app.blacklistedToolContactLocations == locations)
    let cancel = try productionLearningRequest(app, .cancel, owner: .humanGuidedDiscovery(.penInteraction))
    guard case .accepted = await app.submitPlotterUIRequest(cancel) else {
      Issue.record("Recovery cancellation failed"); await app.shutdown(); return
    }
    #expect(app.activeExerciseAttemptID == nil)
    #expect(app.machineCameraRegistration == map)
    #expect(app.blacklistedToolContactLocations == locations)

    // Re-enter and commit the exact operator observation through the same UI
    // sink. A successful recovery also preserves marks and all physical state.
    let nextRecoveryProjection = app.testPlotterUIProjection(selectedItemID: tipOwner,
      includesLearningPath: true).semantic
    let nextRecovery = try #require(nextRecoveryProjection.request(for: PlotterAppUIActionID.reidentifyPenCap))
    #expect(await app.submitPlotterUIRequest(nextRecovery) == .accepted(requestID: nextRecovery.id))
    let exact = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
    let predicted = try #require(map).fit.cameraPoint(from: #require(before.machine.position).point)
    let clicked = PlotterPointSelectionSubmission(selectionID: exact.id, frame: exact.frame,
      point: predicted, presentationTransformRevision: exact.presentationTransformRevision,
      referenceRegion: try AxisAlignedBounds(minX: 0, minY: 0, maxX: 12, maxY: 12))
    let clickProjection = app.plotterUIProjection(selectedItemID: pen, manualDraft: ManualMotionDraft(),
      includesLearningPath: true, pendingPointSelection: clicked).semantic
    let clickRequest = try #require(clickProjection.request(for: PlotterAppUIActionID.pointSelection(clicked)))
    let clickOutcome = await app.submitPlotterUIRequest(clickRequest)
    #expect(clickOutcome == .accepted(requestID: clickRequest.id), "\(app.discoveryError ?? "no error")")
    #expect(app.activeExerciseAttemptID == nil)
    #expect(app.blacklistedToolContactLocations == locations)
    #expect(app.machineCameraRegistration == map)
    #expect(app.learningArtifactGraph.revisions == graph)
    let confirmed = try #require(app.penCapAppearanceSelection?.operatorObservation)
    #expect(confirmed.residualPixels == 0)
    #expect(confirmed.isExtrapolated)
    #expect(confirmed.predictionDomain == map?.applicabilityRectangle)
    #expect(app.machineCameraRegistration?.applicabilityRectangle == map?.applicabilityRectangle)
    #expect(app.capRecoveryDetail?.contains("extrapolated prediction (advisory only") == true)
    #expect(await machine.requestedDrawingStrokes == beforeStrokes)
    #expect(await machine.requestedPenCommands == beforePen)
    #expect(await machine.requestedFeeds == beforeFeeds)

    // The new exact retry path reports only preparations that actually happen.
    let redo = try productionLearningRequest(app, .redoThisStep, owner: cameraOwner)
    guard case .accepted = await app.submitPlotterUIRequest(redo) else {
      Issue.record("Settled failed tip owner still blocked Camera Redo"); await app.shutdown(); return
    }
    let preparedAttempt = try #require(app.activeExerciseAttemptID)
    #expect(app.activeExerciseAttemptOwnerID == cameraOwner)
    for action in [PlotterLearningAction.redoThisStep, .recordAnotherAttempt] {
      let other = currentLearningRequestEvenIfUnavailable(app, action,
        owner: .humanGuidedDiscovery(.penInteraction))
      guard case .refused = await app.submitPlotterUIRequest(other) else {
        Issue.record("No-op attempt preparation falsely returned accepted"); continue
      }
      #expect(app.activeExerciseAttemptID == preparedAttempt)
      #expect(app.activeExerciseAttemptOwnerID == cameraOwner)
    }
    await app.performTestExerciseAction(.cancel, for: cameraOwner)
    let after = await machine.snapshot()
    #expect(after.machine.position == before.machine.position)
    #expect(await machine.requestedDrawingStrokes == beforeStrokes)
    #expect(await machine.requestedPenCommands == beforePen)
    #expect(await machine.requestedFeeds == beforeFeeds)
    #expect(app.blacklistedToolContactLocations == locations)
    #expect(app.machineCameraRegistration == map)
    #expect(store.checkpoint?.penInteraction == savedBeforeMark?.penInteraction)
    #expect(store.checkpoint?.machineArtifacts == savedBeforeMark?.machineArtifacts)
    #expect(store.checkpoint?.machineCamera == savedBeforeMark?.machineCamera)
    #expect(store.checkpoint?.penCapAppearance?.operatorObservation?.isExtrapolated == true)
    try #require(store.checkpoint).validate()
    await app.shutdown()
  }
}

@MainActor
private func productionLearningRequest(_ app: PlotterApplicationRuntime,
  _ action: PlotterLearningAction, owner: LearningPathItemID) throws -> PlotterUIRequest {
  let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
  let intent = PlotterLearningActionRequest(item: .init(rawValue: "\(owner.number)-\(owner.title)"), action: action)
  return try #require(projection.request(matching: .learningAction(intent)),
    "Missing enabled \(action): \(app.explorationError ?? app.discoveryError ?? "no error")")
}

@MainActor
private func currentLearningRequestEvenIfUnavailable(_ app: PlotterApplicationRuntime,
  _ action: PlotterLearningAction, owner: LearningPathItemID) -> PlotterUIRequest {
  let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
  let intent = PlotterLearningActionRequest(item: .init(rawValue: "\(owner.number)-\(owner.title)"), action: action)
  return projection.request(matching: .learningAction(intent)) ?? PlotterUIRequest(
    id: .init(rawValue: UUID()), uiRevision: projection.revision,
    runtimeRevisions: projection.runtimeRevisions, actionID: .init(learningRequest: intent),
    intent: .learningAction(intent))
}

/// Injects the detector's terminal loss at the LIVE camera-session boundary,
/// after the production telemetry owner acknowledges exactly two real requests.
/// Pixel matching is independently tested in the matcher suite.
private actor PartialCapCaptureFailure: PlotterObservationCameraSessionPort {
  let base: any PlotterObservationCameraSessionPort
  private(set) var completedCircles = 0
  private(set) var injectedLossCount = 0
  private var shouldLoseNextCap = false
  init(base: any PlotterObservationCameraSessionPort) { self.base = base }
  func record(_ event: WorkflowTelemetryEvent) {
    guard event.operation == .sparseTipCalibration, event.phase == .circleCompleted,
      let count = event.sparseTipProgress?.completedCircleCount else { return }
    completedCircles = count
    if count == 2 { shouldLoseNextCap = true }
  }
  func captureStableWorkflowCap(_ request: StableWorkflowCapCaptureRequest) async throws -> StableWorkflowCapInspection {
    if shouldLoseNextCap {
      shouldLoseNextCap = false
      injectedLossCount += 1
      throw LearningPathOperationError.requiredState("Pen-cap measurement refused: no-pen-cap-detected (injected at the camera boundary).")
    }
    return try await base.captureStableWorkflowCap(request)
  }
  func discover() async -> CameraCaptureSnapshot { await base.discover() }
  func select(_ id: CameraDeviceID) async throws -> CameraCaptureSnapshot { try await base.select(id) }
  func start() async -> CameraCaptureSnapshot { await base.start() }
  func stop() async -> CameraCaptureSnapshot { await base.stop() }
  func restart() async -> CameraCaptureSnapshot { await base.restart() }
  func snapshot() async -> CameraCaptureSnapshot { await base.snapshot() }
  func frames() async -> AsyncStream<DisplayedFrame> { await base.frames() }
  func captureFrame(newerThanNanoseconds boundary: UInt64) async throws -> DisplayedFrame? {
    try await base.captureFrame(newerThanNanoseconds: boundary)
  }
  func inspectWorkflowScene(newerThanNanoseconds boundary: UInt64,
    requestedFeatures: SceneFeatureSet, analysisRegion: PixelRect?) async throws -> LiveSceneInspection? {
    try await base.inspectWorkflowScene(newerThanNanoseconds: boundary, requestedFeatures: requestedFeatures, analysisRegion: analysisRegion)
  }
  func setSceneAnalysisRegion(_ region: PixelRect?) async { await base.setSceneAnalysisRegion(region) }
  func setPenCapReference(_ reference: PenCapVisualReference?) async { await base.setPenCapReference(reference) }
  func setPenCapColor(_ color: PenCapColor) async { await base.setPenCapColor(color) }
  func setAutomaticInspection(_ cadence: VisionAnalysisCadence?, requestedFeatures: SceneFeatureSet) async -> PlotterSceneAnalysisSnapshot {
    await base.setAutomaticInspection(cadence, requestedFeatures: requestedFeatures)
  }
  func analysisUpdates() async -> AsyncStream<PlotterSceneAnalysisSnapshot> { await base.analysisUpdates() }
  func visionDiagnostics() async -> CameraSourceSessionVisionDiagnostics { await base.visionDiagnostics() }
  func observePlannedDrawingInk(_ request: PlannedDrawingObservationRequest) async -> PlannedDrawingObservationOutcome {
    await base.observePlannedDrawingInk(request)
  }
}

private final class CameraReplacementSaveStore: @unchecked Sendable {
  private let lock = NSLock()
  private let storage = ArtifactResetCheckpointStoreFixture()
  private var rejectedPriorRevision: LearningArtifactRevisionID?
  var checkpoint: AcceptedLearningPathCheckpoint? { storage.checkpoint }
  func load() -> AcceptedLearningPathCheckpointLoadResult { storage.load() }
  func clear() { storage.clear() }
  func rejectReplacement(of revision: LearningArtifactRevisionID?) {
    lock.withLock { rejectedPriorRevision = revision }
  }
  func save(_ candidate: AcceptedLearningPathCheckpoint) throws {
    let reject = lock.withLock {
      rejectedPriorRevision.map { candidate.machineCamera?.revision.id != $0 } ?? false
    }
    if reject { throw LearningPathOperationError.requiredState("Injected camera replacement save failure") }
    storage.save(candidate)
  }
}
