import Foundation

public enum EpisodeEventOrigin: String, Codable, Hashable, Sendable {
  case operatorRequest
  case policy
  case system
  case environment
  case runtime
}

public struct EpisodeEventActor: Codable, Hashable, Sendable {
  public let id: EpisodeActorID
  public let origin: EpisodeEventOrigin

  public init(id: EpisodeActorID, origin: EpisodeEventOrigin) {
    self.id = id
    self.origin = origin
  }
}

public struct EpisodeEventCausation: Codable, Hashable, Sendable {
  public let eventID: EpisodeEventID?
  public let intentRequestID: IntentRequestID?
  public let effectID: EpisodeEffectID?

  public init(
    eventID: EpisodeEventID? = nil,
    intentRequestID: IntentRequestID? = nil,
    effectID: EpisodeEffectID? = nil
  ) {
    self.eventID = eventID
    self.intentRequestID = intentRequestID
    self.effectID = effectID
  }
}

public struct EpisodeEvent<Payload>: Codable, Hashable, Sendable
where Payload: Codable & Hashable & Sendable {
  public let id: EpisodeEventID
  public let episodeID: EpisodeID
  public let sequence: EpisodeEventSequence
  public let recordedAt: Date
  public let actor: EpisodeEventActor
  public let causation: EpisodeEventCausation?
  public let correlationID: EpisodeCorrelationID
  public let preStateRevision: EpisodeStateRevision
  public let postStateRevision: EpisodeStateRevision
  public let payload: Payload
  public let artifactReferences: [EpisodeArtifactReference]
  public let postStateDigest: EpisodeStateDigest

  public init(
    id: EpisodeEventID,
    episodeID: EpisodeID,
    sequence: EpisodeEventSequence,
    recordedAt: Date,
    actor: EpisodeEventActor,
    causation: EpisodeEventCausation? = nil,
    correlationID: EpisodeCorrelationID,
    preStateRevision: EpisodeStateRevision,
    postStateRevision: EpisodeStateRevision,
    payload: Payload,
    artifactReferences: [EpisodeArtifactReference] = [],
    postStateDigest: EpisodeStateDigest
  ) {
    self.id = id
    self.episodeID = episodeID
    self.sequence = sequence
    self.recordedAt = recordedAt
    self.actor = actor
    self.causation = causation
    self.correlationID = correlationID
    self.preStateRevision = preStateRevision
    self.postStateRevision = postStateRevision
    self.payload = payload
    self.artifactReferences = artifactReferences
    self.postStateDigest = postStateDigest
  }
}

public struct EpisodeReduction<State, Effect>: Sendable
where State: EpisodeState, Effect: Codable & Hashable & Sendable {
  public let state: State
  public let effects: [Effect]

  public init(state: State, effects: [Effect] = []) {
    self.state = state
    self.effects = effects
  }
}

public protocol EpisodeReducing: Sendable {
  associatedtype State: EpisodeState
  associatedtype EventPayload: Codable & Hashable & Sendable
  associatedtype Effect: Codable & Hashable & Sendable

  func reduce(
    state: State,
    event: EpisodeEvent<EventPayload>
  ) -> EpisodeReduction<State, Effect>
}
