import CryptoKit
import Foundation
import PlotterModel

public struct ToolContactObservationID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct ToolContactOperationID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct CameraCaptureSessionID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct MachineGeometryIdentity: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct MachineCoordinateFrameRevision: Codable, Hashable, Sendable {
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

public struct ToolAssemblyRevision: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct PenContactProfileRevision: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

/// Identifies one replaceable physical sheet and its sheet-specific ink state.
/// It is deliberately absent from `TipCalibrationApplicabilityContext`: a new
/// sheet does not invalidate tip calibration when the contact plane is
/// explicitly declared unchanged.
public struct PaperInstanceRevision: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public struct PaperContactPlaneRevision: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

/// Keeps replaceable sheet identity separate from the geometric/contact-plane
/// identity that participates in tip-calibration applicability.
public struct PaperRevisionContext: Codable, Hashable, Sendable {
  public let instance: PaperInstanceRevision
  public let contactPlane: PaperContactPlaneRevision

  public init(
    instance: PaperInstanceRevision,
    contactPlane: PaperContactPlaneRevision
  ) {
    self.instance = instance
    self.contactPlane = contactPlane
  }
}

public enum PaperContactPlaneReplacementDeclaration: Codable, Hashable, Sendable {
  /// The caller has established that fixture, support, stock thickness, and
  /// contact height remain represented by the same semantic plane revision.
  case explicitlyUnchanged(PaperContactPlaneRevision)
  /// One or more contact-plane semantics changed and the supplied revision is
  /// the new identity. Existing tip authority must remain quarantined.
  case changed(to: PaperContactPlaneRevision)
}

public enum PaperReplacementTransitionError: Error, Equatable, Sendable {
  case paperInstanceDidNotChange
  case unchangedDeclarationDoesNotMatchCurrentPlane
  case changedDeclarationReusesCurrentPlane
  case encodedCurrentContextMismatch
}

/// An immutable fact describing a physical sheet replacement. Retaining the
/// plane is possible only through the explicit `.explicitlyUnchanged` case;
/// there is no default that silently carries calibration authority forward.
public struct PaperReplacementTransition: Codable, Hashable, Sendable {
  public let previous: PaperRevisionContext
  public let current: PaperRevisionContext
  public let contactPlaneDeclaration: PaperContactPlaneReplacementDeclaration

  public init(
    previous: PaperRevisionContext,
    newPaperInstance: PaperInstanceRevision,
    contactPlaneDeclaration: PaperContactPlaneReplacementDeclaration
  ) throws {
    guard newPaperInstance != previous.instance else {
      throw PaperReplacementTransitionError.paperInstanceDidNotChange
    }
    let currentPlane: PaperContactPlaneRevision
    switch contactPlaneDeclaration {
    case .explicitlyUnchanged(let declaredPlane):
      guard declaredPlane == previous.contactPlane else {
        throw PaperReplacementTransitionError.unchangedDeclarationDoesNotMatchCurrentPlane
      }
      currentPlane = declaredPlane
    case .changed(let changedPlane):
      guard changedPlane != previous.contactPlane else {
        throw PaperReplacementTransitionError.changedDeclarationReusesCurrentPlane
      }
      currentPlane = changedPlane
    }
    self.previous = previous
    current = PaperRevisionContext(instance: newPaperInstance, contactPlane: currentPlane)
    self.contactPlaneDeclaration = contactPlaneDeclaration
  }

  private enum CodingKeys: String, CodingKey {
    case previous, current, contactPlaneDeclaration
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let previous = try values.decode(PaperRevisionContext.self, forKey: .previous)
    let current = try values.decode(PaperRevisionContext.self, forKey: .current)
    let declaration = try values.decode(
      PaperContactPlaneReplacementDeclaration.self,
      forKey: .contactPlaneDeclaration
    )
    let validated = try Self(
      previous: previous,
      newPaperInstance: current.instance,
      contactPlaneDeclaration: declaration
    )
    guard validated.current == current else {
      throw PaperReplacementTransitionError.encodedCurrentContextMismatch
    }
    self = validated
  }

  /// `nil` means the transition has explicitly retained the same contact
  /// plane. A non-nil value must be routed through the existing calibration
  /// applicability decision, which quarantines changed-plane authority.
  public var tipCalibrationApplicabilityChange: TipCalibrationApplicabilityChange? {
    switch contactPlaneDeclaration {
    case .explicitlyUnchanged:
      nil
    case .changed(let revision):
      .paperContactPlaneChanged(revision)
    }
  }
}

public struct PresentationTransformRevision: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum CameraImageOrientation: String, Codable, Hashable, Sendable {
  case up
  case right
  case down
  case left
}

public enum TipCalibrationAuthorityError: Error, Equatable, Sendable {
  case emptyValue(String)
  case invalidOpticalConfiguration
  case invalidFrameReference
  case frameEvidenceMismatch
  case invalidPointingUncertainty
  case clickOutsideFrame
  case invalidDisposition
  case invalidAcceptedPenEvidence
  case invalidTemporalOrder
  case invalidUncertainty
  case invalidObservationSet
  case invalidRegistrationEvidence
  case invalidApplicabilityContext
  case invalidCheckpoint
  case unsupportedCheckpointSchema(UInt16)
  case unsupportedCheckpointAlgorithm(String)
  case sourceRebaseNotPermitted
}

/// Semantic optical identity. Unlike `CameraConfigurationID`, this value does
/// not rotate merely because capture restarted.
public struct CameraOpticalConfigurationIdentity: Codable, Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let sensorFormat: String
  public let width: Int
  public let height: Int
  public let pixelFormat: FramePixelFormat
  public let orientation: CameraImageOrientation
  public let mirrored: Bool
  public let captureCrop: PixelRect?
  public let digitalZoomFactor: Double
  public let lensIdentity: String
  public let focusConfiguration: String
  public let mountRevision: UUID
  public let reframingRevision: UUID

  public init(
    source: FrameSourceIdentity,
    sensorFormat: String,
    width: Int,
    height: Int,
    pixelFormat: FramePixelFormat,
    orientation: CameraImageOrientation,
    mirrored: Bool,
    captureCrop: PixelRect? = nil,
    digitalZoomFactor: Double,
    lensIdentity: String,
    focusConfiguration: String,
    mountRevision: UUID,
    reframingRevision: UUID
  ) throws {
    guard width > 0, height > 0, digitalZoomFactor.isFinite, digitalZoomFactor >= 1,
      !sensorFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !lensIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !focusConfiguration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TipCalibrationAuthorityError.invalidOpticalConfiguration }
    if let captureCrop {
      guard captureCrop.x >= 0, captureCrop.y >= 0,
        captureCrop.x + captureCrop.width <= width,
        captureCrop.y + captureCrop.height <= height
      else { throw TipCalibrationAuthorityError.invalidOpticalConfiguration }
    }
    self.source = source
    self.sensorFormat = sensorFormat
    self.width = width
    self.height = height
    self.pixelFormat = pixelFormat
    self.orientation = orientation
    self.mirrored = mirrored
    self.captureCrop = captureCrop
    self.digitalZoomFactor = digitalZoomFactor
    self.lensIdentity = lensIdentity
    self.focusConfiguration = focusConfiguration
    self.mountRevision = mountRevision
    self.reframingRevision = reframingRevision
  }
}

public struct TipCalibrationApplicabilityContext: Codable, Hashable, Sendable {
  public let opticalConfiguration: CameraOpticalConfigurationIdentity
  public let machineGeometry: MachineGeometryIdentity
  public let machineCoordinateFrame: MachineCoordinateFrameRevision
  public let toolAssembly: ToolAssemblyRevision
  public let penContactProfile: PenContactProfileRevision
  public let paperContactPlane: PaperContactPlaneRevision

  public init(
    opticalConfiguration: CameraOpticalConfigurationIdentity,
    machineGeometry: MachineGeometryIdentity,
    machineCoordinateFrame: MachineCoordinateFrameRevision,
    toolAssembly: ToolAssemblyRevision,
    penContactProfile: PenContactProfileRevision,
    paperContactPlane: PaperContactPlaneRevision
  ) {
    self.opticalConfiguration = opticalConfiguration
    self.machineGeometry = machineGeometry
    self.machineCoordinateFrame = machineCoordinateFrame
    self.toolAssembly = toolAssembly
    self.penContactProfile = penContactProfile
    self.paperContactPlane = paperContactPlane
  }
}

/// A locator is present only when exact bytes were durably archived. A frame
/// hash without this locator remains provenance, not a reprocessing promise.
public struct ContentAddressedFrameLocator: Codable, Hashable, Sendable {
  public let locator: String
  public let contentSHA256: String

