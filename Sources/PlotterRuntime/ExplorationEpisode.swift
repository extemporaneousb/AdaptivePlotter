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

public enum ExplorationSource: String, Hashable, Sendable {
  case live
  case simulated
}

public enum ExplorationEpisodeTermination: Hashable, Sendable {
  case completed
  case failed(String)
  case ambiguous(String)
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
  case localPreLineBaseline
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

/// One current-slice, in-memory learning record. It deliberately has no
/// persistence or replay behavior; camera byte export remains camera-owned.
public struct ExplorationEpisode: Hashable, Sendable {
  public let sessionID: LearningEvidenceSessionID
  public let id: ExplorationEpisodeID
  public let source: ExplorationSource
  public let startedNanoseconds: UInt64

  public var termination: ExplorationEpisodeTermination?
  public var controllerEvidence: ExplorationControllerEvidence?
  public var frames: [ExplorationFrameEvidence]
  public var lineStartPosition: MachinePosition?
  public var observedLineStartPoint: Point2<CameraPixelSpace>?
  public var observedLineObservation: IsolatedInkObservation?
  public var visionEstimate: ExplorationAssessment?
  public var humanAssessment: ExplorationAssessment?
  public var residual: ExplorationResidual?

  public init(
    sessionID: LearningEvidenceSessionID,
    id: ExplorationEpisodeID = ExplorationEpisodeID(),
    source: ExplorationSource,
    startedNanoseconds: UInt64
  ) {
    self.sessionID = sessionID
    self.id = id
    self.source = source
    self.startedNanoseconds = startedNanoseconds
    termination = nil
    controllerEvidence = nil
    frames = []
    lineStartPosition = nil
    observedLineStartPoint = nil
    observedLineObservation = nil
    visionEstimate = nil
    humanAssessment = nil
    residual = nil
  }
}
