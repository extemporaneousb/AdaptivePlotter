import Foundation

public struct CorrespondedGeometry: Hashable, Codable, Sendable {
  public let intended: Polyline<FieldSpace>
  public let predicted: Polyline<FieldSpace>
  public let observed: Polyline<FieldSpace>

  public init(
    intended: Polyline<FieldSpace>,
    predicted: Polyline<FieldSpace>,
    observed: Polyline<FieldSpace>
  ) throws {
    guard intended.points.count == predicted.points.count,
      predicted.points.count == observed.points.count
    else { throw PlotterModelError.invalidValue("corresponded paths require equal point counts") }
    self.intended = intended
    self.predicted = predicted
    self.observed = observed
  }

  private enum CodingKeys: String, CodingKey { case intended, predicted, observed }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      intended: container.decode(Polyline<FieldSpace>.self, forKey: .intended),
      predicted: container.decode(Polyline<FieldSpace>.self, forKey: .predicted),
      observed: container.decode(Polyline<FieldSpace>.self, forKey: .observed)
    )
  }
}

public struct ResidualMetrics: Hashable, Codable, Sendable {
  public let rootMeanSquare: Double
  public let maximum: Double

  public init(rootMeanSquare: Double, maximum: Double) throws {
    guard rootMeanSquare.isFinite, rootMeanSquare >= 0,
      maximum.isFinite, maximum >= 0
    else { throw GeometryError.nonFiniteCoordinate }
    self.rootMeanSquare = rootMeanSquare
    self.maximum = maximum
  }

  private enum CodingKeys: String, CodingKey { case rootMeanSquare, maximum }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      rootMeanSquare: container.decode(Double.self, forKey: .rootMeanSquare),
      maximum: container.decode(Double.self, forKey: .maximum)
    )
  }
}

public struct ResidualEvaluation: Hashable, Codable, Sendable {
  public let correspondence: CorrespondedGeometry
  public let goalResiduals: [Vector2<FieldSpace>]
  public let modelInnovations: [Vector2<FieldSpace>]
  public let goalMetrics: ResidualMetrics
  public let modelMetrics: ResidualMetrics

  init(
    correspondence: CorrespondedGeometry,
    goalResiduals: [Vector2<FieldSpace>],
    modelInnovations: [Vector2<FieldSpace>],
    goalMetrics: ResidualMetrics,
    modelMetrics: ResidualMetrics
  ) {
    self.correspondence = correspondence
    self.goalResiduals = goalResiduals
    self.modelInnovations = modelInnovations
    self.goalMetrics = goalMetrics
    self.modelMetrics = modelMetrics
  }

  private enum CodingKeys: String, CodingKey {
    case correspondence, goalResiduals, modelInnovations, goalMetrics, modelMetrics
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let correspondence = try container.decode(CorrespondedGeometry.self, forKey: .correspondence)
    let recomputed = try ResidualCalculator.evaluate(correspondence)
    let goalResiduals = try container.decode(
      [Vector2<FieldSpace>].self,
      forKey: .goalResiduals
    )
    let modelInnovations = try container.decode(
      [Vector2<FieldSpace>].self,
      forKey: .modelInnovations
    )
    let goalMetrics = try container.decode(ResidualMetrics.self, forKey: .goalMetrics)
    let modelMetrics = try container.decode(ResidualMetrics.self, forKey: .modelMetrics)
    guard recomputed.goalResiduals == goalResiduals,
      recomputed.modelInnovations == modelInnovations,
      recomputed.goalMetrics == goalMetrics,
      recomputed.modelMetrics == modelMetrics
    else { throw PlotterModelError.invalidValue("durable residual evaluation is inconsistent") }
    self = recomputed
  }
}