  public init(locator: String, contentSHA256: String) throws {
    guard !locator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      Self.isSHA256(contentSHA256)
    else { throw TipCalibrationAuthorityError.invalidFrameReference }
    self.locator = locator
    self.contentSHA256 = contentSHA256.lowercased()
  }

  fileprivate static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy { $0.isHexDigit }
  }
}

public struct ExactTipCalibrationFrame: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let source: FrameSourceIdentity
  public let captureSessionID: CameraCaptureSessionID
  public let opticalConfiguration: CameraOpticalConfigurationIdentity
  public let cameraConfigurationID: CameraConfigurationID
  public let captureNanoseconds: UInt64
  public let width: Int
  public let height: Int
  public let pixelFormat: FramePixelFormat
  public let archivedBytes: ContentAddressedFrameLocator?

  public init(
    frameID: FrameID,
    frameSHA256: String,
    source: FrameSourceIdentity,
    captureSessionID: CameraCaptureSessionID,
    opticalConfiguration: CameraOpticalConfigurationIdentity,
    cameraConfigurationID: CameraConfigurationID,
    captureNanoseconds: UInt64,
    width: Int,
    height: Int,
    pixelFormat: FramePixelFormat,
    archivedBytes: ContentAddressedFrameLocator? = nil
  ) throws {
    guard ContentAddressedFrameLocator.isSHA256(frameSHA256), width > 0, height > 0,
      source == opticalConfiguration.source,
      width == opticalConfiguration.width,
      height == opticalConfiguration.height,
      pixelFormat == opticalConfiguration.pixelFormat,
      archivedBytes?.contentSHA256 == nil
        || archivedBytes?.contentSHA256 == frameSHA256.lowercased()
    else { throw TipCalibrationAuthorityError.invalidFrameReference }
    self.frameID = frameID
    self.frameSHA256 = frameSHA256.lowercased()
    self.source = source
    self.captureSessionID = captureSessionID
    self.opticalConfiguration = opticalConfiguration
    self.cameraConfigurationID = cameraConfigurationID
    self.captureNanoseconds = captureNanoseconds
    self.width = width
    self.height = height
    self.pixelFormat = pixelFormat
    self.archivedBytes = archivedBytes
  }
}

public enum ToolContactCalibrationPosition: String, Codable, CaseIterable, Hashable, Sendable {
  case center
  case negativeX
  case positiveY
  case positiveX
  case negativeY
}

public enum ToolContactPointRole: String, Codable, Hashable, Sendable {
  case assertedCenter
}

public struct ToolContactClickEvidence: Codable, Hashable, Sendable {
  public let point: Point2<CameraPixelSpace>
  public let role: ToolContactPointRole
  public let pointingUncertaintyPixels: Vector2<CameraPixelSpace>
  public let timestamp: RuntimeTimestamp
  public let presentationTransformRevision: PresentationTransformRevision

  public init(
    point: Point2<CameraPixelSpace>,
    role: ToolContactPointRole = .assertedCenter,
    pointingUncertaintyPixels: Vector2<CameraPixelSpace>,
    timestamp: RuntimeTimestamp,
    presentationTransformRevision: PresentationTransformRevision
  ) throws {
    guard pointingUncertaintyPixels.dx > 0, pointingUncertaintyPixels.dy > 0 else {
      throw TipCalibrationAuthorityError.invalidPointingUncertainty
    }
    self.point = point
    self.role = role
    self.pointingUncertaintyPixels = pointingUncertaintyPixels
    self.timestamp = timestamp
    self.presentationTransformRevision = presentationTransformRevision
  }
}

public struct ControllerContextEvidenceReference: Codable, Hashable, Sendable {
  public let passiveProbeID: UUID
  public let evidenceSHA256: String
  public let algorithmRevision: String

  public init(passiveProbeID: UUID, evidenceSHA256: String, algorithmRevision: String) throws {
    guard ContentAddressedFrameLocator.isSHA256(evidenceSHA256),
      !algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TipCalibrationAuthorityError.emptyValue("controller context evidence") }
    self.passiveProbeID = passiveProbeID
    self.evidenceSHA256 = evidenceSHA256.lowercased()
    self.algorithmRevision = algorithmRevision
  }
}

public struct PenActuationEvidence: Codable, Hashable, Sendable {
  public let outcome: PenOutcome
  public let profile: PenActuationProfile
  public let timestamp: RuntimeTimestamp

  public init(
    outcome: PenOutcome,
    profile: PenActuationProfile,
    timestamp: RuntimeTimestamp
  ) {
    self.outcome = outcome
    self.profile = profile
    self.timestamp = timestamp
  }
}

public enum ToolContactMarkGeometryKind: String, Codable, Hashable, Sendable {
  case circularOutline
}

/// Commanded geometry whose selected center is associated with one calibration
/// machine position. This describes the intended finite mark; it is not a
/// claim that physical ink was observed.
public struct ToolContactMarkGeometryEvidence: Codable, Hashable, Sendable {
  public let kind: ToolContactMarkGeometryKind
  public let center: MachinePosition
  public let radiusMM: Double
  public let chordCount: Int
  public let maximumChordDeviationMM: Double
  public let maximumFeedMMPerMinute: Double

  public init(
    kind: ToolContactMarkGeometryKind = .circularOutline,
    center: MachinePosition,
    radiusMM: Double,
    chordCount: Int,
    maximumFeedMMPerMinute: Double
  ) throws {
    guard radiusMM.isFinite, radiusMM > 0, chordCount >= 8,
      maximumFeedMMPerMinute.isFinite, maximumFeedMMPerMinute > 0
    else {
      throw TipCalibrationAuthorityError.invalidObservationSet
    }
    let maximumChordDeviationMM = radiusMM * (1 - cos(.pi / Double(chordCount)))
    guard maximumChordDeviationMM.isFinite,
      maximumChordDeviationMM <= MachinePositionAcceptancePolicy.toleranceMM
    else { throw TipCalibrationAuthorityError.invalidObservationSet }
    self.kind = kind
    self.center = center
    self.radiusMM = radiusMM
    self.chordCount = chordCount
    self.maximumChordDeviationMM = maximumChordDeviationMM
    self.maximumFeedMMPerMinute = maximumFeedMMPerMinute
  }
}

/// Settled Pen-Up reveal evidence captured before the operator selects a mark.
/// It proves both controller arrival and a fresh cap-map check at the reveal pose.
public struct ToolContactRevealEvidence: Codable, Hashable, Sendable {
  public let intendedPosition: MachinePosition
  public let actualSettledPosition: MachinePosition
  public let settledAt: RuntimeTimestamp
  public let controllerContextEvidence: ControllerContextEvidenceReference
  public let frame: ExactTipCalibrationFrame
  public let capEstimate: ToolCapAnchorEstimate
  public let capMapPrediction: Point2<CameraPixelSpace>
  public let capMapResidualPixels: Double
  public let maximumCapMapResidualPixels: Double

  public init(
    intendedPosition: MachinePosition,
    actualSettledPosition: MachinePosition,
    settledAt: RuntimeTimestamp,
    controllerContextEvidence: ControllerContextEvidenceReference,
    frame: ExactTipCalibrationFrame,
    capEstimate: ToolCapAnchorEstimate,
    capMapPrediction: Point2<CameraPixelSpace>,
    maximumCapMapResidualPixels: Double
  ) throws {
    let positionResidual = MachinePositionAcceptancePolicy.residualMM(
      actualSettledPosition,
      from: intendedPosition
    )
    let capResidual = capMapPrediction.distance(to: capEstimate.point)
    guard MachinePositionAcceptancePolicy.accepts(residualMM: positionResidual),
      maximumCapMapResidualPixels.isFinite, maximumCapMapResidualPixels >= 0,
      capResidual <= maximumCapMapResidualPixels,
      settledAt.monotonicNanoseconds <= frame.captureNanoseconds,
      capEstimate.source == frame.source,
      capEstimate.frameID == frame.frameID,
      capEstimate.cameraConfigurationID == frame.cameraConfigurationID
    else { throw TipCalibrationAuthorityError.frameEvidenceMismatch }
    self.intendedPosition = intendedPosition
    self.actualSettledPosition = actualSettledPosition
    self.settledAt = settledAt
    self.controllerContextEvidence = controllerContextEvidence
    self.frame = frame
    self.capEstimate = capEstimate
    self.capMapPrediction = capMapPrediction
    capMapResidualPixels = capResidual
    self.maximumCapMapResidualPixels = maximumCapMapResidualPixels
  }
}

