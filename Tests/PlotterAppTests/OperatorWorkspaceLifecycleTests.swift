import Testing
import PlotterModel

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace typed lifecycle", .serialized)
@MainActor
struct OperatorWorkspaceLifecycleTests {
  @Test("top motion action enables and disables simulated authorization")
  func motionAuthorizationActionToggles() async {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()

    #expect(!workspace.motionAuthorizationEnabled)
    #expect(workspace.motionAuthorizationActionUnavailableReason == nil)

    await workspace.performMotionAuthorizationAction()

    #expect(workspace.motionAuthorizationEnabled)
    #expect(workspace.motionAuthorizationActionUnavailableReason == nil)

    await workspace.performMotionAuthorizationAction()

    #expect(!workspace.motionAuthorizationEnabled)
    #expect(workspace.testManualMotionEpisodePresentation.jogControlsUnavailableReason
      == "Enable Motion before requesting movement.")
    await workspace.shutdown()
  }

  @Test("Learning motion identity is exhaustive and presentation-only wording is derived")
  func typedLearningMotionActions() {
    #expect(LearningMotionAction.moveToEstimatedCenter.title == "Move to Estimated Center")
    #expect(
      LearningMotionAction.cameraCalibrationSample(index: 2, total: 5).title
        == "Current-Camera Calibration Sample 2 of 5"
    )
    #expect(
      LearningMotionAction.sparseTipApproach(.negativeX).title
        == "Sparse Tip Mark Minimum-X / Minimum-Y Corner Approach"
    )
    #expect(
      LearningMotionAction.sparseTipCircleStart(.positiveX).title
        == "Sparse Tip Circle Maximum-X / Maximum-Y Corner Start"
    )
    #expect(
      LearningMotionAction.returnToLocalRevealPose.title == "Return to Local Reveal Pose"
    )
  }

  @Test("a second start cannot replace the active typed attempt")
  func duplicateStartRetainsActiveAttempt() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()
    await workspace.activateMotionGuard()

    await workspace.beginPenInteraction()
    let firstID = try #require(workspace.activeExerciseAttemptID)
    await workspace.beginPenInteraction()

    #expect(workspace.activeExerciseAttemptID == firstID)
    #expect(
      workspace.activeExerciseAttemptOwnerID
        == .humanGuidedDiscovery(.penInteraction)
    )
    await workspace.shutdown()
  }

  @Test("typed disposition is independent of presentation wording")
  func typedDispositionIgnoresWording() {
    let misleadingFailure = WorkflowFailure(
      kind: .failed,
      detail: "ambiguous unclear refusal alarm disconnected",
      recovery: .resolveNamedFailure
    )
    let neutralAmbiguity = WorkflowFailure(
      kind: .ambiguous,
      detail: "The owner has no attributable terminal result.",
      recovery: .resolveNamedFailure
    )
    let possibleInk = WorkflowFailure(
      kind: .possibleInk,
      detail: "The mark owner ended after contact.",
      recovery: .resolveNamedFailure
    )

    #expect(misleadingFailure.attemptDisposition == .failed(misleadingFailure.detail))
    #expect(misleadingFailure.boundaryDisposition == .failed(misleadingFailure.detail))
    #expect(neutralAmbiguity.attemptDisposition == .ambiguous(neutralAmbiguity.detail))
    #expect(neutralAmbiguity.boundaryDisposition == .ambiguous(neutralAmbiguity.detail))
    #expect(possibleInk.attemptDisposition == .ambiguous(possibleInk.detail))
    #expect(possibleInk.boundaryDisposition == .ambiguous(possibleInk.detail))
  }

  @Test("lost simulated drawing outcome clears Stop and preserves no-redraw recovery")
  func lostSimulatedDrawingOutcomeCleansOwner() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      simulator: harness.simulator,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, simulator: harness.simulator)

    workspace.replaceSimulatedExecutionPacingForTesting(
      DrawingOutcomeLossPacing(simulator: harness.simulator)
    )
    let owner = LearningPathItemID.observedDrawingTrial(.chooseDrawingBorderPlan)
    try requireEnabledPublicAction(
      .start,
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.start, for: owner)

    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.observedDrawingTrialStep == .revealAndObserveNewInk)
    #expect(workspace.restartableExerciseItemID == nil)
    #expect(workspace.explorationError?.contains("will not restart") == true)
    await workspace.shutdown()
  }

  @Test("Draw and Validate Drawing Border previews the planned Border before motion and completes automatically")
  func oneGoPreviewsThenCompletesTrial() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      simulator: harness.simulator,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, simulator: harness.simulator)
    let positionBeforeGo = (await harness.simulator.snapshot()).mpos
    let pacing = FirstOperationSuspensionPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let owner = LearningPathItemID.observedDrawingTrial(.chooseDrawingBorderPlan)

    let trial = Task { await workspace.performTestExerciseAction(.start, for: owner) }
    await pacing.waitUntilSuspended()

    let surface = workspace.testActionSurfacePresentation
    let predicted = try #require(
      surface.overlays.first {
        $0.provenance.kind == .intendedPath && $0.provenance.source == .planned
      })
    let displayedFrame = try #require(surface.displayedFrame)
    let drawingBorderPath = try #require(workspace.drawingBorderPlan?.strokes.first?.path)
    let registration = try #require(workspace.tipCameraRegistration)
    guard case .polyline(let predictedBorder) = predicted.geometry else {
      Issue.record("The model prediction must be a camera-pixel polyline.")
      return
    }
    #expect(predicted.frameID == displayedFrame.frame.id)
    #expect(predicted.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID)
    let projectedBorder = try drawingBorderPath.points.map { try registration.tipPixel(at: $0) }
    #expect(predictedBorder.points == projectedBorder)
    #expect((await harness.simulator.snapshot()).mpos == positionBeforeGo)
    #expect(workspace.observedDrawingTrialStep == .moveToDrawingBorderStart)
    #expect(
      workspace.selectedOperatorActionPresentation(for: owner).activity?.outcome == .inProgress)
    #expect(
      workspace.selectedOperatorActionPresentation(for: owner).activity?.phase == "Phase 3 of 6"
    )
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains {
        if case .stop = $0.kind { return true }
        return false
      } == true)

    await pacing.resume()
    await trial.value

    #expect(workspace.drawingTrialAssessment == .predictionObserved)
    #expect(workspace.completedDrawingComparisonReviewIsAvailable)
    #expect(workspace.completedDrawingComparisonReviewIsPinned)
    let completedSurface = workspace.testActionSurfacePresentation
    #expect(
      completedSurface.displayedFrame?.frame.id == workspace.explorationPostFrame?.frame.id)
    #expect(
      Set(completedSurface.overlays.map(\.provenance.kind)).isSuperset(of: [
        .intendedPath,
        .observedInk,
        .residual,
      ]))

    workspace.resumeLivePreviewAfterDrawingComparison()
    #expect(!workspace.completedDrawingComparisonReviewIsPinned)
    await workspace.reviewCompletedDrawingComparison()
    #expect(workspace.completedDrawingComparisonReviewIsPinned)
    #expect(
      workspace.testWorkbenchCapabilityPresentation.learning == .interactiveLearningComplete
    )
    #expect(workspace.frameMode == .simulated)
    #expect(!workspace.drawingDraftSnapshot.isOpen)
    #expect(!workspace.paperCoverageIsCurrent)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentExerciseActionStripPresentation == nil)
    await workspace.shutdown()
  }

  @Test("injected Boundary ambiguity remains typed when wording is neutral")
  func boundaryAmbiguityDoesNotDependOnText() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()
    await workspace.activateMotionGuard()

    let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    try requireEnabledPublicAction(.start, owner: penOwner, workspace: workspace)
    await workspace.performTestExerciseAction(.start, for: penOwner)
    try await identifyPenCap(workspace)
    for _ in 0..<3 {
      try requireEnabledPublicAction(.choice(.yes), owner: penOwner, workspace: workspace)
      await workspace.performTestExerciseAction(.choice(.yes), for: penOwner)
    }

    await harness.simulator.injectFault(.ambiguityBeforeNextBoundarySegment)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try requireEnabledPublicAction(.start, owner: boundaryOwner, workspace: workspace)
    await workspace.performTestExerciseAction(.start, for: boundaryOwner)
    try await waitUntil { workspace.activeExerciseAttemptID == nil }

    guard case .ambiguous(let detail) = workspace.boundaryActivityRecords.last?.disposition else {
      Issue.record("Expected typed ambiguous Boundary disposition")
      return
    }
    #expect(detail == "The simulated Drawing Boundary motion lost attributable segment completion.")
    #expect(workspace.contextualStopPresentation == nil)
    await workspace.shutdown()
  }
}

private actor DrawingOutcomeLossPacing: SimulatedLearningExecutionPacing {
  let simulator: CausalSimulatorProbe
  var suspensionCount = 0

  init(simulator: CausalSimulatorProbe) {
    self.simulator = simulator
  }

  func suspendBetweenSteps() async {
    suspensionCount += 1
    if suspensionCount == 2 {
      await simulator.injectFault(.outcomeUnavailableAfterNextExecution)
    }
    await Task.yield()
  }
}
