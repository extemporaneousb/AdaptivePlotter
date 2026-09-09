import Foundation
import PlotterModel

public enum DrawingRunEvidenceError: Error, Equatable, Sendable {
  case emptyValue(String)
  case invalidHash
  case planIdentityMismatch
  case missingExecutionPlanGeometry
  case invalidFrontier
  case invalidFramePair
  case invalidResidual
  case invalidObservation
  case incompatibleDisposition
  case missingComparisonEvidence
  case unsupportedSchema(UInt16)
}

public struct DrawingProgramEvidenceReference: Codable, Hashable, Sendable {
  public let programID: ProgramID
  public let contentHash: Digest
  /// Retains generator/capture provenance without storing the source photo.
  /// Older hash-only references decode with no source.
  public let source: DrawingSourceProvenance?

  public init(programID: ProgramID, contentHash: Digest, source: DrawingSourceProvenance? = nil) {
    self.programID = programID
    self.contentHash = contentHash
    self.source = source
  }

  public init(program: DrawingProgram) {
    self.init(programID: program.id, contentHash: program.contentHash, source: program.source)
  }
}

/// Placement does not own execution identity. The caller assigns a stable ID
/// when placement is accepted and the canonical content hash pins its value.
public struct DrawingPlacementEvidenceReference: Codable, Hashable, Sendable {
  public let placementID: UUID
  public let contentHash: Digest

  public init(placementID: UUID, contentHash: Digest) {
    self.placementID = placementID
    self.contentHash = contentHash
  }

  public init(placementID: UUID, placement: DrawingPlacement) throws {
    self.init(placementID: placementID, contentHash: try canonicalDigest(of: placement))
  }
}

public struct DrawingExecutionPlanEvidenceReference: Codable, Hashable, Sendable {
  public let revisionID: ExecutionPlanRevisionID
  public let contentHash: Digest
  /// Present for every newly recorded run. Nil identifies a decoded legacy
  /// record whose former schema persisted only the hash reference.
  public let executionPlan: ExecutionPlanRevision?

  public init(
    revisionID: ExecutionPlanRevisionID,
    contentHash: Digest
  ) throws {
    guard revisionID.rawValue == contentHash else {
      throw DrawingRunEvidenceError.planIdentityMismatch
    }
    self.revisionID = revisionID
    self.contentHash = contentHash
    executionPlan = nil
  }

  public init(plan: ExecutionPlanRevision) throws {
    guard plan.revisionID.rawValue == plan.contentHash else {
      throw DrawingRunEvidenceError.planIdentityMismatch
    }
    revisionID = plan.revisionID
    contentHash = plan.contentHash
    executionPlan = plan
  }

  public var hasReconstructableGeometry: Bool { executionPlan != nil }

  private enum CodingKeys: String, CodingKey { case revisionID, contentHash, executionPlan }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let revisionID = try values.decode(ExecutionPlanRevisionID.self, forKey: .revisionID)
    let contentHash = try values.decode(Digest.self, forKey: .contentHash)
    guard revisionID.rawValue == contentHash else {
      throw DrawingRunEvidenceError.planIdentityMismatch
    }
    let executionPlan = try values.decodeIfPresent(
      ExecutionPlanRevision.self,
      forKey: .executionPlan
    )
    guard
      executionPlan == nil
        || (executionPlan?.revisionID == revisionID && executionPlan?.contentHash == contentHash)
    else { throw DrawingRunEvidenceError.planIdentityMismatch }
    self.revisionID = revisionID
    self.contentHash = contentHash
    self.executionPlan = executionPlan
  }
}

/// Pins both the accepted tip revision and all semantic applicability
/// identities. The hash addresses the durable registration evidence; it is not
/// an authorization to restore or promote that registration.
public struct DrawingTipCalibrationEvidenceReference: Codable, Hashable, Sendable {
  public let acceptedRevisionID: LearningArtifactRevisionID
  public let registrationEvidenceSHA256: String
  public let applicability: TipCalibrationApplicabilityContext
  public let estimatorRevision: String

