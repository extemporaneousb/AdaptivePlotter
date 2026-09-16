import CryptoKit
import Foundation
import PlotterModel

/// A label objective is independent of why a candidate was retained.
enum PortraitLabelObjective: String, Codable, CaseIterable, Sendable {
  case screenAesthetic, physicalRealization
}

enum PortraitTrainableParameter: String, Codable, CaseIterable, Sendable {
  case contourLevels, minimumContourLength, simplificationTolerance, hatchSpacing
  case tonalStrength, smoothing, sketchThreshold, hatchAngleDegrees, headScale
  case foreheadWidth, foreheadHeight, eyeScale, lateralScale
}

struct PortraitFrozenParameter: Codable, Hashable, Sendable {
  let parameter: PortraitTrainableParameter
  let value: Double
}

struct PortraitStyleScope: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let name: String
  let revision: Int
  let objective: PortraitLabelObjective
  let allowedFamilies: [PortraitStyle]
  let activeParameters: [PortraitTrainableParameter]
  let frozenParameters: [PortraitFrozenParameter]

  static let screenSketch = Self(
    id: UUID(uuidString: "BC4D5C09-434A-4092-8762-C4DB391D463F")!, name: "My drawing style", revision: 1,
    objective: .screenAesthetic, allowedFamilies: PortraitStyle.allCases,
    activeParameters: [.contourLevels, .minimumContourLength, .simplificationTolerance,
      .hatchSpacing, .tonalStrength, .smoothing, .sketchThreshold, .hatchAngleDegrees],
    frozenParameters: [.init(parameter: .headScale, value: 1)])
}

struct PortraitPresentationContext: Codable, Hashable, Sendable {
  let rendererRevision: String
  let drawingHeightMM: Double
  let inkWidthMM: Double
  let inkWidthIsMeasured: Bool
  let materialRevision: String?
  let objective: PortraitLabelObjective
  let prompt: String
  let physicalAttemptID: UUID?
  let physicalRecordID: UUID?
  let physicalMediaSHA256s: [String]?
  /// Nil preserves the original preview contract and its historical encoding.
  let displayEvidence: PortraitDisplayEvidence?

  init(drawingHeightMM: Double = 100, inkWidthMM: Double = 0.4,
    inkWidthIsMeasured: Bool = false, materialRevision: String? = nil,
    objective: PortraitLabelObjective = .screenAesthetic,
    prompt: String = "Rate likeness and drawing quality as displayed",
    physicalAttemptID: UUID? = nil, physicalRecordID: UUID? = nil,
    physicalMediaSHA256s: [String]? = nil, displayEvidence: PortraitDisplayEvidence? = nil) throws {
    guard drawingHeightMM.isFinite, drawingHeightMM > 0,
      inkWidthMM.isFinite, inkWidthMM > 0 else { throw PortraitCandidateError.invalidPresentation }
    rendererRevision = displayEvidence == nil ? "portrait-preview-v1"
      : displayEvidence?.placement?.cameraGeometry == nil ? "portrait-plane-preview-v2"
      : "portrait-camera-preview-v3"
    self.drawingHeightMM = drawingHeightMM
    self.inkWidthMM = inkWidthMM
    self.inkWidthIsMeasured = inkWidthIsMeasured
    self.materialRevision = materialRevision
    self.objective = objective
    self.prompt = prompt
    self.physicalAttemptID = physicalAttemptID
    self.physicalRecordID = physicalRecordID
    self.physicalMediaSHA256s = physicalMediaSHA256s
    self.displayEvidence = displayEvidence
    if objective == .physicalRealization {
      guard physicalAttemptID != nil, physicalRecordID != nil,
        let hashes = physicalMediaSHA256s, !hashes.isEmpty,
        hashes.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else {
        throw PortraitCandidateError.invalidPresentation
      }
    } else if physicalAttemptID != nil || physicalRecordID != nil || physicalMediaSHA256s != nil {
      throw PortraitCandidateError.invalidPresentation
    }
    try validateDisplayEvidence()
  }