public enum ToolContactObservationDisposition: Codable, Hashable, Sendable {
  case accepted
  case rejected(String)
  case excluded(String)
  case ambiguous(String)

  public var blacklistsPhysicalLocation: Bool {
    if case .ambiguous = self { return true }
    return false
  }

  fileprivate var reasonIsValid: Bool {
    switch self {
    case .accepted: true
    case .rejected(let reason), .excluded(let reason), .ambiguous(let reason):
      !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
}

public struct AlgorithmRevisionEvidence: Codable, Hashable, Sendable {
  public let component: String
  public let revision: String

  public init(component: String, revision: String) throws {
    guard !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TipCalibrationAuthorityError.emptyValue("algorithm revision") }
    self.component = component
    self.revision = revision
  }
}

/// Immutable raw evidence for one operator-selected physical contact mark.
public struct ToolContactObservation: Codable, Hashable, Sendable {
  public let id: ToolContactObservationID
  public let attemptID: ExerciseAttemptID
  public let operationID: ToolContactOperationID
  public let calibrationPosition: ToolContactCalibrationPosition
  public let intendedMarkPosition: MachinePosition
  public let actualSettledPosition: MachinePosition
  public let machineGeometry: MachineGeometryIdentity
  public let controllerSessionID: UUID
  public let machineCoordinateFrame: MachineCoordinateFrameRevision
  public let controllerContextEvidence: ControllerContextEvidenceReference
  public let markGeometry: ToolContactMarkGeometryEvidence
  public let penDown: PenActuationEvidence
  public let penUp: PenActuationEvidence
  public let toolAssembly: ToolAssemblyRevision
  public let penContactProfile: PenContactProfileRevision
  public let paperContactPlane: PaperContactPlaneRevision
  public let preMarkFrame: ExactTipCalibrationFrame
  public let preMarkCapEstimate: ToolCapAnchorEstimate
  public let revealEvidence: ToolContactRevealEvidence
  public let click: ToolContactClickEvidence
  public let capMapPredictionAtMark: Point2<CameraPixelSpace>
  public let capMapResidualPixels: Double
  public let disposition: ToolContactObservationDisposition
  public let consumedLearningArtifactRevisionIDs: Set<LearningArtifactRevisionID>
  public let algorithmRevisions: Set<AlgorithmRevisionEvidence>

  public init(
    id: ToolContactObservationID = ToolContactObservationID(),
    attemptID: ExerciseAttemptID,
    operationID: ToolContactOperationID,
    calibrationPosition: ToolContactCalibrationPosition,
    intendedMarkPosition: MachinePosition,
    actualSettledPosition: MachinePosition,
    machineGeometry: MachineGeometryIdentity,
    controllerSessionID: UUID,
    machineCoordinateFrame: MachineCoordinateFrameRevision,
    controllerContextEvidence: ControllerContextEvidenceReference,
    markGeometry: ToolContactMarkGeometryEvidence,
    penDown: PenActuationEvidence,
    penUp: PenActuationEvidence,
    toolAssembly: ToolAssemblyRevision,
    penContactProfile: PenContactProfileRevision,
    paperContactPlane: PaperContactPlaneRevision,
    preMarkFrame: ExactTipCalibrationFrame,
    preMarkCapEstimate: ToolCapAnchorEstimate,
    revealEvidence: ToolContactRevealEvidence,
    click: ToolContactClickEvidence,
    capMapPredictionAtMark: Point2<CameraPixelSpace>,
    disposition: ToolContactObservationDisposition,
    consumedLearningArtifactRevisionIDs: Set<LearningArtifactRevisionID>,
    algorithmRevisions: Set<AlgorithmRevisionEvidence>
  ) throws {
    guard disposition.reasonIsValid else { throw TipCalibrationAuthorityError.invalidDisposition }
    let markPositionResidual = MachinePositionAcceptancePolicy.residualMM(
      actualSettledPosition,
      from: intendedMarkPosition
    )
    let capResidual = capMapPredictionAtMark.distance(to: preMarkCapEstimate.point)
    guard MachinePositionAcceptancePolicy.accepts(residualMM: markPositionResidual),
      MachinePositionAcceptancePolicy.accepts(
        markGeometry.center,
        target: intendedMarkPosition
      ),
      preMarkFrame.source == revealEvidence.frame.source,
      preMarkFrame.captureSessionID == revealEvidence.frame.captureSessionID,
      preMarkFrame.opticalConfiguration == revealEvidence.frame.opticalConfiguration,
      preMarkFrame.cameraConfigurationID == revealEvidence.frame.cameraConfigurationID,
      preMarkCapEstimate.source == preMarkFrame.source,
      preMarkCapEstimate.frameID == preMarkFrame.frameID,
      preMarkCapEstimate.cameraConfigurationID == preMarkFrame.cameraConfigurationID
    else { throw TipCalibrationAuthorityError.frameEvidenceMismatch }
    guard click.point.x >= 0, click.point.x < Double(revealEvidence.frame.width),
      click.point.y >= 0, click.point.y < Double(revealEvidence.frame.height)
    else { throw TipCalibrationAuthorityError.clickOutsideFrame }
    guard preMarkFrame.captureNanoseconds <= penDown.timestamp.monotonicNanoseconds,
      penDown.timestamp.monotonicNanoseconds <= penUp.timestamp.monotonicNanoseconds,
      penUp.timestamp.monotonicNanoseconds <= revealEvidence.settledAt.monotonicNanoseconds,
      revealEvidence.frame.captureNanoseconds <= click.timestamp.monotonicNanoseconds
    else { throw TipCalibrationAuthorityError.invalidTemporalOrder }
    if disposition == .accepted {
      guard case .commandedAndSettled(command: .lower, commandedState: .down) = penDown.outcome,
        case .commandedAndSettled(command: .raise, commandedState: .up) = penUp.outcome
      else { throw TipCalibrationAuthorityError.invalidAcceptedPenEvidence }
    }
    guard !consumedLearningArtifactRevisionIDs.isEmpty, !algorithmRevisions.isEmpty else {
      throw TipCalibrationAuthorityError.invalidObservationSet
    }
    self.id = id
    self.attemptID = attemptID
    self.operationID = operationID
    self.calibrationPosition = calibrationPosition
    self.intendedMarkPosition = intendedMarkPosition
    self.actualSettledPosition = actualSettledPosition
    self.machineGeometry = machineGeometry
    self.controllerSessionID = controllerSessionID
    self.machineCoordinateFrame = machineCoordinateFrame
    self.controllerContextEvidence = controllerContextEvidence
    self.markGeometry = markGeometry
    self.penDown = penDown
    self.penUp = penUp
    self.toolAssembly = toolAssembly
    self.penContactProfile = penContactProfile
    self.paperContactPlane = paperContactPlane
    self.preMarkFrame = preMarkFrame
    self.preMarkCapEstimate = preMarkCapEstimate
    self.revealEvidence = revealEvidence
    self.click = click
    self.capMapPredictionAtMark = capMapPredictionAtMark
    capMapResidualPixels = capResidual
    self.disposition = disposition
    self.consumedLearningArtifactRevisionIDs = consumedLearningArtifactRevisionIDs
    self.algorithmRevisions = algorithmRevisions
  }

  public func durableEvidenceSHA256() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(self)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  public var postRevealSelectionFrame: ExactTipCalibrationFrame { revealEvidence.frame }
}

public enum TipCameraModelForm: String, Codable, Hashable, Sendable {
  case constantCameraPixelCorrection
  case directAffine
}

public enum TipCalibrationModelSelectionError: Error, Equatable, Sendable {
  case invalidObservationSet
}

/// Provenance for the five observations consumed by affine-first construction.
/// Model form records whether affine construction succeeded or the constant
/// correction construction fallback was required. Residuals are retained
/// separately as diagnostics and never select or reject a model.
public struct TipCalibrationModelSelectionEvidence: Codable, Hashable, Sendable {
  public let observationIDs: [ToolContactObservationID]
  public let selectedModelForm: TipCameraModelForm

  fileprivate func validate() throws {
    guard observationIDs.count == 5, Set(observationIDs).count == 5
    else { throw TipCalibrationModelSelectionError.invalidObservationSet }
  }
}

public struct TipCalibrationModelSelection: Hashable, Sendable {
  public let modelForm: TipCameraModelForm
  public let finalCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  public let uncertainty: TipCalibrationUncertainty
  public let evidence: TipCalibrationModelSelectionEvidence

