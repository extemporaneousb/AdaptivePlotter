import Foundation
import PlotterModel

public enum WorkflowTelemetryOperation: String, Codable, CaseIterable, Hashable, Sendable {
  case manualJog
  case currentCameraCalibration
}

public enum WorkflowTelemetryPhase: String, Codable, CaseIterable, Hashable, Sendable {
  case intentAccepted
  case phaseChanged
  case controllerContextEstablished
  case controllerContextCompared
  case completed
  case cancelled
  case failed
}

public enum WorkflowTelemetryRecovery: String, Codable, CaseIterable, Hashable, Sendable {
  case none
  case retryCalibration
  case revalidateControllerContext
  case resolveNamedFailure
}

public struct WorkflowMotionIntent: Codable, Hashable, Sendable {
  public let deltaXMM: Double
  public let deltaYMM: Double
  public let feedMMPerMinute: Double

  public init(deltaXMM: Double, deltaYMM: Double, feedMMPerMinute: Double) {
    self.deltaXMM = deltaXMM
    self.deltaYMM = deltaYMM
    self.feedMMPerMinute = feedMMPerMinute
  }
}

public struct WorkflowControllerContextTelemetry: Codable, Hashable, Sendable {
  public let baselineProbeID: UUID?
  public let refreshedProbeID: UUID
  public let comparison: ControllerCheckpointContextComparison?

  public init(
    baselineProbeID: UUID?,
    refreshedProbeID: UUID,
    comparison: ControllerCheckpointContextComparison?
  ) {
    self.baselineProbeID = baselineProbeID
    self.refreshedProbeID = refreshedProbeID
    self.comparison = comparison
  }
}

/// Durable workflow semantics that complement the RunLedger's raw controller
/// events. These records are diagnostic facts only; replay and admission must
/// never consume them.
public struct WorkflowTelemetryEvent: Codable, Hashable, Sendable {
  public static let schemaVersion = 1

  public let eventID: UUID
  public let operationID: UUID
  public let operation: WorkflowTelemetryOperation
  public let phase: WorkflowTelemetryPhase
  public let attemptID: ExerciseAttemptID?
  public let detail: String
  public let motionIntent: WorkflowMotionIntent?
  public let controllerContext: WorkflowControllerContextTelemetry?
  public let failureCode: String?
  public let recovery: WorkflowTelemetryRecovery

  public init(
    eventID: UUID = UUID(),
    operationID: UUID,
    operation: WorkflowTelemetryOperation,
    phase: WorkflowTelemetryPhase,
    attemptID: ExerciseAttemptID? = nil,
    detail: String,
    motionIntent: WorkflowMotionIntent? = nil,
    controllerContext: WorkflowControllerContextTelemetry? = nil,
    failureCode: String? = nil,
    recovery: WorkflowTelemetryRecovery = .none
  ) {
    self.eventID = eventID
    self.operationID = operationID
    self.operation = operation
    self.phase = phase
    self.attemptID = attemptID
    self.detail = detail
    self.motionIntent = motionIntent
    self.controllerContext = controllerContext
    self.failureCode = failureCode
    self.recovery = recovery
  }
}
