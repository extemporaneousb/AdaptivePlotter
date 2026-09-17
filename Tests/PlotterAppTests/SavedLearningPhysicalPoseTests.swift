import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing
@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Saved Learning physical position", .serialized)
@MainActor
struct SavedLearningPhysicalPoseTests {
  @Test("complete Saved Learning retains calibration but cannot authorize Draw from unchanged MPos")
  func retainedLearningDoesNotProvePhysicalPosition() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    #expect(app.interactiveLearningIsComplete)
    #expect(app.tipCameraRegistration == f.accepted.registration)
    #expect(app.currentDrawableMachineRegion == f.accepted.drawableRegion)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.testActionSurfacePresentation.overlays.contains { $0.provenance.kind == .acceptedBoundary })
    try await selectPhysicalPosePortrait(f)
    try await f.submit(.assertPaperCoverage)
    await app.drawingDraftSynchronizationTask?.value
    let run = await f.runRuntime.synchronize(environment: .live)
    if case .unavailable(let issue) = run.readiness {
      #expect(issue.reason == .physicalPositionUnverified)
      #expect(issue.remedy == .reestablishPositionFromCamera)
    } else { Issue.record("Retained Learning bypassed the physical-position preflight") }
    let projection = app.testPlotterUIProjection()
    #expect(projection.semantic.request(matching: .drawingRun(.start)) == nil)
    #expect(!projection.semantic.actions.contains { $0.intent == .drawingRun(.start) && $0.isAvailable })
    // Exercise the canonical typed intent even when the UI omits the blocked
    // action. Constructing a request must not bypass retained-owner readiness.
    let draw = PlotterUIRequest(id: .init(rawValue: UUID()), uiRevision: projection.semantic.revision,
      runtimeRevisions: projection.semantic.runtimeRevisions,
      actionID: PlotterAppUIActionID.drawingRun(.start), intent: .drawingRun(.start))
    guard case .refused = await app.submitPlotterUIRequest(draw) else {
      Issue.record("Saved numeric MPos admitted Drawing without physical-position evidence")
      await app.shutdown(); return
    }
    #expect(await f.planGate.request == nil)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedDrawingStrokes.isEmpty)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    await app.shutdown()
  }

  @Test("contact-plane change keeps camera position recovery reachable without restoring invalidated tip calibration")
  func changedPlaneRetainsPrefixPositionRecovery() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    let originalMap = try #require(app.machineCameraRegistration)
    let originalPaper = app.currentPaperRevisionContext
    let penRevision = app.learningArtifactGraph.currentRevision(for: .penInteraction)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.tipCameraRegistration != nil)
    let changePlane = try #require(app.testPlotterUIProjection().semantic.request(
      matching: .paper(.contactPlaneChanged)))
    try #require(await app.submitPlotterUIRequest(changePlane) == .accepted(requestID: changePlane.id))
    let newPaper = app.currentPaperRevisionContext
    #expect(newPaper.contactPlane != originalPaper.contactPlane)
    #expect(newPaper.instance != originalPaper.instance)
    #expect(app.tipCameraRegistration == nil)
    #expect(app.machineCameraRegistration == originalMap)
    #expect(app.learningArtifactGraph.currentRevision(for: .penInteraction) == penRevision)
    #expect(app.penInteractionCompleted)
    #expect(!app.interactiveLearningIsComplete)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    _ = try physicalPositionRequest(app)
    try await reestablishPhysicalPositionForTest(app)
    #expect(app.currentPaperRevisionContext == newPaper)
    #expect(app.tipCameraRegistration == nil)
    #expect(app.machineCameraRegistration != nil)
    #expect(app.penInteractionCompleted)
    #expect(!app.interactiveLearningIsComplete)
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true).semantic
    let circles = PlotterLearningActionRequest(item: .init(rawValue: "\(owner.number)-\(owner.title)"),
      action: .tipCalibration(.beginFourMarkBatch))
    #expect(projection.request(matching: .learningAction(circles)) != nil)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedDrawingStrokes.isEmpty)
    guard case .loaded(let saved) = f.stores.checkpointStore.load() else {
      Issue.record("Plane-change recovery lost the retained Learning prefix"); await app.shutdown(); return
    }
    #expect(saved.tipCalibration == nil)
    #expect(saved.stageFour == nil)
    #expect(saved.machineCamera != nil)
    #expect(saved.penInteraction != nil)
    #expect(saved.semanticIdentity.paperContactPlane == newPaper.contactPlane)
    guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
      Issue.record("Plane-change recovery lost immutable drawing history"); await app.shutdown(); return
    }
    #expect(archive.records == [f.accepted.borderRecord])
    await app.shutdown()
  }

  @Test("unchanged controller position and translated physical cap rebase all accepted geometry without motion")
  func gravityTranslationRebasesCoherently() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    let oldMap = try #require(app.machineCameraRegistration)
    let oldTip = try #require(app.tipCameraRegistration)
    let oldRegion = try #require(app.currentDrawableMachineRegion)
    let oldPaper = app.currentPaperRevisionContext
    let controllerPosition = try #require((await f.machine.snapshot()).machine.position)
    let predictedCap = try oldMap.fit.cameraPoint(from: controllerPosition.point)
    // The carriage moved with power absent, while MPos did not. Supply a
    // separately observed cap anchor, never a changed controller coordinate.
    let observedCap = try Point2<CameraPixelSpace>(x: (predictedCap.x + 48).rounded(),
      y: (predictedCap.y + 32).rounded())
    await f.camera.configurePoseCapture(anchor: observedCap)
    let formerPhysicalPoint = try oldMap.fit.machinePoint(from: observedCap)
    let expectedDelta = try formerPhysicalPoint.vector(to: controllerPosition.point)
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let commands = await f.machine.requestedPenCommands
    try await reestablishPhysicalPositionForTest(app)
    let newTip = try #require(app.tipCameraRegistration)
    let newMap = try #require(app.machineCameraRegistration)
    let newRegion = try #require(app.currentDrawableMachineRegion)
    #expect((await f.machine.snapshot()).machine.position == controllerPosition)
    #expect(await f.machine.requestedPenCommands == commands)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedDrawingStrokes.isEmpty)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.activeExerciseAttemptID == nil)
    #expect(app.testActionSurfacePresentation.pointSelectionRequest == nil)
    #expect(app.currentPaperRevisionContext == oldPaper)
    #expect(newTip.applicability.machineCoordinateFrame.rawValue
      == oldTip.applicability.machineCoordinateFrame.rawValue + 1)
    #expect(newMap.coordinateRevision == newTip.applicability.machineCoordinateFrame.rawValue)
    #expect(abs(newRegion.bounds.minX - oldRegion.bounds.minX - expectedDelta.dx) < 0.000_001)
    #expect(abs(newRegion.bounds.minY - oldRegion.bounds.minY - expectedDelta.dy) < 0.000_001)
    #expect(try newMap.fit.cameraPoint(from: controllerPosition.point).distance(to: observedCap) < 0.000_001)
    // A point on the retained paper projects to the same pixel after all
    // machine-space authorities translate together.
    let oldPoint = try Point2<MachineSpace>(
      x: (oldTip.applicabilityRectangle.minX + oldTip.applicabilityRectangle.maxX) / 2,
      y: (oldTip.applicabilityRectangle.minY + oldTip.applicabilityRectangle.maxY) / 2)
    let newPoint = try oldPoint.translated(by: expectedDelta)
    #expect(try newTip.tipPixel(at: newPoint).distance(to: oldTip.tipPixel(at: oldPoint)) < 0.000_001)
    let evidence = try #require(newTip.revalidationEvidence)
    if case .visuallyRevalidated(let frameID, _) = app.controllerPoseApplicability {
      #expect(frameID == evidence.frame.frameID)
    } else { Issue.record("Current pose lacks exact observed frame authority") }
    guard case .loaded(let saved) = f.stores.checkpointStore.load() else {
      Issue.record("Rebased authority did not persist"); await app.shutdown(); return
    }
    #expect(saved.tipCalibration?.registration == newTip)
    #expect(saved.machineCamera?.registration == newMap)
    #expect(saved.machineArtifacts?.coordinateRevision == newMap.coordinateRevision)
    #expect(saved.stageFour?.recordID == f.accepted.borderRecord.recordID)
    guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
      Issue.record("Position recovery lost prior drawing evidence"); await app.shutdown(); return
    }
    #expect(archive.records == [f.accepted.borderRecord])
    await app.shutdown()
  }

  @Test("a uniquely acquired matching cap verifies position while confidence remains diagnostic",
    arguments: [PhysicalPoseCaptureMode.valid, .lowConfidence])
  func matchingCapRetainsCalibrationAndCurrentSessionUse(_ mode: PhysicalPoseCaptureMode) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await f.camera.configurePoseCapture(mode: mode)
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    try await reestablishPhysicalPositionForTest(app)
    #expect(app.tipCameraRegistration?.revalidationEvidence?.capEstimate.confidence
      == (mode == .lowConfidence ? 0.25 : 1))
    #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.interactiveLearningIsComplete)
    let verified = try #require(app.tipCameraRegistration)
    let captures = await f.camera.poseCaptureCount
    await submitControllerSession(app, .requestPassiveProbe)
    #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.tipCameraRegistration == verified)
    #expect(await f.camera.poseCaptureCount == captures)
    await app.recordNewPaperSheetOnCurrentPlane()
    #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.tipCameraRegistration == verified)
    #expect(await f.camera.poseCaptureCount == captures)
    await app.shutdown()
  }

  @Test("failed exact cap evidence leaves all retained authority unchanged",
    arguments: [PhysicalPoseCaptureMode.unavailable, .ambiguous, .stale, .wrongSource, .wrongConfiguration])
  func rejectedObservationCannotPartiallyPublish(_ mode: PhysicalPoseCaptureMode) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await f.camera.configurePoseCapture(mode: mode)
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let before = PhysicalPoseAuthoritySnapshot(app)
    let request = try physicalPositionRequest(app)
    _ = await app.submitPlotterUIRequest(request)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(PhysicalPoseAuthoritySnapshot(app) == before)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    #expect(await f.machine.requestedDrawingStrokes.isEmpty)
    guard case .loaded(let saved) = f.stores.checkpointStore.load() else {
      Issue.record("Rejected evidence lost accepted package"); await app.shutdown(); return
    }
    #expect(saved == f.accepted.checkpoint)
    await app.shutdown()
  }

  @Test("known manual Jog and Pen busy snapshots preserve verified pose and completed Learning")
  func knownManualBusyOperationsPreservePhysicalPosition() async throws {
    let penGate = PenRequestGate()
    let f = try await DrawingWorkbenchApplicationFixture.make(holdsManualJog: true, penRequestGate: penGate)
    defer { f.stores.remove() }
    let app = f.application
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let accepted = PhysicalPoseAuthoritySnapshot(app)
    let captures = await f.camera.poseCaptureCount
    let jog = Task { await app.submitTestManualJog(.xNegative) }
    do {
      try await waitUntilAsync { await f.machine.relativeJogIsAwaitingSettlement }
      _ = await app.refreshControllerSessionSnapshot()
      #expect(app.machineSnapshot?.machine.connection == .moving)
      #expect(app.machineSnapshot?.machine.operationInFlight == true)
      #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      await f.machine.settleRelativeJogNaturally()
      await jog.value
      #expect(app.manualMotionEpisodeSnapshot?.activeOperation == nil)
      _ = await app.refreshControllerSessionSnapshot()
      #expect(app.machineSnapshot?.machine.connection == .connected)
      #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      #expect(app.interactiveLearningIsComplete)
      #expect(PhysicalPoseAuthoritySnapshot(app) == accepted)
      #expect(await f.camera.poseCaptureCount == captures)

      let pen = Task { await app.submitTestManualPen(.lower) }
      do {
        try await waitUntilAsync { await penGate.isHeld }
        _ = await app.refreshControllerSessionSnapshot()
        #expect(app.machineSnapshot?.machine.connection == .actuatingPen)
        #expect(app.machineSnapshot?.currentOperation == .penActuation(.lower))
        #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
        await penGate.releaseFirstRequest()
        await pen.value
        #expect(app.manualMotionEpisodeSnapshot?.activeOperation == nil)
        _ = await app.refreshControllerSessionSnapshot()
        #expect(app.machineSnapshot?.machine.connection == .connected)
        #expect(app.machineSnapshot?.machine.penState == .down)
        #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
        #expect(app.interactiveLearningIsComplete)
        #expect(PhysicalPoseAuthoritySnapshot(app) == accepted)
        #expect(await f.camera.poseCaptureCount == captures)
      } catch {
        await penGate.releaseFirstRequest()
        await pen.value
        throw error
      }
      await app.shutdown()
    } catch {
      _ = await f.machine.cancel(intent: .shutdown)
      await penGate.releaseFirstRequest()
      await jog.value
      await app.shutdown()
      throw error
    }
  }

  @Test("transport loss from an actual moving operation invalidates pose despite unchanged MPos")
  func transportLossDuringManualMotionRequiresRecovery() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(holdsManualJog: true)
    defer { f.stores.remove() }
    let app = f.application
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let originalPosition = (await f.machine.snapshot()).machine.position
    let captures = await f.camera.poseCaptureCount
    let jog = Task { await app.submitTestManualJog(.xNegative) }
    do {
      try await waitUntilAsync { await f.machine.relativeJogIsAwaitingSettlement }
      _ = await app.refreshControllerSessionSnapshot()
      #expect(app.machineSnapshot?.machine.connection == .moving)
      #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      // A lower transport event, not an application pose assignment. The
      // operation remains held while the existing snapshot refresh observes loss.
      await f.machine.reportTransportAvailability(false)
      _ = await app.refreshControllerSessionSnapshot()
      #expect(app.machineSnapshot?.machine.connection == .disconnected)
      #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      _ = await f.machine.cancel(intent: .operatorStop)
      await jog.value
      #expect(app.manualMotionEpisodeSnapshot?.activeOperation == nil)
      await f.machine.reportTransportAvailability(true)
      await app.establishMachineSession(f.machine.descriptor)
      await submitControllerSession(app, .requestPassiveProbe)
      #expect((await f.machine.snapshot()).machine.position == originalPosition)
      #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      #expect(app.interactiveLearningIsComplete)
      #expect(await f.camera.poseCaptureCount == captures)
      await app.shutdown()
    } catch {
      _ = await f.machine.cancel(intent: .shutdown)
      await jog.value
      await app.shutdown()
      throw error
    }
  }

  @Test("controller disconnect loses physical continuity even when MPos is unchanged")
  func disconnectRequiresFreshPhysicalPosition() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    let before = try #require((await f.machine.snapshot()).machine.position)
    let tip = try #require(app.tipCameraRegistration)
    await submitControllerSession(app, .toggleConnection)
    await app.establishMachineSession(f.machine.descriptor)
    await submitControllerSession(app, .requestPassiveProbe)
    #expect((await f.machine.snapshot()).machine.position == before)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(app.tipCameraRegistration == tip)
    #expect(app.interactiveLearningIsComplete)
    #expect(await f.machine.requestedFeeds.isEmpty)
    await app.shutdown()
  }

  @Test("Stop during held camera recovery publishes no pose or calibration authority")
  func stopHeldCameraRecoveryIsAtomic() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let before = PhysicalPoseAuthoritySnapshot(app)
    let gate = TestInspectionSuspension()
    await gate.arm()
    await f.camera.configurePoseCapture(gate: gate)
    let request = try physicalPositionRequest(app)
    let recovery = Task { await app.submitPlotterUIRequest(request) }
    do {
      try await waitUntilAsync { await gate.isWaiting }
      let projection = app.testPlotterUIProjection(
        selectedItemID: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks), includesLearningPath: true)
      let stop = try #require(WorkbenchStopPresentation.actions(in: projection.semantic).first)
      let stopRequest = try #require(projection.semantic.request(for: stop.id))
      let stopping = Task { await app.submitPlotterUIRequest(stopRequest) }
      // The stop joins the existing capture owner. Release only after the
      // cancellation request has reached that owner, without touching machine.
      try await waitUntil { app.tipCalibrationRuntime.snapshot().admissionClosed }
      await gate.release()
      _ = await stopping.value
      _ = await recovery.value
      #expect(PhysicalPoseAuthoritySnapshot(app) == before)
      #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      #expect(await f.machine.requestedFeeds.isEmpty)
      #expect(await f.machine.requestedPenCommands.isEmpty)
      #expect(await f.machine.requestedDrawingStrokes.isEmpty)
      guard case .loaded(let saved) = f.stores.checkpointStore.load() else {
        Issue.record("Cancelled capture lost accepted package"); await app.shutdown(); return
      }
      #expect(saved == f.accepted.checkpoint)
      await app.shutdown()
    } catch {
      await gate.release()
      await app.shutdown()
      _ = await recovery.value
      throw error
    }
  }

  @Test("held position recovery excludes source controller and paper mutations")
  func recoveryReservationProtectsDependencies() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let before = PhysicalPoseAuthoritySnapshot(app)
    let gate = TestInspectionSuspension()
    await gate.arm()
    await f.camera.configurePoseCapture(gate: gate)
    let request = try physicalPositionRequest(app)
    let recovery = Task { await app.submitPlotterUIRequest(request) }
    do {
      try await waitUntilAsync { await gate.isWaiting }
      let source = app.observationConfigurationProjection.request(.selectSource(.simulated, cameraID: nil))
      #expect(await app.submitObservationConfiguration(source) != nil)
      let controller = app.controllerSessionProjection.request(.toggleConnection)
      if case .refused = await app.submitControllerSessionRequest(controller) {} else {
        Issue.record("Controller mutation bypassed camera-position recovery owner")
      }
      await app.recordNewPaperSheetOnCurrentPlane()
      #expect(PhysicalPoseAuthoritySnapshot(app) == before)
      #expect(app.frameMode == .live)
      await gate.release()
      _ = await recovery.value
      #expect(!app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      #expect(app.currentPaperRevisionContext == before.paper)
      #expect(await f.machine.requestedFeeds.isEmpty)
      await app.shutdown()
    } catch {
      await gate.release()
      await app.shutdown()
      _ = await recovery.value
      throw error
    }
  }

  @Test("controller movement during exact cap capture discards the mixed-time correspondence")
  func controllerPositionChangeDuringCaptureIsRejected() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let before = PhysicalPoseAuthoritySnapshot(app)
    let gate = TestInspectionSuspension()
    await gate.arm()
    await f.camera.configurePoseCapture(gate: gate)
    let request = try physicalPositionRequest(app)
    let recovery = Task { await app.submitPlotterUIRequest(request) }
    do {
      try await waitUntilAsync { await gate.isWaiting }
      try await f.machine.setPosition(x: 20, y: 0)
      await gate.release()
      _ = await recovery.value
      #expect(PhysicalPoseAuthoritySnapshot(app) == before)
      #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
      #expect(await f.machine.requestedFeeds.isEmpty)
      await app.shutdown()
    } catch {
      await gate.release()
      await app.shutdown()
      _ = await recovery.value
      throw error
    }
  }

  @Test("successive translated recoveries preserve possible ink for both border choices but allow a moved target",
    arguments: [false, true])
  func translatedPlanCannotReplayPossibleInk(_ border: Bool) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    try await selectPhysicalPosePortrait(f)
    // Leave real placement room, so the final moved-target assertion cannot
    // pass/fail merely because Fit filled the entire drawable region.
    let drawingScale = floor(app.drawingDraftSnapshot.uniformScale * 80) / 100
    try await f.submit(.setUniformScale(drawingScale))
    if border { try await f.submit(.setDrawBorder(true)) }
    try await f.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    let initialPlan = try #require(app.drawingDraftSnapshot.plan)
    await f.planGate.release(.possibleInk)
    let start = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    #expect(await app.submitPlotterUIRequest(start) == .accepted(requestID: start.id))
    let record = try #require(app.drawingRunSnapshot?.terminal?.record)
    #expect(record.executionFrontiers.commandedStrokeCount > 0)
    #expect(record.executionFrontiers.inkVerifiedStrokeCount == 0)
    let paper = app.currentPaperRevisionContext
    let previousPlacement = app.drawingDraftSnapshot.placementID
    let newRun = try #require(app.testPlotterUIProjection().semantic.request(
      matching: .drawingRun(.beginNewRun(record.runID))))
    #expect(await app.submitPlotterUIRequest(newRun) == .accepted(requestID: newRun.id))
    // The Run handoff owns Draft.beginNewPlan; it is not a second UI action.
    #expect(app.drawingRunSnapshot?.terminal == nil)
    #expect(app.drawingDraftSnapshot.placementID != previousPlacement)
    #expect(!app.drawingDraftSnapshot.drawBorder)
    #expect(app.testPlotterUIProjection().semantic.request(
      matching: .drawingDraft(.fitInDrawableRegion)) != nil)
    if border { try await f.submit(.setDrawBorder(true)) }
    var previousHash = initialPlan.contentHash
    for inwardFraction in [0.5, 0.75] {
      await submitControllerSession(app, .toggleConnection)
      await app.establishMachineSession(f.machine.descriptor)
      await submitControllerSession(app, .requestPassiveProbe)
      await f.machine.setPenState(.up)
      _ = await app.refreshControllerSessionSnapshot()
      let map = try #require(app.machineCameraRegistration)
      let position = try #require((await f.machine.snapshot()).machine.position)
      let bounds = try #require(app.currentDrawableMachineRegion).effectiveBounds
      // Choose an interior point separated from the actual settled carriage.
      // The accepted eight-pixel residual policy must choose a real rebase,
      // rather than a valid matching-pose confirmation with no revision change.
      let interiorPoints = try [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)].map { x, y in
        try Point2<MachineSpace>(x: bounds.minX + (bounds.maxX - bounds.minX) * x,
          y: bounds.minY + (bounds.maxY - bounds.minY) * y)
      }
      let destination = try #require(interiorPoints.max {
        position.point.distance(to: $0) < position.point.distance(to: $1)
      })
      let observedMachinePoint = try Point2<MachineSpace>(
        x: position.point.x + (destination.x - position.point.x) * inwardFraction,
        y: position.point.y + (destination.y - position.point.y) * inwardFraction)
      let predictedCap = try map.fit.cameraPoint(from: position.point)
      let cap = try map.fit.cameraPoint(from: observedMachinePoint)
      let observed = try Point2<CameraPixelSpace>(x: cap.x.rounded(), y: cap.y.rounded())
      #expect(observed.distance(to: predictedCap) > 8,
        "Both observations must exceed the established rebase residual threshold")
      let formerPhysicalPoint = try map.fit.machinePoint(from: observed)
      #expect(formerPhysicalPoint.x >= bounds.minX && formerPhysicalPoint.x <= bounds.maxX)
      #expect(formerPhysicalPoint.y >= bounds.minY && formerPhysicalPoint.y <= bounds.maxY)
      let translation = try formerPhysicalPoint.vector(to: position.point)
      #expect(abs(translation.dx - translation.dx.rounded()) > 0.000_001
        || abs(translation.dy - translation.dy.rounded()) > 0.000_001,
        "Each recovery must actually exercise a noninteger machine-coordinate translation")
      await f.camera.configurePoseCapture(anchor: observed)
      try await reestablishPhysicalPositionForTest(app)
      #expect(app.currentPaperRevisionContext == paper)
      #expect(app.interactiveLearningIsComplete)
      #expect((await f.machine.snapshot()).machine.position == position)
      // Same selected program, border choice, size and relative placement on
      // the translated Boundary is the same physical drawing, even when
      // floating-point composition changes its exact coordinate content hash.
      try await f.submit(.fitInDrawableRegion)
      try await f.submit(.setUniformScale(drawingScale))
      try await f.submit(.assertPaperCoverage)
      await app.drawingDraftSynchronizationTask?.value
      let currentRun = await f.runRuntime.synchronize(environment: .live)
      try await waitUntil { app.drawingRunSnapshot?.projection == currentRun.projection }
      let translatedPlan = try #require(app.drawingDraftSnapshot.plan)
      #expect(app.drawingDraftSnapshot.drawBorder == border)
      #expect(translatedPlan.contentHash != previousHash)
      previousHash = translatedPlan.contentHash
      if case .unavailable(let refusal) = currentRun.readiness {
        #expect(refusal.reason == .planMayAlreadyContainInk,
          "Rebased physical plan must retain ink exclusion: \(refusal)")
      } else { Issue.record("Coordinate rebase admitted a possibly inked physical plan: \(currentRun.readiness)") }
      let blockedProjection = app.testPlotterUIProjection().semantic
      #expect(blockedProjection.request(matching: .drawingRun(.start)) == nil)
      let blockedStart = PlotterUIRequest(id: .init(rawValue: UUID()), uiRevision: blockedProjection.revision,
        runtimeRevisions: blockedProjection.runtimeRevisions,
        actionID: PlotterAppUIActionID.drawingRun(.start), intent: .drawingRun(.start))
      guard case .refused = await app.submitPlotterUIRequest(blockedStart) else {
        Issue.record("A current typed Start bypassed immutable possible-ink exclusion")
        await app.shutdown(); return
      }
      guard case .loaded(let checkpoint) = f.stores.checkpointStore.load() else {
        Issue.record("Repeated recovery lost its accepted package"); await app.shutdown(); return
      }
      #expect(checkpoint.stageFour?.recordID == f.accepted.borderRecord.recordID)
      try checkpoint.validate()
    }
    guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
      Issue.record("Position recovery lost drawing history"); await app.shutdown(); return
    }
    #expect(archive.records == [f.accepted.borderRecord, record])

    let center = try #require(app.drawingDraftSnapshot.machineCenter)
    let movedCenter = try Point2<MachineSpace>(x: center.x + 3.25, y: center.y)
    let tip = try #require(app.tipCameraRegistration)
    let placement = PlotterDrawingDraftCameraPlacement(
      frame: try #require(app.drawingDraftSnapshot.projection.externalFacts.displayedFrame),
      point: try tip.tipPixel(at: movedCenter))
    let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingPlacement: placement)
    let move = try #require(projection.semantic.request(matching: .drawingDraft(.placeAtCameraPoint(placement))))
    let canonicalMoveID = PlotterAppUIActionID.drawingDraft(.placeAtCameraPoint(placement))
    let identitySurvivedCompilation = move.actionID == canonicalMoveID
    #expect(identitySurvivedCompilation,
      "Placement ID changed at compiler boundary: canonical length=\(canonicalMoveID.rawValue.count), projected length=\(move.actionID.rawValue.count)")
    #expect(canonicalMoveID.rawValue.count <= PlotterUICompiler.Limits().maximumTextLength)
    let otherPlacement = PlotterDrawingDraftCameraPlacement(frame: placement.frame,
      point: try Point2(x: placement.point.x + 1, y: placement.point.y))
    let alteredMove = PlotterUIRequest(id: .init(rawValue: UUID()), uiRevision: move.uiRevision,
      runtimeRevisions: move.runtimeRevisions, actionID: move.actionID,
      intent: .drawingDraft(.placeAtCameraPoint(otherPlacement)))
    guard case .refused(let alteredRefusal) = await app.submitPlotterUIRequest(alteredMove) else {
      Issue.record("Compact placement identity admitted a different point than its exact reached intent")
      await app.shutdown(); return
    }
    #expect(alteredRefusal.reason == .mismatchedIntent)
    let moveOutcome = await app.submitPlotterUIRequest(move)
    let moveDetail: String
    if case .refused(let refusal) = moveOutcome { moveDetail = "\(refusal.reason): \(refusal.remedy)" }
    else { moveDetail = "\(moveOutcome)" }
    let moveContext = "Moved target refused: \(moveDetail); placement frame=\(placement.frame.frameID), "
      + "current frame=\(String(describing: app.drawingDraftExternalFacts.revisions.displayedFrame?.frameID))"
    try #require(moveOutcome == .accepted(requestID: move.id), "\(moveContext)")
    try await f.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    #expect(try #require(app.drawingDraftSnapshot.machineCenter).distance(to: movedCenter) < 0.000_001)
    await f.planGate.release(.possibleInk)
    let movedStart = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    #expect(await app.submitPlotterUIRequest(movedStart) == .accepted(requestID: movedStart.id))
    let movedRecord = try #require(app.drawingRunSnapshot?.terminal?.record)
    #expect(movedRecord.recordID != record.recordID)
    guard case .loaded(let finalArchive) = await f.stores.evidenceStore.load() else {
      Issue.record("Moved drawing lost prior immutable evidence"); await app.shutdown(); return
    }
    #expect(finalArchive.records == [f.accepted.borderRecord, record, movedRecord])
    await app.shutdown()
  }

  @Test("startup preserves rebased Boundary but never projects old-coordinate archive strokes through the new map")
  func rebasedSavedCandidateDoesNotMisprojectHistoricalPlans() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false)
    defer { f.stores.remove() }
    let app = f.application
    let oldRecord = f.accepted.borderRecord
    let map = try #require(app.machineCameraRegistration)
    let position = try #require((await f.machine.snapshot()).machine.position)
    let cap = try map.fit.cameraPoint(from: position.point)
    await f.camera.configurePoseCapture(anchor: try Point2(x: cap.x + 48, y: cap.y + 32))
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    try await reestablishPhysicalPositionForTest(app)
    let expectedBoundary = try #require(app.testActionSurfacePresentation.overlays.first {
      $0.provenance.kind == .acceptedBoundary
    }).geometry
    let expectedBorder = try #require(app.testActionSurfacePresentation.overlays.first {
      $0.provenance.kind == .drawingBorder
    }).geometry
    guard case .loaded(let beforeShutdown) = f.stores.checkpointStore.load() else {
      Issue.record("Rebased checkpoint unavailable before startup"); await app.shutdown(); return
    }
    #expect(beforeShutdown.tipCalibration?.registration.applicability != oldRecord.tipCalibration.applicability)
    #expect(beforeShutdown.semanticIdentity.paperInstance == oldRecord.paper.instance)
    await app.shutdown()
    // Shutdown legitimately saves a new envelope after all owners settle.
    // Compare startup with that exact durable input, while also proving the
    // accepted geometry and immutable Learning lineage survived the resave.
    guard case .loaded(let saved) = f.stores.checkpointStore.load() else {
      Issue.record("Rebased checkpoint disappeared during shutdown"); return
    }
    #expect(saved.semanticIdentity == beforeShutdown.semanticIdentity)
    #expect(saved.machineArtifacts == beforeShutdown.machineArtifacts)
    #expect(saved.machineCamera == beforeShutdown.machineCamera)
    #expect(saved.tipCalibration == beforeShutdown.tipCalibration)
    #expect(saved.stageFour == beforeShutdown.stageFour)

    let machine = f.machine
    let clock = f.clock
    let restarted = plotterApplicationRuntime(machine: machine,
      observationSessionOverride: f.camera, statePersistencePort: f.stores.persistence,
      drawingEvidencePort: f.stores.evidencePort, tipCalibrationSemanticIdentities: f.accepted.identities,
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [machine.descriptor] }, readNanoseconds: { clock.read() }),
      loadPenCapAppearanceSelection: { nil }, log: EventLog())
    await restarted.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await submitObservationConfigurationForTest(restarted, .selectSource(.live, f.camera.device.id))
    #expect(restarted.tipCameraRegistration == nil)
    #expect(restarted.learningArtifactGraph.revisions.isEmpty)
    #expect(restarted.artifactResetEpisodeSnapshot.savedLearning.candidate?.checkpoint == saved)
    let overlays = restarted.testActionSurfacePresentation.overlays
    #expect(overlays.first { $0.provenance.kind == .acceptedBoundary }?.geometry == expectedBoundary)
    #expect(overlays.first { $0.provenance.kind == .drawingBorder }?.geometry == expectedBorder)
    #expect(!overlays.contains { $0.provenance.kind == .intendedPath })
    guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
      Issue.record("Historical plan disappeared instead of being excluded from current projection")
      await restarted.shutdown(); return
    }
    #expect(archive.records == [oldRecord])

    // Archived history is independent of authoring. An ordinary fresh program
    // still obtains a preview from the rebased accepted geometry.
    try await applyCompleteSavedLearning(restarted)
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .contours, strokeStyle: restarted.drawingStrokeStyle)
    let selectProjection = restarted.plotterUIProjection(selectedItemID: restarted.testCurrentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
    let select = try #require(selectProjection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
    #expect(await restarted.submitPlotterUIRequest(select) == .accepted(requestID: select.id))
    let fit = try #require(restarted.testPlotterUIProjection().semantic.request(matching: .drawingDraft(.fitInDrawableRegion)))
    #expect(await restarted.submitPlotterUIRequest(fit) == .accepted(requestID: fit.id))
    #expect(restarted.drawingDraftSnapshot.preview != nil)
    #expect(restarted.drawingDraftSnapshot.plan?.provenance.modelRevisionID.rawValue
      == saved.tipCalibration?.registration.acceptedRevisionID.rawValue)
    await restarted.shutdown()
  }

  @Test("failed durable rebase publication cannot make the live pose or geometry current")
  func failedPersistenceIsAtomic() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make(verifyPhysicalPose: false,
      checkpointSaveFails: true)
    defer { f.stores.remove() }
    let app = f.application
    let map = try #require(app.machineCameraRegistration)
    let position = try #require((await f.machine.snapshot()).machine.position)
    let cap = try map.fit.cameraPoint(from: position.point)
    await f.camera.configurePoseCapture(anchor: try Point2(x: cap.x + 48, y: cap.y + 32))
    await f.machine.setPenState(.up)
    _ = await app.refreshControllerSessionSnapshot()
    let before = PhysicalPoseAuthoritySnapshot(app)
    let request = try physicalPositionRequest(app)
    _ = await app.submitPlotterUIRequest(request)
    #expect(PhysicalPoseAuthoritySnapshot(app) == before)
    #expect(app.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(await f.machine.requestedFeeds.isEmpty)
    #expect(await f.machine.requestedPenCommands.isEmpty)
    guard case .loaded(let saved) = f.stores.checkpointStore.load() else {
      Issue.record("Failed save lost preceding package"); await app.shutdown(); return
    }
    #expect(saved == f.accepted.checkpoint)
    await app.shutdown()
  }
}

