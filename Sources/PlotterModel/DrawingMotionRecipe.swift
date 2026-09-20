import Foundation

/// Independently addresses an execution recipe without changing intended plan,
/// checkpoint, preview, or possible-ink identity.
public struct DrawingMotionRecipe: Codable, Hashable, Sendable, CanonicalEncodable {
  public let schemaVersion: UInt16
  public let planRevisionID: ExecutionPlanRevisionID
  public let planContentHash: Digest
  public let policy: DrawingMotionPolicy
  public let contentHash: Digest

  public init(planRevisionID: ExecutionPlanRevisionID, planContentHash: Digest,
    policy: DrawingMotionPolicy) throws {
    guard planRevisionID.rawValue == planContentHash else { throw DrawingPlanningError.contentHashMismatch }
    try policy.validate()
    schemaVersion = 1; self.planRevisionID = planRevisionID; self.planContentHash = planContentHash
    self.policy = policy
    contentHash = try canonicalDigest(of: Basis(planRevisionID: planRevisionID,
      planContentHash: planContentHash, policy: policy))
  }

  public func validate(plan: ExecutionPlanRevision) throws {
    try policy.validate()
    guard schemaVersion == 1, planRevisionID == plan.revisionID, planContentHash == plan.contentHash,
      contentHash == (try canonicalDigest(of: Basis(planRevisionID: planRevisionID,
        planContentHash: planContentHash, policy: policy))) else {
      throw DrawingPlanningError.contentHashMismatch
    }
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try Basis(planRevisionID: planRevisionID, planContentHash: planContentHash, policy: policy)
      .encodeCanonical(to: &encoder)
    encoder.appendDigest(contentHash)
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, planRevisionID, planContentHash, policy, contentHash }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard try values.decode(UInt16.self, forKey: .schemaVersion) == 1 else {
      throw PlotterModelError.invalidValue("unsupported drawing motion recipe schema")
    }
    let decoded = try Self(planRevisionID: values.decode(ExecutionPlanRevisionID.self, forKey: .planRevisionID),
      planContentHash: values.decode(Digest.self, forKey: .planContentHash),
      policy: values.decode(DrawingMotionPolicy.self, forKey: .policy))
    guard try values.decode(Digest.self, forKey: .contentHash) == decoded.contentHash else {
      throw DrawingPlanningError.contentHashMismatch
    }
    self = decoded
  }

  private struct Basis: CanonicalEncodable {
    let planRevisionID: ExecutionPlanRevisionID
    let planContentHash: Digest
    let policy: DrawingMotionPolicy
    func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
      try encoder.appendString("DrawingMotionRecipe-v1")
      try planRevisionID.encodeCanonical(to: &encoder); encoder.appendDigest(planContentHash)
      try policy.encodeCanonical(to: &encoder)
    }
  }
}

extension DrawingPlanner {
  public static func motionRecipe(for plan: ExecutionPlanRevision,
    policy: DrawingMotionPolicy) throws -> DrawingMotionRecipe {
    try DrawingMotionRecipe(planRevisionID: plan.revisionID, planContentHash: plan.contentHash, policy: policy)
  }
}
