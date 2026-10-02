import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing
import PlotterUI
@testable import PlotterApp

@Suite("Complete saved Learning restoration", .serialized)
@MainActor
struct SavedLearningCompletionTests {
  @Test("paper replacement preserves unapplied and declined Saved Learning without activating it",
    arguments: [false, true], [false, true])
  func paperReplacementBeforeApplyingSavedLearning(declined: Bool, changedPlane: Bool) async throws {
    let fixture = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(fixture)
    let machine = try LowerMachineSessionFixture(log: EventLog())
    let app = plotterApplicationRuntime(machine: machine,
      statePersistencePort: stores.persistence, drawingEvidencePort: stores.evidencePort,
      tipCalibrationSemanticIdentities: fixture.identities, log: EventLog())
    if declined {
      await app.performTestExerciseAction(.startNewLearning, for: app.testCurrentLearningPathItemID)
    }
    let before = app.currentPaperRevisionContext
    #expect(app.learningArtifactGraph.revisions.isEmpty)
    if changedPlane { await app.recordPaperContactPlaneChanged() }
    else { await app.recordNewPaperSheetOnCurrentPlane() }
    #expect(app.currentPaperRevisionContext.instance != before.instance)
    guard case .loaded(let saved) = stores.checkpointStore.load() else {
      Issue.record("Paper replacement erased inactive Saved Learning")
      await app.shutdown(); return
    }
    #expect(saved.semanticIdentity.paperInstance == app.currentPaperRevisionContext.instance)
    #expect(saved.semanticIdentity.paperContactPlane == app.currentPaperRevisionContext.contactPlane)
    #expect(saved.penInteraction == fixture.checkpoint.penInteraction)
    #expect(saved.machineArtifacts == fixture.checkpoint.machineArtifacts)
    #expect(saved.machineCamera == fixture.checkpoint.machineCamera)
    #expect(saved.penCapAppearance == fixture.checkpoint.penCapAppearance)
    #expect(saved.referenceFrame == fixture.checkpoint.referenceFrame)
    #expect(saved.tipCalibration == (changedPlane ? nil : fixture.checkpoint.tipCalibration))
    #expect(saved.stageFour == (changedPlane ? nil : fixture.checkpoint.stageFour))
    #expect(app.learningArtifactGraph.revisions.isEmpty)
    #expect(app.machineCameraRegistration == nil)
    #expect(app.tipCameraRegistration == nil)
    #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint == nil)
    if declined {
      guard case .retainedForLater(let retained) = app.artifactResetEpisodeSnapshot.savedLearning else {
        Issue.record("Paper replacement activated declined Saved Learning")
        await app.shutdown(); return
      }
      #expect(retained == saved)
    } else {
      #expect(app.artifactResetEpisodeSnapshot.savedLearning.candidate?.checkpoint == saved)
    }
    #expect(await machine.requestedPenCommands.isEmpty)
    #expect(await machine.requestedFeeds.isEmpty)
    await app.shutdown()
  }