  func validateDisplayEvidence(program: DrawingProgram? = nil) throws {
    guard let evidence = displayEvidence else { return }
    try evidence.validate()
    let expectedRenderer = evidence.placement?.cameraGeometry == nil
      ? "portrait-plane-preview-v2" : "portrait-camera-preview-v3"
    guard objective == .screenAesthetic, rendererRevision == expectedRenderer,
      evidence.mode != .reference || drawingHeightMM == 100 else {
      throw PortraitCandidateError.invalidPresentation
    }
    if let program {
      guard evidence.programContentHash == program.contentHash.description else {
        throw PortraitCandidateError.invalidPresentation
      }
      if let placement = evidence.placement {
        let height = try placement.controllerEdgeLengths(for: program.fieldExtent).height
        guard height.isFinite, height > 0,
          abs(drawingHeightMM - height) <= max(1e-9, abs(height) * 1e-9) else {
          throw PortraitCandidateError.invalidPresentation
        }
      }
    }
  }
}

/// An ancestry reference does not own a parent's source, raster or vectors.
struct PortraitCandidateLineage: Codable, Hashable, Sendable {
  let parentID: String?
  let parentProgramHash: String?
  let parentRecipe: PortraitStyleRecipe?
  let ancestryGroupID: UUID
}

enum PortraitCandidateError: Error, LocalizedError {
  case missingSource, invalidPresentation, invalidRating, integrityMismatch, incompatibleScope
  var errorDescription: String? {
    switch self {
    case .missingSource: "The exact source and analyzed drawing are unavailable."
    case .invalidPresentation: "Drawing size and ink width must be positive and finite."
    case .invalidRating: "Choose a rating from 1 to 5."
    case .integrityMismatch: "The retained candidate does not match its content identity."
    case .incompatibleScope: "The rating objective does not match the selected style scope."
    }
  }
}

enum PortraitCandidateCoding {
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }
  static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}

/// The immutable transient rendering result. Only an explicit qualifying event
/// sends this same payload to durable storage. Generation alone never saves it.
struct PortraitCandidate: Identifiable, Codable, Sendable {
  static let schemaVersion = 1
  let id: String
  let sourceData: Data
  let sourceSHA256: String
  let sourcePixelExtent: PortraitSourceCropExtent?
  let raster: PortraitRaster
  let rasterSHA256: String
  let recipe: PortraitStyleRecipe
  let recipeSHA256: String
  let program: DrawingProgram
  let photoID: UUID
  let captureSessionID: UUID
  let createdAt: Date
  let lineage: PortraitCandidateLineage
  let producerRevision: String
  let checkpointID: String?
  let pose: PortraitPose?
  let proposal: PortraitProposalMetadata?
  let warpManifest: PortraitHeadWarpManifest?

  init(sourceData: Data, sourcePixelExtent: PortraitSourceCropExtent?, raster: PortraitRaster,
    recipe: PortraitStyleRecipe, program: DrawingProgram, photoID: UUID,
    captureSessionID: UUID, createdAt: Date = Date(), lineage: PortraitCandidateLineage? = nil,
    checkpointID: String? = nil, pose: PortraitPose? = nil,
    proposal: PortraitProposalMetadata? = nil, warpManifest: PortraitHeadWarpManifest? = nil) throws {
    guard !sourceData.isEmpty else { throw PortraitCandidateError.missingSource }
    let encoder = PortraitCandidateCoding.encoder()
    self.sourceData = sourceData
    sourceSHA256 = PortraitCandidateCoding.digest(sourceData)
    self.sourcePixelExtent = sourcePixelExtent
    self.raster = raster
    rasterSHA256 = PortraitCandidateCoding.digest(try encoder.encode(raster))
    self.recipe = recipe
    recipeSHA256 = PortraitCandidateCoding.digest(try encoder.encode(recipe))
    self.program = program
    self.photoID = photoID
    self.captureSessionID = captureSessionID
    self.createdAt = createdAt
    self.lineage = lineage ?? PortraitCandidateLineage(parentID: nil, parentProgramHash: nil,
      parentRecipe: nil, ancestryGroupID: captureSessionID)
    producerRevision = warpManifest == nil ? "portrait-v3" : "portrait-v4"
    self.warpManifest = warpManifest
    if let warpManifest {
      guard let parameters = recipe.vectorOptions.semanticHead,
        warpManifest == PortraitHeadTransform(raster: raster, parameters: parameters.bounded).manifest,
        program.source.sourceIdentifier.hasPrefix("portrait-v4|"),
        program.source.sourceIdentifier.split(separator: "|").contains(Substring("headWarp=" + PortraitCandidateCoding.digest(try encoder.encode(warpManifest))))
      else { throw PortraitCandidateError.integrityMismatch }
    } else if recipe.vectorOptions.semanticHead != nil { throw PortraitCandidateError.integrityMismatch }
    self.checkpointID = checkpointID
    self.pose = pose
    self.proposal = proposal
    // Source/analysis/recipe/program define a candidate. Session/photo UUIDs and
    // time are provenance, not artificial duplicates of an identical drawing.
    let extentHash = PortraitCandidateCoding.digest(try encoder.encode(sourcePixelExtent))
    var identityParts = ["portrait-candidate-v1", sourceSHA256, extentHash, rasterSHA256, recipeSHA256,
      program.contentHash.description, checkpointID ?? "prior",
      self.lineage.parentID ?? "root"]
    // Optional additions preserve existing DS-02 IDs when absent.
    if let pose { identityParts.append("pose=\(pose.rawValue)") }
    if let proposal { identityParts.append(PortraitCandidateCoding.digest(try encoder.encode(proposal))) }
    if let warpManifest { identityParts.append(PortraitCandidateCoding.digest(try encoder.encode(warpManifest))) }
    id = PortraitCandidateCoding.digest(Data(identityParts.joined(separator: "|").utf8))
  }

