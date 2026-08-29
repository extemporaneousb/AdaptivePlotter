import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace computation diagnostics", .serialized)
@MainActor
struct OperatorWorkspaceComputationDiagnosticsTests {
  @Test("presentation probes expose current recomputation owners without fixed cost assertions")
  func presentationProbeBaseline() async throws {
    let log = EventLog()
    let workspace = workspace(machine: try MachineFixture(log: log), log: log)
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
    let workspace = workspace(machine: try MachineFixture(log: log), log: log)
    workspace.resetComputationDiagnosticsForTesting()

    let current = workspace.testCurrentLearningPathItemID
    let first = workspace.testLearningPathProjection(selectedItemID: current)
    let second = workspace.testLearningPathProjection(selectedItemID: current)
    let selected = LearningPathItemID.stage(.observedDrawingTrials)
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
    #expect(diagnostics.selectedLearningProjectionCacheHitCount == 1)
    #expect(diagnostics.learningResetPlanBuildCount == 1)
    #expect(diagnostics.learningProjectionCacheHitCount >= 2)
    #expect(diagnostics.actionSurfaceBuildCount == 1)
    #expect(
      diagnostics.actionSurfaceBuildCount
        == diagnosticsAfterFirstSurface.actionSurfaceBuildCount
    )
    #expect(
      diagnostics.actionSurfaceCacheHitCount
        > diagnosticsAfterFirstSurface.actionSurfaceCacheHitCount
    )
    await workspace.shutdown()
  }

  @Test("cached projection matches an uncached projector after representative transitions")
  func cachedProjectionParity() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let workspace = workspace(machine: machine, log: log)

    func expectParity(_ selected: LearningPathItemID) {
      let cached = workspace.testLearningPathProjection(selectedItemID: selected)
      let uncached = workspace.uncachedLearningPathProjectionForTesting(
        selectedItemID: selected
      )
      #expect(cached == uncached)
    }

    expectParity(.humanGuidedDiscovery(.penInteraction))
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    expectParity(.humanGuidedDiscovery(.penInteraction))
    await workspace.performMotionAuthorizationAction()
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
    let camera = try CameraFixture()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: try Vector2(dx: 0, dy: 0),
      positionObserver: { camera.trackMachinePosition($0) }
    )
    let workspace = workspace(machine: machine, camera: camera, log: log)
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)

    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try requireEnabledPublicAction(
      .moveToEstimatedCenter,
      owner: boundaryOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.moveToEstimatedCenter, for: boundaryOwner)
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try requireEnabledPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(
      .runCameraCalibrationAndBuildProposal,
      for: cameraOwner
    )
    try requireEnabledPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.acceptCameraCalibrationProposal, for: cameraOwner)
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let plan = try SparseTipBatchMarkPlan(
      boundarySideAggregates: workspace.boundarySideAggregates
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
      .drawFourCornerTipCircles,
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.drawFourCornerTipCircles, for: tipOwner)

    let snapshotsAfterBatch = await machine.snapshotCallCount
    let probesAfterBatch = await machine.passiveProbeCallCount
    let strokesAfterBatch = await machine.requestedDrawingStrokes
    let penCommandsAfterBatch = await machine.requestedPenCommands
    let diagnostics = workspace.computationDiagnosticsForTesting
    #expect(strokesAfterBatch.count - strokesBefore == 64)
    #expect(probesAfterBatch - probesBefore == 5)
    #expect(snapshotsAfterBatch - snapshotsBefore == 1)
    #expect(
      Array(penCommandsAfterBatch.dropFirst(penCommandsBefore))
        == [.raise, .lower, .raise, .lower, .raise, .lower, .raise, .lower, .raise]
    )
    #expect(diagnostics.stoppableOperationMutationCount > 64)
    #expect(diagnostics.stoppableOperationSemanticInvalidationCount == 2)
    #expect(diagnostics.learningProjectionBuildCount == 1)
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
    let observations = workspace.sparseTipCalibrationCoordinator.acceptedObservations.map {
      $0.observation
    }
    #expect(
      observations.count == 4,
      "phase=\(workspace.sparseTipCalibrationCoordinator.phase) error=\(workspace.explorationError ?? "nil") episodePoints=\(workspace.pointSelectionEpisodeProjection.exactPointSelection.selectedPoints.count)"
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
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(camera),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    workspace.resetComputationDiagnosticsForTesting()
    _ = workspace.currentExerciseActionStripPresentation
    let baseline = workspace.computationDiagnosticsForTesting

    for _ in 0..<100 {
      await workspace.refreshVideoDiagnostics()
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
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let gate = CameraInspectionGate()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(camera, inspectionGate: gate),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
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
    #expect(workspace.overlayStatus(for: .penCap).state == .suspended)
    let selected = workspace.testCurrentLearningPathItemID
    let vision = try #require(
      workspace.selectedOperatorActionPresentation(for: selected).subsystemStatuses.first {
        $0.id == "vision"
      }
    )
    #expect(vision.state == "Camera calibration Vision · active")
    #expect(!vision.state.contains("Trial ink analysis"))

    await gate.release()
    _ = try await capture.value
    #expect(workspace.exactWorkflowVisionOwner == nil)
    #expect(workspace.overlayStatus(for: .penCap).state != .suspended)
    await workspace.shutdown()
  }

  @Test("automatic Pen Down publishes its question in one bounded settlement update")
  func automaticPenDownPublishesNextAuthority() async throws {
    try await expectAutomaticPenSettlementPublishesNextAuthority(
      command: .lower,
      expectedCurrentStepBeforeSettlement: "command-down",
      expectedCurrentStepAfterSettlement: "answer-currently-down"
    )
  }

  @Test("automatic Pen Up publishes its question in one bounded settlement update")
  func automaticPenUpPublishesNextAuthority() async throws {
    try await expectAutomaticPenSettlementPublishesNextAuthority(
      command: .raise,
      expectedCurrentStepBeforeSettlement: "command-up",
      expectedCurrentStepAfterSettlement: "answer-finally-up"
    )
  }

  private func expectAutomaticPenSettlementPublishesNextAuthority(
    command: PenCommand,
    expectedCurrentStepBeforeSettlement: String,
    expectedCurrentStepAfterSettlement: String
  ) async throws {
    let log = EventLog()
    let gate = PenCommandCompletionGate(
      command: command,
      occurrence: 1
    )
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let traffic = CameraAnalysisTrafficFixture()
    let workspace = workspaceWithPenCommandCompletionGate(
      machine: machine,
      cameraActions: cameraActions(
        camera,
        analysisUpdates: { traffic.updates() }
      ),
      gate: gate
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await waitForExecutorTurns { traffic.subscriptionCount == 1 }
    await workspace.beginPenInteraction()
    try await identifyPenCap(workspace)
    try await waitForExecutorTurns { traffic.subscriptionCount >= 2 }
    if command == .raise {
      await workspace.answerCurrentQuestion(.yes)
    }
    try requireStep(
      workspace,
      command == .lower ? "answer-initially-up" : "answer-currently-down"
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    workspace.resetComputationDiagnosticsForTesting()
    _ = workspace.testActionSurfacePresentation
    let requestCountBeforeAnswer = await machine.requestedPenCommands.count
    try await waitForExecutorTurnsAsync {
      workspace.testActionSurfacePresentation.displayedFrame != nil
    }
    let nextTask = Task {
      await workspace.performTestExerciseAction(.choice(.yes), for: owner)
    }
    try await waitForExecutorTurnsAsync {
      let commands = await machine.requestedPenCommands
      return commands.count == requestCountBeforeAnswer + 1
        && commands.last == command
    }
    try requireStep(workspace, expectedCurrentStepBeforeSettlement)
    _ = workspace.currentExerciseActionStripPresentation
    _ = workspace.testActionSurfacePresentation
    let baselineDiagnostics = workspace.computationDiagnosticsForTesting
    let baselineSnapshotCallCount = await machine.snapshotCallCount
    #expect(baselineDiagnostics.events.contains(.penRequest(command, .began)))
    #expect(!baselineDiagnostics.events.contains(.penRequest(command, .ended)))

    await gate.release()
    await nextTask.value
    try requireStep(workspace, expectedCurrentStepAfterSettlement)
    #expect(workspace.currentExerciseActionStripPresentation?.penSetpointAdjustment?.command == command)
    _ = workspace.testActionSurfacePresentation
    let diagnostics = workspace.computationDiagnosticsForTesting
    #expect(diagnostics.events.contains(.penRequest(command, .ended)))
    #expect(
      diagnostics.learningSessionWriteCount
        == baselineDiagnostics.learningSessionWriteCount + 1
    )
    #expect(
      diagnostics.semanticPresentationRevision
        == baselineDiagnostics.semanticPresentationRevision + 1
    )
    #expect(
      diagnostics.learningProjectionBuildCount
        == baselineDiagnostics.learningProjectionBuildCount + 1
    )
    #expect(
      diagnostics.actionSurfaceBuildCount
        == baselineDiagnostics.actionSurfaceBuildCount
    )
    #expect(await machine.snapshotCallCount == baselineSnapshotCallCount + 1)
    traffic.finish()
    await workspace.shutdown()
  }

  @Test("held Pen Up remains suspended while bounded analysis revisions are published")
  func heldPenUpWithAnalysisTraffic() async throws {
    let log = EventLog()
    let gate = PenRequestGate()
    let machine = try MachineFixture(log: log, penRequestGate: gate)
    let camera = try CameraFixture()
    let traffic = CameraAnalysisTrafficFixture()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(
        camera,
        analysisUpdates: { traffic.updates() }
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
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
    #expect(workspace.penRequestInProgress)

    for revision in 10...12 {
      traffic.inject(revision: UInt64(revision))
      try await waitForExecutorTurns {
        workspace.computationDiagnosticsForTesting.visionAnalysisRevisionCount
          == revision - 9
      }
      _ = workspace.currentExerciseActionStripPresentation
      _ = workspace.testActionSurfacePresentation
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
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let traffic = CameraAnalysisTrafficFixture()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(
        camera,
        analysisUpdates: { traffic.updates() }
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await waitForExecutorTurns(
      conditionDescription: "initial analysis subscription"
    ) {
      traffic.subscriptionCount == 1
    }
    try await completePenInteraction(workspace)
    try await waitForExecutorTurns(
      conditionDescription: "post-identification analysis resubscription"
    ) {
      traffic.subscriptionCount >= 2
    }
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    workspace.resetComputationDiagnosticsForTesting()

    await workspace.performTestExerciseAction(.start, for: owner)
    try await waitForExecutorTurnsAsync(
      conditionDescription: "Boundary Stop publication and controller settlement continuation"
    ) {
      guard workspace.contextualStopPresentation != nil else { return false }
      return await machine.boundaryMotionIsAwaitingSettlement
    }
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

    let stop = try #require(workspace.contextualStopPresentation)
    var diagnostics = workspace.computationDiagnosticsForTesting
    #expect(diagnostics.events.contains(.boundaryMotion(.positiveX, .began)))
    #expect(!diagnostics.events.contains(.boundaryMotion(.positiveX, .ended)))
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains {
        if case .stop(let capabilityID) = $0.kind {
          return capabilityID == stop.capabilityID
        }
        return false
      } == true
    )

    await workspace.stopCurrentOperation(capabilityID: stop.capabilityID)
    diagnostics = workspace.computationDiagnosticsForTesting
    #expect(diagnostics.events.contains(.boundaryMotion(.positiveX, .ended)))
    traffic.finish()
    await workspace.shutdown()
  }

  @Test("supervised Pen-Up travel can settle naturally after bounded analysis traffic")
  func heldSupervisedTravelWithAnalysisTraffic() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let traffic = CameraAnalysisTrafficFixture()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(
        camera,
        analysisUpdates: { traffic.updates() }
      ),
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await waitForExecutorTurns(
      conditionDescription: "initial analysis subscription"
    ) {
      traffic.subscriptionCount == 1
    }
    try await completePenInteraction(workspace)
    try await waitForExecutorTurns(
      conditionDescription: "post-identification analysis resubscription"
    ) {
      traffic.subscriptionCount >= 2
    }
    try await completeLiveBoundaries(workspace, machine: machine)
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    workspace.resetComputationDiagnosticsForTesting()

    let subscriptionCountBeforeTravel = traffic.subscriptionCount
    let automaticRequestsBeforeTravel = camera.recordedAutomaticInspectionRequests
    let travelTask = Task {
      await workspace.performTestExerciseAction(.moveToEstimatedCenter, for: owner)
    }
    try await waitForExecutorTurnsAsync(
      conditionDescription: "center-travel settlement continuation"
    ) {
      return await machine.relativeJogIsAwaitingSettlement
    }
    let heldStop = try #require(workspace.contextualStopPresentation)
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

    var diagnostics = workspace.computationDiagnosticsForTesting
    #expect(
      diagnostics.events.contains(
        .supervisedTravel(.moveToEstimatedCenter, .began)
      )
    )
    #expect(
      !diagnostics.events.contains(
        .supervisedTravel(.moveToEstimatedCenter, .ended)
      )
    )
    #expect(workspace.contextualStopPresentation?.capabilityID == heldStop.capabilityID)
    let vision = try #require(
      workspace.selectedOperatorActionPresentation(for: owner).subsystemStatuses.first {
        $0.id == "vision"
      }
    )
    #expect(vision.state == "Overlay analysis · running")
    #expect(!vision.detail.accessibilityText.contains("preview held"))
    #expect(traffic.subscriptionCount == subscriptionCountBeforeTravel)
    #expect(camera.recordedAutomaticInspectionRequests == automaticRequestsBeforeTravel)

    await machine.settleRelativeJogNaturally()
    await travelTask.value
    diagnostics = workspace.computationDiagnosticsForTesting
    #expect(
      diagnostics.events.contains(
        .supervisedTravel(.moveToEstimatedCenter, .ended)
      )
    )
    #expect(workspace.centerArrivalPosition != nil)
    #expect(traffic.subscriptionCount == subscriptionCountBeforeTravel)
    #expect(camera.recordedAutomaticInspectionRequests == automaticRequestsBeforeTravel)
    traffic.finish()
    await workspace.shutdown()
  }
}

