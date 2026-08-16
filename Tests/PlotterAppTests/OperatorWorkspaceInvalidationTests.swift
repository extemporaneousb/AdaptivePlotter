import Foundation
import PlotterModel
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

extension OperatorWorkspaceTests {
  @Test("Invalidate All LIVE Learning clears a quarantined durable tip checkpoint")
  func invalidateAllLiveLearningClearsTipCheckpoint() async throws {
    let seeded = makeSimulatedHarness()
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
    let durableTip = try AcceptedTipCalibrationCheckpoint(
        registration: registration,
        acceptanceEvent: TipCalibrationAcceptanceEvent(
          acceptedRevisionID: registration.acceptedRevisionID,
          timestamp: registration.acceptedAt,
          actor: "test fixture"
        ),
        surfaceExposures: seeded.workspace.learningSurfaceExposureLedger.entries
    )
    let checkpointBox = LearningAuthorityManifestBox(tip: durableTip)

    let liveRestart = makeSimulatedHarness(manifestActions: checkpointBox.actions)
    #expect(liveRestart.workspace.frameMode == .live)
    #expect(liveRestart.workspace.quarantinedTipCalibrationCheckpoint != nil)
    let plan = try #require(liveRestart.workspace.invalidateAllLearningPlan)
    #expect(plan.removesDurableTipRegistration)
    #expect(!plan.removesDurableMachineRegistration)
    #expect(liveRestart.workspace.performLearningInvalidation(plan))
    #expect(checkpointBox.tipCheckpoint == nil)
    #expect(liveRestart.workspace.quarantinedTipCalibrationCheckpoint == nil)
  }

  @Test("Invalidate All LIVE Learning clears durable authority but retains session facts")
  func invalidateAllLiveLearningClearsCheckpointAndRetainsSessionFacts() async throws {
    let log = EventLog()
    let machine = try MachineFixture(log: log)
    let checkpointBox = LearningAuthorityManifestBox()
    let workspace = workspace(
      machine: machine,
      camera: try CameraFixture(),
      manifestActions: checkpointBox.actions,
      log: log
    )
    await workspace.establishMachineSession(machine.descriptor)
    await workspace.requestPassiveProbe()
    await workspace.startCamera()
    try await completePenInteraction(workspace)
    let stalePlan = try #require(workspace.invalidateAllLearningPlan)
    await workspace.beginPairedBoundarySide(.positiveX)
    try await waitUntil { workspace.contextualStopPresentation != nil }
    try await stopActiveOperation(workspace)
    #expect(checkpointBox.checkpoint != nil)
    #expect(!workspace.performLearningInvalidation(stalePlan))
    #expect(workspace.boundarySideAggregates[.positiveX] != nil)
    #expect(
      workspace.learningAuthorityError?.contains("changed while the invalidation summary was open") == true
    )

    let plan = try #require(workspace.invalidateAllLearningPlan)
    #expect(plan.source == .live)
    #expect(plan.scope == .all)
    #expect(plan.removesDurableMachineRegistration)
    #expect(plan.title == "Invalidate All Learning")
    #expect(workspace.performLearningInvalidation(plan))