@MainActor
func physicalPositionRequest(_ app: PlotterApplicationRuntime) throws -> PlotterUIRequest {
  let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
  let projection = app.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true)
  let action = try #require(projection.semantic.actions.first {
    if case .learningAction(let request) = $0.intent {
      return request.action == .tipCalibration(.revalidateCheckpoint)
    }
    return false
  }, "The existing tip owner must expose physical-position recovery with Learning retained")
  return try #require(projection.semantic.request(for: action.id), "\(String(describing: action))")
}

@MainActor
func reestablishPhysicalPositionForTest(_ app: PlotterApplicationRuntime) async throws {
  let request = try physicalPositionRequest(app)
  let outcome = await app.submitPlotterUIRequest(request)
  try #require(outcome == .accepted(requestID: request.id),
    "\(app.explorationError ?? String(describing: outcome))")
  try #require(!app.controllerPoseApplicability.requiresPhysicalPositionForTest,
    "\(app.explorationError ?? "Position recovery did not establish current authority")")
}

@MainActor
private func selectPhysicalPosePortrait(_ f: DrawingWorkbenchApplicationFixture) async throws {
  let app = f.application
  let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
    style: .contours, strokeStyle: app.drawingStrokeStyle)
  let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
    manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
  let request = try #require(projection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
  #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
  try await f.submit(.fitInDrawableRegion)
}

