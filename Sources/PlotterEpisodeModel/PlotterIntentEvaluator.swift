import EpisodeCore
import Foundation
import PlotterModel

public enum PlotterIntentRequirement: String, Codable, CaseIterable, Hashable, Sendable {
  case familyPermitted
  case episodeOpen
  case sessionIdle
  case sessionReady
  case resultAwaitingEvidence
  case sourceObservationRecorded
  case controllerConnected
  case motionEnabled
  case poseSettled
  case controllerOperationInactive
  case jogRoutingCurrent
  case penActuationProfileCurrent
  case cameraAvailable
  case exactFrameAvailable
  case executionPlanCurrent
  case evidenceAvailable
  case outcomeAvailable
  case learningEnabled
  case exactSelectionRequestValid
  case exactSelectionCurrent
  case exactSelectionFrameCurrent
  case presentationTransformCurrent
  case pointWithinExactFrame
  case exactSelectionHasCapacity
  case pointSampleUsable
  case learningWorkInactive

  public var id: EpisodeRequirementID {
    EpisodeRequirementID(rawValue: "plotter.\(rawValue)")
  }
}

public struct PlotterIntentRequirementEvaluation: Codable, Hashable, Sendable {
  public let requirement: PlotterIntentRequirement
  public let owner: EpisodeAuthorityID
  public let comparedCapabilityFacts: [CapabilityFactReference]
  public let isSatisfied: Bool
  public let remedy: String

  public init(
    requirement: PlotterIntentRequirement,
    owner: EpisodeAuthorityID,
    comparedCapabilityFacts: [CapabilityFactReference],
    isSatisfied: Bool,
    remedy: String
  ) {
    self.requirement = requirement
    self.owner = owner
    self.comparedCapabilityFacts = comparedCapabilityFacts
    self.isSatisfied = isSatisfied
    self.remedy = remedy
  }

  var satisfaction: IntentRequirementSatisfaction {
    IntentRequirementSatisfaction(
      requirementID: requirement.id,
      owner: owner,
      comparedCapabilityFacts: comparedCapabilityFacts
    )
  }

  var refusal: IntentRequirementRefusal {
    IntentRequirementRefusal(
      requirementID: requirement.id,
      owner: owner,
      comparedCapabilityFacts: comparedCapabilityFacts,
      remedy: remedy
    )
  }
}

private enum PlotterRequirementOwner {
  static let model = EpisodeAuthorityID(rawValue: "PlotterEpisodeModel")
  static let controller = EpisodeAuthorityID(rawValue: "MachineController")
  static let camera = EpisodeAuthorityID(rawValue: "CameraEvidenceAuthority")
  static let plan = EpisodeAuthorityID(rawValue: "PlotterModel.ExecutionPlanRevision")
  static let evidence = EpisodeAuthorityID(rawValue: "PlotterEvidenceAuthority")
  static let outcome = EpisodeAuthorityID(rawValue: "PlotterEpisodeOutcome")
  static let pointSelection = EpisodeAuthorityID(rawValue: "PlotterPointSelectionAuthority")
  static let learning = EpisodeAuthorityID(rawValue: "PlotterLearningAuthority")
}

private func stateRequirement(
  _ requirement: PlotterIntentRequirement,
  isSatisfied: Bool,
  remedy: String
) -> PlotterIntentRequirementEvaluation {
  PlotterIntentRequirementEvaluation(
    requirement: requirement,
    owner: PlotterRequirementOwner.model,
    comparedCapabilityFacts: [],
    isSatisfied: isSatisfied,
    remedy: remedy
  )
}

private func factRequirement(
  _ requirement: PlotterIntentRequirement,
  fact: PlotterCapabilityFact?,
  expectedOwner: EpisodeAuthorityID,
  isSatisfied: Bool,
  remedy: String
) -> PlotterIntentRequirementEvaluation {
  PlotterIntentRequirementEvaluation(
    requirement: requirement,
    owner: fact?.owner ?? expectedOwner,
    comparedCapabilityFacts: fact.map { [CapabilityFactReference($0)] } ?? [],
    isSatisfied: isSatisfied,
    remedy: remedy
  )
}

