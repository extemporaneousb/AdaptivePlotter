import Foundation

public struct PlotterBoundaryRevision:
  RawRepresentable, Codable, Hashable, Comparable, Sendable
{
  public let rawValue: UInt64

  public init(rawValue: UInt64) { self.rawValue = rawValue }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct PlotterBoundaryRequestID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct PlotterBoundaryAttemptID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct PlotterBoundaryOperationID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct PlotterBoundaryCancellationCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct PlotterBoundaryPublicationRecoveryCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct PlotterBoundaryResetCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum PlotterBoundaryDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case negativeX
  case positiveX
  case negativeY
  case positiveY

  public var displayName: String {
    switch self {
    case .negativeX: "X−"
    case .positiveX: "X+"
    case .negativeY: "Y−"
    case .positiveY: "Y+"
    }
  }
}

public enum PlotterBoundaryAttemptMode: String, Codable, Hashable, Sendable {
  case normal
  case replacement
  case additional
}

public enum PlotterBoundaryCancellationIntent: String, Codable, Hashable, Sendable {
  case operatorStop
  case cancelAttempt
  case shutdown
}

public struct PlotterBoundaryProjectionReference: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let revision: PlotterBoundaryRevision
  public let operationID: PlotterBoundaryOperationID?

  public init(
    environment: PlotterEnvironment,
    revision: PlotterBoundaryRevision,
    operationID: PlotterBoundaryOperationID?
  ) {
    self.environment = environment
    self.revision = revision
    self.operationID = operationID
  }
}

public enum PlotterBoundaryIntent: Codable, Hashable, Sendable {
  case selectDirection(PlotterBoundaryDirection)
  case acquire(direction: PlotterBoundaryDirection, mode: PlotterBoundaryAttemptMode)
  case moveToEstimatedCenter(retry: Bool)
  case stop(PlotterBoundaryCancellationCapabilityID)
  case cancel(PlotterBoundaryCancellationCapabilityID)
  case recoverPublication(PlotterBoundaryPublicationRecoveryCapabilityID)
  case reserveReset
  case commitReset(PlotterBoundaryResetCapabilityID)
  case abortReset(PlotterBoundaryResetCapabilityID)
}

public struct PlotterBoundarySubmission: Hashable, Sendable {
  public let requestID: PlotterBoundaryRequestID
  public let projection: PlotterBoundaryProjectionReference
  public let intent: PlotterBoundaryIntent

  public init(
    requestID: PlotterBoundaryRequestID = PlotterBoundaryRequestID(),
    projection: PlotterBoundaryProjectionReference,
    intent: PlotterBoundaryIntent
  ) {
    self.requestID = requestID
    self.projection = projection
    self.intent = intent
  }
}

public enum PlotterBoundaryRefusalReason: Hashable, Sendable {
  case staleProjection
  case environmentChanged
  case admissionClosed
  case learningDisabled
  case operationInFlight
  case directionNotAllowed(PlotterBoundaryDirection)
  case acceptedDirectionRequired(PlotterBoundaryDirection)
  case retainedContextMismatch(
    expectedSessionID: UUID, expectedCoordinateRevision: UInt64,
    actualSessionID: UUID, actualCoordinateRevision: UInt64
  )
  case controllerUnavailable(String)
  case motionAuthorizationRequired
  case physicalPositionUnverified(String)
  case lowerOperationInFlight
  case stickyAmbiguity(String)
  case cancellationCapabilityMismatch
  case centerUnavailable
  case centerArrivalAlreadyAccepted
  case centerRetryMismatch(expected: Bool, submitted: Bool)
  case sourceFactsChanged
  case publicationRecoveryCapabilityMismatch
  case publicationRecoveryRequired
  case resetTransactionInFlight
  case resetNotReserved
  case resetCapabilityMismatch
  case persistenceFailed(String)
  case lowerRefused(String)
}

public enum PlotterBoundaryRemedy: Hashable, Sendable {
  case useCurrentProjection
  case enableLearning
  case waitForActiveOwner
  case choosePublishedDirection
  case recordRequiredDirection
  case connectAndProbeController
  case authorizeMotion
  case restorePhysicalPosition
  case resolveAmbiguityWithoutAutomaticResend
  case useExactCancellationCapability
  case completeAllFourSides
  case continueAfterAcceptedCenter
  case usePublishedCenterRetry
  case refreshCurrentFacts
  case retryExactPublication
  case waitForResetTransaction
  case reserveResetTransaction
  case useExactResetCapability
  case restartApplication
  case resetBoundaryForCurrentSession
}

public struct PlotterBoundaryRefusal: Hashable, Sendable {
  public let requestID: PlotterBoundaryRequestID
  public let reason: PlotterBoundaryRefusalReason
  public let owner: String
  public let remedy: PlotterBoundaryRemedy
  public let currentProjection: PlotterBoundaryProjectionReference