  public static func fitAffineFirst(
    acceptedObservations: [AcceptedToolContactObservation],
    capCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  ) throws -> Self {
    guard acceptedObservations.count == 5,
      Set(acceptedObservations.map { $0.observation.calibrationPosition })
        == Set(ToolContactCalibrationPosition.allCases),
      Set(acceptedObservations.map { $0.observation.id }).count == 5,
      Set(acceptedObservations.map(\.artifactRevisionID)).count == 5
    else { throw TipCalibrationModelSelectionError.invalidObservationSet }
    let selectedForm: TipCameraModelForm
    let final: AffineTransform2<MachineSpace, CameraPixelSpace>
    do {
      final = try affineTransform(observations: acceptedObservations)
      selectedForm = .directAffine
    } catch {
      final = try constantCorrectionTransform(
        observations: acceptedObservations,
        capCameraFromMachine: capCameraFromMachine
      )
      selectedForm = .constantCameraPixelCorrection
    }
    let residuals = try acceptedObservations.map {
      try final.applying(to: $0.observation.actualSettledPosition.point)
        .distance(to: $0.observation.click.point)
    }
    let rms = sqrt(residuals.reduce(0) { $0 + $1 * $1 } / Double(residuals.count))
    let variance = max(1e-9, rms * rms)
    var covariance = Array(repeating: 0.0, count: 36)
    for index in 0..<6 { covariance[index * 6 + index] = variance }
    let evidence = TipCalibrationModelSelectionEvidence(
      observationIDs: acceptedObservations.map { $0.observation.id },
      selectedModelForm: selectedForm
    )
    try evidence.validate()
    return Self(
      modelForm: selectedForm,
      finalCameraFromMachine: final,
      uncertainty: try TipCalibrationUncertainty(
        affineParameterCovariance: covariance,
        rootMeanSquareResidualPixels: rms,
        maximumResidualPixels: residuals.max() ?? 0
      ),
      evidence: evidence
    )
  }

  private static func constantCorrectionTransform(
    observations: [AcceptedToolContactObservation],
    capCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  ) throws -> AffineTransform2<MachineSpace, CameraPixelSpace> {
    var weightedDX = 0.0
    var weightedDY = 0.0
    var totalWeight = 0.0
    for accepted in observations {
      let observation = accepted.observation
      let cap = try capCameraFromMachine.applying(to: observation.actualSettledPosition.point)
      let uncertainty = observation.click.pointingUncertaintyPixels
      let weight = 1 / max(1e-9, uncertainty.dx * uncertainty.dx + uncertainty.dy * uncertainty.dy)
      weightedDX += weight * (observation.click.point.x - cap.x)
      weightedDY += weight * (observation.click.point.y - cap.y)
      totalWeight += weight
    }
    guard totalWeight > 0 else { throw TipCalibrationModelSelectionError.invalidObservationSet }
    return try AffineTransform2(
      m11: capCameraFromMachine.m11,
      m12: capCameraFromMachine.m12,
      m21: capCameraFromMachine.m21,
      m22: capCameraFromMachine.m22,
      tx: capCameraFromMachine.tx + weightedDX / totalWeight,
      ty: capCameraFromMachine.ty + weightedDY / totalWeight
    )
  }

  private static func affineTransform(
    observations: [AcceptedToolContactObservation]
  ) throws -> AffineTransform2<MachineSpace, CameraPixelSpace> {
    let correspondences = observations.map {
      MachineCameraRegistrationCorrespondence(
        machine: $0.observation.actualSettledPosition.point,
        camera: $0.observation.click.point
      )
    }
    let weights = observations.map {
      let uncertainty = $0.observation.click.pointingUncertaintyPixels
      return 1 / max(1e-9, uncertainty.dx * uncertainty.dx + uncertainty.dy * uncertainty.dy)
    }
    return try MachineCameraRegistrationFit.fit(
      correspondences: correspondences,
      weights: weights
    ).cameraFromMachine
  }

  fileprivate static func supportsDirectAffineConstruction(
    observations: [AcceptedToolContactObservation]
  ) -> Bool {
    do {
      _ = try affineTransform(observations: observations)
      return true
    } catch {
      return false
    }
  }
}

public enum TipCalibrationSampleRole: String, Codable, Hashable, Sendable {
  case fit
  case holdout
}

public struct AcceptedToolContactObservation: Codable, Hashable, Sendable {
  public let artifactRevisionID: LearningArtifactRevisionID
  public let observation: ToolContactObservation

  public init(
    artifactRevisionID: LearningArtifactRevisionID,
    observation: ToolContactObservation
  ) throws {
    guard observation.disposition == .accepted else {
      throw TipCalibrationAuthorityError.invalidObservationSet
    }
    self.artifactRevisionID = artifactRevisionID
    self.observation = observation
  }
}

public struct TipRegistrationObservationEvidence: Codable, Hashable, Sendable {
  public let observationID: ToolContactObservationID
  public let observationArtifactRevisionID: LearningArtifactRevisionID
  public let observationSHA256: String
  public let calibrationPosition: ToolContactCalibrationPosition
  public let observedPoint: Point2<CameraPixelSpace>
  public let predictedPoint: Point2<CameraPixelSpace>
  public let pointingUncertaintyPixels: Vector2<CameraPixelSpace>
  public let residualPixels: Double

  fileprivate init(
    observationID: ToolContactObservationID,
    observationArtifactRevisionID: LearningArtifactRevisionID,
    observationSHA256: String,
    calibrationPosition: ToolContactCalibrationPosition,
    observedPoint: Point2<CameraPixelSpace>,
    predictedPoint: Point2<CameraPixelSpace>,
    pointingUncertaintyPixels: Vector2<CameraPixelSpace>
  ) throws {
    guard ContentAddressedFrameLocator.isSHA256(observationSHA256),
      pointingUncertaintyPixels.dx > 0, pointingUncertaintyPixels.dy > 0
    else { throw TipCalibrationAuthorityError.invalidRegistrationEvidence }
    self.observationID = observationID
    self.observationArtifactRevisionID = observationArtifactRevisionID
    self.observationSHA256 = observationSHA256.lowercased()
    self.calibrationPosition = calibrationPosition
    self.observedPoint = observedPoint
    self.predictedPoint = predictedPoint
    self.pointingUncertaintyPixels = pointingUncertaintyPixels
    residualPixels = observedPoint.distance(to: predictedPoint)
    guard residualPixels.isFinite else {
      throw TipCalibrationAuthorityError.invalidRegistrationEvidence
    }
  }

  fileprivate func validate() throws {
    guard ContentAddressedFrameLocator.isSHA256(observationSHA256),
      pointingUncertaintyPixels.dx > 0,
      pointingUncertaintyPixels.dy > 0,
      residualPixels.isFinite,
      abs(observedPoint.distance(to: predictedPoint) - residualPixels) <= 1e-9
    else { throw TipCalibrationAuthorityError.invalidRegistrationEvidence }
  }
}

public struct TipCalibrationUncertainty: Codable, Hashable, Sendable {
  /// Row-major covariance for [m11, m12, m21, m22, tx, ty].
  public let affineParameterCovariance: [Double]
  public let rootMeanSquareResidualPixels: Double
  public let maximumResidualPixels: Double

  public init(
    affineParameterCovariance: [Double],
    rootMeanSquareResidualPixels: Double,
    maximumResidualPixels: Double
  ) throws {
    guard affineParameterCovariance.count == 36,
      affineParameterCovariance.allSatisfy(\.isFinite),
      (0..<6).allSatisfy({ row in
        (0..<6).allSatisfy { column in
          abs(
            affineParameterCovariance[row * 6 + column]
              - affineParameterCovariance[column * 6 + row]
          ) <= 1e-9
        }
      }),
      Self.isPositiveSemidefinite(affineParameterCovariance),
      rootMeanSquareResidualPixels.isFinite, rootMeanSquareResidualPixels >= 0,
      maximumResidualPixels.isFinite, maximumResidualPixels >= 0
    else { throw TipCalibrationAuthorityError.invalidUncertainty }
    self.affineParameterCovariance = affineParameterCovariance
    self.rootMeanSquareResidualPixels = rootMeanSquareResidualPixels
    self.maximumResidualPixels = maximumResidualPixels
  }

  fileprivate func validate() throws {
    _ = try Self(
      affineParameterCovariance: affineParameterCovariance,
      rootMeanSquareResidualPixels: rootMeanSquareResidualPixels,
      maximumResidualPixels: maximumResidualPixels
    )
  }

