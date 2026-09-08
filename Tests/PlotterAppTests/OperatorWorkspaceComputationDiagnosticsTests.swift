import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace computation diagnostics", .serialized)
@MainActor
struct PlotterApplicationRuntimeComputationDiagnosticsTests {
  @Test("root redraws reuse projection while input edits and semantic actions stay current")
  func rootRedrawsKeepRequestsCurrent() async throws {
    let log = EventLog()
    let workspace = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), log: log)
    let selected = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    var draft = ManualMotionDraft()
    var viewport = ActionSurfaceViewportState()
    func project() -> PlotterAppUIProjection {
      workspace.plotterUIProjection(
        selectedItemID: selected, manualDraft: draft, includesLearningPath: true,
        observationViewport: viewport
      )
    }
    let original = project()
    let builds = workspace.previewIsolationDiagnostics.plotterUIProjectionBuildCount
    for _ in 0..<20 {
      #expect(project().semantic.revision == original.semantic.revision)
      #expect(project().semantic.actions == original.semantic.actions)
    }
    #expect(workspace.previewIsolationDiagnostics.plotterUIProjectionBuildCount == builds)

    draft.feedMMPerMinute = "not a feed"
    let edited = project()
    #expect(edited.semantic.revision != original.semantic.revision)
    #expect(
      edited.semantic.action(id: PlotterAppUIActionID.manualXPositive)?.intent
        == .unavailableLocalInput(PlotterAppUIActionID.manualXPositive)
    )
    viewport.zoom = 0.5
    let zoomed = project()
    #expect(zoomed.semantic.revision != edited.semantic.revision)
    #expect(project().semantic.actions == zoomed.semantic.actions)

    let toggle = try #require(zoomed.semantic.request(for: PlotterAppUIActionID.learningMode))
    let disposition = await workspace.submitPlotterUIRequest(toggle)
    guard case .accepted = disposition else {
      Issue.record("Current cached Learning mode request was refused: \(disposition)")
      await workspace.shutdown()
      return
    }
    let changed = project()
    #expect(changed.learningIsEnabled != original.learningIsEnabled)
    #expect(changed.semantic.revision != zoomed.semantic.revision)
    #expect(project().semantic.actions == changed.semantic.actions)
    await workspace.shutdown()
  }

  @Test("presentation probes expose current recomputation owners without fixed cost assertions")
  func presentationProbeBaseline() async throws {
    let log = EventLog()
    let workspace = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), log: log)
    workspace.resetComputationDiagnosticsForTesting()

    let current = workspace.testCurrentLearningPathItemID
    _ = workspace.testLearningPathProjection(selectedItemID: current)
    _ = workspace.testActionSurfacePresentation

    let diagnostics = workspace.computationDiagnosticsForTesting
    #expect(diagnostics.currentLearningItemBuildCount > 0)
    #expect(diagnostics.learningSnapshotWithoutResetBuildCount > 0)
    #expect(diagnostics.learningSnapshotWithResetBuildCount > 0)
    #expect(diagnostics.learningProjectionBuildCount > 0)
    #expect(diagnostics.learningResetPlanBuildCount > 0)
    #expect(diagnostics.learningSessionReadCount > 0)
    #expect(diagnostics.actionSurfaceBuildCount > 0)
    #expect(
      diagnostics.events.contains {
        if case .learningActionStripChanged = $0 { return true }
        return false
      }
    )
    #expect(
      diagnostics.events.contains {
        if case .actionSurfaceChanged = $0 { return true }
        return false
      }
    )
    await workspace.shutdown()
  }

  @Test("one semantic revision reuses Learning selection and Action Surface caches")
  func presentationCacheReuse() async throws {
    let log = EventLog()
    let workspace = plotterApplicationRuntime(machine: try LowerMachineSessionFixture(log: log), log: log)
    workspace.resetComputationDiagnosticsForTesting()

    let current = workspace.testCurrentLearningPathItemID
    let first = workspace.testLearningPathProjection(selectedItemID: current)
    let second = workspace.testLearningPathProjection(selectedItemID: current)
    let selected = LearningPathItemID.stage(.borderValidations)
    let firstSelected = workspace.testLearningPathProjection(selectedItemID: selected)
    let secondSelected = workspace.testLearningPathProjection(selectedItemID: selected)
    let firstSurface = workspace.testActionSurfacePresentation
    let diagnosticsAfterFirstSurface = workspace.computationDiagnosticsForTesting
    let secondSurface = workspace.testActionSurfacePresentation

    #expect(first == second)
    #expect(firstSelected == secondSelected)
    #expect(firstSurface.displayedFrame?.frame.id == secondSurface.displayedFrame?.frame.id)
    #expect(firstSurface.overlays.count == secondSurface.overlays.count)
    let diagnostics = workspace.computationDiagnosticsForTesting
    #expect(diagnostics.currentLearningItemBuildCount == 1)
    #expect(diagnostics.learningProjectionBuildCount == 2)
    #expect(diagnostics.selectedLearningProjectionBuildCount == 1)
    // The root now reuses the complete projection before reaching the inner
    // selected-Learning and Action Surface caches a second time.
    #expect(diagnostics.selectedLearningProjectionCacheHitCount == 0)
    #expect(diagnostics.learningResetPlanBuildCount == 1)
    #expect(diagnostics.learningProjectionCacheHitCount >= 2)
    #expect(diagnostics.actionSurfaceBuildCount == 1)
    #expect(
      diagnostics.actionSurfaceBuildCount
        == diagnosticsAfterFirstSurface.actionSurfaceBuildCount
    )
    #expect(
      diagnostics.actionSurfaceCacheHitCount
        == diagnosticsAfterFirstSurface.actionSurfaceCacheHitCount
    )
    await workspace.shutdown()
  }

  @Test("120 ambient preview frames invalidate only the video-local projection")
  func ambientPreviewFramesStayOutOfSemanticProjection() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession()
    let previewFrames = TestPreviewFrameUpdateSource()
    let identities = TipCalibrationSemanticIdentityState.ephemeral()
    let savedCheckpoint = try acceptedPenLearningTestCheckpoint(
      identity: identities.learningPathIdentity
    )
    let workspace = plotterApplicationRuntime(
      machine: try LowerMachineSessionFixture(log: log),
      observationSessionOverride: resolvedObservationSession(
        camera,
        frameUpdates: { previewFrames.updates() }
      ),
      statePersistencePort: TestApplicationStatePersistencePort(
        loadCheckpoint: { .loaded(savedCheckpoint) }
      ),
      tipCalibrationSemanticIdentities: identities,
      log: log
    )
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    try await waitForExecutorTurns(
      conditionDescription: "preview frame subscription"
    ) {
      previewFrames.subscriptionCount == 1
    }
    try await waitUntil {
      workspace.actionSurfacePreview.displayedFrame?.frame.sequence == 1
    }
    let initialFrame = try #require(camera.snapshot.latestFrame)
    previewFrames.inject(DisplayedFrame(
      source: initialFrame.source,
      frame: try frame(
        id: "saved-learning-comparison-frame",
        sequence: 2,
        capture: 102,
        configurationID: initialFrame.frame.cameraConfigurationID
      )
    ))
    try await waitForExecutorTurns(
      conditionDescription: "initial Saved Learning optical comparison"
    ) {
      workspace.artifactResetEpisodeSnapshot.savedLearning.candidate?
        .opticalComparison.contains("Waiting for") == false
    }
    // Wait for the actual draft reference, not an assumed scheduler delay.
    try await waitUntil {
      workspace.drawingDraftSnapshot.projection.externalFacts
        == workspace.drawingDraftExternalFacts.revisions
    }

    workspace.resetPreviewIsolationDiagnostics()
    let rootProjection = RootProjectionBuildProbe(application: workspace)
    rootProjection.start()
    let baseline = workspace.previewIsolationDiagnostics
    let baselineRootBuildCount = rootProjection.buildCount

    for offset in 1...120 {
      let sequence = UInt64(offset + 2)
      previewFrames.inject(DisplayedFrame(
        source: initialFrame.source,
        frame: try frame(
          id: "ambient-preview-\(sequence)",
          sequence: sequence,
          capture: 100 + sequence,
          configurationID: initialFrame.frame.cameraConfigurationID
        )
      ))
      try await waitUntil {
        workspace.previewIsolationDiagnostics.previewPublicationCount == UInt64(offset)
      }
    }

    let afterPreview = workspace.previewIsolationDiagnostics
    #expect(afterPreview.previewPublicationCount == 120)
    #expect(afterPreview.latestPreviewFrameID == FrameID(rawValue: "ambient-preview-122"))
    #expect(afterPreview.latestPreviewSequence == 122)
    #expect(afterPreview.latestPreviewSource == initialFrame.source)
    #expect(
      afterPreview.latestPreviewCameraConfigurationID
        == initialFrame.frame.cameraConfigurationID
    )
    #expect(
      afterPreview.semanticPresentationRevision
        == baseline.semanticPresentationRevision
    )
    #expect(
      afterPreview.plotterUIProjectionBuildCount
        == baseline.plotterUIProjectionBuildCount
    )
    #expect(
      afterPreview.learningProjectionBuildCount
        == baseline.learningProjectionBuildCount
    )
    #expect(
      afterPreview.drawingDraftSynchronizationCount
        == baseline.drawingDraftSynchronizationCount
    )
    #expect(rootProjection.buildCount == baselineRootBuildCount)

    workspace.markSemanticPresentationChangedForTesting()
    try await waitUntil {
      rootProjection.buildCount == baselineRootBuildCount + 1
    }
    let afterSemanticTransition = workspace.previewIsolationDiagnostics
    #expect(
      afterSemanticTransition.semanticPresentationRevision
        == afterPreview.semanticPresentationRevision + 1
    )
    #expect(
      afterSemanticTransition.plotterUIProjectionBuildCount
        == afterPreview.plotterUIProjectionBuildCount + 1
    )
    #expect(
      afterSemanticTransition.learningProjectionBuildCount
        == afterPreview.learningProjectionBuildCount + 1
    )
    #expect(
      afterSemanticTransition.drawingDraftSynchronizationCount
        == afterPreview.drawingDraftSynchronizationCount + 1
    )

    // The same reached Open action remains usable after video-only updates.
    try await waitUntil {
      workspace.drawingDraftSnapshot.projection.externalFacts
        == workspace.drawingDraftExternalFacts.revisions
    }
    let projection = workspace.testPlotterUIProjection(
      selectedItemID: .humanGuidedDiscovery(.penInteraction), includesLearningPath: true)
    let openRequest = try #require(projection.semantic.request(for: PlotterAppUIActionID.drawingOpen))
    previewFrames.inject(DisplayedFrame(source: initialFrame.source,
      frame: try frame(id: "open-after-preview", sequence: 123, capture: 223,
        configurationID: initialFrame.frame.cameraConfigurationID)))
    try await waitUntil { workspace.actionSurfacePreview.displayedFrame?.frame.sequence == 123 }
    #expect(await workspace.submitPlotterUIRequest(openRequest) == .accepted(requestID: openRequest.id))
    #expect(workspace.drawingStudioIsPresented)
    previewFrames.finish()
    await workspace.shutdown()
  }

  @Test("cached projection matches an uncached projector after representative transitions")
  func cachedProjectionParity() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let workspace = plotterApplicationRuntime(machine: machine, log: log)

    func expectParity(_ selected: LearningPathItemID) {
      let cached = workspace.testLearningPathProjection(selectedItemID: selected)
      let uncached = workspace.uncachedLearningPathProjectionForTesting(
        selectedItemID: selected
      )
      #expect(cached == uncached)
    }

    expectParity(.humanGuidedDiscovery(.penInteraction))
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    expectParity(.humanGuidedDiscovery(.penInteraction))
    await submitControllerSession(workspace, .toggleMotionAuthorization)
    expectParity(.humanGuidedDiscovery(.penInteraction))
    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { !workspace.testLearningIsEnabled }
    expectParity(.humanGuidedDiscovery(.penInteraction))
    await workspace.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
    try await waitUntil { workspace.testLearningIsEnabled }
    expectParity(.humanGuidedDiscovery(.penInteraction))
    await workspace.shutdown()
  }

  @Test("Exercise 1.4 batch consumes typed outcomes without per-segment recomputation")
  func stageThreeFourBatchConsumesTypedOutcomes() async throws {
    let log = EventLog()
    let camera = try TestObservationCameraSession()
    let machine = try LowerMachineSessionFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0),
      positionObserver: { camera.trackMachinePosition($0) }
    )
    let boundaryRuntimeAccess = TestBoundaryRuntimeAccess()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      camera: camera,
      boundaryRuntimeAccess: boundaryRuntimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    try await installAcceptedBoundaryTestProjection(
      runtime: try #require(boundaryRuntimeAccess.runtime),
      workspace: workspace,
      environment: .live,
      centerArrivalIsAccepted: false
    )
    try await machine.setPosition(x: 100, y: 50)
    await submitControllerSession(workspace, .requestPassiveProbe)

    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try requireEnabledPublicAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      owner: boundaryOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(
      .boundary(.moveToEstimatedCenter(retry: false)),
      for: boundaryOwner
    )
    try await waitForAcceptedBoundaryCenterArrival(workspace: workspace)
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try requireEnabledPublicAction(
      .cameraCalibration(.buildFivePositionProposal),
      owner: cameraOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(
      .cameraCalibration(.buildFivePositionProposal),
      for: cameraOwner
    )
    try requireEnabledPublicAction(
      .cameraCalibration(.acceptProposal),
      owner: cameraOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.cameraCalibration(.acceptProposal), for: cameraOwner)
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let plan = try SparseTipBatchMarkPlan(
      acceptedBoundaryAggregates: workspace.testAcceptedBoundaryAggregates
    )
    let registration = try #require(workspace.machineCameraRegistration)

    let snapshotsBefore = await machine.snapshotCallCount
    let probesBefore = await machine.passiveProbeCallCount
    let strokesBefore = await machine.requestedDrawingStrokes.count
    let penCommandsBefore = await machine.requestedPenCommands.count
    workspace.resetComputationDiagnosticsForTesting()
    let semanticRevisionBefore =
      workspace.computationDiagnosticsForTesting.semanticPresentationRevision

    try requireEnabledPublicAction(
      .tipCalibration(.beginFourMarkBatch),
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.tipCalibration(.beginFourMarkBatch), for: tipOwner)

    let snapshotsAfterBatch = await machine.snapshotCallCount
    let probesAfterBatch = await machine.passiveProbeCallCount
    let strokesAfterBatch = await machine.requestedDrawingStrokes
    let penCommandsAfterBatch = await machine.requestedPenCommands
    let diagnostics = workspace.computationDiagnosticsForTesting
    #expect(strokesAfterBatch.count - strokesBefore == 64)
    #expect(probesAfterBatch - probesBefore == 5)
    // One owner read admits the effect from current settled MPos; one publishes
    // the terminal controller truth. The 64 drawing segments must not add reads.
    #expect(snapshotsAfterBatch - snapshotsBefore == 2)
    #expect(
      Array(penCommandsAfterBatch.dropFirst(penCommandsBefore))
        == [.raise, .lower, .raise, .lower, .raise, .lower, .raise, .lower, .raise]
    )
    #expect(diagnostics.stoppableOperationMutationCount > 64)
    #expect(diagnostics.stoppableOperationSemanticInvalidationCount == 2)
    // One build admits the exact UI request; the second records the required
    // immutable post-transition Learning projection after owner settlement.
    #expect(diagnostics.learningProjectionBuildCount == 2)
    #expect(diagnostics.semanticPresentationRevision - semanticRevisionBefore < 64)
    #expect(workspace.blacklistedToolContactLocations.isEmpty)
    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.machineSnapshot?.currentOperation == .idle)
    #expect(workspace.machineSnapshot?.machine.controllerState == .idle)
    #expect(workspace.machineSnapshot?.machine.penState == .up)
    #expect(workspace.machineSnapshot?.machine.position == plan.finalRevealPosition)
    #expect(workspace.lastProtocolPoseSettlement?.action == .sparseTipBatchReveal)
    #expect(workspace.lastProtocolPoseSettlement?.actual == plan.finalRevealPosition)

    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    for mark in plan.marks {
      let predicted = try registration.fit.cameraPoint(from: mark.machinePosition.point)
      try await submitPointSelectionAndWait(
        workspace,
        request: request,
        point: try Point2(
          x: min(max(predicted.x, 0), Double(request.frame.width - 1)),
          y: min(max(predicted.y, 0), Double(request.frame.height - 1))
        )
      )
    }
    let observations = workspace.tipCalibrationRuntime.acceptedObservations.map {
      $0.observation
    }
    #expect(
      observations.count == 4,
      "phase=\(workspace.tipCalibrationRuntime.phase) error=\(workspace.explorationError ?? "nil") episodePoints=\(workspace.pointSelectionEpisodeProjection.exactPointSelection.selectedPoints.count)"
    )
    #expect(Set(observations.map { $0.controllerContextEvidence.passiveProbeID }).count == 4)
    #expect(
      Set(observations.map { $0.revealEvidence.controllerContextEvidence.passiveProbeID }).count
        == 1
    )
    #expect(
      Set(
        observations.map { $0.controllerContextEvidence.passiveProbeID }
          + observations.map { $0.revealEvidence.controllerContextEvidence.passiveProbeID }
      ).count == 5
    )
    #expect(await machine.requestedDrawingStrokes.count == strokesAfterBatch.count)
    #expect(await machine.passiveProbeCallCount == probesAfterBatch)
    #expect(workspace.blacklistedToolContactLocations.isEmpty)
    await workspace.shutdown()
  }

  @Test("one hundred pull-only Vision diagnostics refreshes preserve the Learning base")
  func diagnosticsOnlyAnalysisPreservesLearningBase() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: resolvedObservationSession(camera),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    workspace.resetComputationDiagnosticsForTesting()
    _ = workspace.currentExerciseActionStripPresentation
    let baseline = workspace.computationDiagnosticsForTesting

    for _ in 0..<100 {
      await submitObservationConfigurationForTest(workspace, .requestDiagnostics)
      _ = workspace.currentExerciseActionStripPresentation
    }

    let diagnostics = workspace.computationDiagnosticsForTesting
    #expect(camera.visionDiagnosticsCallCount == 100)
    #expect(diagnostics.visionAnalysisRevisionCount == 0)
    #expect(diagnostics.semanticPresentationRevision == baseline.semanticPresentationRevision)
    #expect(diagnostics.learningProjectionBuildCount == baseline.learningProjectionBuildCount)
    #expect(
      diagnostics.learningSnapshotWithoutResetBuildCount
        == baseline.learningSnapshotWithoutResetBuildCount
    )
    #expect(diagnostics.learningProjectionCacheHitCount >= 100)
    await workspace.shutdown()
  }

  @Test("held exact workflow publishes its typed Vision owner and suspends overlays")
  func heldExactWorkflowPublishesTypedOwner() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let gate = TestInspectionSuspension()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: resolvedObservationSession(camera, inspectionGate: gate),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    await gate.arm()

    let capture = Task {
      try await workspace.captureStableWorkflowCap(newerThan: 50)
    }
    try await waitForExecutorTurnsAsync(
      conditionDescription: "held exact camera-calibration inspection"
    ) {
      await gate.isWaiting
    }

    #expect(workspace.exactWorkflowVisionOwner == .cameraCalibration)
    #expect(workspace.workbenchComputationPresentation?.title == "Analyzing camera calibration")
    #expect(workspace.overlayStatus(for: .penCap).state == .suspended)

    await gate.release()
    _ = try await capture.value
    #expect(workspace.exactWorkflowVisionOwner == nil)
    #expect(workspace.workbenchComputationPresentation == nil)
    #expect(workspace.overlayStatus(for: .penCap).state != .suspended)
    await workspace.shutdown()
  }

  @Test("held Pen Up remains suspended while bounded analysis revisions are published")
  func heldPenUpWithAnalysisTraffic() async throws {
    let log = EventLog()
    let gate = PenRequestGate()
    let machine = try LowerMachineSessionFixture(log: log, penRequestGate: gate)
    let camera = try TestObservationCameraSession()
    let traffic = TestAnalysisUpdateSource()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: resolvedObservationSession(
        camera,
        analysisUpdates: { traffic.updates() }
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    try await waitForExecutorTurns(
      conditionDescription: "initial analysis subscription"
    ) {
      traffic.subscriptionCount == 1
    }
    workspace.resetComputationDiagnosticsForTesting()

    let penTask = Task { await workspace.executeLearningPenCommand(.raise) }
    try await waitForExecutorTurnsAsync {
      await machine.requestedPenCommands == [.raise]
    }
    var previousProjection: PlotterAppUIProjection?
    var previousBuildCount: Int?
    for revision in 10...12 {
      traffic.inject(revision: UInt64(revision))
      try await waitForExecutorTurns {
        workspace.computationDiagnosticsForTesting.visionAnalysisRevisionCount
          == revision - 9
      }
      if revision == 10 {
        // The first result changes stopped -> running. Finish that semantic
        // publication before measuring subsequent overlay-only revisions.
        try await waitUntil {
          workspace.drawingDraftSnapshot.projection.externalFacts
            == workspace.drawingDraftExternalFacts.revisions
        }
      }
      let projection = workspace.testPlotterUIProjection(includesLearningPath: true)
      let buildCount = workspace.computationDiagnosticsForTesting.plotterUIProjectionBuildCount
      if let previousProjection, let previousBuildCount {
        #expect(projection.semantic.revision == previousProjection.semantic.revision)
        #expect(projection.semantic.actions == previousProjection.semantic.actions)
        #expect(buildCount == previousBuildCount)
      }
      previousProjection = projection
      previousBuildCount = buildCount
    }

    var diagnostics = workspace.computationDiagnosticsForTesting
    #expect(diagnostics.events.contains(.penRequest(.raise, .began)))
    #expect(!diagnostics.events.contains(.penRequest(.raise, .ended)))
    #expect(diagnostics.visionAnalysisRevisionCount == 3)
    #expect(diagnostics.learningProjectionBuildCount > 0)
    #expect(diagnostics.actionSurfaceBuildCount > 0)

    await gate.releaseFirstRequest()
    _ = await penTask.value
    diagnostics = workspace.computationDiagnosticsForTesting
    #expect(diagnostics.events.contains(.penRequest(.raise, .ended)))
    traffic.finish()
    await workspace.shutdown()
  }

  @Test("Boundary Stop remains published while bounded analysis revisions arrive")
  func heldBoundaryWithAnalysisTraffic() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let traffic = TestAnalysisUpdateSource()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: resolvedObservationSession(
        camera,
        analysisUpdates: { traffic.updates() }
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    try await waitForExecutorTurns(
      conditionDescription: "initial analysis subscription"
    ) {
      traffic.subscriptionCount == 1
    }
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    try await waitForExecutorTurns(
      conditionDescription: "post-identification analysis resubscription"
    ) {
      traffic.subscriptionCount >= 2
    }
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    workspace.resetComputationDiagnosticsForTesting()

    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: owner,
      workspace: workspace
    )
    _ = await machine.waitForBoundaryRequest(count: 1)
    let terminalCount = workspace.testBoundaryTerminals.count
    for revision in 10...12 {
      traffic.inject(revision: UInt64(revision))
      try await waitForExecutorTurns(
        conditionDescription: "Boundary analysis revision \(revision - 9)"
      ) {
        workspace.computationDiagnosticsForTesting.visionAnalysisRevisionCount
          == revision - 9
      }
      _ = workspace.currentExerciseActionStripPresentation
      _ = workspace.testActionSurfacePresentation
    }

    let stop = try renderedBoundaryStopKind(owner: owner, workspace: workspace)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains {
        if case .boundary(.stop(_)) = $0.kind {
          return $0.kind == stop
        }
        return false
      } == true
    )

    await workspace.performTestExerciseAction(stop, for: owner)
    try await waitForBoundaryTerminalCount(terminalCount + 1, workspace: workspace)
    #expect(workspace.testBoundaryTerminals.last?.disposition == .accepted)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains {
        if case .boundary(.stop(_)) = $0.kind { return true }
        return false
      } == false
    )
    traffic.finish()
    await workspace.shutdown()
  }

  @Test("typed Boundary center travel can settle naturally after bounded analysis traffic")
  func heldSupervisedTravelWithAnalysisTraffic() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let traffic = TestAnalysisUpdateSource()
    let boundaryRuntimeAccess = TestBoundaryRuntimeAccess()
    let workspace = plotterApplicationRuntime(
      machine: machine,
      observationSessionOverride: resolvedObservationSession(
        camera,
        analysisUpdates: { traffic.updates() }
      ),
      boundaryRuntimeAccess: boundaryRuntimeAccess,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await submitControllerSession(workspace, .requestPassiveProbe)
    await submitObservationConfigurationForTest(workspace, .selectSource(.live, nil))
    try await waitForExecutorTurns(
      conditionDescription: "initial analysis subscription"
    ) {
      traffic.subscriptionCount == 1
    }
    let prerequisitePenOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    await workspace.performTestExerciseAction(.start, for: prerequisitePenOwner)
    let prerequisitePenRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let prerequisitePenFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: prerequisitePenRequest, point: try Point2(
      x: Double(prerequisitePenFrame.frame.width - 1) / 2,
      y: Double(prerequisitePenFrame.frame.height - 1) / 2
    ))
    try await waitUntil { workspace.activeDiscoverySequenceID == .penInteraction }
    for _ in 0..<3 { await workspace.performTestExerciseAction(.choice(.yes), for: prerequisitePenOwner) }
    #expect(workspace.penInteractionCompleted)
    try await waitForExecutorTurns(
      conditionDescription: "post-identification analysis resubscription"
    ) {
      traffic.subscriptionCount >= 2
    }
    try await installAcceptedBoundaryTestProjection(
      runtime: try #require(boundaryRuntimeAccess.runtime),
      workspace: workspace,
      environment: .live,
      centerArrivalIsAccepted: false
    )
    try await machine.setPosition(x: 100, y: 50)
    await submitControllerSession(workspace, .requestPassiveProbe)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    workspace.resetComputationDiagnosticsForTesting()

    let subscriptionCountBeforeTravel = traffic.subscriptionCount
    let automaticRequestsBeforeTravel = camera.recordedAutomaticInspectionRequests
    let travelTask = Task {
      await workspace.performTestExerciseAction(
        .boundary(.moveToEstimatedCenter(retry: false)),
        for: owner
      )
    }
    try await waitForExecutorTurnsAsync(
      conditionDescription: "center-travel settlement continuation"
    ) {
      return await machine.relativeJogIsAwaitingSettlement
    }
    let heldStop = try renderedBoundaryStopKind(owner: owner, workspace: workspace)
    #expect(traffic.subscriptionCount == subscriptionCountBeforeTravel)
    #expect(camera.recordedAutomaticInspectionRequests == automaticRequestsBeforeTravel)
    #expect(workspace.exactWorkflowVisionOwner == nil)

    for revision in 20...22 {
      traffic.inject(revision: UInt64(revision))
      try await waitForExecutorTurns(
        conditionDescription: "center-travel analysis revision \(revision - 19)"
      ) {
        workspace.computationDiagnosticsForTesting.visionAnalysisRevisionCount
          == revision - 19
      }
      _ = workspace.currentExerciseActionStripPresentation
      _ = workspace.testActionSurfacePresentation
    }

    if case .centering = workspace.currentBoundarySnapshot?.projection.phase {
      // Expected: the typed Boundary owner remains active through settlement.
    } else {
      Issue.record("Expected the Boundary runtime to remain in its centering phase.")
    }
    let currentStop = try renderedBoundaryStopKind(owner: owner, workspace: workspace)
    #expect(currentStop == heldStop)
    #expect(traffic.subscriptionCount == subscriptionCountBeforeTravel)
    #expect(camera.recordedAutomaticInspectionRequests == automaticRequestsBeforeTravel)

    await machine.settleRelativeJogNaturally()
    await travelTask.value
    try await waitForAcceptedBoundaryCenterArrival(workspace: workspace)
    #expect(workspace.currentBoundarySnapshot?.projection.terminal?.activity == .centerArrival)
    #expect(workspace.currentBoundarySnapshot?.projection.terminal?.disposition == .accepted)
    #expect(workspace.testCenterArrivalPosition != nil)
    #expect(traffic.subscriptionCount == subscriptionCountBeforeTravel)
    #expect(camera.recordedAutomaticInspectionRequests == automaticRequestsBeforeTravel)
    traffic.finish()
    await workspace.shutdown()
  }
}

@MainActor
private final class RootProjectionBuildProbe {
  private let application: PlotterApplicationRuntime
  private(set) var buildCount = 0

  init(application: PlotterApplicationRuntime) {
    self.application = application
  }

  func start() {
    withObservationTracking {
      _ = application.testPlotterUIProjection(includesLearningPath: true)
      buildCount += 1
    } onChange: { [weak self] in
      Task { @MainActor in self?.start() }
    }
  }
}
