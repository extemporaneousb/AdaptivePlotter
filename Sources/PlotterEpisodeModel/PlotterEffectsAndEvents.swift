import EpisodeCore
import Foundation
import PlotterModel

public struct PlotterEffectContext: Codable, Hashable, Sendable {
  public let episodeID: EpisodeID
  public let requestID: IntentRequestID
  public let effectID: EpisodeEffectID
  public let environment: PlotterEnvironment

  public init(
    episodeID: EpisodeID,
    requestID: IntentRequestID,
    effectID: EpisodeEffectID,
    environment: PlotterEnvironment
  ) {
    self.episodeID = episodeID
    self.requestID = requestID
    self.effectID = effectID
    self.environment = environment
  }
}

public enum PlotterFramePurpose: String, Codable, Hashable, Sendable {
  case exactObservation
  case drawingResult
  case learningSample
}

public enum PlotterEffect: Codable, Hashable, Sendable {
  case prepareSession(PlotterEffectContext)
  case closeSession(PlotterEffectContext)
  case captureFrame(
    context: PlotterEffectContext,
    purpose: PlotterFramePurpose,
    configurationID: CameraConfigurationID
  )
  case performManualMotion(context: PlotterEffectContext, request: PlotterJogRequest)
  case setPen(context: PlotterEffectContext, request: PlotterPenActuationRequest)
  case executeDrawing(context: PlotterEffectContext, planRevisionID: ExecutionPlanRevisionID)
  case activateModel(context: PlotterEffectContext, revisionID: DrawingModelRevisionID)

  public var context: PlotterEffectContext {
    switch self {
    case let .prepareSession(context), let .closeSession(context):
      return context
    case let .captureFrame(context, _, _):
      return context
    case let .performManualMotion(context, _):
      return context
    case let .setPen(context, _):
      return context
    case let .executeDrawing(context, _):
      return context
    case let .activateModel(context, _):
      return context
    }
  }
}

public enum PlotterAcceptedIntentExecution: Codable, Hashable, Sendable {
  case stateOnly
  case externalEffect(effectID: EpisodeEffectID, environment: PlotterEnvironment)
}

public enum PlotterAcceptedIntentError: Error, Equatable, Sendable {
  case externalEffectRequired
  case stateOnlyRequired
}

public struct PlotterAcceptedIntent: Codable, Hashable, Sendable {
  public let requestID: IntentRequestID
  public let intent: PlotterIntent
  public let comparedStateRevision: EpisodeStateRevision
  public let comparedCapabilityFacts: [CapabilityFactReference]
  public let satisfiedRequirements: [IntentRequirementSatisfaction]
  public let execution: PlotterAcceptedIntentExecution

  public init(
    requestID: IntentRequestID,
    intent: PlotterIntent,
    comparedStateRevision: EpisodeStateRevision,
    comparedCapabilityFacts: [CapabilityFactReference],
    satisfiedRequirements: [IntentRequirementSatisfaction],
    execution: PlotterAcceptedIntentExecution
  ) throws {
    switch (intent.requiresExternalEffect, execution) {
    case (true, .stateOnly):
      throw PlotterAcceptedIntentError.externalEffectRequired
    case (false, .externalEffect):
      throw PlotterAcceptedIntentError.stateOnlyRequired
    case (true, .externalEffect), (false, .stateOnly):
      break
    }
    self.requestID = requestID
    self.intent = intent
    self.comparedStateRevision = comparedStateRevision
    self.comparedCapabilityFacts = comparedCapabilityFacts
    self.satisfiedRequirements = satisfiedRequirements
    self.execution = execution
  }

