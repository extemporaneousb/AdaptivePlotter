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

  @Test("five stationary marks select, fit, and accept one tip registration")
  func fullFiveMarkAcceptance() async throws {
    let checkpointBox = TipCheckpointBox()
    let harness = makeSimulatedHarness(
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

    // Deterministic in-frame affine clicks exercise workflow/model authority;
    // simulator rendering truth is tested separately from human perception.
    let clicks: [Point2<CameraPixelSpace>] = try [
      Point2(x: 160, y: 120),
      Point2(x: 20, y: 120),
      Point2(x: 160, y: 220),
      Point2(x: 300, y: 120),
      Point2(x: 160, y: 20),
    ]
    for (index, click) in clicks.enumerated() {
      try await performPublicAction(
        .createNextSparseTipMark,
        owner: tipOwner,
        workspace: workspace
      )
      let surface = workspace.actionSurfacePresentation
      let request = try #require(surface.pointSelectionRequest)
      workspace.selectToolContactPoint(ActionSurfacePointSelection(
        frame: request.frame,
        point: click,
        presentationTransformRevision: request.presentationTransformRevision
      ))
      try await performPublicAction(.acceptSparseTipMark, owner: tipOwner, workspace: workspace)
      #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.count == index + 1)
    }

    let proposal = try #require(
      workspace.proposedTipCameraRegistration,
      "proposal missing: \(workspace.explorationError ?? "no error")"
    )
    #expect(proposal.modelSelectionEvidence.fitObservationIDs.count == 3)
    #expect(proposal.modelSelectionEvidence.holdoutObservationIDs.count == 2)
    try await performPublicAction(.acceptTipCalibration, owner: tipOwner, workspace: workspace)
    #expect(workspace.tipCameraRegistration?.acceptedRevisionID == proposal.acceptedRevisionID)
    #expect(workspace.sparseTipCalibrationCoordinator.phase == .accepted)
    #expect(checkpointBox.checkpoint?.registration.acceptedRevisionID == proposal.acceptedRevisionID)
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

  @Test("re-click retains the exact frozen frame and emits no motion or ink")
  func frozenReClickNoRedraw() async throws {
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
    try await performPublicAction(.createNextSparseTipMark, owner: owner, workspace: workspace)
    let request = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)
    let frameID = request.frame.frameID
    let before = await harness.runtime.snapshot()
    workspace.selectToolContactPoint(ActionSurfacePointSelection(
      frame: request.frame,
      point: try Point2(x: 160, y: 120),
      presentationTransformRevision: request.presentationTransformRevision
    ))
    try await performPublicAction(.reClickSparseTipFrame, owner: owner, workspace: workspace)
    let after = await harness.runtime.snapshot()
    let reClickRequest = try #require(workspace.actionSurfacePresentation.pointSelectionRequest)

    #expect(reClickRequest.frame.frameID == frameID)
    #expect(after.mpos == before.mpos)
    #expect(after.persistentInkSegmentCount == before.persistentInkSegmentCount)
    #expect(after.currentOperation == nil)
  }

  @Test("quarantined checkpoint revalidates after restart without another tap")
  func checkpointRevalidationRestoresWithoutAnotherTap() async throws {
    let checkpointBox = TipCheckpointBox()
    let checkpointActions = OperatorWorkspace.AcceptedTipCalibrationCheckpointActions(
      load: { checkpointBox.load() },
      save: { checkpointBox.save($0) },
      clear: { checkpointBox.clear() }
    )
    let identities = TipCalibrationSemanticIdentityState(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
    let initial = makeSimulatedHarness(
      tipCheckpointActions: checkpointActions,
      tipCalibrationSemanticIdentities: identities
    )
    try await completeSimulatedBoundariesAndCenter(
      initial.workspace,
      runtime: initial.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(
      initial.workspace,
      runtime: initial.runtime
    )
    let saved = try #require(checkpointBox.checkpoint)
    #expect((await initial.runtime.snapshot()).persistentInkSegmentCount == 5)

    let restarted = makeSimulatedHarness(
      tipCheckpointActions: checkpointActions,
      tipCalibrationSemanticIdentities: identities
    )
    try await completeSimulatedBoundariesAndCenter(
      restarted.workspace,
      runtime: restarted.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
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

    let replacementPaper = PaperContactPlaneRevision()
    let changedPaperIdentities = TipCalibrationSemanticIdentityState(
      machineGeometry: identities.machineGeometry,
      toolAssembly: identities.toolAssembly,
      penContactProfile: identities.penContactProfile,
      paperContactPlane: replacementPaper,
      cameraMountRevision: identities.cameraMountRevision,
      cameraReframingRevision: identities.cameraReframingRevision
    )
    let changedPaper = makeSimulatedHarness(
      tipCheckpointActions: checkpointActions,
      tipCalibrationSemanticIdentities: changedPaperIdentities
    )
    try await completeSimulatedBoundariesAndCenter(
      changedPaper.workspace,
      runtime: changedPaper.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: cameraOwner,
      workspace: changedPaper.workspace
    )
    try await performPublicAction(
      .acceptCameraCalibrationProposal,
      owner: cameraOwner,
      workspace: changedPaper.workspace
    )
    try await performPublicAction(.start, owner: tipOwner, workspace: changedPaper.workspace)
    try await performPublicAction(
      .createNextSparseTipMark,
      owner: tipOwner,
      workspace: changedPaper.workspace
    )
    let request = try #require(changedPaper.workspace.actionSurfacePresentation.pointSelectionRequest)
    let registration = try #require(changedPaper.workspace.machineCameraRegistration)
    let center = try #require(changedPaper.workspace.cameraCalibrationReferencePosition)
    let representativeBoundary = try #require(
      changedPaper.workspace.boundarySideAggregates.values.first
    )
    let plan = try CurrentCameraCalibrationPlan(
      targetPosition: center,
      boundarySideAggregates: changedPaper.workspace.boundarySideAggregates,
      controllerSessionID: representativeBoundary.controllerSessionID,
      coordinateRevision: representativeBoundary.coordinateRevision
    )
    let sample = try #require(plan.samples.first { $0.position == .center })
    let cap = try registration.fit.cameraPoint(from: sample.machinePosition.point)
    let truth = try cap.translated(by: await changedPaper.runtime.capToTipPixelOffsetTruth())
    changedPaper.workspace.selectToolContactPoint(ActionSurfacePointSelection(
      frame: request.frame,
      point: truth,
      presentationTransformRevision: request.presentationTransformRevision
    ))
    let review = try #require(
      changedPaper.workspace.actionSurfacePresentation.tipPresentation.reviewGeometry
    )
    #expect(review.click == truth)
    #expect(review.prediction != nil)
    #expect(review.residual != nil)
    try await performPublicAction(
      .acceptSparseTipMark,
      owner: tipOwner,
      workspace: changedPaper.workspace
    )
    let contactPlaneRestored = try #require(
      changedPaper.workspace.tipCameraRegistration,
      "contact-plane restore error: \(changedPaper.workspace.explorationError ?? "none")"
    )
    #expect((await changedPaper.runtime.snapshot()).persistentInkSegmentCount == 1)
    #expect(contactPlaneRestored.applicability.paperContactPlane == replacementPaper)
    #expect(
      contactPlaneRestored.revalidationEvidence?.contactPlaneRevalidation != nil
    )
    #expect(
      changedPaper.workspace.currentLearningPathItemID
        == LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    )
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
    #expect(
      workspace.completedExplorationEpisodes.last?.observedLineObservation?
        .tipRegistrationRevisionID == tipRevision
    )
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