  fileprivate func transformed(by jacobian: [Double], pixelScale: Double = 1) throws -> Self {
    var result = Array(repeating: 0.0, count: 36)
    for row in 0..<6 {
      for column in 0..<6 {
        var value = 0.0
        for left in 0..<6 {
          for right in 0..<6 {
            value +=
              jacobian[row * 6 + left]
              * affineParameterCovariance[left * 6 + right]
              * jacobian[column * 6 + right]
          }
        }
        result[row * 6 + column] = value
      }
    }
    return try Self(
      affineParameterCovariance: result,
      rootMeanSquareResidualPixels: rootMeanSquareResidualPixels * pixelScale,
      maximumResidualPixels: maximumResidualPixels * pixelScale
    )
  }

  private static func isPositiveSemidefinite(_ matrix: [Double]) -> Bool {
    let tolerance = 1e-10
    var factor = Array(repeating: 0.0, count: 36)
    for row in 0..<6 {
      for column in 0...row {
        var value = matrix[row * 6 + column]
        for index in 0..<column {
          value -= factor[row * 6 + index] * factor[column * 6 + index]
        }
        if row == column {
          guard value >= -tolerance else { return false }
          factor[row * 6 + column] = sqrt(max(0, value))
        } else if factor[column * 6 + column] > tolerance {
          factor[row * 6 + column] = value / factor[column * 6 + column]
        } else if abs(value) > tolerance {
          return false
        }
      }
    }
    return true
  }
}

public struct KnownCameraPixelRebaseEvidence: Codable, Hashable, Sendable {
  public let id: UUID
  public let fromOpticalConfiguration: CameraOpticalConfigurationIdentity
  public let toOpticalConfiguration: CameraOpticalConfigurationIdentity
  public let transform: AffineTransform2<CameraPixelSpace, CameraPixelSpace>
  public let captureSessionID: CameraCaptureSessionID
  public let evidenceSHA256: String
  public let algorithmRevision: String

  public init(
    id: UUID = UUID(),
    fromOpticalConfiguration: CameraOpticalConfigurationIdentity,
    toOpticalConfiguration: CameraOpticalConfigurationIdentity,
    transform: AffineTransform2<CameraPixelSpace, CameraPixelSpace>,
    captureSessionID: CameraCaptureSessionID,
    evidenceSHA256: String,
    algorithmRevision: String
  ) throws {
    guard
      Self.isSupportedPixelOnlyChange(
        from: fromOpticalConfiguration,
        to: toOpticalConfiguration
      ),
      ContentAddressedFrameLocator.isSHA256(evidenceSHA256),
      !algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TipCalibrationAuthorityError.sourceRebaseNotPermitted }
    self.id = id
    self.fromOpticalConfiguration = fromOpticalConfiguration
    self.toOpticalConfiguration = toOpticalConfiguration
    self.transform = transform
    self.captureSessionID = captureSessionID
    self.evidenceSHA256 = evidenceSHA256.lowercased()
    self.algorithmRevision = algorithmRevision
  }

  fileprivate func validate() throws {
    guard
      Self.isSupportedPixelOnlyChange(
        from: fromOpticalConfiguration,
        to: toOpticalConfiguration
      ),
      ContentAddressedFrameLocator.isSHA256(evidenceSHA256),
      !algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TipCalibrationAuthorityError.sourceRebaseNotPermitted }
  }

  private static func isSupportedPixelOnlyChange(
    from: CameraOpticalConfigurationIdentity,
    to: CameraOpticalConfigurationIdentity
  ) -> Bool {
    from.source == to.source
      && from.sensorFormat == to.sensorFormat
      && from.orientation == to.orientation
      && from.mirrored == to.mirrored
      && from.digitalZoomFactor == to.digitalZoomFactor
      && from.lensIdentity == to.lensIdentity
      && from.focusConfiguration == to.focusConfiguration
      && from.mountRevision == to.mountRevision
  }
}

public enum TipRegistrationDerivation: Codable, Hashable, Sendable {
  case accepted
  case checkpointRevalidated(
    fromRevision: LearningArtifactRevisionID,
    evidenceID: UUID
  )
  case knownPixelTransform(
    fromRevision: LearningArtifactRevisionID,
    evidence: KnownCameraPixelRebaseEvidence
  )
  case knownMachineCoordinateRebase(
    fromRevision: LearningArtifactRevisionID,
    delta: Vector2<MachineSpace>
  )
}

/// Accepted operational authority mapping machine coordinates directly to the
/// paper-contact pixel. It is not a camera-independent physical tool vector.
public struct TipCameraRegistration: Codable, Hashable, Sendable {
  public let modelForm: TipCameraModelForm
  public let cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  public let modelSelectionEvidence: TipCalibrationModelSelectionEvidence
  public let uncertainty: TipCalibrationUncertainty
  public let applicabilityRectangle: AxisAlignedBounds<MachineSpace>
  public let observationEvidence: [TipRegistrationObservationEvidence]
  public let applicability: TipCalibrationApplicabilityContext
  public let acceptedRevisionID: LearningArtifactRevisionID
  public let machineCameraRegistrationRevisionID: LearningArtifactRevisionID
  public let captureSessionIDs: Set<CameraCaptureSessionID>
  public let estimatorRevision: String
  public let acceptedAt: RuntimeTimestamp
  public let derivation: TipRegistrationDerivation
  public let revalidationEvidence: TipCalibrationRevalidationEvidence?

  public init(
    modelForm: TipCameraModelForm,
    cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>,
    modelSelectionEvidence: TipCalibrationModelSelectionEvidence,
    uncertainty: TipCalibrationUncertainty,
    applicabilityRectangle: AxisAlignedBounds<MachineSpace>,
    acceptedObservations: [AcceptedToolContactObservation],
    applicability: TipCalibrationApplicabilityContext,
    acceptedRevisionID: LearningArtifactRevisionID,
    machineCameraRegistrationRevisionID: LearningArtifactRevisionID,
    estimatorRevision: String,
    acceptedAt: RuntimeTimestamp
  ) throws {
    try modelSelectionEvidence.validate()
    guard modelSelectionEvidence.selectedModelForm == modelForm,
      acceptedObservations.count == 5,
      Set(acceptedObservations.map { $0.observation.calibrationPosition })
        == Set(ToolContactCalibrationPosition.allCases),
      Set(acceptedObservations.map(\.artifactRevisionID)).count == 5,
      TipCalibrationModelSelection.supportsDirectAffineConstruction(
        observations: acceptedObservations
      ) == (modelForm == .directAffine),
      acceptedObservations.allSatisfy({
        $0.observation.click.timestamp.wallTime <= acceptedAt.wallTime
      })
    else { throw TipCalibrationAuthorityError.invalidRegistrationEvidence }
    let evidence = try acceptedObservations.map { accepted in
      let observation = accepted.observation
      guard observation.machineGeometry == applicability.machineGeometry,
        observation.machineCoordinateFrame == applicability.machineCoordinateFrame,
        observation.toolAssembly == applicability.toolAssembly,
        observation.penContactProfile == applicability.penContactProfile,
        observation.paperContactPlane == applicability.paperContactPlane,
        observation.postRevealSelectionFrame.opticalConfiguration
          == applicability.opticalConfiguration,
        observation.consumedLearningArtifactRevisionIDs.contains(
          machineCameraRegistrationRevisionID
        ),
        MachinePositionAcceptancePolicy.contains(
          observation.intendedMarkPosition,
          in: applicabilityRectangle
        ),
        MachinePositionAcceptancePolicy.contains(
          observation.actualSettledPosition,
          in: applicabilityRectangle
        ),
        MachinePositionAcceptancePolicy.contains(
          observation.markGeometry.center,
          in: applicabilityRectangle
        ),
        MachinePositionAcceptancePolicy.accepts(
          observation.markGeometry.center,
          target: observation.intendedMarkPosition
        ),
        MachinePositionAcceptancePolicy.accepts(
          residualMM: MachinePositionAcceptancePolicy.residualMM(
            observation.actualSettledPosition,
            from: observation.intendedMarkPosition
          )
        )
      else { throw TipCalibrationAuthorityError.invalidApplicabilityContext }
      return try TipRegistrationObservationEvidence(
        observationID: observation.id,
        observationArtifactRevisionID: accepted.artifactRevisionID,
        observationSHA256: observation.durableEvidenceSHA256(),
        calibrationPosition: observation.calibrationPosition,
        observedPoint: observation.click.point,
        predictedPoint: cameraFromMachine.applying(to: observation.actualSettledPosition.point),
        pointingUncertaintyPixels: observation.click.pointingUncertaintyPixels
      )
    }
    try self.init(
      modelForm: modelForm,
      cameraFromMachine: cameraFromMachine,
      modelSelectionEvidence: modelSelectionEvidence,
      uncertainty: uncertainty,
      applicabilityRectangle: applicabilityRectangle,
      validatedObservationEvidence: evidence,
      applicability: applicability,
      acceptedRevisionID: acceptedRevisionID,
      machineCameraRegistrationRevisionID: machineCameraRegistrationRevisionID,
      captureSessionIDs: Set(
        acceptedObservations.map {
          $0.observation.postRevealSelectionFrame.captureSessionID
        }),
      estimatorRevision: estimatorRevision,
      acceptedAt: acceptedAt,
      derivation: .accepted,
      revalidationEvidence: nil
    )
  }

