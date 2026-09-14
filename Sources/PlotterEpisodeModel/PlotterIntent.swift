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
  case replace(
    currentSelectionID: PlotterPointSelectionID,
    replacement: PlotterPointSelectionRequest
  )
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

/// Canonical values-only controller request; App reconstructs the lower link descriptor.
public struct PlotterControllerSessionReference: Hashable, Sendable {
  public let revision: UInt64; public let capabilityID: UUID
  public init(revision: UInt64, capabilityID: UUID) {
    self.revision = revision; self.capabilityID = capabilityID
  }
}
public struct PlotterControllerSerialDevice: Hashable, Sendable {
  public let identifier, displayName, transport: String; public let bsdPath: String?
  public init(identifier: String, displayName: String, bsdPath: String?, transport: String) {
    self.identifier = identifier; self.displayName = displayName
    self.bsdPath = bsdPath; self.transport = transport
  }
}
public enum PlotterControllerSessionIntent: Hashable, Sendable {
  case applyAxisCalibration(proposalID: UUID)
  case refreshSerialDevices, toggleConnection, requestPassiveProbe, clearAlarm
  case toggleMotionAuthorization
  case selectSerialDevice(PlotterControllerSerialDevice)
}
public struct PlotterControllerSessionRequest: Hashable, Sendable {
  public let reference: PlotterControllerSessionReference
  public let intent: PlotterControllerSessionIntent
  public init(reference: PlotterControllerSessionReference, intent: PlotterControllerSessionIntent) {
    self.reference = reference; self.intent = intent
  }
}

/// Canonical values-only camera/Vision request; App reconstructs lower effect inputs.
public struct PlotterObservationConfigurationReference: Hashable, Sendable {
  public let revision: UInt64; public let capabilityID: UUID
  public init(revision: UInt64, capabilityID: UUID) {
    self.revision = revision; self.capabilityID = capabilityID
  }
}
public enum PlotterObservationConfigurationSource: Hashable, Sendable { case live, simulated }
public struct PlotterObservationRegion: Hashable, Sendable {
  public let x, y, width, height: Int
  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x; self.y = y; self.width = width; self.height = height
  }
}
public struct PlotterObservationFrameIdentity: Hashable, Sendable {
  public let frameID, cameraConfigurationID: String
  public let sequence, captureNanoseconds: UInt64
  public init(frameID: String, sequence: UInt64, captureNanoseconds: UInt64, cameraConfigurationID: String) {
    self.frameID = frameID; self.sequence = sequence
    self.captureNanoseconds = captureNanoseconds; self.cameraConfigurationID = cameraConfigurationID
  }
}
public enum WorkbenchCameraRole: String, CaseIterable, Codable, Hashable, Sendable {
  case plotter, portrait
}
public enum PlotterObservationOperatorIntent: Hashable, Sendable {
  case refresh, stopLiveSource, restartLiveSource, requestDiagnostics
  case selectCameraRole(WorkbenchCameraRole)
  case selectSource(PlotterObservationConfigurationSource, cameraID: String?)
  case setCadence(framesPerSecond: Double)
  case setRegion(PlotterObservationRegion?, displayedFrame: PlotterObservationFrameIdentity)
  case setOverlay(identifier: String, enabled: Bool)
}
public struct PlotterObservationOperatorSubmission: Hashable, Sendable {
  public let reference: PlotterObservationConfigurationReference
  public let intent: PlotterObservationOperatorIntent
  public init(reference: PlotterObservationConfigurationReference, intent: PlotterObservationOperatorIntent) {
    self.reference = reference; self.intent = intent
  }
}

public struct PlotterLearningItemIdentity: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
}
public struct ContextualStopCapabilityID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: UUID
  public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
