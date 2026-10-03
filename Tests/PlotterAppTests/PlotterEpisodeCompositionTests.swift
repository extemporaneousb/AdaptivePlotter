import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@Suite("PlotterEpisodeCompositionTests")
@MainActor
struct PlotterEpisodeCompositionTests {
  @Test("construction defers Drawing history and checkpoint reads until asynchronous recovery")
  func constructionDefersDurableRecovery() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let port = DrawingRunEvidencePort(store: DrawingRunEvidenceStore(fileURL: directory.appendingPathComponent("evidence.json")))
    let reads = SynchronousCallCounter()
    let machine = try LowerMachineSessionFixture(log: EventLog())
    let app = plotterApplicationRuntime(machine: machine,
      statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: {
        reads.increment(); return .absent
      }), drawingEvidencePort: port, log: EventLog())
    #expect(await port.loadCount == 0)
    #expect(reads.value == 0)
    #expect(app.savedLearningRecoveryIsPending)
    #expect(app.artifactResetEpisodeSnapshot.savedLearning.candidate == nil)
    #expect(app.learningModePresentation.actionTitle == "Loading Saved Learning")
    #expect(app.artifactResetUnavailableReason?.contains("Verifying saved Drawing") == true)
    #expect(!app.interactiveLearningIsComplete)
    let projection = app.testPlotterUIProjection(includesLearningPath: true).semantic
    let action = try #require(projection.action(id: PlotterAppUIActionID.learningMode))
    #expect(!action.isAvailable)
    let request = PlotterUIRequest(id: .init(rawValue: UUID()), uiRevision: projection.revision,
      runtimeRevisions: projection.runtimeRevisions, actionID: action.id, intent: action.intent)
    guard case .refused(let refusal) = await app.submitPlotterUIRequest(request) else {
      Issue.record("Pending recovery admitted Learning"); await app.shutdown(); return
    }
    #expect(refusal.reason == .unavailableAction)
    await app.loadDrawingEvidenceArchive()
    #expect(await port.loadCount == 1)
    #expect(reads.value == 1)
    #expect(!app.savedLearningRecoveryIsPending)
    #expect(app.axisMetricRecoveryError == nil)
    #expect(app.drawingEvidenceError == nil)
    #expect(await machine.requestedFeeds.isEmpty)
    #expect(await machine.requestedPenCommands.isEmpty)
    await app.shutdown()
  }

  @Test("rejected startup evidence cannot publish Saved Learning or drawing authority")
  func rejectedRecoveryRemainsUnavailable() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("evidence.json")
    let corrupt = Data("corrupt Drawing evidence".utf8)
    try corrupt.write(to: file)
    let reads = SynchronousCallCounter()
    let port = DrawingRunEvidencePort(store: DrawingRunEvidenceStore(fileURL: file))
    let machine = try LowerMachineSessionFixture(log: EventLog())
    let app = plotterApplicationRuntime(machine: machine,
      statePersistencePort: TestApplicationStatePersistencePort(loadCheckpoint: {
        reads.increment(); return .absent
      }), drawingEvidencePort: port, log: EventLog())
    #expect(await port.loadCount == 0)
    await app.loadDrawingEvidenceArchive()
    #expect(!app.savedLearningRecoveryIsPending)
    #expect(reads.value == 0)
    #expect(app.axisMetricRecoveryError != nil)
    #expect(app.drawingEvidenceError != nil)
    #expect(app.artifactResetEpisodeSnapshot.savedLearning.candidate == nil)
    guard case .archiveUnavailable = app.drawingRunSnapshot?.noRedraw else {
      Issue.record("Corrupt history must block Drawing"); await app.shutdown(); return
    }
    #expect(try Data(contentsOf: file) == corrupt)
    #expect(await machine.requestedFeeds.isEmpty)
    await app.shutdown()
  }

  @Test("cancelled recovery and reads after shutdown cannot publish late authority")
  func cancelledRecoveryDoesNotPublish() async throws {
    let reads = SynchronousCallCounter()
    let app = try PlotterApplicationFixture(statePersistencePort:
      TestApplicationStatePersistencePort(loadCheckpoint: { reads.increment(); return .absent })).application
    let cancelled = Task { await app.loadDrawingEvidenceArchive() }
    cancelled.cancel()
    await cancelled.value
    #expect(app.savedLearningRecoveryIsPending)
    #expect(reads.value == 0)
    #expect(app.drawingRunSnapshot?.readiness != .ready)
    await app.shutdown()
    await app.loadDrawingEvidenceArchive()
    #expect(app.savedLearningRecoveryIsPending)
    #expect(reads.value == 0)
    #expect(app.artifactResetEpisodeSnapshot.savedLearning.candidate == nil)
  }

  @Test("production-equivalent fixture exposes one projection-bound public sink")
  func onePublicSinkAndForgedRequestRefusal() async throws {
    let fixture = try PlotterApplicationFixture()
    let application = fixture.application
    let sink: any PlotterUIIntentSink = application
    let projection = application.testPlotterUIProjection(includesLearningPath: true).semantic
    let reached = try #require(projection.action(id: PlotterAppUIActionID.learningMode))
    let forged = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: projection.revision,
      runtimeRevisions: projection.runtimeRevisions,
      actionID: reached.id,
      intent: .requestIncidentPackage
    )

    guard case .refused(let refusal) = await sink.submitPlotterUIRequest(forged) else {
      Issue.record("A forged intent must be refused by the sole public sink.")
      return
    }
    #expect(refusal.reason == .mismatchedIntent)
    await application.shutdown()
  }

  @Test("unavailable Learning submissions publish a typed source-attributed episode refusal")
  func unavailableLearningEpisodeRefusal() async throws {
    let application = try PlotterApplicationFixture().application
    let projection = application.testPlotterUIProjection(includesLearningPath: true).semantic
    let action = try #require(projection.actions.first {
      if case .learningAction = $0.intent { return $0.unavailableReason != nil }
      return false
    })
    guard case .learningAction(let learningRequest) = action.intent else { return }
    let request = PlotterUIRequest(
      id: PlotterUIRequestID(rawValue: UUID()),
      uiRevision: projection.revision,
      runtimeRevisions: projection.runtimeRevisions,
      actionID: action.id,
      intent: action.intent
    )

    guard case .refused(let refusal) = await application.submitPlotterUIRequest(request) else {
      Issue.record("An unavailable Learning action must be refused and recorded.")
      return
    }
    #expect(refusal.reason == .unavailableAction)
    let episode = try #require(application.learningEpisodeRecord.entries.last)
    #expect(episode.request == .action(learningRequest))
    #expect(episode.environment == .live)
    #expect(episode.preStateRevision == episode.postStateRevision)
    #expect(!episode.stateChangePublished)
    guard case .refused(let reason, let owner, let remedy) = episode.result else {
      Issue.record("The Learning episode lost its refusal result.")
      return
    }
    #expect(reason == .unavailableAction)
    #expect(owner.rawValue == "PlotterUIIntentSink")
    #expect(remedy == refusal.remedy)
    await application.shutdown()
  }

  @Test("Learning reset records exact request, owner settlement, and post-transition projection")
  func learningResetEpisodeProjection() async throws {
    let application = try PlotterApplicationFixture().application
    let projection = application.testPlotterUIProjection(includesLearningPath: true).semantic
    let action = try #require(projection.actions.first {
      if case .learningReset = $0.intent { return $0.isAvailable }
      return false
    })
    guard case .learningReset(let resetRequest) = action.intent else { return }
    let disposition = await application.submitPlotterUIRequest(.init(
      id: .init(rawValue: UUID()),
      uiRevision: projection.revision,
      runtimeRevisions: projection.runtimeRevisions,
      actionID: action.id,
      intent: action.intent
    ))
    guard case .accepted = disposition else {
      Issue.record("The exact available Learning reset must settle through its owner.")
      return
    }
    let episode = try #require(application.learningEpisodeRecord.entries.last)
    #expect(episode.request == .reset(resetRequest))
    #expect(episode.postTransitionProjection.stateRevision == episode.postStateRevision)
    #expect(episode.postTransitionProjection.activeOwner == nil)
    #expect(episode.stateChangePublished)
    guard case .accepted(let owner) = episode.result else {
      Issue.record("The settled reset must publish its typed owner outcome.")
      return
    }
    #expect(owner.rawValue == "PlotterArtifactResetRuntime")
    await application.shutdown()
  }

  @Test("startup is idempotent and shutdown closes admission")
  func startupIdempotenceAndClosedAdmission() async throws {
    let camera = try TestObservationCameraSession()
    let startupGate = TestConfigurationSuspension()
    let discoveryCount = SynchronousCallCounter()
    let clock = TestClock()
    let fixture = try PlotterApplicationFixture(
      observationSessionOverride: resolvedObservationSession(
        camera,
        startupGate: startupGate
      ),
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: {
          discoveryCount.increment()
          return []
        },
        readNanoseconds: { clock.next() }
      )
    )
    let application = fixture.application
    let policy = AdaptivePlotterLaunchPolicy(arguments: ["AdaptivePlotter"])

    await startupGate.arm()
    let startup = Task { await application.performApplicationStartup(policy) }
    try await waitForExecutorTurnsAsync(
      conditionDescription: "held production startup camera start"
    ) {
      await startupGate.isWaiting
    }

    // The second call observes `.starting` and must not replay discovery or
    // create a second startup lane.
    await application.performApplicationStartup(policy)
    #expect(discoveryCount.value == 1)

    let openProjection = application.testPlotterUIProjection(includesLearningPath: true).semantic
    let openRequest = try #require(
      openProjection.request(for: PlotterAppUIActionID.learningMode)
    )
    let completion = AsyncCompletionProbe()
    let shutdown = Task {
      await application.shutdown()
      await completion.complete()
    }

    try await waitForExecutorTurns(
      conditionDescription: "application admission closed before startup await completes"
    ) {
      application.testPlotterUIProjection(includesLearningPath: true).semantic.revision
        != openProjection.revision
    }
    guard case .refused = await application.submitPlotterUIRequest(openRequest) else {
      Issue.record("Shutdown must synchronously close projection-bound admission.")
      await startupGate.release()
      _ = await startup.value
      _ = await shutdown.value
      return
    }
    #expect(await completion.isComplete == false)

    await startupGate.release()
    _ = await startup.value
    _ = await shutdown.value
    #expect(await completion.isComplete)
  }

  @Test("shutdown cancels and joins the active model-episode Learning task")
  func learningEpisodeTaskStopAndJoin() async throws {
    let camera = try TestObservationCameraSession()
    let inspectionGate = TestInspectionSuspension()
    let fixture = try PlotterApplicationFixture(
      observationSessionOverride: resolvedObservationSession(
        camera,
        inspectionGate: inspectionGate
      )
    )
    let application = fixture.application
    await application.establishMachineSession(fixture.machine.descriptor)
    await submitControllerSession(application, .requestPassiveProbe)
    await submitObservationConfigurationForTest(application, .selectSource(.live, nil))

    await inspectionGate.arm()
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    let residualAction = Task {
      await application.performTestExerciseAction(.start, for: owner)
    }
    try await waitForExecutorTurnsAsync(
      conditionDescription: "episode-keyed retained Learning operation"
    ) {
      await inspectionGate.isWaiting
    }

    let beforeClose = application.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let completion = AsyncCompletionProbe()
    let shutdown = Task {
      await application.shutdown()
      await completion.complete()
    }
    try await waitForExecutorTurns(
      conditionDescription: "residual shutdown admission close"
    ) {
      application.testPlotterUIProjection(
        selectedItemID: owner,
        includesLearningPath: true
      ).semantic.revision != beforeClose.revision
    }
    #expect(await completion.isComplete == false)

    await inspectionGate.release()
    _ = await residualAction.value
    _ = await shutdown.value
    #expect(await completion.isComplete)
    #expect(await inspectionGate.cancellationWasObserved)
    let episode = try #require(application.learningEpisodeRecord.entries.last)
    #expect(episode.request == .action(.init(
      item: .init(rawValue: "\(owner.number)-\(owner.title)"),
      action: .start
    )))
    #expect(episode.transitionID.episodeID == application.learningEpisodeRecord.episodeID)
    #expect(episode.environment == .live)
    guard case .refused(let reason, let episodeOwner, let remedy) = episode.result else {
      Issue.record("Shutdown cancellation must publish a typed Learning refusal.")
      return
    }
    #expect(reason == .ownerRefused)
    #expect(episodeOwner.rawValue == "PlotterApplicationRuntime")
    #expect(remedy.contains("cancelled"))

    let closedProjection = application.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(closedProjection.actions.allSatisfy { !$0.isAvailable })
  }

  @Test("accepted Learning persists before shutdown publishes a closed projection")
  func orderedLearningPersistence() async throws {
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let checkpoint = try acceptedPenLearningTestCheckpoint(
      identity: identities.learningPathIdentity
    )
    let order = SynchronousEventLog()
    let persisted = ArtifactResetCheckpointStoreFixture(checkpoint: checkpoint)
    let statePersistencePort = TestApplicationStatePersistencePort(
      loadCheckpoint: { persisted.load() },
      saveCheckpoint: {
        persisted.save($0)
        order.append("learning-persisted")
      },
      clearCheckpoint: { persisted.clear() }
    )
    let fixture = try PlotterApplicationFixture(
      statePersistencePort: statePersistencePort,
      tipCalibrationSemanticIdentities: identities,
      loadPenCapAppearanceSelection: { nil }
    )
    let application = fixture.application
    await application.establishMachineSession(fixture.machine.descriptor)
    await submitControllerSession(application, .requestPassiveProbe)
    let owner = application.testCurrentLearningPathItemID
    await application.performTestExerciseAction(.applySavedLearning, for: owner)
    #expect(application.penInteractionCompleted)

    await application.shutdown()

    #expect(order.values == ["learning-persisted"])
    #expect(
      persisted.checkpoint?.penInteraction?.revision.id == checkpoint.penInteraction?.revision.id
    )
    let closed = application.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    #expect(closed.actions.allSatisfy { !$0.isAvailable })
  }

  @Test("passive live preview publishes without hashing or exact-frame draft facts")
  func passivePreviewRemainsPresentationOnly() async throws {
    let camera = try TestObservationCameraSession()
    let metrics = FrameContentHashMetrics()
    let passive = DisplayedFrame(
      source: .live(camera.device.id),
      frame: try StampedFrame(
        id: FrameID(rawValue: "passive-production-preview"),
        sequence: 41,
        captureNanoseconds: 410,
        cameraConfigurationID: CameraConfigurationID(),
        width: 16,
        height: 12,
        rowBytes: 64,
        pixelFormat: .bgra8,
        bytes: OwnedFrameBytes(Array(repeating: 255, count: 16 * 12 * 4)),
        eagerlyMaterializeContentHash: false,
        contentHashMetrics: metrics
      )
    )
    let passiveSnapshot = CameraCaptureSnapshot(
      devices: [camera.device],
      selectedDeviceID: camera.device.id,
      state: .running,
      latestFrame: passive,
      error: nil
    )
    let fixture = try PlotterApplicationFixture(
      observationSessionOverride: resolvedObservationSession(
        camera,
        snapshotProvider: { passiveSnapshot }
      ),
      loadPenCapAppearanceSelection: { nil }
    )
    let application = fixture.application

    await application.performApplicationStartup(
      AdaptivePlotterLaunchPolicy(arguments: ["AdaptivePlotter"])
    )

    let presented = try #require(application.testActionSurfacePresentation.displayedFrame)
    #expect(presented.frame.id == passive.frame.id)
    #expect(presented.frame.materializedContentSHA256 == nil)
    #expect(metrics.snapshot.totalComputationCount == 0)
    #expect(application.drawingDraftSnapshot.projection.externalFacts.displayedFrame == nil)
    #expect(application.drawingDraftSnapshot.preview == nil)
    #expect(application.testActionSurfacePresentation.pointSelectionRequest == nil)

    await application.shutdown()
    #expect(metrics.snapshot.totalComputationCount == 0)
  }

  @Test("controller observation and paper controls are immutable application requests")
  func immutableApplicationControlProjection() async throws {
    let fixture = try PlotterApplicationFixture()
    let application = fixture.application
    let initial = application.testPlotterUIProjection(includesLearningPath: true)
    let actionIDs = [
      PlotterAppUIActionID.controllerRefresh,
      PlotterAppUIActionID.observationRefresh,
      PlotterAppUIActionID.paperNewSheet,
      PlotterAppUIActionID.paperContactPlane,
    ]

    for actionID in actionIDs {
      let action = try #require(initial.semantic.action(id: actionID))
      switch (actionID, action.intent) {
      case (PlotterAppUIActionID.controllerRefresh, .controller(_)),
        (PlotterAppUIActionID.observationRefresh, .observation(_)),
        (PlotterAppUIActionID.paperNewSheet, .paper(.newSheetOnCurrentPlane)),
        (PlotterAppUIActionID.paperContactPlane, .paper(.contactPlaneChanged)):
        break
      default:
        Issue.record("Application control \(actionID.rawValue) lost its typed request.")
      }
    }
    #expect(initial.controllerSession.environment == .live)
    #expect(initial.observationConfiguration.frameMode == .live)

    let staleRequest = try #require(
      initial.semantic.request(for: PlotterAppUIActionID.controllerRefresh)
    )
    let simulatedRequest = try #require(
      initial.semantic.request(for: PlotterAppUIActionID.observationSimulated)
    )
    guard case .accepted = await application.submitPlotterUIRequest(simulatedRequest) else {
      Issue.record("The current projection-bound simulated-source action must be accepted.")
      await application.shutdown()
      return
    }
    for _ in 0..<4_000 {
      if application.observationConfigurationProjection.frameMode == .simulated { break }
      await Task.yield()
    }
    guard application.observationConfigurationProjection.frameMode == .simulated else {
      let cameraError = application.cameraError ?? "nil"
      Issue.record(
        "The accepted simulated-source request did not publish: cameraError=\(cameraError), observation=\(application.observationConfigurationProjection)."
      )
      await application.shutdown()
      return
    }
    let updated = application.testPlotterUIProjection(includesLearningPath: true)
    #expect(initial.controllerSession.environment == .live)
    #expect(initial.observationConfiguration.frameMode == .live)
    #expect(updated.controllerSession.environment == .simulated)
    #expect(updated.observationConfiguration.frameMode == .simulated)
    #expect(updated.actionSurface.displayedFrame?.source == .simulated)
    let controllerSlot = WorkbenchControllerSlotPresentation(mode: updated.controllerSession.environment)
    #expect(controllerSlot.title == "Learning Simulator")
    #expect(!controllerSlot.isSerialSelectionEnabled)

    guard case .refused(let refusal) = await application.submitPlotterUIRequest(staleRequest) else {
      Issue.record("An action from an immutable stale projection must not mutate state.")
      await application.shutdown()
      return
    }
    #expect(refusal.reason == .staleUIRevision)

    await application.shutdown()
  }
}