extension ControllerPoseApplicability {
  var requiresPhysicalPositionForTest: Bool {
    if case .requiresVisualRevalidation = self { return true }
    return false
  }
}

private struct PhysicalPoseAuthoritySnapshot: Equatable {
  let tip: TipCameraRegistration?
  let map: MachineCameraRegistration?
  let boundary: [BoundaryDirection: BoundarySideAggregate]
  let graph: Set<LearningArtifactRevision>
  let paper: PaperRevisionContext
  @MainActor init(_ app: PlotterApplicationRuntime) {
    tip = app.tipCameraRegistration
    map = app.machineCameraRegistration
    boundary = app.testAcceptedBoundaryAggregates
    graph = Set(app.learningArtifactGraph.revisions)
    paper = app.currentPaperRevisionContext
  }
}

enum PhysicalPoseFixtureError: Error { case persistence }
enum PhysicalPoseCaptureMode: Hashable, Sendable { case valid, lowConfidence, unavailable, ambiguous, stale, wrongSource, wrongConfiguration }

/// Synthetic lower vision evidence. This exercises production frame, source,
/// controller, transaction and rebase owners; it does not claim detector or
/// physical-camera acceptance.
func physicalPoseInspection(frame original: DisplayedFrame, anchor: Point2<CameraPixelSpace>,
  mode: PhysicalPoseCaptureMode, staleBoundary: UInt64) throws -> StableWorkflowCapInspection {
  let old = original.frame
  let frame = DisplayedFrame(source: mode == .wrongSource
    ? .live(CameraDeviceID(rawValue: "wrong-physical-position-camera")) : original.source,
    frame: try StampedFrame(id: old.id, sequence: old.sequence,
      captureNanoseconds: mode == .stale ? staleBoundary : old.captureNanoseconds,
      cameraConfigurationID: mode == .wrongConfiguration ? CameraConfigurationID() : old.cameraConfigurationID,
      width: old.width, height: old.height, rowBytes: old.rowBytes,
      pixelFormat: old.pixelFormat, bytes: old.bytes))
  let box = PixelRect(x: Int(anchor.x.rounded()) - 4, y: Int(anchor.y.rounded()) - 8,
    width: 8, height: 8)
  let cap = PenCapMeasurement(pixelCount: 64, boundingBox: box,
    centroid: try Point2(x: Double(box.x) + 4, y: Double(box.y) + 4),
    confidence: mode == .lowConfidence ? 0.25 : 1)
  let measurement = PlotterSceneMeasurement(frameID: frame.frame.id,
    frameSHA256: frame.frame.contentSHA256, cameraConfigurationID: frame.frame.cameraConfigurationID,
    penCap: .found(cap, diagnostics: PenCapDiagnostics(inspectedPixelCount: old.width * old.height,
      thresholdPixelCount: 64, componentCount: 1, candidates: [])),
    armatureEnvelope: .notRequested, overlays: [], algorithmRevision: "synthetic-physical-position-evidence-v1",
    diagnosticSHA256: frame.frame.contentSHA256,
    computation: SceneVisionComputationDiagnostics(requestedFeatures: [.penCap], expandedFeatures: [.penCap],
      executionCounts: [:], inspectedPixelCounts: [:]))
  return StableWorkflowCapInspection(inspection: LiveSceneInspection(displayedFrame: frame,
    measurement: measurement), cap: cap)
}
