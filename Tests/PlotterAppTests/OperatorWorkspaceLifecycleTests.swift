import Testing
import PlotterEpisodeRuntime
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
    #expect(LearningMotionAction.moveToDrawingBorderStart.title == "Move to Drawing Border Start")
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
    #expect(neutralAmbiguity.attemptDisposition == .ambiguous(neutralAmbiguity.detail))
    #expect(possibleInk.attemptDisposition == .ambiguous(possibleInk.detail))
  }

  @Test("lost simulated drawing outcome clears Stop and preserves no-redraw recovery")
  func lostSimulatedDrawingOutcomeCleansOwner() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)

    workspace.replaceSimulatedExecutionPacingForTesting(
      DrawingOutcomeLossPacing(simulator: harness.simulator)
    )
    let owner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)
    try requireEnabledPublicAction(
      .start,
      owner: owner,
      workspace: workspace
    )
    await workspace.performTestExerciseAction(.start, for: owner)

    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.borderValidationStep == .revealAndObserveNewInk)
    #expect(workspace.restartableExerciseItemID == nil)
    #expect(workspace.explorationError?.contains("will not restart") == true)
    await workspace.shutdown()
  }

  @Test("Draw and Validate Drawing Border previews before motion and waits for explicit acceptance")
  func oneGoPreviewsThenWaitsForExplicitAcceptance() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    try await completeSimulatedPenInteractionPrerequisite(workspace)
    try await installAcceptedBoundaryTestProjection(
      runtime: harness.boundaryRuntime,
      workspace: workspace,
      environment: .simulated
    )
    try await completeSimulatedTipCalibration(workspace, simulator: harness.simulator)
    let positionBeforeGo = (await harness.simulator.snapshot()).mpos
    let pacing = FirstOperationSuspensionPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let owner = LearningPathItemID.borderValidation(.chooseDrawingBorderPlan)

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
    #expect(workspace.borderValidationStep == .moveToDrawingBorderStart)
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

    #expect(workspace.borderValidationAssessment == nil)
    #expect(workspace.borderValidationStep == .compareIntendedAndObservedGeometry)
    #expect(workspace.activeExerciseAttemptID != nil)
    #expect(!workspace.completedDrawingComparisonReviewIsAvailable)
    #expect(
      workspace.selectedOperatorActionPresentation(for: owner).actionStrip?.actions.map(\.kind)
        == [
          .borderValidation(.acceptObservedPrediction),
          .borderValidation(.reject("Operator rejected the observed Drawing Border comparison.")),
        ]
    )

    await workspace.performTestExerciseAction(
      .borderValidation(.acceptObservedPrediction),
      for: owner
    )

    #expect(workspace.borderValidationAssessment == .predictionObserved)
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
    let penRequest = try #require(workspace.testActionSurfacePresentation.pointSelectionRequest)
    let penFrame = try #require(workspace.testActionSurfacePresentation.displayedFrame)
    submitPointSelection(workspace, request: penRequest, point: try Point2(
      x: Double(penFrame.frame.width - 1) / 2,
      y: Double(penFrame.frame.height - 1) / 2
    ))
    try await waitUntil {
      workspace.activeDiscoverySequenceID == .penInteraction || workspace.discoveryError != nil
    }
    for _ in 0..<3 {
      try requireEnabledPublicAction(.choice(.yes), owner: penOwner, workspace: workspace)
      await workspace.performTestExerciseAction(.choice(.yes), for: penOwner)
    }

    await harness.simulator.injectFault(.ambiguityBeforeNextBoundarySegment)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    let terminalCount = workspace.testBoundaryTerminals.count
    try await submitRenderedBoundaryAcquisition(
      .positiveX,
      owner: boundaryOwner,
      workspace: workspace
    )
    try await waitForBoundaryTerminalCount(terminalCount + 1, workspace: workspace)

    guard case .ambiguous(let detail) = workspace.testBoundaryTerminals.last?.disposition else {
      Issue.record("Expected typed ambiguous Boundary disposition")
      return
    }
    #expect(!detail.isEmpty)
    #expect(
      workspace.selectedOperatorActionPresentation(for: boundaryOwner).actionStrip?.actions
        .contains { if case .boundary(.stop(_)) = $0.kind { return true }; return false } == false
    )
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
