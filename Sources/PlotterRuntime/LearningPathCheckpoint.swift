import CryptoKit
import Foundation
import PlotterModel

public struct LearningPathSemanticIdentity: Codable, Hashable, Sendable {
  public let machineGeometry: MachineGeometryIdentity
  public let toolAssembly: ToolAssemblyRevision
  public let penContactProfile: PenContactProfileRevision
  public let paperInstance: PaperInstanceRevision
  public let paperContactPlane: PaperContactPlaneRevision
  public let cameraMountRevision: UUID
  public let cameraReframingRevision: UUID

  public init(
    machineGeometry: MachineGeometryIdentity,
    toolAssembly: ToolAssemblyRevision,
    penContactProfile: PenContactProfileRevision,
    paperInstance: PaperInstanceRevision,
    paperContactPlane: PaperContactPlaneRevision,
    cameraMountRevision: UUID,
    cameraReframingRevision: UUID
  ) {
    self.machineGeometry = machineGeometry
    self.toolAssembly = toolAssembly
    self.penContactProfile = penContactProfile
    self.paperInstance = paperInstance
    self.paperContactPlane = paperContactPlane
    self.cameraMountRevision = cameraMountRevision
    self.cameraReframingRevision = cameraReframingRevision
  }
}

public struct AcceptedPenInteractionCheckpoint: Codable, Hashable, Sendable {
  public let revision: LearningArtifactRevision
  public let acceptedSequence: UInt64
  public let evidence: PenInteractionAttemptEvidence

  public init(
    revision: LearningArtifactRevision,
    acceptedSequence: UInt64,
    evidence: PenInteractionAttemptEvidence
  ) throws {
    guard revision.kind == .penInteraction,
      revision.state == .current,
      revision.disposition == .succeeded,
      revision.consumedRevisionIDs.isEmpty
    else { throw AcceptedLearningPathCheckpointError.invalidPenInteraction }
    self.revision = revision
    self.acceptedSequence = acceptedSequence
    self.evidence = evidence
  }
}

public struct AcceptedMachineCameraCheckpoint: Codable, Hashable, Sendable {
  public let revision: LearningArtifactRevision
  public let registration: MachineCameraRegistration

  public init(
    revision: LearningArtifactRevision,
    registration: MachineCameraRegistration
  ) throws {
    guard revision.kind == .machineCameraRegistration,
      revision.state == .current,
      revision.disposition == .succeeded,
      registration.correspondenceRevisionIDs.isSubset(of: revision.consumedRevisionIDs)
    else { throw AcceptedLearningPathCheckpointError.invalidMachineCameraRegistration }
    self.revision = revision
    self.registration = registration
  }
}

public struct AcceptedStageFourCheckpoint: Codable, Hashable, Sendable {
  public let recordID: DrawingEvidenceRecordID
  public let tipCalibrationRevisionID: LearningArtifactRevisionID
  public let paperContactPlane: PaperContactPlaneRevision

  public init(
    recordID: DrawingEvidenceRecordID,
    tipCalibrationRevisionID: LearningArtifactRevisionID,
    paperContactPlane: PaperContactPlaneRevision
  ) {
    self.recordID = recordID
    self.tipCalibrationRevisionID = tipCalibrationRevisionID
    self.paperContactPlane = paperContactPlane
  }
}

public enum AcceptedLearningPathCheckpointError: Error, Equatable, Sendable {
  case unsupportedSchema(UInt16)
  case unsupportedAlgorithm(String)
  case invalidPenInteraction
  case invalidMachineCameraRegistration
  case invalidTipCalibration
  case invalidStageFourReference
}