  public init(
    acceptedRevisionID: LearningArtifactRevisionID,
    registrationEvidenceSHA256: String,
    applicability: TipCalibrationApplicabilityContext,
    estimatorRevision: String
  ) throws {
    guard Self.isSHA256(registrationEvidenceSHA256) else {
      throw DrawingRunEvidenceError.invalidHash
    }
    guard !estimatorRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw DrawingRunEvidenceError.emptyValue("tip estimator revision")
    }
    self.acceptedRevisionID = acceptedRevisionID
    self.registrationEvidenceSHA256 = registrationEvidenceSHA256.lowercased()
    self.applicability = applicability
    self.estimatorRevision = estimatorRevision
  }

  private enum CodingKeys: String, CodingKey {
    case acceptedRevisionID, registrationEvidenceSHA256, applicability, estimatorRevision
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      acceptedRevisionID: values.decode(
        LearningArtifactRevisionID.self,
        forKey: .acceptedRevisionID
      ),
      registrationEvidenceSHA256: values.decode(
        String.self,
        forKey: .registrationEvidenceSHA256
      ),
      applicability: values.decode(
        TipCalibrationApplicabilityContext.self,
        forKey: .applicability
      ),
      estimatorRevision: values.decode(String.self, forKey: .estimatorRevision)
    )
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
  }
}

public enum DrawingRunRequestFrontier: UInt8, Codable, CaseIterable, Hashable, Sendable {
  case created = 0
  case validated = 1
  case admitted = 2
}

/// Monotonic execution fact counts. Each downstream frontier is constrained
/// by the preceding one; an ink verification can never outrun controller
/// completion and controller completion can never outrun commands.
public struct DrawingRunExecutionFrontiers: Codable, Hashable, Sendable {
  public let plannedStrokeCount: UInt32
  public let commandedStrokeCount: UInt32
  public let controllerCompletedStrokeCount: UInt32
  public let inkVerifiedStrokeCount: UInt32

  public init(
    plannedStrokeCount: UInt32,
    commandedStrokeCount: UInt32,
    controllerCompletedStrokeCount: UInt32,
    inkVerifiedStrokeCount: UInt32
  ) throws {
    guard plannedStrokeCount > 0,
      inkVerifiedStrokeCount <= controllerCompletedStrokeCount,
      controllerCompletedStrokeCount <= commandedStrokeCount,
      commandedStrokeCount <= plannedStrokeCount
    else { throw DrawingRunEvidenceError.invalidFrontier }
    self.plannedStrokeCount = plannedStrokeCount
    self.commandedStrokeCount = commandedStrokeCount
    self.controllerCompletedStrokeCount = controllerCompletedStrokeCount
    self.inkVerifiedStrokeCount = inkVerifiedStrokeCount
  }

  private enum CodingKeys: String, CodingKey {
    case plannedStrokeCount, commandedStrokeCount, controllerCompletedStrokeCount
    case inkVerifiedStrokeCount
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      plannedStrokeCount: values.decode(UInt32.self, forKey: .plannedStrokeCount),
      commandedStrokeCount: values.decode(UInt32.self, forKey: .commandedStrokeCount),
      controllerCompletedStrokeCount: values.decode(
        UInt32.self,
        forKey: .controllerCompletedStrokeCount
      ),
      inkVerifiedStrokeCount: values.decode(UInt32.self, forKey: .inkVerifiedStrokeCount)
    )
  }
}

public enum DrawingRunExecutionDisposition: Codable, Hashable, Sendable {
  case completed
  case refused(reason: String)
  case cancelled(reason: String)
  case ambiguous(reason: String)
  case failed(reason: String)

  fileprivate var reasonIsValid: Bool {
    switch self {
    case .completed:
      true
    case .refused(let reason), .cancelled(let reason), .ambiguous(let reason),
      .failed(let reason):
      !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }
}

public struct DrawingObservationFramePair: Codable, Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let baseline: ExactFrameProvenance
  public let post: ExactFrameProvenance

  public init(
    source: FrameSourceIdentity,
    baseline: ExactFrameProvenance,
    post: ExactFrameProvenance
  ) throws {
    guard baseline.frameID != post.frameID,
      baseline.captureNanoseconds < post.captureNanoseconds,
      baseline.cameraConfigurationID == post.cameraConfigurationID,
      Self.isSHA256(baseline.frameSHA256),
      Self.isSHA256(post.frameSHA256),
      baseline.width > 0,
      baseline.height > 0,
      baseline.rowBytes >= baseline.width * baseline.pixelFormat.bytesPerPixel,
      baseline.width == post.width,
      baseline.height == post.height,
      baseline.rowBytes == post.rowBytes,
      baseline.pixelFormat == post.pixelFormat
    else { throw DrawingRunEvidenceError.invalidFramePair }
    self.source = source
    self.baseline = baseline
    self.post = post
  }