private func episodeOpen(_ state: PlotterEpisodeState) -> PlotterIntentRequirementEvaluation {
  stateRequirement(
    .episodeOpen,
    isSatisfied: state.phase != .terminal,
    remedy: "Start a new episode before submitting this intent."
  )
}

private func sessionReady(_ state: PlotterEpisodeState) -> PlotterIntentRequirementEvaluation {
  stateRequirement(
    .sessionReady,
    isSatisfied: state.phase == .ready,
    remedy: "Wait for session preparation to commit a ready state."
  )
}

private func resultAwaitingEvidence(
  _ state: PlotterEpisodeState
) -> PlotterIntentRequirementEvaluation {
  stateRequirement(
    .resultAwaitingEvidence,
    isSatisfied: state.phase == .awaitingEvidence,
    remedy: "Complete the drawing effect before acquiring result evidence."
  )
}

private func controllerRequirements(
  facts: [PlotterCapabilityFact],
  environment: PlotterEnvironment?,
  motionRemedy: String = "Enable Motion before requesting movement."
) -> [PlotterIntentRequirementEvaluation] {
  let connection = facts.fact(ofKind: .connection)
  let motion = facts.fact(ofKind: .motion)
  let pose = facts.fact(ofKind: .pose)
  let isConnected: Bool
  if case let .connection(value)? = connection {
    isConnected = value.isConnected && (environment == nil || value.environment == environment)
  } else {
    isConnected = false
  }
  let isMotionEnabled: Bool
  if case let .motion(value)? = motion {
    isMotionEnabled = value.isEnabled && (environment == nil || value.environment == environment)
  } else {
    isMotionEnabled = false
  }
  let isPoseSettled: Bool
  if case let .pose(value)? = pose {
    isPoseSettled = value.isSettled && (environment == nil || value.environment == environment)
  } else {
    isPoseSettled = false
  }
  return [
    factRequirement(
      .controllerConnected,
      fact: connection,
      expectedOwner: PlotterRequirementOwner.controller,
      isSatisfied: isConnected,
      remedy: "Connect the plotter controller."
    ),
    factRequirement(
      .motionEnabled,
      fact: motion,
      expectedOwner: PlotterRequirementOwner.controller,
      isSatisfied: isMotionEnabled,
      remedy: motionRemedy
    ),
    factRequirement(
      .poseSettled,
      fact: pose,
      expectedOwner: PlotterRequirementOwner.controller,
      isSatisfied: isPoseSettled,
      remedy: "Wait for the controller pose to settle under its current policy."
    ),
  ]
}

private func manualControllerRequirements(
  intent: PlotterManualMotionIntent,
  facts: [PlotterCapabilityFact],
  environment: PlotterEnvironment?
) -> [PlotterIntentRequirementEvaluation] {
  let manualController = facts.fact(ofKind: .manualController)
  let value: PlotterManualControllerFact?
  if case let .manualController(fact)? = manualController {
    value = fact
  } else {
    value = nil
  }
  let inactive = factRequirement(
    .controllerOperationInactive,
    fact: manualController,
    expectedOwner: PlotterRequirementOwner.controller,
    isSatisfied: value?.operationIsActive != true
      && (environment == nil || value?.environment == environment),
    remedy: "Wait for the current controller operation to settle before requesting manual action."
  )
  switch intent {
  case let .jog(request):
    let shared = controllerRequirements(facts: facts, environment: environment)
    return shared + [
      inactive,
      factRequirement(
        .jogRoutingCurrent,
        fact: manualController,
        expectedOwner: PlotterRequirementOwner.controller,
        isSatisfied: (value?.penState.requiredJogRouting == request.routing
          || (value == nil && request.routing == .relativeTravel))
          && (environment == nil || value?.environment == environment),
        remedy: "Refresh controller Pen state and rebuild the manual jog request."
      ),
    ]
  case let .setPen(request):
    let shared = controllerRequirements(
      facts: facts,
      environment: environment,
      motionRemedy: "Enable Motion before actuating the pen."
    )
    return Array(shared.dropLast()) + [
      inactive,
      factRequirement(
        .penActuationProfileCurrent,
        fact: manualController,
        expectedOwner: PlotterRequirementOwner.controller,
        isSatisfied: value?.penActuationProfileRevision == request.profile.revision
          && (environment == nil || value?.environment == environment),
        remedy: "Refresh the current Pen actuation profile before requesting direct Pen motion."
      ),
    ]
  }
}

