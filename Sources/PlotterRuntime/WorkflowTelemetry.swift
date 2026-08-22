import Foundation
import PlotterModel

public enum WorkflowTelemetryOperation: String, Codable, CaseIterable, Hashable, Sendable {
  case manualJog
  case manualDrawingStroke
  case currentCameraCalibration
  case sparseTipCalibration
}

public enum WorkflowTelemetryPhase: String, Codable, CaseIterable, Hashable, Sendable {
  case intentAccepted
  case batchAdmitted
  case circleCompleted
  case revealCompleted
  case phaseChanged
  case controllerContextEstablished
  case controllerContextCompared
  case completed
  case cancelled
  case failed
}

public enum SparseTipWorkflowProgressStage: String, Codable, CaseIterable, Hashable, Sendable {
  case batchAdmitted
  case circleCompleted
  case revealCompleted
  case terminal
}

public enum SparseTipWorkflowTerminalDisposition: String, Codable, CaseIterable, Hashable,
  Sendable
{
  case completed
  case cancelled
  case refused
  case unclear
  case ambiguous
  case failed
  case possibleInk
}

/// One semantic Stage 3.4 batch fact. A circle-complete record represents all
/// of that circle's chords; individual chord motion never emits workflow
/// telemetry.
public struct SparseTipWorkflowProgress: Codable, Hashable, Sendable {
  public let stage: SparseTipWorkflowProgressStage
  public let completedCircleCount: Int
  public let totalCircleCount: Int
  public let circlePosition: ToolContactCalibrationPosition?
  public let chordCount: Int?
  public let terminalDisposition: SparseTipWorkflowTerminalDisposition?

  public init(
    stage: SparseTipWorkflowProgressStage,
    completedCircleCount: Int,
    totalCircleCount: Int,
    circlePosition: ToolContactCalibrationPosition? = nil,
    chordCount: Int? = nil,
    terminalDisposition: SparseTipWorkflowTerminalDisposition? = nil
  ) {
    self.stage = stage
    self.completedCircleCount = completedCircleCount
    self.totalCircleCount = totalCircleCount
    self.circlePosition = circlePosition
    self.chordCount = chordCount
    self.terminalDisposition = terminalDisposition
  }
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
  public static let schemaVersion = 2

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
  public let sparseTipProgress: SparseTipWorkflowProgress?

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
    recovery: WorkflowTelemetryRecovery = .none,
    sparseTipProgress: SparseTipWorkflowProgress? = nil
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
    self.sparseTipProgress = sparseTipProgress
  }
}
