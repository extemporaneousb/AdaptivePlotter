import CryptoKit
import Foundation
import PlotterModel

/// C2 identity crosses the App boundary without importing its candidate archive.
public struct DrawingRunCandidateReference: Codable, Hashable, Sendable {
  public let candidateID: String
  public let contentHash: PlotterModel.Digest
  public let programContentHash: PlotterModel.Digest
  public let sourceProgram: DrawingProgram
  public init(candidateID: String, contentHash: PlotterModel.Digest, sourceProgram: DrawingProgram) {
    self.candidateID = candidateID
    self.contentHash = contentHash
    self.programContentHash = sourceProgram.contentHash
    self.sourceProgram = sourceProgram
  }

  /// The one known compositor preserves all artwork stroke identities and maps
  /// every point with the same orientation-preserving similarity transform.
  public func matches(_ executionProgram: DrawingProgram) -> Bool {
    guard candidateID == contentHash.description,
      sourceProgram.contentHash == programContentHash else { return false }
    if executionProgram == sourceProgram { return true }
    guard executionProgram.source.kind == sourceProgram.source.kind,
      executionProgram.source.sourceIdentifier
        == sourceProgram.source.sourceIdentifier + "|draw-border-v1|artwork=\(programContentHash)",
      executionProgram.strokes.count == sourceProgram.strokes.count + 1 else { return false }
    let pairs = zip(sourceProgram.strokes, executionProgram.strokes)
    var sourcePoints: [Point2<FieldSpace>] = []
    var targetPoints: [Point2<FieldSpace>] = []
    for (source, target) in pairs {
      guard source.id == target.id, source.style == target.style,
        source.semanticRole == target.semanticRole,
        source.path.points.count == target.path.points.count else { return false }
      sourcePoints += source.path.points; targetPoints += target.path.points
    }
    guard let origin = sourcePoints.first, let targetOrigin = targetPoints.first,
      let anchor = sourcePoints.indices.first(where: {
        hypot(sourcePoints[$0].x - origin.x, sourcePoints[$0].y - origin.y) > 1e-9
      }) else { return false }
    let dx = sourcePoints[anchor].x - origin.x, dy = sourcePoints[anchor].y - origin.y
    let tx = targetPoints[anchor].x - targetOrigin.x, ty = targetPoints[anchor].y - targetOrigin.y
    let lengthSquared = dx * dx + dy * dy
    let a = (dx * tx + dy * ty) / lengthSquared
    let b = (dx * ty - dy * tx) / lengthSquared
    guard a.isFinite, b.isFinite, hypot(a, b) > 0 else { return false }
    for index in sourcePoints.indices {
      let x = sourcePoints[index].x - origin.x, y = sourcePoints[index].y - origin.y
      guard hypot(targetOrigin.x + a * x - b * y - targetPoints[index].x,
        targetOrigin.y + b * x + a * y - targetPoints[index].y) <= 1e-7 else { return false }
    }
    return true
  }

}

/// Captured attempt conditions. Selected material applicability is historical
/// provenance and may differ from the actual conditions alongside it.
public struct DrawingRunAttemptContext: Codable, Hashable, Sendable {
  public let program: DrawingProgram
  public let registration: TipCameraRegistration
  public let materialProfile: DrawingMaterialProfileRevision?
  public let materialApplicability: DrawingMaterialApplicability?
  public let paperStock: String?
  public let drawingFeedMMPerMinute: Double
  public let penActuationProfile: PenActuationProfile
  public let paper: PaperRevisionContext
  public let candidate: DrawingRunCandidateReference?

  public init(program: DrawingProgram, registration: TipCameraRegistration,
    materialProfile: DrawingMaterialProfileRevision? = nil,
    materialApplicability: DrawingMaterialApplicability? = nil,
    paperStock: String? = nil, drawingFeedMMPerMinute: Double, penActuationProfile: PenActuationProfile,
    paper: PaperRevisionContext, candidate: DrawingRunCandidateReference? = nil) throws {
    self.program = program; self.registration = registration
    self.materialProfile = materialProfile; self.materialApplicability = materialApplicability
    self.paperStock = paperStock
    self.drawingFeedMMPerMinute = drawingFeedMMPerMinute
    self.penActuationProfile = penActuationProfile; self.paper = paper; self.candidate = candidate
    try validate()
  }