  private enum CodingKeys: String, CodingKey { case source, baseline, post }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      source: values.decode(FrameSourceIdentity.self, forKey: .source),
      baseline: values.decode(ExactFrameProvenance.self, forKey: .baseline),
      post: values.decode(ExactFrameProvenance.self, forKey: .post)
    )
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
  }
}

public struct DrawingResidualEvidence: Codable, Hashable, Sendable {
  public let correspondenceCount: UInt32
  public let rootMeanSquarePixels: Double
  public let maximumPixels: Double
  public let rootMeanSquareCrossTrackPixels: Double

  public init(
    correspondenceCount: UInt32,
    rootMeanSquarePixels: Double,
    maximumPixels: Double,
    rootMeanSquareCrossTrackPixels: Double
  ) throws {
    guard correspondenceCount > 0,
      rootMeanSquarePixels.isFinite, rootMeanSquarePixels >= 0,
      maximumPixels.isFinite, maximumPixels >= rootMeanSquarePixels,
      rootMeanSquareCrossTrackPixels.isFinite, rootMeanSquareCrossTrackPixels >= 0
    else { throw DrawingRunEvidenceError.invalidResidual }
    self.correspondenceCount = correspondenceCount
    self.rootMeanSquarePixels = rootMeanSquarePixels
    self.maximumPixels = maximumPixels
    self.rootMeanSquareCrossTrackPixels = rootMeanSquareCrossTrackPixels
  }

  private enum CodingKeys: String, CodingKey {
    case correspondenceCount, rootMeanSquarePixels, maximumPixels
    case rootMeanSquareCrossTrackPixels
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      correspondenceCount: values.decode(UInt32.self, forKey: .correspondenceCount),
      rootMeanSquarePixels: values.decode(Double.self, forKey: .rootMeanSquarePixels),
      maximumPixels: values.decode(Double.self, forKey: .maximumPixels),
      rootMeanSquareCrossTrackPixels: values.decode(
        Double.self,
        forKey: .rootMeanSquareCrossTrackPixels
      )
    )
  }
}

public struct DrawingObservedInkEvidence: Codable, Hashable, Sendable {
  public let frames: DrawingObservationFramePair
  public let intendedInk: [Polyline<CameraPixelSpace>]
  public let observedInk: [Polyline<CameraPixelSpace>]
  public let residual: DrawingResidualEvidence?
  public let algorithmRevisions: Set<AlgorithmRevisionEvidence>
  /// Extraction/association facts, independent of sampled residual geometry.
  /// Nil means this producer or a legacy archive did not record the count.
  public let detectedPixelCount: Int?
  public let ambiguousPixelCount: Int?

  public init(
    frames: DrawingObservationFramePair,
    intendedInk: [Polyline<CameraPixelSpace>],
    observedInk: [Polyline<CameraPixelSpace>],
    residual: DrawingResidualEvidence?,
    algorithmRevisions: Set<AlgorithmRevisionEvidence>,
    detectedPixelCount: Int? = nil,
    ambiguousPixelCount: Int? = nil
  ) throws {
    guard !intendedInk.isEmpty, !observedInk.isEmpty, !algorithmRevisions.isEmpty else {
      throw DrawingRunEvidenceError.invalidObservation
    }
    self.frames = frames
    self.intendedInk = intendedInk
    self.observedInk = observedInk
    self.residual = residual
    self.algorithmRevisions = algorithmRevisions
    self.detectedPixelCount = detectedPixelCount
    self.ambiguousPixelCount = ambiguousPixelCount
  }

