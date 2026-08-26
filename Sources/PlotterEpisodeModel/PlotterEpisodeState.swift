import EpisodeCore
import Foundation
import PlotterModel

public enum PlotterEpisodePhase: String, Codable, CaseIterable, Hashable, Sendable {
  case idle
  case preparing
  case ready
  case executing
  case awaitingEvidence
  case assessing
  case terminal
}

public struct PlotterIntentRefusalRecord: Codable, Hashable, Sendable {
  public let requestID: IntentRequestID
  public let intent: PlotterIntent
  public let comparedStateRevision: EpisodeStateRevision
  public let comparedCapabilityFacts: [CapabilityFactReference]
  public let failedRequirements: [IntentRequirementRefusal]

  public init(
    requestID: IntentRequestID,
    intent: PlotterIntent,
    comparedStateRevision: EpisodeStateRevision,
    comparedCapabilityFacts: [CapabilityFactReference],
    failedRequirements: [IntentRequirementRefusal]
  ) {
    self.requestID = requestID
    self.intent = intent
    self.comparedStateRevision = comparedStateRevision
    self.comparedCapabilityFacts = comparedCapabilityFacts
    self.failedRequirements = failedRequirements
  }
}

public struct PlotterEpisodeState: EpisodeState {
  public let episodeID: EpisodeID
  public let revision: EpisodeStateRevision
  public let canonicalDigest: EpisodeStateDigest
  public let phase: PlotterEpisodePhase
  public let permittedIntentFamilies: [PlotterIntentFamily]
  public let currentPlanRevisionID: ExecutionPlanRevisionID?
  public let activeDrawingModelRevisionID: DrawingModelRevisionID?
  public let selectedPoint: Point2<MachineSpace>?
  public let activeRequestID: IntentRequestID?
  public let activeIntent: PlotterIntent?
  public let pendingEffectID: EpisodeEffectID?
  public let activeEffectProgress: PlotterEffectProgress?
  public let lastTerminalEffect: PlotterEffectTerminalRecord?
  public let observationIDs: [PlotterObservationID]
  public let measurementIDs: [PlotterMeasurementID]
  public let acceptedEvidenceIDs: [PlotterEvidenceID]
  public let outcome: PlotterEpisodeOutcome?
  public let assessment: PlotterAssessment?
  public let lastRefusal: PlotterIntentRefusalRecord?
  public let lastCommittedAt: Date?

  public init(
    episodeID: EpisodeID,
    revision: EpisodeStateRevision = .initial,
    canonicalDigest: EpisodeStateDigest,
    phase: PlotterEpisodePhase = .idle,
    permittedIntentFamilies: [PlotterIntentFamily] = PlotterIntentFamily.allCases,
    currentPlanRevisionID: ExecutionPlanRevisionID? = nil,
    activeDrawingModelRevisionID: DrawingModelRevisionID? = nil,
    selectedPoint: Point2<MachineSpace>? = nil,
    activeRequestID: IntentRequestID? = nil,
    activeIntent: PlotterIntent? = nil,
    pendingEffectID: EpisodeEffectID? = nil,
    activeEffectProgress: PlotterEffectProgress? = nil,
    lastTerminalEffect: PlotterEffectTerminalRecord? = nil,
    observationIDs: [PlotterObservationID] = [],
    measurementIDs: [PlotterMeasurementID] = [],
    acceptedEvidenceIDs: [PlotterEvidenceID] = [],
    outcome: PlotterEpisodeOutcome? = nil,
    assessment: PlotterAssessment? = nil,
    lastRefusal: PlotterIntentRefusalRecord? = nil,
    lastCommittedAt: Date? = nil
  ) {
    self.episodeID = episodeID
    self.revision = revision
    self.canonicalDigest = canonicalDigest
    self.phase = phase
    self.permittedIntentFamilies = permittedIntentFamilies
    self.currentPlanRevisionID = currentPlanRevisionID
    self.activeDrawingModelRevisionID = activeDrawingModelRevisionID
    self.selectedPoint = selectedPoint
    self.activeRequestID = activeRequestID
    self.activeIntent = activeIntent
    self.pendingEffectID = pendingEffectID
    self.activeEffectProgress = activeEffectProgress
    self.lastTerminalEffect = lastTerminalEffect
    self.observationIDs = observationIDs
    self.measurementIDs = measurementIDs
    self.acceptedEvidenceIDs = acceptedEvidenceIDs
    self.outcome = outcome
    self.assessment = assessment
    self.lastRefusal = lastRefusal
    self.lastCommittedAt = lastCommittedAt
  }
}