  private enum CodingKeys: String, CodingKey {
    case requestID
    case intent
    case comparedStateRevision
    case comparedCapabilityFacts
    case satisfiedRequirements
    case execution
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      requestID: container.decode(IntentRequestID.self, forKey: .requestID),
      intent: container.decode(PlotterIntent.self, forKey: .intent),
      comparedStateRevision: container.decode(
        EpisodeStateRevision.self,
        forKey: .comparedStateRevision
      ),
      comparedCapabilityFacts: container.decode(
        [CapabilityFactReference].self,
        forKey: .comparedCapabilityFacts
      ),
      satisfiedRequirements: container.decode(
        [IntentRequirementSatisfaction].self,
        forKey: .satisfiedRequirements
      ),
      execution: container.decode(PlotterAcceptedIntentExecution.self, forKey: .execution)
    )
  }

  public func effect(episodeID: EpisodeID) -> PlotterEffect? {
    guard case let .externalEffect(effectID, environment) = execution else {
      return nil
    }
    let context = PlotterEffectContext(
      episodeID: episodeID,
      requestID: requestID,
      effectID: effectID,
      environment: environment
    )
    switch intent {
    case .session(.begin):
      return .prepareSession(context)
    case .session(.finish):
      return .closeSession(context)
    case let .observation(.captureExactFrame(configurationID)):
      return .captureFrame(
        context: context,
        purpose: .exactObservation,
        configurationID: configurationID
      )
    case .pointSelection:
      return nil
    case let .manualMotion(.jog(request)):
      return .performManualMotion(context: context, request: request)
    case let .manualMotion(.setPen(request)):
      return .setPen(context: context, request: request)
    case let .drawing(.execute(planRevisionID)):
      return .executeDrawing(context: context, planRevisionID: planRevisionID)
    case let .drawing(.captureResult(configurationID)):
      return .captureFrame(
        context: context,
        purpose: .drawingResult,
        configurationID: configurationID
      )
    case let .learning(.captureSample(configurationID)):
      return .captureFrame(
        context: context,
        purpose: .learningSample,
        configurationID: configurationID
      )
    case let .learning(.acceptModel(revisionID)):
      return .activateModel(context: context, revisionID: revisionID)
    case .learning(.setEnabled):
      return nil
    case .evidence:
      return nil
    }
  }
}

public struct PlotterEffectResultContext: Codable, Hashable, Sendable {
  public let episodeID: EpisodeID
  public let requestID: IntentRequestID
  public let intent: PlotterIntent
  public let effectID: EpisodeEffectID
  public let environment: PlotterEnvironment
  public let effectRevision: EpisodeRevisionIdentifier

  public init(
    episodeID: EpisodeID,
    requestID: IntentRequestID,
    intent: PlotterIntent,
    effectID: EpisodeEffectID,
    environment: PlotterEnvironment,
    effectRevision: EpisodeRevisionIdentifier
  ) {
    self.episodeID = episodeID
    self.requestID = requestID
    self.intent = intent
    self.effectID = effectID
    self.environment = environment
    self.effectRevision = effectRevision
  }
}

public enum PlotterEffectLane: String, Codable, CaseIterable, Hashable, Sendable {
  case machine
  case exactWorkflowCapture
  case backgroundAnalysis
  case durableAppend
}

public enum PlotterEffectOwningSubsystem: String, Codable, CaseIterable, Hashable, Sendable {
  case session
  case machineController
  case cameraCapture
  case visionWorker
  case drawingModel
  case evidenceAuthority
}

public enum PlotterEffectProgressPhase: String, Codable, CaseIterable, Hashable, Sendable {
  case waiting
  case progressing
  case cancelling
  case settling
  case suspectedStall
}

public enum PlotterAwaitedEffectResult: String, Codable, CaseIterable, Hashable, Sendable {
  case sessionReadiness
  case sessionClosure
  case exactFrame
  case controllerSettlement
  case penSettlement
  case drawingCompletion
  case modelActivation
}

public enum PlotterEffectCancellationAvailability:
  String, Codable, CaseIterable, Hashable, Sendable
{
  case unavailable
  case available
}

public enum PlotterEffectCancellationPhase:
  String, Codable, CaseIterable, Hashable, Sendable
{
  case notRequested
  case requested
  case observed
  case settling
}

public struct PlotterEffectCancellationStatus: Codable, Hashable, Sendable {
  public let availability: PlotterEffectCancellationAvailability
  public let phase: PlotterEffectCancellationPhase

  public init(
    availability: PlotterEffectCancellationAvailability,
    phase: PlotterEffectCancellationPhase
  ) {
    self.availability = availability
    self.phase = phase
  }
}

public enum PlotterEffectProgressValidationError: Error, Equatable, Sendable {
  case progressPrecedesStart
  case deadlinePrecedesStart
}

public struct PlotterEffectProgress: Codable, Hashable, Sendable {
  public let episodeID: EpisodeID
  public let requestID: IntentRequestID
  public let intent: PlotterIntent
  public let effectID: EpisodeEffectID
  public let effectRevision: EpisodeRevisionIdentifier
  public let environment: PlotterEnvironment
  public let lane: PlotterEffectLane
  public let owningSubsystem: PlotterEffectOwningSubsystem
  public let phase: PlotterEffectProgressPhase
  public let startedAt: Date
  public let lastAttributableProgressAt: Date
  public let resultCurrentlyAwaited: PlotterAwaitedEffectResult
  public let deadline: Date?
  public let cancellation: PlotterEffectCancellationStatus