  private enum CodingKeys: String, CodingKey {
    case frames, intendedInk, observedInk, residual, algorithmRevisions
    case detectedPixelCount, ambiguousPixelCount
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      frames: values.decode(DrawingObservationFramePair.self, forKey: .frames),
      intendedInk: values.decode(
        [Polyline<CameraPixelSpace>].self,
        forKey: .intendedInk
      ),
      observedInk: values.decode(
        [Polyline<CameraPixelSpace>].self,
        forKey: .observedInk
      ),
      residual: values.decodeIfPresent(DrawingResidualEvidence.self, forKey: .residual),
      algorithmRevisions: values.decode(
        Set<AlgorithmRevisionEvidence>.self,
        forKey: .algorithmRevisions
      ),
      detectedPixelCount: values.decodeIfPresent(Int.self, forKey: .detectedPixelCount),
      ambiguousPixelCount: values.decodeIfPresent(Int.self, forKey: .ambiguousPixelCount)
    )
  }
}

public enum DrawingObservationRejectionReason: Codable, Hashable, Sendable {
  case invalidFrameIdentity
  case observationPoseMismatch
  case computationCancelled
  case excessiveAlignment
  case excessiveBackgroundResidual
  case inkMissing
  case inkAmbiguous(candidateCount: Int)
  case correspondenceUnavailable
  case unsupportedDrawing
  case algorithmFailure(code: String)

  fileprivate var isValid: Bool {
    switch self {
    case .inkAmbiguous(let candidateCount):
      candidateCount > 0
    case .algorithmFailure(let code):
      !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    default:
      true
    }
  }
}

public struct DrawingObservationRejection: Codable, Hashable, Sendable {
  public let frames: DrawingObservationFramePair
  public let reason: DrawingObservationRejectionReason
  public let algorithmRevisions: Set<AlgorithmRevisionEvidence>
  /// Nil means extraction did not finish, or this is a legacy record.
  public let detectedPixelCount: Int?

  public var diagnosticSummary: String {
    let detail: String
    switch reason {
    case .inkMissing:
      detail = detectedPixelCount == 0
        ? "No newly darkened pixels met the ink threshold."
        : "Observer reported insufficient ink for measurement."
    case .correspondenceUnavailable:
      detail = "Detected pixels could not form a sampled path for residual measurement."
    case .inkAmbiguous(let count):
      detail = "\(count) detected pixels match multiple planned paths equally."
    case .excessiveAlignment:
      detail = "Before/after camera displacement exceeded the frame alignment range."
    case .excessiveBackgroundResidual:
      detail = "Before/after background changes exceeded the frame subtraction tolerance."
    case .invalidFrameIdentity:
      detail = "The supplied images do not match the recorded frame pair."
    case .observationPoseMismatch:
      detail = "Before/after images have different controller poses."
    case .computationCancelled:
      detail = "Observation computation was cancelled."
    case .unsupportedDrawing:
      detail = "The planned geometry cannot be observed in the requested image region."
    case .algorithmFailure(let code):
      detail = "Observer could not complete: \(code)."
    }
    let summary = "\(reason): \(detail)"
    if let detectedPixelCount {
      return "\(detectedPixelCount) newly darkened pixels detected. \(summary)"
    }
    return "\(summary) Detected pixel count unavailable."
  }

  public init(
    frames: DrawingObservationFramePair,
    reason: DrawingObservationRejectionReason,
    algorithmRevisions: Set<AlgorithmRevisionEvidence>,
    detectedPixelCount: Int? = nil
  ) throws {
    guard reason.isValid, !algorithmRevisions.isEmpty else {
      throw DrawingRunEvidenceError.invalidObservation
    }
    self.frames = frames
    self.reason = reason
    self.algorithmRevisions = algorithmRevisions
    self.detectedPixelCount = detectedPixelCount
  }

  private enum CodingKeys: String, CodingKey {
    case frames, reason, algorithmRevisions, detectedPixelCount
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      frames: values.decode(DrawingObservationFramePair.self, forKey: .frames),
      reason: values.decode(DrawingObservationRejectionReason.self, forKey: .reason),
      algorithmRevisions: values.decode(
        Set<AlgorithmRevisionEvidence>.self,
        forKey: .algorithmRevisions
      ),
      detectedPixelCount: values.decodeIfPresent(Int.self, forKey: .detectedPixelCount)
    )
  }
}

public enum DrawingObservationNotAttemptedReason: String, Codable, Hashable, Sendable {
  case requestRefused
  case executionCancelledBeforeObservation
  case executionFailedBeforeObservation
  case frameEvidenceUnavailable
  case projectionOutsideTipApplicability
}

public enum DrawingRunObservationOutcome: Codable, Hashable, Sendable {
  case observed(DrawingObservedInkEvidence)
  case rejected(DrawingObservationRejection)
  case notAttempted(DrawingObservationNotAttemptedReason)
}