  private init(
    modelForm: TipCameraModelForm,
    cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>,
    modelSelectionEvidence: TipCalibrationModelSelectionEvidence,
    uncertainty: TipCalibrationUncertainty,
    applicabilityRectangle: AxisAlignedBounds<MachineSpace>,
    validatedObservationEvidence observationEvidence: [TipRegistrationObservationEvidence],
    applicability: TipCalibrationApplicabilityContext,
    acceptedRevisionID: LearningArtifactRevisionID,
    machineCameraRegistrationRevisionID: LearningArtifactRevisionID,
    captureSessionIDs: Set<CameraCaptureSessionID>,
    estimatorRevision: String,
    acceptedAt: RuntimeTimestamp,
    derivation: TipRegistrationDerivation,
    revalidationEvidence: TipCalibrationRevalidationEvidence?
  ) throws {
    try modelSelectionEvidence.validate()
    let observationIDs = Set(observationEvidence.map(\.observationID))
    let observationRevisionIDs = Set(observationEvidence.map(\.observationArtifactRevisionID))
    let positions = Set(observationEvidence.map(\.calibrationPosition))
    guard modelSelectionEvidence.selectedModelForm == modelForm,
      Set(modelSelectionEvidence.observationIDs) == observationIDs,
      observationEvidence.count == 5, observationIDs.count == 5,
      observationRevisionIDs.count == 5,
      positions == Set(ToolContactCalibrationPosition.allCases),
      !captureSessionIDs.isEmpty,
      !estimatorRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TipCalibrationAuthorityError.invalidObservationSet }
    try uncertainty.validate()
    for item in observationEvidence { try item.validate() }
    self.modelForm = modelForm
    self.cameraFromMachine = cameraFromMachine
    self.modelSelectionEvidence = modelSelectionEvidence
    self.uncertainty = uncertainty
    self.applicabilityRectangle = applicabilityRectangle
    self.observationEvidence = observationEvidence
    self.applicability = applicability
    self.acceptedRevisionID = acceptedRevisionID
    self.machineCameraRegistrationRevisionID = machineCameraRegistrationRevisionID
    self.captureSessionIDs = captureSessionIDs
    self.estimatorRevision = estimatorRevision
    self.acceptedAt = acceptedAt
    self.derivation = derivation
    self.revalidationEvidence = revalidationEvidence
  }

  fileprivate func validate() throws {
    _ = try Self(
      modelForm: modelForm,
      cameraFromMachine: cameraFromMachine,
      modelSelectionEvidence: modelSelectionEvidence,
      uncertainty: uncertainty,
      applicabilityRectangle: applicabilityRectangle,
      validatedObservationEvidence: observationEvidence,
      applicability: applicability,
      acceptedRevisionID: acceptedRevisionID,
      machineCameraRegistrationRevisionID: machineCameraRegistrationRevisionID,
      captureSessionIDs: captureSessionIDs,
      estimatorRevision: estimatorRevision,
      acceptedAt: acceptedAt,
      derivation: derivation,
      revalidationEvidence: revalidationEvidence
    )
    if case .knownPixelTransform(_, let evidence) = derivation {
      try evidence.validate()
    }
    if case .checkpointRevalidated(_, let evidenceID) = derivation {
      guard let revalidationEvidence,
        revalidationEvidence.id == evidenceID,
        revalidationEvidence.currentApplicability == applicability,
        revalidationEvidence.timestamp.wallTime <= acceptedAt.wallTime
      else { throw TipCalibrationAuthorityError.invalidCheckpoint }
      try revalidationEvidence.validate()
    }
  }

  public var consumedObservationIDs: Set<ToolContactObservationID> {
    Set(observationEvidence.map(\.observationID))
  }

  public var consumedArtifactRevisionIDs: Set<LearningArtifactRevisionID> {
    Set(observationEvidence.map(\.observationArtifactRevisionID))
      .union([machineCameraRegistrationRevisionID])
  }

  public func tipPixel(at machinePoint: Point2<MachineSpace>) throws -> Point2<CameraPixelSpace> {
    guard MachinePositionAcceptancePolicy.contains(machinePoint, in: applicabilityRectangle)
    else { throw GeometryError.outsideDomain }
    return try cameraFromMachine.applying(to: machinePoint)
  }

  public func applyingKnownPixelTransform(
    _ evidence: KnownCameraPixelRebaseEvidence
  ) throws -> Self {
    try evidence.validate()
    guard evidence.fromOpticalConfiguration == applicability.opticalConfiguration else {
      throw TipCalibrationAuthorityError.sourceRebaseNotPermitted
    }
    let transform = evidence.transform
    let a = cameraFromMachine
    let rebased = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: transform.m11 * a.m11 + transform.m12 * a.m21,
      m12: transform.m11 * a.m12 + transform.m12 * a.m22,
      m21: transform.m21 * a.m11 + transform.m22 * a.m21,
      m22: transform.m21 * a.m12 + transform.m22 * a.m22,
      tx: transform.m11 * a.tx + transform.m12 * a.ty + transform.tx,
      ty: transform.m21 * a.tx + transform.m22 * a.ty + transform.ty
    )
    var jacobian = Array(repeating: 0.0, count: 36)
    jacobian[0] = transform.m11
    jacobian[2] = transform.m12
    jacobian[7] = transform.m11
    jacobian[9] = transform.m12
    jacobian[12] = transform.m21
    jacobian[14] = transform.m22
    jacobian[19] = transform.m21
    jacobian[21] = transform.m22
    jacobian[28] = transform.m11
    jacobian[29] = transform.m12
    jacobian[34] = transform.m21
    jacobian[35] = transform.m22
    let pixelScale = Self.maximumLinearScale(of: transform)
    let rebasedEvidence = try observationEvidence.map { evidence in
      try TipRegistrationObservationEvidence(
        observationID: evidence.observationID,
        observationArtifactRevisionID: evidence.observationArtifactRevisionID,
        observationSHA256: evidence.observationSHA256,
        calibrationPosition: evidence.calibrationPosition,
        observedPoint: transform.applying(to: evidence.observedPoint),
        predictedPoint: transform.applying(to: evidence.predictedPoint),
        pointingUncertaintyPixels: Vector2(
          dx: hypot(
            transform.m11 * evidence.pointingUncertaintyPixels.dx,
            transform.m12 * evidence.pointingUncertaintyPixels.dy
          ),
          dy: hypot(
            transform.m21 * evidence.pointingUncertaintyPixels.dx,
            transform.m22 * evidence.pointingUncertaintyPixels.dy
          )
        )
      )
    }
    let updatedContext = TipCalibrationApplicabilityContext(
      opticalConfiguration: evidence.toOpticalConfiguration,
      machineGeometry: applicability.machineGeometry,
      machineCoordinateFrame: applicability.machineCoordinateFrame,
      toolAssembly: applicability.toolAssembly,
      penContactProfile: applicability.penContactProfile,
      paperContactPlane: applicability.paperContactPlane
    )
    return try Self(
      modelForm: modelForm,
      cameraFromMachine: rebased,
      modelSelectionEvidence: modelSelectionEvidence,
      uncertainty: uncertainty.transformed(by: jacobian, pixelScale: pixelScale),
      applicabilityRectangle: applicabilityRectangle,
      validatedObservationEvidence: rebasedEvidence,
      applicability: updatedContext,
      acceptedRevisionID: acceptedRevisionID,
      machineCameraRegistrationRevisionID: machineCameraRegistrationRevisionID,
      captureSessionIDs: captureSessionIDs.union([evidence.captureSessionID]),
      estimatorRevision: estimatorRevision,
      acceptedAt: acceptedAt,
      derivation: .knownPixelTransform(fromRevision: acceptedRevisionID, evidence: evidence),
      revalidationEvidence: revalidationEvidence
    )
  }

  /// `delta` defines new coordinates as m' = m + delta.
  public func rebasedForKnownMachineCoordinateChange(
    to revision: MachineCoordinateFrameRevision,
    delta: Vector2<MachineSpace>
  ) throws -> Self {
    let a = cameraFromMachine
    let rebased = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: a.m11, m12: a.m12, m21: a.m21, m22: a.m22,
      tx: a.tx - a.m11 * delta.dx - a.m12 * delta.dy,
      ty: a.ty - a.m21 * delta.dx - a.m22 * delta.dy
    )
    let domain = try AxisAlignedBounds<MachineSpace>(
      minX: applicabilityRectangle.minX + delta.dx,
      minY: applicabilityRectangle.minY + delta.dy,
      maxX: applicabilityRectangle.maxX + delta.dx,
      maxY: applicabilityRectangle.maxY + delta.dy
    )
    var jacobian = Array(repeating: 0.0, count: 36)
    jacobian[0] = 1
    jacobian[7] = 1
    jacobian[14] = 1
    jacobian[21] = 1
    jacobian[24] = -delta.dx
    jacobian[25] = -delta.dy
    jacobian[28] = 1
    jacobian[32] = -delta.dx
    jacobian[33] = -delta.dy
    jacobian[35] = 1
    let updatedContext = TipCalibrationApplicabilityContext(
      opticalConfiguration: applicability.opticalConfiguration,
      machineGeometry: applicability.machineGeometry,
      machineCoordinateFrame: revision,
      toolAssembly: applicability.toolAssembly,
      penContactProfile: applicability.penContactProfile,
      paperContactPlane: applicability.paperContactPlane
    )
    return try Self(
      modelForm: modelForm,
      cameraFromMachine: rebased,
      modelSelectionEvidence: modelSelectionEvidence,
      uncertainty: uncertainty.transformed(by: jacobian),
      applicabilityRectangle: domain,
      validatedObservationEvidence: observationEvidence,
      applicability: updatedContext,
      acceptedRevisionID: acceptedRevisionID,
      machineCameraRegistrationRevisionID: machineCameraRegistrationRevisionID,
      captureSessionIDs: captureSessionIDs,
      estimatorRevision: estimatorRevision,
      acceptedAt: acceptedAt,
      derivation: .knownMachineCoordinateRebase(
        fromRevision: acceptedRevisionID,
        delta: delta
      ),
      revalidationEvidence: revalidationEvidence
    )
  }

  private static func maximumLinearScale(
    of transform: AffineTransform2<CameraPixelSpace, CameraPixelSpace>
  ) -> Double {
    let s11 = transform.m11 * transform.m11 + transform.m21 * transform.m21
    let s12 = transform.m11 * transform.m12 + transform.m21 * transform.m22
    let s22 = transform.m12 * transform.m12 + transform.m22 * transform.m22
    let largestEigenvalue = (s11 + s22 + sqrt(pow(s11 - s22, 2) + 4 * s12 * s12)) / 2
    return sqrt(max(0, largestEigenvalue))
  }
}