public enum PlotterLearningChoice: String, Codable, CaseIterable, Hashable, Sendable {
  case yes, no
}
public enum PlotterLearningPenCommand: String, Codable, Hashable, Sendable { case raise, lower }
public enum PlotterLearningCameraCalibrationAction: String, Codable, Hashable, Sendable {
  case buildFivePositionProposal, acceptProposal, rejectProposal
}
public enum PlotterLearningTipCalibrationAction: Codable, Hashable, Sendable {
  case beginFourMarkBatch, revalidateCheckpoint, acceptProposal, rejectProposal, retryCommit
  case captureNewClickFrame(retainedPointCount: Int)
}
public enum PlotterLearningPointSelectionCorrectionAction: String, Codable, Hashable, Sendable {
  case undoLastPoint, clearPoints
}
public enum PlotterLearningBorderValidationAction: Codable, Hashable, Sendable {
  case acceptObservedPrediction, reject(String)
}

/// Model-owned meaning carried unchanged from actionability to the feature owner.
public enum PlotterLearningAction: Codable, Hashable, Sendable {
  case applySavedLearning, startNewLearning, start, cancel, restart, redoThisStep
  case recordAnotherAttempt, paperReplaced
  case choice(PlotterLearningChoice)
  case setPenSetpoint(PlotterLearningPenCommand, Int)
  case stopPenInteraction(PlotterPenInteractionCancellationCapabilityID)
  case boundary(PlotterBoundaryIntent), stop(ContextualStopCapabilityID)
  case cameraCalibration(PlotterLearningCameraCalibrationAction)
  case tipCalibration(PlotterLearningTipCalibrationAction)
  case pointSelectionCorrection(PlotterLearningPointSelectionCorrectionAction)
  case borderValidation(PlotterLearningBorderValidationAction)
}
public struct PlotterLearningActionRequest: Codable, Hashable, Sendable {
  public let item: PlotterLearningItemIdentity; public let action: PlotterLearningAction
  public init(item: PlotterLearningItemIdentity, action: PlotterLearningAction) {
    self.item = item; self.action = action
  }
}

/// One stable Learning journal identity, minted once when its record is created.
public struct PlotterLearningEpisodeID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID; public init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}
public struct PlotterLearningTransitionID: Hashable, Sendable {
  public let episodeID: PlotterLearningEpisodeID; public let sequence: UInt64
  public init(episodeID: PlotterLearningEpisodeID, sequence: UInt64) { self.episodeID = episodeID; self.sequence = sequence }
}
public enum PlotterLearningEpisodeRefusalReason: Hashable, Sendable {
  case staleUIRevision, staleRuntimeRevision, unknownAction, mismatchedIntent
  case unavailableAction, ownerRefused
}
public enum PlotterLearningEpisodeResult: Hashable, Sendable {
  case accepted(owner: EpisodeAuthorityID)
  case refused(reason: PlotterLearningEpisodeRefusalReason, owner: EpisodeAuthorityID, remedy: String)
}
public enum PlotterLearningRecordRequest: Hashable, Sendable {
  case action(PlotterLearningActionRequest)
  case reset(PlotterLearningResetRequest)
}
public struct PlotterLearningPostTransitionProjection: Hashable, Sendable {
  public let stateRevision: PlotterProjectionRevision
  public let currentItem: PlotterLearningItemIdentity
  public let activeOwner: PlotterLearningItemIdentity?
  public let learningIsEnabled: Bool
  public init(
    stateRevision: PlotterProjectionRevision,
    currentItem: PlotterLearningItemIdentity,
    activeOwner: PlotterLearningItemIdentity?,
    learningIsEnabled: Bool
  ) {
    self.stateRevision = stateRevision; self.currentItem = currentItem
    self.activeOwner = activeOwner; self.learningIsEnabled = learningIsEnabled
  }
}
public struct PlotterLearningEpisode: Hashable, Sendable {
  public let transitionID: PlotterLearningTransitionID
  public let request: PlotterLearningRecordRequest; public let environment: PlotterEnvironment
  public let preStateRevision: PlotterProjectionRevision
  public let result: PlotterLearningEpisodeResult
  public let postTransitionProjection: PlotterLearningPostTransitionProjection
  public var postStateRevision: PlotterProjectionRevision { postTransitionProjection.stateRevision }
  public var stateChangePublished: Bool { preStateRevision != postStateRevision }
  public var sequence: UInt64 { transitionID.sequence }
}