private func cameraRequirements(
  configurationID: CameraConfigurationID,
  facts: [PlotterCapabilityFact]
) -> [PlotterIntentRequirementEvaluation] {
  let camera = facts.fact(ofKind: .camera)
  let isAvailable: Bool
  let hasExactFrame: Bool
  if case let .camera(value)? = camera {
    isAvailable = value.isAvailable && value.configurationID == configurationID
    hasExactFrame = isAvailable && value.exactFrameAvailable
  } else {
    isAvailable = false
    hasExactFrame = false
  }
  return [
    factRequirement(
      .cameraAvailable,
      fact: camera,
      expectedOwner: PlotterRequirementOwner.camera,
      isSatisfied: isAvailable,
      remedy: "Select and activate the required camera configuration."
    ),
    factRequirement(
      .exactFrameAvailable,
      fact: camera,
      expectedOwner: PlotterRequirementOwner.camera,
      isSatisfied: hasExactFrame,
      remedy: "Acquire an exact frame from the active camera configuration."
    ),
  ]
}

private func evidenceRequirement(
  question: PlotterEvidenceQuestion,
  facts: [PlotterCapabilityFact]
) -> PlotterIntentRequirementEvaluation {
  let evidence = facts.fact(ofKind: .evidence)
  let isAvailable: Bool
  if case let .evidence(value)? = evidence {
    isAvailable = value.availableQuestions.contains(question)
  } else {
    isAvailable = false
  }
  return factRequirement(
    .evidenceAvailable,
    fact: evidence,
    expectedOwner: PlotterRequirementOwner.evidence,
    isSatisfied: isAvailable,
    remedy: "Acquire applicable evidence from the authoritative evidence owner."
  )
}

public enum PlotterSessionIntentRules {
  public static func requirements(
    for intent: PlotterSessionIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case .begin:
      return [
        episodeOpen(state),
        stateRequirement(
          .sessionIdle,
          isSatisfied: state.phase == .idle,
          remedy: "Finish or reset the current session before beginning another."
        ),
      ]
    case .finish:
      return [episodeOpen(state), sessionReady(state)]
    }
  }
}

public enum PlotterObservationIntentRules {
  public static func requirements(
    for intent: PlotterObservationIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case let .captureExactFrame(configurationID):
      return [episodeOpen(state), sessionReady(state)]
        + cameraRequirements(configurationID: configurationID, facts: capabilityFacts)
    }
  }
}

