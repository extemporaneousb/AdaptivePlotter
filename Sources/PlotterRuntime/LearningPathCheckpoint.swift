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

/// The complete accepted result of Identify Pen Cap. Exact-frame provenance is
/// retained with the learned color so a restart cannot silently promote an
/// unproven color preference into Learning authority.
public struct AcceptedPenCapAppearance: Codable, Hashable, Sendable {
  public static let algorithmRevision = "pen-cap-click-9x9-median-v1"
  public static let minimumUsableSampleCount = 9

  public let color: PenCapColor
  public let frameID: FrameID
  public let frameSHA256: String
  public let source: FrameSourceIdentity
  public let cameraConfigurationID: CameraConfigurationID
  public let width: Int
  public let height: Int
  public let pixelFormat: FramePixelFormat
  public let clickPoint: Point2<CameraPixelSpace>
  public let usableSampleCount: Int
  public let totalSampleCount: Int
  public let algorithmRevision: String

  public init(
    color: PenCapColor,
    frameID: FrameID,
    frameSHA256: String,
    source: FrameSourceIdentity,
    cameraConfigurationID: CameraConfigurationID,
    width: Int,
    height: Int,
    pixelFormat: FramePixelFormat,
    clickPoint: Point2<CameraPixelSpace>,
    usableSampleCount: Int,
    totalSampleCount: Int,
    algorithmRevision: String
  ) throws {
    guard case .live = source,
      !frameID.rawValue.isEmpty,
      Self.isSHA256(frameSHA256),
      width > 0,
      height > 0,
      pixelFormat == .rgba8 || pixelFormat == .bgra8,
      clickPoint.x >= 0,
      clickPoint.x < Double(width),
      clickPoint.y >= 0,
      clickPoint.y < Double(height),
      usableSampleCount >= Self.minimumUsableSampleCount,
      totalSampleCount >= usableSampleCount,
      algorithmRevision == Self.algorithmRevision,
      Self.isUsable(color)
    else { throw AcceptedLearningPathCheckpointError.invalidPenCapAppearance }
    self.color = color
    self.frameID = frameID
    self.frameSHA256 = frameSHA256.lowercased()
    self.source = source
    self.cameraConfigurationID = cameraConfigurationID
    self.width = width
    self.height = height
    self.pixelFormat = pixelFormat
    self.clickPoint = clickPoint
    self.usableSampleCount = usableSampleCount
    self.totalSampleCount = totalSampleCount
    self.algorithmRevision = algorithmRevision
  }

  public func matches(_ frame: DisplayedFrame) -> Bool {
    frameID == frame.frame.id
      && frameSHA256 == frame.frame.contentSHA256
      && source == frame.source
      && cameraConfigurationID == frame.frame.cameraConfigurationID
      && width == frame.frame.width
      && height == frame.frame.height
      && pixelFormat == frame.frame.pixelFormat
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
  }

  private static func isUsable(_ color: PenCapColor) -> Bool {
    let channels = [Double(color.red), Double(color.green), Double(color.blue)].map { $0 / 255 }
    let maximum = channels.max() ?? 0
    let minimum = channels.min() ?? 0
    let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
    return saturation >= 0.20 && maximum >= 0.10 && maximum <= 0.98
  }
}

/// The one bounded camera image retained with accepted Learning. This is
/// presentation and comparison evidence only: it never proves physical
/// applicability, restores authority, or authorizes motion.
public struct AcceptedLearningReferenceFrame: Codable, Hashable, Sendable {
  public static let maximumByteCount = 16 * 1_024 * 1_024

  public let opticalConfiguration: CameraOpticalConfigurationIdentity
  public let frame: StampedFrame

  public init(
    opticalConfiguration: CameraOpticalConfigurationIdentity,
    frame: StampedFrame
  ) throws {
    guard opticalConfiguration.width == frame.width,
      opticalConfiguration.height == frame.height,
      opticalConfiguration.pixelFormat == frame.pixelFormat,
      frame.bytes.count == frame.rowBytes * frame.height,
      frame.bytes.count <= Self.maximumByteCount
    else { throw AcceptedLearningPathCheckpointError.invalidReferenceFrame }
    self.opticalConfiguration = opticalConfiguration
    self.frame = frame
  }

