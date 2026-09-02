import Foundation

public struct PlotterPenInteractionRevision:
  RawRepresentable, Codable, Hashable, Comparable, Sendable
{
  public let rawValue: UInt64

  public init(rawValue: UInt64) { self.rawValue = rawValue }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct PlotterPenInteractionRequestID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct PlotterPenInteractionOperationID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public struct PlotterPenInteractionCancellationCapabilityID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

public enum PlotterPenInteractionCommand: String, Codable, Hashable, Sendable {
  case raise
  case lower
}

public enum PlotterPenInteractionAttemptMode: String, Codable, Hashable, Sendable {
  case normal
  case replacement
  case additional
}

public enum PlotterPenInteractionTerminalDisposition: Hashable, Sendable {
  case refused(String)
  case unclear(String)
  case cancelled
  case ambiguous(String)
  case failed(String)
}

public struct PlotterPenInteractionProfile: Codable, Hashable, Sendable {
  public let raisedSpindleValue: Int
  public let loweredSpindleValue: Int
  public let settleSeconds: Double

  public init(
    raisedSpindleValue: Int,
    loweredSpindleValue: Int,
    settleSeconds: Double
  ) {
    precondition((0...1000).contains(raisedSpindleValue))
    precondition((0...1000).contains(loweredSpindleValue))
    precondition(settleSeconds.isFinite && settleSeconds >= 0)
    self.raisedSpindleValue = raisedSpindleValue
    self.loweredSpindleValue = loweredSpindleValue
    self.settleSeconds = settleSeconds
  }

  public func value(for command: PlotterPenInteractionCommand) -> Int {
    command == .raise ? raisedSpindleValue : loweredSpindleValue
  }
}

public struct PlotterPenInteractionAdmissionFacts: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let learningEnabled: Bool
  public let controllerSessionEstablished: Bool
  public let motionAuthorized: Bool
  public let lowerOperationInFlight: Bool
  public let stickyAmbiguity: String?
  public let capSelectionAvailable: Bool

  public init(
    environment: PlotterEnvironment,
    learningEnabled: Bool,
    controllerSessionEstablished: Bool,
    motionAuthorized: Bool,
    lowerOperationInFlight: Bool,
    stickyAmbiguity: String?,
    capSelectionAvailable: Bool
  ) {
    self.environment = environment
    self.learningEnabled = learningEnabled
    self.controllerSessionEstablished = controllerSessionEstablished
    self.motionAuthorized = motionAuthorized
    self.lowerOperationInFlight = lowerOperationInFlight
    self.stickyAmbiguity = stickyAmbiguity
    self.capSelectionAvailable = capSelectionAvailable
  }
}

public struct PlotterPenInteractionProjectionReference: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let revision: PlotterPenInteractionRevision
  public let operationID: PlotterPenInteractionOperationID?

  public init(
    environment: PlotterEnvironment,
    revision: PlotterPenInteractionRevision,
    operationID: PlotterPenInteractionOperationID?
  ) {
    self.environment = environment
    self.revision = revision
    self.operationID = operationID
  }
}

public enum PlotterPenInteractionIntent: Hashable, Sendable {
  case start(mode: PlotterPenInteractionAttemptMode, attemptID: UUID)
  case capSelectionAccepted
  case setpoint(command: PlotterPenInteractionCommand, value: Int)
  case actuate(PlotterPenInteractionCommand)
  case confirm(command: PlotterPenInteractionCommand)
  case abortAndRaise(PlotterPenInteractionCancellationCapabilityID)
  case finish(PlotterPenInteractionTerminalDisposition)
  case cancel(PlotterPenInteractionCancellationCapabilityID)
  case stop(PlotterPenInteractionCancellationCapabilityID)
  case reset
}

public struct PlotterPenInteractionSubmission: Hashable, Sendable {
  public let requestID: PlotterPenInteractionRequestID
  public let projection: PlotterPenInteractionProjectionReference
  public let facts: PlotterPenInteractionAdmissionFacts
  public let intent: PlotterPenInteractionIntent

