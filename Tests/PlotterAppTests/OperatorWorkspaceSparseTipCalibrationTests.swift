import Foundation
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@MainActor
@Suite("Operator workspace sparse tip calibration")
struct OperatorWorkspaceSparseTipCalibrationTests {
  @Test("rejected surface safety history is actionable only through Paper Replacement")
  func rejectedSurfaceStoreRoutesRecoveryNotice() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let surface = LearningSurfaceExposureBox(
      rejectedReason: "injected corrupt surface safety history"
    )
    let workspace = workspace(
      machine: machine,
      manifestActions: LearningAuthorityManifestBox().actions,
      surfaceExposureActions: surface.actions,
      log: log
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )

    #expect(
      workspace.learningSurfaceExposureError?.contains("injected corrupt surface") == true
    )
    #expect(
      workspace.currentOperatorNoticeMessage?.contains("injected corrupt surface") == true
    )
    #expect(
      workspace.selectedOperatorActionPresentation(for: owner)
        .actionStrip?.actions.map(\.kind) == [.paperReplaced]
    )

    try await performPublicAction(.paperReplaced, owner: owner, workspace: workspace)

    #expect(workspace.learningSurfaceExposureError == nil)
    #expect(surface.operationCounts.recoveries == 1)
  }

  @Test("rejected LIVE authority manifest blocks sparse contact before any workflow effect")
  func rejectedManifestPreflightsSparseContact() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let camera = try CameraFixture()
    let surface = LearningSurfaceExposureBox()
    let corruptRevision = LearningAuthorityStoreRevision.corrupt(
      fileSHA256: RunLedger.sha256Hex(Data("corrupt manifest".utf8))
    )
    let manifestActions = OperatorWorkspace.LearningAuthorityManifestActions(
      load: {
        .rejected(
          reason: "injected corrupt manifest",
          revision: corruptRevision
        )
      },
      commit: { _, _ in
        throw LearningAuthorityManifestBoxError.injectedCommitFailure
      }
    )
    let workspace = workspace(
      machine: machine,
      camera: camera,
      manifestActions: manifestActions,
      surfaceExposureActions: surface.actions,
      log: log
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    let cameraCalls = camera.inspectionCallCount
    let surfaceCounts = surface.operationCounts
    let machineEvents = await log.values

    // This fresh workspace is still at 3.1, so 3.4 is a future review row and
    // exposes no executable strip. The pure projector test covers the disabled
    // Start descriptor once 3.4 is current; these calls exercise runtime
    // defense in depth even when invoked directly.
    #expect(workspace.selectedOperatorActionPresentation(for: owner).actionStrip == nil)
    #expect(workspace.learningAuthorityManifestError?.contains("injected corrupt manifest") == true)
    #expect(
      workspace.currentOperatorNoticeMessage?.contains("injected corrupt manifest") == true
    )

    await workspace.performExerciseAction(.start, for: owner)
    await workspace.performExerciseAction(.createNextSparseTipMark, for: owner)

    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.learningSurfaceExposureLedger.entries.isEmpty)
    #expect(camera.inspectionCallCount == cameraCalls)
    #expect(surface.operationCounts.saves == surfaceCounts.saves)
    #expect(await log.values == machineEvents)
  }

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
    let manifestBox = LearningAuthorityManifestBox()
    let harness = makeSimulatedHarness(
      manifestActions: manifestBox.actions
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
      #expect(surface.viewportContext?.fittedRegion?.width == max(96, request.frame.width / 3))
      #expect(surface.viewportContext?.fittedRegion?.height == max(96, request.frame.height / 3))
      workspace.selectToolContactPoint(ActionSurfacePointSelection(
        frame: request.frame,
        point: click,
        presentationTransformRevision: request.presentationTransformRevision
      ))
      try await performPublicAction(.acceptSparseTipMark, owner: tipOwner, workspace: workspace)
      #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.count == index + 1)
      let observation = try #require(
        workspace.sparseTipCalibrationCoordinator.acceptedObservations.last?.observation
      )
      #expect(observation.markGeometry.radiusMM == 2)
      #expect(observation.markGeometry.chordCount == 16)
      #expect(observation.markGeometry.maximumFeedMMPerMinute == 100)
      #expect(observation.penDown.outcome == .commandedAndSettled(
        command: .lower,
        commandedState: .down
      ))
      let reveal = observation.revealEvidence.actualSettledPosition.point
      let expectedRevealX =
        try #require(workspace.boundarySideAggregates[.positiveX]).estimateMM
        - CurrentCameraCalibrationPlan.safetyMarginMM
      let safeMinY =
        try #require(workspace.boundarySideAggregates[.negativeY]).estimateMM
        + CurrentCameraCalibrationPlan.safetyMarginMM
      let safeMaxY =
        try #require(workspace.boundarySideAggregates[.positiveY]).estimateMM
        - CurrentCameraCalibrationPlan.safetyMarginMM
      let expectedRevealY = min(max(0, safeMinY), safeMaxY)
      #expect(abs(reveal.x - expectedRevealX) < 1e-9)
      #expect(abs(reveal.y - expectedRevealY) < 1e-9)
      #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == (index + 1) * 16)
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
    #expect(manifestBox.checkpoint == nil)
    #expect(manifestBox.tipCheckpoint == nil)
    #expect(manifestBox.operationCounts.loads == 1)
    #expect(manifestBox.operationCounts.commits == 0)
    #expect(
      workspace.selectedOperatorActionPresentation(for: tipOwner)
        .actionStrip?.actions.map(\.kind) == [.paperReplaced]
    )
    let beforeRejectedRedo = await harness.runtime.snapshot()
    await workspace.performExerciseAction(.redoThisStep, for: tipOwner)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(await harness.runtime.snapshot() == beforeRejectedRedo)

    try await performPublicAction(.paperReplaced, owner: tipOwner, workspace: workspace)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.sparseTipCalibrationCoordinator.phase == .idle)
    #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == 0)
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )
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

  @Test("Camera Redo rejection preserves accepted authority and ends the attempt")
  func cameraRedoRejectPreservesAcceptedFallback() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedBoundariesAndCenter(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .acceptCameraCalibrationProposal,
      owner: owner,
      workspace: workspace
    )
    let acceptedRegistration = try #require(workspace.machineCameraRegistration)
    let acceptedRevision = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration)
    )

    await workspace.performExerciseAction(.redoThisStep, for: owner)
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: owner,
      workspace: workspace
    )
    #expect(workspace.proposedMachineCameraRegistration != nil)
    #expect(workspace.machineCameraRegistration == acceptedRegistration)
    try await performPublicAction(
      .rejectCameraCalibrationProposal,
      owner: owner,
      workspace: workspace
    )

    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.proposedMachineCameraRegistration == nil)
    #expect(workspace.cameraCalibrationAnchorFrame == nil)
    #expect(workspace.cameraCalibrationReferencePosition == nil)
    #expect(workspace.cameraCalibrationReferenceCapAnchor == nil)
    #expect(workspace.machineCameraRegistration == acceptedRegistration)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration)?.id
        == acceptedRevision.id
    )
  }

  @Test("initial Camera rejection accepts no registration and ends the attempt")
  func initialCameraRejectLeavesNoAuthority() async throws {
    let harness = makeSimulatedHarness()
    try await completeSimulatedBoundariesAndCenter(
      harness.workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try await performPublicAction(
      .runCameraCalibrationAndBuildProposal,
      owner: owner,
      workspace: workspace
    )
    try await performPublicAction(
      .rejectCameraCalibrationProposal,
      owner: owner,
      workspace: workspace
    )

    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.proposedMachineCameraRegistration == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .machineCameraRegistration) == nil
    )
    #expect(workspace.currentLearningPathItemID == owner)
  }

  @Test("LIVE circle finalizer save failure raises once and accepts no observation")
  func liveCircleFinalizerFailureBlocksAuthority() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: Vector2(dx: 0, dy: 0)
    )
    let camera = try CameraFixture(frameWidth: 320, frameHeight: 240)
    let surfaceStore = LearningSurfaceExposureBox()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(camera, machinePositionFrom: machine),
      surfaceExposureActions: surfaceStore.actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(
      .moveToEstimatedCenter,
      owner: boundaryOwner,
      workspace: workspace
    )
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
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
    let penRequestsBefore = await machine.requestedPenCommands.count
    surfaceStore.injectSaveFailure(afterSuccessfulSaves: 1)

    try await performPublicAction(
      .createNextSparseTipMark,
      owner: tipOwner,
      workspace: workspace
    )

    #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.isEmpty)
    #expect(workspace.learningSurfaceExposureLedger.entries.count == 1)
    #expect(workspace.learningSurfaceExposureLedger.entries.first?.penUpFinalization == nil)
    #expect(surfaceStore.operationCounts.saves == 2)
    let newPenRequests = Array((await machine.requestedPenCommands).dropFirst(penRequestsBefore))
    #expect(newPenRequests == [.lower, .raise])
    #expect(workspace.learningSurfaceExposureError?.contains("injectedSaveFailure") == true)
    #expect(
      workspace.explorationError?.contains("not durable") == true,
      "actual exploration error: \(workspace.explorationError ?? "nil")"
    )

    await workspace.performExerciseAction(.createNextSparseTipMark, for: tipOwner)
    #expect(await machine.requestedPenCommands.count == penRequestsBefore + 2)
    #expect(surfaceStore.operationCounts.saves == 2)
  }

  @Test("LIVE line finalizer save failure retains exposure and never redraws")
  func liveLineFinalizerFailureBlocksAuthorityAndRetry() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: Vector2(dx: 0, dy: 0)
    )
    let camera = try CameraFixture(frameWidth: 320, frameHeight: 240)
    let surfaceStore = LearningSurfaceExposureBox()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(camera, machinePositionFrom: machine),
      surfaceExposureActions: surfaceStore.actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(
      .moveToEstimatedCenter,
      owner: boundaryOwner,
      workspace: workspace
    )
    try await completeLiveSparseTipCalibration(workspace)

    let planOwner = LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    try await performPublicAction(
      .chooseIsolatedLinePlan(.positiveX),
      owner: planOwner,
      workspace: workspace
    )
    try await performPublicAction(
      .captureLocalPreLineBaseline,
      owner: .observedDrawingTrial(.captureLocalPreLineBaseline),
      workspace: workspace
    )
    try await performPublicAction(
      .moveToLineStart,
      owner: .observedDrawingTrial(.moveToLineStart),
      workspace: workspace
    )

    let drawOwner = LearningPathItemID.observedDrawingTrial(.drawIsolatedLine)
    let penRequestsBefore = await machine.requestedPenCommands.count
    let motionRequestsBefore = await machine.requestedFeeds.count
    let drawingRequestsBefore = await machine.requestedDrawingStrokes.count
    let cameraRequestsBefore = camera.inspectionCallCount
    let savesBefore = surfaceStore.operationCounts.saves
    surfaceStore.injectSaveFailure(afterSuccessfulSaves: 1)

    try await performPublicAction(.drawIsolatedLine, owner: drawOwner, workspace: workspace)

    #expect(workspace.currentDrawingTrialGroupHasExposure)
    #expect(
      workspace.learningArtifactGraph.revisions.contains {
        guard $0.state == .current else { return false }
        if case .lineExecution = $0.kind { return true }
        return false
      } == false
    )
    let lineExposure = try #require(
      workspace.learningSurfaceExposureLedger.entries.last,
      "missing retained line reservation"
    )
    if case .drawingTrial = lineExposure.owner {
      #expect(lineExposure.penUpFinalization == nil)
    } else {
      Issue.record("The retained exposure was not the isolated-line reservation")
    }
    #expect(surfaceStore.operationCounts.saves == savesBefore + 2)
    let newPenRequests = Array((await machine.requestedPenCommands).dropFirst(penRequestsBefore))
    #expect(newPenRequests == [.lower, .raise])
    #expect(await machine.requestedDrawingStrokes.count == drawingRequestsBefore + 1)
    #expect(workspace.learningSurfaceExposureError?.contains("injectedSaveFailure") == true)
    #expect(
      workspace.explorationError?.contains("not durable") == true,
      "actual line exploration error: \(workspace.explorationError ?? "nil")"
    )

    await workspace.performExerciseAction(.drawIsolatedLine, for: drawOwner)
    #expect(await machine.requestedPenCommands.count == penRequestsBefore + 2)
    #expect(await machine.requestedFeeds.count == motionRequestsBefore + 1)
    #expect(await machine.requestedDrawingStrokes.count == drawingRequestsBefore + 1)
    #expect(camera.inspectionCallCount == cameraRequestsBefore)
    #expect(surfaceStore.operationCounts.saves == savesBefore + 2)

    let invalidation = try #require(workspace.learningInvalidationPlan(for: drawOwner))
    #expect(!invalidation.expectedCurrentRevisionIDs.isEmpty)
    #expect(
      invalidation.affectedItemIDs.contains(
        .observedDrawingTrial(.chooseIsolatedLinePlan)
      )
    )
    #expect(workspace.performLearningInvalidation(invalidation))
    #expect(
      workspace.currentLearningPathItemID
        == .observedDrawingTrial(.chooseIsolatedLinePlan)
    )
    #expect(!workspace.currentDrawingTrialGroupHasExposure)
    #expect(await machine.requestedPenCommands.count == penRequestsBefore + 2)
    #expect(await machine.requestedFeeds.count == motionRequestsBefore + 1)
    #expect(await machine.requestedDrawingStrokes.count == drawingRequestsBefore + 1)
    #expect(camera.inspectionCallCount == cameraRequestsBefore)
    #expect(surfaceStore.operationCounts.saves == savesBefore + 2)
  }

  @Test("LIVE Paper Replacement failure converges manifest and memory to no tip authority")
  func livePaperReplacementFailureClearsTipAuthoritySafely() async throws {
    let log = EventLog()
    let machine = try MachineFixture(
      log: log,
      relativeJogSettlementOffset: Vector2(dx: 0, dy: 0)
    )
    let camera = try CameraFixture(frameWidth: 320, frameHeight: 240)
    let manifest = LearningAuthorityManifestBox()
    let surfaceStore = LearningSurfaceExposureBox()
    let workspace = workspace(
      machine: machine,
      cameraActionsOverride: cameraActions(camera, machinePositionFrom: machine),
      manifestActions: manifest.actions,
      surfaceExposureActions: surfaceStore.actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    try await completeLiveBoundaries(workspace, machine: machine)
    try await performPublicAction(
      .moveToEstimatedCenter,
      owner: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      workspace: workspace
    )
    try await completeLiveSparseTipCalibration(workspace)
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    #expect(manifest.tipCheckpoint != nil)
    #expect(workspace.tipCameraRegistration != nil)
    #expect(
      workspace.selectedOperatorActionPresentation(for: tipOwner)
        .actionStrip?.actions.map(\.kind) == [.paperReplaced]
    )
    let penCount = await machine.requestedPenCommands.count
    let motionCount = await machine.requestedFeeds.count
    let drawingCount = await machine.requestedDrawingStrokes.count
    let cameraCount = camera.inspectionCallCount
    let exposureCount = workspace.learningSurfaceExposureLedger.entries.count
    let savesBefore = surfaceStore.operationCounts.saves
    let paperBefore = surfaceStore.paper
    surfaceStore.injectSaveFailure()

    try await performPublicAction(.paperReplaced, owner: tipOwner, workspace: workspace)

    #expect(manifest.tipCheckpoint == nil)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .tipCameraRegistration) == nil
    )
    #expect(
      workspace.currentLearningPathItemID
        == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )
    #expect(
      workspace.learningSurfaceExposureRecoveryDisposition == .diagnosticsRequired
    )
    #expect(workspace.learningSurfaceExposureError?.contains("injectedSaveFailure") == true)
    #expect(surfaceStore.operationCounts.saves == savesBefore + 1)
    #expect(surfaceStore.paper == paperBefore)
    #expect(workspace.learningSurfaceExposureLedger.entries.count == exposureCount)
    #expect(await machine.requestedPenCommands.count == penCount)
    #expect(await machine.requestedFeeds.count == motionCount)
    #expect(await machine.requestedDrawingStrokes.count == drawingCount)
    #expect(camera.inspectionCallCount == cameraCount)
    let blocked = try #require(
      workspace.selectedOperatorActionPresentation(for: tipOwner)
        .actionStrip?.actions.first
    )
    #expect(blocked.kind == .start)
    #expect(!blocked.isEnabled)
    #expect(blocked.unavailableReason?.contains("surface-exposure ledger") == true)
  }

  @Test("re-click retains the exact frozen frame and emits no motion or additional ink")
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
    #expect(workspace.frozenToolContactSelectionFrame?.frame.id == frameID)
    #expect(workspace.selectedToolContactPoint == nil)
    #expect(after.mpos == before.mpos)
    #expect(after.persistentInkSegmentCount == before.persistentInkSegmentCount)
    #expect(after.currentOperation == nil)
  }

  @Test("stopping a circle retains its center exposure and never redraws it")
  func stoppedCircleRetainsExposureWithoutRedraw() async throws {
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
      await workspace.performExerciseAction(.createNextSparseTipMark, for: owner)
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

    #expect(workspace.learningSurfaceExposureLedger.entries.count == 1)
    #expect(workspace.sparseTipCalibrationCoordinator.acceptedObservations.isEmpty)
    #expect(workspace.actionSurfacePresentation.pointSelectionRequest == nil)
    #expect(workspace.contextualStopPresentation == nil)
    #expect((await harness.runtime.snapshot()).persistentInkSegmentCount == 0)
    if case .possibleInkExposureRetained(let exposure, _) =
      workspace.sparseTipCalibrationCoordinator.phase
    {
      #expect(exposure.owner == .sparseTipMark(.center))
      #expect(
        exposure.geometry
          == .sparseCalibrationCircle(
            center: try MachinePosition(x: 0, y: 0),
            radiusMM: 2
          )
      )
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
      ),
      surfaceExposures: initial.workspace.learningSurfaceExposureLedger.entries
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
      tipCalibrationSemanticIdentities: changedPaperIdentities
    )
    try await completeSimulatedBoundariesAndCenter(
      changedPaper.workspace,
      runtime: changedPaper.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    changedPaper.workspace.replaceSimulatedTipCalibrationCheckpointForTesting(saved)
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
    #expect((await changedPaper.runtime.snapshot()).persistentInkSegmentCount == 16)
    #expect(contactPlaneRestored.applicability.paperContactPlane == replacementPaper)
    #expect(
      contactPlaneRestored.revalidationEvidence?.contactPlaneRevalidation != nil
    )
    #expect(
      changedPaper.workspace.currentLearningPathItemID
        == LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    )
  }

  @Test("restart blocks a tip checkpoint whose sparse safety history is absent or incomplete")
  func checkpointRequiresCompleteSurfaceSafetyHistory() async throws {
    let identities = TipCalibrationSemanticIdentityState(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
    let seeded = makeSimulatedHarness(tipCalibrationSemanticIdentities: identities)
    try await completeSimulatedBoundariesAndCenter(
      seeded.workspace,
      runtime: seeded.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(
      seeded.workspace,
      runtime: seeded.runtime
    )
    let registration = try #require(seeded.workspace.tipCameraRegistration)
    let checkpoint = try AcceptedTipCalibrationCheckpoint(
      registration: registration,
      acceptanceEvent: TipCalibrationAcceptanceEvent(
        acceptedRevisionID: registration.acceptedRevisionID,
        timestamp: registration.acceptedAt,
        actor: "test fixture"
      ),
      surfaceExposures: seeded.workspace.learningSurfaceExposureLedger.entries
    )
    let manifest = LearningAuthorityManifestBox(tip: checkpoint)

    let absent = makeSimulatedHarness(
      manifestActions: manifest.actions,
      surfaceExposureActions: LearningSurfaceExposureBox().actions,
      tipCalibrationSemanticIdentities: identities
    )
    #expect(absent.workspace.learningSurfaceExposureError?.contains("not cross-bound") == true)
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    #expect(
      absent.workspace.selectedOperatorActionPresentation(for: tipOwner)
        .actionStrip?.actions.map(\.kind) == [.paperReplaced]
    )
    try await performPublicAction(
      .paperReplaced,
      owner: tipOwner,
      workspace: absent.workspace
    )
    #expect(manifest.tipCheckpoint == nil)
    #expect(absent.workspace.learningSurfaceExposureError == nil)

    let first = try #require(checkpoint.surfaceExposures.first)
    let liveFirst = try LearningSurfaceExposure(
      id: first.id,
      provenance: .livePossiblePhysicalInk,
      paperContactPlane: first.paperContactPlane,
      owner: first.owner,
      geometry: first.geometry,
      reservedNanoseconds: first.reservedNanoseconds,
      penUpFinalization: first.penUpFinalization
    )
    let incompleteLedger = try LearningSurfaceExposureLedger(entries: [liveFirst])
    let incompleteStore = LearningSurfaceExposureBox(
      ledger: incompleteLedger,
      paper: identities.paperContactPlane
    )
    let incompleteManifest = LearningAuthorityManifestBox(tip: checkpoint)
    let incomplete = makeSimulatedHarness(
      manifestActions: incompleteManifest.actions,
      surfaceExposureActions: incompleteStore.actions,
      tipCalibrationSemanticIdentities: identities
    )
    #expect(incomplete.workspace.learningSurfaceExposureError?.contains("not cross-bound") == true)
    #expect(
      incomplete.workspace.selectedOperatorActionPresentation(for: tipOwner)
        .actionStrip?.actions.map(\.kind) == [.paperReplaced]
    )
  }

  @Test("Paper Replacement rejects a stale safety revision without erasing another writer")
  func paperReplacementRejectsStaleSurfaceWriter() async throws {
    let paper = PaperContactPlaneRevision()
    func exposure(
      _ position: ToolContactCalibrationPosition,
      x: Double
    ) throws -> LearningSurfaceExposure {
      try LearningSurfaceExposure(
        provenance: .livePossiblePhysicalInk,
        paperContactPlane: paper,
        owner: .sparseTipMark(position),
        geometry: .sparseCalibrationCircle(
          center: MachinePosition(x: x, y: 0),
          radiusMM: 2
        ),
        reservedNanoseconds: UInt64(x + 10)
      )
    }
    var initialLedger = LearningSurfaceExposureLedger()
    try initialLedger.reserve(try exposure(.center, x: 0))
    let store = LearningSurfaceExposureBox(ledger: initialLedger, paper: paper)
    let identities = TipCalibrationSemanticIdentityState(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperContactPlane: paper,
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
    let harness = makeSimulatedHarness(
      manifestActions: LearningAuthorityManifestBox().actions,
      surfaceExposureActions: store.actions,
      tipCalibrationSemanticIdentities: identities
    )
    let owner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    #expect(
      harness.workspace.selectedOperatorActionPresentation(for: owner)
        .actionStrip?.actions.map(\.kind) == [.paperReplaced]
    )

    var externalLedger = initialLedger
    try externalLedger.reserve(try exposure(.negativeX, x: 10))
    try store.replaceFromExternalWriter(ledger: externalLedger, paper: paper)
    try await performPublicAction(.paperReplaced, owner: owner, workspace: harness.workspace)

    #expect(harness.workspace.explorationError?.contains("staleStoreRevision") == true)
    #expect(store.ledger?.entries.count == 2)
    #expect(store.paper == paper)
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

    let episode = try #require(workspace.completedExplorationEpisodes.last)
    let observation = try #require(episode.observedLineObservation)
    #expect(observation.tipRegistrationRevisionID == tipRevision)
    #expect(
      workspace.completedExplorationEpisodes.last?.observedLineObservation?
        .tipRegistrationRevisionID == tipRevision
    )
    #expect(observation.localPreLineBaseline.frameID != observation.postLine.frameID)
    #expect(episode.frames.contains { $0.role == .localPreLineBaseline })
    #expect(episode.frames.contains { $0.role == .postLine })
    #expect(await harness.runtime.persistentInk().isEmpty == false)
    #expect(workspace.learningArtifactGraph.revisions.contains {
      guard $0.state == .current else { return false }
      if case .comparison = $0.kind { return true }
      return false
    })
  }
}
