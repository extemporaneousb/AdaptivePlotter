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
public enum RunIDTag: Sendable {}
public enum CameraConfigurationIDTag: Sendable {}
public enum PenProfileIDTag: Sendable {}
public enum DrawingModelRevisionIDTag: Sendable {}
public enum DrawingRegistrationRevisionIDTag: Sendable {}
public enum PlanCheckpointIDTag: Sendable {}
public enum DrawingEvidenceRecordIDTag: Sendable {}

public typealias ProgramID = StrongID<ProgramIDTag>
public typealias StrokeID = StrongID<StrokeIDTag>
public typealias RunID = StrongID<RunIDTag>
public typealias CameraConfigurationID = StrongID<CameraConfigurationIDTag>
public typealias PenProfileID = StrongID<PenProfileIDTag>
public typealias DrawingModelRevisionID = StrongID<DrawingModelRevisionIDTag>
public typealias DrawingRegistrationRevisionID = StrongID<DrawingRegistrationRevisionIDTag>
public typealias PlanCheckpointID = StrongID<PlanCheckpointIDTag>
public typealias DrawingEvidenceRecordID = StrongID<DrawingEvidenceRecordIDTag>