public enum TipCalibrationApplicabilityChange: Hashable, Sendable {
  case presentationTransformChanged(PresentationTransformRevision)
  case captureSessionRestarted(
    CameraCaptureSessionID,
    provenOpticalConfiguration: CameraOpticalConfigurationIdentity
  )
  case knownPixelTransform(
    KnownCameraPixelRebaseEvidence
  )
  case knownMachineCoordinateRebase(MachineCoordinateFrameRevision, Vector2<MachineSpace>)
  case paperContactPlaneChanged(PaperContactPlaneRevision)
  case unknownOpticalChange
  case liveSimulationSourceChanged
  case unknownMachineCoordinateChange
  case machineGeometryChanged
  case toolAssemblyChanged
  case penContactProfileChanged
}

public enum TipCalibrationApplicabilityDecision: Hashable, Sendable {
  case retain
  case requireExplicitRevalidation(String)
  case quarantine(String)
  case invalidate(String)
  case rebased(TipCameraRegistration)
}

extension TipCameraRegistration {
  /// Derives a new accepted revision from a quarantined checkpoint after fresh
  /// controller/cap evidence has revalidated the original semantic authority.
  /// Raw observation identities and hashes remain unchanged; their in-memory
  /// graph revisions are rebuilt under the current machine-camera revision.
  public func revalidatedFromCheckpoint(
    evidence: TipCalibrationRevalidationEvidence,
    acceptedRevisionID: LearningArtifactRevisionID,
    machineCameraRegistrationRevisionID: LearningArtifactRevisionID,
    observationArtifactRevisionIDs: [ToolContactObservationID: LearningArtifactRevisionID],
    acceptedAt: RuntimeTimestamp
  ) throws -> Self {
    let current = evidence.currentApplicability
    guard current.opticalConfiguration == applicability.opticalConfiguration,
      current.machineGeometry == applicability.machineGeometry,
      current.machineCoordinateFrame == applicability.machineCoordinateFrame,
      current.toolAssembly == applicability.toolAssembly,
      current.penContactProfile == applicability.penContactProfile,
      current.paperContactPlane == applicability.paperContactPlane,
      evidence.currentMachineCameraRegistrationRevisionID
        == machineCameraRegistrationRevisionID,
      evidence.timestamp.wallTime <= acceptedAt.wallTime,
      observationArtifactRevisionIDs.count == observationEvidence.count,
      Set(observationArtifactRevisionIDs.keys) == Set(observationEvidence.map(\.observationID))
    else { throw TipCalibrationAuthorityError.invalidCheckpoint }
    let rebuiltEvidence = try observationEvidence.map { item in
      guard let artifactRevisionID = observationArtifactRevisionIDs[item.observationID] else {
        throw TipCalibrationAuthorityError.invalidCheckpoint
      }
      return try TipRegistrationObservationEvidence(
        observationID: item.observationID,
        observationArtifactRevisionID: artifactRevisionID,
        observationSHA256: item.observationSHA256,
        calibrationPosition: item.calibrationPosition,
        observedPoint: item.observedPoint,
        predictedPoint: item.predictedPoint,
        pointingUncertaintyPixels: item.pointingUncertaintyPixels
      )
    }
    let durableSourceRevision: LearningArtifactRevisionID =
      switch derivation {
      case .checkpointRevalidated(let fromRevision, _): fromRevision
      case .accepted, .knownPixelTransform, .knownMachineCoordinateRebase:
        self.acceptedRevisionID
      }
    return try Self(
      modelForm: modelForm,
      cameraFromMachine: cameraFromMachine,
      modelSelectionEvidence: modelSelectionEvidence,
      uncertainty: uncertainty,
      applicabilityRectangle: applicabilityRectangle,
      validatedObservationEvidence: rebuiltEvidence,
      applicability: evidence.currentApplicability,
      acceptedRevisionID: acceptedRevisionID,
      machineCameraRegistrationRevisionID: machineCameraRegistrationRevisionID,
      captureSessionIDs: captureSessionIDs.union([evidence.captureSessionID]),
      estimatorRevision: estimatorRevision,
      acceptedAt: acceptedAt,
      derivation: .checkpointRevalidated(
        fromRevision: durableSourceRevision,
        evidenceID: evidence.id
      ),
      revalidationEvidence: evidence
    )
  }

  public func applicabilityDecision(
    for change: TipCalibrationApplicabilityChange
  ) throws -> TipCalibrationApplicabilityDecision {
    switch change {
    case .presentationTransformChanged:
      return .retain
    case .captureSessionRestarted(_, let provenOpticalConfiguration):
      guard provenOpticalConfiguration == applicability.opticalConfiguration else {
        return .invalidate("Capture restarted with different semantic optical identity.")
      }
      return .requireExplicitRevalidation(
        "Capture restarted; semantic optics match but authority must be revalidated."
      )
    case .knownPixelTransform(let evidence):
      return .rebased(try applyingKnownPixelTransform(evidence))
    case .knownMachineCoordinateRebase(let revision, let delta):
      return .rebased(try rebasedForKnownMachineCoordinateChange(to: revision, delta: delta))
    case .paperContactPlaneChanged:
      return .quarantine("Paper/contact plane changed; contact-plane revalidation is required.")
    case .unknownOpticalChange:
      return .invalidate("Semantic optical configuration changed without a known pixel transform.")
    case .liveSimulationSourceChanged:
      return .invalidate("LIVE and SIMULATED optical authority cannot cross sources.")
    case .unknownMachineCoordinateChange:
      return .invalidate("Machine coordinate origin changed without a known rebase.")
    case .machineGeometryChanged:
      return .invalidate("Machine geometry, steps, direction, or kinematics changed.")
    case .toolAssemblyChanged:
      return .invalidate("Tool assembly, holder, armature, cap landmark, nib, or remount changed.")
    case .penContactProfileChanged:
      return .invalidate("Pen contact profile changed.")
    }
  }
}

