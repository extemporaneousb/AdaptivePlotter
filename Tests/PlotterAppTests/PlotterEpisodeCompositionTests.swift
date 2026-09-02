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
      intent: .applicationAction(reached.id)
    )

    guard case .refused(let refusal) = await sink.submitPlotterUIRequest(forged) else {
      Issue.record("A forged intent must be refused by the sole public sink.")
      return
    }
    #expect(refusal.reason == .mismatchedIntent)
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

  @Test("shutdown stops and joins a package-registry residual operation")
  func residualRegistryStopAndJoin() async throws {
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
      conditionDescription: "registry-backed retained Learning operation"
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
      #expect(action.intent == .applicationAction(actionID))
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
    #expect(
      updated.observationConfiguration.simulatorEvidenceLabel
        == "SIMULATED — NOT PHYSICAL EVIDENCE"
    )

    guard case .refused(let refusal) = await application.submitPlotterUIRequest(staleRequest) else {
      Issue.record("An action from an immutable stale projection must not mutate state.")
      await application.shutdown()
      return
    }
    #expect(refusal.reason == .staleUIRevision)

    await application.shutdown()
  }
}