/// One immutable post-run fact. It can feed a later readiness assessment, but
/// cannot itself promote a model, restore calibration, authorize execution, or
/// replay motion.
public struct DrawingRunEvidenceRecord: Codable, Hashable, Sendable {
  public static let schemaVersion: UInt16 = 3
  private static let legacyReferenceOnlySchemaVersion: UInt16 = 1
  private static let reconstructablePlanSchemaVersion: UInt16 = 2

  public let schemaVersion: UInt16
  public let recordID: DrawingEvidenceRecordID
  public let runID: RunID
  public let requestID: UUID
  public let role: BorderValidationEvidenceRole
  public let evidenceDisposition: BorderValidationEvidenceDisposition
  public let requestFrontier: DrawingRunRequestFrontier
  public let executionFrontiers: DrawingRunExecutionFrontiers
  public let executionDisposition: DrawingRunExecutionDisposition
  public let program: DrawingProgramEvidenceReference
  public let placement: DrawingPlacementEvidenceReference
  public let plan: DrawingExecutionPlanEvidenceReference
  public let planningProvenance: DrawingPlanningProvenance
  public let tipCalibration: DrawingTipCalibrationEvidenceReference
  public let paper: PaperRevisionContext
  public let observation: DrawingRunObservationOutcome
  public let recordedAt: RuntimeTimestamp

  public init(
    recordID: DrawingEvidenceRecordID = DrawingEvidenceRecordID(),
    runID: RunID,
    requestID: UUID,
    role: BorderValidationEvidenceRole,
    evidenceDisposition: BorderValidationEvidenceDisposition,
    requestFrontier: DrawingRunRequestFrontier,
    executionFrontiers: DrawingRunExecutionFrontiers,
    executionDisposition: DrawingRunExecutionDisposition,
    program: DrawingProgramEvidenceReference,
    placement: DrawingPlacementEvidenceReference,
    plan: DrawingExecutionPlanEvidenceReference,
    planningProvenance: DrawingPlanningProvenance,
    tipCalibration: DrawingTipCalibrationEvidenceReference,
    paper: PaperRevisionContext,
    observation: DrawingRunObservationOutcome,
    recordedAt: RuntimeTimestamp
  ) throws {
    try self.init(
      schemaVersion: Self.schemaVersion,
      recordID: recordID,
      runID: runID,
      requestID: requestID,
      role: role,
      evidenceDisposition: evidenceDisposition,
      requestFrontier: requestFrontier,
      executionFrontiers: executionFrontiers,
      executionDisposition: executionDisposition,
      program: program,
      placement: placement,
      plan: plan,
      planningProvenance: planningProvenance,
      tipCalibration: tipCalibration,
      paper: paper,
      observation: observation,
      recordedAt: recordedAt
    )
  }

