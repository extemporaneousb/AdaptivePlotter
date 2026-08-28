import EpisodeCore
import Foundation
import PlotterEpisodeModel

/// Stateless typed ingress. Runtime composition supplies the current state and
/// facts, then commits the returned payload before executing any effect.
public struct PlotterIntentGateway: Sendable {
  private let evaluator = PlotterIntentEvaluator()

  public init() {}

  public func evaluate(
    requestID: IntentRequestID,
    intent: PlotterIntent,
    state: PlotterEpisodeState,
    capabilityFacts: [PlotterCapabilityFact],
    environment: PlotterEnvironment,
    requiredLearningPointSelectionOwner: PlotterPointSelectionActivityOwner? = nil
  ) throws -> PlotterIntentGatewayEvaluation {
    let decision = evaluator.evaluate(
      requestID: requestID,
      intent: intent,
      state: state,
      capabilityFacts: capabilityFacts,
      requiredLearningPointSelectionOwner: requiredLearningPointSelectionOwner
    )
    let payload: PlotterEpisodeEventPayload
    switch decision {
    case let .admitted(context, satisfiedRequirements):
      let execution: PlotterAcceptedIntentExecution = intent.requiresExternalEffect
        ? .externalEffect(effectID: EpisodeEffectID(rawValue: UUID()), environment: environment)
        : .stateOnly
      payload = .intentAccepted(try PlotterAcceptedIntent(
        requestID: requestID,
        intent: intent,
        comparedStateRevision: context.comparedStateRevision,
        comparedCapabilityFacts: context.comparedCapabilityFacts,
        satisfiedRequirements: satisfiedRequirements,
        execution: execution
      ))
    case let .refused(context, failedRequirements):
      payload = .intentRefused(PlotterIntentRefusalRecord(
        requestID: requestID,
        intent: intent,
        comparedStateRevision: context.comparedStateRevision,
        comparedCapabilityFacts: context.comparedCapabilityFacts,
        failedRequirements: failedRequirements
      ))
    }
    return PlotterIntentGatewayEvaluation(decision: decision, payload: payload)
  }
}

public struct PlotterIntentGatewayEvaluation: Sendable {
  public let decision: IntentDecision
  public let payload: PlotterEpisodeEventPayload

  public init(decision: IntentDecision, payload: PlotterEpisodeEventPayload) {
    self.decision = decision
    self.payload = payload
  }
}