  /// Legacy DS-02 programs already own an exact pose token in producer
  /// provenance. Decode only that known format; missing/ambiguous pose stays nil.
  var renderPose: PortraitPose? {
    if let pose { return pose }
    guard program.source.kind == "portrait",
      program.source.sourceIdentifier.hasPrefix("portrait-v3|") else { return nil }
    let tokens = program.source.sourceIdentifier.split(separator: "|").filter { $0.hasPrefix("pose=") }
    guard tokens.count == 1, let token = tokens.first else { return nil }
    return PortraitPose(rawValue: String(token.dropFirst(5)))
  }

  func validateIntegrity() throws {
    let rebuilt = try Self(sourceData: sourceData, sourcePixelExtent: sourcePixelExtent,
      raster: raster, recipe: recipe, program: program, photoID: photoID,
      captureSessionID: captureSessionID, createdAt: createdAt, lineage: lineage, checkpointID: checkpointID,
      pose: pose, proposal: proposal, warpManifest: warpManifest)
    guard rebuilt.id == id, rebuilt.sourceSHA256 == sourceSHA256,
      rebuilt.rasterSHA256 == rasterSHA256, rebuilt.recipeSHA256 == recipeSHA256,
      producerRevision == rebuilt.producerRevision else { throw PortraitCandidateError.integrityMismatch }
  }
}

enum PortraitRetentionReason: Codable, Hashable, Sendable {
  case shortlisted
  case rated(labelRevisionID: UUID)
  case projectionAccepted(acceptanceID: UUID)
  case physicalAttempt(attemptID: UUID)
}

struct PortraitRetentionEvent: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let reason: PortraitRetentionReason
  let createdAt: Date
  init(reason: PortraitRetentionReason, id: UUID = UUID(), createdAt: Date = Date()) {
    self.id = id; self.reason = reason; self.createdAt = createdAt
  }
}

struct PortraitLabelRevision: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let previousRevisionID: UUID?
  let candidateID: String
  let programContentHash: String
  let rating: Int
  let createdAt: Date
  let scope: PortraitStyleScope
  let presentation: PortraitPresentationContext

  init(candidate: PortraitCandidate, rating: Int, scope: PortraitStyleScope,
    presentation: PortraitPresentationContext, previousRevisionID: UUID? = nil,
    id: UUID = UUID(), createdAt: Date = Date()) throws {
    guard (1...5).contains(rating) else { throw PortraitCandidateError.invalidRating }
    guard scope.objective == presentation.objective else { throw PortraitCandidateError.incompatibleScope }
    try presentation.validateDisplayEvidence(program: candidate.program)
    self.id = id; self.previousRevisionID = previousRevisionID
    candidateID = candidate.id; programContentHash = candidate.program.contentHash.description
    self.rating = rating; self.scope = scope; self.presentation = presentation; self.createdAt = createdAt
  }
}
