import EpisodeCore
import Foundation
import PlotterModel

public enum PlotterSessionIntent: Codable, Hashable, Sendable {
  case begin
  case finish
}

public enum PlotterObservationIntent: Codable, Hashable, Sendable {
  case captureExactFrame(configurationID: CameraConfigurationID)
}

public enum PlotterExactFrameSource: Codable, Hashable, Sendable {
  case live(deviceID: String)
  case simulated

  public var environment: PlotterEnvironment {
    switch self {
    case .live: .live
    case .simulated: .simulated
    }
  }
}

public enum PlotterExactFramePixelFormat: String, Codable, Hashable, Sendable {
  case gray8
  case rgba8
  case bgra8
}

/// Stable model-level identity for one exact displayed frame. Frame bytes stay
/// in the runtime recording lane; the optional artifact reference is published
/// only after those bytes were durably installed and verified.
public struct PlotterExactFrameReference: Codable, Hashable, Sendable {
  public let frameID: String
  public let frameSHA256: String
  public let source: PlotterExactFrameSource
  public let cameraConfigurationID: CameraConfigurationID
  public let captureNanoseconds: UInt64
  public let sequence: UInt64
  public let width: Int
  public let height: Int
  public let rowBytes: Int
  public let pixelFormat: PlotterExactFramePixelFormat
  public let archivedBytes: EpisodeArtifactReference?
  public let archivedByteLocator: String?

  public init(
    frameID: String,
    frameSHA256: String,
    source: PlotterExactFrameSource,
    cameraConfigurationID: CameraConfigurationID,
    captureNanoseconds: UInt64,
    sequence: UInt64,
    width: Int,
    height: Int,
    rowBytes: Int,
    pixelFormat: PlotterExactFramePixelFormat,
    archivedBytes: EpisodeArtifactReference? = nil,
    archivedByteLocator: String? = nil
  ) {
    self.frameID = frameID
    self.frameSHA256 = frameSHA256.lowercased()
    self.source = source
    self.cameraConfigurationID = cameraConfigurationID
    self.captureNanoseconds = captureNanoseconds
    self.sequence = sequence
    self.width = width
    self.height = height
    self.rowBytes = rowBytes
    self.pixelFormat = pixelFormat
    self.archivedBytes = archivedBytes
    self.archivedByteLocator = archivedByteLocator
  }
}

public struct PlotterPointSelectionID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct PlotterPresentationTransformRevision:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum PlotterExactPointSelectionPurpose: String, Codable, Hashable, Sendable {
  case penCapAppearance
  case toolContact
}

public struct PlotterPointSelectionRequest: Codable, Hashable, Sendable {
  public let id: PlotterPointSelectionID
  public let frame: PlotterExactFrameReference
  public let sourceObservationID: PlotterObservationID
  public let presentationTransformRevision: PlotterPresentationTransformRevision
  public let prompt: String
  public let purpose: PlotterExactPointSelectionPurpose
  public let requiredPointCount: Int

  public init(
    id: PlotterPointSelectionID = PlotterPointSelectionID(),
    frame: PlotterExactFrameReference,
    sourceObservationID: PlotterObservationID,
    presentationTransformRevision: PlotterPresentationTransformRevision,
    prompt: String,
    purpose: PlotterExactPointSelectionPurpose,
    requiredPointCount: Int
  ) {
    self.id = id
    self.frame = frame
    self.sourceObservationID = sourceObservationID
    self.presentationTransformRevision = presentationTransformRevision
    self.prompt = prompt
    self.purpose = purpose
    self.requiredPointCount = requiredPointCount
  }
}

public struct PlotterPointSelectionSubmission: Codable, Hashable, Sendable {
  public let selectionID: PlotterPointSelectionID
  public let frame: PlotterExactFrameReference
  public let point: Point2<CameraPixelSpace>
  public let presentationTransformRevision: PlotterPresentationTransformRevision

  public init(
    selectionID: PlotterPointSelectionID,
    frame: PlotterExactFrameReference,
    point: Point2<CameraPixelSpace>,
    presentationTransformRevision: PlotterPresentationTransformRevision
  ) {
    self.selectionID = selectionID
    self.frame = frame
    self.point = point
    self.presentationTransformRevision = presentationTransformRevision
  }
}

public enum PlotterPointSelectionIntent: Codable, Hashable, Sendable {
  case stage(PlotterPointSelectionRequest)
  case select(PlotterPointSelectionSubmission)
  case undo(PlotterPointSelectionID)
  case clear(PlotterPointSelectionID)
  case cancel(PlotterPointSelectionID)
  case setContinuation(selectionID: PlotterPointSelectionID, isActive: Bool)
}

public enum PlotterJogDirection: String, Codable, CaseIterable, Hashable, Sendable {
  case positiveX
  case negativeX
  case positiveY
  case negativeY
}

public enum PlotterPenPosition: String, Codable, Hashable, Sendable {
  case raised
  case lowered
}

public enum PlotterIntentValidationError: Error, Equatable, Sendable {
  case invalidJogDistance
  case invalidJogFeed
  case invalidPenActuationProfile
}

public enum PlotterManualJogRouting: String, Codable, Hashable, Sendable {
  case relativeTravel
  case drawingStroke
  case possibleInk
}