    #expect(checkpointBox.checkpoint == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .penInteraction) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(.positiveX))
        == nil
    )
    #expect(workspace.penAttemptHistory.records.isEmpty)
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.controllerSessionEstablished)
    #expect(workspace.motionAuthorizationEnabled)
    #expect(
      workspace.currentLearningPathItemID == .humanGuidedDiscovery(.penInteraction)
    )
    await workspace.shutdown()
  }

  @Test("Invalidating Boundary dependents retains Pen and removes later SIMULATED authority")
  func invalidateBoundaryDependentsRetainsEarlierLearning() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    let penRevisionID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
    )
    let anchor = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let plan = try #require(workspace.learningInvalidationPlan(for: anchor))
    #expect(plan.source == .simulated)
    #expect(!plan.removesDurableMachineRegistration)
    #expect(!plan.physicalInkMayRemain)
    #expect(plan.title == "Invalidate This Step")
    #expect(workspace.performLearningInvalidation(plan))

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .penInteraction)?.id
        == penRevisionID
    )
    #expect(workspace.boundarySideAggregates.isEmpty)
    #expect(workspace.estimatedMachineCenter == nil)
    #expect(workspace.machineCameraRegistration == nil)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.currentLearningPathItemID == anchor)
    await workspace.shutdown()
  }

  @Test("Invalidating comparison preserves the observed line and performs no redraw")
  func invalidatingComparisonPreservesObservedLine() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    try await completeSimulatedStageFour(workspace)
    let linePlan = try #require(
      workspace.learningArtifactGraph.revisions.first { revision in
        guard revision.state == .current else { return false }
        if case .linePlan = revision.kind { return true }
        return false
      })
    guard case .linePlan(let group) = linePlan.kind else {
      Issue.record("Expected the current line-plan revision to carry its attempt group.")
      return
    }
    let linePlanID = linePlan.id
    let observationID = try #require(
      workspace.learningArtifactGraph.currentRevision(for: .postLineObservation(group))?.id
    )
    let inkBefore = await harness.runtime.persistentInk()
    let anchor = LearningPathItemID.observedDrawingTrial(
      .compareIntendedAndObservedGeometry
    )
    let plan = try #require(workspace.learningInvalidationPlan(for: anchor))
    #expect(plan.affectedItemIDs == [anchor])
    #expect(plan.expectedCurrentRevisionIDs.count == 1)
    #expect(workspace.performLearningInvalidation(plan))

    #expect(workspace.drawingTrialAssessment == nil)
    #expect(workspace.learningArtifactGraph.currentRevision(for: .comparison(group)) == nil)
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .linePlan(group))?.id == linePlanID
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .postLineObservation(group))?.id
        == observationID
    )
    #expect(workspace.currentLearningPathItemID == anchor)
    #expect(await harness.runtime.persistentInk() == inkBefore)
    await workspace.shutdown()
  }

  @Test("Invalidating line-start arrival removes its real zero-or-travel settlement subject")
  func invalidateLineStartArrival() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    try await performPublicAction(
      .chooseIsolatedLinePlan(.positiveX),
      owner: .observedDrawingTrial(.chooseIsolatedLinePlan),
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
    #expect(workspace.lastProtocolPoseSettlement != nil)

    let anchor = LearningPathItemID.observedDrawingTrial(.moveToLineStart)
    let plan = try #require(workspace.learningInvalidationPlan(for: anchor))
    #expect(plan.expectedCurrentRevisionIDs.count == 1)
    #expect(plan.affectedItemIDs == [anchor])
    #expect(workspace.performLearningInvalidation(plan))

    #expect(workspace.currentLearningPathItemID == anchor)
    #expect(workspace.lastProtocolPoseSettlement == nil)
    #expect(workspace.localPreLineBaseline != nil)
    await workspace.shutdown()
  }

  @Test("Invalidating an exposed Stage 4 group retains exposure and replans elsewhere")
  func invalidatingExposedStageFourGroupNeverRedrawsIt() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    try await completeSimulatedStageFour(workspace)
    let exposedStart = try #require(workspace.drawingTrialLineStart)
    let inkBefore = await harness.runtime.persistentInk()
    #expect(workspace.learningSurfaceExposureLedger.entries.count == 6)
    #expect(workspace.currentDrawingTrialGroupHasExposure)

    let owner = LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)
    let plan = try #require(workspace.learningInvalidationPlan(for: owner))
    #expect(!plan.physicalInkMayRemain)
    #expect(workspace.performLearningInvalidation(plan))
    #expect(workspace.learningSurfaceExposureLedger.entries.count == 6)
    #expect(!workspace.currentDrawingTrialGroupHasExposure)
    #expect(await harness.runtime.persistentInk() == inkBefore)

    try await performPublicAction(
      .chooseIsolatedLinePlan(.positiveX),
      owner: owner,
      workspace: workspace
    )
    #expect(workspace.learningSurfaceExposureLedger.entries.count == 6)
    #expect(!workspace.currentDrawingTrialGroupHasExposure)
    #expect(workspace.drawingTrialLineStart != exposedStart)
    #expect(await harness.runtime.persistentInk() == inkBefore)
    await workspace.shutdown()
  }

  @Test(
    "Invalidating exposed 4.2 through 4.4 routes through a fresh 4.1 plan",
    arguments: [
      ObservedDrawingTrialStep.captureLocalPreLineBaseline,
      .moveToLineStart,
      .drawIsolatedLine,
    ]
  )
  func invalidatingExposedSetupRoutesThroughFreshPlan(
    _ step: ObservedDrawingTrialStep
  ) async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    try await completeSimulatedStageFour(workspace)
    let oldPlanRevision = try #require(
      workspace.learningArtifactGraph.revisions.first { revision in
        guard revision.state == .current else { return false }
        if case .linePlan = revision.kind { return true }
        return false
      }
    )
    guard case .linePlan(let oldGroup) = oldPlanRevision.kind else {
      Issue.record("Expected a group-scoped line plan.")
      return
    }
    let before = await harness.runtime.snapshot()
    let inkBefore = await harness.runtime.persistentInk()
    let exposureCount = workspace.learningSurfaceExposureLedger.entries.count
    let owner = LearningPathItemID.observedDrawingTrial(step)
    let plan = try #require(workspace.learningInvalidationPlan(for: owner))

    #expect(workspace.performLearningInvalidation(plan))
    #expect(
      workspace.currentLearningPathItemID
        == .observedDrawingTrial(.chooseIsolatedLinePlan)
    )
    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .linePlan(oldGroup)) == nil
    )
    #expect(workspace.learningArtifactGraph.revision(id: oldPlanRevision.id)?.state != .current)
    #expect(!workspace.currentDrawingTrialGroupHasExposure)
    #expect(await harness.runtime.snapshot() == before)
    #expect(await harness.runtime.persistentInk() == inkBefore)

    try await performPublicAction(
      .chooseIsolatedLinePlan(.positiveX),
      owner: .observedDrawingTrial(.chooseIsolatedLinePlan),
      workspace: workspace
    )
    let replacement = try #require(
      workspace.learningArtifactGraph.revisions.first { revision in
        guard revision.state == .current else { return false }
        if case .linePlan = revision.kind { return true }
        return false
      }
    )
    guard case .linePlan(let replacementGroup) = replacement.kind else {
      Issue.record("Expected a replacement group-scoped line plan.")
      return
    }
    #expect(replacementGroup != oldGroup)
    #expect(workspace.learningArtifactGraph.revision(id: oldPlanRevision.id)?.state != .current)
    #expect(workspace.learningSurfaceExposureLedger.entries.count == exposureCount)
    #expect(!workspace.currentDrawingTrialGroupHasExposure)
    #expect(await harness.runtime.snapshot() == before)
    #expect(await harness.runtime.persistentInk() == inkBefore)
    await workspace.shutdown()
  }

  @Test(
    "Browsing exposed 4.1 through 4.4 suppresses Redo until confirmed invalidation",
    arguments: [
      ObservedDrawingTrialStep.chooseIsolatedLinePlan,
      .captureLocalPreLineBaseline,
      .moveToLineStart,
      .drawIsolatedLine,
    ]
  )
  func exposedSetupBrowseIsInert(
    _ step: ObservedDrawingTrialStep
  ) async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.positiveX, .negativeX, .positiveY, .negativeY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    try await completeSimulatedStageFour(workspace)
    let oldPlanRevision = try #require(
      workspace.learningArtifactGraph.revisions.first { revision in
        guard revision.state == .current else { return false }
        if case .linePlan = revision.kind { return true }
        return false
      }
    )
    guard case .linePlan(let oldGroup) = oldPlanRevision.kind else {
      Issue.record("Expected a group-scoped line plan.")
      return
    }
    let before = await harness.runtime.snapshot()
    let inkBefore = await harness.runtime.persistentInk()
    let exposureCount = workspace.learningSurfaceExposureLedger.entries.count
    let owner = LearningPathItemID.observedDrawingTrial(step)

    #expect(workspace.selectedOperatorActionPresentation(for: owner).actionStrip == nil)
    #expect(workspace.learningInvalidationPlan(for: owner) != nil)
    await workspace.performExerciseAction(.redoThisStep, for: owner)

    #expect(
      workspace.learningArtifactGraph.currentRevision(for: .linePlan(oldGroup))?.id
        == oldPlanRevision.id
    )
    #expect(workspace.learningSurfaceExposureLedger.entries.count == exposureCount)
    #expect(workspace.currentDrawingTrialGroupHasExposure)
    #expect(await harness.runtime.snapshot() == before)
    #expect(await harness.runtime.persistentInk() == inkBefore)
    #expect(await harness.machineActionLog.values.isEmpty)
    await workspace.shutdown()
  }
}
