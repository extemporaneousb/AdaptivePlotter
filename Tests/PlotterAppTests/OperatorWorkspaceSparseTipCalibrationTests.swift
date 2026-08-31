import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@MainActor
@Suite("Operator workspace sparse tip calibration")
struct OperatorWorkspaceSparseTipCalibrationTests {
  @Test("settled sparse pose does not emit a numerical-zero travel")
  func settledPoseSkipsNumericalZeroTravel() throws {
    let current = try MachinePosition(x: -38.475, y: -23.641)
    let numericallyDifferentTarget = try MachinePosition(
      x: -38.474999999999994,
      y: -23.641
    )
    let residue = numericallyDifferentTarget.point.x - current.point.x

    #expect(residue > 0)
    #expect(residue < 1e-12)
    #expect(
      try OperatorWorkspace.supervisedTravelDelta(
        from: current,
        to: numericallyDifferentTarget
      ) == nil
    )

    let outsideTolerance = try MachinePosition(x: current.point.x + 0.501, y: current.point.y)
    let travelDelta = try OperatorWorkspace.supervisedTravelDelta(
      from: current,
      to: outsideTolerance
    )
    let requiredDelta = try #require(travelDelta)
    #expect(abs(requiredDelta.dx - 0.501) < 1e-12)
    #expect(requiredDelta.dy == 0)
  }

  @Test("four SIMULATED corner-circle centers accept in memory without writing LIVE authority")
  func fullFourCornerMarkAcceptance() async throws {
    let checkpointBox = LearningPathCheckpointBox()
    let telemetry = WorkflowTelemetryFixture()
    let harness = makeCausalSimulatorAppFixture(
      workflowTelemetry: telemetry,
      learningPathCheckpointActions: .init(
        load: { checkpointBox.load() },
        save: { checkpointBox.save($0) },
        clear: { checkpointBox.clear() }
      )
    )
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    let workspace = harness.workspace
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
    let telemetryCountBeforeSparseBatch = await telemetry.events.count

    try requireEnabledPublicAction(
      .drawFourCornerTipCircles,
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.drawFourCornerTipCircles, for: tipOwner)
    let sparseBatchEvents = Array(
      (await telemetry.events).dropFirst(telemetryCountBeforeSparseBatch)
    )
    #expect(sparseBatchEvents.count == 7)
    #expect(sparseBatchEvents.allSatisfy { $0.operation == .sparseTipCalibration })
    #expect(sparseBatchEvents.allSatisfy { $0.operation != .currentCameraCalibration })
    #expect(Set(sparseBatchEvents.map(\.operationID)).count == 1)
    #expect(
      sparseBatchEvents.map(\.phase)
        == [
          .batchAdmitted,
          .circleCompleted, .circleCompleted, .circleCompleted, .circleCompleted,
          .revealCompleted,
          .completed,
        ]
    )
    #expect(
      sparseBatchEvents.compactMap(\.sparseTipProgress).map(\.stage)
        == [
          .batchAdmitted,
          .circleCompleted, .circleCompleted, .circleCompleted, .circleCompleted,
          .revealCompleted,
          .terminal,
        ]
    )
    #expect(
      sparseBatchEvents.compactMap(\.sparseTipProgress).map(\.completedCircleCount)
        == [0, 1, 2, 3, 4, 4, 4]
    )
    #expect(
      sparseBatchEvents.compactMap(\.sparseTipProgress).map(\.totalCircleCount)
        == [4, 4, 4, 4, 4, 4, 4]
    )
    #expect(
      sparseBatchEvents.compactMap(\.sparseTipProgress).compactMap(\.chordCount)
        == [16, 16, 16, 16]
    )
    #expect(
      sparseBatchEvents.compactMap(\.sparseTipProgress).compactMap(\.circlePosition)
        == SparseTipCalibrationCoordinator.orderedPositions
    )
    #expect(
      sparseBatchEvents.last?.sparseTipProgress?.terminalDisposition == .completed
    )
    let surface = workspace.testActionSurfacePresentation
    let request = try #require(surface.pointSelectionRequest)
    #expect(surface.viewportContext?.preferredInitialZoom == 0)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 64)
    let registration = try #require(workspace.machineCameraRegistration)
    let truthOffset = await harness.simulator.capToTipPixelOffsetTruth()
    let batch = try SparseTipBatchMarkPlan(
      acceptedBoundaryAggregates: workspace.testAcceptedBoundaryAggregates
    )
    let revealSnapshot = await harness.simulator.snapshot()
    #expect(revealSnapshot.mpos.xMM == batch.finalRevealPosition.point.x)
    #expect(revealSnapshot.mpos.yMM == batch.finalRevealPosition.point.y)
    let clicks = try batch.marks.map {
      try registration.fit.cameraPoint(from: $0.machinePosition.point)
        .translated(by: truthOffset)
    }
    for click in [clicks[3], clicks[1], clicks[0], clicks[2]] {
      try await submitPointSelectionAndWait(workspace, request: request, point: click)
    }
    #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.count == 4)
    let observations = workspace.sparseTipCalibrationCoordinator.acceptedObservations.map(
      \.observation
    )
    let revealFrameIDs = Set(observations.map { $0.revealEvidence.frame.frameID })
    #expect(revealFrameIDs.count == 1)
    #expect(Set(observations.map(\.revealEvidence)).count == 1)
    #expect(Set(observations.map(\.attemptID)).count == 1)
    #expect(Set(observations.map(\.operationID)).count == 4)
    #expect(Set(observations.map { $0.preMarkFrame.frameID }).count == 4)
    #expect(observations.map(\.intendedMarkPosition) == batch.marks.map(\.machinePosition))
    for observation in observations {
      #expect(observation.markGeometry.radiusMM == 2)
      #expect(observation.markGeometry.chordCount == 16)
      #expect(observation.markGeometry.maximumFeedMMPerMinute == 100)
      #expect(
        observation.penDown.outcome
          == .commandedAndSettled(
            command: .lower,
            commandedState: .down
          ))
      #expect(
        observation.penUp.outcome
          == .commandedAndSettled(
            command: .raise,
            commandedState: .up
          ))
    }
    for (preceding, following) in zip(observations, observations.dropFirst()) {
      #expect(
        preceding.penUp.timestamp.monotonicNanoseconds
          <= following.preMarkFrame.captureNanoseconds
      )
      #expect(
        following.preMarkFrame.captureNanoseconds
          <= following.penDown.timestamp.monotonicNanoseconds
      )
    }
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 64)

    #expect(workspace.tipCameraRegistration == nil)
    let proposed = try #require(workspace.proposedTipCameraRegistration)
    #expect(proposed.applicabilityRectangle == batch.applicabilityRectangle)
    let proposalOverlays = workspace.testActionSurfacePresentation.overlays
    let proposedBoundaryOverlay = try #require(
      proposalOverlays.first { $0.provenance.kind == .acceptedBoundary }
    )
    let proposedFrameOverlay = try #require(
      proposalOverlays.first {
        $0.provenance.kind == .intendedPath
          && $0.provenance.algorithmRevision == "proposed-tip-drawing-border-preview-v2"
      }
    )
    guard case .polyline(let proposedBoundary) = proposedBoundaryOverlay.geometry,
      case .polyline(let proposedFrame) = proposedFrameOverlay.geometry
    else {
      Issue.record("Expected the accepted Drawing Boundary and proposed Drawing Border polylines.")
      return
    }
    let boundaryOutline = try DrawingBorderPlan(bounds: batch.boundaryEnvelope)
    let proposedBorder = try DrawingBorderPlan(bounds: batch.applicabilityRectangle)
    let proposedBoundaryPoints = try boundaryOutline.pathPositions.map {
      try proposed.cameraFromMachine.applying(to: $0.point)
    }
    let proposedFramePoints = try proposedBorder.pathPositions.map {
      try proposed.tipPixel(at: $0.point)
    }
    #expect(proposedBoundary.points == proposedBoundaryPoints)
    #expect(proposedFrame.points == proposedFramePoints)
    if case .reviewingModel(.directAffine) = workspace.sparseTipCalibrationCoordinator.phase {
      // The fourth click stages a reviewable map; it is not accepted implicitly.
    } else {
      Issue.record("Expected the fitted tip map to wait for explicit review.")
    }
    try requireEnabledPublicAction(
      .rejectTipCalibrationProposal,
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.rejectTipCalibrationProposal, for: tipOwner)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.proposedTipCameraRegistration == nil)
    #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.isEmpty)
    #expect(
      workspace.sparseTipCalibrationCoordinator.phase
        == .awaitingFrozenClicks(FrameID(rawValue: request.frame.frameID))
    )
    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest?.frame == request.frame)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 64)
    for click in [clicks[3], clicks[1], clicks[0], clicks[2]] {
      try await submitPointSelectionAndWait(workspace, request: request, point: click)
    }
    try requireEnabledPublicAction(
      .acceptTipCalibrationProposal,
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.acceptTipCalibrationProposal, for: tipOwner)

    let accepted = try #require(
      workspace.tipCameraRegistration,
      "accepted registration missing: \(workspace.explorationError ?? "no error")"
    )
    #expect(accepted.modelForm == .directAffine)
    #expect(accepted.applicabilityRectangle == batch.applicabilityRectangle)
    #expect(accepted.modelSelectionEvidence.observationIDs.count == 4)
    #expect(workspace.proposedTipCameraRegistration == nil)
    #expect(workspace.sparseTipCalibrationCoordinator.phase == .accepted)
    let regionOverlay = try #require(
      workspace.testActionSurfacePresentation.overlays.first {
        $0.provenance.kind == .drawingBorder
      }
    )
    guard case .polyline(let regionPolyline) = regionOverlay.geometry else {
      Issue.record("Expected the accepted Drawing Border overlay to be a bounding polyline.")
      return
    }
    let acceptedBoundaryOverlay = try #require(
      workspace.testActionSurfacePresentation.overlays.first {
        $0.provenance.kind == .acceptedBoundary
      }
    )
    guard case .polyline(let acceptedBoundaryPolyline) = acceptedBoundaryOverlay.geometry else {
      Issue.record("Expected the accepted Drawing Boundary overlay to be a bounding polyline.")
      return
    }
    #expect(workspace.currentDrawableMachineRegion?.effectiveBounds == batch.boundaryEnvelope)
    let acceptedFramePoints = try proposedBorder.pathPositions.map {
      try accepted.tipPixel(at: $0.point)
    }
    #expect(regionPolyline.points == acceptedFramePoints)
    let acceptedBoundaryPoints = try boundaryOutline.pathPositions.map {
      try accepted.cameraFromMachine.applying(to: $0.point)
    }
    #expect(acceptedBoundaryPolyline.points == acceptedBoundaryPoints)
    #expect(
      workspace.testCurrentLearningPathItemID
        == .observedDrawingTrial(.chooseDrawingBorderPlan)
    )
    #expect(checkpointBox.checkpoint == nil)
    #expect(checkpointBox.operationCounts.loads == 1)
    #expect(checkpointBox.operationCounts.saves == 0)
    #expect(checkpointBox.operationCounts.clears == 0)
  }

  @Test("five-cap acceptance advances directly to sparse marks")
  func fiveCapAcceptance() async throws {
    let harness = makeCausalSimulatorAppFixture()
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    #expect(workspace.testCurrentLearningPathItemID == owner)
    #expect(workspace.testActionSurfacePresentation.tipPresentation.statusText == "Tip not calibrated")

    try requireEnabledPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.runCameraCalibrationAndBuildProposal, for: owner)
    let proposal = try #require(workspace.proposedMachineCameraRegistration)
    #expect(proposal.fitCorrespondenceProvenance.count == 3)
    #expect(proposal.holdoutCorrespondenceProvenance.count == 2)
    #expect(proposal.fit.correspondences.count == 5)
    #expect(proposal.opticalConfiguration.source == .simulated)
    #expect(
      proposal.applicabilityDerivation
        == .boundaryEnvelopeInsetAndSymmetricallyReduced(
          safetyMarginMM: 10,
          maximumHalfSpanMM: 30
        ))
    try requireEnabledPublicAction(
      .acceptCameraCalibrationProposal,
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.acceptCameraCalibrationProposal, for: owner)
    #expect(
      workspace.testCurrentLearningPathItemID
        == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )
  }

  @Test("same-frame click correction emits no motion, capture, or additional ink")
  func frozenClickCorrectionNoRedraw() async throws {
    let harness = makeCausalSimulatorAppFixture()
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    let workspace = harness.workspace
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

    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    try requireEnabledPublicAction(
      .drawFourCornerTipCircles,
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.drawFourCornerTipCircles, for: owner)
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let frameID = request.frame.frameID
    let before = await harness.simulator.snapshot()
    try await submitPointSelectionAndWait(
      workspace,
      request: request,
      point: try Point2(x: 160, y: 120)
    )
    try requireEnabledPublicAction(.undoLastSparseTipClick, owner: owner, workspace: workspace)
    await workspace.performTestExerciseAction(.undoLastSparseTipClick, for: owner)
    let after = await harness.simulator.snapshot()
    let correctedRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)

    #expect(correctedRequest.frame.frameID == frameID)
    #expect(
      workspace.pointSelectionEpisodeProjection.exactPointSelection.request?.frame.frameID
        == frameID
    )
    #expect(workspace.selectedToolContactPoints.isEmpty)
    #expect(after.mpos == before.mpos)
    #expect(after.persistentInkSegmentCount == before.persistentInkSegmentCount)
    #expect(after.currentOperation == nil)
  }

  @Test("stopping a corner circle after Pen Down blacklists its location and never redraws it")
  func stoppedCircleBlacklistsWithoutRedraw() async throws {
    let telemetry = WorkflowTelemetryFixture()
    let harness = makeCausalSimulatorAppFixture(workflowTelemetry: telemetry)
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    let workspace = harness.workspace
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
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    let pacing = CalibrationStopPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let telemetryCountBeforeSparseBatch = await telemetry.events.count

    let markTask = Task {
      await workspace.performTestExerciseAction(.drawFourCornerTipCircles, for: owner)
    }
    await pacing.waitUntilSuspended()
    let travelCapability = try #require(workspace.contextualStopPresentation?.capabilityID)
    #expect(workspace.currentExerciseActionStripPresentation?.mustRemainVisible == true)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.map(\.kind)
        == [.stop(travelCapability)]
    )
    await pacing.resume()
    await pacing.waitUntilSuspended()
    let capability = try #require(workspace.contextualStopPresentation?.capabilityID)
    #expect(capability == travelCapability)
    #expect(
      workspace.contextualStopPresentation?.detail.contains("four-circle calibration")
        == true
    )
    #expect(workspace.currentExerciseActionStripPresentation?.mustRemainVisible == true)
    await pacing.resume()
    await pacing.waitUntilSuspended()
    #expect(workspace.contextualStopPresentation?.capabilityID == capability)
    let stopTask = Task { await workspace.stopCurrentOperation(capabilityID: capability) }
    try await waitUntilAsync { (await harness.simulator.snapshot()).currentOperation == nil }
    await pacing.resume()
    await stopTask.value
    await markTask.value

    let sparseBatchEvents = Array(
      (await telemetry.events).dropFirst(telemetryCountBeforeSparseBatch)
    )
    #expect(sparseBatchEvents.allSatisfy { $0.operation == .sparseTipCalibration })
    #expect(sparseBatchEvents.first?.sparseTipProgress?.stage == .batchAdmitted)
    let terminalEvents = sparseBatchEvents.filter { $0.sparseTipProgress?.stage == .terminal }
    #expect(terminalEvents.count == 1)
    #expect(terminalEvents[0].phase == .failed)
    #expect(terminalEvents[0].sparseTipProgress?.terminalDisposition == .possibleInk)

    #expect(workspace.sparseTipCalibrationCoordinator.blacklistedPositions == [.negativeX])
    #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.isEmpty)
    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest == nil)
    #expect(workspace.contextualStopPresentation == nil)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 0)
    if case .possibleInkBlacklisted(let location, _) =
      workspace.sparseTipCalibrationCoordinator.phase
    {
      let batch = try SparseTipBatchMarkPlan(
        acceptedBoundaryAggregates: workspace.testAcceptedBoundaryAggregates
      )
      #expect(location.machinePosition == batch.marks[0].machinePosition)
      #expect(location.markRadiusMM == 2)
    } else {
      Issue.record("Stopped circle did not retain terminal possible-ink state")
    }
  }

  @Test("explicit changed-coordinate recovery revalidates without another mark")
  func checkpointRevalidationRestoresWithoutAnotherMark() async throws {
    let identities = TipCalibrationSemanticIdentityState(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperInstance: PaperInstanceRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
    let initial = makeCausalSimulatorAppFixture(tipCalibrationSemanticIdentities: identities)
    try await completeSimulatedPenInteractionPrerequisite(initial.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: initial.boundaryRuntime,
      workspace: initial.workspace,
      environment: .simulated
    )
    try await completeSimulatedSparseTipCalibration(
      initial.workspace,
      simulator: initial.simulator
    )
    let initialRegistration = try #require(initial.workspace.tipCameraRegistration)
    let saved = try AcceptedTipCalibrationCheckpoint(
      registration: initialRegistration,
      acceptanceEvent: TipCalibrationAcceptanceEvent(
        acceptedRevisionID: initialRegistration.acceptedRevisionID,
        timestamp: initialRegistration.acceptedAt,
        actor: "test fixture"
      )
    )
    #expect((await initial.simulator.snapshot()).persistentInkSegmentCount == 64)

    let restarted = makeCausalSimulatorAppFixture(tipCalibrationSemanticIdentities: identities)
    try await completeSimulatedPenInteractionPrerequisite(restarted.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: restarted.boundaryRuntime,
      workspace: restarted.workspace,
      environment: .simulated
    )
    restarted.workspace.replaceSimulatedTipCalibrationCheckpointForTesting(saved)
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    try requireEnabledPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(
      .runCameraCalibrationAndBuildProposal,
      for: cameraOwner
    )
    try requireEnabledPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(
      .acceptCameraCalibrationProposal,
      for: cameraOwner
    )
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    #expect((await restarted.simulator.snapshot()).persistentInkSegmentCount == 0)
    try requireEnabledPublicAction(
      .revalidateTipCalibrationCheckpoint,
      owner: tipOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(
      .revalidateTipCalibrationCheckpoint,
      for: tipOwner
    )

    let restored = try #require(
      restarted.workspace.tipCameraRegistration,
      "restore error: \(restarted.workspace.explorationError ?? "none")"
    )
    #expect((await restarted.simulator.snapshot()).persistentInkSegmentCount == 0)
    #expect(restored.acceptedRevisionID != saved.registration.acceptedRevisionID)
    let revalidationEvidenceID = try #require(restored.revalidationEvidence?.id)
    #expect(
      restored.derivation
        == TipRegistrationDerivation.checkpointRevalidated(
          fromRevision: saved.registration.acceptedRevisionID,
          evidenceID: revalidationEvidenceID
        ))
    #expect(
      restarted.workspace.testCurrentLearningPathItemID
        == LearningPathItemID.observedDrawingTrial(.chooseDrawingBorderPlan)
    )
    #expect(
      restored.estimatorRevision == SparseTipCircularMarkPlan.registrationEstimatorRevision
    )
    let drawingOwner = LearningPathItemID.observedDrawingTrial(.chooseDrawingBorderPlan)
    try requireEnabledPublicAction(
      .start,
      owner: drawingOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(.start, for: drawingOwner)
    let domain = restored.applicabilityRectangle
    #expect(
      restarted.workspace.drawingBorderPlan?.strokes.first?.path.points.first
        == (try Point2(x: domain.minX, y: domain.minY)))

  }

  @Test("unchanged application reload restores the exact tip revision without calibration work")
  func softwareReloadRestoresAcceptedTipRevision() async throws {
    let harness = makeCausalSimulatorAppFixture()
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    try await completeSimulatedSparseTipCalibration(
      harness.workspace,
      simulator: harness.simulator
    )
    let accepted = try #require(harness.workspace.tipCameraRegistration)
    let checkpoint = try AcceptedTipCalibrationCheckpoint(
      registration: accepted,
      acceptanceEvent: TipCalibrationAcceptanceEvent(
        acceptedRevisionID: accepted.acceptedRevisionID,
        timestamp: accepted.acceptedAt,
        actor: "test fixture"
      )
    )
    let before = await harness.simulator.snapshot()

    try harness.workspace.simulateUnchangedApplicationTipReloadForTesting(checkpoint)

    #expect(harness.workspace.tipCameraRegistration == accepted)
    #expect(
      harness.workspace.learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
        == accepted.acceptedRevisionID
    )
    #expect(harness.workspace.recoverableTipCalibrationCheckpoint == nil)
    #expect(await harness.simulator.snapshot() == before)
  }

  @Test("Stage 2 consumes the exact accepted tip revision against nonzero simulator truth")
  func stageFourConsumesExactTipRevision() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: workspace,
      environment: .simulated
    )
    let truthOffset = await harness.simulator.capToTipPixelOffsetTruth()
    #expect(abs(truthOffset.dx) + abs(truthOffset.dy) > 0)
    try await completeSimulatedSparseTipCalibration(workspace, simulator: harness.simulator)

    let accepted = try #require(workspace.tipCameraRegistration)
    let acceptedBoundary = try SparseTipBatchMarkPlan.boundaryEnvelope(
      for: workspace.testAcceptedBoundaryAggregates
    )
    #expect(accepted.applicabilityRectangle == (try AxisAlignedBounds(
      minX: acceptedBoundary.minX + 10,
      minY: acceptedBoundary.minY + 10,
      maxX: acceptedBoundary.maxX - 10,
      maxY: acceptedBoundary.maxY - 10
    )))
    let tipRevision = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
    )
    #expect(workspace.tipCameraRegistration?.acceptedRevisionID == tipRevision)
    try await completeSimulatedStageFour(workspace)

    let observation = try #require(workspace.lastFrameObservation)
    let executionPlan = try #require(workspace.drawingBorderPlan)
    #expect(executionPlan.provenance.registrationRevisionID.rawValue == tipRevision.rawValue)
    #expect(executionPlan.drawableRegion.bounds == acceptedBoundary)
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 0.5)
    #expect(
      DrawingRegionContainmentPolicy.numericalEpsilonMM
        < MachinePositionAcceptancePolicy.toleranceMM
    )
    #expect(executionPlan.drawableRegion.contains(try Point2(
      x: acceptedBoundary.minX - DrawingRegionContainmentPolicy.numericalEpsilonMM,
      y: acceptedBoundary.minY
    )))
    #expect(!executionPlan.drawableRegion.contains(try Point2(
      x: acceptedBoundary.minX - (DrawingRegionContainmentPolicy.numericalEpsilonMM * 2),
      y: acceptedBoundary.minY
    )))
    let expectedBorder = try DrawingBorderPlan(
      bounds: SparseTipBatchMarkPlan.drawingBorderBounds(for: acceptedBoundary)
    )
    let plannedBorderPoints = try #require(executionPlan.strokes.first?.path.points)
    #expect(plannedBorderPoints.count == expectedBorder.pathPositions.count)
    #expect(zip(plannedBorderPoints, expectedBorder.pathPositions).allSatisfy {
      plannedPoint, expectedPosition in
      MachinePositionAcceptancePolicy.accepts(
        MachinePosition(point: plannedPoint),
        target: expectedPosition
      )
    })
    #expect(observation.evidence.frames.baseline.frameID != observation.evidence.frames.post.frameID)
    #expect(workspace.drawingTrialRevealPosition != nil)
    #expect(await harness.simulator.persistentInk().isEmpty == false)
    #expect(
      workspace.learningArtifactGraph.revisions.contains {
        guard $0.state == .current else { return false }
        if case .comparison = $0.kind { return true }
        return false
      })
  }
}
