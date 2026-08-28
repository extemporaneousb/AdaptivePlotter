import EpisodeCore
import Foundation
import PlotterModel

public enum PlotterCapabilityKind: String, Codable, CaseIterable, Hashable, Sendable {
  case connection
  case motion
  case pose
  case camera
  case executionPlan
  case evidence
  case outcome
  case learningActivity
}

public struct PlotterConnectionFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let environment: PlotterEnvironment
  public let isConnected: Bool

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    environment: PlotterEnvironment,
    isConnected: Bool
  ) {
    self.owner = owner
    self.revision = revision
    self.environment = environment
    self.isConnected = isConnected
  }
}

public struct PlotterMotionFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let isEnabled: Bool

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    isEnabled: Bool
  ) {
    self.owner = owner
    self.revision = revision
    self.isEnabled = isEnabled
  }
}

public struct PlotterPoseFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let machinePosition: Point2<MachineSpace>?
  public let isSettled: Bool
  public let settlementPolicyRevision: EpisodeRevisionIdentifier

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    machinePosition: Point2<MachineSpace>?,
    isSettled: Bool,
    settlementPolicyRevision: EpisodeRevisionIdentifier
  ) {
    self.owner = owner
    self.revision = revision
    self.machinePosition = machinePosition
    self.isSettled = isSettled
    self.settlementPolicyRevision = settlementPolicyRevision
  }
}

public struct PlotterCameraFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let configurationID: CameraConfigurationID
  public let configurationRevision: EpisodeRevisionIdentifier
  public let isAvailable: Bool
  public let exactFrameAvailable: Bool

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    configurationID: CameraConfigurationID,
    configurationRevision: EpisodeRevisionIdentifier,
    isAvailable: Bool,
    exactFrameAvailable: Bool
  ) {
    self.owner = owner
    self.revision = revision
    self.configurationID = configurationID
    self.configurationRevision = configurationRevision
    self.isAvailable = isAvailable
    self.exactFrameAvailable = exactFrameAvailable
  }
}

public struct PlotterExecutionPlanFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let currentRevisionID: ExecutionPlanRevisionID?

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    currentRevisionID: ExecutionPlanRevisionID?
  ) {
    self.owner = owner
    self.revision = revision
    self.currentRevisionID = currentRevisionID
  }
}

public struct PlotterEvidenceFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let authorityRevision: EpisodeRevisionIdentifier
  public let availableQuestions: [PlotterEvidenceQuestion]

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    authorityRevision: EpisodeRevisionIdentifier,
    availableQuestions: [PlotterEvidenceQuestion]
  ) {
    self.owner = owner
    self.revision = revision
    self.authorityRevision = authorityRevision
    self.availableQuestions = availableQuestions
  }
}

public struct PlotterOutcomeFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let availableOutcomeIDs: [PlotterOutcomeID]

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    availableOutcomeIDs: [PlotterOutcomeID]
  ) {
    self.owner = owner
    self.revision = revision
    self.availableOutcomeIDs = availableOutcomeIDs
  }
}

public struct PlotterPointSelectionActivityOwner: Codable, Hashable, Sendable {
  public let selectionID: PlotterPointSelectionID
  public let exerciseAttemptID: UUID

  public init(
    selectionID: PlotterPointSelectionID,
    exerciseAttemptID: UUID
  ) {
    self.selectionID = selectionID
    self.exerciseAttemptID = exerciseAttemptID
  }
}

public struct PlotterLearningActivityFact: Codable, Hashable, Sendable {
  public let owner: EpisodeAuthorityID
  public let revision: CapabilityFactRevision
  public let activeCameraCalibration: Bool
  public let activeAttempt: Bool
  public let activeDiscovery: Bool
  public let activeExploration: Bool
  public let activeLearningMotion: Bool
  public let pointSelectionOwner: PlotterPointSelectionActivityOwner?

  public init(
    owner: EpisodeAuthorityID,
    revision: CapabilityFactRevision,
    activeCameraCalibration: Bool,
    activeAttempt: Bool,
    activeDiscovery: Bool,
    activeExploration: Bool,
    activeLearningMotion: Bool,
    pointSelectionOwner: PlotterPointSelectionActivityOwner? = nil
  ) {
    self.owner = owner
    self.revision = revision
    self.activeCameraCalibration = activeCameraCalibration
    self.activeAttempt = activeAttempt
    self.activeDiscovery = activeDiscovery
    self.activeExploration = activeExploration
    self.activeLearningMotion = activeLearningMotion
    self.pointSelectionOwner = pointSelectionOwner
  }

  public var activePointSelection: Bool { pointSelectionOwner != nil }

  public var hasActiveLearningWork: Bool {
    activeCameraCalibration || activeAttempt || activeDiscovery || activeExploration
      || activeLearningMotion
  }

  public var hasActiveUnrelatedLearningWork: Bool {
    activeCameraCalibration || activeExploration || activeLearningMotion
      || (activeAttempt && !activePointSelection)
      || (activeDiscovery && !activePointSelection)
  }
}

public enum PlotterCapabilityFact: CapabilityFact {
  case connection(PlotterConnectionFact)
  case motion(PlotterMotionFact)
  case pose(PlotterPoseFact)
  case camera(PlotterCameraFact)
  case executionPlan(PlotterExecutionPlanFact)
  case evidence(PlotterEvidenceFact)
  case outcome(PlotterOutcomeFact)
  case learningActivity(PlotterLearningActivityFact)

  public var kind: PlotterCapabilityKind {
    switch self {
    case .connection:
      return .connection
    case .motion:
      return .motion
    case .pose:
      return .pose
    case .camera:
      return .camera
    case .executionPlan:
      return .executionPlan
    case .evidence:
      return .evidence
    case .outcome:
      return .outcome
    case .learningActivity:
      return .learningActivity
    }
  }

  public var capabilityID: EpisodeCapabilityID {
    EpisodeCapabilityID(rawValue: "plotter.\(kind.rawValue)")
  }

  public var owner: EpisodeAuthorityID {
    switch self {
    case let .connection(fact):
      return fact.owner
    case let .motion(fact):
      return fact.owner
    case let .pose(fact):
      return fact.owner
    case let .camera(fact):
      return fact.owner
    case let .executionPlan(fact):
      return fact.owner
    case let .evidence(fact):
      return fact.owner
    case let .outcome(fact):
      return fact.owner
    case let .learningActivity(fact):
      return fact.owner
    }
  }

  public var revision: CapabilityFactRevision {
    switch self {
    case let .connection(fact):
      return fact.revision
    case let .motion(fact):
      return fact.revision
    case let .pose(fact):
      return fact.revision
    case let .camera(fact):
      return fact.revision
    case let .executionPlan(fact):
      return fact.revision
    case let .evidence(fact):
      return fact.revision
    case let .outcome(fact):
      return fact.revision
    case let .learningActivity(fact):
      return fact.revision
    }
  }
}

extension Collection where Element == PlotterCapabilityFact {
  func fact(ofKind kind: PlotterCapabilityKind) -> PlotterCapabilityFact? {
    first { $0.kind == kind }
  }

  func sortedReferences() -> [CapabilityFactReference] {
    map(CapabilityFactReference.init).sorted { lhs, rhs in
      if lhs.capabilityID.rawValue != rhs.capabilityID.rawValue {
        return lhs.capabilityID.rawValue < rhs.capabilityID.rawValue
      }
      if lhs.owner.rawValue != rhs.owner.rawValue {
        return lhs.owner.rawValue < rhs.owner.rawValue
      }
      return lhs.revision < rhs.revision
    }
  }
}