public enum ResidualCalculator {
  public static func evaluate(_ correspondence: CorrespondedGeometry) throws -> ResidualEvaluation {
    let goal = try zip(correspondence.intended.points, correspondence.observed.points).map {
      try $0.vector(to: $1)
    }
    let model = try zip(correspondence.predicted.points, correspondence.observed.points).map {
      try $0.vector(to: $1)
    }
    return ResidualEvaluation(
      correspondence: correspondence,
      goalResiduals: goal,
      modelInnovations: model,
      goalMetrics: try metrics(for: goal),
      modelMetrics: try metrics(for: model)
    )
  }

  private static func metrics(for residuals: [Vector2<FieldSpace>]) throws -> ResidualMetrics {
    let magnitudes = residuals.map(\.magnitude)
    let rms = sqrt(magnitudes.reduce(0) { $0 + $1 * $1 } / Double(magnitudes.count))
    guard let maximum = magnitudes.max() else {
      throw PlotterModelError.invalidValue("residual set cannot be empty")
    }
    return try ResidualMetrics(rootMeanSquare: rms, maximum: maximum)
  }
}

public enum RecordedRunStatus: UInt8, Codable, Sendable {
  case idle = 0
  case active = 1
  case paused = 2
  case complete = 3
  case aborted = 4
}

public struct SuccessorPlanActivation: Hashable, Codable, Sendable {
  public let programID: ProgramID
  public let planID: PlanID
  public let modelID: ModelID
  public let stateEstimateID: StateEstimateID
  public let safetyPolicyID: SafetyPolicyID
  public let frontiers: ExecutionFrontiers
  public let authority: ExecutionAuthority

  public init(
    programID: ProgramID,
    planID: PlanID,
    modelID: ModelID,
    stateEstimateID: StateEstimateID,
    safetyPolicyID: SafetyPolicyID,
    frontiers: ExecutionFrontiers,
    authority: ExecutionAuthority
  ) throws {
    guard frontiers.planID == planID else {
      throw PlotterModelError.invalidValue(
        "successor activation frontiers must reference the successor plan"
      )
    }
    guard frontiers.commandedThrough == nil,
      frontiers.controllerCompletedThrough == nil,
      frontiers.inkBySlice.isEmpty
    else {
      throw PlotterModelError.invalidValue(
        "successor activation frontiers must be fresh"
      )
    }
    guard authority.planID == planID,
      authority.modelID == modelID,
      authority.stateEstimateID == stateEstimateID,
      authority.fixedSafetyPolicyID == safetyPolicyID
    else {
      throw PlotterModelError.invalidValue(
        "successor activation authority identity mismatch"
      )
    }
    self.programID = programID
    self.planID = planID
    self.modelID = modelID
    self.stateEstimateID = stateEstimateID
    self.safetyPolicyID = safetyPolicyID
    self.frontiers = frontiers
    self.authority = authority
  }

  private enum CodingKeys: String, CodingKey {
    case programID, planID, modelID, stateEstimateID, safetyPolicyID, frontiers, authority
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      programID: container.decode(ProgramID.self, forKey: .programID),
      planID: container.decode(PlanID.self, forKey: .planID),
      modelID: container.decode(ModelID.self, forKey: .modelID),
      stateEstimateID: container.decode(StateEstimateID.self, forKey: .stateEstimateID),
      safetyPolicyID: container.decode(SafetyPolicyID.self, forKey: .safetyPolicyID),
      frontiers: container.decode(ExecutionFrontiers.self, forKey: .frontiers),
      authority: container.decode(ExecutionAuthority.self, forKey: .authority)
    )
  }
}

public enum RecordedRunEvent: Hashable, Codable, Sendable {
  case runStarted(
    programID: ProgramID,
    planID: PlanID,
    modelID: ModelID,
    authority: ExecutionAuthority,
    frontiers: ExecutionFrontiers
  )
  case authorityChanged(ExecutionAuthority)
  case instructionAdvanced(PlanCursor)
  case frontiersChanged(ExecutionFrontiers)
  case checkpointResolved(CheckpointResolution)
  case successorPlanActivated(SuccessorPlanActivation)
  case paused([RunBlocker])
  case completed
  case aborted(String)
}