  @Test("production Apply Saved restores every accepted milestone and Border completion with Unknown or Down pen",
    arguments: [PenState.unknown, .down])
  func completeSavedPackageDoesNotReplayLearning(_ penState: PenState) async throws {
    // Synthetic accepted artifacts are generated separately; this workspace
    // only exercises ordinary persisted startup and the projected Apply action.
    let fixture = try await CompleteAcceptedLearningFixture.make()
    let checkpoint = fixture.checkpoint
    let record = fixture.borderRecord
    let tip = fixture.registration
    let expectedGraph = try checkpoint.restoredLearningGraph()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(fixture)
    let checkpointStore = stores.checkpointStore
    let evidenceStore = stores.evidenceStore

    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    await machine.setPenState(penState)
    let restored = plotterApplicationRuntime(machine: machine, statePersistencePort: stores.persistence,
      drawingEvidencePort: stores.evidencePort,
      tipCalibrationSemanticIdentities: fixture.identities,
      loadPenCapAppearanceSelection: { nil }, log: log)
    // Startup loads the existing archive even before a fresh camera is chosen.
    // No new optical context or pen pose is fabricated during restoration.
    await restored.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await restored.establishMachineSession(machine.descriptor)
    await submitControllerSession(restored, .requestPassiveProbe)
    let beforeApply = await log.values
    try await applyCompleteSavedLearning(restored)
    // Graph enumeration is dictionary order; compare every complete typed
    // revision and its current-kind lookup, including dependency identities.
    #expect(restored.learningArtifactGraph.revisions.count == expectedGraph.revisions.count)
    #expect(Set(restored.learningArtifactGraph.revisions) == Set(expectedGraph.revisions))
    for revision in expectedGraph.revisions {
      #expect(restored.learningArtifactGraph.revision(id: revision.id) == revision)
      #expect(restored.learningArtifactGraph.currentRevision(for: revision.kind)
        == expectedGraph.currentRevision(for: revision.kind))
    }
    #expect(restored.penInteractionCompleted)
    #expect(restored.testAcceptedBoundaryAggregates.count == 4)
    #expect(restored.testEstimatedMachineCenter == fixture.expectedCenter)
    #expect(restored.machineCameraRegistration == checkpoint.machineCamera?.registration)
    #expect(restored.tipCameraRegistration == tip)
    #expect(try restored.penCapAppearanceSelection?.acceptedCheckpoint() == checkpoint.penCapAppearance)
    #expect(restored.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.checkpointID == checkpoint.checkpointID)
    #expect(restored.borderValidationSnapshot.assessment == .predictionObserved)
    #expect(restored.interactiveLearningIsComplete)
    #expect(restored.controllerPoseApplicability.requiresPhysicalPositionForTest)
    #expect(restored.currentExerciseActionStripPresentation == nil)
    #expect(restored.learningPathItemPresentations.allSatisfy { $0.status == .complete })
    #expect(restored.activeExerciseAttemptID == nil)
    #expect(restored.testActionSurfacePresentation.pointSelectionRequest == nil)
    #expect(await log.values == beforeApply)
    #expect((await machine.snapshot()).machine.penState == penState)
    guard case .loaded(let savedAgain) = checkpointStore.load() else {
      Issue.record("The accepted package was not retained after application")
      await restored.shutdown()
      return
    }
    #expect(savedAgain.checkpointID == checkpoint.checkpointID)
    guard case .loaded(let archive) = await evidenceStore.load() else {
      Issue.record("The accepted Border archive was not retained")
      await restored.shutdown()
      return
    }
    #expect(archive.records == [record])
    await restored.shutdown()
  }
}

