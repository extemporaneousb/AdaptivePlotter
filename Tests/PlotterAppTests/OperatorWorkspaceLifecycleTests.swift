import Testing
import PlotterEpisodeRuntime
import PlotterModel

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace typed lifecycle", .serialized)
@MainActor
struct PlotterApplicationRuntimeLifecycleTests {
  @Test("top motion action enables and disables simulated authorization")
  func motionAuthorizationActionToggles() async {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    await submitControllerSession(workspace, .toggleConnection)

    #expect(!workspace.controllerSessionProjection.motionAuthorized)
    #expect(workspace.controllerSessionProjection.motionAuthorizationUnavailableReason == nil)

    await submitControllerSession(workspace, .toggleMotionAuthorization)

    #expect(workspace.controllerSessionProjection.motionAuthorized)
    #expect(workspace.controllerSessionProjection.motionAuthorizationUnavailableReason == nil)

    await submitControllerSession(workspace, .toggleMotionAuthorization)

    #expect(!workspace.controllerSessionProjection.motionAuthorized)
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
    #expect(workspace.borderValidationSnapshot.step == .revealAndObserveNewInk)
    #expect(workspace.restartableExerciseItemID == nil)
    #expect(workspace.explorationError?.contains("will not restart") == true)
    await workspace.shutdown()
  }

  @Test("Drawing Border previews before motion and graduates automatically")
  func oneGoPreviewsThenGraduatesAutomatically() async throws {
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
    let drawingBorderPath = try #require(
      workspace.borderValidationSnapshot.drawingBorderPlan?.strokes.first?.path
    )
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
    #expect(workspace.borderValidationSnapshot.step == .moveToDrawingBorderStart)
    #expect(
      workspace.currentExerciseActionStripPresentation?.actions.contains {
        if case .stop = $0.kind { return true }
        return false
      } == true)

    await pacing.resume()
    await trial.value

    #expect(workspace.borderValidationSnapshot.assessment == .predictionObserved)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentExerciseActionStripPresentation == nil)
    #expect(workspace.completedDrawingComparisonReviewIsAvailable)
    #expect(!workspace.completedDrawingComparisonReviewIsPinned)
    #expect(!workspace.testActionSurfacePresentation.completedComparisonReview.isPresentedOnCanvas)
    #expect(workspace.workbenchCapabilityPresentation.learning == .interactiveLearningComplete)
    await workspace.reviewCompletedDrawingComparison()
    #expect(workspace.completedDrawingComparisonReviewIsPinned)
    let completedSurface = workspace.testActionSurfacePresentation
    #expect(completedSurface.completedComparisonReview.isPresentedOnCanvas)
    #expect(
      completedSurface.displayedFrame?.frame.id
        == workspace.borderValidationSnapshot.postFrame?.frame.id)
    #expect(
      Set(completedSurface.overlays.map(\.provenance.kind)).isSuperset(of: [
        .intendedPath,
        .observedInk,
        .residual,
      ]))

    let comparisonBeforeClose = workspace.borderValidationSnapshot
    let learningBeforeClose = Set(workspace.learningArtifactGraph.revisions)
    let simulatorBeforeClose = await harness.simulator.snapshot()
    let closeUI = workspace.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true)
    let close = try #require(closeUI.semantic.request(matching: .retainedComparisonReview(.resumeLivePreview)))
    #expect(await workspace.submitPlotterUIRequest(close) == .accepted(requestID: close.id))
    #expect(!workspace.completedDrawingComparisonReviewIsPinned)
    let closedSurface = workspace.testActionSurfacePresentation
    #expect(!closedSurface.completedComparisonReview.isPresentedOnCanvas)
    #expect(closedSurface.usesAmbientPreviewFrame)
    #expect(workspace.completedDrawingComparisonReviewIsAvailable)
    #expect(workspace.borderValidationSnapshot.postFrame == comparisonBeforeClose.postFrame)
    #expect(workspace.borderValidationSnapshot.inkObservation == comparisonBeforeClose.inkObservation)
    #expect(workspace.borderValidationSnapshot.drawingOutcome == comparisonBeforeClose.drawingOutcome)
    #expect(workspace.borderValidationSnapshot.assessment == comparisonBeforeClose.assessment)
    #expect(Set(workspace.learningArtifactGraph.revisions) == learningBeforeClose)
    #expect((await harness.simulator.snapshot()).mpos == simulatorBeforeClose.mpos)

    // Video Settings uses this same retained action after the canvas box closes.
    let reopenUI = workspace.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true)
    let reopen = try #require(reopenUI.semantic.request(matching: .retainedComparisonReview(.reviewExactFrame)))
    #expect(await workspace.submitPlotterUIRequest(reopen) == .accepted(requestID: reopen.id))
    try await waitUntil { workspace.completedDrawingComparisonReviewIsPinned }
    #expect(workspace.completedDrawingComparisonReviewIsPinned)
    #expect(workspace.testActionSurfacePresentation.completedComparisonReview.isPresentedOnCanvas)
    #expect(workspace.testActionSurfacePresentation.displayedFrame == comparisonBeforeClose.postFrame)
    #expect(
      workspace.testWorkbenchCapabilityPresentation.learning == .interactiveLearningComplete
    )
    #expect(workspace.frameMode == .simulated)
    #expect(!workspace.drawingDraftSnapshot.isTargetVisible)
    #expect(!workspace.paperCoverageIsCurrent)
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentExerciseActionStripPresentation == nil)
    let reviewUI = workspace.testPlotterUIProjection(selectedItemID: owner, includesLearningPath: true)
    let openStudio = try #require(reviewUI.semantic.request(matching: .drawingDraft(.showTarget)))
    let disposition = await workspace.submitPlotterUIRequest(openStudio)
    #expect(disposition == .accepted(requestID: openStudio.id))
    let studioIsPresented = workspace.drawingTargetIsVisible
    let comparisonIsPinned = workspace.completedDrawingComparisonReviewIsPinned
    #expect(studioIsPresented)
    #expect(!comparisonIsPinned)
    await workspace.shutdown()
  }

  @Test("injected Boundary ambiguity remains typed when wording is neutral")
  func boundaryAmbiguityDoesNotDependOnText() async throws {
    let harness = makeCausalSimulatorAppFixture()
    let workspace = harness.workspace
    await submitObservationConfigurationForTest(workspace, .selectSource(.simulated, nil))
    await submitControllerSession(workspace, .toggleConnection)
    await submitControllerSession(workspace, .toggleMotionAuthorization)

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