public enum PlotterPointSelectionIntentRules {
  public static func requirements(
    for intent: PlotterPointSelectionIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case let .stage(request):
      let frameIsValid = !request.frame.frameID.isEmpty
        && request.frame.frameSHA256.count == 64
        && request.frame.frameSHA256.allSatisfy(\.isHexDigit)
        && request.frame.width > 0
        && request.frame.height > 0
        && request.frame.rowBytes > 0
        && request.requiredPointCount > 0
      return [
        episodeOpen(state),
        stateRequirement(
          .learningEnabled,
          isSatisfied: state.learningIsEnabled,
          remedy: "Turn Learning on before starting a point-selection request."
        ),
        stateRequirement(
          .sourceObservationRecorded,
          isSatisfied: state.observationIDs.contains(request.sourceObservationID),
          remedy: "Capture and commit the exact source observation before selecting its point."
        ),
        PlotterIntentRequirementEvaluation(
          requirement: .exactSelectionRequestValid,
          owner: PlotterRequirementOwner.pointSelection,
          comparedCapabilityFacts: [],
          isSatisfied: frameIsValid,
          remedy: "Freeze a valid exact frame before starting point selection."
        ),
      ]
    case let .select(submission):
      let request = state.exactPointSelection.request
      return [
        episodeOpen(state),
        stateRequirement(
          .learningEnabled,
          isSatisfied: state.learningIsEnabled,
          remedy: "Turn Learning on before submitting a point."
        ),
        PlotterIntentRequirementEvaluation(
          requirement: .exactSelectionCurrent,
          owner: PlotterRequirementOwner.pointSelection,
          comparedCapabilityFacts: [],
          isSatisfied: request?.id == submission.selectionID,
          remedy: "Use the currently presented point-selection request."
        ),
        PlotterIntentRequirementEvaluation(
          requirement: .exactSelectionFrameCurrent,
          owner: PlotterRequirementOwner.camera,
          comparedCapabilityFacts: [],
          isSatisfied: request?.frame == submission.frame,
          remedy: "Submit the point against the exact frozen frame currently presented."
        ),
        PlotterIntentRequirementEvaluation(
          requirement: .presentationTransformCurrent,
          owner: PlotterRequirementOwner.pointSelection,
          comparedCapabilityFacts: [],
          isSatisfied: request?.presentationTransformRevision
            == submission.presentationTransformRevision,
          remedy: "Submit from the current unmodified point-selection presentation."
        ),
        PlotterIntentRequirementEvaluation(
          requirement: .pointWithinExactFrame,
          owner: PlotterRequirementOwner.pointSelection,
          comparedCapabilityFacts: [],
          isSatisfied: submission.point.x >= 0
            && submission.point.x < Double(request?.frame.width ?? 0)
            && submission.point.y >= 0
            && submission.point.y < Double(request?.frame.height ?? 0),
          remedy: "Select a point inside the exact camera frame."
        ),
        PlotterIntentRequirementEvaluation(
          requirement: .exactSelectionHasCapacity,
          owner: PlotterRequirementOwner.pointSelection,
          comparedCapabilityFacts: [],
          isSatisfied: state.exactPointSelection.phase == .collecting
            && state.exactPointSelection.selectedPoints.count
              < (request?.requiredPointCount ?? 0),
          remedy: "Finish, undo, clear, or cancel the current point-selection request."
        ),
      ]
    case let .undo(selectionID), let .clear(selectionID),
      let .cancel(selectionID), let .setContinuation(selectionID, _):
      return [
        episodeOpen(state),
        PlotterIntentRequirementEvaluation(
          requirement: .exactSelectionCurrent,
          owner: PlotterRequirementOwner.pointSelection,
          comparedCapabilityFacts: [],
          isSatisfied: state.exactPointSelection.request?.id == selectionID,
          remedy: "Use the currently presented point-selection request."
        ),
      ]
    }
  }
}

public enum PlotterManualMotionIntentRules {
  public static func requirements(
    for intent: PlotterManualMotionIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact],
    environment: PlotterEnvironment?
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case .jog, .setPen:
      return [episodeOpen(state), sessionReady(state)]
        + manualControllerRequirements(
          intent: intent,
          facts: capabilityFacts,
          environment: environment
        )
    }
  }
}

public enum PlotterDrawingIntentRules {
  public static func requirements(
    for intent: PlotterDrawingIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact],
    environment: PlotterEnvironment?
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case let .execute(planRevisionID):
      let plan = capabilityFacts.fact(ofKind: .executionPlan)
      let isCurrent: Bool
      if case let .executionPlan(value)? = plan {
        isCurrent = value.currentRevisionID == planRevisionID
          && state.currentPlanRevisionID == planRevisionID
      } else {
        isCurrent = false
      }
      return [
        episodeOpen(state),
        sessionReady(state),
        factRequirement(
          .executionPlanCurrent,
          fact: plan,
          expectedOwner: PlotterRequirementOwner.plan,
          isSatisfied: isCurrent,
          remedy: "Rebuild and select an execution plan bound to current revisions."
        ),
      ] + controllerRequirements(facts: capabilityFacts, environment: environment)
    case let .captureResult(configurationID):
      return [episodeOpen(state), resultAwaitingEvidence(state)]
        + cameraRequirements(configurationID: configurationID, facts: capabilityFacts)
    }
  }
}

