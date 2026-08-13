import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Operator workspace typed lifecycle", .serialized)
@MainActor
struct OperatorWorkspaceLifecycleTests {
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

    await harness.runtime.injectFault(.outcomeUnavailableAfterNextExecution)
    try await performPublicAction(
      .drawIsolatedLine,
      owner: .observedDrawingTrial(.drawIsolatedLine),
      workspace: workspace
    )

    #expect(workspace.contextualStopPresentation == nil)
    #expect(workspace.observedDrawingTrialStep == .revealAndObserveNewInk)
    #expect(workspace.restartableExerciseItemID == nil)
    #expect(workspace.explorationError?.contains("will not be restarted") == true)
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