  public init(
    requestID: PlotterPenInteractionRequestID = PlotterPenInteractionRequestID(),
    projection: PlotterPenInteractionProjectionReference,
    facts: PlotterPenInteractionAdmissionFacts,
    intent: PlotterPenInteractionIntent
  ) {
    self.requestID = requestID
    self.projection = projection
    self.facts = facts
    self.intent = intent
  }
}

public enum PlotterPenInteractionRefusalReason: Hashable, Sendable {
  case staleProjection
  case environmentChanged
  case learningDisabled
  case interactionAlreadyActive
  case interactionNotActive
  case capSelectionUnavailable
  case capSelectionRequired
  case controllerUnavailable
  case motionAuthorizationRequired
  case lowerOperationInFlight
  case lowerRefused(String)
  case stickyAmbiguity(String)
  case setpointOutOfRange(Int)
  case commandNotExpected
  case cancellationCapabilityMismatch
  case admissionClosed
}

public enum PlotterPenInteractionRemedy: Hashable, Sendable {
  case useCurrentProjection
  case enableLearning
  case finishOrCancelCurrentInteraction
  case completeExactCapSelection
  case connectAndProbeController
  case authorizeMotion
  case waitForLowerSettlement
  case resolveAmbiguityWithoutAutomaticResend
  case choosePublishedSetpointRange
  case useCurrentPrompt
  case useExactCancellationCapability
  case restartApplication
}

public struct PlotterPenInteractionRefusal: Hashable, Sendable {
  public let requestID: PlotterPenInteractionRequestID
  public let reason: PlotterPenInteractionRefusalReason
  public let owner: String
  public let remedy: PlotterPenInteractionRemedy
  public let currentProjection: PlotterPenInteractionProjectionReference

  public init(
    requestID: PlotterPenInteractionRequestID,
    reason: PlotterPenInteractionRefusalReason,
    owner: String = "PlotterPenInteractionRuntime",
    remedy: PlotterPenInteractionRemedy,
    currentProjection: PlotterPenInteractionProjectionReference
  ) {
    self.requestID = requestID
    self.reason = reason
    self.owner = owner
    self.remedy = remedy
    self.currentProjection = currentProjection
  }
}

public enum PlotterPenInteractionPhase: Hashable, Sendable {
  case idle
  case awaitingCapSelection
  case awaitingControllerCommand(PlotterPenInteractionCommand)
  case awaitingConfirmation(PlotterPenInteractionCommand)
  case confirming(PlotterPenInteractionCommand)
  case drainingSetpoint(PlotterPenInteractionCommand)
  case settling(PlotterPenInteractionCommand)
  case cancelling
  case succeeded
  case refused(PlotterPenInteractionRefusalReason)
  case possiblePhysicalChange(String)
}

public struct PlotterPenInteractionProjection: Hashable, Sendable {
  public let reference: PlotterPenInteractionProjectionReference
  public let phase: PlotterPenInteractionPhase
  public let profile: PlotterPenInteractionProfile
  public let cancellationCapabilityID: PlotterPenInteractionCancellationCapabilityID?
  public let lastRefusal: PlotterPenInteractionRefusal?
  public let evidenceCount: Int
  public let physicalEvidenceClaimed: Bool

  public init(
    reference: PlotterPenInteractionProjectionReference,
    phase: PlotterPenInteractionPhase,
    profile: PlotterPenInteractionProfile,
    cancellationCapabilityID: PlotterPenInteractionCancellationCapabilityID?,
    lastRefusal: PlotterPenInteractionRefusal?,
    evidenceCount: Int,
    physicalEvidenceClaimed: Bool = false
  ) {
    self.reference = reference
    self.phase = phase
    self.profile = profile
    self.cancellationCapabilityID = cancellationCapabilityID
    self.lastRefusal = lastRefusal
    self.evidenceCount = evidenceCount
    self.physicalEvidenceClaimed = physicalEvidenceClaimed
  }
}

public enum PlotterPenInteractionDisposition: Hashable, Sendable {
  case applied(PlotterPenInteractionProjection)
  /// The request passed initial admission, but an exact Stop, reset, or
  /// shutdown owner superseded it before the requested fact could commit.
  case superseded(PlotterPenInteractionProjection)
  case refused(PlotterPenInteractionRefusal)
}