extension SavedLearningCompletionTests {
  @Test("two ordinary drawings retain Learning and exact coverage across replacement paper", arguments: [false, true])
  func consecutiveDrawingsAcrossReplacementSheet(_ border: Bool) async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    let originalPaper = app.currentPaperRevisionContext
    let originalRegistration = try #require(app.tipCameraRegistration)
    let originalBoundary = app.testAcceptedBoundaryAggregates
    let originalOutlines = app.testActionSurfacePresentation.overlays.filter {
      [.acceptedBoundary, .drawingRegion].contains($0.provenance.kind)
    }
    #expect(originalOutlines.count == 2)
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .contours, strokeStyle: app.drawingStrokeStyle)
    var records: [DrawingRunEvidenceRecord] = []
    for index in 0..<2 {
      #expect(app.drawingDraftSnapshot.drawBorder == (index == 1 && border))
      let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
        manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
      let select = try #require(projection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
      #expect(await app.submitPlotterUIRequest(select) == .accepted(requestID: select.id))
      try await f.submit(.fitInDrawableRegion)
      if border != app.drawingDraftSnapshot.drawBorder { try await f.submit(.setDrawBorder(border)) }
      let latest = try #require(await f.camera.snapshot().latestFrame)
      let hashMetrics = FrameContentHashMetrics()
      let captureTime = max(latest.frame.captureNanoseconds, f.clock.read()) + 100
      f.clock.set(captureTime)
      let exact = DisplayedFrame(source: latest.source, frame: try StampedFrame(id: FrameID(),
        sequence: latest.frame.sequence + 1, captureNanoseconds: captureTime,
        cameraConfigurationID: latest.frame.cameraConfigurationID, width: latest.frame.width,
        height: latest.frame.height, rowBytes: latest.frame.rowBytes, pixelFormat: latest.frame.pixelFormat,
        bytes: latest.frame.bytes, eagerlyMaterializeContentHash: false, contentHashMetrics: hashMetrics))
      f.camera.previewFrames.inject(exact)
      try await waitForExecutorTurns(conditionDescription: "replacement sheet exact camera frame") {
        app.actionSurfacePreview.displayedFrame?.frame.id == exact.frame.id
      }
      #expect(exact.frame.materializedContentSHA256 == nil)
      #expect(hashMetrics.snapshot.totalComputationCount == 0)
      try await f.submit(.assertPaperCoverage)
      #expect(hashMetrics.snapshot.exactEvidenceComputationCount == 1)
      #expect(app.drawingDraftSnapshot.paperCoverageObservation?.frame.frameID == exact.frame.id)
      #expect(app.drawingDraftSnapshot.paperCoverageObservation?.paper.instance == app.currentPaperRevisionContext.instance)
      #expect(app.paperReplacementStatus == nil)
      do {
        try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
      } catch {
        let detail = "Repeated sheet drawing iteration=\(index) border=\(border) "
          + "readiness=\(String(describing: app.drawingRunSnapshot?.readiness)) "
          + "phase=\(String(describing: app.drawingRunSnapshot?.phase)) "
          + "noRedraw=\(String(describing: app.drawingRunSnapshot?.noRedraw)) "
          + "draftRevision=\(app.drawingDraftSnapshot.projection.draftRevision) "
          + "plan=\(String(describing: app.drawingDraftSnapshot.plan?.revisionID)) "
          + "runPlan=\(String(describing: app.drawingRunSnapshot?.projection.planIdentity?.planRevisionID)) "
          + "coverageCurrent=\(app.drawingDraftSnapshot.paperCoverageIsCurrent) "
          + "coverageFrame=\(String(describing: app.drawingDraftSnapshot.paperCoverageObservation?.frame)) "
          + "displayedFrame=\(String(describing: app.displayedFrame?.frame.id)) "
          + "now=\(f.clock.read()) explorationError=\(String(describing: app.explorationError))"
        Issue.record("\(detail)")
        await app.shutdown()
        throw error
      }
      let start = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
      let run = Task { await app.submitPlotterUIRequest(start) }
      if index == 0 {
        try await waitUntilAsync { await f.planGate.request != nil }
        let activePaper = app.currentPaperRevisionContext
        await app.recordNewPaperSheetOnCurrentPlane()
        #expect(app.currentPaperRevisionContext == activePaper)
        #expect(app.explorationError != nil)
        await f.planGate.release(.completed)
      }
      #expect(await run.value == .accepted(requestID: start.id))
      let terminal = try #require(app.drawingRunSnapshot?.terminal)
      // Full-Boundary Fit reaches beyond this saved tip calibration's measured
      // applicability. Completed controller commands cannot supply ink proof.
      #expect(terminal.disposition == .nonAttributable)
      #expect(terminal.record.evidenceDisposition == .nonAttributable)
      #expect(terminal.record.observation == .notAttempted(.projectionOutsideTipApplicability))
      #expect(terminal.record.executionDisposition == .completed)
      #expect(app.drawingRunSnapshot?.physicalEvidenceClaimed == false)
      #expect(terminal.record.role == .ordinaryDrawing)
      let executedPlan = try #require(terminal.record.plan.executionPlan)
      #expect(executedPlan.strokes.count == program.strokes.count + (border ? 1 : 0))
      let frontiers = terminal.record.executionFrontiers
      #expect(frontiers.plannedStrokeCount == UInt32(executedPlan.strokes.count))
      #expect(frontiers.commandedStrokeCount == frontiers.plannedStrokeCount)
      #expect(frontiers.controllerCompletedStrokeCount == frontiers.plannedStrokeCount)
      #expect(frontiers.inkVerifiedStrokeCount == 0)
      #expect(terminal.record.program.source?.sourceIdentifier.contains("|draw-border-v1|") == border)
      if border {
        let extent = program.fieldExtent
        let fieldCorners: [Point2<FieldSpace>] = [
          try Point2(x: 0, y: 0), try Point2(x: extent.width, y: 0),
          try Point2(x: extent.width, y: extent.height), try Point2(x: 0, y: extent.height),
          try Point2(x: 0, y: 0),
        ]
        let expected = try fieldCorners.map { try executedPlan.placement.applying(to: $0) }
        let path = try #require(executedPlan.strokes.first).path.points
        #expect(path.count == expected.count)
        #expect(path.first == path.last)
        for (actual, corner) in zip(path, expected) {
          #expect(abs(actual.x - corner.x) <= DrawingRegionContainmentPolicy.numericalEpsilonMM)
          #expect(abs(actual.y - corner.y) <= DrawingRegionContainmentPolicy.numericalEpsilonMM)
        }
        #expect(executedPlan.strokes.dropFirst().map(\.logicalStrokeID) == program.strokes.map(\.id))
      }
      records.append(terminal.record)
      if index == 0 {
        if !border {
          // A new draft alone never authorizes retracing ink on this sheet.
          // The bordered variant below exercises direct terminal -> New Sheet.
          let newDrawing = try #require(app.testPlotterUIProjection().semantic.request(
            matching: .drawingRun(.beginNewRun(terminal.runID))))
          #expect(await app.submitPlotterUIRequest(newDrawing) == .accepted(requestID: newDrawing.id))
          guard case .unavailable(let issue) = app.drawingRunSnapshot?.readiness else {
            Issue.record("The completed plan must remain blocked on its original sheet")
            await app.shutdown()
            return
          }
          #expect(issue.reason == .planMayAlreadyContainInk)
          #expect(app.currentPaperRevisionContext == originalPaper)
          #expect(app.drawingDraftSnapshot.plan?.contentHash == terminal.record.plan.contentHash)
        }
        let retainedProgram = app.drawingDraftSnapshot.program
        let retainedScale = app.drawingDraftSnapshot.uniformScale
        let retainedRotation = app.drawingDraftSnapshot.rotationDegrees
        let retainedCenter = app.drawingDraftSnapshot.centerCameraPixel
        let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .paper(.newSheetOnCurrentPlane)))
        #expect(await app.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
        #expect(app.drawingDraftSnapshot.program == retainedProgram)
        #expect(app.drawingDraftSnapshot.uniformScale == retainedScale)
        #expect(app.drawingDraftSnapshot.rotationDegrees == retainedRotation)
        #expect(app.drawingDraftSnapshot.centerCameraPixel == retainedCenter)
        #expect(app.drawingDraftSnapshot.drawBorder == border)
        #expect(app.currentPaperRevisionContext.instance != originalPaper.instance)
        #expect(app.currentPaperRevisionContext.contactPlane == originalPaper.contactPlane)
        #expect(app.tipCameraRegistration == originalRegistration)
        #expect(app.testAcceptedBoundaryAggregates == originalBoundary)
        #expect(app.penInteractionCompleted && app.interactiveLearningIsComplete)
        #expect(app.borderValidationSnapshot.assessment != nil)
        #expect(app.currentDrawableMachineRegion != nil)
        let outlines = app.testActionSurfacePresentation.overlays.filter {
          [.acceptedBoundary, .drawingRegion].contains($0.provenance.kind)
        }
        #expect(outlines.count == 2)
        #expect(outlines.map(\.geometry) == originalOutlines.map(\.geometry))
        #expect(outlines.allSatisfy { $0.matches(app.displayedFrame!) })
        #expect(app.drawingRunSnapshot?.terminal == nil)
        #expect(!app.drawingDraftSnapshot.paperCoverageIsCurrent)
        #expect(app.explorationError == nil)
        #expect(app.paperReplacementStatus?.contains("Calibration retained") == true)
      }
    }
    #expect(records[0].paper.instance != records[1].paper.instance)
    #expect(records[0].runID != records[1].runID)
    guard case .loaded(let archive) = await f.stores.evidenceStore.load() else {
      Issue.record("Repeated drawings must remain durable")
      await app.shutdown(); return
    }
    #expect(archive.records.contains(f.accepted.borderRecord))
    #expect(records.allSatisfy(archive.records.contains))
    await app.shutdown()
  }

  @Test("compatible already-applied Saved Learning recovers active calibration loss on a replacement sheet")
  func recoverAppliedCalibrationOnNewSheet() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    await app.recordNewPaperSheetOnCurrentPlane()
    let currentPaper = app.currentPaperRevisionContext
    let checkpoint = try #require(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint)
    #expect(checkpoint.semanticIdentity.paperInstance == currentPaper.instance)
    // Reproduce the old runtime failure directly: immutable accepted data and
    // the current sheet survive, but active tip registration is lost.
    app.tipCalibrationRuntime.resetForPaper(currentPaper.instance)
    _ = app.borderValidationRuntime.apply(.rewind(.chooseDrawingBorderPlan))
    #expect(app.tipCameraRegistration == nil)
    #expect(!app.interactiveLearningIsComplete)
    try await applyCompleteSavedLearning(app)
    #expect(app.tipCameraRegistration == checkpoint.tipCalibration?.registration)
    #expect(app.currentPaperRevisionContext == currentPaper)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.currentDrawableMachineRegion != nil)
    #expect(app.explorationError == nil)
    await app.shutdown()
  }

  @Test("changed contact plane invalidates only tip-dependent Learning and cannot recover the old package")
  func changedPlanePreservesUnrelatedLearning() async throws {
    let f = try await DrawingWorkbenchApplicationFixture.make()
    defer { f.stores.remove() }
    let app = f.application
    let machineCamera = app.machineCameraRegistration
    let boundary = app.testAcceptedBoundaryAggregates
    let before = app.currentPaperRevisionContext
    await app.recordPaperContactPlaneChanged()
    #expect(app.currentPaperRevisionContext.contactPlane != before.contactPlane)
    #expect(app.tipCameraRegistration == nil)
    #expect(app.tipCalibrationRuntime.recoverableCheckpoint == nil)
    #expect(!app.interactiveLearningIsComplete)
    #expect(app.penInteractionCompleted)
    #expect(app.machineCameraRegistration == machineCamera)
    #expect(app.testAcceptedBoundaryAggregates == boundary)
    #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.tipCalibration == nil)
    #expect(app.artifactResetEpisodeSnapshot.savedLearning.appliedCheckpoint?.stageFour == nil)
    #expect(app.testPlotterUIProjection(includesLearningPath: true).semantic.actions.allSatisfy {
      guard case .learningAction(let request) = $0.intent else { return true }
      return request.action != .applySavedLearning
    })
    #expect(app.paperReplacementStatus?.contains("Repeat pen-tip calibration") == true)
    await app.shutdown()
  }

  @Test("typed Paper failures expose the transaction remedy, roll back authority, and clear on retry",
    arguments: PaperReplacementFailurePoint.allCases, [false, true])
  func paperCoverageFailureRollsBackPackage(
    _ failurePoint: PaperReplacementFailurePoint, _ contactPlaneChanged: Bool
  ) async throws {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(accepted)
    let paperPersistence = ReplacementPaperPersistenceProbe()
    let checkpointStore = stores.checkpointStore
    let persistedPaper = PaperRevisionContext(instance: accepted.identities.paperInstance,
      contactPlane: accepted.identities.paperContactPlane)
    let checkpointFailure = ReplacementCheckpointFailureProbe(store: checkpointStore, paper: persistedPaper)
    let persistence = TestApplicationStatePersistencePort(
      loadCheckpoint: { checkpointStore.load() },
      saveCheckpoint: { try checkpointFailure.save($0) },
      clearCheckpoint: { try checkpointStore.clear() },
      savePaperContext: { try checkpointFailure.savePaper($0) })
    let draft = nominalDrawingDraftRuntime(paperPersistence: paperPersistence)
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let app = plotterApplicationRuntime(machine: machine, statePersistencePort: persistence,
      drawingDraftRuntime: draft, drawingEvidencePort: stores.evidencePort,
      tipCalibrationSemanticIdentities: accepted.identities, loadPenCapAppearanceSelection: { nil }, log: log)
    await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    try await applyCompleteSavedLearning(app)
    let paper = app.currentPaperRevisionContext
    let graph = Set(app.learningArtifactGraph.revisions)
    switch failurePoint {
    case .metadata: checkpointFailure.failNextPaperSave()
    case .checkpoint: checkpointFailure.failNextSave()
    case .coverage: await paperPersistence.failClear()
    }
    let declaration: PlotterUIPaperRequest = contactPlaneChanged
      ? .contactPlaneChanged : .newSheetOnCurrentPlane
    let request = try #require(app.testPlotterUIProjection().semantic.request(matching: .paper(declaration)))
    let outcome = await app.submitPlotterUIRequest(request)
    guard case .refused(let refusal) = outcome else {
      Issue.record("A failed Paper transaction must return its visible refusal, not accepted")
      await app.shutdown()
      return
    }
    #expect(refusal.requestID == request.id)
    #expect(refusal.reason == .retainedOwnerRefused)
    #expect(refusal.remedy.contains(failurePoint.expectedRemedy))
    #expect(app.currentPaperRevisionContext == paper)
    #expect(checkpointFailure.paper == paper)
    #expect(Set(app.learningArtifactGraph.revisions) == graph)
    #expect(app.tipCameraRegistration == accepted.registration)
    #expect(app.interactiveLearningIsComplete)
    #expect(app.explorationError == refusal.remedy)
    guard case .loaded(let retained) = stores.checkpointStore.load() else {
      Issue.record("Rollback lost the accepted package")
      await app.shutdown(); return
    }
    #expect(retained == accepted.checkpoint)
    await paperPersistence.allowClear()
    let retry = try #require(app.testPlotterUIProjection().semantic.request(matching: .paper(declaration)))
    #expect(await app.submitPlotterUIRequest(retry) == .accepted(requestID: retry.id))
    #expect(app.currentPaperRevisionContext.instance != paper.instance)
    #expect(checkpointFailure.paper == app.currentPaperRevisionContext)
    #expect((app.currentPaperRevisionContext.contactPlane != paper.contactPlane) == contactPlaneChanged)
    #expect(app.tipCameraRegistration == (contactPlaneChanged ? nil : accepted.registration))
    #expect(app.penInteractionCompleted)
    #expect(app.machineCameraRegistration == accepted.checkpoint.machineCamera?.registration)
    #expect(app.explorationError == nil)
    await app.shutdown()
  }
}

