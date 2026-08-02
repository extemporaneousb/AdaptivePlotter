import Foundation

public struct StrongID<Tag>: Hashable, Codable, Sendable, CustomStringConvertible {
  public let rawValue: UUID

  public init(_ rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }

  public var description: String { rawValue.uuidString.lowercased() }
}

extension StrongID: Comparable {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.description < rhs.description
  }
}

public enum ProgramIDTag: Sendable {}
public enum StrokeIDTag: Sendable {}
public enum StrokeSliceIDTag: Sendable {}
public enum PlanIDTag: Sendable {}
public enum RunIDTag: Sendable {}
public enum ModelIDTag: Sendable {}
public enum ModelCandidateIDTag: Sendable {}
public enum StateEstimateIDTag: Sendable {}
public enum FieldRegistrationIDTag: Sendable {}
public enum SafetyPolicyIDTag: Sendable {}
public enum MachineConfigurationIDTag: Sendable {}
public enum CameraConfigurationIDTag: Sendable {}
public enum ToolConfigurationIDTag: Sendable {}
public enum PenProfileIDTag: Sendable {}
public enum EvidenceIDTag: Sendable {}
public enum ObservationIDTag: Sendable {}
public enum ObservationRegionIDTag: Sendable {}
public enum CheckpointIDTag: Sendable {}
public enum CheckpointResolutionIDTag: Sendable {}
public enum ClearanceEnvelopeIDTag: Sendable {}
public enum ClearancePoseIDTag: Sendable {}
public enum ClearancePathIDTag: Sendable {}

public typealias ProgramID = StrongID<ProgramIDTag>
public typealias StrokeID = StrongID<StrokeIDTag>
public typealias StrokeSliceID = StrongID<StrokeSliceIDTag>
public typealias PlanID = StrongID<PlanIDTag>
public typealias RunID = StrongID<RunIDTag>
public typealias ModelID = StrongID<ModelIDTag>
public typealias ModelCandidateID = StrongID<ModelCandidateIDTag>
public typealias StateEstimateID = StrongID<StateEstimateIDTag>
public typealias FieldRegistrationID = StrongID<FieldRegistrationIDTag>
public typealias SafetyPolicyID = StrongID<SafetyPolicyIDTag>
public typealias MachineConfigurationID = StrongID<MachineConfigurationIDTag>
public typealias CameraConfigurationID = StrongID<CameraConfigurationIDTag>
public typealias ToolConfigurationID = StrongID<ToolConfigurationIDTag>
public typealias PenProfileID = StrongID<PenProfileIDTag>
public typealias EvidenceID = StrongID<EvidenceIDTag>
public typealias ObservationID = StrongID<ObservationIDTag>
public typealias ObservationRegionID = StrongID<ObservationRegionIDTag>
public typealias CheckpointID = StrongID<CheckpointIDTag>
public typealias CheckpointResolutionID = StrongID<CheckpointResolutionIDTag>
public typealias ClearanceEnvelopeID = StrongID<ClearanceEnvelopeIDTag>
public typealias ClearancePoseID = StrongID<ClearancePoseIDTag>
public typealias ClearancePathID = StrongID<ClearancePathIDTag>
