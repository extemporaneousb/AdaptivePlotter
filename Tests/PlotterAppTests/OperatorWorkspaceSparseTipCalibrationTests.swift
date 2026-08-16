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

    let outsideTolerance = try MachinePosition(x: current.point.x + 0.051, y: current.point.y)
    let travelDelta = try OperatorWorkspace.supervisedTravelDelta(
      from: current,
      to: outsideTolerance
    )
    let requiredDelta = try #require(travelDelta)
    #expect(abs(requiredDelta.dx - 0.051) < 1e-12)
    #expect(requiredDelta.dy == 0)
  }

  @Test("five SIMULATED circle centers accept in memory without writing LIVE authority")
  func fullFiveMarkAcceptance() async throws {
    let machineCheckpointBox = CheckpointBox()
    let checkpointBox = TipCheckpointBox()
    let harness = makeSimulatedHarness(
      checkpointActions: .init(
        load: { machineCheckpointBox.load() },
        save: { machineCheckpointBox.save($0) },
        clear: { machineCheckpointBox.clear() }
      ),
      tipCheckpointActions: .init(
        load: { checkpointBox.load() },
        save: { checkpointBox.save($0) },
        clear: { checkpointBox.clear() }
      )
    )
    try await completeSimulatedBoundariesAndCenter(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    let workspace = harness.workspace
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    try await performPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    try await performPublicAction(.start, owner: tipOwner, workspace: workspace)

    try await performPublicAction(
      .drawFiveSparseTipCircles,
      owner: tipOwner,
      workspace: workspace
    )
    let surface = workspace.actionSurfacePresentation
    let request = try #require(surface.pointSelectionRequest)
    #expect(surface.viewportContext?.preferredInitialZoom == 0)
    #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == 80)
    let registration = try #require(workspace.machineCameraRegistration)
    let center = try #require(workspace.cameraCalibrationReferencePosition)
    let truthOffset = await harness.runtime.capToTipPixelOffsetTruth()
    let batch = try SparseTipBatchMarkPlan(
      center: center,
      boundarySideAggregates: workspace.boundarySideAggregates
    )
    let clicks = try batch.marks.map {
      try registration.fit.cameraPoint(from: $0.machinePosition.point)
        .translated(by: truthOffset)
    }
    for click in [clicks[3], clicks[1], clicks[4], clicks[0], clicks[2]] {
      workspace.selectToolContactPoint(ActionSurfacePointSelection(
        frame: request.frame,
        point: click,
        presentationTransformRevision: request.presentationTransformRevision
      ))
    }
    #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.count == 5)
    let observations = workspace.sparseTipCalibrationCoordinator.acceptedObservations.map(
      \.observation
    )
    let revealFrameIDs = Set(observations.map { $0.revealEvidence.frame.frameID })
    #expect(revealFrameIDs.count == 1)
    #expect(Set(observations.map(\.revealEvidence)).count == 1)
    #expect(Set(observations.map(\.attemptID)).count == 1)
    #expect(Set(observations.map(\.operationID)).count == 5)
    #expect(Set(observations.map { $0.preMarkFrame.frameID }).count == 5)
    #expect(observations.map(\.intendedMarkPosition) == batch.marks.map(\.machinePosition))
    for observation in observations {
      #expect(observation.markGeometry.radiusMM == 2)
      #expect(observation.markGeometry.chordCount == 16)
      #expect(observation.markGeometry.maximumFeedMMPerMinute == 100)
      #expect(observation.penDown.outcome == .commandedAndSettled(
        command: .lower,
        commandedState: .down
      ))
      #expect(observation.penUp.outcome == .commandedAndSettled(
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
    #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == 80)

    let proposal = try #require(
      workspace.proposedTipCameraRegistration,
      "proposal missing: \(workspace.explorationError ?? "no error")"
    )
    #expect(proposal.modelForm == .directAffine)
    #expect(proposal.modelSelectionEvidence.observationIDs.count == 5)
    try await performPublicAction(.acceptTipCalibration, owner: tipOwner, workspace: workspace)
    #expect(workspace.tipCameraRegistration?.acceptedRevisionID == proposal.acceptedRevisionID)
    #expect(workspace.sparseTipCalibrationCoordinator.phase == .accepted)
    #expect(
      workspace.currentLearningPathItemID
        == .observedDrawingTrial(.chooseIsolatedLinePlan)
    )
    #expect(checkpointBox.checkpoint == nil)
    #expect(checkpointBox.operationCounts.loads == 1)
    #expect(checkpointBox.operationCounts.saves == 0)
    #expect(checkpointBox.operationCounts.clears == 0)
    #expect(machineCheckpointBox.checkpoint == nil)
    #expect(machineCheckpointBox.operationCounts.loads == 1)
    #expect(machineCheckpointBox.operationCounts.saves == 0)
    #expect(machineCheckpointBox.operationCounts.clears == 0)
  }

  @Test("five-cap acceptance advances directly to sparse marks")
  func fiveCapAcceptance() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedBoundariesAndCenter(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    #expect(workspace.currentLearningPathItemID == owner)
    #expect(workspace.actionSurfacePresentation.tipPresentation.statusText == "Tip not calibrated")

    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: owner,
      workspace: workspace
    )
    let proposal = try #require(workspace.proposedMachineCameraRegistration)
    #expect(proposal.fitCorrespondenceProvenance.count == 3)
    #expect(proposal.holdoutCorrespondenceProvenance.count == 2)
    #expect(proposal.fit.correspondences.count == 5)
    #expect(proposal.opticalConfiguration.source == .simulated)
    #expect(proposal.applicabilityDerivation == .boundaryEnvelopeInsetAndSymmetricallyReduced(
      safetyMarginMM: 10,
      maximumHalfSpanMM: 30
    ))
    try await performPublicAction(.acceptCameraCalibrationProposal, owner: owner, workspace: workspace)
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )
  }

  @Test("same-frame click correction emits no motion, capture, or additional ink")
  func frozenClickCorrectionNoRedraw() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedBoundariesAndCenter(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    let workspace = harness.workspace
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    try await performPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: workspace
    )

    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    try await performPublicAction(.start, owner: owner, workspace: workspace)
    try await performPublicAction(.drawFiveSparseTipCircles, owner: owner, workspace: workspace)
    let request = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)
    let frameID = request.frame.frameID
    let before = await harness.runtime.snapshot()
    workspace.selectToolContactPoint(ActionSurfacePointSelection(
      frame: request.frame,
      point: try Point2(x: 160, y: 120),
      presentationTransformRevision: request.presentationTransformRevision
    ))
    try await performPublicAction(.undoLastSparseTipClick, owner: owner, workspace: workspace)
    let after = await harness.runtime.snapshot()
    let correctedRequest = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)

    #expect(correctedRequest.frame.frameID == frameID)
    #expect(workspace.frozenToolContactSelectionFrame?.frame.id == frameID)
    #expect(workspace.selectedToolContactPoints.isEmpty)
    #expect(after.mpos == before.mpos)
    #expect(after.persistentInkSegmentCount == before.persistentInkSegmentCount)
    #expect(after.currentOperation == nil)
  }

  @Test("stopping a circle blacklists its center and never redraws it")
  func stoppedCircleBlacklistsWithoutRedraw() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedBoundariesAndCenter(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    let workspace = harness.workspace
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    try await performPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: workspace
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    try await performPublicAction(.start, owner: owner, workspace: workspace)
    let pacing = CalibrationStopPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)

    let markTask = Task {
      await workspace.performExerciseAction(.drawFiveSparseTipCircles, for: owner)
    }
    await pacing.waitUntilSuspended()
    await pacing.resume()
    try await waitUntil {
      workspace.contextualStopPresentation?.detail.contains("calibration circle") == true
    }
    let capability = try #require(workspace.contextualStopPresentation?.capabilityID)
    let stopTask = Task { await workspace.stopCurrentOperation(capabilityID: capability) }
    try await waitUntilAsync { (await harness.runtime.snapshot()).currentOperation == nil }
    await pacing.resume()
    await stopTask.value
    await markTask.value

    #expect(workspace.sparseTipCalibrationCoordinator.blacklistedPositions == [.center])
    #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.isEmpty)
    #expect(workspace.actionSurfacePresentation.pointSelectionRequest == nil)
    #expect(workspace.contextualStopPresentation == nil)
    #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == 0)
    if case .possibleInkBlacklisted(let location, _) =
      workspace.sparseTipCalibrationCoordinator.phase
    {
      #expect(location.machinePosition == (try MachinePosition(x: 0, y: 0)))
      #expect(location.markRadiusMM == 2)
    } else {
      Issue.record("Stopped circle did not retain terminal possible-ink state")
    }
  }

  @Test("quarantined checkpoint revalidates after restart without another mark")
  func checkpointRevalidationRestoresWithoutAnotherMark() async throws {
    let identities = TipCalibrationSemanticIdentityState(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
    let initial = makeSimulatedHarness(tipCalibrationSemanticIdentities: identities)
    try await completeSimulatedBoundariesAndCenter(
      initial.workspace,
      runtime: initial.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(
      initial.workspace,
      runtime: initial.runtime
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
    #expect((await initial.runtime.snapshot()).persistentInkSegmentCount == 80)

    let restarted = makeSimulatedHarness(tipCalibrationSemanticIdentities: identities)
    try await completeSimulatedBoundariesAndCenter(
      restarted.workspace,
      runtime: restarted.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    restarted.workspace.replaceSimulatedTipCalibrationCheckpointForTesting(saved)
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: restarted.workspace
    )
    try await performPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: restarted.workspace
    )
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    #expect((await restarted.runtime.snapshot()).persistentInkSegmentCount == 0)
    try await performPublicAction(
      .revalidateTipCalibrationCheckpoint,
      owner: tipOwner,
      workspace: restarted.workspace
    )

    let restored = try #require(
      restarted.workspace.tipCameraRegistration,
      "restore error: \(restarted.workspace.explorationError ?? "none")"
    )
    #expect((await restarted.runtime.snapshot()).persistentInkSegmentCount == 0)
    #expect(restored.acceptedRevisionID != saved.registration.acceptedRevisionID)
    let revalidationEvidenceID = try #require(restored.revalidationEvidence?.id)
    #expect(restored.derivation == TipRegistrationDerivation.checkpointRevalidated(
      fromRevision: saved.registration.acceptedRevisionID,
      evidenceID: revalidationEvidenceID
    ))
    #expect(
      restarted.workspace.currentLearningPathItemID
        == LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    )
    #expect(
      restored.estimatorRevision == SparseTipCircularMarkPlan.registrationEstimatorRevision
    )
    try await performPublicAction(
      .chooseIsolatedLinePlan(.positiveX),
      owner: .observedDrawingTrial(.chooseIsolatedLinePlan),
      workspace: restarted.workspace
    )
    let domain = restored.applicabilityRectangle
    #expect(restarted.workspace.drawingTrialLineStart == (try MachinePosition(
      x: (domain.minX + domain.maxX) / 2 - 2.5,
      y: (domain.minY + domain.maxY) / 2 + (domain.maxY - domain.minY) * 0.25
    )))

  }

  @Test("Stage 4 consumes the exact accepted tip revision against nonzero simulator truth")
  func stageFourConsumesExactTipRevision() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    let truthOffset = await harness.runtime.capToTipPixelOffsetTruth()
    #expect(abs(truthOffset.dx) + abs(truthOffset.dy) > 0)
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)

    let tipRevision = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
    )
    #expect(workspace.tipCameraRegistration?.acceptedRevisionID == tipRevision)
    try await completeSimulatedStageFour(workspace)

    let observation = try #require(workspace.lastInkObservation)
    #expect(observation.tipRegistrationRevisionID == tipRevision)
    #expect(observation.localPreLineBaseline.frameID != observation.postLine.frameID)
    #expect(workspace.drawingTrialRevealPosition != nil)
    #expect(await harness.runtime.persistentInk().isEmpty == false)
    #expect(workspace.learningArtifactGraph.revisions.contains {
      guard $0.state == .current else { return false }
      if case .comparison = $0.kind { return true }
      return false
    })
  }
}