extension SavedLearningCompletionTests {
  @Test("application shutdown joins committed replacement after a completed drawing")
  func shutdownCompletesProductionPaperReplacement() async throws {
    let persistence = ReplacementPaperPersistenceProbe()
    let f = try await DrawingWorkbenchApplicationFixture.make(paperPersistence: persistence)
    defer { f.stores.remove() }
    let app = f.application
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .contours, strokeStyle: app.drawingStrokeStyle)
    let projection = app.plotterUIProjection(selectedItemID: app.testCurrentLearningPathItemID,
      manualDraft: ManualMotionDraft(), includesLearningPath: true, pendingDrawingProgram: program)
    let select = try #require(projection.semantic.request(matching: .drawingDraft(.selectProgram(program))))
    #expect(await app.submitPlotterUIRequest(select) == .accepted(requestID: select.id))
    try await f.submit(.fitInDrawableRegion)
    try await f.submit(.assertPaperCoverage)
    try await waitUntil { app.drawingRunSnapshot?.readiness == .ready }
    await f.planGate.release(.completed)
    let start = try #require(app.testPlotterUIProjection().semantic.request(matching: .drawingRun(.start)))
    #expect(await app.submitPlotterUIRequest(start) == .accepted(requestID: start.id))
    let record = try #require(app.drawingRunSnapshot?.terminal?.record)
    let oldPaper = app.currentPaperRevisionContext
    let activeRegistration = app.tipCameraRegistration
    await persistence.holdNextClear()
    let replacement = Task { await app.recordNewPaperSheetOnCurrentPlane() }
    try await waitUntilAsync { await persistence.isHeld }
    let shutdown = Task { await app.shutdown() }
    try await waitUntil { app.artifactResetEpisodeSnapshot.admissionClosed }
    await persistence.releaseClear()
    await replacement.value
    await shutdown.value
    #expect(app.currentPaperRevisionContext.instance != oldPaper.instance)
    #expect(app.currentPaperRevisionContext.contactPlane == oldPaper.contactPlane)
    #expect(app.artifactResetEpisodeSnapshot.phase == .completed)
    #expect(app.drawingRunSnapshot?.terminal == nil)
    guard case .loaded(let checkpoint) = f.stores.checkpointStore.load(),
      case .loaded(let archive) = await f.stores.evidenceStore.load() else {
      Issue.record("Shutdown lost durable Learning or drawing evidence")
      return
    }
    #expect(checkpoint.semanticIdentity.paperInstance == app.currentPaperRevisionContext.instance)
    #expect(checkpoint.tipCalibration?.registration == activeRegistration)
    #expect(archive.records.contains(record))
  }

  @Test("paper publication holds source controller and repeated-sheet mutations until one commit")
  func heldPaperPublicationExcludesMutation() async throws {
    let accepted = try await CompleteAcceptedLearningFixture.make()
    let stores = CompleteAcceptedLearningStores()
    defer { stores.remove() }
    try await stores.save(accepted)
    let paperPersistence = ReplacementPaperPersistenceProbe()
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let app = plotterApplicationRuntime(machine: machine, statePersistencePort: stores.persistence,
      drawingDraftRuntime: nominalDrawingDraftRuntime(paperPersistence: paperPersistence),
      drawingEvidencePort: stores.evidencePort, tipCalibrationSemanticIdentities: accepted.identities,
      loadPenCapAppearanceSelection: { nil }, log: log)
    await app.performApplicationStartup(AdaptivePlotterLaunchPolicy(arguments: []))
    await app.establishMachineSession(machine.descriptor)
    try await applyCompleteSavedLearning(app)
    let previousPaper = app.currentPaperRevisionContext
    let previousGraph = Set(app.learningArtifactGraph.revisions)
    await paperPersistence.holdNextClear()
    let replacement = Task { await app.recordNewPaperSheetOnCurrentPlane() }
    try await waitUntilAsync { await paperPersistence.isHeld }
    let source = app.observationConfigurationProjection.request(.selectSource(.simulated, cameraID: nil))
    #expect(await app.submitObservationConfiguration(source) != nil)
    let controller = app.controllerSessionProjection.request(.toggleConnection)
    guard case .refused = await app.submitControllerSessionRequest(controller) else {
      await paperPersistence.releaseClear()
      await replacement.value
      await app.shutdown()
      Issue.record("Controller mutation bypassed the active paper transaction")
      return
    }
    await app.recordNewPaperSheetOnCurrentPlane()
    #expect(app.currentPaperRevisionContext == previousPaper)
    #expect(Set(app.learningArtifactGraph.revisions) == previousGraph)
    #expect(app.frameMode == .live)
    await paperPersistence.releaseClear()
    await replacement.value
    #expect(app.currentPaperRevisionContext.instance != previousPaper.instance)
    #expect(app.currentPaperRevisionContext.contactPlane == previousPaper.contactPlane)
    #expect(app.tipCameraRegistration == accepted.registration)
    #expect(app.explorationError == nil)
    await app.shutdown()
  }
}

