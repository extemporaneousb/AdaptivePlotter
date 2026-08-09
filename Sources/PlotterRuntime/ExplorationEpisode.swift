import Foundation
import PlotterModel

public struct LearningEvidenceSessionID: RawRepresentable, Hashable, Sendable,
  CustomStringConvertible
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ uuid: UUID = UUID()) {
    rawValue = uuid.uuidString.lowercased()
  }

  public var description: String { rawValue }
}

public struct ExplorationEpisodeID: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(_ uuid: UUID = UUID()) {
    rawValue = uuid.uuidString.lowercased()
  }

  public var description: String { rawValue }
}

public enum ExplorationLearningRung: String, CaseIterable, Hashable, Sendable {
  case humanGuidedDiscovery
  case observedDrawingTrial
  case adaptiveDrawing
}

public enum ExplorationSource: String, Hashable, Sendable {
  case live
  case simulated
}

/// Assigned before an action. Every observation derived from one physical mark
/// retains this episode-level membership.
public enum ExplorationDataSplit: String, Hashable, Sendable {
  case training
  case reserved
}

public enum ExplorationEpisodeTermination: Hashable, Sendable {
  case completed
  case failed(String)
  case ambiguous(String)
}

public enum ExplorationActionKind: String, CaseIterable, Hashable, Sendable {
  case boundarySearch
  case relativeJog
  case penUp
  case penDown
  case armatureMove
  case acceptClearPose
  case captureTargetPoseRegistration
  case capturePreTargetClearViewBaseline
  case drawVisibilityTarget
  case captureVisibilityTargetSample
  case captureTargetAnchoredTrialBaseline
  case drawingStroke
  case returnToClearPose
  case capturePostLine
  case observeInk
}

/// An attributable description of a closed typed runtime action. It is not a
/// controller-text field and carries no execution authority.
public struct ExplorationActionSummary: Hashable, Sendable {
  public let kind: ExplorationActionKind
  public let parameters: String

  public init(kind: ExplorationActionKind, parameters: String) {
    self.kind = kind
    self.parameters = parameters
  }
}

public struct ExplorationActionCandidate: Hashable, Sendable {
  public let id: String
  public let action: ExplorationActionSummary

  public init(id: String, action: ExplorationActionSummary) {
    self.id = id
    self.action = action
  }
}

public struct ExplorationPolicySelection: Hashable, Sendable {
  public let modelVersion: String?
  public let policyVersion: String?
  public let selectedCandidateID: String?
  public let selectionPropensity: Double?
  public let snapshotSummary: String?

  public init(
    modelVersion: String? = nil,
    policyVersion: String? = nil,
    selectedCandidateID: String? = nil,
    selectionPropensity: Double? = nil,
    snapshotSummary: String? = nil
  ) {
    self.modelVersion = modelVersion
    self.policyVersion = policyVersion
    self.selectedCandidateID = selectedCandidateID
    self.selectionPropensity = selectionPropensity
    self.snapshotSummary = snapshotSummary
  }
}

public enum ExplorationControllerOutcome: String, Hashable, Sendable {
  case completed
  case cancelled
  case refused
  case failed
  case ambiguous
}

public struct ExplorationControllerEvidence: Hashable, Sendable {
  public let startPosition: MachinePosition?
  public let finalPosition: MachinePosition?
  public let startSampleNanoseconds: UInt64?
  public let settlementNanoseconds: UInt64?
  public let outcome: ExplorationControllerOutcome
  public let summary: String
  public let ambiguity: String?

  public init(
    startPosition: MachinePosition? = nil,
    finalPosition: MachinePosition? = nil,
    startSampleNanoseconds: UInt64? = nil,
    settlementNanoseconds: UInt64? = nil,
    outcome: ExplorationControllerOutcome,
    summary: String,
    ambiguity: String? = nil
  ) {
    self.startPosition = startPosition
    self.finalPosition = finalPosition
    self.startSampleNanoseconds = startSampleNanoseconds
    self.settlementNanoseconds = settlementNanoseconds
    self.outcome = outcome
    self.summary = summary
    self.ambiguity = ambiguity
  }
}

