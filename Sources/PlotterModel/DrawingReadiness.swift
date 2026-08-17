import Foundation

/// A trial's role is fixed before its result exists. In particular, a reserved
/// holdout cannot be promoted into training evidence after inspection.
public enum DrawingTrialEvidenceRole: UInt8, Codable, Sendable, CaseIterable {
  case training = 0
  case reservedHoldout = 1
  case evaluationHoldout = 2
  case ordinaryDrawing = 3
}

extension DrawingTrialEvidenceRole: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public enum DrawingTrialEvidenceDisposition: UInt8, Codable, Sendable, CaseIterable {
  case attributable = 0
  case refused = 1
  case ambiguous = 2
  case possibleInk = 3
  case visionUnclear = 4
  case cancelled = 5
}

extension DrawingTrialEvidenceDisposition: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public struct DrawingEvidenceReference: Hashable, Codable, Sendable, CanonicalEncodable {
  public let recordID: DrawingEvidenceRecordID
  public let role: DrawingTrialEvidenceRole
  public let disposition: DrawingTrialEvidenceDisposition

  public init(
    recordID: DrawingEvidenceRecordID,
    role: DrawingTrialEvidenceRole,
    disposition: DrawingTrialEvidenceDisposition
  ) {
    self.recordID = recordID
    self.role = role
    self.disposition = disposition
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try recordID.encodeCanonical(to: &encoder)
    try role.encodeCanonical(to: &encoder)
    try disposition.encodeCanonical(to: &encoder)
  }
}

public enum DrawingReadinessRequirement: UInt8, Codable, Sendable, CaseIterable {
  case currentProvenance = 0
  case coverageSet = 1
  case untouchedLineHoldouts = 2
  case candidatePriorComparison = 3
  case shapeHoldouts = 4
}

extension DrawingReadinessRequirement: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public enum DrawingReadinessRequirementDisposition: UInt8, Codable, Sendable, CaseIterable {
  case incomplete = 0
  case passed = 1
  case failed = 2
}

extension DrawingReadinessRequirementDisposition: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public struct DrawingReadinessRequirementResult:
  Hashable, Codable, Sendable, CanonicalEncodable
{
  public let requirement: DrawingReadinessRequirement
  public let disposition: DrawingReadinessRequirementDisposition
  public let evidenceRecordIDs: [DrawingEvidenceRecordID]

  public init(
    requirement: DrawingReadinessRequirement,
    disposition: DrawingReadinessRequirementDisposition,
    evidenceRecordIDs: [DrawingEvidenceRecordID] = []
  ) throws {
    guard Set(evidenceRecordIDs).count == evidenceRecordIDs.count else {
      throw DrawingReadinessError.duplicateEvidenceReference
    }
    guard disposition != .passed || !evidenceRecordIDs.isEmpty else {
      throw DrawingReadinessError.passedRequirementHasNoEvidence(requirement)
    }
    self.requirement = requirement
    self.disposition = disposition
    self.evidenceRecordIDs = evidenceRecordIDs.sorted()
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try requirement.encodeCanonical(to: &encoder)
    try disposition.encodeCanonical(to: &encoder)
    try encoder.appendCount(evidenceRecordIDs.count)
    for id in evidenceRecordIDs { try id.encodeCanonical(to: &encoder) }
  }

  private enum CodingKeys: String, CodingKey {
    case requirement, disposition, evidenceRecordIDs
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      requirement: container.decode(DrawingReadinessRequirement.self, forKey: .requirement),
      disposition: container.decode(
        DrawingReadinessRequirementDisposition.self,
        forKey: .disposition
      ),
      evidenceRecordIDs: container.decode(
        [DrawingEvidenceRecordID].self,
        forKey: .evidenceRecordIDs
      )
    )
  }
}

public enum DrawingReadinessState: UInt8, Codable, Sendable {
  case notReady = 0
  case ready = 1
}

extension DrawingReadinessState: CanonicalEncodable {
  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public enum DrawingReadinessError: Error, Equatable, Sendable {
  case incompleteRequirementSet
  case duplicateRequirement
  case duplicateEvidenceRecord
  case duplicateEvidenceReference
  case unknownEvidenceRecord(DrawingEvidenceRecordID)
  case passedRequirementHasNoEvidence(DrawingReadinessRequirement)
  case contentHashMismatch
}

public struct DrawingReadinessAssessment: Hashable, Codable, Sendable, CanonicalEncodable {
  public static let schemaVersion: UInt16 = 1