  /// Operator text is deliberately separate from the complete typed reason.
  /// Session identities and lower-layer details remain in diagnostic state.
  public var operatorMessage: String {
    Self.operatorMessage(reason: reason, remedy: remedy)
  }

  public static func operatorMessage(
    reason: PlotterBoundaryRefusalReason, remedy: PlotterBoundaryRemedy
  ) -> String {
    switch reason {
    case .physicalPositionUnverified(let instruction):
      // External facts provide curated recovery instructions here, including
      // the missing-map case where camera position recovery is unavailable.
      return instruction
    case .retainedContextMismatch:
      return "Saved Boundary belongs to a different controller session or coordinate frame. Reset Boundary before recording new sides."
    case .directionNotAllowed(let direction):
      return "\(direction.displayName) is not the next Boundary side. Choose an available direction."
    case .acceptedDirectionRequired(let direction):
      return "Record \(direction.displayName) before repeating or replacing it."
    case .lowerRefused:
      return "The controller refused the Boundary request. Check controller status before retrying."
    case .persistenceFailed:
      return "Boundary could not be saved. Retry Save; motion will not repeat."
    default: break
    }
    switch remedy {
    case .useCurrentProjection, .refreshCurrentFacts:
      return "Boundary state changed. Retry from the current controls."
    case .enableLearning: return "Enable Learning before recording Boundary."
    case .waitForActiveOwner: return "Wait for the current operation to finish."
    case .choosePublishedDirection: return "Choose an available Boundary direction."
    case .recordRequiredDirection: return "Record the required Boundary side first."
    case .connectAndProbeController: return "Connect the controller and refresh its position."
    case .authorizeMotion: return "Enable Motion before recording Boundary."
    case .restorePhysicalPosition: return "Re-establish Position from Camera before using saved Boundary."
    case .resolveAmbiguityWithoutAutomaticResend:
      return "Boundary motion could not be verified. Check the controller before continuing."
    case .useExactCancellationCapability:
      return "Use the current Boundary Stop control."
    case .completeAllFourSides: return "Record all four Boundary sides before moving to center."
    case .continueAfterAcceptedCenter: return "Center arrival is already accepted. Continue to the next exercise."
    case .usePublishedCenterRetry: return "Use the current Move to Center control."
    case .retryExactPublication: return "Boundary could not be saved. Retry Save; motion will not repeat."
    case .waitForResetTransaction: return "Wait for the current Boundary reset to finish."
    case .reserveResetTransaction, .useExactResetCapability:
      return "Reopen the current Learning reset confirmation."
    case .restartApplication: return "Boundary is closed. Restart the app before continuing."
    case .resetBoundaryForCurrentSession:
      return "Reset Boundary before recording sides in this controller session."
    }
  }

  public init(
    requestID: PlotterBoundaryRequestID,
    reason: PlotterBoundaryRefusalReason,
    owner: String = "PlotterBoundaryRuntime",
    remedy: PlotterBoundaryRemedy,
    currentProjection: PlotterBoundaryProjectionReference
  ) {
    self.requestID = requestID
    self.reason = reason
    self.owner = owner
    self.remedy = remedy
    self.currentProjection = currentProjection
  }
}

public enum PlotterBoundaryActivityKind: String, Codable, Hashable, Sendable {
  case sideAcquisition
  case centerArrival
}

public enum PlotterBoundaryPhase: Hashable, Sendable {
  case idle
  case reserving(
    activity: PlotterBoundaryActivityKind,
    direction: PlotterBoundaryDirection?
  )
  case admitting(direction: PlotterBoundaryDirection)
  case normalizingPenUp(direction: PlotterBoundaryDirection)
  case normalizingPenUpForCenter
  case moving(direction: PlotterBoundaryDirection)
  case centering
  case cancelling(PlotterBoundaryCancellationIntent)
  case publishing
  case publicationIncomplete(PlotterBoundaryPublicationRecoveryCapabilityID)
  case resetReserved(PlotterBoundaryResetCapabilityID)
  case refused(PlotterBoundaryRefusalReason)
  case needsAttention(String)
}

public struct PlotterBoundaryAggregateSummary: Hashable, Sendable {
  public let direction: PlotterBoundaryDirection
  public let estimateMM: Double
  public let validSampleCount: Int
  public let revisionID: UUID

  public init(
    direction: PlotterBoundaryDirection,
    estimateMM: Double,
    validSampleCount: Int,
    revisionID: UUID
  ) {
    self.direction = direction
    self.estimateMM = estimateMM
    self.validSampleCount = validSampleCount
    self.revisionID = revisionID
  }
}

public struct PlotterBoundaryPositionSummary: Hashable, Sendable {
  public let xMM: Double
  public let yMM: Double

