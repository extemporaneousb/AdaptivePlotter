import Testing

@testable import PlotterModel

@Suite("Finite execution plans")
struct ExecutionPlanTests {
  @Test("bootstrap plan uses the closed vocabulary and ends at one checkpoint")
  func validBootstrapPlan() throws {
    let first = try executionPlan()
    let second = try executionPlan()
    #expect(first.instructions.count == 11)
    #expect(first.contentHash == second.contentHash)
    guard case .checkpoint = first.instructions.last else {
      Issue.record("plan did not end at checkpoint")
      return
    }
  }

  @Test("checkpoint is unique and terminal")
  func checkpointTerminal() throws {
    var instructions = try validInstructions()
    instructions.removeLast()
    #expect(throws: ExecutionPlanError.checkpointMustBeUniqueAndLast) {
      _ = try executionPlan(instructions: instructions)
    }
  }

  @Test("draw is pinned to the plan model")
  func modelPinned() throws {
    let wrong = ModelID(uuid("ffffffff-ffff-ffff-ffff-ffffffffffff"))
    #expect(throws: ExecutionPlanError.drawModelMismatch) {
      _ = try executionPlan(instructions: validInstructions(modelID: wrong))
    }
  }

  @Test("draw cannot occur without a clean baseline inspection")
  func baselineRequired() throws {
    var instructions = try validInstructions()
    instructions.removeSubrange(1...2)
    #expect(throws: ExecutionPlanError.baselineRequiredBeforeDraw) {
      _ = try executionPlan(instructions: instructions)
    }
  }

  @Test("post-draw lift, clearance, fresh frame, and inspection are mandatory")
  func postDrawAtomRequired() throws {
    var instructions = try validInstructions()
    instructions.remove(at: 7)
    #expect(throws: ExecutionPlanError.drawMustBeFollowedByLiftClearFrameAndInspection) {
      _ = try executionPlan(instructions: instructions)
    }
  }
}

@Suite("Frontiers and authority")
struct FrontierAuthorityTests {
  @Test("controller completion cannot exceed the commanded frontier")
  func frontierOrdering() {
    #expect(
      throws: PlotterModelError.invalidValue("controller completion exceeds commanded frontier")
    ) {
      _ = try ExecutionFrontiers(
        planID: IDs.plan,
        commandedThrough: PlanCursor(planID: IDs.plan, instructionIndex: 4),
        controllerCompletedThrough: PlanCursor(planID: IDs.plan, instructionIndex: 5),
        inkBySlice: [:]
      )
    }
  }

  @Test("ink verification cannot exceed controller completion")
  func inkCannotLeadController() {
    let commanded = PlanCursor(planID: IDs.plan, instructionIndex: 5)
    #expect(
      throws: PlotterModelError.invalidValue("ink fact exceeds controller-completed frontier")
    ) {
      _ = try ExecutionFrontiers(
        planID: IDs.plan,
        commandedThrough: commanded,
        controllerCompletedThrough: PlanCursor(planID: IDs.plan, instructionIndex: 3),
        inkBySlice: [
          IDs.slice: SliceExecutionFact(
            drawCursor: PlanCursor(planID: IDs.plan, instructionIndex: 4),
            disposition: .verified(IDs.observation)
          )
        ]
      )
    }
  }

  @Test("commanded or ink-dispositioned work is never automatically replanned")
  func noAutomaticRedraw() throws {
    let drawCursor = PlanCursor(planID: IDs.plan, instructionIndex: 4)
    let frontiers = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: drawCursor,
      controllerCompletedThrough: drawCursor,
      inkBySlice: [
        IDs.slice: SliceExecutionFact(
          drawCursor: drawCursor,
          disposition: .ambiguous(reasons: ["unknown write outcome"])
        )
      ]
    )
    #expect(!frontiers.mayPlanAutomatically(sliceID: IDs.slice, at: drawCursor))
    #expect(
      !frontiers.mayPlanAutomatically(
        sliceID: IDs.otherSlice,
        at: PlanCursor(planID: IDs.plan, instructionIndex: 3)
      ))
    #expect(
      frontiers.mayPlanAutomatically(
        sliceID: IDs.otherSlice,
        at: PlanCursor(planID: IDs.plan, instructionIndex: 6)
      ))
  }

  @Test("isolated training authority is distinct from general drawing")
  func operationDistinct() throws {
    let value = try authority()
    #expect(value.allowed)
    #expect(value.operation == .isolatedTrainingProbe)
    #expect(value.operation != .generalDrawing)
  }

  @Test("allowed authority cannot coexist with blockers")
  func authorityInvariant() throws {
    let blocker = try RunBlocker(code: "camera_stale", summary: "No fresh frame")
    #expect(
      throws: PlotterModelError.invalidValue(
        "authority allowed state conflicts with blockers/operation")
    ) {
      _ = try ExecutionAuthority(
        allowed: true,
        operation: .isolatedTrainingProbe,
        planID: IDs.plan,
        modelID: IDs.model,
        stateEstimateID: IDs.state,
        fixedSafetyPolicyID: IDs.safety,
        evidence: [],
        limits: AuthorityLimits(
          maximumFeed: 10,
          maximumDistance: 10,
          maximumCommandHorizonNanoseconds: 1
        ),
        blockers: [blocker]
      )
    }
  }
}