  public func compare(
    with current: DisplayedFrame,
    opticalConfiguration currentOpticalConfiguration: CameraOpticalConfigurationIdentity,
    searchRadiusPixels: Int = 4
  ) -> LearningReferenceFrameComparison {
    guard searchRadiusPixels >= 0 else { return .unavailable(.invalidSearchRadius) }
    guard current.source == opticalConfiguration.source else {
      return .unavailable(.sourceMismatch)
    }
    guard currentOpticalConfiguration == opticalConfiguration else {
      return .unavailable(.opticalConfigurationMismatch)
    }
    guard current.frame.width == frame.width, current.frame.height == frame.height else {
      return .unavailable(.dimensionMismatch)
    }
    guard current.frame.pixelFormat == frame.pixelFormat else {
      return .unavailable(.pixelFormatMismatch)
    }
    // This report is advisory and shown during startup. Bound each candidate
    // residual to roughly 65k spatial samples so a full-resolution camera does
    // not turn a 9x9 alignment search into repeated multi-second UI work.
    let pixelCount = frame.width * frame.height
    let sampleStride = max(
      1,
      Int(ceil(sqrt(Double(pixelCount) / 65_536.0)))
    )
    return .compared(
      VisionWorker.bestIntegerAlignment(
        frame,
        current.frame,
        excluding: PixelRect(x: 0, y: 0, width: 0, height: 0),
        searchRadius: searchRadiusPixels,
        sampleStride: sampleStride
      )
    )
  }
}

public enum LearningReferenceFrameComparisonUnavailable: String, Hashable, Sendable {
  case invalidSearchRadius
  case sourceMismatch
  case opticalConfigurationMismatch
  case dimensionMismatch
  case pixelFormatMismatch
}

/// An advisory numeric report. Deliberately no pass/fail or sameness threshold
/// is encoded here; accepting saved Learning remains an operator decision.
public enum LearningReferenceFrameComparison: Hashable, Sendable {
  case compared(IntegerFrameAlignment)
  case unavailable(LearningReferenceFrameComparisonUnavailable)
}

public enum AcceptedLearningPathCheckpointError: Error, Equatable, Sendable {
  case unsupportedSchema(UInt16)
  case unsupportedAlgorithm(String)
  case invalidPenInteraction
  case invalidMachineCameraRegistration
  case invalidTipCalibration
  case invalidStageFourReference
  case invalidPenCapAppearance
  case invalidReferenceFrame
}