public struct PlotterLearningModeAvailability: Hashable, Sendable {
  public let isAvailable: Bool
  public let refusalRequirement: PlotterIntentRequirement?
  public let refusalOwner: EpisodeAuthorityID?
  public let refusalRemedy: String?

  public init(
    isAvailable: Bool,
    refusalRequirement: PlotterIntentRequirement? = nil,
    refusalOwner: EpisodeAuthorityID? = nil,
    refusalRemedy: String? = nil
  ) {
    self.isAvailable = isAvailable
    self.refusalRequirement = refusalRequirement
    self.refusalOwner = refusalOwner
    self.refusalRemedy = refusalRemedy
  }
}

public enum PlotterLearningIntentRules {
  public static let authority = EpisodeAuthorityID(rawValue: "PlotterLearningAuthority")
  public static let learningOffRemedy =
    "Cancel or finish the active Learning attempt before turning Learning off."

  public static func modeAvailability(
    targetIsEnabled: Bool,
    exactPointSelection: PlotterExactPointSelectionState,
    activityFact: PlotterLearningActivityFact?,
    requiredPointSelectionOwner: PlotterPointSelectionActivityOwner? = nil
  ) -> PlotterLearningModeAvailability {
    guard !targetIsEnabled else {
      return PlotterLearningModeAvailability(isAvailable: true)
    }
    // EA-04 point selection, including its exact owner-bound Pen-cap
    // continuation, is cancellable by the Learning-Off intent itself. Other
    // calibration, exploration, and motion owners remain refusal authorities.
    let currentPointSelectionOwner = activityFact?.pointSelectionOwner
    let ownerMatchesRequired = requiredPointSelectionOwner.map {
      currentPointSelectionOwner == $0
    } ?? true
    let exactSelectionIsCancellable = exactPointSelection.phase == .collecting
      || (exactPointSelection.phase == .continuing
        && exactPointSelection.continuationIsActive)
    let factClaimsCurrentPointSelection = currentPointSelectionOwner != nil
      && currentPointSelectionOwner?.selectionID == exactPointSelection.request?.id
      && exactSelectionIsCancellable
      && ownerMatchesRequired
    let hasUnrelatedWork = activityFact.map {
      factClaimsCurrentPointSelection
        ? $0.hasActiveUnrelatedLearningWork
        : $0.hasActiveLearningWork
    } ?? false
    let isAvailable = !hasUnrelatedWork
    guard !isAvailable else {
      return PlotterLearningModeAvailability(isAvailable: true)
    }
    return PlotterLearningModeAvailability(
      isAvailable: false,
      refusalRequirement: .learningWorkInactive,
      refusalOwner: activityFact?.owner ?? authority,
      refusalRemedy: learningOffRemedy
    )
  }

  public static func requirements(
    for intent: PlotterLearningIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact],
    requiredPointSelectionOwner: PlotterPointSelectionActivityOwner? = nil
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case let .captureSample(configurationID):
      return [episodeOpen(state), sessionReady(state)]
        + cameraRequirements(configurationID: configurationID, facts: capabilityFacts)
    case .acceptModel:
      return [
        episodeOpen(state),
        evidenceRequirement(question: .modelFitness, facts: capabilityFacts),
      ]
    case let .setEnabled(isEnabled):
      guard !isEnabled else { return [episodeOpen(state)] }
      let activity = capabilityFacts.fact(ofKind: .learningActivity)
      let activityFact: PlotterLearningActivityFact?
      if case let .learningActivity(value)? = activity {
        activityFact = value
      } else {
        activityFact = nil
      }
      let availability = modeAvailability(
        targetIsEnabled: isEnabled,
        exactPointSelection: state.exactPointSelection,
        activityFact: activityFact,
        requiredPointSelectionOwner: requiredPointSelectionOwner
      )
      return [
        episodeOpen(state),
        factRequirement(
          .learningWorkInactive,
          fact: activity,
          expectedOwner: availability.refusalOwner ?? authority,
          isSatisfied: availability.isAvailable,
          remedy: availability.refusalRemedy ?? learningOffRemedy
        ),
      ]
    }
  }
}

