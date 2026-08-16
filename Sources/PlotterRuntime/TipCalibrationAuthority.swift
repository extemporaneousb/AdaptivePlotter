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

public struct PaperContactPlaneRevision: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
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
  case invalidHoldoutEvidence
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
      archivedBytes?.contentSHA256 == nil || archivedBytes?.contentSHA256 == frameSHA256.lowercased()
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
      maximumChordDeviationMM <= ControllerPositionAcceptancePolicy.toleranceMM
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
    let positionResidual = ControllerPositionAcceptancePolicy.residualMM(
      actualSettledPosition,
      from: intendedPosition
    )
    let capResidual = capMapPrediction.distance(to: capEstimate.point)
    guard ControllerPositionAcceptancePolicy.accepts(residualMM: positionResidual),
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
  public let maximumCapMapResidualPixels: Double
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
    maximumCapMapResidualPixels: Double,
    disposition: ToolContactObservationDisposition,
    consumedLearningArtifactRevisionIDs: Set<LearningArtifactRevisionID>,
    algorithmRevisions: Set<AlgorithmRevisionEvidence>
  ) throws {
    guard disposition.reasonIsValid else { throw TipCalibrationAuthorityError.invalidDisposition }
    let markPositionResidual = ControllerPositionAcceptancePolicy.residualMM(
      actualSettledPosition,
      from: intendedMarkPosition
    )
    let capResidual = capMapPredictionAtMark.distance(to: preMarkCapEstimate.point)
    guard ControllerPositionAcceptancePolicy.accepts(residualMM: markPositionResidual),
      markGeometry.center == intendedMarkPosition,
      maximumCapMapResidualPixels.isFinite, maximumCapMapResidualPixels >= 0,
      capResidual <= maximumCapMapResidualPixels,
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
    self.maximumCapMapResidualPixels = maximumCapMapResidualPixels
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
  case constantFailureIsNotCoherent
  case affineHoldoutFailure
}

public struct TipCalibrationCandidateHoldout: Codable, Hashable, Sendable {
  public let calibrationPosition: ToolContactCalibrationPosition
  public let observedPoint: Point2<CameraPixelSpace>
  public let predictedPoint: Point2<CameraPixelSpace>
  public let residualPixels: Double
  public let maximumResidualPixels: Double

  public var passes: Bool { residualPixels <= maximumResidualPixels }

  fileprivate init(
    observation: AcceptedToolContactObservation,
    transform: AffineTransform2<MachineSpace, CameraPixelSpace>,
    maximumResidualPixels: Double
  ) throws {
    calibrationPosition = observation.observation.calibrationPosition
    observedPoint = observation.observation.click.point
    predictedPoint = try transform.applying(to: observation.observation.actualSettledPosition.point)
    residualPixels = observedPoint.distance(to: predictedPoint)
    self.maximumResidualPixels = maximumResidualPixels
  }
}

public enum TipCalibrationAffineEscalationDisposition: String, Codable, Hashable, Sendable {
  case notRequired
  case coherentTwoHoldoutFailure
}

/// Independent pre-refit evidence. Holdout predictions are sealed before the
/// last two observations may participate in the final five-sample refit.
public struct TipCalibrationModelSelectionEvidence: Codable, Hashable, Sendable {
  public let fitObservationIDs: [ToolContactObservationID]
  public let holdoutObservationIDs: [ToolContactObservationID]
  public let constantCandidate: AffineTransform2<MachineSpace, CameraPixelSpace>
  public let constantHoldouts: [TipCalibrationCandidateHoldout]
  public let affineEscalation: TipCalibrationAffineEscalationDisposition
  public let affineCandidate: AffineTransform2<MachineSpace, CameraPixelSpace>?
  public let affineHoldouts: [TipCalibrationCandidateHoldout]
  public let selectedModelForm: TipCameraModelForm

