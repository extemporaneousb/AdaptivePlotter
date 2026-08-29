import EpisodeCore
import Foundation
import PlotterModel

public struct PlotterDrawingRunRevision:
  RawRepresentable, Hashable, Comparable, Sendable
{
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct PlotterDrawingRunRequestID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct PlotterDrawingRunStopCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct PlotterDrawingRunPublicationRecoveryCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

/// Content and provenance identity handed off by the canonical EA-08A draft.
/// The full immutable values remain in PlotterEpisodeRuntime; this value is the
/// compact equality key used by submissions and presentation.
public struct PlotterDrawingRunPlanIdentity: Hashable, Sendable {
  public let draftRevision: PlotterDrawingDraftRevision
  public let programID: ProgramID
  public let programContentHash: Digest
  public let placementID: UUID
  public let planRevisionID: ExecutionPlanRevisionID
  public let planContentHash: Digest
  public let evidenceRole: DrawingTrialEvidenceRole
  public let paperCoverageObservationID: UUID
  public let tipRegistrationRevisionID: UUID

  public init(
    draftRevision: PlotterDrawingDraftRevision,
    programID: ProgramID,
    programContentHash: Digest,
    placementID: UUID,
    planRevisionID: ExecutionPlanRevisionID,
    planContentHash: Digest,
    evidenceRole: DrawingTrialEvidenceRole,
    paperCoverageObservationID: UUID,
    tipRegistrationRevisionID: UUID
  ) {
    self.draftRevision = draftRevision
    self.programID = programID
    self.programContentHash = programContentHash
    self.placementID = placementID
    self.planRevisionID = planRevisionID
    self.planContentHash = planContentHash
    self.evidenceRole = evidenceRole
    self.paperCoverageObservationID = paperCoverageObservationID
    self.tipRegistrationRevisionID = tipRegistrationRevisionID
  }
}

public struct PlotterDrawingRunProjectionReference: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let runRevision: PlotterDrawingRunRevision
  public let planIdentity: PlotterDrawingRunPlanIdentity?

  public init(
    environment: PlotterEnvironment,
    runRevision: PlotterDrawingRunRevision,
    planIdentity: PlotterDrawingRunPlanIdentity?
  ) {
    self.environment = environment
    self.runRevision = runRevision
    self.planIdentity = planIdentity
  }
}

public enum PlotterDrawingRunIntent: Hashable, Sendable {
  case start
  case stop(PlotterDrawingRunStopCapabilityID)
  case pinReview(RunID)
  case unpinReview(RunID)
  case beginNewRun(RunID)
  case recoverPublication(PlotterDrawingRunPublicationRecoveryCapabilityID)
}

public struct PlotterDrawingRunSubmission: Hashable, Sendable {
  public let requestID: PlotterDrawingRunRequestID
  public let projection: PlotterDrawingRunProjectionReference
  public let intent: PlotterDrawingRunIntent

  public init(
    requestID: PlotterDrawingRunRequestID = PlotterDrawingRunRequestID(),
    projection: PlotterDrawingRunProjectionReference,
    intent: PlotterDrawingRunIntent
  ) {
    self.requestID = requestID
    self.projection = projection
    self.intent = intent
  }
}

public enum PlotterDrawingRunRefusalReason: Hashable, Sendable {
  case staleProjection
  case admissionClosed
  case simulatedRunIsNonphysical
  case exactPlanUnavailable
  case exactPlanChanged
  case effectEnvironmentChanged
  case penActuationProfileChanged
  case learningIncomplete
  case paperCoverageNotCurrent
  case controllerUnavailable
  case activeRunOwnsWorkflow
  case terminalRequiresNewRunHandoff
  case planMayAlreadyContainInk
  case stopCapabilityMismatch
  case reviewUnavailable
  case runIdentityMismatch
  case publicationRecoveryMismatch
  case evidencePublicationInProgress
  case evidenceArchiveUnavailable
}

public enum PlotterDrawingRunRemedy: Hashable, Sendable {
  case useCurrentProjection
  case restartApplication
  case switchToLiveSource
  case reviewExactPlan
  case reviewPenActuationProfile
  case restoreLearningAuthority
  case assertCurrentPaperCoverage
  case restoreControllerReadiness
  case waitForActiveRun
  case beginNewPlan
  case movePlanAwayFromPossibleInk
  case useExactStopCapability
  case retainExactPostFrame
  case useExactRunIdentity
  case retryEvidencePublication
  case waitForEvidencePublication
  case restoreEvidenceArchive
}

public struct PlotterDrawingRunRefusal: Hashable, Sendable {
  public let requestID: PlotterDrawingRunRequestID
  public let projection: PlotterDrawingRunProjectionReference
  public let owner: EpisodeAuthorityID
  public let reason: PlotterDrawingRunRefusalReason
  public let remedy: PlotterDrawingRunRemedy

  public init(
    requestID: PlotterDrawingRunRequestID,
    projection: PlotterDrawingRunProjectionReference,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingRunRefusalReason,
    remedy: PlotterDrawingRunRemedy
  ) {
    self.requestID = requestID
    self.projection = projection
    self.owner = owner
    self.reason = reason
    self.remedy = remedy
  }
}
