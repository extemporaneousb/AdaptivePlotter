import Foundation
import PlotterModel

public enum WorkflowTelemetryOperation: String, Codable, CaseIterable, Hashable, Sendable {
  case manualJog
  case manualDrawingStroke
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

public enum WorkflowTelemetryFailureCode: String, Codable, CaseIterable, Hashable, Sendable {
  case controllerContextChanged = "controller_context_changed"
  case freshFrameUnavailable = "fresh_frame_unavailable"
  case controllerOutcome = "controller_outcome"
  case inkRejected = "ink_rejected"
  case requiredStateMissing = "required_state_missing"
  case unexpectedFailure = "unexpected_failure"
  case manualJogAdmissionRejected = "manual_jog_admission_rejected"
  case manualJogRefused = "manual_jog_refused"
  case manualJogAmbiguous = "manual_jog_ambiguous"
  case manualDrawingAdmissionRejected = "manual_drawing_admission_rejected"
  case manualDrawingRefused = "manual_drawing_refused"
  case manualDrawingAmbiguous = "manual_drawing_ambiguous"
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
  public let failureCode: WorkflowTelemetryFailureCode?
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
    failureCode: WorkflowTelemetryFailureCode? = nil,
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
