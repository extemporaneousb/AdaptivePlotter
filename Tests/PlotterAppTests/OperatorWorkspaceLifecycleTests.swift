import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace typed lifecycle", .serialized)
@MainActor
struct OperatorWorkspaceLifecycleTests {
  @Test("top motion action enables and disables simulated authorization")
  func motionAuthorizationActionToggles() async {
    let harness = makeSimulatedHarness()
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
    #expect(workspace.motionUnavailableReason == "Enable simulated Motion first.")
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
      LearningMotionAction.sparseTipCircleChord(index: 16, total: 16).title
        == "Sparse Tip Circle chord 16/16"
    )
    #expect(
      LearningMotionAction.returnToLocalRevealPose.title == "Return to Local Reveal Pose"
    )
  }

  @Test("a second start cannot replace the active typed attempt")
  func duplicateStartRetainsActiveAttempt() async throws {
    let harness = makeSimulatedHarness()
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
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)

    workspace.replaceSimulatedExecutionPacingForTesting(
      DrawingOutcomeLossPacing(runtime: harness.runtime)
    )
    try await performPublicAction(
      .start,
      owner: .observedDrawingTrial(.chooseIsolatedLinePlan),
      workspace: workspace
    )

    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.observedDrawingTrialStep == .revealAndObserveNewInk)
    #expect(workspace.restartableExerciseItemID == nil)
    #expect(workspace.explorationError?.contains("will not be restarted") == true)
    await workspace.shutdown()
  }

  @Test("one Go previews the predicted line before motion and completes automatically")
  func oneGoPreviewsThenCompletesTrial() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    try await completeSimulatedBoundariesAndCenter(
      workspace,
      runtime: harness.runtime,
      boundaryOrder: [.negativeX, .positiveX, .negativeY, .positiveY]
    )
    try await completeSimulatedSparseTipCalibration(workspace, runtime: harness.runtime)
    let positionBeforeGo = (await harness.runtime.snapshot()).mpos
    let pacing = FirstOperationSuspensionPacing()
    workspace.replaceSimulatedExecutionPacingForTesting(pacing)
    let owner = LearningPathItemID.observedDrawingTrial(.chooseIsolatedLinePlan)

    let trial = Task { await workspace.performExerciseAction(.start, for: owner) }
    await pacing.waitUntilSuspended()

    let surface = workspace.actionSurfacePresentation
    let predicted = try #require(
      surface.overlays.first {
        $0.provenance.kind == .intendedPath && $0.provenance.source == .planned
      })
    let displayedFrame = try #require(surface.displayedFrame)
    let lineStart = try #require(workspace.drawingTrialLineStart)
    let lineEnd = try #require(workspace.drawingTrialLineEnd)
    let registration = try #require(workspace.tipCameraRegistration)
    guard case .polyline(let predictedLine) = predicted.geometry else {
      Issue.record("The model prediction must be a camera-pixel polyline.")
      return
    }
    #expect(predicted.frameID == displayedFrame.frame.id)
    #expect(predicted.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID)
    #expect(
      predictedLine.points == [
        try registration.tipPixel(at: lineStart.point),
        try registration.tipPixel(at: lineEnd.point),
      ])
    #expect((await harness.runtime.snapshot()).mpos == positionBeforeGo)
    #expect(workspace.observedDrawingTrialStep == .moveToLineStart)
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
    let completedSurface = workspace.actionSurfacePresentation
    #expect(
      completedSurface.displayedFrame?.frame.id == workspace.explorationPostLineFrame?.frame.id)
    #expect(
      Set(completedSurface.overlays.map(\.provenance.kind)).isSuperset(of: [
        .intendedPath,
        .observedInk,
        .residual,
      ]))

    workspace.resumeLivePreviewAfterDrawingComparison()
    #expect(!workspace.completedDrawingComparisonReviewIsPinned)
    workspace.reviewCompletedDrawingComparison()
    #expect(workspace.completedDrawingComparisonReviewIsPinned)
    #expect(
      workspace.workbenchCapabilityPresentation.learning == .interactiveLearningComplete
    )

    workspace.confirmCurrentPaperCoversDrawableRegion()
    #expect(workspace.paperCoverageIsCurrent)
    #expect(
      workspace.workbenchCapabilityPresentation.paper
        == .current(
          detail: "Operator assertion: this sheet covers the outline; paper edges were not measured.")
    )
    workspace.openDrawingStudio()
    #expect(!workspace.completedDrawingComparisonReviewIsPinned)
    await workspace.performDrawingStudioAction(.selectCatalogItem(.elephant))
    await workspace.performDrawingStudioAction(.centerInDrawableRegion)
    let studio = workspace.drawingStudioPresentation
    let studioFrame = try #require(workspace.actionSurfacePresentation.displayedFrame)
    #expect(workspace.drawingStudioIsPresented)
    #expect(studio.selectedCatalogItemID == .elephant)
    #expect(studio.canvas.targetPreview?.provenance.matches(studioFrame) == true)
    #expect(studio.canvas.targetPreview?.executionPlanContentHash != nil)
    #expect(studio.canvas.targetPreview?.status == .ready)
    if case .unavailable(let reason) = studio.runState {
      #expect(reason.contains("SIMULATED previews placement"))
    } else {
      Issue.record("Simulation must preview an immutable plan without claiming physical execution.")
    }
    #expect(workspace.activeExerciseAttemptID == nil)
    #expect(workspace.currentExerciseActionStripPresentation == nil)

    let originalPaper = workspace.currentPaperRevisionContext
    let acceptedTipRevision = workspace.tipCameraRegistration?.acceptedRevisionID
    await workspace.recordNewPaperSheetOnCurrentPlane()
    #expect(workspace.currentPaperRevisionContext.instance != originalPaper.instance)
    #expect(workspace.currentPaperRevisionContext.contactPlane == originalPaper.contactPlane)
    #expect(workspace.tipCameraRegistration?.acceptedRevisionID == acceptedTipRevision)
    #expect(!workspace.paperCoverageIsCurrent)

    await workspace.recordPaperContactPlaneChanged()
    #expect(workspace.currentPaperRevisionContext.contactPlane != originalPaper.contactPlane)
    #expect(workspace.tipCameraRegistration == nil)
    #expect(workspace.activeExerciseAttemptID == nil)
    await workspace.shutdown()
  }

  @Test("injected Boundary ambiguity remains typed when wording is neutral")
  func boundaryAmbiguityDoesNotDependOnText() async throws {
    let harness = makeSimulatedHarness()
    let workspace = harness.workspace
    await workspace.switchFrameMode(.simulated)
    await workspace.performControllerConnectionAction()
    await workspace.activateMotionGuard()

    let penOwner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
    try await performPublicAction(.start, owner: penOwner, workspace: workspace)
    try await identifyPenCap(workspace)
    for _ in 0..<3 {
      try await performPublicAction(.choice(.yes), owner: penOwner, workspace: workspace)
    }

    await harness.runtime.injectFault(.ambiguityBeforeNextBoundarySegment)
    let boundaryOwner = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    try await performPublicAction(.start, owner: boundaryOwner, workspace: workspace)
    try await waitUntil { workspace.activeExerciseAttemptID == nil }

    guard case .ambiguous(let detail) = workspace.boundaryActivityRecords.last?.disposition else {
      Issue.record("Expected typed ambiguous Boundary disposition")
      return
    }
    #expect(detail == "The simulated Boundary owner lost attributable segment completion.")
    #expect(workspace.contextualStopPresentation == nil)
    await workspace.shutdown()
  }
}

private actor DrawingOutcomeLossPacing: SimulatedLearningExecutionPacing {
  let runtime: SimulatedLearningRuntime
  var suspensionCount = 0

  init(runtime: SimulatedLearningRuntime) {
    self.runtime = runtime
  }

  func suspendBetweenSteps() async {
    suspensionCount += 1
    if suspensionCount == 2 {
      await runtime.injectFault(.outcomeUnavailableAfterNextExecution)
    }
    await Task.yield()
  }
}