  private init(
    schemaVersion: UInt16,
    recordID: DrawingEvidenceRecordID,
    runID: RunID,
    requestID: UUID,
    role: BorderValidationEvidenceRole,
    evidenceDisposition: BorderValidationEvidenceDisposition,
    requestFrontier: DrawingRunRequestFrontier,
    executionFrontiers: DrawingRunExecutionFrontiers,
    executionDisposition: DrawingRunExecutionDisposition,
    program: DrawingProgramEvidenceReference,
    placement: DrawingPlacementEvidenceReference,
    plan: DrawingExecutionPlanEvidenceReference,
    planningProvenance: DrawingPlanningProvenance,
    tipCalibration: DrawingTipCalibrationEvidenceReference,
    paper: PaperRevisionContext,
    observation: DrawingRunObservationOutcome,
    recordedAt: RuntimeTimestamp
  ) throws {
    guard
      schemaVersion == Self.legacyReferenceOnlySchemaVersion
        || schemaVersion == Self.reconstructablePlanSchemaVersion
        || schemaVersion == Self.schemaVersion
    else { throw DrawingRunEvidenceError.unsupportedSchema(schemaVersion) }
    if schemaVersion != Self.legacyReferenceOnlySchemaVersion,
      !plan.hasReconstructableGeometry
    {
      throw DrawingRunEvidenceError.missingExecutionPlanGeometry
    }
    if schemaVersion != Self.schemaVersion,
      evidenceDisposition == .nonAttributable
        || observation == .notAttempted(.projectionOutsideTipApplicability)
    {
      throw DrawingRunEvidenceError.unsupportedSchema(schemaVersion)
    }
    guard executionDisposition.reasonIsValid else {
      throw DrawingRunEvidenceError.emptyValue("execution disposition reason")
    }
    guard requestFrontier == .admitted || executionFrontiers.commandedStrokeCount == 0 else {
      throw DrawingRunEvidenceError.invalidFrontier
    }
    if case .completed = executionDisposition {
      guard
        executionFrontiers.controllerCompletedStrokeCount
          == executionFrontiers.plannedStrokeCount
      else { throw DrawingRunEvidenceError.incompatibleDisposition }
    }
    try Self.validateDisposition(
      evidenceDisposition,
      executionDisposition: executionDisposition,
      observation: observation
    )
    if evidenceDisposition == .attributable,
      role != .ordinaryDrawing
    {
      guard case .observed(let observed) = observation, observed.residual != nil else {
        throw DrawingRunEvidenceError.missingComparisonEvidence
      }
    }
    self.schemaVersion = schemaVersion
    self.recordID = recordID
    self.runID = runID
    self.requestID = requestID
    self.role = role
    self.evidenceDisposition = evidenceDisposition
    self.requestFrontier = requestFrontier
    self.executionFrontiers = executionFrontiers
    self.executionDisposition = executionDisposition
    self.program = program
    self.placement = placement
    self.plan = plan
    self.planningProvenance = planningProvenance
    self.tipCalibration = tipCalibration
    self.paper = paper
    self.observation = observation
    self.recordedAt = recordedAt
  }

  public var readinessReference: DrawingEvidenceReference {
    DrawingEvidenceReference(
      recordID: recordID,
      role: role,
      disposition: evidenceDisposition
    )
  }