public struct PlotterJogRequest: Codable, Hashable, Sendable {
  public let direction: PlotterJogDirection
  public let distanceMM: Double
  public let feedMMPerMinute: Double
  public let routing: PlotterManualJogRouting

  public init(
    direction: PlotterJogDirection,
    distanceMM: Double,
    feedMMPerMinute: Double = 500,
    routing: PlotterManualJogRouting = .relativeTravel
  ) throws {
    guard distanceMM.isFinite, distanceMM > 0 else {
      throw PlotterIntentValidationError.invalidJogDistance
    }
    guard feedMMPerMinute.isFinite, feedMMPerMinute > 0 else {
      throw PlotterIntentValidationError.invalidJogFeed
    }
    self.direction = direction
    self.distanceMM = distanceMM
    self.feedMMPerMinute = feedMMPerMinute
    self.routing = routing
  }

  private enum CodingKeys: String, CodingKey {
    case direction
    case distanceMM
    case feedMMPerMinute
    case routing
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      direction: container.decode(PlotterJogDirection.self, forKey: .direction),
      distanceMM: container.decode(Double.self, forKey: .distanceMM),
      feedMMPerMinute: container.decodeIfPresent(Double.self, forKey: .feedMMPerMinute) ?? 500,
      routing: container.decodeIfPresent(PlotterManualJogRouting.self, forKey: .routing)
        ?? .relativeTravel
    )
  }
}

public struct PlotterManualPenActuationProfile: Codable, Hashable, Sendable {
  public let raisedSpindleValue: Int
  public let loweredSpindleValue: Int
  public let settleSeconds: Double
  public let revision: EpisodeRevisionIdentifier

  public init(
    raisedSpindleValue: Int,
    loweredSpindleValue: Int,
    settleSeconds: Double,
    revision: EpisodeRevisionIdentifier
  ) throws {
    guard (0...1000).contains(raisedSpindleValue),
      (0...1000).contains(loweredSpindleValue),
      settleSeconds.isFinite,
      settleSeconds >= 0
    else { throw PlotterIntentValidationError.invalidPenActuationProfile }
    self.raisedSpindleValue = raisedSpindleValue
    self.loweredSpindleValue = loweredSpindleValue
    self.settleSeconds = settleSeconds
    self.revision = revision
  }

  private enum CodingKeys: String, CodingKey {
    case raisedSpindleValue
    case loweredSpindleValue
    case settleSeconds
    case revision
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      raisedSpindleValue: container.decode(Int.self, forKey: .raisedSpindleValue),
      loweredSpindleValue: container.decode(Int.self, forKey: .loweredSpindleValue),
      settleSeconds: container.decode(Double.self, forKey: .settleSeconds),
      revision: container.decode(EpisodeRevisionIdentifier.self, forKey: .revision)
    )
  }
}

public struct PlotterPenActuationRequest: Codable, Hashable, Sendable {
  public let position: PlotterPenPosition
  public let profile: PlotterManualPenActuationProfile

  public init(position: PlotterPenPosition, profile: PlotterManualPenActuationProfile) {
    self.position = position
    self.profile = profile
  }
}

public enum PlotterManualMotionIntent: Codable, Hashable, Sendable {
  case jog(PlotterJogRequest)
  case setPen(PlotterPenActuationRequest)
}

public enum PlotterDrawingIntent: Codable, Hashable, Sendable {
  case execute(planRevisionID: ExecutionPlanRevisionID)
  case captureResult(configurationID: CameraConfigurationID)
}

public enum PlotterLearningIntent: Codable, Hashable, Sendable {
  case captureSample(configurationID: CameraConfigurationID)
  case acceptModel(revisionID: DrawingModelRevisionID)
  case setEnabled(Bool)
}

public enum PlotterEvidenceQuestion: String, Codable, CaseIterable, Hashable, Sendable {
  case pointIdentity
  case motionSettlement
  case drawingOutcome
  case modelFitness
}

public enum PlotterEvidenceIntent: Codable, Hashable, Sendable {
  case accept(subject: PlotterEvidenceSubject, question: PlotterEvidenceQuestion)
  case assess(outcomeID: PlotterOutcomeID)
}

public enum PlotterIntent: EpisodeIntent {
  public typealias InitialContext = PlotterEpisodeInitialContext
  public typealias Grammar = PlotterIntentGrammar
  public typealias AssessmentRule = PlotterAssessmentRule

  case session(PlotterSessionIntent)
  case observation(PlotterObservationIntent)
  case pointSelection(PlotterPointSelectionIntent)
  case manualMotion(PlotterManualMotionIntent)
  case drawing(PlotterDrawingIntent)
  case learning(PlotterLearningIntent)
  case evidence(PlotterEvidenceIntent)

  public var family: PlotterIntentFamily {
    switch self {
    case .session:
      return .session
    case .observation:
      return .observation
    case .pointSelection:
      return .pointSelection
    case .manualMotion:
      return .manualMotion
    case .drawing:
      return .drawing
    case .learning:
      return .learning
    case .evidence:
      return .evidence
    }
  }

  public var requiresExternalEffect: Bool {
    switch self {
    case .pointSelection, .evidence, .learning(.setEnabled):
      return false
    case .session, .observation, .manualMotion, .drawing,
      .learning(.captureSample), .learning(.acceptModel):
      return true
    }
  }
}
