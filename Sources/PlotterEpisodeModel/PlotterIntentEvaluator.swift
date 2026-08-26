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
  case cameraAvailable
  case exactFrameAvailable
  case executionPlanCurrent
  case evidenceAvailable
  case outcomeAvailable

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
  facts: [PlotterCapabilityFact]
) -> [PlotterIntentRequirementEvaluation] {
  let connection = facts.fact(ofKind: .connection)
  let motion = facts.fact(ofKind: .motion)
  let pose = facts.fact(ofKind: .pose)
  let isConnected: Bool
  if case let .connection(value)? = connection {
    isConnected = value.isConnected
  } else {
    isConnected = false
  }
  let isMotionEnabled: Bool
  if case let .motion(value)? = motion {
    isMotionEnabled = value.isEnabled
  } else {
    isMotionEnabled = false
  }
  let isPoseSettled: Bool
  if case let .pose(value)? = pose {
    isPoseSettled = value.isSettled
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
      remedy: "Enable Motion before requesting movement."
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
    case let .select(request):
      return [
        episodeOpen(state),
        stateRequirement(
          .sourceObservationRecorded,
          isSatisfied: state.observationIDs.contains(request.sourceObservationID),
          remedy: "Capture and commit the exact source observation before selecting its point."
        ),
      ]
    case .clear:
      return [episodeOpen(state)]
    }
  }
}

public enum PlotterManualMotionIntentRules {
  public static func requirements(
    for intent: PlotterManualMotionIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
  ) -> [PlotterIntentRequirementEvaluation] {
    switch intent {
    case .jog, .setPen:
      return [episodeOpen(state), sessionReady(state)]
        + controllerRequirements(facts: capabilityFacts)
    }
  }
}

public enum PlotterDrawingIntentRules {
  public static func requirements(
    for intent: PlotterDrawingIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
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
      ] + controllerRequirements(facts: capabilityFacts)
    case let .captureResult(configurationID):
      return [episodeOpen(state), resultAwaitingEvidence(state)]
        + cameraRequirements(configurationID: configurationID, facts: capabilityFacts)
    }
  }
}

public enum PlotterLearningIntentRules {
  public static func requirements(
    for intent: PlotterLearningIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact]
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
        capabilityFacts: orderedFacts
      )
    case let .drawing(value):
      scoped = PlotterDrawingIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts
      )
    case let .learning(value):
      scoped = PlotterLearningIntentRules.requirements(
        for: value,
        state: state,
        capabilityFacts: orderedFacts
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