private actor ReplacementPaperPersistenceProbe: PlotterDrawingDraftPaperPersistence {
  private var fails = false
  private var shouldHold = false
  private var continuation: CheckedContinuation<Void, Never>?
  var isHeld: Bool { continuation != nil }
  func holdNextClear() { shouldHold = true }
  func releaseClear() { continuation?.resume(); continuation = nil }
  func failClear() { fails = true }
  func allowClear() { fails = false }
  func load() -> PaperCoverageObservation? { nil }
  func save(_: PaperCoverageObservation) {}
  func clear() async throws {
    if shouldHold {
      shouldHold = false
      await withCheckedContinuation { continuation = $0 }
    }
    if fails { throw ReplacementPaperPersistenceError.unavailable }
  }
}

private final class ReplacementCheckpointFailureProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var fails = false
  private var paperSaveFails = false
  private var persistedPaper: PaperRevisionContext
  private let store: AcceptedLearningPathCheckpointStore
  init(store: AcceptedLearningPathCheckpointStore, paper: PaperRevisionContext) {
    self.store = store
    persistedPaper = paper
  }
  var paper: PaperRevisionContext { lock.withLock { persistedPaper } }
  func failNextSave() { lock.withLock { fails = true } }
  func failNextPaperSave() { lock.withLock { paperSaveFails = true } }
  func savePaper(_ paper: PaperRevisionContext) throws {
    let shouldFail = lock.withLock {
      persistedPaper = paper
      let shouldFail = paperSaveFails
      paperSaveFails = false
      return shouldFail
    }
    if shouldFail { throw ReplacementPaperPersistenceError.unavailable }
  }
  func save(_ checkpoint: AcceptedLearningPathCheckpoint) throws {
    try store.save(checkpoint)
    if lock.withLock({ let value = fails; fails = false; return value }) {
      throw ReplacementPaperPersistenceError.unavailable
    }
  }
}
private enum ReplacementPaperPersistenceError: Error { case unavailable }


enum PaperReplacementFailurePoint: CaseIterable, Sendable {
  case metadata, checkpoint, coverage

  var expectedRemedy: String {
    switch self {
    case .metadata: "Paper identity durable write/read-back failed"
    case .checkpoint: "Canonical checkpoint save failed"
    case .coverage: "Sheet coverage persistence failed"
    }
  }
}