  public init(
    episodeID: EpisodeID,
    requestID: IntentRequestID,
    intent: PlotterIntent,
    effectID: EpisodeEffectID,
    effectRevision: EpisodeRevisionIdentifier,
    environment: PlotterEnvironment,
    lane: PlotterEffectLane,
    owningSubsystem: PlotterEffectOwningSubsystem,
    phase: PlotterEffectProgressPhase,
    startedAt: Date,
    lastAttributableProgressAt: Date,
    resultCurrentlyAwaited: PlotterAwaitedEffectResult,
    deadline: Date? = nil,
    cancellation: PlotterEffectCancellationStatus
  ) throws {
    guard lastAttributableProgressAt >= startedAt else {
      throw PlotterEffectProgressValidationError.progressPrecedesStart
    }
    if let deadline, deadline < startedAt {
      throw PlotterEffectProgressValidationError.deadlinePrecedesStart
    }
    self.episodeID = episodeID
    self.requestID = requestID
    self.intent = intent
    self.effectID = effectID
    self.effectRevision = effectRevision
    self.environment = environment
    self.lane = lane
    self.owningSubsystem = owningSubsystem
    self.phase = phase
    self.startedAt = startedAt
    self.lastAttributableProgressAt = lastAttributableProgressAt
    self.resultCurrentlyAwaited = resultCurrentlyAwaited
    self.deadline = deadline
    self.cancellation = cancellation
  }

  private enum CodingKeys: String, CodingKey {
    case episodeID
    case requestID
    case intent
    case effectID
    case effectRevision
    case environment
    case lane
    case owningSubsystem
    case phase
    case startedAt
    case lastAttributableProgressAt
    case resultCurrentlyAwaited
    case deadline
    case cancellation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      episodeID: container.decode(EpisodeID.self, forKey: .episodeID),
      requestID: container.decode(IntentRequestID.self, forKey: .requestID),
      intent: container.decode(PlotterIntent.self, forKey: .intent),
      effectID: container.decode(EpisodeEffectID.self, forKey: .effectID),
      effectRevision: container.decode(EpisodeRevisionIdentifier.self, forKey: .effectRevision),
      environment: container.decode(PlotterEnvironment.self, forKey: .environment),
      lane: container.decode(PlotterEffectLane.self, forKey: .lane),
      owningSubsystem: container.decode(
        PlotterEffectOwningSubsystem.self,
        forKey: .owningSubsystem
      ),
      phase: container.decode(PlotterEffectProgressPhase.self, forKey: .phase),
      startedAt: container.decode(Date.self, forKey: .startedAt),
      lastAttributableProgressAt: container.decode(
        Date.self,
        forKey: .lastAttributableProgressAt
      ),
      resultCurrentlyAwaited: container.decode(
        PlotterAwaitedEffectResult.self,
        forKey: .resultCurrentlyAwaited
      ),
      deadline: container.decodeIfPresent(Date.self, forKey: .deadline),
      cancellation: container.decode(
        PlotterEffectCancellationStatus.self,
        forKey: .cancellation
      )
    )
  }
}

public enum PlotterEffectOutput: Codable, Hashable, Sendable {
  case sessionPrepared
  case sessionClosed
  case frameCaptured(PlotterObservationID)
  case motionSettled(PlotterObservationID)
  case penSettled(position: PlotterPenPosition, observationID: PlotterObservationID)
  case drawingExecuted(
    planRevisionID: ExecutionPlanRevisionID,
    observationIDs: [PlotterObservationID]
  )
  case modelActivated(DrawingModelRevisionID)
}

public struct PlotterEffectRefusal: Codable, Hashable, Sendable {
  public let requirementID: EpisodeRequirementID
  public let owner: EpisodeAuthorityID
  public let comparedRevision: EpisodeRevisionIdentifier
  public let remedy: String

  public init(
    requirementID: EpisodeRequirementID,
    owner: EpisodeAuthorityID,
    comparedRevision: EpisodeRevisionIdentifier,
    remedy: String
  ) {
    self.requirementID = requirementID
    self.owner = owner
    self.comparedRevision = comparedRevision
    self.remedy = remedy
  }
}

public struct PlotterEffectAmbiguity: Codable, Hashable, Sendable {
  public let summary: String
  public let observationIDs: [PlotterObservationID]
  public let possibleInk: Bool

  public init(summary: String, observationIDs: [PlotterObservationID], possibleInk: Bool) {
    self.summary = summary
    self.observationIDs = observationIDs
    self.possibleInk = possibleInk
  }
}

public enum PlotterEffectFailureCode: String, Codable, CaseIterable, Hashable, Sendable {
  case connectionLost
  case controllerRejected
  case cameraUnavailable
  case evidenceUnavailable
  case environmentFailure
}