/// One bounded ordered admission/result record; feature journals remain separate.
public struct PlotterLearningEpisodeRecord: Sendable {
  public struct Reservation: Hashable, Sendable {
    public let transitionID: PlotterLearningTransitionID
    public let request: PlotterLearningRecordRequest; public let environment: PlotterEnvironment
    public let preStateRevision: PlotterProjectionRevision
  }
  public private(set) var entries: [PlotterLearningEpisode] = []
  public let episodeID: PlotterLearningEpisodeID
  private var nextSequence: UInt64 = 1; private let maximumEntries: Int
  public init(episodeID: PlotterLearningEpisodeID = .init(), maximumEntries: Int = 128) { self.episodeID = episodeID; self.maximumEntries = max(1, maximumEntries) }

  public mutating func reserve(
    _ request: PlotterLearningRecordRequest,
    environment: PlotterEnvironment,
    preStateRevision: PlotterProjectionRevision
  ) -> Reservation {
    let sequence = nextSequence; nextSequence &+= 1
    let transitionID = PlotterLearningTransitionID(episodeID: episodeID, sequence: sequence)
    return Reservation(transitionID: transitionID, request: request,
      environment: environment, preStateRevision: preStateRevision)
  }

  public mutating func publish(
    _ reservation: Reservation,
    result: PlotterLearningEpisodeResult,
    postTransitionProjection: PlotterLearningPostTransitionProjection
  ) {
    entries.append(.init(
      transitionID: reservation.transitionID, request: reservation.request,
      environment: reservation.environment, preStateRevision: reservation.preStateRevision,
      result: result, postTransitionProjection: postTransitionProjection
    ))
    entries.sort { $0.sequence < $1.sequence }
    if entries.count > maximumEntries { entries.removeFirst(entries.count - maximumEntries) }
  }
}

public enum PlotterLearningResetSource: String, Codable, Hashable, Sendable { case live, simulated }
public enum PlotterLearningResetScope: Hashable, Sendable {
  case from(PlotterLearningItemIdentity), all
}
public struct PlotterLearningResetRequest: Hashable, Sendable {
  public let scope: PlotterLearningResetScope; public let source: PlotterLearningResetSource
  public let anchor: PlotterLearningItemIdentity; public let affectedItems: [PlotterLearningItemIdentity]
  public let expectedCurrentRevisionIDs: Set<String>; public let expectedAcceptedAttemptSequence: UInt64
  public let removesDurableMachineCheckpoint, removesDurableTipCheckpoint, physicalInkMayRemain: Bool
  public init(
    scope: PlotterLearningResetScope, source: PlotterLearningResetSource,
    anchor: PlotterLearningItemIdentity, affectedItems: [PlotterLearningItemIdentity],
    expectedCurrentRevisionIDs: Set<String>, expectedAcceptedAttemptSequence: UInt64,
    removesDurableMachineCheckpoint: Bool, removesDurableTipCheckpoint: Bool,
    physicalInkMayRemain: Bool
  ) {
    self.scope = scope; self.source = source; self.anchor = anchor
    self.affectedItems = affectedItems; self.expectedCurrentRevisionIDs = expectedCurrentRevisionIDs
    self.expectedAcceptedAttemptSequence = expectedAcceptedAttemptSequence
    self.removesDurableMachineCheckpoint = removesDurableMachineCheckpoint
    self.removesDurableTipCheckpoint = removesDurableTipCheckpoint
    self.physicalInkMayRemain = physicalInkMayRemain
  }
  public var identity: String {
    let scopeID = switch scope { case .from(let item): "from-\(item.rawValue)"; case .all: "all" }
    return "learning.reset.\(source.rawValue).\(scopeID).\(expectedAcceptedAttemptSequence).\(expectedCurrentRevisionIDs.sorted().joined(separator: ","))"
  }
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