public struct SequencedRunEvent: Hashable, Codable, Sendable {
  public let runID: RunID
  public let sequence: UInt64
  public let event: RecordedRunEvent

  public init(runID: RunID, sequence: UInt64, event: RecordedRunEvent) {
    self.runID = runID
    self.sequence = sequence
    self.event = event
  }
}

public struct RecordedRunState: Hashable, Codable, Sendable {
  public let runID: RunID
  public var lastSequence: UInt64
  public var status: RecordedRunStatus
  public let programID: ProgramID
  public var planID: PlanID
  public var modelID: ModelID
  public var stateEstimateID: StateEstimateID?
  public var instructionCursor: PlanCursor?
  public var frontiers: ExecutionFrontiers
  public var authority: ExecutionAuthority
  public var blockers: [RunBlocker]
  public var lastCheckpointResolutionID: CheckpointResolutionID?
  public var pendingSuccessorBasis: PlanningBasis?
}

public enum RecordedReplayError: Error, Equatable, Sendable {
  case empty
  case firstEventMustStartRun
  case mixedRunIDs
  case nonContiguousSequence(expected: UInt64, actual: UInt64)
  case terminalRunHasLaterEvents
  case planIdentityMismatch
  case checkpointPriorFrontiersMismatch
  case successorActivationRequired
  case unexpectedSuccessorActivation
  case successorAuthorityMismatch
  case frontierRegression
  case authorityIdentityMismatch
  case successorPlanDidNotAdvance
  case successorProgramMismatch
  case successorSafetyPolicyMismatch
  case successorPlanningBasisMismatch
  case incompleteSuccessorActivation
}