public struct TipCalibrationAcceptanceEvent: Codable, Hashable, Sendable {
  public let id: UUID
  public let acceptedRevisionID: LearningArtifactRevisionID
  public let timestamp: RuntimeTimestamp
  public let actor: String

  public init(
    id: UUID = UUID(),
    acceptedRevisionID: LearningArtifactRevisionID,
    timestamp: RuntimeTimestamp,
    actor: String
  ) throws {
    guard !actor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw TipCalibrationAuthorityError.emptyValue("acceptance actor")
    }
    self.id = id
    self.acceptedRevisionID = acceptedRevisionID
    self.timestamp = timestamp
    self.actor = actor
  }
}

public struct TipCalibrationRevalidationEvidence: Codable, Hashable, Sendable {
  public let id: UUID
  public let currentApplicability: TipCalibrationApplicabilityContext
  public let currentMachineCameraRegistrationRevisionID: LearningArtifactRevisionID
  public let controllerContextEvidence: ControllerContextEvidenceReference
  public let frame: ExactTipCalibrationFrame
  public let capEstimate: ToolCapAnchorEstimate
  public let capMapPrediction: Point2<CameraPixelSpace>
  public let capMapResidualPixels: Double
  public let maximumCapMapResidualPixels: Double
  public let timestamp: RuntimeTimestamp
  public let algorithmRevision: String

  public var captureSessionID: CameraCaptureSessionID { frame.captureSessionID }

  public init(
    id: UUID = UUID(),
    currentApplicability: TipCalibrationApplicabilityContext,
    currentMachineCameraRegistrationRevisionID: LearningArtifactRevisionID,
    controllerContextEvidence: ControllerContextEvidenceReference,
    frame: ExactTipCalibrationFrame,
    capEstimate: ToolCapAnchorEstimate,
    capMapPrediction: Point2<CameraPixelSpace>,
    maximumCapMapResidualPixels: Double,
    timestamp: RuntimeTimestamp,
    algorithmRevision: String
  ) throws {
    let capResidual = capMapPrediction.distance(to: capEstimate.point)
    guard currentApplicability.opticalConfiguration == frame.opticalConfiguration,
      capEstimate.source == frame.source,
      capEstimate.frameID == frame.frameID,
      capEstimate.cameraConfigurationID == frame.cameraConfigurationID,
      maximumCapMapResidualPixels.isFinite,
      maximumCapMapResidualPixels >= 0,
      capResidual <= maximumCapMapResidualPixels,
      frame.captureNanoseconds <= timestamp.monotonicNanoseconds,
      !algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw TipCalibrationAuthorityError.frameEvidenceMismatch }
    self.id = id
    self.currentApplicability = currentApplicability
    self.currentMachineCameraRegistrationRevisionID =
      currentMachineCameraRegistrationRevisionID
    self.controllerContextEvidence = controllerContextEvidence
    self.frame = frame
    self.capEstimate = capEstimate
    self.capMapPrediction = capMapPrediction
    capMapResidualPixels = capResidual
    self.maximumCapMapResidualPixels = maximumCapMapResidualPixels
    self.timestamp = timestamp
    self.algorithmRevision = algorithmRevision
  }

  fileprivate func validate() throws {
    _ = try Self(
      id: id,
      currentApplicability: currentApplicability,
      currentMachineCameraRegistrationRevisionID:
        currentMachineCameraRegistrationRevisionID,
      controllerContextEvidence: controllerContextEvidence,
      frame: frame,
      capEstimate: capEstimate,
      capMapPrediction: capMapPrediction,
      maximumCapMapResidualPixels: maximumCapMapResidualPixels,
      timestamp: timestamp,
      algorithmRevision: algorithmRevision
    )
  }
}

public struct RevalidatedTipCameraAuthority: Hashable, Sendable {
  public let registration: TipCameraRegistration
  public let effectiveApplicability: TipCalibrationApplicabilityContext
  public let evidence: TipCalibrationRevalidationEvidence
}

public enum AcceptedTipCalibrationCheckpointRevalidation: Hashable, Sendable {
  case restored(RevalidatedTipCameraAuthority)
  case quarantined(String)
  case invalidated(String)
}

/// Durable tip authority is separate from the machine-only checkpoint. Loading
/// this payload never restores a graph revision or operational authority.
public struct AcceptedTipCalibrationCheckpoint: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 1
  public static let algorithmRevision = "accepted-tip-calibration-v1"

  public let schemaVersion: UInt16
  public let algorithmRevision: String
  public let checkpointID: UUID
  public let registration: TipCameraRegistration
  public let acceptanceEvent: TipCalibrationAcceptanceEvent

  public init(
    checkpointID: UUID = UUID(),
    registration: TipCameraRegistration,
    acceptanceEvent: TipCalibrationAcceptanceEvent
  ) throws {
    schemaVersion = Self.schemaVersion
    algorithmRevision = Self.algorithmRevision
    self.checkpointID = checkpointID
    self.registration = registration
    self.acceptanceEvent = acceptanceEvent
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == Self.schemaVersion else {
      throw TipCalibrationAuthorityError.unsupportedCheckpointSchema(schemaVersion)
    }
    guard algorithmRevision == Self.algorithmRevision else {
      throw TipCalibrationAuthorityError.unsupportedCheckpointAlgorithm(algorithmRevision)
    }
    try registration.validate()
    guard acceptanceEvent.acceptedRevisionID == registration.acceptedRevisionID,
      acceptanceEvent.timestamp.wallTime >= registration.acceptedAt.wallTime
    else { throw TipCalibrationAuthorityError.invalidCheckpoint }
  }

  public func revalidate(
    with evidence: TipCalibrationRevalidationEvidence
  ) -> AcceptedTipCalibrationCheckpointRevalidation {
    let accepted = registration.applicability
    let current = evidence.currentApplicability
    guard evidence.timestamp.wallTime >= acceptanceEvent.timestamp.wallTime
    else { return .quarantined("Revalidation evidence predates checkpoint acceptance.") }
    guard accepted.opticalConfiguration == current.opticalConfiguration else {
      return .invalidated("Semantic optical identity does not match the checkpoint.")
    }
    guard accepted.machineGeometry == current.machineGeometry,
      accepted.machineCoordinateFrame == current.machineCoordinateFrame
    else { return .invalidated("Machine geometry or coordinate-frame identity changed.") }
    guard accepted.toolAssembly == current.toolAssembly,
      accepted.penContactProfile == current.penContactProfile
    else { return .invalidated("Tool assembly or contact profile changed.") }
    guard accepted.paperContactPlane == current.paperContactPlane else {
      return .quarantined(
        "Paper/contact-plane identity changed; complete a fresh five-circle calibration."
      )
    }
    return .restored(
      RevalidatedTipCameraAuthority(
        registration: registration,
        effectiveApplicability: current,
        evidence: evidence
      )
    )
  }

}

public enum AcceptedTipCalibrationCheckpointLoadResult: Sendable {
  case absent
  case quarantined(AcceptedTipCalibrationCheckpoint)
  case rejected(String)
}

public struct AcceptedTipCalibrationCheckpointStore: Sendable {
  private struct Envelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() -> AcceptedTipCalibrationCheckpointLoadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
    do {
      let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: fileURL))
      guard envelope.schemaVersion == AcceptedTipCalibrationCheckpoint.schemaVersion else {
        return .rejected("Unsupported tip-checkpoint envelope schema \(envelope.schemaVersion).")
      }
      guard Self.sha256(envelope.payload) == envelope.payloadSHA256 else {
        return .rejected("Tip-checkpoint integrity verification failed.")
      }
      let checkpoint = try JSONDecoder().decode(
        AcceptedTipCalibrationCheckpoint.self,
        from: envelope.payload
      )
      try checkpoint.validate()
      return .quarantined(checkpoint)
    } catch {
      return .rejected("Tip checkpoint could not be decoded: \(error)")
    }
  }

  public func save(_ checkpoint: AcceptedTipCalibrationCheckpoint) throws {
    try checkpoint.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(checkpoint)
    let envelope = Envelope(
      schemaVersion: AcceptedTipCalibrationCheckpoint.schemaVersion,
      payload: payload,
      payloadSHA256: Self.sha256(payload)
    )
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try encoder.encode(envelope).write(to: fileURL, options: [.atomic])
  }

  public func clear() throws {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    try FileManager.default.removeItem(at: fileURL)
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