/// One durable accepted prefix of the LIVE Learning Path. Operational owners,
/// Motion authorization, current Pen pose, pending commands, live camera
/// streams, and controller-pose trust are deliberately excluded. At most one
/// bounded reference image may accompany the accepted values for preview.
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
  public let penCapAppearance: AcceptedPenCapAppearance?
  public let referenceFrame: AcceptedLearningReferenceFrame?

  public init(
    checkpointID: UUID = UUID(),
    semanticIdentity: LearningPathSemanticIdentity,
    penInteraction: AcceptedPenInteractionCheckpoint? = nil,
    machineArtifacts: AcceptedMachineArtifactCheckpoint? = nil,
    machineCamera: AcceptedMachineCameraCheckpoint? = nil,
    tipCalibration: AcceptedTipCalibrationCheckpoint? = nil,
    stageFour: AcceptedStageFourCheckpoint? = nil,
    penCapAppearance: AcceptedPenCapAppearance? = nil,
    referenceFrame: AcceptedLearningReferenceFrame? = nil
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
    self.penCapAppearance = penCapAppearance
    self.referenceFrame = referenceFrame
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
        guard
          tipCalibration.registration.machineCameraRegistrationRevisionID
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
    if let penCapAppearance {
      _ = try AcceptedPenCapAppearance(
        color: penCapAppearance.color,
        frameID: penCapAppearance.frameID,
        frameSHA256: penCapAppearance.frameSHA256,
        source: penCapAppearance.source,
        cameraConfigurationID: penCapAppearance.cameraConfigurationID,
        width: penCapAppearance.width,
        height: penCapAppearance.height,
        pixelFormat: penCapAppearance.pixelFormat,
        clickPoint: penCapAppearance.clickPoint,
        usableSampleCount: penCapAppearance.usableSampleCount,
        totalSampleCount: penCapAppearance.totalSampleCount,
        algorithmRevision: penCapAppearance.algorithmRevision
      )
      if let machineCamera {
        guard penCapAppearance.source == machineCamera.registration.source,
          penCapAppearance.width == machineCamera.registration.opticalConfiguration.width,
          penCapAppearance.height == machineCamera.registration.opticalConfiguration.height,
          penCapAppearance.pixelFormat
            == machineCamera.registration.opticalConfiguration.pixelFormat
        else { throw AcceptedLearningPathCheckpointError.invalidPenCapAppearance }
      }
    }
    if let referenceFrame {
      _ = try AcceptedLearningReferenceFrame(
        opticalConfiguration: referenceFrame.opticalConfiguration,
        frame: referenceFrame.frame
      )
      guard
        referenceFrame.opticalConfiguration.mountRevision
          == semanticIdentity.cameraMountRevision,
        referenceFrame.opticalConfiguration.reframingRevision
          == semanticIdentity.cameraReframingRevision
      else { throw AcceptedLearningPathCheckpointError.invalidReferenceFrame }
      if let machineCamera {
        guard
          referenceFrame.opticalConfiguration
            == machineCamera.registration.opticalConfiguration
        else { throw AcceptedLearningPathCheckpointError.invalidReferenceFrame }
      }
      if let tipCalibration {
        guard
          referenceFrame.opticalConfiguration
            == tipCalibration.registration.applicability.opticalConfiguration
        else { throw AcceptedLearningPathCheckpointError.invalidReferenceFrame }
      }
      if let penCapAppearance {
        guard penCapAppearance.source == referenceFrame.opticalConfiguration.source,
          penCapAppearance.width == referenceFrame.opticalConfiguration.width,
          penCapAppearance.height == referenceFrame.opticalConfiguration.height,
          penCapAppearance.pixelFormat == referenceFrame.opticalConfiguration.pixelFormat
        else { throw AcceptedLearningPathCheckpointError.invalidReferenceFrame }
      }
    }
  }

  /// Reconstructs the exact saved current dependency index into a local value.
  /// The caller can therefore assign one complete graph after explicit
  /// operator acceptance instead of incrementally mutating application state.
  /// No artifact payload or operational authority is applied by this method.
  public func restoredLearningGraph() throws -> LearningDependencyGraph {
    try validate()
    var pending: [LearningArtifactRevision] = []
    if let penInteraction {
      pending.append(Self.restorationCandidate(penInteraction.revision))
    }
    if let machineArtifacts {
      pending.append(contentsOf: machineArtifacts.acceptedRevisions.map(Self.restorationCandidate))
    }
    if let machineCamera {
      pending.append(Self.restorationCandidate(machineCamera.revision))
    }
    if let tipCalibration {
      pending.append(contentsOf: try tipCalibration.restoredGraphRevisions())
    }

    var graph = LearningDependencyGraph()
    while !pending.isEmpty {
      if let index = pending.firstIndex(where: { revision in
        revision.consumedRevisionIDs.allSatisfy {
          graph.revision(id: $0)?.state == .current
        }
      }) {
        _ = try graph.commitReplacement(pending.remove(at: index))
      } else {
        // Have the canonical graph report the precise missing dependency or
        // invalid semantic shape without partially exposing the local value.
        _ = try graph.commitReplacement(pending[0])
      }
    }
    return graph
  }

  private static func restorationCandidate(
    _ revision: LearningArtifactRevision
  ) -> LearningArtifactRevision {
    LearningArtifactRevision(
      id: revision.id,
      kind: revision.kind,
      attemptID: revision.attemptID,
      disposition: revision.disposition,
      consumedRevisionIDs: revision.consumedRevisionIDs
    )
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
