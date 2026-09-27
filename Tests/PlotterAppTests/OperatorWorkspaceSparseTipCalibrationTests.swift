import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Testing

@testable import PlotterApp

@MainActor
@Suite("Operator workspace sparse tip calibration")
struct PlotterApplicationRuntimeSparseTipCalibrationTests {
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
      try PlotterApplicationRuntime.supervisedTravelDelta(
        from: current,
        to: numericallyDifferentTarget
      ) == nil
    )

    let outsideTolerance = try MachinePosition(x: current.point.x + 1.001, y: current.point.y)
    let travelDelta = try PlotterApplicationRuntime.supervisedTravelDelta(
      from: current,
      to: outsideTolerance
    )
    let requiredDelta = try #require(travelDelta)
    #expect(abs(requiredDelta.dx - 1.001) < 1e-12)
    #expect(requiredDelta.dy == 0)
  }

  @Test("four SIMULATED corner-circle centers accept in memory without writing LIVE authority")
  func fullFourCornerMarkAcceptance() async throws {
    let checkpointBox = ArtifactResetCheckpointStoreFixture()
    let telemetry = WorkflowTelemetryFixture()
    let clock = TestClock()
    let harness = makeCausalSimulatorAppFixture(
      statePersistencePort: TestApplicationStatePersistencePort(
        loadCheckpoint: { checkpointBox.load() },
        saveCheckpoint: { checkpointBox.save($0) },
        clearCheckpoint: { checkpointBox.clear() }
      ),
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [] },
        readNanoseconds: { clock.next() },
        recordTelemetry: { await telemetry.record($0) }
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
    let telemetryCountBeforeSparseBatch = await telemetry.events.count

    try requireEnabledPublicAction(
      .tipCalibration(.beginFourMarkBatch),
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.tipCalibration(.beginFourMarkBatch), for: tipOwner)
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
        == PlotterTipCalibrationRuntime.orderedPositions
    )
    #expect(
      sparseBatchEvents.last?.sparseTipProgress?.terminalDisposition == .completed
    )
    let surface = workspace.testActionSurfacePresentation
    let revealRequest = try #require(surface.pointSelectionRequest)
    #expect(surface.viewportContext?.preferredInitialZoom == 0)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 64)
    let beforeReplacement = await harness.simulator.snapshot()
    try requireEnabledPublicAction(
      .tipCalibration(.captureNewClickFrame(retainedPointCount: 0)),
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(
      .tipCalibration(.captureNewClickFrame(retainedPointCount: 0)),
      for: tipOwner
    )
    let request = try #require(
      workspace.testActionSurfacePresentation.pointSelectionRequest,
      "replacement error: \(workspace.explorationError ?? "none")"
    )
    let afterReplacement = await harness.simulator.snapshot()
    #expect(request.id != revealRequest.id)
    #expect(request.frame.frameID != revealRequest.frame.frameID)
    #expect(request.frame.captureNanoseconds > revealRequest.frame.captureNanoseconds)
    #expect(workspace.selectedToolContactPoints.isEmpty)
    #expect(afterReplacement.mpos == beforeReplacement.mpos)
    #expect(afterReplacement.penPose == .up)
    #expect(afterReplacement.currentOperation == nil)
    #expect(
      afterReplacement.persistentInkSegmentCount
        == beforeReplacement.persistentInkSegmentCount
    )
    let registration = try #require(workspace.machineCameraRegistration)
    let truthOffset = await harness.simulator.capToTipPixelOffsetTruth()
    let batch = try SparseTipBatchMarkPlan(
      acceptedBoundaryAggregates: workspace.testAcceptedBoundaryAggregates
    )
    let revealSnapshot = await harness.simulator.snapshot()
    #expect(
      revealSnapshot.mpos == (try SimulatedLearningMPos(
        xMM: batch.finalRevealPosition.point.x,
        yMM: batch.finalRevealPosition.point.y
      ))
    )
    let clicks = try batch.marks.map {
      try registration.fit.cameraPoint(from: $0.machinePosition.point)
        .translated(by: truthOffset)
    }
    for click in [clicks[3], clicks[1], clicks[0], clicks[2]] {
      try await submitPointSelectionAndWait(workspace, request: request, point: click)
    }
    #expect(workspace.tipCalibrationRuntime.acceptedObservations.count == 4)
    let observations = workspace.tipCalibrationRuntime.acceptedObservations.map(
      \.observation
    )
    let revealFrameIDs = Set(observations.map { $0.revealEvidence.frame.frameID })
    #expect(revealFrameIDs.count == 1)
    #expect(revealFrameIDs == [FrameID(rawValue: revealRequest.frame.frameID)])
    #expect(
      Set(observations.compactMap { $0.click.exactFrame?.frameID })
        == [FrameID(rawValue: request.frame.frameID)]
    )
    #expect(observations.allSatisfy { $0.click.exactFrame?.frameID != $0.revealEvidence.frame.frameID })
    #expect(Set(observations.map(\.revealEvidence)).count == 1)
    #expect(Set(observations.map(\.attemptID)).count == 1)
    #expect(Set(observations.map(\.operationID)).count == 4)
    #expect(Set(observations.map { $0.preMarkFrame.frameID }).count == 4)
    #expect(observations.map(\.intendedMarkPosition) == batch.marks.map(\.machinePosition))
    for observation in observations {
      #expect(observation.markGeometry.radiusMM == 2)
      #expect(observation.markGeometry.chordCount == 16)
      #expect(observation.markGeometry.maximumFeedMMPerMinute == 500)
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
        $0.provenance.kind == .drawingRegion
      }
    )
    guard case .polyline(let proposedBoundary) = proposedBoundaryOverlay.geometry,
      case .polyline(let proposedFrame) = proposedFrameOverlay.geometry
    else {
      Issue.record("Expected the machine Boundary and selected Drawing Region polylines.")
      return
    }
    let boundaryOutline = try DrawingBorderPlan(bounds: batch.boundaryEnvelope)
    let proposedBorder = try DrawingBorderPlan(bounds: batch.workingRegion)
    let proposedBoundaryPoints = try boundaryOutline.pathPositions.map {
      try registration.fit.cameraPoint(from: $0.point)
    }
    let proposedFramePoints = try proposedBorder.pathPositions.map {
      try registration.fit.cameraPoint(from: $0.point)
    }
    #expect(proposedBoundary.points == proposedBoundaryPoints)
    #expect(proposedFrame.points == proposedFramePoints)
    if case .reviewingProposal = workspace.tipCalibrationRuntime.phase {
      // The fourth click stages a reviewable map; it is not accepted implicitly.
    } else {
      Issue.record("Expected the fitted tip map to wait for explicit review.")
    }
    try requireEnabledPublicAction(
      .tipCalibration(.rejectProposal),
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.tipCalibration(.rejectProposal), for: tipOwner)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.proposedTipCameraRegistration == nil)
    #expect(workspace.tipCalibrationRuntime.acceptedObservations.isEmpty)
    #expect(
      workspace.tipCalibrationRuntime.phase == .rejected
    )
    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest?.frame == request.frame)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 64)
    for click in [clicks[3], clicks[1], clicks[0], clicks[2]] {
      try await submitPointSelectionAndWait(workspace, request: request, point: click)
    }
    try requireEnabledPublicAction(
      .tipCalibration(.acceptProposal),
      owner: tipOwner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.tipCalibration(.acceptProposal), for: tipOwner)

    let accepted = try #require(
      workspace.tipCameraRegistration,
      "accepted registration missing: \(workspace.explorationError ?? "no error")"
    )
    let replacementRuntime = PlotterTipCalibrationRuntime(effectPort: FailedReplacementTipPort())
    replacementRuntime.restoreAcceptedRegistration(accepted)
    await replacementRuntime.prepareForNewAttempt()
    #expect(replacementRuntime.acceptedRegistration == accepted)
    #expect(await replacementRuntime.submit(.beginFourMarkBatch) == .failed("Replacement unavailable"))
    #expect(replacementRuntime.phase == .accepted)
    #expect(replacementRuntime.acceptedRegistration == accepted)
    await replacementRuntime.cancelAttempt()
    replacementRuntime.clearPaperTransients(PaperInstanceRevision())
    #expect(replacementRuntime.acceptedRegistration == accepted)
    #expect(replacementRuntime.phase == .accepted)
    #expect(accepted.modelForm == .directAffine)
    #expect(accepted.applicabilityRectangle == batch.applicabilityRectangle)
    #expect(accepted.modelSelectionEvidence.observationIDs.count == 4)
    #expect(workspace.proposedTipCameraRegistration == nil)
    #expect(workspace.tipCalibrationRuntime.phase == .accepted)
    let acceptedGuideFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    let calibratedGuides = workspace.sparseTipGuideOverlays(on: acceptedGuideFrame)
    #expect(calibratedGuides.count == 10)
    #expect(calibratedGuides.allSatisfy { $0.provenance.algorithmRevision == "planned-four-circle-compatible-tip-projection-v1" })
    let regionOverlay = try #require(
      workspace.testActionSurfacePresentation.overlays.first {
        $0.provenance.kind == .drawingRegion
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
      try accepted.diagnosticProjection(at: $0.point).cameraPoint
    }
    #expect(regionPolyline.points == acceptedFramePoints)
    let acceptedBoundaryPoints = try boundaryOutline.pathPositions.map {
      try accepted.cameraFromMachine.applying(to: $0.point)
    }
    #expect(acceptedBoundaryPolyline.points == acceptedBoundaryPoints)
    #expect(
      workspace.testCurrentLearningPathItemID
        == .borderValidation(.chooseDrawingBorderPlan)
    )
    #expect(checkpointBox.checkpoint == nil)
    #expect(checkpointBox.operationCounts.loads == 1)
    #expect(checkpointBox.operationCounts.saves == 0)
    #expect(checkpointBox.operationCounts.clears == 0)
  }

  @Test("unaccepted circle recovery preserves upstream Learning and excludes same-sheet replay", arguments: [false, true])
  func recoverUnacceptedCircles(scopedReset: Bool) async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime, workspace: workspace, environment: .simulated)
    let camera = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    await workspace.performTestExerciseAction(.cameraCalibration(.buildFivePositionProposal), for: camera)
    await workspace.performTestExerciseAction(.cameraCalibration(.acceptProposal), for: camera)
    let tip = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    let upstream = workspace.learningArtifactGraph.revisions.filter { $0.state == .current }
    let registration = try #require(workspace.machineCameraRegistration)
    let boundary = workspace.testAcceptedBoundaryAggregates
    await workspace.performTestExerciseAction(.tipCalibration(.beginFourMarkBatch), for: tip)
    #expect(workspace.tipCalibrationRuntime.expectedSelection != nil)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 64)
    let guideFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    let plannedGuides = workspace.sparseTipGuideOverlays(on: guideFrame)
    try #require(plannedGuides.count == 10)
    #expect(plannedGuides.allSatisfy { $0.provenance.source == .planned })
    #expect(workspace.sparseTipGuideDetail(on: guideFrame)?.contains("unknown tip offset") == true)
    let batch = try #require(workspace.currentSparseTipBatchPlan)
    for (index, mark) in batch.marks.enumerated() {
      guard case .polyline(let circle) = plannedGuides[3 + index * 2].geometry else {
        Issue.record("Expected a planned circle polyline"); return
      }
      #expect(circle.points == (try mark.circle.pathPositions.map { try registration.fit.cameraPoint(from: $0.point) }))
    }
    let plan = try #require(workspace.learningVacatePlan(from: tip))
    #expect(plan.physicalInkMayRemain)
    if scopedReset {
      #expect(await workspace.performLearningVacate(plan))
    } else {
      await workspace.performTestExerciseAction(.cancel, for: tip)
    }
    #expect(workspace.tipCalibrationRuntime.expectedSelection == nil)
    #expect(workspace.tipCalibrationRuntime.acceptedRegistration == nil)
    #expect(workspace.machineCameraRegistration == registration)
    #expect(workspace.testAcceptedBoundaryAggregates == boundary)
    for revision in upstream {
      #expect(workspace.learningArtifactGraph.revisions.contains { $0.id == revision.id && $0.state == .current })
    }
    #expect(workspace.tipCalibrationRuntime.blacklistedLocations.count == 4)
    let beforeRetry = await harness.simulator.snapshot()
    let samePaperRequest = workspace.testPlotterUIProjection(
      selectedItemID: tip, includesLearningPath: true).semantic.request(
        for: learningActionID(.tipCalibration(.beginFourMarkBatch), owner: tip))
    #expect(samePaperRequest == nil)
    let rejectedRetry = await workspace.tipCalibrationRuntime.submit(.beginFourMarkBatch)
    if case .refused = rejectedRetry {} else { Issue.record("Same-sheet calibration retry must refuse.") }
    let refusedRetry = await harness.simulator.snapshot()
    #expect(refusedRetry.persistentInkSegmentCount == 64)
    #expect(refusedRetry.mpos == beforeRetry.mpos)
    await workspace.recordNewPaperSheetOnCurrentPlane()
    #expect(workspace.machineCameraRegistration == registration)
    #expect(workspace.testAcceptedBoundaryAggregates == boundary)
    #expect(workspace.tipCalibrationRuntime.blacklistedLocations.isEmpty)
    #expect(workspace.tipCalibrationRuntime.expectedSelection == nil)
    #expect(workspace.sparseTipGuideOverlays(on: guideFrame).map(\.geometry) == plannedGuides.map(\.geometry))
    let freshPaper = await harness.simulator.snapshot()
    #expect(freshPaper.persistentInkSegmentCount == 0)
    #expect(freshPaper.mpos == beforeRetry.mpos)
    await workspace.performTestExerciseAction(.tipCalibration(.beginFourMarkBatch), for: tip)
    #expect(workspace.tipCalibrationRuntime.expectedSelection != nil)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 64)
    await workspace.shutdown()
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
      .cameraCalibration(.buildFivePositionProposal),
      owner: owner,
      workspace: workspace
    )
    let runActionID = learningActionID(
      .cameraCalibration(.buildFivePositionProposal),
      owner: owner
    )
    let runProjection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let runRequest = try #require(runProjection.request(for: runActionID))
    let sink: any PlotterUIIntentSink = workspace
    #expect(await sink.submitPlotterUIRequest(runRequest) == .accepted(requestID: runRequest.id))
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
      .cameraCalibration(.acceptProposal),
      owner: owner,
      workspace: workspace
    )
    let acceptActionID = learningActionID(
      .cameraCalibration(.acceptProposal),
      owner: owner
    )
    let acceptProjection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let acceptRequest = try #require(acceptProjection.request(for: acceptActionID))
    #expect(await sink.submitPlotterUIRequest(acceptRequest) == .accepted(requestID: acceptRequest.id))
    #expect(
      workspace.testCurrentLearningPathItemID
        == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )
  }

  @Test("projection-bound five-cap calibration preserves a fractional reference position")
  func fiveCapAcceptancePreservesFractionalReference() async throws {
    let initialMPos = try SimulatedLearningMPos(xMM: 0.1, yMM: -0.2)
    let harness = makeCausalSimulatorAppFixture(initialMPos: initialMPos)
    try await completeSimulatedPenInteractionPrerequisite(harness.workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: harness.workspace,
      environment: .simulated
    )
    let workspace = harness.workspace
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    try requireEnabledPublicAction(
      .cameraCalibration(.buildFivePositionProposal),
      owner: owner,
      workspace: workspace
    )
    let actionID = learningActionID(
      .cameraCalibration(.buildFivePositionProposal),
      owner: owner
    )
    let projection = workspace.testPlotterUIProjection(
      selectedItemID: owner,
      includesLearningPath: true
    ).semantic
    let request = try #require(projection.request(for: actionID))
    let sink: any PlotterUIIntentSink = workspace

    #expect(await sink.submitPlotterUIRequest(request) == .accepted(requestID: request.id))
    let proposal = try #require(workspace.proposedMachineCameraRegistration)
    #expect(
      proposal.fitCorrespondenceProvenance.first?.machinePoint
        == (try Point2<MachineSpace>(x: initialMPos.xMM, y: initialMPos.yMM))
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

    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    try requireEnabledPublicAction(
      .tipCalibration(.beginFourMarkBatch),
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.tipCalibration(.beginFourMarkBatch), for: owner)
    let request = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let frameID = request.frame.frameID
    let before = await harness.simulator.snapshot()
    try await submitPointSelectionAndWait(
      workspace,
      request: request,
      point: try Point2(x: 160, y: 120)
    )
    try requireEnabledPublicAction(.pointSelectionCorrection(.undoLastPoint), owner: owner, workspace: workspace)
    await workspace.performTestExerciseAction(.pointSelectionCorrection(.undoLastPoint), for: owner)
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
    let clock = TestClock()
    let harness = makeCausalSimulatorAppFixture(
      residualEffectPort: TestApplicationResidualEffectPort(
        discoverDevices: { [] },
        readNanoseconds: { clock.next() },
        recordTelemetry: { await telemetry.record($0) }
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
    let owner = LearningPathItemID.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    let pacing = CalibrationStopPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let telemetryCountBeforeSparseBatch = await telemetry.events.count

    let markTask = Task {
      await workspace.performTestExerciseAction(.tipCalibration(.beginFourMarkBatch), for: owner)
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

    #expect(workspace.tipCalibrationRuntime.blacklistedPositions == [.negativeX])
    #expect(workspace.tipCalibrationRuntime.acceptedObservations.isEmpty)
    #expect(workspace.testActionSurfacePresentation.pointSelectionRequest == nil)
    #expect(workspace.contextualStopPresentation == nil)
    #expect((await harness.simulator.snapshot()).persistentInkSegmentCount == 0)
    if case .possibleInkBlacklisted(let location, _) =
      workspace.tipCalibrationRuntime.phase
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
    try await completeSimulatedTipCalibration(
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
    let cameraOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    try requireEnabledPublicAction(
      .cameraCalibration(.buildFivePositionProposal),
      owner: cameraOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(
      .cameraCalibration(.buildFivePositionProposal),
      for: cameraOwner
    )
    try requireEnabledPublicAction(
      .cameraCalibration(.acceptProposal),
      owner: cameraOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(
      .cameraCalibration(.acceptProposal),
      for: cameraOwner
    )
    restarted.workspace.replaceSimulatedTipCalibrationCheckpointForTesting(saved)
    let tipOwner = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    #expect((await restarted.simulator.snapshot()).persistentInkSegmentCount == 0)
    try requireEnabledPublicAction(
      .tipCalibration(.revalidateCheckpoint),
      owner: tipOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(
      .tipCalibration(.revalidateCheckpoint),
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
        == LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    )
    #expect(
      restored.estimatorRevision == SparseTipCircularMarkPlan.registrationEstimatorRevision
    )
    let drawingOwner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    try requireEnabledPublicAction(
      .start,
      owner: drawingOwner,
      workspace: restarted.workspace
    )
    await restarted.workspace.performTestExerciseAction(.start, for: drawingOwner)
    let domain = restored.applicabilityRectangle
    #expect(
      restarted.workspace.borderValidationSnapshot.drawingBorderPlan?
        .strokes.first?.path.points.first
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
    try await completeSimulatedTipCalibration(
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
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)

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
    let validationOwner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    try requireEnabledPublicAction(.start, owner: validationOwner, workspace: workspace)
    await workspace.performTestExerciseAction(.start, for: validationOwner)
    #expect(workspace.borderValidationSnapshot.step == .compareIntendedAndObservedGeometry)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.borderValidationSnapshot.assessment == .predictionObserved)

    let observation = try #require(workspace.borderValidationSnapshot.inkObservation)
    let executionPlan = try #require(workspace.borderValidationSnapshot.drawingBorderPlan)
    #expect(executionPlan.provenance.registrationRevisionID.rawValue == tipRevision.rawValue)
    #expect(executionPlan.drawableRegion.bounds == acceptedBoundary)
    #expect(MachinePositionAcceptancePolicy.toleranceMM == 1.0)
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
    #expect(workspace.borderValidationSnapshot.revealPosition != nil)
    #expect(await harness.simulator.persistentInk().isEmpty == false)
    #expect(
      workspace.learningArtifactGraph.revisions.contains {
        guard $0.state == .current else { return false }
        if case .comparison = $0.kind { return true }
        return false
      })
  }
}

private actor FailedReplacementTipPort: PlotterTipCalibrationEffectPort {
  func execute(_ request: PlotterTipCalibrationEffectRequest) async -> PlotterTipCalibrationEffectResult {
    .failed("Replacement unavailable")
  }
}