private actor PenCommandCompletionGate {
  private let command: PenCommand
  private var remainingOccurrences: Int
  private var releasedEarly = false
  private var continuation: CheckedContinuation<Void, Never>?

  init(command: PenCommand, occurrence: Int) {
    precondition(occurrence > 0)
    self.command = command
    remainingOccurrences = occurrence
  }

  func waitIfTarget(_ candidate: PenCommand) async {
    guard candidate == command, remainingOccurrences > 0 else { return }
    remainingOccurrences -= 1
    guard remainingOccurrences == 0, !releasedEarly else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func release() {
    guard let continuation else {
      releasedEarly = true
      return
    }
    self.continuation = nil
    continuation.resume()
  }
}

@MainActor
private func workspaceWithPenCommandCompletionGate(
  machine: MachineFixture,
  cameraActions: OperatorWorkspace.CameraActions,
  gate: PenCommandCompletionGate
) -> OperatorWorkspace {
  let clock = TestClock()
  return OperatorWorkspace(
    machineActions: .init(
      select: { _ in await machine.snapshot() },
      snapshot: { await machine.snapshot() },
      requestPassiveProbe: { await machine.passiveProbeResult() },
      requestControllerAlarmClear: { .refused(.noCurrentAlarmEvidence) },
      activateMotionGuard: { .activated },
      deactivateMotionGuard: {},
      beginRelativeJog: { request in
        .admitted(
          RelativeJogOperation(
            id: UUID(),
            task: Task { await machine.performRelativeMotion(request) }
          )
        )
      },
      beginDrawingStroke: { request in
        .admitted(
          DrawingStrokeOperation(
            id: UUID(),
            task: Task { await machine.requestDrawingStroke(request) }
          )
        )
      },
      beginPenActuation: { command, profile in
        .admitted(PenActuationOperation(
          id: UUID(),
          task: Task {
            let outcome = await machine.requestPen(command, profile: profile)
            await gate.waitIfTarget(command)
            return outcome
          }
        ))
      },
      beginBoundaryMotion: { request, _ in
        .admitted(
          BoundaryMotionOperation(
            ownerID: request.ownerID,
            task: Task { await machine.requestBoundaryMotion(request) }
          )
        )
      },
      requestJogCancel: { intent in await machine.cancel(intent: intent) },
      disconnect: {}
    ),
    cameraActions: cameraActions,
    drawingDraftRuntime: nominalDrawingDraftRuntime(),
    drawingRunComposition: nominalDrawingRunComposition(),
    incidentPackageUIService: nominalIncidentPackageUIService(),
    serialDevices: [machine.descriptor],
    serialDeviceDiscovery: { [machine.descriptor] },
    loadSelectedSerialIdentifier: { nil },
    persistSelectedSerialIdentifier: { _ in },
    loadPenCapAppearanceSelection: { testPenCapAppearanceSelection() },
    persistPenCapAppearanceSelection: { _ in },
    loadOverlayPreference: { nil },
    persistOverlayPreference: { _ in },
    nowNanoseconds: { clock.next() }
  )
}