  fileprivate func validate() throws {
    guard fitObservationIDs.count == 3, Set(fitObservationIDs).count == 3,
      holdoutObservationIDs.count == 2, Set(holdoutObservationIDs).count == 2,
      Set(fitObservationIDs).isDisjoint(with: Set(holdoutObservationIDs)),
      constantHoldouts.count == 2,
      constantHoldouts.allSatisfy({
        $0.calibrationPosition == .positiveX || $0.calibrationPosition == .negativeY
      })
    else { throw TipCalibrationModelSelectionError.invalidObservationSet }
    switch selectedModelForm {
    case .constantCameraPixelCorrection:
      guard affineEscalation == .notRequired, affineCandidate == nil,
        affineHoldouts.isEmpty, constantHoldouts.allSatisfy(\.passes)
      else { throw TipCalibrationModelSelectionError.invalidObservationSet }
    case .directAffine:
      guard affineEscalation == .coherentTwoHoldoutFailure,
        constantHoldouts.allSatisfy({ !$0.passes }), affineCandidate != nil,
        affineHoldouts.count == 2, affineHoldouts.allSatisfy(\.passes)
      else { throw TipCalibrationModelSelectionError.invalidObservationSet }
    }
  }
}

public struct TipCalibrationModelSelection: Hashable, Sendable {
  public let modelForm: TipCameraModelForm
  public let finalCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  public let uncertainty: TipCalibrationUncertainty
  public let evidence: TipCalibrationModelSelectionEvidence