public enum PlotterEvidenceIntentRules {
  public static func requirements(
    for intent: PlotterEvidenceIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case let .accept(_, question):
      return [episodeOpen(state), evidenceRequirement(question: question, facts: capabilityFacts)]
    case let .assess(outcomeID):
      let outcome = capabilityFacts.fact(ofKind: .outcome)
      let isAvailable: Bool
      if case let .outcome(value)? = outcome {
        isAvailable = value.availableOutcomeIDs.contains(outcomeID) && state.outcome?.id == outcomeID
      } else {
        isAvailable = false
      }
      return [
        factRequirement(
          .outcomeAvailable,
          fact: outcome,
          expectedOwner: PlotterRequirementOwner.outcome,
          isSatisfied: isAvailable,
          remedy: "Commit the identified episode outcome before assessing it."
        )
      ]
    }
  }
}

public struct PlotterIntentEvaluator: EpisodeIntentEvaluating {
  public init() {}

  public func evaluate(
    requestID: IntentRequestID,
    intent: PlotterIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
  ) -> IntentDecision {
    evaluate(
      requestID: requestID,
      intent: intent,
      state: state,
      capabilityFacts: capabilityFacts,
      environment: nil,
      requiredLearningPointSelectionOwner: nil
    )
  }

  public func evaluate(
    requestID: IntentRequestID,
    intent: PlotterIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact],
    environment: PlotterEnvironment? = nil,
    requiredLearningPointSelectionOwner: PlotterPointSelectionActivityOwner?
  ) -> IntentDecision {
    let orderedFacts = capabilityFacts.sorted { lhs, rhs in
      if lhs.kind.rawValue != rhs.kind.rawValue {
        return lhs.kind.rawValue < rhs.kind.rawValue
      }
      if lhs.revision != rhs.revision {
        return lhs.revision < rhs.revision
      }
      return lhs.owner.rawValue < rhs.owner.rawValue
    }
    let family = stateRequirement(
      .familyPermitted,
      isSatisfied: state.permittedIntentFamilies.contains(intent.family),
      remedy: "Use an intent family admitted by this episode definition."
    )
    let scoped: [PlotterIntentRequirementEvaluation]
    switch intent {
    case let .session(value):
      scoped = PlotterSessionIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts
      )
    case let .observation(value):
      scoped = PlotterObservationIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts
      )
    case let .pointSelection(value):
      scoped = PlotterPointSelectionIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts
      )
    case let .manualMotion(value):
      scoped = PlotterManualMotionIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts,
        environment: environment
      )
    case let .drawing(value):
      scoped = PlotterDrawingIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts,
        environment: environment
      )
    case let .learning(value):
      scoped = PlotterLearningIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts,
        requiredPointSelectionOwner: requiredLearningPointSelectionOwner
      )
    case let .evidence(value):
      scoped = PlotterEvidenceIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts
      )
    }

    let requirements = [family] + scoped
    let context = IntentDecisionContext(
      requestID: requestID,
      episodeID: state.episodeID,
      comparedStateRevision: state.revision,
      comparedCapabilityFacts: orderedFacts.sortedReferences()
    )
    let failures = requirements.filter { !$0.isSatisfied }
    if failures.isEmpty {
      return .admitted(
        context: context,
        satisfiedRequirements: requirements.map(\.satisfaction)
      )
    }
    return .refused(
      context: context,
      failedRequirements: failures.map(\.refusal)
    )
  }
}