public enum ExplorationFrameRole: String, CaseIterable, Hashable, Sendable {
  case preAction
  case postAction
  case boundaryObservation
  case armatureObservation
  case targetPoseRegistration
  case preTargetClearViewBaseline
  case visibilityTargetSample
  case targetAnchoredTrialBaseline
  case postLine
}

public struct ExplorationFrameEvidence: Hashable, Sendable {
  public let role: ExplorationFrameRole
  public let frameID: FrameID
  public let contentSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let algorithmRevision: String

  public init(
    role: ExplorationFrameRole,
    frameID: FrameID,
    contentSHA256: String,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    algorithmRevision: String
  ) {
    self.role = role
    self.frameID = frameID
    self.contentSHA256 = contentSHA256
    self.captureNanoseconds = captureNanoseconds
    self.cameraConfigurationID = cameraConfigurationID
    self.algorithmRevision = algorithmRevision
  }
}

public struct ExplorationAssessment: Hashable, Sendable {
  public let summary: String
  public let provenance: String

  public init(summary: String, provenance: String) {
    self.summary = summary
    self.provenance = provenance
  }
}

public struct ExplorationResidual: Hashable, Sendable {
  public let rmsPixels: Double?
  public let maximumPixels: Double?
  public let crossTrackPixels: Double?
  public let summary: String
  public let provenance: String

  public init(
    rmsPixels: Double? = nil,
    maximumPixels: Double? = nil,
    crossTrackPixels: Double? = nil,
    summary: String,
    provenance: String
  ) {
    self.rmsPixels = rmsPixels
    self.maximumPixels = maximumPixels
    self.crossTrackPixels = crossTrackPixels
    self.summary = summary
    self.provenance = provenance
  }
}

public struct ExplorationReward: Hashable, Sendable {
  public let value: Double?
  public let summary: String
  public let provenance: String

  public init(value: Double? = nil, summary: String, provenance: String) {
    self.value = value
    self.summary = summary
    self.provenance = provenance
  }
}

/// One current-slice, in-memory learning record. It deliberately has no
/// persistence or replay behavior; camera byte export remains camera-owned.
public struct ExplorationEpisode: Hashable, Sendable {
  public let sessionID: LearningEvidenceSessionID
  public let id: ExplorationEpisodeID
  public let rung: ExplorationLearningRung
  public let source: ExplorationSource
  public let split: ExplorationDataSplit
  public let startedNanoseconds: UInt64

  public var termination: ExplorationEpisodeTermination?
  public var candidateActions: [ExplorationActionCandidate]
  public var policySelection: ExplorationPolicySelection?
  public var proposedAction: ExplorationActionSummary?
  public var executedAction: ExplorationActionSummary?
  public var controllerEvidence: ExplorationControllerEvidence?
  public var frames: [ExplorationFrameEvidence]
  public var lineStartPosition: MachinePosition?
  public var targetContactPoint: Point2<CameraPixelSpace>?
  public var visionEstimate: ExplorationAssessment?
  public var humanAssessment: ExplorationAssessment?
  public var residual: ExplorationResidual?
  public var reward: ExplorationReward?

  public init(
    sessionID: LearningEvidenceSessionID,
    id: ExplorationEpisodeID = ExplorationEpisodeID(),
    rung: ExplorationLearningRung,
    source: ExplorationSource,
    split: ExplorationDataSplit,
    startedNanoseconds: UInt64
  ) {
    self.sessionID = sessionID
    self.id = id
    self.rung = rung
    self.source = source
    self.split = split
    self.startedNanoseconds = startedNanoseconds
    termination = nil
    candidateActions = []
    policySelection = nil
    proposedAction = nil
    executedAction = nil
    controllerEvidence = nil
    frames = []
    lineStartPosition = nil
    targetContactPoint = nil
    visionEstimate = nil
    humanAssessment = nil
    residual = nil
    reward = nil
  }
}