  public static func selectSmallestPassingModel(
    acceptedObservations: [AcceptedToolContactObservation],
    capCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>,
    maximumHoldoutResidualPixels: Double
  ) throws -> Self {
    guard acceptedObservations.count == 5,
      maximumHoldoutResidualPixels.isFinite, maximumHoldoutResidualPixels >= 0,
      Set(acceptedObservations.map { $0.observation.calibrationPosition })
        == Set(ToolContactCalibrationPosition.allCases)
    else { throw TipCalibrationModelSelectionError.invalidObservationSet }
    let fit = acceptedObservations.filter {
      TipRegistrationObservationEvidence.expectedRole(for: $0.observation.calibrationPosition)
        == .fit
    }
    let holdouts = acceptedObservations.filter {
      TipRegistrationObservationEvidence.expectedRole(for: $0.observation.calibrationPosition)
        == .holdout
    }
    guard fit.count == 3, holdouts.count == 2 else {
      throw TipCalibrationModelSelectionError.invalidObservationSet
    }

    let constantCandidate = try constantCorrectionTransform(
      observations: fit,
      capCameraFromMachine: capCameraFromMachine
    )
    let constantHoldouts = try holdouts.map {
      try TipCalibrationCandidateHoldout(
        observation: $0,
        transform: constantCandidate,
        maximumResidualPixels: maximumHoldoutResidualPixels
      )
    }
    let selectedForm: TipCameraModelForm
    let affineCandidate: AffineTransform2<MachineSpace, CameraPixelSpace>?
    let affineHoldouts: [TipCalibrationCandidateHoldout]
    let escalation: TipCalibrationAffineEscalationDisposition
    if constantHoldouts.allSatisfy(\.passes) {
      selectedForm = .constantCameraPixelCorrection
      affineCandidate = nil
      affineHoldouts = []
      escalation = .notRequired
    } else {
      // A lone bad holdout is not evidence for a larger model. Coherent
      // escalation also requires the two residual vectors to agree with one
      // affine trend rather than merely both exceeding a scalar threshold.
      guard constantHoldouts.allSatisfy({ !$0.passes }),
        coherentAffineFailure(constantHoldouts)
      else {
        throw TipCalibrationModelSelectionError.constantFailureIsNotCoherent
      }
      let candidate = try affineTransform(observations: fit)
      let tested = try holdouts.map {
        try TipCalibrationCandidateHoldout(
          observation: $0,
          transform: candidate,
          maximumResidualPixels: maximumHoldoutResidualPixels
        )
      }
      guard tested.allSatisfy(\.passes) else {
        throw TipCalibrationModelSelectionError.affineHoldoutFailure
      }
      selectedForm = .directAffine
      affineCandidate = candidate
      affineHoldouts = tested
      escalation = .coherentTwoHoldoutFailure
    }

    let final =
      switch selectedForm {
      case .constantCameraPixelCorrection:
        try constantCorrectionTransform(
          observations: acceptedObservations,
          capCameraFromMachine: capCameraFromMachine
        )
      case .directAffine:
        try affineTransform(observations: acceptedObservations)
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
      fitObservationIDs: fit.map { $0.observation.id },
      holdoutObservationIDs: holdouts.map { $0.observation.id },
      constantCandidate: constantCandidate,
      constantHoldouts: constantHoldouts,
      affineEscalation: escalation,
      affineCandidate: affineCandidate,
      affineHoldouts: affineHoldouts,
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

  /// A non-authoritative constant-correction candidate for post-click review
  /// once the three fit observations exist. Holdouts never participate here.
  public static func provisionalConstantCandidate(
    acceptedObservations: [AcceptedToolContactObservation],
    capCameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  ) throws -> AffineTransform2<MachineSpace, CameraPixelSpace> {
    let fit = acceptedObservations.filter {
      TipRegistrationObservationEvidence.expectedRole(for: $0.observation.calibrationPosition)
        == .fit
    }
    guard fit.count == 3,
      Set(fit.map { $0.observation.calibrationPosition })
        == Set([.center, .negativeX, .positiveY])
    else { throw TipCalibrationModelSelectionError.invalidObservationSet }
    return try constantCorrectionTransform(
      observations: fit,
      capCameraFromMachine: capCameraFromMachine
    )
  }

  private static func coherentAffineFailure(
    _ holdouts: [TipCalibrationCandidateHoldout]
  ) -> Bool {
    guard holdouts.count == 2 else { return false }
    let first = holdouts[0]
    let second = holdouts[1]
    let firstX = first.observedPoint.x - first.predictedPoint.x
    let firstY = first.observedPoint.y - first.predictedPoint.y
    let secondX = second.observedPoint.x - second.predictedPoint.x
    let secondY = second.observedPoint.y - second.predictedPoint.y
    // Orthogonal X+ and Y- holdouts may expose different affine columns; the
    // coherent requirement is finite, non-trivial residual evidence at both,
    // not equal direction or magnitude.
    return [firstX, firstY, secondX, secondY].allSatisfy(\.isFinite)
      && hypot(firstX, firstY) > 0
      && hypot(secondX, secondY) > 0
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
  public let role: TipCalibrationSampleRole
  public let observedPoint: Point2<CameraPixelSpace>
  public let predictedPoint: Point2<CameraPixelSpace>
  public let pointingUncertaintyPixels: Vector2<CameraPixelSpace>
  public let residualPixels: Double
  public let maximumResidualPixels: Double

  fileprivate init(
    observationID: ToolContactObservationID,
    observationArtifactRevisionID: LearningArtifactRevisionID,
    observationSHA256: String,
    calibrationPosition: ToolContactCalibrationPosition,
    role: TipCalibrationSampleRole,
    observedPoint: Point2<CameraPixelSpace>,
    predictedPoint: Point2<CameraPixelSpace>,
    pointingUncertaintyPixels: Vector2<CameraPixelSpace>,
    maximumResidualPixels: Double
  ) throws {
    guard ContentAddressedFrameLocator.isSHA256(observationSHA256),
      pointingUncertaintyPixels.dx > 0, pointingUncertaintyPixels.dy > 0,
      maximumResidualPixels.isFinite, maximumResidualPixels >= 0
    else { throw TipCalibrationAuthorityError.invalidHoldoutEvidence }
    self.observationID = observationID
    self.observationArtifactRevisionID = observationArtifactRevisionID
    self.observationSHA256 = observationSHA256.lowercased()
    self.calibrationPosition = calibrationPosition
    self.role = role
    self.observedPoint = observedPoint
    self.predictedPoint = predictedPoint
    self.pointingUncertaintyPixels = pointingUncertaintyPixels
    residualPixels = observedPoint.distance(to: predictedPoint)
    self.maximumResidualPixels = maximumResidualPixels
  }

  public var passes: Bool { residualPixels <= maximumResidualPixels }

  fileprivate func validate() throws {
    guard Self.expectedRole(for: calibrationPosition) == role,
      ContentAddressedFrameLocator.isSHA256(observationSHA256),
      pointingUncertaintyPixels.dx > 0,
      pointingUncertaintyPixels.dy > 0,
      maximumResidualPixels.isFinite,
      maximumResidualPixels >= 0,
      abs(observedPoint.distance(to: predictedPoint) - residualPixels) <= 1e-9
    else { throw TipCalibrationAuthorityError.invalidHoldoutEvidence }
  }

  fileprivate static func expectedRole(
    for position: ToolContactCalibrationPosition
  ) -> TipCalibrationSampleRole {
    switch position {
    case .center, .negativeX, .positiveY: .fit
    case .positiveX, .negativeY: .holdout
    }
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
            value += jacobian[row * 6 + left]
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
    guard Self.isSupportedPixelOnlyChange(
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
    guard Self.isSupportedPixelOnlyChange(
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
    maximumObservationResidualPixels: Double,
    applicability: TipCalibrationApplicabilityContext,
    acceptedRevisionID: LearningArtifactRevisionID,
    machineCameraRegistrationRevisionID: LearningArtifactRevisionID,
    estimatorRevision: String,
    acceptedAt: RuntimeTimestamp
  ) throws {
    try modelSelectionEvidence.validate()
    guard modelSelectionEvidence.selectedModelForm == modelForm,
      maximumObservationResidualPixels.isFinite,
      maximumObservationResidualPixels >= 0,
      acceptedObservations.count == 5,
      Set(acceptedObservations.map { $0.observation.calibrationPosition })
        == Set(ToolContactCalibrationPosition.allCases),
      Set(acceptedObservations.map(\.artifactRevisionID)).count == 5,
      acceptedObservations.allSatisfy({
        $0.observation.click.timestamp.wallTime <= acceptedAt.wallTime
      }),
      Self.fitPositionsAreNonCollinear(acceptedObservations)
    else { throw TipCalibrationAuthorityError.invalidHoldoutEvidence }
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
        applicabilityRectangle.contains(observation.actualSettledPosition.point)
      else { throw TipCalibrationAuthorityError.invalidApplicabilityContext }
      return try TipRegistrationObservationEvidence(
        observationID: observation.id,
        observationArtifactRevisionID: accepted.artifactRevisionID,
        observationSHA256: observation.durableEvidenceSHA256(),
        calibrationPosition: observation.calibrationPosition,
        role: TipRegistrationObservationEvidence.expectedRole(
          for: observation.calibrationPosition
        ),
        observedPoint: observation.click.point,
        predictedPoint: cameraFromMachine.applying(to: observation.actualSettledPosition.point),
        pointingUncertaintyPixels: observation.click.pointingUncertaintyPixels,
        maximumResidualPixels: maximumObservationResidualPixels
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
      captureSessionIDs: Set(acceptedObservations.map {
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
    let holdouts = observationEvidence.filter { $0.role == .holdout }
    let residualSquareMean = observationEvidence.reduce(0) {
      $0 + $1.residualPixels * $1.residualPixels
    } / Double(max(1, observationEvidence.count))
    let measuredRMSResidual = sqrt(residualSquareMean)
    let measuredMaximumResidual = observationEvidence.map(\.residualPixels).max() ?? 0
    guard modelSelectionEvidence.selectedModelForm == modelForm,
      Set(modelSelectionEvidence.fitObservationIDs + modelSelectionEvidence.holdoutObservationIDs)
        == observationIDs,
      observationEvidence.count == 5, observationIDs.count == 5,
      observationRevisionIDs.count == 5,
      positions == Set(ToolContactCalibrationPosition.allCases),
      observationEvidence.allSatisfy({
        $0.role == TipRegistrationObservationEvidence.expectedRole(for: $0.calibrationPosition)
      }),
      holdouts.count == 2, holdouts.allSatisfy(\.passes),
      uncertainty.rootMeanSquareResidualPixels + 1e-9 >= measuredRMSResidual,
      uncertainty.maximumResidualPixels + 1e-9 >= measuredMaximumResidual,
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

  private static func fitPositionsAreNonCollinear(
    _ acceptedObservations: [AcceptedToolContactObservation]
  ) -> Bool {
    let points = Dictionary(
      uniqueKeysWithValues: acceptedObservations.map {
        ($0.observation.calibrationPosition, $0.observation.actualSettledPosition.point)
      }
    )
    guard let center = points[.center],
      let negativeX = points[.negativeX],
      let positiveY = points[.positiveY]
    else { return false }
    let signedDoubleArea = (negativeX.x - center.x) * (positiveY.y - center.y)
      - (negativeX.y - center.y) * (positiveY.x - center.x)
    return abs(signedDoubleArea) > 1e-9
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
    var revisions = Set(observationEvidence.map(\.observationArtifactRevisionID))
      .union([machineCameraRegistrationRevisionID])
    if let contactRevision = revalidationEvidence?.contactPlaneRevalidation?
      .acceptedObservation.artifactRevisionID
    {
      revisions.insert(contactRevision)
    }
    return revisions
  }

  public func tipPixel(at machinePoint: Point2<MachineSpace>) throws -> Point2<CameraPixelSpace> {
    guard applicabilityRectangle.contains(machinePoint) else { throw GeometryError.outsideDomain }
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
    jacobian[0] = transform.m11; jacobian[2] = transform.m12
    jacobian[7] = transform.m11; jacobian[9] = transform.m12
    jacobian[12] = transform.m21; jacobian[14] = transform.m22
    jacobian[19] = transform.m21; jacobian[21] = transform.m22
    jacobian[28] = transform.m11; jacobian[29] = transform.m12
    jacobian[34] = transform.m21; jacobian[35] = transform.m22
    let pixelScale = Self.maximumLinearScale(of: transform)
    let rebasedEvidence = try observationEvidence.map { evidence in
      try TipRegistrationObservationEvidence(
        observationID: evidence.observationID,
        observationArtifactRevisionID: evidence.observationArtifactRevisionID,
        observationSHA256: evidence.observationSHA256,
        calibrationPosition: evidence.calibrationPosition,
        role: evidence.role,
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
        ),
        maximumResidualPixels: evidence.maximumResidualPixels * pixelScale
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
    jacobian[0] = 1; jacobian[7] = 1; jacobian[14] = 1; jacobian[21] = 1
    jacobian[24] = -delta.dx; jacobian[25] = -delta.dy; jacobian[28] = 1
    jacobian[32] = -delta.dx; jacobian[33] = -delta.dy; jacobian[35] = 1
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
      (current.paperContactPlane == applicability.paperContactPlane
        || evidence.contactPlaneRevalidation != nil),
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
        role: item.role,
        observedPoint: item.observedPoint,
        predictedPoint: item.predictedPoint,
        pointingUncertaintyPixels: item.pointingUncertaintyPixels,
        maximumResidualPixels: item.maximumResidualPixels
      )
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
        fromRevision: self.acceptedRevisionID,
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

public struct TipContactPlaneRevalidationEvidence: Codable, Hashable, Sendable {
  public let acceptedObservation: AcceptedToolContactObservation
  public let maximumTipResidualPixels: Double

  public init(
    acceptedObservation: AcceptedToolContactObservation,
    maximumTipResidualPixels: Double
  ) throws {
    guard maximumTipResidualPixels.isFinite, maximumTipResidualPixels >= 0 else {
      throw TipCalibrationAuthorityError.invalidHoldoutEvidence
    }
    self.acceptedObservation = acceptedObservation
    self.maximumTipResidualPixels = maximumTipResidualPixels
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
  public let contactPlaneRevalidation: TipContactPlaneRevalidationEvidence?
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
    contactPlaneRevalidation: TipContactPlaneRevalidationEvidence? = nil,
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
    self.contactPlaneRevalidation = contactPlaneRevalidation
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
      contactPlaneRevalidation: contactPlaneRevalidation,
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
    if accepted.paperContactPlane != current.paperContactPlane {
      guard let contactEvidence = evidence.contactPlaneRevalidation,
        acceptsContactPlaneRevalidation(
          contactEvidence,
          current: current,
          machineCameraRegistrationRevisionID:
            evidence.currentMachineCameraRegistrationRevisionID
        )
      else {
        return .quarantined("Paper/contact-plane identity changed; revalidate that plane first.")
      }
    }
    return .restored(
      RevalidatedTipCameraAuthority(
        registration: registration,
        effectiveApplicability: current,
        evidence: evidence
      )
    )
  }

  private func acceptsContactPlaneRevalidation(
    _ evidence: TipContactPlaneRevalidationEvidence,
    current: TipCalibrationApplicabilityContext,
    machineCameraRegistrationRevisionID: LearningArtifactRevisionID
  ) -> Bool {
    let observation = evidence.acceptedObservation.observation
    guard observation.disposition == .accepted,
      observation.machineGeometry == current.machineGeometry,
      observation.machineCoordinateFrame == current.machineCoordinateFrame,
      observation.toolAssembly == current.toolAssembly,
      observation.penContactProfile == current.penContactProfile,
      observation.paperContactPlane == current.paperContactPlane,
      observation.postRevealSelectionFrame.opticalConfiguration
        == current.opticalConfiguration,
      observation.consumedLearningArtifactRevisionIDs.contains(
        machineCameraRegistrationRevisionID
      ),
      observation.click.timestamp.wallTime >= acceptanceEvent.timestamp.wallTime,
      registration.applicabilityRectangle.contains(observation.actualSettledPosition.point),
      let predicted = try? registration.cameraFromMachine.applying(
        to: observation.actualSettledPosition.point
      )
    else { return false }
    return observation.click.point.distance(to: predicted)
      <= evidence.maximumTipResidualPixels
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