@Suite("Residuals and recorded replay")
struct ResidualReplayTests {
  @Test("goal residual and model innovation remain separate")
  func residuals() throws {
    let correspondence = try CorrespondedGeometry(
      intended: Polyline(points: [fieldPoint(0, 0), fieldPoint(10, 0)]),
      predicted: Polyline(points: [fieldPoint(1, 0), fieldPoint(11, 0)]),
      observed: Polyline(points: [fieldPoint(2, 0), fieldPoint(12, 0)])
    )
    let result = try ResidualCalculator.evaluate(correspondence)
    #expect(result.goalMetrics.rootMeanSquare == 2)
    #expect(result.modelMetrics.rootMeanSquare == 1)
    #expect(result.goalResiduals[0].dx == 2)
    #expect(result.modelInnovations[0].dx == 1)
  }

  @Test("checkpoint decision records independent evidence, state, model, and next action")
  func checkpointProduct() throws {
    let prior = try emptyFrontiers()
    let cursor = PlanCursor(planID: IDs.plan, instructionIndex: 9)
    let result = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: cursor,
      controllerCompletedThrough: cursor,
      inkBySlice: [
        IDs.slice: SliceExecutionFact(
          drawCursor: PlanCursor(planID: IDs.plan, instructionIndex: 4),
          disposition: .verified(IDs.observation)
        )
      ]
    )
    let decision = CheckpointDecision(
      evidenceDisposition: .accepted(IDs.evidence),
      stateSelection: .retain(IDs.state),
      modelSelection: .retain(IDs.model, reasons: ["insufficient independent trials"]),
      nextAction: .complete
    )
    let basis = try PlanningBasis(
      programID: IDs.program,
      currentPlanID: IDs.plan,
      modelID: IDs.model,
      stateEstimateID: IDs.state,
      safetyPolicyID: IDs.safety,
      unresolvedSlices: []
    )
    let first = try CheckpointResolution(
      id: IDs.resolution,
      checkpointID: IDs.checkpoint,
      decision: decision,
      priorFrontiers: prior,
      resultingFrontiers: result,
      nextPlanningBasis: basis
    )
    let second = try CheckpointResolution(
      id: IDs.resolution,
      checkpointID: IDs.checkpoint,
      decision: decision,
      priorFrontiers: prior,
      resultingFrontiers: result,
      nextPlanningBasis: basis
    )
    #expect(first.contentHash == second.contentHash)
  }

  @Test("recorded replay consumes decisions without rerunning algorithms")
  func recordedReplay() throws {
    let initialFrontiers = try emptyFrontiers()
    let startAuthority = try authority()
    let completedCursor = PlanCursor(planID: IDs.plan, instructionIndex: 9)
    let completedFrontiers = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: completedCursor,
      controllerCompletedThrough: completedCursor,
      inkBySlice: [
        IDs.slice: SliceExecutionFact(
          drawCursor: PlanCursor(planID: IDs.plan, instructionIndex: 4),
          disposition: .verified(IDs.observation)
        )
      ]
    )
    let decision = CheckpointDecision(
      evidenceDisposition: .accepted(IDs.evidence),
      stateSelection: .retain(IDs.state),
      modelSelection: .retain(IDs.model, reasons: ["first trial"]),
      nextAction: .complete
    )
    let resolution = try CheckpointResolution(
      id: IDs.resolution,
      checkpointID: IDs.checkpoint,
      decision: decision,
      priorFrontiers: initialFrontiers,
      resultingFrontiers: completedFrontiers,
      nextPlanningBasis: PlanningBasis(
        programID: IDs.program,
        currentPlanID: IDs.plan,
        modelID: IDs.model,
        stateEstimateID: IDs.state,
        safetyPolicyID: IDs.safety,
        unresolvedSlices: []
      )
    )
    let replay = try RecordedRunReducer.replay([
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 40,
        event: .runStarted(
          programID: IDs.program,
          planID: IDs.plan,
          modelID: IDs.model,
          authority: startAuthority,
          frontiers: initialFrontiers
        )
      ),
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 41,
        event: .instructionAdvanced(completedCursor)
      ),
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 42,
        event: .checkpointResolved(resolution)
      ),
    ])
    #expect(replay.status == .complete)
    #expect(replay.frontiers == completedFrontiers)
    #expect(replay.lastCheckpointResolutionID == IDs.resolution)
    #expect(replay.lastSequence == 42)
  }

  @Test("recorded replay rejects missing sequence numbers")
  func replaySequenceGate() throws {
    let frontiers = try emptyFrontiers()
    let start = SequencedRunEvent(
      runID: IDs.run,
      sequence: 1,
      event: .runStarted(
        programID: IDs.program,
        planID: IDs.plan,
        modelID: IDs.model,
        authority: try authority(),
        frontiers: frontiers
      )
    )
    #expect(throws: RecordedReplayError.nonContiguousSequence(expected: 2, actual: 3)) {
      _ = try RecordedRunReducer.replay([
        start,
        SequencedRunEvent(runID: IDs.run, sequence: 3, event: .completed),
      ])
    }
  }

  @Test("checkpoint selection IDs must match the next planning basis")
  func checkpointSelectionIdentity() throws {
    let frontiers = try emptyFrontiers()
    let decision = CheckpointDecision(
      evidenceDisposition: .accepted(IDs.evidence),
      stateSelection: .retain(IDs.state),
      modelSelection: .retain(IDs.model, reasons: []),
      nextAction: .complete
    )
    #expect(
      throws: PlotterModelError.invalidValue(
        "checkpoint selections disagree with the next planning basis"
      )
    ) {
      _ = try CheckpointResolution(
        id: IDs.resolution,
        checkpointID: IDs.checkpoint,
        decision: decision,
        priorFrontiers: frontiers,
        resultingFrontiers: frontiers,
        nextPlanningBasis: PlanningBasis(
          programID: IDs.program,
          currentPlanID: IDs.plan,
          modelID: IDs.successorModel,
          stateEstimateID: IDs.state,
          safetyPolicyID: IDs.safety,
          unresolvedSlices: []
        )
      )
    }
  }

  @Test("checkpoint resolution rejects frontier regression")
  func checkpointFrontierRegression() throws {
    let priorCursor = PlanCursor(planID: IDs.plan, instructionIndex: 5)
    let prior = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: priorCursor,
      controllerCompletedThrough: priorCursor,
      inkBySlice: [:]
    )
    let regressedCursor = PlanCursor(planID: IDs.plan, instructionIndex: 4)
    let regressed = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: regressedCursor,
      controllerCompletedThrough: regressedCursor,
      inkBySlice: [:]
    )
    #expect(throws: PlotterModelError.invalidValue("checkpoint frontiers regress")) {
      _ = try CheckpointResolution(
        id: IDs.resolution,
        checkpointID: IDs.checkpoint,
        decision: CheckpointDecision(
          evidenceDisposition: .accepted(IDs.evidence),
          stateSelection: .retain(IDs.state),
          modelSelection: .retain(IDs.model, reasons: []),
          nextAction: .complete
        ),
        priorFrontiers: prior,
        resultingFrontiers: regressed,
        nextPlanningBasis: PlanningBasis(
          programID: IDs.program,
          currentPlanID: IDs.plan,
          modelID: IDs.model,
          stateEstimateID: IDs.state,
          safetyPolicyID: IDs.safety,
          unresolvedSlices: []
        )
      )
    }
  }

  @Test("recorded replay requires checkpoint prior frontiers to equal live replay state")
  func checkpointPriorMustMatchReplay() throws {
    let initial = try emptyFrontiers()
    let cursor = PlanCursor(planID: IDs.plan, instructionIndex: 3)
    let claimedPrior = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: cursor,
      controllerCompletedThrough: cursor,
      inkBySlice: [:]
    )
    let resolution = try CheckpointResolution(
      id: IDs.resolution,
      checkpointID: IDs.checkpoint,
      decision: CheckpointDecision(
        evidenceDisposition: .accepted(IDs.evidence),
        stateSelection: .retain(IDs.state),
        modelSelection: .retain(IDs.model, reasons: []),
        nextAction: .complete
      ),
      priorFrontiers: claimedPrior,
      resultingFrontiers: claimedPrior,
      nextPlanningBasis: PlanningBasis(
        programID: IDs.program,
        currentPlanID: IDs.plan,
        modelID: IDs.model,
        stateEstimateID: IDs.state,
        safetyPolicyID: IDs.safety,
        unresolvedSlices: []
      )
    )
    #expect(throws: RecordedReplayError.checkpointPriorFrontiersMismatch) {
      _ = try RecordedRunReducer.replay([
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 1,
          event: .runStarted(
            programID: IDs.program,
            planID: IDs.plan,
            modelID: IDs.model,
            authority: authority(),
            frontiers: initial
          )
        ),
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 2,
          event: .checkpointResolved(resolution)
        ),
      ])
    }
  }

  @Test("recorded replay rejects a regressing frontier event")
  func replayFrontierRegression() throws {
    let cursor = PlanCursor(planID: IDs.plan, instructionIndex: 3)
    let progressed = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: cursor,
      controllerCompletedThrough: cursor,
      inkBySlice: [:]
    )
    #expect(throws: RecordedReplayError.frontierRegression) {
      _ = try RecordedRunReducer.replay([
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 1,
          event: .runStarted(
            programID: IDs.program,
            planID: IDs.plan,
            modelID: IDs.model,
            authority: authority(),
            frontiers: progressed
          )
        ),
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 2,
          event: .frontiersChanged(emptyFrontiers())
        ),
      ])
    }
  }

  @Test("authority changes cannot switch plan or model identity")
  func replayAuthorityIdentity() throws {
    let mismatched = try authority(
      planID: IDs.successorPlan,
      modelID: IDs.successorModel,
      stateEstimateID: IDs.successorState
    )
    #expect(throws: RecordedReplayError.authorityIdentityMismatch) {
      _ = try RecordedRunReducer.replay([
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 1,
          event: .runStarted(
            programID: IDs.program,
            planID: IDs.plan,
            modelID: IDs.model,
            authority: authority(),
            frontiers: emptyFrontiers()
          )
        ),
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 2,
          event: .authorityChanged(mismatched)
        ),
      ])
    }
  }

  @Test("multi-plan replay requires and installs an explicit successor activation")
  func successorPlanReplay() throws {
    let initialFrontiers = try emptyFrontiers()
    let resolution = try successorResolution(priorFrontiers: initialFrontiers)
    let activation = try successorActivation()
    let replay = try RecordedRunReducer.replay([
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 1,
        event: .runStarted(
          programID: IDs.program,
          planID: IDs.plan,
          modelID: IDs.model,
          authority: authority(),
          frontiers: initialFrontiers
        )
      ),
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 2,
        event: .checkpointResolved(resolution)
      ),
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 3,
        event: .successorPlanActivated(activation)
      ),
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 4,
        event: .instructionAdvanced(
          PlanCursor(planID: IDs.successorPlan, instructionIndex: 1)
        )
      ),
    ])
    #expect(replay.planID == IDs.successorPlan)
    #expect(replay.modelID == IDs.successorModel)
    #expect(replay.stateEstimateID == IDs.successorState)
    #expect(replay.frontiers == activation.frontiers)
    #expect(replay.authority == activation.authority)
    #expect(replay.pendingSuccessorBasis == nil)
  }

  @Test("replay fails closed when a successor checkpoint has no activation")
  func successorActivationMustComplete() throws {
    let initial = try emptyFrontiers()
    let resolution = try successorResolution(priorFrontiers: initial)
    #expect(throws: RecordedReplayError.incompleteSuccessorActivation) {
      _ = try RecordedRunReducer.replay([
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 1,
          event: .runStarted(
            programID: IDs.program,
            planID: IDs.plan,
            modelID: IDs.model,
            authority: authority(),
            frontiers: initial
          )
        ),
        SequencedRunEvent(
          runID: IDs.run,
          sequence: 2,
          event: .checkpointResolved(resolution)
        ),
      ])
    }
  }

  @Test("successor activation must advance to a genuinely new plan")
  func successorActivationMustAdvancePlan() throws {
    let initial = try emptyFrontiers()
    let resolution = try successorResolution(priorFrontiers: initial)
    let activation = try successorActivation(planID: IDs.plan)
    #expect(throws: RecordedReplayError.successorPlanDidNotAdvance) {
      _ = try replaySuccessor(resolution: resolution, activation: activation, initial: initial)
    }
  }

  @Test("successor activation retains the checkpoint program")
  func successorActivationRetainsProgram() throws {
    let initial = try emptyFrontiers()
    let resolution = try successorResolution(priorFrontiers: initial)
    let activation = try successorActivation(programID: IDs.otherProgram)
    #expect(throws: RecordedReplayError.successorProgramMismatch) {
      _ = try replaySuccessor(resolution: resolution, activation: activation, initial: initial)
    }
  }

  @Test("successor activation retains the checkpoint safety policy")
  func successorActivationRetainsSafetyPolicy() throws {
    let initial = try emptyFrontiers()
    let resolution = try successorResolution(priorFrontiers: initial)
    let activation = try successorActivation(safetyPolicyID: IDs.otherSafety)
    #expect(throws: RecordedReplayError.successorSafetyPolicyMismatch) {
      _ = try replaySuccessor(resolution: resolution, activation: activation, initial: initial)
    }
  }

  @Test("successor checkpoint basis cannot replace the run program")
  func successorBasisRetainsProgram() throws {
    let initial = try emptyFrontiers()
    let resolution = try successorResolution(
      priorFrontiers: initial,
      programID: IDs.otherProgram
    )
    let activation = try successorActivation(programID: IDs.otherProgram)
    #expect(throws: RecordedReplayError.successorProgramMismatch) {
      _ = try replaySuccessor(resolution: resolution, activation: activation, initial: initial)
    }
  }

  @Test("successor checkpoint basis cannot replace the fixed safety policy")
  func successorBasisRetainsSafetyPolicy() throws {
    let initial = try emptyFrontiers()
    let resolution = try successorResolution(
      priorFrontiers: initial,
      safetyPolicyID: IDs.otherSafety
    )
    let activation = try successorActivation(safetyPolicyID: IDs.otherSafety)
    #expect(throws: RecordedReplayError.successorSafetyPolicyMismatch) {
      _ = try replaySuccessor(resolution: resolution, activation: activation, initial: initial)
    }
  }

  private func replaySuccessor(
    resolution: CheckpointResolution,
    activation: SuccessorPlanActivation,
    initial: ExecutionFrontiers
  ) throws -> RecordedRunState {
    try RecordedRunReducer.replay([
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 1,
        event: .runStarted(
          programID: IDs.program,
          planID: IDs.plan,
          modelID: IDs.model,
          authority: authority(),
          frontiers: initial
        )
      ),
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 2,
        event: .checkpointResolved(resolution)
      ),
      SequencedRunEvent(
        runID: IDs.run,
        sequence: 3,
        event: .successorPlanActivated(activation)
      ),
    ])
  }
}