public struct PlotterIntentAvailability: Codable, Hashable, Sendable {
  public let intent: PlotterIntent
  public let requestID: IntentRequestID
  public let disposition: IntentDecisionDisposition
  public let comparedStateRevision: EpisodeStateRevision
  public let comparedCapabilityFacts: [CapabilityFactReference]
  public let requirementResults: [IntentRequirementResult]

  public init(intent: PlotterIntent, decision: IntentDecision) {
    self.intent = intent
    requestID = decision.context.requestID
    disposition = decision.disposition
    comparedStateRevision = decision.context.comparedStateRevision
    comparedCapabilityFacts = decision.context.comparedCapabilityFacts
    requirementResults = decision.requirementResults
  }
}

public struct PlotterEpisodeProjection: Codable, Hashable, Sendable {
  public let episodeID: EpisodeID
  public let runtimeStateRevision: EpisodeStateRevision
  public let runtimeStateDigest: EpisodeStateDigest
  public let runtimeLastCommittedAt: Date?
  public let projectionRevision: PlotterProjectionRevision
  public let projectedAt: Date
  public let phase: PlotterEpisodePhase
  public let selectedPoint: Point2<MachineSpace>?
  public let activeEffectProgress: PlotterEffectProgress?
  public let lastTerminalEffect: PlotterEffectTerminalRecord?
  public let currentReason: String?
  public let authoritativeOwner: EpisodeAuthorityID?
  public let remedy: String?
  public let availabilities: [PlotterIntentAvailability]

  public init(
    episodeID: EpisodeID,
    runtimeStateRevision: EpisodeStateRevision,
    runtimeStateDigest: EpisodeStateDigest,
    runtimeLastCommittedAt: Date?,
    projectionRevision: PlotterProjectionRevision,
    projectedAt: Date,
    phase: PlotterEpisodePhase,
    selectedPoint: Point2<MachineSpace>?,
    activeEffectProgress: PlotterEffectProgress?,
    lastTerminalEffect: PlotterEffectTerminalRecord?,
    currentReason: String?,
    authoritativeOwner: EpisodeAuthorityID?,
    remedy: String?,
    availabilities: [PlotterIntentAvailability]
  ) {
    self.episodeID = episodeID
    self.runtimeStateRevision = runtimeStateRevision
    self.runtimeStateDigest = runtimeStateDigest
    self.runtimeLastCommittedAt = runtimeLastCommittedAt
    self.projectionRevision = projectionRevision
    self.projectedAt = projectedAt
    self.phase = phase
    self.selectedPoint = selectedPoint
    self.activeEffectProgress = activeEffectProgress
    self.lastTerminalEffect = lastTerminalEffect
    self.currentReason = currentReason
    self.authoritativeOwner = authoritativeOwner
    self.remedy = remedy
    self.availabilities = availabilities
  }
}

public enum PlotterEpisodeProjector {
  public static func project(
    state: PlotterEpisodeState,
    availabilities: [PlotterIntentAvailability],
    revision: PlotterProjectionRevision,
    projectedAt: Date
  ) -> PlotterEpisodeProjection {
    let refusal = state.lastRefusal?.failedRequirements.first
    return PlotterEpisodeProjection(
      episodeID: state.episodeID,
      runtimeStateRevision: state.revision,
      runtimeStateDigest: state.canonicalDigest,
      runtimeLastCommittedAt: state.lastCommittedAt,
      projectionRevision: revision,
      projectedAt: projectedAt,
      phase: state.phase,
      selectedPoint: state.selectedPoint,
      activeEffectProgress: state.activeEffectProgress,
      lastTerminalEffect: state.lastTerminalEffect,
      currentReason: refusal?.requirementID.rawValue,
      authoritativeOwner: refusal?.owner,
      remedy: refusal?.remedy,
      availabilities: availabilities
    )
  }
}