public struct PlotterEffectFailure: Codable, Hashable, Sendable {
  public let code: PlotterEffectFailureCode
  public let owner: EpisodeAuthorityID
  public let summary: String

  public init(code: PlotterEffectFailureCode, owner: EpisodeAuthorityID, summary: String) {
    self.code = code
    self.owner = owner
    self.summary = summary
  }
}

public enum PlotterEffectCancellationSettlement: Codable, Hashable, Sendable {
  case controllerSettled(observationID: PlotterObservationID, possibleInk: Bool)
  case drawingStoppedWithPenRaised(
    observationID: PlotterObservationID,
    possibleInk: Bool
  )

  public var observationID: PlotterObservationID {
    switch self {
    case let .controllerSettled(observationID, _),
      let .drawingStoppedWithPenRaised(observationID, _):
      observationID
    }
  }

  public var possibleInk: Bool {
    switch self {
    case let .controllerSettled(_, possibleInk),
      let .drawingStoppedWithPenRaised(_, possibleInk):
      possibleInk
    }
  }
}

public enum PlotterEffectResult: Codable, Hashable, Sendable {
  case completed(context: PlotterEffectResultContext, output: PlotterEffectOutput)
  case refused(context: PlotterEffectResultContext, refusal: PlotterEffectRefusal)
  case cancelled(context: PlotterEffectResultContext)
  case cancelledAfterSettlement(
    context: PlotterEffectResultContext,
    settlement: PlotterEffectCancellationSettlement
  )
  case ambiguous(context: PlotterEffectResultContext, ambiguity: PlotterEffectAmbiguity)
  case timedOut(context: PlotterEffectResultContext, deadline: Date)
  case evidenceUnavailable(context: PlotterEffectResultContext, reason: String)
  case failed(context: PlotterEffectResultContext, failure: PlotterEffectFailure)

  public var context: PlotterEffectResultContext {
    switch self {
    case let .completed(context, _):
      return context
    case let .refused(context, _):
      return context
    case let .cancelled(context):
      return context
    case let .cancelledAfterSettlement(context, _):
      return context
    case let .ambiguous(context, _):
      return context
    case let .timedOut(context, _):
      return context
    case let .evidenceUnavailable(context, _):
      return context
    case let .failed(context, _):
      return context
    }
  }

  public var disposition: PlotterEffectTerminalDisposition {
    switch self {
    case .completed:
      return .completed
    case .refused:
      return .refused
    case .cancelled, .cancelledAfterSettlement:
      return .cancelled
    case .ambiguous:
      return .ambiguous
    case .timedOut:
      return .timedOut
    case .evidenceUnavailable:
      return .evidenceUnavailable
    case .failed:
      return .failed
    }
  }
}

public enum PlotterEffectTerminalDisposition:
  String, Codable, CaseIterable, Hashable, Sendable
{
  case completed
  case refused
  case cancelled
  case ambiguous
  case timedOut
  case evidenceUnavailable
  case failed
}

public struct PlotterEffectTerminalRecord: Codable, Hashable, Sendable {
  public let settledAt: Date
  public let disposition: PlotterEffectTerminalDisposition
  public let result: PlotterEffectResult

  public init(settledAt: Date, result: PlotterEffectResult) {
    self.settledAt = settledAt
    disposition = result.disposition
    self.result = result
  }

  private enum CodingKeys: String, CodingKey {
    case settledAt
    case disposition
    case result
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let result = try container.decode(PlotterEffectResult.self, forKey: .result)
    let disposition = try container.decode(
      PlotterEffectTerminalDisposition.self,
      forKey: .disposition
    )
    guard disposition == result.disposition else {
      throw DecodingError.dataCorruptedError(
        forKey: .disposition,
        in: container,
        debugDescription: "terminal disposition does not match typed result"
      )
    }
    self.init(
      settledAt: try container.decode(Date.self, forKey: .settledAt),
      result: result
    )
  }
}

public enum PlotterEpisodeEventPayload: Codable, Hashable, Sendable {
  case intentAccepted(PlotterAcceptedIntent)
  case intentRefused(PlotterIntentRefusalRecord)
  case effectProgressed(PlotterEffectProgress)
  case effectResult(PlotterEffectResult)
  case observationRecorded(PlotterObservation)
  case measurementRecorded(PlotterMeasurement)
  case evidenceDecided(PlotterEvidenceDecision)
  case outcomeRecorded(PlotterEpisodeOutcome)
  case assessmentRecorded(PlotterAssessment)
}

public typealias PlotterEpisodeEvent = EpisodeEvent<PlotterEpisodeEventPayload>
