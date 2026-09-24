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
    do {
      try await waitForExecutorTurns { traffic.subscriptionCount == 1 }
    } catch {
      throw TestTimeout(conditionDescription:
        "initial analysis subscription: subscriptions=\(traffic.subscriptionCount), configurations=\(camera.recordedAutomaticInspectionRequests.count), revision=\(app.visionAnalysisSnapshot.revision), phase=\(app.visionAnalysisSnapshot.phase.state); \(error)")
    }
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
    let camera = try TestObservationCameraSession(machineTrackingOrigin: 12)
    let machine = try LowerMachineSessionFixture(log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0),
      positionObserver: { camera.trackMachinePosition($0) })
    let store = CameraReplacementSaveStore()
    let boundary = TestBoundaryRuntimeAccess()
    let app = plotterApplicationRuntime(machine: machine,
      observationSessionOverride: recoveryObservationSession(camera),
      statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: { store.load() },
        saveCheckpoint: { try store.save($0) }, clearCheckpoint: { store.clear() }),
      boundaryRuntimeAccess: boundary, log: log)
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
    let pen = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await app.performTestExerciseAction(.start, for: pen)
    let initial = try #require(app.testActionSurfacePresentation.pointSelectionRequest)
    submitPointSelection(app, request: initial, point: try await recoveryMarkerSeed(app))
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
      point: point, presentationTransformRevision: selection.presentationTransformRevision)
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
    let expectedEstimator = recovered.trackingEstimatorRevision
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
      #expect(app.penCapAppearanceSelection?.markerReference == recovered.markerReference)
      #expect(app.penCapAppearanceSelection?.visualReference == nil)
      #expect(store.checkpoint?.penCapAppearance?.operatorObservation == nil)
      #expect(store.checkpoint?.machineCamera?.registration.capAnchorEstimatorRevision == expectedEstimator)
      #expect(app.capRecoveryDetail == nil)
      try #require(store.checkpoint).validate()
    }
    await app.shutdown()
  }

  @Test("first Camera sample-five cap loss recovers without motion and completes the published retry")
  func firstCameraCapLossReturnsToAcceptedCenter() async throws {
    let fixture = try await makeCameraReturnFixture()
    let app = fixture.app
    let machine = fixture.machine
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let boundaryBefore = try #require((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts)
    let graphBefore = app.learningArtifactGraph.revisions
    let previousReference = try #require(app.penCapAppearanceSelection?.markerReference)
    let center = try #require(boundaryBefore.centerArrivalPosition)
    var selection = LearningPathSelectionState(current: app.currentLearningPathItemID)
    try #require(selection.current == cameraOwner)
    var reviewing = selection
    reviewing.select(.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering))
    await fixture.observation.loseStableCapture(number: 6)
    let feedsBefore = await machine.requestedFeeds.count
    let run = try productionLearningRequest(app, .cameraCalibration(.buildFivePositionProposal), owner: selection.selected)
    guard case .refused = await app.submitPlotterUIRequest(run) else {
      Issue.record("Sample-five detector loss must refuse Camera completion."); await app.shutdown(); return
    }
    #expect(await fixture.observation.injectedLossCount == 1)
    #expect(app.machineCameraRegistration == nil)
    #expect(app.proposedMachineCameraRegistration == nil)
    let lost = try #require((await machine.snapshot()).machine.position)
    #expect(abs(lost.point.x - center.point.x) < 0.001)
    #expect(abs(lost.point.y - (center.point.y - 24)) < 0.001)
    #expect(await machine.requestedFeeds.count == feedsBefore + 4)
    let returnID = learningActionID(.cameraCalibration(.returnToAcceptedCenter), owner: cameraOwner)
    #expect(app.testPlotterUIProjection(selectedItemID: cameraOwner, includesLearningPath: true)
      .semantic.request(for: returnID) != nil)
    let penBefore = await machine.requestedPenCommands
    let recovery = try #require(app.testPlotterUIProjection(selectedItemID: cameraOwner,
      includesLearningPath: true).semantic.request(for: PlotterAppUIActionID.reidentifyPenCap))
    #expect(await app.submitPlotterUIRequest(recovery) == .accepted(requestID: recovery.id))
    selection.updateCurrent(app.currentLearningPathItemID)
    reviewing.updateCurrent(app.currentLearningPathItemID)
    #expect(selection.selected == penOwner)
    #expect(reviewing.selected == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering))
    let cancel = try productionLearningRequest(app, .cancel, owner: selection.selected)
    #expect(await app.submitPlotterUIRequest(cancel) == .accepted(requestID: cancel.id))
    selection.updateCurrent(app.currentLearningPathItemID)
    #expect(selection.selected == cameraOwner)
    #expect(app.activeExerciseAttemptOwnerID == cameraOwner)
    // The cancelled observation restored a prepared Camera owner. Cancel that
    // prepared attempt before selecting a fresh observation, as normal UI does.
    let cameraCancel = try productionLearningRequest(app, .cancel, owner: cameraOwner)
    #expect(await app.submitPlotterUIRequest(cameraCancel) == .accepted(requestID: cameraCancel.id))
    let again = try #require(app.testPlotterUIProjection(selectedItemID: cameraOwner,
      includesLearningPath: true).semantic.request(for: PlotterAppUIActionID.reidentifyPenCap))
    #expect(await app.submitPlotterUIRequest(again) == .accepted(requestID: again.id))
    selection.updateCurrent(app.currentLearningPathItemID)
    let exact = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
    let clicked = PlotterPointSelectionSubmission(selectionID: exact.id, frame: exact.frame,
      point: try await recoveryMarkerSeed(app), presentationTransformRevision: exact.presentationTransformRevision)
    let clickProjection = app.plotterUIProjection(selectedItemID: selection.selected,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingPointSelection: clicked).semantic
    let click = try #require(clickProjection.request(for: PlotterAppUIActionID.pointSelection(clicked)))
    let clickOutcome = await app.submitPlotterUIRequest(click)
    try #require(clickOutcome == .accepted(requestID: click.id), "\(clickOutcome)")
    let recoveredReference = try #require(app.penCapAppearanceSelection?.markerReference)
    #expect(exact.referenceMode == .sampledColorMarker)
    #expect(recoveredReference.color == previousReference.color)
    #expect(recoveredReference.componentPixelCount == previousReference.componentPixelCount)
    #expect(recoveredReference.selectionPoint == recoveredReference.acquisitionAnchor)
    #expect(recoveredReference.frameID != previousReference.frameID)
    #expect(app.penCapAppearanceSelection?.visualReference == nil)
    #expect(app.machineCameraRegistration == nil)
    selection.updateCurrent(app.currentLearningPathItemID)
    reviewing.updateCurrent(app.currentLearningPathItemID)
    #expect(selection.selected == cameraOwner)
    #expect(reviewing.selected == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering))
    #expect((await machine.snapshot()).machine.position == lost)
    #expect(await machine.requestedFeeds.count == feedsBefore + 4)
    #expect(await machine.requestedPenCommands == penBefore)
    #expect((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts == boundaryBefore)
    #expect(app.learningArtifactGraph.revisions == graphBefore)
    let returnRequest = try productionLearningRequest(app, .cameraCalibration(.returnToAcceptedCenter), owner: selection.selected)
    #expect(await app.submitPlotterUIRequest(returnRequest) == .accepted(requestID: returnRequest.id))
    #expect((await machine.snapshot()).machine.position == center)
    #expect(await machine.requestedFeeds.count == feedsBefore + 5)
    #expect((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts == boundaryBefore)
    #expect(app.learningArtifactGraph.revisions == graphBefore)
    let retry = try productionLearningRequest(app, .cameraCalibration(.buildFivePositionProposal), owner: selection.selected)
    #expect(await app.submitPlotterUIRequest(retry) == .accepted(requestID: retry.id))
    let proposal = try #require(app.proposedMachineCameraRegistration)
    #expect(proposal.correspondenceProvenance.count == 5)
    #expect((await machine.snapshot()).machine.position == center)
    let accept = try productionLearningRequest(app, .cameraCalibration(.acceptProposal), owner: selection.selected)
    #expect(await app.submitPlotterUIRequest(accept) == .accepted(requestID: accept.id))
    #expect(app.machineCameraRegistration == proposal)
    #expect((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts == boundaryBefore)
    #expect(await machine.requestedDrawingStrokes.isEmpty)
    await app.shutdown()
  }

  @Test("cancelled Camera replacement remains the destination after cap observation", arguments: [false, true])
  func cameraReplacementDestinationSurvivesRecovery(cancelObservation: Bool) async throws {
    let fixture = try await makeCameraReturnFixture()
    let app = fixture.app
    let camera = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    for action in [PlotterLearningAction.cameraCalibration(.buildFivePositionProposal), .cameraCalibration(.acceptProposal), .redoThisStep, .cancel] {
      let request = try productionLearningRequest(app, action, owner: camera)
      #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    }
    let map = try #require(app.machineCameraRegistration)
    let before = await fixture.machine.snapshot()
    let feeds = await fixture.machine.requestedFeeds
    var selection = LearningPathSelectionState(current: app.currentLearningPathItemID)
    selection.select(camera)
    let reidentify = try #require(app.testPlotterUIProjection(selectedItemID: selection.selected,
      includesLearningPath: true).semantic.request(for: PlotterAppUIActionID.reidentifyPenCap))
    #expect(await app.submitPlotterUIRequest(reidentify) == .accepted(requestID: reidentify.id))
    selection.updateCurrent(app.currentLearningPathItemID)
    #expect(selection.selected == camera)
    if cancelObservation {
      let request = try productionLearningRequest(app, .cancel, owner: .humanGuidedDiscovery(.penInteraction))
      #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    } else {
      let exact = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
      let point = try map.fit.cameraPoint(from: #require(before.machine.position).point)
      let click = PlotterPointSelectionSubmission(selectionID: exact.id, frame: exact.frame,
        point: point, presentationTransformRevision: exact.presentationTransformRevision)
      let projection = app.plotterUIProjection(selectedItemID: selection.selected,
        manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingPointSelection: click).semantic
      let request = try #require(projection.request(for: PlotterAppUIActionID.pointSelection(click)))
      let outcome = await app.submitPlotterUIRequest(request)
      try #require(outcome == .accepted(requestID: request.id), "\(outcome)")
    }
    selection.updateCurrent(app.currentLearningPathItemID)
    #expect(selection.current == camera)
    #expect(selection.selected == camera)
    #expect(app.activeExerciseAttemptOwnerID == camera)
    #expect(app.machineCameraRegistration == map)
    #expect((await fixture.machine.snapshot()).machine.position == before.machine.position)
    #expect(await fixture.machine.requestedFeeds == feeds)
    #expect(app.testPlotterUIProjection(selectedItemID: selection.selected, includesLearningPath: true)
      .semantic.request(for: learningActionID(.cameraCalibration(.buildFivePositionProposal), owner: camera)) != nil)
    await app.shutdown()
  }

  @Test("marker Locate and replacement each retain one exact reference without granting a map")
  func replacementClearsPreMapAppearanceHistory() async throws {
    let fixture = try await makeCameraReturnFixture()
    let app = fixture.app
    let graph = app.learningArtifactGraph.revisions
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    for replaces in [false, true] {
      let id = replaces ? PlotterAppUIActionID.replacePenCapReference : PlotterAppUIActionID.reidentifyPenCap
      let start = try #require(app.testPlotterUIProjection(selectedItemID: app.currentLearningPathItemID,
        includesLearningPath: true).semantic.request(for: id))
      #expect(await app.submitPlotterUIRequest(start) == .accepted(requestID: start.id))
      let exact = try #require(app.pointSelectionEpisodeProjection.exactPointSelection.request)
      let click = PlotterPointSelectionSubmission(selectionID: exact.id, frame: exact.frame,
        point: try await recoveryMarkerSeed(app), presentationTransformRevision: exact.presentationTransformRevision)
      let projection = app.plotterUIProjection(selectedItemID: owner, manualDraft: ManualMotionDraft(),
        includesLearningPath: true, pendingPointSelection: click).semantic
      let request = try #require(projection.request(for: PlotterAppUIActionID.pointSelection(click)))
      let outcome = await app.submitPlotterUIRequest(request)
      try #require(outcome == .accepted(requestID: request.id), "\(outcome)")
      let reference = try #require(app.penCapAppearanceSelection?.markerReference)
      #expect(exact.referenceMode == .sampledColorMarker)
      #expect(reference.selectionPoint == reference.acquisitionAnchor)
      #expect(reference.frameID.rawValue == exact.frame.frameID)
      #expect(app.penCapAppearanceSelection?.visualReference == nil)
      #expect(app.machineCameraRegistration == nil)
      #expect(app.learningArtifactGraph.revisions == graph)
    }
    #expect(await fixture.machine.requestedFeeds.isEmpty)
    await app.shutdown()
  }

  @Test("fresh off-center MPos replaces a stale Run projection with explicit center return")
  func freshPositionExposesReturnAction() async throws {
    let fixture = try await makeCameraReturnFixture()
    let app = fixture.app
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let center = try #require((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts?.centerArrivalPosition)
    let request = try productionLearningRequest(app, .cameraCalibration(.buildFivePositionProposal), owner: owner)
    try await fixture.machine.setPosition(x: center.point.x, y: center.point.y - 24)
    let feeds = await fixture.machine.requestedFeeds
    guard case .refused = await app.submitPlotterUIRequest(request) else {
      Issue.record("Fresh off-center position must refuse calibration capture."); await app.shutdown(); return
    }
    let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true)
    #expect(projection.semantic.request(for: learningActionID(.cameraCalibration(.returnToAcceptedCenter), owner: owner)) != nil)
    #expect(projection.semantic.request(for: learningActionID(.cameraCalibration(.buildFivePositionProposal), owner: owner)) == nil)
    #expect(await fixture.machine.requestedFeeds == feeds)
    #expect(app.machineCameraRegistration == nil)
    await app.shutdown()
  }

  @Test("Stop cancels the exact accepted-center return without publishing arrival or calibration")
  func centerReturnStopPreservesAuthority() async throws {
    let fixture = try await makeCameraReturnFixture(automaticallySettlesTravel: false)
    let app = fixture.app
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let prior = try #require((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts)
    let graph = app.learningArtifactGraph.revisions
    let center = try #require(prior.centerArrivalPosition)
    try await fixture.machine.setPosition(x: center.point.x, y: center.point.y - 24)
    await submitControllerSession(app, .requestPassiveProbe)
    var disposition: PlotterUIRequestDisposition?
    let task = Task { @MainActor in
      let request = try productionLearningRequest(app, .cameraCalibration(.returnToAcceptedCenter), owner: owner)
      disposition = await app.submitPlotterUIRequest(request)
    }
    do {
      try await waitUntilAsync { await fixture.machine.relativeJogIsAwaitingSettlement || disposition != nil }
      try #require(await fixture.machine.relativeJogIsAwaitingSettlement)
      let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
      let stop = try #require(projection.actions.first { action in
        guard case .learningAction(let request) = action.intent,
          case .stop = request.action else { return false }
        return action.isAvailable
      }.flatMap { projection.request(for: $0.id) })
      #expect(await app.submitPlotterUIRequest(stop) == .accepted(requestID: stop.id))
      try await waitUntil { disposition != nil }
      try await task.value
      guard case .refused = disposition else {
        Issue.record("Stopped center travel must never acknowledge arrival."); await app.shutdown(); return
      }
      #expect((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts == prior)
      #expect(app.learningArtifactGraph.revisions == graph)
      #expect(app.proposedMachineCameraRegistration == nil)
      #expect(app.machineCameraRegistration == nil)
      #expect((await fixture.machine.snapshot()).machine.position != center)
      await app.shutdown()
    } catch {
      await app.shutdown()
      throw error
    }
  }

  @Test("cancelled or revised authority during Pen-Up normalization never admits center XY", arguments: ["cancel", "boundary", "pose"])
  func centerReturnRevalidatesAfterPenNormalization(change: String) async throws {
    let penGate = PenRequestGate()
    await penGate.releaseFirstRequest()
    let fixture = try await makeCameraReturnFixture(penGate: penGate)
    let app = fixture.app
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let prior = try #require((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts)
    let center = try #require(prior.centerArrivalPosition)
    try await fixture.machine.setPosition(x: center.point.x, y: center.point.y - 24)
    await submitControllerSession(app, .requestPassiveProbe)
    let feeds = await fixture.machine.requestedFeeds
    await penGate.holdNextRequest()
    var outcome: PlotterUIRequestDisposition?
    let task = Task { @MainActor in
      let request = try productionLearningRequest(app, .cameraCalibration(.returnToAcceptedCenter), owner: owner)
      outcome = await app.submitPlotterUIRequest(request)
    }
    do {
      try await waitUntilAsync { await penGate.isHeld || outcome != nil }
      try #require(await penGate.isHeld)
      if change == "boundary" {
        try await installAcceptedBoundaryTestProjection(runtime: fixture.boundary,
          workspace: app, environment: .live)
      } else if change == "pose" {
        await fixture.machine.reportTransportAvailability(false)
        _ = await app.refreshControllerSessionSnapshot()
        #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
        await fixture.machine.reportTransportAvailability(true)
        _ = await app.refreshControllerSessionSnapshot()
        #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      } else { task.cancel() }
      await penGate.releaseFirstRequest()
      try await waitUntil { outcome != nil }
      try await task.value
      guard case .refused = outcome else {
        Issue.record("Cancelled or changed authority must refuse the pending return."); await app.shutdown(); return
      }
      #expect(await fixture.machine.requestedFeeds == feeds)
      #expect(app.proposedMachineCameraRegistration == nil)
      #expect((await fixture.machine.snapshot()).machine.position != center)
      await app.shutdown()
    } catch {
      task.cancel()
      await penGate.releaseFirstRequest()
      await app.shutdown()
      throw error
    }
  }

  @Test("saved historical Boundary session requires visual proof before center return and camera retry", arguments: [false, true])
  func historicalBoundaryReturnRequiresCurrentPose(verifyPose: Bool) async throws {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(accepted)
    let machine = try LowerMachineSessionFixture(log: EventLog(),
      relativeJogSettlementOffset: Vector2(dx: 0, dy: 0))
    let checkpoint = try #require(accepted.checkpoint.machineArtifacts)
    let map = try #require(accepted.checkpoint.machineCamera).registration
    let center = try #require(checkpoint.centerArrivalPosition)
    try await machine.setPosition(x: center.point.x, y: center.point.y - 24)
    let clock = ComputationTestClock()
    clock.set(max(clock.read(), accepted.frame.frame.captureNanoseconds))
    let camera = try AcceptedDrawingCameraSession(frame: accepted.frame, clock: clock)
    let observed = PartialCapCaptureFailure(base: camera, beforeCapture: {
      let position = try #require((await machine.snapshot()).machine.position)
      await camera.configurePoseCapture(anchor: try map.fit.cameraPoint(from: position.point))
    })
    let app = plotterApplicationRuntime(machine: machine, observationSessionOverride: observed,
      statePersistencePort: stores.persistence, tipCalibrationSemanticIdentities: accepted.identities,
      residualEffectPort: TestApplicationResidualEffectPort(discoverDevices: { [machine.descriptor] },
        readNanoseconds: { clock.read() }), loadPenCapAppearanceSelection: { nil }, log: EventLog())
    await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await app.establishMachineSession(machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    await submitObservationConfigurationForTest(app, .selectSource(.live, camera.device.id))
    try await applyCompleteSavedLearning(app)
    await machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let currentSession = await app.currentBoundaryExternalFacts(for: .live).controllerSessionID
    #expect(currentSession != checkpoint.controllerSessionID)
    if verifyPose { try await reestablishPhysicalPositionForTest(app) }
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let redo = try productionLearningRequest(app, .redoThisStep, owner: owner)
    #expect(await app.submitPlotterUIRequest(redo) == .accepted(requestID: redo.id))
    let feeds = await machine.requestedFeeds
    let request = currentLearningRequestEvenIfUnavailable(app, .cameraCalibration(.returnToAcceptedCenter), owner: owner)
    let outcome = await app.submitPlotterUIRequest(request)
    if verifyPose {
      try #require(outcome == .accepted(requestID: request.id), "\(outcome)")
      #expect((await machine.snapshot()).machine.position == center)
      #expect(app.learningArtifactGraph.currentRevision(for: .centerArrival)?.id == checkpoint.acceptedRevisions.first { $0.kind == .centerArrival }?.id)
      let run = try productionLearningRequest(app, .cameraCalibration(.buildFivePositionProposal), owner: owner)
      try #require(await app.submitPlotterUIRequest(run) == .accepted(requestID: run.id))
      let proposal = try #require(app.proposedMachineCameraRegistration)
      #expect(proposal.controllerSessionID == currentSession)
      #expect(proposal.correspondenceProvenance.allSatisfy { $0.controllerSessionID == currentSession })
      #expect(proposal.correspondenceProvenance.count == 5)
      if case .loaded(let saved) = stores.checkpointStore.load() {
        #expect(saved.machineArtifacts == checkpoint)
      } else { Issue.record("Saved Boundary checkpoint disappeared during Camera retry.") }
    } else {
      guard case .refused = outcome else {
        Issue.record("Historical coordinates without visual proof admitted a return."); await app.shutdown(); return
      }
      #expect(await machine.requestedFeeds == feeds)
      #expect(app.machineCameraRegistration == map)
    }
    await app.shutdown()
  }

  @Test("accepted-center return refuses Down or Unknown pen state without travel", arguments: [PenState.down, .unknown])
  func centerReturnRequiresFreshPenUp(_ state: PenState) async throws {
    let fixture = try await makeCameraReturnFixture()
    let app = fixture.app
    let center = try #require((await fixture.boundary.snapshot(for: .live)).acceptedMachineArtifacts?.centerArrivalPosition)
    try await fixture.machine.setPosition(x: center.point.x, y: center.point.y - 24)
    await submitControllerSession(app, .requestPassiveProbe)
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    let request = try productionLearningRequest(app, .cameraCalibration(.returnToAcceptedCenter), owner: owner)
    let feeds = await fixture.machine.requestedFeeds
    let pen = await fixture.machine.requestedPenCommands
    await fixture.machine.setPenState(state)
    guard case .refused = await app.submitPlotterUIRequest(request) else {
      Issue.record("Unproved Pen Up must refuse center travel."); await app.shutdown(); return
    }
    #expect(await fixture.machine.requestedFeeds == feeds)
    #expect(await fixture.machine.requestedPenCommands == pen)
    #expect(app.machineCameraRegistration == nil)
    await app.shutdown()
  }

  @Test("partial two-circle failure releases Learning ownership and retains exactly the contacted locations")
  func partialBatchFailureAllowsObservationOnlyRecovery() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession(machineTrackingOrigin: 12)
    let observed = PartialCapCaptureFailure(base: recoveryObservationSession(camera))
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
    submitPointSelection(app, request: initial, point: try await recoveryMarkerSeed(app))
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
    #expect(selection.referenceMode == .sampledColorMarker)
    #expect(selection.referenceGeometry == nil)
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
      point: predicted, presentationTransformRevision: exact.presentationTransformRevision)
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
    let observedAnchor = try #require(app.penCapAppearanceSelection?.markerReference).acquisitionAnchor
    #expect(confirmed.residualPixels == predicted.distance(to: observedAnchor))
    // The synthetic camera quantizes its declared tracking point to whole pixels.
    #expect(confirmed.residualPixels <= sqrt(0.5))
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

/// These tests inject calibrated measurements. Their operator-selection pixels
/// must depict that same datum, rather than the shared fixture's stationary blob.
private func recoveryObservationSession(_ camera: TestObservationCameraSession) -> any PlotterObservationCameraSessionPort {
  resolvedObservationSession(camera, captureProvider: { boundary in
    let inspection = try camera.inspection(after: boundary)
    let original = inspection.displayedFrame
    let frame = original.frame
    let cap = try #require(inspection.measurement.penCap.measurement)
    // The shared mock has no explicit referenceAnchor: calibration therefore
    // consumes its bottom-center, not its deliberately offset centroid.
    let reported = try ToolCapAnchorEstimate(componentCentroid: cap.centroid,
      componentBounds: AxisAlignedBounds(minX: Double(cap.boundingBox.x),
        minY: Double(cap.boundingBox.y),
        maxX: Double(cap.boundingBox.x + cap.boundingBox.width),
        maxY: Double(cap.boundingBox.y + cap.boundingBox.height)),
      selectedAnchor: cap.referenceAnchor, confidence: cap.confidence,
      estimatorRevision: "recovery-fixture-declared-datum", source: original.source,
      frameID: frame.id, cameraConfigurationID: frame.cameraConfigurationID).point
    // The generic fixture declares (99,52) before it has any machine position.
    // Use the initial visible center only in that explicitly untracked state.
    let untracked = reported.x == 99 && reported.y == 52
    let x = untracked ? 12 : Int(reported.x.rounded())
    let y = untracked ? 12 : Int(reported.y.rounded())
    try #require(x >= 3 && x < frame.width - 3 && y >= 3 && y < frame.height - 3)
    var bytes = [UInt8](repeating: 12, count: frame.rowBytes * frame.height)
    for index in stride(from: 3, to: bytes.count, by: 4) { bytes[index] = 255 }
    for row in (y - 2)...(y + 2) { for column in (x - 2)...(x + 2) {
      let index = row * frame.rowBytes + column * 4
      bytes[index] = 105; bytes[index + 1] = 185; bytes[index + 2] = 45
    } }
    return DisplayedFrame(source: original.source, frame: try StampedFrame(
      id: frame.id, sequence: frame.sequence, captureNanoseconds: frame.captureNanoseconds,
      cameraConfigurationID: frame.cameraConfigurationID, width: frame.width, height: frame.height,
      rowBytes: frame.rowBytes, pixelFormat: frame.pixelFormat, bytes: OwnedFrameBytes(bytes)))
  })
}

@MainActor
private func recoveryMarkerSeed(_ app: PlotterApplicationRuntime) async throws -> Point2<CameraPixelSpace> {
  let frame = try #require(app.testActionSurfacePresentation.displayedFrame)
  let measured = try await VisionWorker().inspectPlotterScene(in: frame.frame, requestedFeatures: [.penCap])
  return try #require(measured.penCap.measurement).centroid
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
  let beforeCapture: @Sendable () async throws -> Void
  private(set) var completedCircles = 0
  private(set) var injectedLossCount = 0
  private var shouldLoseNextCap = false
  private var failingStableCapture: Int?
  private var stableCaptureCount = 0
  func loseStableCapture(number: Int) { stableCaptureCount = 0; failingStableCapture = number }
  init(base: any PlotterObservationCameraSessionPort,
    beforeCapture: @escaping @Sendable () async throws -> Void = {}) {
    self.base = base
    self.beforeCapture = beforeCapture
  }
  func record(_ event: WorkflowTelemetryEvent) {
    guard event.operation == .sparseTipCalibration, event.phase == .circleCompleted,
      let count = event.sparseTipProgress?.completedCircleCount else { return }
    completedCircles = count
    if count == 2 { shouldLoseNextCap = true }
  }
  func captureStableWorkflowCap(_ request: StableWorkflowCapCaptureRequest) async throws -> StableWorkflowCapInspection {
    try await beforeCapture()
    stableCaptureCount += 1
    if shouldLoseNextCap || stableCaptureCount == failingStableCapture {
      failingStableCapture = nil
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
    try await beforeCapture()
    return try await base.captureFrame(newerThanNanoseconds: boundary)
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

@MainActor
private func makeCameraReturnFixture(automaticallySettlesTravel: Bool = true, penGate: PenRequestGate? = nil) async throws -> (
  app: PlotterApplicationRuntime, machine: LowerMachineSessionFixture,
  observation: PartialCapCaptureFailure, boundary: PlotterBoundaryRuntime
) {
  let log = EventLog()
  let camera = try TestObservationCameraSession(machineTrackingOrigin: 12)
  let observed = PartialCapCaptureFailure(base: recoveryObservationSession(camera))
  let machine = try LowerMachineSessionFixture(log: log,
    relativeJogSettlementOffset: automaticallySettlesTravel ? try Vector2(dx: 0, dy: 0) : nil,
    penRequestGate: penGate,
    positionObserver: { camera.trackMachinePosition($0) })
  let store = ArtifactResetCheckpointStoreFixture()
  let boundary = TestBoundaryRuntimeAccess()
  let app = plotterApplicationRuntime(machine: machine, observationSessionOverride: observed,
    statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: { store.load() },
      saveCheckpoint: { store.save($0) }, clearCheckpoint: { store.clear() }),
    boundaryRuntimeAccess: boundary, log: log)
  await app.establishMachineSession(machine.descriptor)
  await submitControllerSession(app, .requestPassiveProbe)
  await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
  let pen = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
  await app.performTestExerciseAction(.start, for: pen)
  let initial = try #require(app.testActionSurfacePresentation.pointSelectionRequest)
  submitPointSelection(app, request: initial, point: try await recoveryMarkerSeed(app))
  try await waitUntil { app.activeDiscoverySequenceID == .penInteraction }
  for _ in 0..<3 { await app.performTestExerciseAction(.choice(.yes), for: pen) }
  try await installAcceptedBoundaryTestProjection(runtime: #require(boundary.runtime),
    workspace: app, environment: .live)
  let boundaryRuntime = try #require(boundary.runtime)
  let center = try #require((await boundaryRuntime.snapshot(for: .live)).acceptedMachineArtifacts?.centerArrivalPosition)
  try await machine.setPosition(x: center.point.x, y: center.point.y)
  await submitControllerSession(app, .requestPassiveProbe)
  return (app, machine, observed, try #require(boundary.runtime))
}
