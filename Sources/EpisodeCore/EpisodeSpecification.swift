import Foundation

public struct EpisodeGoalConstraint: Codable, Hashable, Sendable {
  public let id: EpisodeGoalConstraintID
  public let summary: String

  public init(id: EpisodeGoalConstraintID, summary: String) {
    self.id = id
    self.summary = summary
  }
}

public struct EpisodeAssessmentCriterion: Codable, Hashable, Sendable {
  public let id: EpisodeAssessmentCriterionID
  public let summary: String

  public init(id: EpisodeAssessmentCriterionID, summary: String) {
    self.id = id
    self.summary = summary
  }
}

public struct EpisodeTerminationCondition: Codable, Hashable, Sendable {
  public let id: EpisodeTerminationConditionID
  public let summary: String

  public init(id: EpisodeTerminationConditionID, summary: String) {
    self.id = id
    self.summary = summary
  }
}

public struct EpisodeGoal: Codable, Hashable, Sendable {
  public let terminalConstraints: [EpisodeGoalConstraint]
  public let intermediateConstraints: [EpisodeGoalConstraint]
  public let assessmentCriteria: [EpisodeAssessmentCriterion]
  public let terminationConditions: [EpisodeTerminationCondition]

  public init(
    terminalConstraints: [EpisodeGoalConstraint],
    intermediateConstraints: [EpisodeGoalConstraint] = [],
    assessmentCriteria: [EpisodeAssessmentCriterion],
    terminationConditions: [EpisodeTerminationCondition]
  ) {
    self.terminalConstraints = terminalConstraints
    self.intermediateConstraints = intermediateConstraints
    self.assessmentCriteria = assessmentCriteria
    self.terminationConditions = terminationConditions
  }
}

public struct EpisodeArtifactReference: Codable, Hashable, Sendable {
  public let id: EpisodeArtifactID
  public let revision: EpisodeRevisionIdentifier
  public let digest: String?

  public init(
    id: EpisodeArtifactID,
    revision: EpisodeRevisionIdentifier,
    digest: String? = nil
  ) {
    self.id = id
    self.revision = revision
    self.digest = digest
  }
}

public struct EpisodeBudgets: Codable, Hashable, Sendable {
  public let maximumCommittedEventCount: UInt64?
  public let maximumElapsedNanoseconds: UInt64?
  public let maximumExternalEffectCount: UInt64?

  public init(
    maximumCommittedEventCount: UInt64? = nil,
    maximumElapsedNanoseconds: UInt64? = nil,
    maximumExternalEffectCount: UInt64? = nil
  ) {
    self.maximumCommittedEventCount = maximumCommittedEventCount
    self.maximumElapsedNanoseconds = maximumElapsedNanoseconds
    self.maximumExternalEffectCount = maximumExternalEffectCount
  }
}

public protocol EpisodeIntent: Codable, Hashable, Sendable {
  associatedtype InitialContext: Codable & Hashable & Sendable
  associatedtype Grammar: Codable & Hashable & Sendable
  associatedtype AssessmentRule: Codable & Hashable & Sendable
}

public struct EpisodeDefinition<Intent>: Codable, Hashable, Sendable
where Intent: EpisodeIntent {
  public let id: EpisodeDefinitionID
  public let revision: EpisodeRevisionIdentifier
  public let goal: EpisodeGoal
  public let initialContext: Intent.InitialContext
  public let permittedIntentGrammar: Intent.Grammar
  public let budgets: EpisodeBudgets
  public let assessmentRules: [Intent.AssessmentRule]

  public init(
    id: EpisodeDefinitionID,
    revision: EpisodeRevisionIdentifier,
    goal: EpisodeGoal,
    initialContext: Intent.InitialContext,
    permittedIntentGrammar: Intent.Grammar,
    budgets: EpisodeBudgets,
    assessmentRules: [Intent.AssessmentRule]
  ) {
    self.id = id
    self.revision = revision
    self.goal = goal
    self.initialContext = initialContext
    self.permittedIntentGrammar = permittedIntentGrammar
    self.budgets = budgets
    self.assessmentRules = assessmentRules
  }
}

public struct EpisodeSchemaRevisions: Codable, Hashable, Sendable {
  public let state: EpisodeRevisionIdentifier
  public let event: EpisodeRevisionIdentifier
  public let journal: EpisodeRevisionIdentifier

  public init(
    state: EpisodeRevisionIdentifier,
    event: EpisodeRevisionIdentifier,
    journal: EpisodeRevisionIdentifier
  ) {
    self.state = state
    self.event = event
    self.journal = journal
  }
}

public struct EpisodeManifest<DomainManifest>: Codable, Hashable, Sendable
where DomainManifest: Codable & Hashable & Sendable {
  public let id: EpisodeManifestID
  public let episodeID: EpisodeID
  public let definitionID: EpisodeDefinitionID
  public let definitionRevision: EpisodeRevisionIdentifier
  public let domainRevision: EpisodeRevisionIdentifier
  public let evaluatorRevision: EpisodeRevisionIdentifier
  public let reducerRevision: EpisodeRevisionIdentifier
  public let schemaRevisions: EpisodeSchemaRevisions
  public let buildRevision: EpisodeRevisionIdentifier
  public let deterministicSeed: UInt64
  public let domainManifest: DomainManifest

  public init(
    id: EpisodeManifestID,
    episodeID: EpisodeID,
    definitionID: EpisodeDefinitionID,
    definitionRevision: EpisodeRevisionIdentifier,
    domainRevision: EpisodeRevisionIdentifier,
    evaluatorRevision: EpisodeRevisionIdentifier,
    reducerRevision: EpisodeRevisionIdentifier,
    schemaRevisions: EpisodeSchemaRevisions,
    buildRevision: EpisodeRevisionIdentifier,
    deterministicSeed: UInt64,
    domainManifest: DomainManifest
  ) {
    self.id = id
    self.episodeID = episodeID
    self.definitionID = definitionID
    self.definitionRevision = definitionRevision
    self.domainRevision = domainRevision
    self.evaluatorRevision = evaluatorRevision
    self.reducerRevision = reducerRevision
    self.schemaRevisions = schemaRevisions
    self.buildRevision = buildRevision
    self.deterministicSeed = deterministicSeed
    self.domainManifest = domainManifest
  }
}