  public static func materialContextHash(profile: DrawingMaterialProfileRevision,
    applicability: DrawingMaterialApplicability?) throws -> PlotterModel.Digest {
    struct Basis: Encodable {
      let profile: DrawingMaterialProfileRevision
      let applicability: DrawingMaterialApplicability?
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return try PlotterModel.Digest(bytes: Array(SHA256.hash(data:
      encoder.encode(Basis(profile: profile, applicability: applicability)))))
  }

  func validate() throws {
    guard drawingFeedMMPerMinute.isFinite, drawingFeedMMPerMinute > 0,
      (0...1000).contains(penActuationProfile.raisedSpindleValue),
      (0...1000).contains(penActuationProfile.loweredSpindleValue),
      penActuationProfile.settleSeconds.isFinite, penActuationProfile.settleSeconds >= 0,
      paper.contactPlane == registration.applicability.paperContactPlane,
      candidate == nil || candidate?.matches(program) == true,
      materialApplicability == nil || materialProfile != nil else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    try materialProfile?.validate()
    if let paperStock, paperStock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
    if let selected = materialApplicability {
      guard !selected.paperStock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        selected.registrationSHA256.utf8.count == 64,
        selected.registrationSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
        selected.drawingFeedMMPerMinute.isFinite, selected.drawingFeedMMPerMinute > 0,
        (0...1000).contains(selected.penActuationProfile.raisedSpindleValue),
        (0...1000).contains(selected.penActuationProfile.loweredSpindleValue),
        selected.penActuationProfile.settleSeconds.isFinite,
        selected.penActuationProfile.settleSeconds >= 0 else {
        throw DrawingRunEvidenceError.invalidAttemptContext
      }
    }
  }
}

/// Durable preparation only; it is never an instruction to restore or replay motion.
public struct DrawingRunIntent: Codable, Hashable, Sendable {
  public let runID: RunID
  public let requestID: UUID
  public let plan: ExecutionPlanRevision
  public let placementID: UUID
  public let role: BorderValidationEvidenceRole
  public let context: DrawingRunAttemptContext
  public let observationPlan: DrawingRunObservationPlan?
  public let recordedAt: RuntimeTimestamp

  public init(runID: RunID, requestID: UUID, plan: ExecutionPlanRevision,
    placementID: UUID, role: BorderValidationEvidenceRole, context: DrawingRunAttemptContext,
    observationPlan: DrawingRunObservationPlan? = nil, recordedAt: RuntimeTimestamp) throws {
    self.runID = runID; self.requestID = requestID; self.plan = plan
    self.placementID = placementID; self.role = role; self.context = context
    self.observationPlan = observationPlan; self.recordedAt = recordedAt
    try validate()
  }

  func validate() throws {
    try context.validate()
    if let expected = plan.provenance.materialContextHash {
      guard let profile = context.materialProfile,
        try DrawingRunAttemptContext.materialContextHash(profile: profile,
          applicability: context.materialApplicability) == expected else {
        throw DrawingRunEvidenceError.invalidAttemptContext
      }
    }
    if let observationPlan {
      try observationPlan.validate(executionPlan: plan)
      guard observationPlan.executionPlanRevisionID == plan.revisionID,
        (1...3).contains(observationPlan.poses.count),
        Set(observationPlan.poses.map(\.id)).count == observationPlan.poses.count,
        observationPlan.requiredPenState == .up,
        observationPlan.poses.allSatisfy({ observationPlan.acceptedMovementBounds.contains($0.position.point) }) else {
        throw DrawingRunEvidenceError.invalidAttemptContext
      }
    }
    let registrationHash = try context.registration.drawingEvidenceContentHash()
    guard plan.sourceProgramID == context.program.id,
      plan.sourceProgramContentHash == context.program.contentHash,
      plan.provenance.modelRevisionID.rawValue == context.registration.acceptedRevisionID.rawValue,
      plan.provenance.modelContentHash == registrationHash,
      plan.provenance.registrationRevisionID.rawValue == context.registration.acceptedRevisionID.rawValue,
      plan.provenance.registrationContentHash.description
        == (try DrawingMaterialApplicability.registrationHash(context.registration)) else {
      throw DrawingRunEvidenceError.invalidAttemptContext
    }
  }
}

public enum DrawingRunInterruptionClassification: String, Codable, Hashable, Sendable {
  /// No ink-dispatch marker was persisted. Pen-up preparation may have moved.
  case preparedWithoutInkDispatch
  /// Dispatch may or may not have reached the controller. Do not infer a clean sheet.
  case possibleInk
}

public struct DrawingRunAttemptState: Codable, Hashable, Sendable {
  public let intent: DrawingRunIntent
  public let baselines: [DrawingRunMediaReference]
  public let inkDispatchPossible: Bool
  public var interruptionClassification: DrawingRunInterruptionClassification {
    inkDispatchPossible ? .possibleInk : .preparedWithoutInkDispatch
  }
  public init(intent: DrawingRunIntent, baselines: [DrawingRunMediaReference] = [],
    inkDispatchPossible: Bool = false) {
    self.intent = intent; self.baselines = baselines; self.inkDispatchPossible = inkDispatchPossible
  }
}

public struct DrawingRunAttemptEvidence: Codable, Hashable, Sendable {
  public let intent: DrawingRunIntent
  public let baselines: [DrawingRunMediaReference]
  public let terminalFrames: [DrawingRunMediaReference]
  public let mediaCoverage: DrawingRunMediaCoverage?
  public let missingCoverageReason: String?
  public init(intent: DrawingRunIntent, baselines: [DrawingRunMediaReference],
    terminalFrames: [DrawingRunMediaReference], mediaCoverage: DrawingRunMediaCoverage? = nil,
    missingCoverageReason: String? = nil) {
    self.intent = intent; self.baselines = baselines; self.terminalFrames = terminalFrames
    self.mediaCoverage = mediaCoverage; self.missingCoverageReason = missingCoverageReason
  }
}