  public let schemaVersion: UInt16
  public let state: DrawingReadinessState
  public let provenance: DrawingPlanningProvenance
  public let applicability: DrawableMachineRegion
  public let requirements: [DrawingReadinessRequirementResult]
  public let evidence: [DrawingEvidenceReference]
  public let contentHash: Digest

  public init(
    provenance: DrawingPlanningProvenance,
    applicability: DrawableMachineRegion,
    requirements: [DrawingReadinessRequirementResult],
    evidence: [DrawingEvidenceReference]
  ) throws {
    guard Set(requirements.map(\.requirement)).count == requirements.count else {
      throw DrawingReadinessError.duplicateRequirement
    }
    guard Set(requirements.map(\.requirement)) == Set(DrawingReadinessRequirement.allCases) else {
      throw DrawingReadinessError.incompleteRequirementSet
    }
    guard Set(evidence.map(\.recordID)).count == evidence.count else {
      throw DrawingReadinessError.duplicateEvidenceRecord
    }

    let evidenceByID = Dictionary(uniqueKeysWithValues: evidence.map { ($0.recordID, $0) })
    for result in requirements {
      for id in result.evidenceRecordIDs where evidenceByID[id] == nil {
        throw DrawingReadinessError.unknownEvidenceRecord(id)
      }
    }

    let orderedRequirements = requirements.sorted {
      $0.requirement.rawValue < $1.requirement.rawValue
    }
    let orderedEvidence = evidence.sorted { $0.recordID < $1.recordID }
    let isReady =
      orderedRequirements.allSatisfy { $0.disposition == .passed }
      && orderedRequirements.flatMap(\.evidenceRecordIDs).allSatisfy {
        evidenceByID[$0]?.disposition == .attributable
      }
    let derivedState: DrawingReadinessState = isReady ? .ready : .notReady
    let basis = DrawingReadinessAssessmentHashBasis(
      schemaVersion: Self.schemaVersion,
      state: derivedState,
      provenance: provenance,
      applicability: applicability,
      requirements: orderedRequirements,
      evidence: orderedEvidence
    )

    schemaVersion = Self.schemaVersion
    state = derivedState
    self.provenance = provenance
    self.applicability = applicability
    self.requirements = orderedRequirements
    self.evidence = orderedEvidence
    contentHash = try canonicalDigest(of: basis)
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try DrawingReadinessAssessmentHashBasis(
      schemaVersion: schemaVersion,
      state: state,
      provenance: provenance,
      applicability: applicability,
      requirements: requirements,
      evidence: evidence
    ).encodeCanonical(to: &encoder)
    encoder.appendDigest(contentHash)
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion, state, provenance, applicability, requirements, evidence, contentHash
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let encodedSchemaVersion = try container.decode(UInt16.self, forKey: .schemaVersion)
    guard encodedSchemaVersion == Self.schemaVersion else {
      throw PlotterModelError.invalidValue("unsupported DrawingReadinessAssessment schema")
    }
    let decodedState = try container.decode(DrawingReadinessState.self, forKey: .state)
    let decodedHash = try container.decode(Digest.self, forKey: .contentHash)
    let decoded = try Self(
      provenance: container.decode(DrawingPlanningProvenance.self, forKey: .provenance),
      applicability: container.decode(DrawableMachineRegion.self, forKey: .applicability),
      requirements: container.decode(
        [DrawingReadinessRequirementResult].self,
        forKey: .requirements
      ),
      evidence: container.decode([DrawingEvidenceReference].self, forKey: .evidence)
    )
    guard decoded.state == decodedState, decoded.contentHash == decodedHash else {
      throw DrawingReadinessError.contentHashMismatch
    }
    self = decoded
  }
}

private struct DrawingReadinessAssessmentHashBasis: CanonicalEncodable {
  let schemaVersion: UInt16
  let state: DrawingReadinessState
  let provenance: DrawingPlanningProvenance
  let applicability: DrawableMachineRegion
  let requirements: [DrawingReadinessRequirementResult]
  let evidence: [DrawingEvidenceReference]

  func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("DrawingReadinessAssessment")
    encoder.appendUInt16(schemaVersion)
    try state.encodeCanonical(to: &encoder)
    try provenance.encodeCanonical(to: &encoder)
    try applicability.encodeCanonical(to: &encoder)
    try encoder.appendCount(requirements.count)
    for requirement in requirements { try requirement.encodeCanonical(to: &encoder) }
    try encoder.appendCount(evidence.count)
    for reference in evidence { try reference.encodeCanonical(to: &encoder) }
  }
}