  public init(xMM: Double, yMM: Double) {
    self.xMM = xMM
    self.yMM = yMM
  }
}

public enum PlotterBoundaryTerminalDisposition: Hashable, Sendable {
  case accepted
  case cancelled
  case shutdown
  case refused(String)
  case ambiguous(String)
  case publicationIncomplete(String)

  public var operatorMessage: String {
    switch self {
    case .accepted: "Boundary accepted."
    case .cancelled: "Boundary attempt cancelled. Accepted Boundary is unchanged."
    case .shutdown: "Boundary stopped during shutdown. Restart the app before continuing."
    case .refused: "Boundary result was not accepted. Accepted Boundary is unchanged."
    case .ambiguous: "Boundary motion could not be verified. Check the controller before continuing."
    case .publicationIncomplete: "Boundary could not be saved. Retry Save; motion will not repeat."
    }
  }
}

public struct PlotterBoundaryTerminal: Hashable, Sendable {
  public let attemptID: PlotterBoundaryAttemptID
  public let operationID: PlotterBoundaryOperationID
  public let activity: PlotterBoundaryActivityKind
  public let direction: PlotterBoundaryDirection?
  public let disposition: PlotterBoundaryTerminalDisposition
  public let finalPosition: PlotterBoundaryPositionSummary?
  public let physicalEvidenceClaimed: Bool

  public init(
    attemptID: PlotterBoundaryAttemptID,
    operationID: PlotterBoundaryOperationID,
    activity: PlotterBoundaryActivityKind,
    direction: PlotterBoundaryDirection?,
    disposition: PlotterBoundaryTerminalDisposition,
    finalPosition: PlotterBoundaryPositionSummary?,
    physicalEvidenceClaimed: Bool = false
  ) {
    self.attemptID = attemptID
    self.operationID = operationID
    self.activity = activity
    self.direction = direction
    self.disposition = disposition
    self.finalPosition = finalPosition
    self.physicalEvidenceClaimed = physicalEvidenceClaimed
  }
}

public struct PlotterBoundaryProjection: Hashable, Sendable {
  public let reference: PlotterBoundaryProjectionReference
  public let phase: PlotterBoundaryPhase
  public let selectedDirection: PlotterBoundaryDirection
  public let allowedDirections: [PlotterBoundaryDirection]
  public let acceptedAggregates: [PlotterBoundaryDirection: PlotterBoundaryAggregateSummary]
  public let estimatedCenter: PlotterBoundaryPositionSummary?
  public let centerArrival: PlotterBoundaryPositionSummary?
  public let centerArrivalRetryRequired: Bool
  public let cancellationCapabilityID: PlotterBoundaryCancellationCapabilityID?
  public let publicationRecoveryCapabilityID:
    PlotterBoundaryPublicationRecoveryCapabilityID?
  public let resetCapabilityID: PlotterBoundaryResetCapabilityID?
  public let lastRefusal: PlotterBoundaryRefusal?
  public let terminal: PlotterBoundaryTerminal?
  public let physicalEvidenceClaimed: Bool

  public init(
    reference: PlotterBoundaryProjectionReference,
    phase: PlotterBoundaryPhase,
    selectedDirection: PlotterBoundaryDirection,
    allowedDirections: [PlotterBoundaryDirection],
    acceptedAggregates: [PlotterBoundaryDirection: PlotterBoundaryAggregateSummary],
    estimatedCenter: PlotterBoundaryPositionSummary?,
    centerArrival: PlotterBoundaryPositionSummary?,
    centerArrivalRetryRequired: Bool,
    cancellationCapabilityID: PlotterBoundaryCancellationCapabilityID?,
    publicationRecoveryCapabilityID: PlotterBoundaryPublicationRecoveryCapabilityID?,
    resetCapabilityID: PlotterBoundaryResetCapabilityID? = nil,
    lastRefusal: PlotterBoundaryRefusal?,
    terminal: PlotterBoundaryTerminal?,
    physicalEvidenceClaimed: Bool = false
  ) {
    self.reference = reference
    self.phase = phase
    self.selectedDirection = selectedDirection
    self.allowedDirections = allowedDirections
    self.acceptedAggregates = acceptedAggregates
    self.estimatedCenter = estimatedCenter
    self.centerArrival = centerArrival
    self.centerArrivalRetryRequired = centerArrivalRetryRequired
    self.cancellationCapabilityID = cancellationCapabilityID
    self.publicationRecoveryCapabilityID = publicationRecoveryCapabilityID
    self.resetCapabilityID = resetCapabilityID
    self.lastRefusal = lastRefusal
    self.terminal = terminal
    self.physicalEvidenceClaimed = physicalEvidenceClaimed
  }
}

public enum PlotterBoundaryDisposition: Hashable, Sendable {
  case applied(PlotterBoundaryProjection)
  case refused(PlotterBoundaryRefusal)
}