/// One durable accepted prefix of the LIVE Learning Path. Operational owners,
/// Motion authorization, current Pen pose, pending commands, camera frames, and
/// controller-pose trust are deliberately excluded.
public struct AcceptedLearningPathCheckpoint: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 1
  public static let algorithmRevision = "accepted-learning-path-v1"

  public let schemaVersion: UInt16
  public let algorithmRevision: String
  public let checkpointID: UUID
  public let semanticIdentity: LearningPathSemanticIdentity
  public let penInteraction: AcceptedPenInteractionCheckpoint?
  public let machineArtifacts: AcceptedMachineArtifactCheckpoint?
  public let machineCamera: AcceptedMachineCameraCheckpoint?
  public let tipCalibration: AcceptedTipCalibrationCheckpoint?
  public let stageFour: AcceptedStageFourCheckpoint?

  public init(
    checkpointID: UUID = UUID(),
    semanticIdentity: LearningPathSemanticIdentity,
    penInteraction: AcceptedPenInteractionCheckpoint? = nil,
    machineArtifacts: AcceptedMachineArtifactCheckpoint? = nil,
    machineCamera: AcceptedMachineCameraCheckpoint? = nil,
    tipCalibration: AcceptedTipCalibrationCheckpoint? = nil,
    stageFour: AcceptedStageFourCheckpoint? = nil
  ) throws {
    schemaVersion = Self.schemaVersion
    algorithmRevision = Self.algorithmRevision
    self.checkpointID = checkpointID
    self.semanticIdentity = semanticIdentity
    self.penInteraction = penInteraction
    self.machineArtifacts = machineArtifacts
    self.machineCamera = machineCamera
    self.tipCalibration = tipCalibration
    self.stageFour = stageFour
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == Self.schemaVersion else {
      throw AcceptedLearningPathCheckpointError.unsupportedSchema(schemaVersion)
    }
    guard algorithmRevision == Self.algorithmRevision else {
      throw AcceptedLearningPathCheckpointError.unsupportedAlgorithm(algorithmRevision)
    }
    if let penInteraction {
      _ = try AcceptedPenInteractionCheckpoint(
        revision: penInteraction.revision,
        acceptedSequence: penInteraction.acceptedSequence,
        evidence: penInteraction.evidence
      )
    }
    if let machineArtifacts { try machineArtifacts.validate() }
    if let machineCamera {
      _ = try AcceptedMachineCameraCheckpoint(
        revision: machineCamera.revision,
        registration: machineCamera.registration
      )
      guard machineCamera.registration.machineGeometry == semanticIdentity.machineGeometry,
        machineCamera.registration.coordinateRevision == machineArtifacts?.coordinateRevision
      else {
        throw AcceptedLearningPathCheckpointError.invalidMachineCameraRegistration
      }
    }
    if let tipCalibration {
      try tipCalibration.validate()
      let applicability = tipCalibration.registration.applicability
      guard applicability.machineGeometry == semanticIdentity.machineGeometry,
        applicability.toolAssembly == semanticIdentity.toolAssembly,
        applicability.penContactProfile == semanticIdentity.penContactProfile,
        applicability.paperContactPlane == semanticIdentity.paperContactPlane
      else { throw AcceptedLearningPathCheckpointError.invalidTipCalibration }
      if let machineCamera {
        guard tipCalibration.registration.machineCameraRegistrationRevisionID
          == machineCamera.revision.id
        else { throw AcceptedLearningPathCheckpointError.invalidTipCalibration }
      }
    }
    if let stageFour {
      guard stageFour.paperContactPlane == semanticIdentity.paperContactPlane,
        let tipCalibration,
        stageFour.tipCalibrationRevisionID
          == tipCalibration.registration.acceptedRevisionID
      else { throw AcceptedLearningPathCheckpointError.invalidStageFourReference }
    }
  }
}

public enum AcceptedLearningPathCheckpointLoadResult: Sendable {
  case absent
  case loaded(AcceptedLearningPathCheckpoint)
  case rejected(String)
}

public struct AcceptedLearningPathCheckpointStore: Sendable {
  private struct Envelope: Codable {
    let schemaVersion: UInt16
    let payload: Data
    let payloadSHA256: String
  }

  public let fileURL: URL

  public init(fileURL: URL) {
    self.fileURL = fileURL
  }

  public func load() -> AcceptedLearningPathCheckpointLoadResult {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return .absent }
    do {
      let envelope = try JSONDecoder().decode(
        Envelope.self,
        from: Data(contentsOf: fileURL)
      )
      guard envelope.schemaVersion == AcceptedLearningPathCheckpoint.schemaVersion else {
        return .rejected(
          "Unsupported Learning Path checkpoint envelope schema \(envelope.schemaVersion)."
        )
      }
      guard Self.sha256(envelope.payload) == envelope.payloadSHA256 else {
        return .rejected("Learning Path checkpoint integrity verification failed.")
      }
      let checkpoint = try JSONDecoder().decode(
        AcceptedLearningPathCheckpoint.self,
        from: envelope.payload
      )
      try checkpoint.validate()
      return .loaded(checkpoint)
    } catch {
      return .rejected("Learning Path checkpoint could not be decoded: \(error)")
    }
  }

  public func save(_ checkpoint: AcceptedLearningPathCheckpoint) throws {
    try checkpoint.validate()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let payload = try encoder.encode(checkpoint)
    let envelope = Envelope(
      schemaVersion: AcceptedLearningPathCheckpoint.schemaVersion,
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
