import Foundation

public protocol EpisodeState: Codable, Hashable, Sendable {
  var episodeID: EpisodeID { get }
  var revision: EpisodeStateRevision { get }
  var canonicalDigest: EpisodeStateDigest { get }
}

public protocol CapabilityFact: Codable, Hashable, Sendable {
  var capabilityID: EpisodeCapabilityID { get }
  var owner: EpisodeAuthorityID { get }
  var revision: CapabilityFactRevision { get }
}

public struct CapabilityFactReference: Codable, Hashable, Sendable {
  public let capabilityID: EpisodeCapabilityID
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision

  public init(
    capabilityID: EpisodeCapabilityID,
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision
  ) {
    self.capabilityID = capabilityID
    self.owner = owner
    self.revision = revision
  }

  public init<Fact>(_ fact: Fact) where Fact: CapabilityFact {
    self.init(
      capabilityID: fact.capabilityID,
      owner: fact.owner,
      revision: fact.revision
    )
  }
}

public struct IntentRequirementSatisfaction: Codable, Hashable, Sendable {
  public let requirementID: EpisodeRequirementID
  public let owner: EpisodeAuthorityID
  public let comparedCapabilityFacts: [CapabilityFactReference]

  public init(
    requirementID: EpisodeRequirementID,
    owner: EpisodeAuthorityID,
    comparedCapabilityFacts: [CapabilityFactReference]
  ) {
    self.requirementID = requirementID
    self.owner = owner
    self.comparedCapabilityFacts = comparedCapabilityFacts
  }
}

public struct IntentRequirementRefusal: Codable, Hashable, Sendable {
  public let requirementID: EpisodeRequirementID
  public let owner: EpisodeAuthorityID
  public let comparedCapabilityFacts: [CapabilityFactReference]
  public let remedy: String

  public init(
    requirementID: EpisodeRequirementID,
    owner: EpisodeAuthorityID,
    comparedCapabilityFacts: [CapabilityFactReference],
    remedy: String
  ) {
    self.requirementID = requirementID
    self.owner = owner
    self.comparedCapabilityFacts = comparedCapabilityFacts
    self.remedy = remedy
  }
}

public enum IntentRequirementResult: Codable, Hashable, Sendable {
  case satisfied(IntentRequirementSatisfaction)
  case refused(IntentRequirementRefusal)
}

public struct IntentDecisionContext: Codable, Hashable, Sendable {
  public let requestID: IntentRequestID
  public let episodeID: EpisodeID
  public let comparedStateRevision: EpisodeStateRevision
  public let comparedCapabilityFacts: [CapabilityFactReference]

  public init(
    requestID: IntentRequestID,
    episodeID: EpisodeID,
    comparedStateRevision: EpisodeStateRevision,
    comparedCapabilityFacts: [CapabilityFactReference]
  ) {
    self.requestID = requestID
    self.episodeID = episodeID
    self.comparedStateRevision = comparedStateRevision
    self.comparedCapabilityFacts = comparedCapabilityFacts
  }
}

public enum IntentDecisionDisposition: String, Codable, Hashable, Sendable {
  case admitted
  case refused
}

public enum IntentDecision: Codable, Hashable, Sendable {
  case admitted(
    context: IntentDecisionContext,
    satisfiedRequirements: [IntentRequirementSatisfaction]
  )
  case refused(
    context: IntentDecisionContext,
    failedRequirements: [IntentRequirementRefusal]
  )

  public var isAdmitted: Bool {
    if case .admitted = self {
      return true
    }
    return false
  }

  public var disposition: IntentDecisionDisposition {
    isAdmitted ? .admitted : .refused
  }

  public var context: IntentDecisionContext {
    switch self {
    case let .admitted(context, _), let .refused(context, _):
      return context
    }
  }

  public var requirementResults: [IntentRequirementResult] {
    switch self {
    case let .admitted(_, requirements):
      return requirements.map(IntentRequirementResult.satisfied)
    case let .refused(_, requirements):
      return requirements.map(IntentRequirementResult.refused)
    }
  }
}

public protocol EpisodeIntentEvaluating: Sendable {
  associatedtype Intent: EpisodeIntent
  associatedtype State: EpisodeState
  associatedtype Fact: CapabilityFact

  func evaluate(
    requestID: IntentRequestID,
    intent: Intent,
    state: State,
    capabilityFacts: [Fact]
  ) -> IntentDecision
}