/// Pure recorded-decision replay. It applies persisted semantic facts exactly;
/// it does not rerun measurement, authority, fitting, or planning algorithms.
public enum RecordedRunReducer {
  public static func replay(_ events: [SequencedRunEvent]) throws -> RecordedRunState {
    guard let first = events.first else { throw RecordedReplayError.empty }
    guard case let .runStarted(programID, planID, modelID, authority, frontiers) = first.event
    else {
      throw RecordedReplayError.firstEventMustStartRun
    }
    guard frontiers.planID == planID else { throw RecordedReplayError.planIdentityMismatch }
    guard authority.planID == nil || authority.planID == planID,
      authority.modelID == nil || authority.modelID == modelID
    else { throw RecordedReplayError.successorAuthorityMismatch }

    var state = RecordedRunState(
      runID: first.runID,
      lastSequence: first.sequence,
      status: .active,
      programID: programID,
      planID: planID,
      modelID: modelID,
      stateEstimateID: authority.stateEstimateID,
      instructionCursor: nil,
      frontiers: frontiers,
      authority: authority,
      blockers: authority.blockers,
      lastCheckpointResolutionID: nil,
      pendingSuccessorBasis: nil
    )

    for recorded in events.dropFirst() {
      guard recorded.runID == state.runID else { throw RecordedReplayError.mixedRunIDs }
      let expected = state.lastSequence + 1
      guard recorded.sequence == expected else {
        throw RecordedReplayError.nonContiguousSequence(
          expected: expected, actual: recorded.sequence)
      }
      guard state.status == .active || state.status == .paused else {
        throw RecordedReplayError.terminalRunHasLaterEvents
      }
      if state.pendingSuccessorBasis != nil {
        guard case .successorPlanActivated = recorded.event else {
          throw RecordedReplayError.successorActivationRequired
        }
      }
      switch recorded.event {
      case .runStarted:
        throw RecordedReplayError.firstEventMustStartRun
      case let .authorityChanged(authority):
        guard authority.planID == nil || authority.planID == state.planID,
          authority.modelID == nil || authority.modelID == state.modelID,
          authority.stateEstimateID == nil
            || authority.stateEstimateID == state.stateEstimateID
        else { throw RecordedReplayError.authorityIdentityMismatch }
        state.authority = authority
        state.blockers = authority.blockers
        if !authority.allowed { state.status = .paused }
      case let .instructionAdvanced(cursor):
        guard cursor.planID == state.planID else {
          throw RecordedReplayError.planIdentityMismatch
        }
        state.instructionCursor = cursor
      case let .frontiersChanged(frontiers):
        guard frontiers.planID == state.planID else {
          throw RecordedReplayError.planIdentityMismatch
        }
        guard try frontiers.isNonRegressing(from: state.frontiers) else {
          throw RecordedReplayError.frontierRegression
        }
        state.frontiers = frontiers
      case let .checkpointResolved(resolution):
        guard resolution.resultingFrontiers.planID == state.planID else {
          throw RecordedReplayError.planIdentityMismatch
        }
        guard resolution.priorFrontiers == state.frontiers else {
          throw RecordedReplayError.checkpointPriorFrontiersMismatch
        }
        state.frontiers = resolution.resultingFrontiers
        state.lastCheckpointResolutionID = resolution.id
        switch resolution.decision.modelSelection {
        case let .retain(id, _): state.modelID = id
        case let .accept(_, _, id): state.modelID = id
        }
        state.stateEstimateID = resolution.decision.stateSelection.selectedStateEstimateID
        switch resolution.decision.nextAction {
        case .pause: state.status = .paused
        case .complete: state.status = .complete
        case .planSuccessor:
          state.status = .active
          state.pendingSuccessorBasis = resolution.nextPlanningBasis
        case .reacquire: state.status = .active
        }
      case let .successorPlanActivated(activation):
        guard let pendingBasis = state.pendingSuccessorBasis else {
          throw RecordedReplayError.unexpectedSuccessorActivation
        }
        guard activation.planID != pendingBasis.currentPlanID,
          activation.planID != state.planID
        else { throw RecordedReplayError.successorPlanDidNotAdvance }
        guard activation.programID == pendingBasis.programID,
          activation.programID == state.programID
        else { throw RecordedReplayError.successorProgramMismatch }
        guard activation.safetyPolicyID == pendingBasis.safetyPolicyID,
          activation.authority.fixedSafetyPolicyID == pendingBasis.safetyPolicyID,
          pendingBasis.safetyPolicyID == state.authority.fixedSafetyPolicyID
        else { throw RecordedReplayError.successorSafetyPolicyMismatch }
        guard activation.modelID == pendingBasis.modelID,
          activation.modelID == state.modelID,
          activation.stateEstimateID == pendingBasis.stateEstimateID,
          activation.stateEstimateID == state.stateEstimateID
        else { throw RecordedReplayError.successorPlanningBasisMismatch }
        guard activation.frontiers.planID == activation.planID,
          activation.authority.planID == activation.planID,
          activation.authority.modelID == activation.modelID,
          activation.authority.stateEstimateID == activation.stateEstimateID
        else { throw RecordedReplayError.successorAuthorityMismatch }
        state.planID = activation.planID
        state.modelID = activation.modelID
        state.stateEstimateID = activation.stateEstimateID
        state.frontiers = activation.frontiers
        state.authority = activation.authority
        state.blockers = activation.authority.blockers
        state.instructionCursor = nil
        state.status = activation.authority.allowed ? .active : .paused
        state.pendingSuccessorBasis = nil
      case let .paused(blockers):
        state.blockers = blockers.sorted { $0.code < $1.code }
        state.status = .paused
      case .completed:
        state.status = .complete
      case .aborted:
        state.status = .aborted
      }
      state.lastSequence = recorded.sequence
    }
    guard state.pendingSuccessorBasis == nil else {
      throw RecordedReplayError.incompleteSuccessorActivation
    }
    return state
  }
}