  /// Shared retrospective/experiment evidence compatibility. Storage preserves
  /// mismatches; only interpretation as calibrated residuals uses this check.
  /// The caller computes the current immutable registration hash once per batch.
  func attributableResidualGeometry(
    using registration: TipCameraRegistration, registrationContentHash: Digest
  ) throws -> (plan: ExecutionPlanRevision, observation: DrawingObservedInkEvidence) {
    guard executionDisposition == .completed, evidenceDisposition == .attributable,
      requestFrontier == .admitted, let geometry = plan.executionPlan,
      case .observed(let observed) = observation,
      Int(executionFrontiers.plannedStrokeCount) == geometry.strokes.count,
      executionFrontiers.commandedStrokeCount == executionFrontiers.plannedStrokeCount,
      executionFrontiers.controllerCompletedStrokeCount == executionFrontiers.plannedStrokeCount,
      executionFrontiers.inkVerifiedStrokeCount == executionFrontiers.plannedStrokeCount,
      observed.intendedInk.count == geometry.strokes.count,
      observed.observedInk.count == geometry.strokes.count else {
      throw PlotterModelError.invalidValue("The archived run lacks completed attributable paths")
    }
    guard registration.acceptedRevisionID == tipCalibration.acceptedRevisionID,
      registration.applicability == tipCalibration.applicability,
      registration.estimatorRevision == tipCalibration.estimatorRevision,
      tipCalibration.registrationEvidenceSHA256 == registrationContentHash.description,
      planningProvenance.registrationContentHash == registrationContentHash,
      planningProvenance.registrationRevisionID.rawValue == registration.acceptedRevisionID.rawValue,
      paper.contactPlane == registration.applicability.paperContactPlane else {
      throw PlotterModelError.invalidValue("The archived registration differs from the current accepted calibration")
    }
    let optics = registration.applicability.opticalConfiguration
    guard observed.frames.source == optics.source,
      observed.frames.baseline.width == optics.width,
      observed.frames.baseline.height == optics.height,
      observed.frames.baseline.pixelFormat == optics.pixelFormat else {
      throw PlotterModelError.invalidValue("The observation camera source or image geometry differs from its calibration")
    }
    guard geometry.provenance == planningProvenance,
      geometry.sourceProgramID == program.programID,
      geometry.sourceProgramContentHash == program.contentHash,
      try DrawingPlacementEvidenceReference(placementID: placement.placementID,
        placement: geometry.placement) == placement else {
      throw PlotterModelError.invalidValue("The archived program, placement or planning provenance differs from its immutable plan")
    }
    for index in geometry.strokes.indices {
      guard try registration.cameraFromMachine.applying(to: geometry.strokes[index].path)
        == observed.intendedInk[index] else {
        throw PlotterModelError.invalidValue("The observation's intended path differs from its immutable plan")
      }
    }
    return (geometry, observed)
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, recordID, runID, requestID, role, evidenceDisposition
    case requestFrontier, executionFrontiers, executionDisposition, program, placement, plan
    case planningProvenance, tipCalibration, paper, observation, recordedAt
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let decodedSchema = try values.decode(UInt16.self, forKey: .schemaVersion)
    guard
      decodedSchema == Self.legacyReferenceOnlySchemaVersion
        || decodedSchema == Self.reconstructablePlanSchemaVersion
        || decodedSchema == Self.schemaVersion
    else {
      throw DrawingRunEvidenceError.unsupportedSchema(decodedSchema)
    }
    try self.init(
      schemaVersion: decodedSchema,
      recordID: values.decode(DrawingEvidenceRecordID.self, forKey: .recordID),
      runID: values.decode(RunID.self, forKey: .runID),
      requestID: values.decode(UUID.self, forKey: .requestID),
      role: values.decode(BorderValidationEvidenceRole.self, forKey: .role),
      evidenceDisposition: values.decode(
        BorderValidationEvidenceDisposition.self,
        forKey: .evidenceDisposition
      ),
      requestFrontier: values.decode(
        DrawingRunRequestFrontier.self,
        forKey: .requestFrontier
      ),
      executionFrontiers: values.decode(
        DrawingRunExecutionFrontiers.self,
        forKey: .executionFrontiers
      ),
      executionDisposition: values.decode(
        DrawingRunExecutionDisposition.self,
        forKey: .executionDisposition
      ),
      program: values.decode(DrawingProgramEvidenceReference.self, forKey: .program),
      placement: values.decode(
        DrawingPlacementEvidenceReference.self,
        forKey: .placement
      ),
      plan: values.decode(DrawingExecutionPlanEvidenceReference.self, forKey: .plan),
      planningProvenance: values.decode(
        DrawingPlanningProvenance.self,
        forKey: .planningProvenance
      ),
      tipCalibration: values.decode(
        DrawingTipCalibrationEvidenceReference.self,
        forKey: .tipCalibration
      ),
      paper: values.decode(PaperRevisionContext.self, forKey: .paper),
      observation: values.decode(DrawingRunObservationOutcome.self, forKey: .observation),
      recordedAt: values.decode(RuntimeTimestamp.self, forKey: .recordedAt)
    )
  }

  private static func validateDisposition(
    _ evidence: BorderValidationEvidenceDisposition,
    executionDisposition: DrawingRunExecutionDisposition,
    observation: DrawingRunObservationOutcome
  ) throws {
    switch evidence {
    case .attributable:
      guard case .completed = executionDisposition,
        case .observed = observation
      else { throw DrawingRunEvidenceError.incompatibleDisposition }
    case .refused:
      guard case .refused = executionDisposition,
        case .notAttempted(.requestRefused) = observation
      else { throw DrawingRunEvidenceError.incompatibleDisposition }
    case .ambiguous:
      guard case .ambiguous = executionDisposition else {
        throw DrawingRunEvidenceError.incompatibleDisposition
      }
    case .possibleInk:
      guard case .ambiguous = executionDisposition else {
        throw DrawingRunEvidenceError.incompatibleDisposition
      }
    case .visionUnclear:
      guard case .completed = executionDisposition else {
        throw DrawingRunEvidenceError.incompatibleDisposition
      }
      switch observation {
      case .rejected, .notAttempted(.frameEvidenceUnavailable):
        break
      case .observed, .notAttempted:
        throw DrawingRunEvidenceError.incompatibleDisposition
      }
    case .nonAttributable:
      guard case .completed = executionDisposition,
        case .notAttempted(.projectionOutsideTipApplicability) = observation
      else { throw DrawingRunEvidenceError.incompatibleDisposition }
    case .cancelled:
      guard case .cancelled = executionDisposition else {
        throw DrawingRunEvidenceError.incompatibleDisposition
      }
    }
  }
}
