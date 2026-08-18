import CryptoKit
import Foundation
import Observation
import PlotterModel
import PlotterRuntime

enum FixedCameraOpticalSettlingPolicy {
  // The C920 mount can wobble by more than one integer pixel after carriage
  // travel. Keep the search finite and accept at most two pixels of global
  // translation; controller pose tolerance remains independently authoritative.
  static let alignmentSearchRadiusPixels = 3
  static let maximumAlignmentShiftPixels = 2
  static let requiredCentroidFrameCount = 3
  static let maximumCentroidSpreadPixels: Double = 2
  static let maximumBackgroundMeanAbsoluteDifference: Double = 4

  static func newestStableCapSample(
    _ samples: [StableWorkflowCapInspection]
  ) throws -> StableWorkflowCapInspection {
    guard samples.count == requiredCentroidFrameCount else {
      throw LearningPathOperationError.requiredState(
        "Pen-cap settlement requires exactly \(requiredCentroidFrameCount) exact frames."
      )
    }
    for sample in samples {
      guard
        sample.inspection.measurement.frameID
          == sample.inspection.displayedFrame.frame.id,
        sample.inspection.measurement.cameraConfigurationID
          == sample.inspection.displayedFrame.frame.cameraConfigurationID,
        sample.inspection.measurement.frameSHA256
          == sample.inspection.displayedFrame.frame.contentSHA256
      else {
        throw LearningPathOperationError.requiredState(
          "Pen-cap settlement result did not belong to its exact displayed frame."
        )
      }
    }
    for (previous, current) in zip(samples, samples.dropFirst()) {
      guard
        previous.inspection.displayedFrame.source == current.inspection.displayedFrame.source,
        previous.inspection.displayedFrame.frame.cameraConfigurationID
          == current.inspection.displayedFrame.frame.cameraConfigurationID
      else {
        throw LearningPathOperationError.requiredState(
          "Camera source or configuration changed during cap settlement."
        )
      }
      guard
        current.inspection.displayedFrame.frame.captureNanoseconds
          > previous.inspection.displayedFrame.frame.captureNanoseconds
      else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
    }
    let maximumSpread =
      samples.enumerated().flatMap { leftIndex, left in
        samples.dropFirst(leftIndex + 1).map {
          left.cap.centroid.distance(to: $0.cap.centroid)
        }
      }.max() ?? 0
    guard maximumSpread <= maximumCentroidSpreadPixels else {
      throw LearningPathOperationError.requiredState(
        String(
          format:
            "Pen-cap centroid did not settle across %d exact frames: %.2f px spread exceeds %.2f px.",
          samples.count,
          maximumSpread,
          maximumCentroidSpreadPixels
        )
      )
    }
    return samples[samples.index(before: samples.endIndex)]
  }
}

struct VideoAnalysisRegionLock: Hashable, Sendable {
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID
  let region: PixelRect

  func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    source == displayedFrame.source
      && cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
  }
}

enum OperatorFrameMode: String, CaseIterable, Hashable, Identifiable, Sendable {
  case live = "LIVE"
  case simulated = "SIMULATED"

  var id: Self { self }
}

enum AcceptedArtifactCheckpointStatus: Equatable, Sendable {
  case unavailable
  case cleared
  case quarantined(sideCount: Int)
  case saved(sideCount: Int, centerArrival: Bool)
  case restored(sideCount: Int, centerArrival: Bool, reportedPositionDeltaMM: Double)
  case incompatible(String)
  case rejected(String)
}

enum ControllerPoseApplicability: Equatable, Sendable {
  case currentSession
  case requiresVisualRevalidation(reportedPositionDeltaMM: Double)
  case visuallyRevalidated(frameID: FrameID, residualPixels: Double)
}

enum JogDirection: String, CaseIterable, Identifiable, Sendable {
  case xNegative
  case xPositive
  case yNegative
  case yPositive

  var id: Self { self }

  var shortLabel: String {
    switch self {
    case .xNegative: "X−"
    case .xPositive: "X+"
    case .yNegative: "Y−"
    case .yPositive: "Y+"
    }
  }
}

enum BoundaryTeachingState: Equatable, Sendable {
  case idle
  case awaitingOwnerAdmission(JogDirection)
  case ownerActive(JogDirection)
  case cancelling(JogDirection)

  var direction: JogDirection? {
    switch self {
    case .idle: nil
    case .awaitingOwnerAdmission(let direction), .ownerActive(let direction),
      .cancelling(let direction):
      direction
    }
  }
}

enum ContextualStopTarget: Hashable, Sendable {
  case pairedBoundary(
    capabilityID: ContextualStopCapabilityID,
    transactionID: UUID,
    operationOwner: ContextualMotionOwnerID,
    attemptID: ExerciseAttemptID,
    direction: BoundaryDirection
  )
  case manualJog(capabilityID: ContextualStopCapabilityID, operationOwner: ContextualMotionOwnerID)
  case manualDrawingStroke(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID
  )
  case exerciseMotion(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    ownerID: LearningPathItemID,
    action: LearningMotionAction
  )
  case drawingTrial(
    capabilityID: ContextualStopCapabilityID, operationOwner: ContextualMotionOwnerID)
  case sparseTipBatch(
    capabilityID: ContextualStopCapabilityID,
    attemptID: ExerciseAttemptID
  )
  case sparseTipBatchSegment(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    location: BlacklistedToolContactLocation
  )

  var capabilityID: ContextualStopCapabilityID {
    switch self {
    case .pairedBoundary(let capabilityID, _, _, _, _),
      .manualJog(let capabilityID, _),
      .manualDrawingStroke(let capabilityID, _),
      .exerciseMotion(let capabilityID, _, _, _),
      .drawingTrial(let capabilityID, _),
      .sparseTipBatch(let capabilityID, _),
      .sparseTipBatchSegment(let capabilityID, _, _):
      capabilityID
    }
  }

  var operationOwner: ContextualMotionOwnerID? {
    switch self {
    case .pairedBoundary(_, _, let owner, _, _),
      .manualJog(_, let owner),
      .manualDrawingStroke(_, let owner),
      .exerciseMotion(_, let owner, _, _),
      .drawingTrial(_, let owner),
      .sparseTipBatchSegment(_, let owner, _):
      owner
    case .sparseTipBatch:
      nil
    }
  }
}

/// Semantic identity for every supervised Learning Path travel. These values
/// cross admission, Stop ownership, settlement, telemetry, and presentation;
/// callers cannot silently invent a new lifecycle action with display text.
enum LearningMotionAction: Hashable, Sendable {
  case moveToEstimatedCenter
  case cameraCalibrationSample(index: Int, total: Int)
  case returnFromCameraCalibration
  case sparseTipApproach(ToolContactCalibrationPosition)
  case sparseTipCircleStart(ToolContactCalibrationPosition)
  case sparseTipBatchReveal
  case sparseTipCircleChord(index: Int, total: Int)
  case moveToLineStart
  case confirmIsolatedLineStart
  case returnToLocalRevealPose

  var title: String {
    switch self {
    case .moveToEstimatedCenter: "Move to Estimated Center"
    case .cameraCalibrationSample(let index, let total):
      "Current-Camera Calibration Sample \(index) of \(total)"
    case .returnFromCameraCalibration: "Return from Current-Camera Calibration"
    case .sparseTipApproach(let position): "Sparse Tip Mark \(position.rawValue) Approach"
    case .sparseTipCircleStart(let position): "Sparse Tip Circle \(position.rawValue) Start"
    case .sparseTipBatchReveal: "Reveal Five Sparse Tip Circles"
    case .sparseTipCircleChord(let index, let total):
      "Sparse Tip Circle chord \(index)/\(total)"
    case .moveToLineStart: "Move to Line Start"
    case .confirmIsolatedLineStart: "Confirm Isolated-Line Start"
    case .returnToLocalRevealPose: "Return to Local Reveal Pose"
    }
  }
}

enum ContextualMotionOwnerID: Hashable, Sendable {
  case liveBoundary(BoundaryMotionOwnerID)
  case liveOperation(UUID)
  case simulated(SimulatedLearningOperationID)

  var isBoundaryOwner: Bool {
    if case .liveBoundary = self { return true }
    return false
  }
}

struct ContextualStopPresentation: Hashable, Sendable {
  let capabilityID: ContextualStopCapabilityID
  let title: String
  let detail: String
}

struct ContextualStopAuditRecord: Hashable, Sendable {
  let capabilityID: ContextualStopCapabilityID
  let actor: String
  let action: String
  let disposition: JogCancelIntent
  let outcome: String
}

enum BoundaryActivityActor: String, Hashable, Sendable {
  case operatorActor = "Operator"
  case controller = "Controller"
  case camera = "Camera"
  case vision = "Vision"
  case workspace = "Workspace"
  case simulator = "Simulator"
}

enum BoundaryActivityOperation: Hashable, Sendable {
  case normal(BoundaryDirection)
  case replacement(BoundaryDirection, acceptedRevisionID: LearningArtifactRevisionID)
  case additional(BoundaryDirection, acceptedRevisionID: LearningArtifactRevisionID)

  var direction: BoundaryDirection {
    switch self {
    case .normal(let direction), .replacement(let direction, _),
      .additional(let direction, _):
      direction
    }
  }

}

enum BoundaryActivityPhase: String, Hashable, Sendable {
  case admission = "Admission"
  case moving = "Moving"
  case renewalPlanning = "Renewal planning"
  case stopLatched = "Stop latched"
  case settling = "Controller settlement"
  case commit = "Atomic accepted commit"
  case recovery = "Recovery"
}

enum BoundaryActivityDisposition: Hashable, Sendable {
  case inProgress
  case succeeded
  case refused(String)
  case failed(String)
  case cancelled
  case ambiguous(String)

}

enum BoundaryActivityDetail: Hashable, Sendable {
  case message(String)
  case atomicCommitRejected(stage: String)

}

enum BoundaryActivityRecovery: Hashable, Sendable {
  case restartNormal(BoundaryDirection)
  case continueWithAcceptedFallback(BoundaryDirection)
  case resolveStickyAmbiguity(String)
  case none

}

/// Narrow, reporting-only Boundary activity. This is not replay, persistence,
/// eligibility authority, or a generic event bus.
struct BoundaryActivityRecord: Identifiable, Hashable, Sendable {
  let id: UUID
  let occurredNanoseconds: UInt64
  let actor: BoundaryActivityActor
  let operation: BoundaryActivityOperation
  let phase: BoundaryActivityPhase
  let disposition: BoundaryActivityDisposition
  let attemptID: ExerciseAttemptID
  let side: BoundaryDirection
  let operationOwnerID: ContextualMotionOwnerID?
  let stopCapabilityID: ContextualStopCapabilityID?
  let finalPosition: MachinePosition?
  let frameID: FrameID?
  let cameraConfigurationID: CameraConfigurationID?
  let affectedRevisionIDs: Set<LearningArtifactRevisionID>
  let retainedRevisionIDs: Set<LearningArtifactRevisionID>
  let detail: BoundaryActivityDetail
  let recovery: BoundaryActivityRecovery
  let acceptedFallbackRemainsCurrent: Bool
}

private struct ContextualStopDispositionLatch: Hashable, Sendable {
  let capabilityID: ContextualStopCapabilityID
  let intent: JogCancelIntent
  let actor: String
}

private enum ContextualStopLifecycleState {
  case available
  case latched(ContextualStopDispositionLatch, cancellationRequestInProgress: Bool)

  var latch: ContextualStopDispositionLatch? {
    switch self {
    case .available: nil
    case .latched(let latch, _): latch
    }
  }

  var cancellationRequestInProgress: Bool {
    if case .latched(_, let inProgress) = self { return inProgress }
    return false
  }
}

private enum StoppableOperationOwner {
  case boundary(Task<Void, Never>)
  case batch(Task<Void, Never>)
  case motion(Task<MotionOutcome, Never>)
  case drawing(Task<DrawingStrokeOutcome, Never>)
  case simulated(Task<SimulatedLearningOperationOutcome?, Never>)

  func settle() async {
    switch self {
    case .boundary(let task): await task.value
    case .batch(let task): await task.value
    case .motion(let task): _ = await task.value
    case .drawing(let task): _ = await task.value
    case .simulated(let task): _ = await task.value
    }
  }

  func cancelBatch() {
    guard case .batch(let task) = self else { return }
    task.cancel()
  }

  var drawingMayHaveInk: Bool {
    switch self {
    case .drawing, .simulated: true
    case .boundary, .batch, .motion: false
    }
  }
}

private struct StoppableOperationSegment {
  let target: ContextualStopTarget
  let owner: StoppableOperationOwner
}

private struct ActiveStoppableOperation {
  let target: ContextualStopTarget
  let owner: StoppableOperationOwner
  var segment: StoppableOperationSegment? = nil
  var possibleInkLocation: BlacklistedToolContactLocation? = nil
  var state: ContextualStopLifecycleState = .available
}

enum BoundaryAtomicCommitFailurePoint: String, CaseIterable, Hashable, Sendable {
  case settlement
  case aggregateConstruction
  case artifactGraphCommit
}

enum DrawingTrialAssessment: String, Hashable, Sendable {
  case predictionObserved

  var title: String {
    switch self {
    case .predictionObserved: "Observed line compared with predicted geometry"
    }
  }
}

enum LearningPathOperationError: LocalizedError, Sendable {
  case freshFrameUnavailable
  case controllerRefused(String)
  case controllerCancelled(String)
  case controllerAmbiguous(String)
  case controllerFailed(String)
  case possibleInk(String)
  case controllerContextChanged(ControllerCheckpointContextComparison)
  case inkRejected(String)
  case requiredState(String)

  var errorDescription: String? {
    switch self {
    case .freshFrameUnavailable:
      "A strictly newer exact camera frame was unavailable."
    case .controllerRefused(let detail), .controllerCancelled(let detail),
      .controllerAmbiguous(let detail), .controllerFailed(let detail), .possibleInk(let detail),
      .inkRejected(let detail), .requiredState(let detail):
      detail
    case .controllerContextChanged(let comparison):
      "Controller context changed during calibration: \(comparison.actionableDescription) The sample was discarded without motion retry."
    }
  }
}

enum WorkflowFailureKind: String, Codable, Hashable, Sendable {
  case refused
  case unclear
  case ambiguous
  case cancelled
  case failed
  case possibleInk
}

struct WorkflowFailure: Error, Hashable, Sendable {
  let kind: WorkflowFailureKind
  let detail: String
  let recovery: WorkflowTelemetryRecovery

  static func failed(_ detail: String) -> Self {
    Self(kind: .failed, detail: detail, recovery: .resolveNamedFailure)
  }

  static func refused(_ detail: String) -> Self {
    Self(kind: .refused, detail: detail, recovery: .resolveNamedFailure)
  }

  static func ambiguous(_ detail: String) -> Self {
    Self(kind: .ambiguous, detail: detail, recovery: .resolveNamedFailure)
  }

  var attemptDisposition: ExerciseAttemptDisposition {
    switch kind {
    case .refused: .refused(detail)
    case .unclear: .unclear(detail)
    case .ambiguous, .possibleInk: .ambiguous(detail)
    case .cancelled: .cancelled
    case .failed: .failed(detail)
    }
  }

  var boundaryDisposition: BoundaryActivityDisposition {
    switch kind {
    case .refused: .refused(detail)
    case .ambiguous, .possibleInk: .ambiguous(detail)
    case .cancelled: .cancelled
    case .unclear, .failed: .failed(detail)
    }
  }
}

enum CurrentCameraCalibrationPhase: Codable, Hashable, Sendable {
  case preparing
  case capturing(sample: Int, total: Int, role: String?)
  case moving(sample: Int, total: Int)
  case returningToReference
  case fittingAndTestingHoldouts

  var description: String {
    switch self {
    case .preparing: "Preparing bounded calibration"
    case .capturing(let sample, let total, let role):
      "Capturing exact sample \(sample) of \(total)\(role.map { " at \($0)" } ?? "")"
    case .moving(let sample, let total): "Moving Pen Up to exact sample \(sample) of \(total)"
    case .returningToReference: "Returning Pen Up to the recorded calibration reference pose"
    case .fittingAndTestingHoldouts:
      "Testing two independent cap holdouts and staging the all-five refit"
    }
  }
}

private struct CurrentCameraCalibrationFailure: Hashable, Sendable {
  let code: WorkflowTelemetryFailureCode
  let detail: String
  let recovery: WorkflowTelemetryRecovery
}

private struct CalibrationMachineObservation: Sendable {
  let position: MachinePosition
  let contextBaseline: ControllerContextBaseline?
}

private struct CalibrationCapAnchorCapture: Sendable {
  let evidence: MachineCameraCorrespondenceProvenance
  let contextBaseline: ControllerContextBaseline?
  let displayedFrame: DisplayedFrame
  let capAnchor: ToolCapAnchorEstimate
}

private struct PendingToolContactEvidence: Sendable {
  let attemptID: ExerciseAttemptID
  let operationID: ToolContactOperationID
  let position: ToolContactCalibrationPosition
  let intendedMarkPosition: MachinePosition
  let actualSettledPosition: MachinePosition
  let controllerContextEvidence: ControllerContextEvidenceReference
  let markGeometry: ToolContactMarkGeometryEvidence
  let penDown: PenActuationEvidence
  let penUp: PenActuationEvidence
  let preMarkFrame: ExactTipCalibrationFrame
  let preMarkCapEstimate: ToolCapAnchorEstimate
  let revealEvidence: ToolContactRevealEvidence
  let capMapPredictionAtMark: Point2<CameraPixelSpace>
  let maximumCapMapResidualPixels: Double
}

private struct DrawnToolContactEvidence: Sendable {
  let attemptID: ExerciseAttemptID
  let operationID: ToolContactOperationID
  let position: ToolContactCalibrationPosition
  let intendedMarkPosition: MachinePosition
  let actualSettledPosition: MachinePosition
  let controllerContextEvidence: ControllerContextEvidenceReference
  let markGeometry: ToolContactMarkGeometryEvidence
  let penDown: PenActuationEvidence
  let penUp: PenActuationEvidence
  let preMarkFrame: ExactTipCalibrationFrame
  let preMarkCapEstimate: ToolCapAnchorEstimate
  let capMapPredictionAtMark: Point2<CameraPixelSpace>
  let maximumCapMapResidualPixels: Double
}

struct LiveSceneInspection: Sendable {
  let displayedFrame: DisplayedFrame
  let measurement: PlotterSceneMeasurement
}

struct StableWorkflowCapInspection: Sendable {
  let inspection: LiveSceneInspection
  let cap: PenCapMeasurement
}

private struct ScopedVisionAnalysisLease: Sendable {}

struct ProtocolPoseSettlement: Hashable, Sendable {
  let action: LearningMotionAction
  let target: MachinePosition
  let actual: MachinePosition
  let residualMM: Double
  let toleranceMM: Double
  let controllerSessionID: UUID
  let coordinateRevision: UInt64
  let toolPaperRevision: UUID
}

struct TipCalibrationSemanticIdentityState: Hashable, Sendable {
  let machineGeometry: MachineGeometryIdentity
  let toolAssembly: ToolAssemblyRevision
  let penContactProfile: PenContactProfileRevision
  let paperInstance: PaperInstanceRevision
  let paperContactPlane: PaperContactPlaneRevision
  let cameraMountRevision: UUID
  let cameraReframingRevision: UUID

  static func ephemeral() -> Self {
    Self(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperInstance: PaperInstanceRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
  }
}

@MainActor
@Observable
final class OperatorWorkspace {
  private enum ExerciseAttemptMode: Equatable, Sendable {
    case normal
    case replacement
    case additional
  }

  private enum ExerciseAttemptLifecycle {
    case idle
    case active(id: ExerciseAttemptID, ownerID: LearningPathItemID, mode: ExerciseAttemptMode)

    var id: ExerciseAttemptID? {
      guard case .active(let id, _, _) = self else { return nil }
      return id
    }

    var ownerID: LearningPathItemID? {
      guard case .active(_, let ownerID, _) = self else { return nil }
      return ownerID
    }

    var mode: ExerciseAttemptMode? {
      guard case .active(_, _, let mode) = self else { return nil }
      return mode
    }

    mutating func begin(ownerID: LearningPathItemID, mode: ExerciseAttemptMode) -> Bool {
      guard case .idle = self else { return false }
      self = .active(id: ExerciseAttemptID(), ownerID: ownerID, mode: mode)
      return true
    }

    mutating func finish() {
      self = .idle
    }
  }

  private struct DrawingTrialState {
    var step: ObservedDrawingTrialStep = .chooseIsolatedLinePlan
    var localPreLineBaseline: DisplayedFrame?
    var revealPosition: MachinePosition?
    var tipRegistrationRevisionID: LearningArtifactRevisionID?
    var observationRegion: PixelRect?
    var postLineFrame: DisplayedFrame?
    var lineStart: MachinePosition?
    var lineEnd: MachinePosition?
    var strokeEvidence: DrawingStrokeEvidence?
    var inkObservation: IsolatedInkObservation?
    var inkStatus = "no isolated-line observation yet"
    var lastTravelFeedSelection: TravelFeedSelection?
    var assessment: DrawingTrialAssessment?
    var comparisonReviewIsPinned = false
    var comparisonAttemptHistories:
      [AttemptCompatibility: ExerciseAttemptHistory<DrawingTrialAssessment>] = [:]
    var group: AttemptGroupIdentity

    init(source: OperatorFrameMode) {
      group = Self.newGroup(for: source)
    }

    static func newGroup(for source: OperatorFrameMode) -> AttemptGroupIdentity {
      AttemptGroupIdentity(
        rawValue: source == .simulated
          ? "simulated-\(UUID().uuidString.lowercased())"
          : UUID().uuidString.lowercased()
      )
    }

    mutating func rewind(from rewindStep: ObservedDrawingTrialStep, source: OperatorFrameMode) {
      if rewindStep == .chooseIsolatedLinePlan {
        lineStart = nil
        lineEnd = nil
        group = Self.newGroup(for: source)
      }

      if rewindStep.rawValue <= ObservedDrawingTrialStep.captureLocalPreLineBaseline.rawValue {
        localPreLineBaseline = nil
      }
      if rewindStep.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue {
        strokeEvidence = nil
      }
      if rewindStep.rawValue <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue {
        postLineFrame = nil
        inkObservation = nil
        inkStatus = "no isolated-line observation yet"
        comparisonReviewIsPinned = false
      }
      assessment = nil
      comparisonAttemptHistories = [:]
      lastTravelFeedSelection = nil
      step = rewindStep
    }
  }

  private struct DrawingStudioState {
    var selectedCatalogItemID: DrawingCatalogEntryID = .square
    var uniformScale = 0.25
    var rotationDegrees = 0.0
    var machineCenter: Point2<MachineSpace>?
    var placementID = UUID()
    var evidenceRole: DrawingTrialEvidenceRole = .ordinaryDrawing
    var program: DrawingProgram?
    var plan: ExecutionPlanRevision?
    var planningError: String?
    var baselineFrame: DisplayedFrame?
    var postFrame: DisplayedFrame?
    var activeStopCapabilityID: ContextualStopCapabilityID?
    var cancelRequested = false
    var runInProgress = false
    var terminalRequiresNewPlan = false
    var redrawBlockedPlanHashes: Set<PlotterModel.Digest> = []
    var runDetail: String?
    var lastRunRecord: DrawingRunEvidenceRecord?
    var reviewIsPinned = false
  }

  private struct ToolContactSelectionContext {
    let pendingEvidence: [PendingToolContactEvidence]
    let frame: DisplayedFrame
    let request: ActionSurfacePointSelectionRequest
  }

  private struct PenCapAppearanceSelectionContext {
    let frame: DisplayedFrame
    let request: ActionSurfacePointSelectionRequest
  }

  private struct PenCapAcceptedClickContinuationIdentity: Equatable, Sendable {
    let id: UUID
    let attemptID: ExerciseAttemptID
    let attemptMode: ExerciseAttemptMode
    let source: OperatorFrameMode
    let selection: PenCapAppearanceSelection
    let lifetimeGeneration: UInt64
  }

  private enum ToolContactSelectionState {
    case idle
    case collecting(ToolContactSelectionContext)

    var context: ToolContactSelectionContext? {
      switch self {
      case .idle: nil
      case .collecting(let context): context
      }
    }

    mutating func stage(_ context: ToolContactSelectionContext) {
      self = .collecting(context)
    }

    mutating func clear() {
      self = .idle
    }
  }

  private enum DrawingStrokeExecutionState: Hashable, Sendable {
    case notAdmitted
    case completedNaturally
    case possibleInk
  }

  private struct ActiveExplorationOperation: Hashable, Sendable {
    let step: ObservedDrawingTrialStep
    var strokeState: DrawingStrokeExecutionState
  }

  private struct PenCommandExecutionEvidence: Hashable, Sendable {
    let command: PenCommand
    let profile: PenActuationProfile
    let outcome: PenOutcome
    let timestamp: RuntimeTimestamp
  }

  /// One complete learning authority value. LIVE and SIMULATED use the same
  /// contract while retaining independent storage and independent lifetimes.
  private struct LearningSessionState {
    var boundaryTeachingState: BoundaryTeachingState = .idle
    var boundaryTeachingResultText = "Choose one side to begin."
    var selectedDiscoverySequenceID: DiscoverySequenceID = .penInteraction
    var discoveryTransactions: [DiscoverySequenceID: DiscoveryTransaction] = [:]
    var discoveryError: String?
    var pairedBoundaryProgress = PairedBoundaryProgress()
    var boundaryAttemptEvidenceByAttemptID: [ExerciseAttemptID: BoundarySideAttemptEvidence] = [:]
    var boundarySideAggregates: [BoundaryDirection: BoundarySideAggregate] = [:]
    var estimatedMachineCenter: EstimatedMachineCenter?
    var learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame?
    var centerArrivalPosition: MachinePosition?
    var centerArrivalRetryRequired = false
    var cameraCalibrationAnchorFrame: DisplayedFrame?
    var cameraCalibrationReferencePosition: MachinePosition?
    var cameraCalibrationReferenceCapAnchor: ToolCapAnchorEstimate?
    var proposedMachineCameraRegistration: MachineCameraRegistration?
    var machineCameraRegistration: MachineCameraRegistration?
    var tipCameraRegistration: TipCameraRegistration?
    var proposedTipCameraRegistration: TipCameraRegistration?
    var sparseTipCalibrationCoordinator = SparseTipCalibrationCoordinator()
    var toolContactSelection: ToolContactSelectionState = .idle
    var blacklistedToolContactLocations: Set<BlacklistedToolContactLocation> = []
    var explicitRegistrationCapAnchorEvidence: [MachineCameraCorrespondenceProvenance] = []
    var currentCameraCalibrationPhase: CurrentCameraCalibrationPhase?
    var currentCameraCalibrationFailure: CurrentCameraCalibrationFailure?
    var lastContextualStopAuditRecord: ContextualStopAuditRecord?
    var boundaryActivityRecords: [BoundaryActivityRecord] = []
    var lastProtocolPoseSettlement: ProtocolPoseSettlement?
    var explorationError: String?
    var drawingTrial: DrawingTrialState
    var learningArtifactGraph = LearningDependencyGraph()
    var penAttemptHistory: ExerciseAttemptHistory<PenInteractionAttemptEvidence>
    var penActuationProfile = PenActuationProfile.initialDefaults
    var penActuationDraft: PenActuationProfile?
    var lastPenExecutionByCommand: [PenCommand: PenCommandExecutionEvidence] = [:]
    var pendingPenUpPositions: [MachinePosition?] = []
    var pendingPenUpSpindleValues: [Int] = []
    var pendingPenUpControllerOutcomes: [PenOutcome?] = []
    var pendingPenUpTimestamps: [RuntimeTimestamp] = []
    var pendingPenDownPositions: [MachinePosition?] = []
    var pendingPenDownSpindleValues: [Int] = []
    var pendingPenDownControllerOutcomes: [PenOutcome?] = []
    var pendingPenDownTimestamps: [RuntimeTimestamp] = []
    var boundaryAttemptHistories:
      [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<
        BoundarySideAttemptEvidence
      >]] = [:]
    var exerciseAttempt: ExerciseAttemptLifecycle = .idle
    var restartableExerciseItemID: LearningPathItemID?
    var acceptedArtifactCheckpointStatus: AcceptedArtifactCheckpointStatus = .unavailable
    var paperCoverageObservation: PaperCoverageObservation?
    var drawingReadinessAssessment: DrawingReadinessAssessment?
    var drawingStudio = DrawingStudioState()
    var parkedAcceptedMachineArtifactCheckpoint: AcceptedMachineArtifactCheckpoint?
    var acceptedLearningPathCheckpoint: AcceptedLearningPathCheckpoint?
    var pendingMachineCameraCheckpoint: AcceptedMachineCameraCheckpoint?
    var acceptedStageFourCheckpoint: AcceptedStageFourCheckpoint?
    var quarantinedTipCalibrationCheckpoint: AcceptedTipCalibrationCheckpoint?
    var controllerPoseApplicability: ControllerPoseApplicability = .currentSession
    var learningAuthorityError: String?
    var selectedBoundaryDirection: BoundaryDirection = .positiveX
    var selectedLineDirection: BoundaryDirection = .positiveX
    var acceptedAttemptSequence: UInt64 = 0
    var controllerSessionID = UUID()
    var explorationCoordinateRevision: UInt64 = 0
    var explorationPaperInstanceRevision: UUID
    var explorationPaperContactPlaneRevision: UUID

    init(
      source: OperatorFrameMode,
      paperInstanceRevision: UUID,
      paperContactPlaneRevision: UUID
    ) {
      let simulated = source == .simulated
      penAttemptHistory = try! ExerciseAttemptHistory(
        compatibility: AttemptCompatibility(
          cameraConfigurationID: nil,
          coordinateSpace: .currentState,
          units: .state,
          group: AttemptGroupIdentity(
            rawValue: simulated ? "simulated-pen-interaction" : "pen-interaction"
          ),
          algorithmRevision: simulated
            ? "simulated-typed-operator-pen-observation-v1"
            : "typed-operator-pen-observation-v1"
        )
      )
      drawingTrial = DrawingTrialState(source: source)
      explorationPaperInstanceRevision = paperInstanceRevision
      explorationPaperContactPlaneRevision = paperContactPlaneRevision
    }
  }

  private enum MotionPriors {
    static let stepMM = "50"
    static let feedMMPerMinute = "500"
    /// Finite GRBL wire segment used only for renewal under one logical owner.
    /// Reaching this distance is never a Boundary Discovery result.
    static let boundaryWireSegmentMM = 50.0
    static let boundaryFeedMMPerMinute = 500.0
  }

  struct MachineActions: Sendable {
    let select: @Sendable (MachineLinkDescriptor) async throws -> RunInterpreterSnapshot
    let snapshot: @Sendable () async -> RunInterpreterSnapshot?
    let requestPassiveProbe: @Sendable () async throws -> PassiveProbeResult
    let requestControllerAlarmClear: @Sendable () async -> ControllerAlarmClearOutcome
    let activateMotionGuard: @Sendable () async -> MotionGuardActivationOutcome
    let deactivateMotionGuard: @Sendable () async -> Void
    let beginRelativeJog: @Sendable (RelativeJogRequest) async -> RelativeJogAdmission
    let beginDrawingStroke: @Sendable (DrawingStrokeRequest) async -> DrawingStrokeAdmission
    let beginDrawingPlan: (@Sendable (DrawingPlanRequest) async -> DrawingPlanAdmission)?
    let requestPenActuation: @Sendable (PenCommand, PenActuationProfile) async -> PenOutcome
    let beginBoundaryMotion:
      @Sendable (BoundaryMotionRequest, BoundaryMotionRenewalPlanner?) async
        -> BoundaryMotionAdmission
    let requestJogCancel: @Sendable (JogCancelIntent) async -> JogCancelOutcome
    let disconnect: @Sendable () async -> Void

    init(
      select: @escaping @Sendable (MachineLinkDescriptor) async throws -> RunInterpreterSnapshot,
      snapshot: @escaping @Sendable () async -> RunInterpreterSnapshot?,
      requestPassiveProbe: @escaping @Sendable () async throws -> PassiveProbeResult,
      requestControllerAlarmClear: @escaping @Sendable () async -> ControllerAlarmClearOutcome,
      activateMotionGuard: @escaping @Sendable () async -> MotionGuardActivationOutcome,
      deactivateMotionGuard: @escaping @Sendable () async -> Void,
      beginRelativeJog: @escaping @Sendable (RelativeJogRequest) async -> RelativeJogAdmission,
      beginDrawingStroke: @escaping @Sendable (DrawingStrokeRequest) async
        -> DrawingStrokeAdmission,
      beginDrawingPlan: (
        @Sendable (DrawingPlanRequest) async
          -> DrawingPlanAdmission
      )? = nil,
      requestPenActuation: @escaping @Sendable (PenCommand, PenActuationProfile) async ->
        PenOutcome,
      beginBoundaryMotion: @escaping @Sendable (
        BoundaryMotionRequest, BoundaryMotionRenewalPlanner?
      ) async -> BoundaryMotionAdmission,
      requestJogCancel: @escaping @Sendable (JogCancelIntent) async -> JogCancelOutcome,
      disconnect: @escaping @Sendable () async -> Void
    ) {
      self.select = select
      self.snapshot = snapshot
      self.requestPassiveProbe = requestPassiveProbe
      self.requestControllerAlarmClear = requestControllerAlarmClear
      self.activateMotionGuard = activateMotionGuard
      self.deactivateMotionGuard = deactivateMotionGuard
      self.beginRelativeJog = beginRelativeJog
      self.beginDrawingStroke = beginDrawingStroke
      self.beginDrawingPlan = beginDrawingPlan
      self.requestPenActuation = requestPenActuation
      self.beginBoundaryMotion = beginBoundaryMotion
      self.requestJogCancel = requestJogCancel
      self.disconnect = disconnect
    }
  }

  struct AnnouncementActions: Sendable {
    let announce: @Sendable (String) async -> SpeechAnnouncementOutcome
    let cancelForShutdown: @Sendable () async -> Void
  }

  struct WorkflowTelemetryActions: Sendable {
    let record: @Sendable (WorkflowTelemetryEvent) async -> Void
  }

  struct AcceptedLearningPathCheckpointActions: Sendable {
    let load: @Sendable () -> AcceptedLearningPathCheckpointLoadResult
    let save: @Sendable (AcceptedLearningPathCheckpoint) throws -> Void
    let clear: @Sendable () throws -> Void
  }

  struct DrawingEvidenceActions: Sendable {
    let load: @Sendable () async -> DrawingRunEvidenceStoreLoadResult
    let append: @Sendable (DrawingRunEvidenceRecord) async throws -> DrawingRunEvidenceArchive
  }

  struct PaperCoverageActions: Sendable {
    let load: @Sendable () -> PaperCoverageObservation?
    let save: @Sendable (PaperCoverageObservation) throws -> Void
    let clear: @Sendable () -> Void
  }

  struct CameraActions: Sendable {
    let discover: @Sendable () async -> CameraCaptureSnapshot
    let select: @Sendable (CameraDeviceID) async throws -> CameraCaptureSnapshot
    let start: @Sendable () async -> CameraCaptureSnapshot
    let stop: @Sendable () async -> CameraCaptureSnapshot
    let restart: @Sendable () async -> CameraCaptureSnapshot
    let snapshot: @Sendable () async -> CameraCaptureSnapshot
    let frames: @Sendable () async -> AsyncStream<DisplayedFrame>
    let inspectWorkflowScene:
      @Sendable (UInt64, SceneFeatureSet, PixelRect?) async throws -> LiveSceneInspection?
    let captureFrame: @Sendable (UInt64) async throws -> DisplayedFrame?
    let setSceneAnalysisRegion: @Sendable (PixelRect?) async -> Void
    let setPenCapColor: @Sendable (PenCapColor) async -> Void
    let setAutomaticInspection:
      @Sendable (VisionAnalysisCadence?, SceneFeatureSet) async
        -> PlotterSceneAnalysisSnapshot
    let analysisUpdates: @Sendable () async -> AsyncStream<PlotterSceneAnalysisSnapshot>
    let observeIsolatedInk:
      @Sendable (IsolatedInkObservationRequest) async
        -> IsolatedInkObservationOutcome
    let observePlannedDrawingInk:
      (
        @Sendable (PlannedDrawingObservationRequest) async
          -> PlannedDrawingObservationOutcome
      )?

    init(
      discover: @escaping @Sendable () async -> CameraCaptureSnapshot,
      select: @escaping @Sendable (CameraDeviceID) async throws -> CameraCaptureSnapshot,
      start: @escaping @Sendable () async -> CameraCaptureSnapshot,
      stop: @escaping @Sendable () async -> CameraCaptureSnapshot,
      restart: @escaping @Sendable () async -> CameraCaptureSnapshot,
      snapshot: @escaping @Sendable () async -> CameraCaptureSnapshot,
      frames: @escaping @Sendable () async -> AsyncStream<DisplayedFrame>,
      inspectWorkflowScene: @escaping @Sendable (
        UInt64, SceneFeatureSet, PixelRect?
      ) async throws -> LiveSceneInspection?,
      captureFrame: @escaping @Sendable (UInt64) async throws -> DisplayedFrame?,
      setSceneAnalysisRegion: @escaping @Sendable (PixelRect?) async -> Void,
      setPenCapColor: @escaping @Sendable (PenCapColor) async -> Void,
      setAutomaticInspection: @escaping @Sendable (
        VisionAnalysisCadence?, SceneFeatureSet
      ) async -> PlotterSceneAnalysisSnapshot,
      analysisUpdates: @escaping @Sendable () async -> AsyncStream<PlotterSceneAnalysisSnapshot>,
      observeIsolatedInk: @escaping @Sendable (IsolatedInkObservationRequest) async
        -> IsolatedInkObservationOutcome,
      observePlannedDrawingInk: (
        @Sendable (PlannedDrawingObservationRequest) async
          -> PlannedDrawingObservationOutcome
      )? = nil
    ) {
      self.discover = discover
      self.select = select
      self.start = start
      self.stop = stop
      self.restart = restart
      self.snapshot = snapshot
      self.frames = frames
      self.inspectWorkflowScene = inspectWorkflowScene
      self.captureFrame = captureFrame
      self.setSceneAnalysisRegion = setSceneAnalysisRegion
      self.setPenCapColor = setPenCapColor
      self.setAutomaticInspection = setAutomaticInspection
      self.analysisUpdates = analysisUpdates
      self.observeIsolatedInk = observeIsolatedInk
      self.observePlannedDrawingInk = observePlannedDrawingInk
    }
  }

  private(set) var livePenCapAppearanceSelection: PenCapAppearanceSelection?
  private(set) var simulatedPenCapAppearanceSelection: PenCapAppearanceSelection?
  private(set) var persistedPenCapAppearanceLoadState: PersistedPenCapAppearanceLoadState
  var penCapAppearanceSelection: PenCapAppearanceSelection? {
    frameMode == .live ? livePenCapAppearanceSelection : simulatedPenCapAppearanceSelection
  }
  private var livePenCapColor: PenCapColor? { livePenCapAppearanceSelection?.color }
  private(set) var overlayPreferenceState: OverlayPreferenceState
  private(set) var visionAnalysisCadence = VisionAnalysisCadence.twoFPS
  private(set) var videoAnalysisRegionLock: VideoAnalysisRegionLock?
  var frameMode: OperatorFrameMode = .live
  // String-backed numeric inputs preserve partially typed values and keep X/Y
  // independent. Runtime value constructors and MachineController own validity.
  var xStepText = MotionPriors.stepMM
  var yStepText = MotionPriors.stepMM
  var feedText = MotionPriors.feedMMPerMinute
  private(set) var learningIsEnabled = true
  private(set) var drawingStudioIsPresented = false

  private(set) var serialDevices: [MachineLinkDescriptor] = []
  private(set) var selectedSerialDevice: MachineLinkDescriptor?
  private(set) var passiveProbeResult: PassiveProbeResult?
  private(set) var machineSnapshot: RunInterpreterSnapshot?
  private(set) var machineError: String?
  private(set) var controllerAlarmClearInProgress = false
  private(set) var controllerConnectionActionInProgress = false
  private(set) var passiveProbeInProgress = false
  private(set) var jogRequestInProgress = false
  private(set) var penRequestInProgress = false
  @ObservationIgnored private var pendingPenSetpointCommand: PenCommand?
  @ObservationIgnored private var penSetpointActuationTask: Task<Void, Never>?
  private var lastManualMotionWasDrawing = false
  private var lastManualMotionMayHaveProducedInk = false
  private(set) var frameModeSwitchInProgress = false
  private(set) var motionAuthorizationActionInProgress = false
  private(set) var lastMotionGuardActivationText = "not activated"
  private(set) var lastContextualStopAuditRecord: ContextualStopAuditRecord? {
    get { activeLearningSession.lastContextualStopAuditRecord }
    set { activeLearningSession.lastContextualStopAuditRecord = newValue }
  }
  private(set) var boundaryActivityRecords: [BoundaryActivityRecord] {
    get { activeLearningSession.boundaryActivityRecords }
    set { activeLearningSession.boundaryActivityRecords = newValue }
  }

  private(set) var cameraSnapshot: CameraCaptureSnapshot?
  private(set) var displayedFrame: DisplayedFrame? {
    didSet {
      let isAvailable = displayedFrame != nil
      if displayedFrameAvailable != isAvailable {
        displayedFrameAvailable = isAvailable
      }
    }
  }
  private(set) var displayedFrameAvailable = false
  @ObservationIgnored private(set) var latestLiveCameraFrame: DisplayedFrame?
  private(set) var overlayResultChannels = OverlayResultChannels()
  private(set) var cameraError: String?
  private(set) var visionError: String?
  private(set) var scopedVisionAnalysisActive = false
  private(set) var exclusiveWorkflowVisionRequestCount = 0
  private(set) var visionAnalysisSnapshot: PlotterSceneAnalysisSnapshot = .stopped
  private(set) var lastSceneMeasurement: PlotterSceneMeasurement?
  private(set) var simulatorEvidenceLabel = "SIMULATED — NOT PHYSICAL EVIDENCE"
  private(set) var simulatorPenState: PenState = .unknown
  private(set) var simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
  private(set) var simulatedLearningSnapshot: SimulatedLearningSnapshot?
  private(set) var simulatedAnnotations: [SimulatedLearningAnnotation] = []
  private(set) var simulatedViewportID: SimulatedCameraViewportID?
  var simulatedAnnotationsAreVisible = true
  private var liveLearningSession: LearningSessionState
  private var simulatedLearningSession: LearningSessionState
  private var activeLearningSession: LearningSessionState {
    get { frameMode == .live ? liveLearningSession : simulatedLearningSession }
    set {
      if frameMode == .live {
        liveLearningSession = newValue
      } else {
        simulatedLearningSession = newValue
      }
    }
  }
  private(set) var boundaryTeachingState: BoundaryTeachingState {
    get { activeLearningSession.boundaryTeachingState }
    set { activeLearningSession.boundaryTeachingState = newValue }
  }
  private(set) var boundaryTeachingResultText: String {
    get { activeLearningSession.boundaryTeachingResultText }
    set { activeLearningSession.boundaryTeachingResultText = newValue }
  }
  var selectedDiscoverySequenceID: DiscoverySequenceID {
    get { activeLearningSession.selectedDiscoverySequenceID }
    set { activeLearningSession.selectedDiscoverySequenceID = newValue }
  }
  private(set) var discoveryTransactions: [DiscoverySequenceID: DiscoveryTransaction] {
    get { activeLearningSession.discoveryTransactions }
    set { activeLearningSession.discoveryTransactions = newValue }
  }
  private(set) var discoveryError: String? {
    get { activeLearningSession.discoveryError }
    set { activeLearningSession.discoveryError = newValue }
  }
  private(set) var pairedBoundaryProgress: PairedBoundaryProgress {
    get { activeLearningSession.pairedBoundaryProgress }
    set { activeLearningSession.pairedBoundaryProgress = newValue }
  }
  private(set) var boundaryAttemptEvidenceByAttemptID:
    [ExerciseAttemptID: BoundarySideAttemptEvidence]
  {
    get { activeLearningSession.boundaryAttemptEvidenceByAttemptID }
    set { activeLearningSession.boundaryAttemptEvidenceByAttemptID = newValue }
  }
  private(set) var boundarySideAggregates: [BoundaryDirection: BoundarySideAggregate] {
    get { activeLearningSession.boundarySideAggregates }
    set { activeLearningSession.boundarySideAggregates = newValue }
  }
  private(set) var estimatedMachineCenter: EstimatedMachineCenter? {
    get { activeLearningSession.estimatedMachineCenter }
    set { activeLearningSession.estimatedMachineCenter = newValue }
  }
  private(set) var learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame? {
    get { activeLearningSession.learnedLocalCoordinateFrame }
    set { activeLearningSession.learnedLocalCoordinateFrame = newValue }
  }
  private(set) var centerArrivalPosition: MachinePosition? {
    get { activeLearningSession.centerArrivalPosition }
    set { activeLearningSession.centerArrivalPosition = newValue }
  }
  private(set) var centerArrivalRetryRequired: Bool {
    get { activeLearningSession.centerArrivalRetryRequired }
    set { activeLearningSession.centerArrivalRetryRequired = newValue }
  }
  private(set) var cameraCalibrationAnchorFrame: DisplayedFrame? {
    get { activeLearningSession.cameraCalibrationAnchorFrame }
    set { activeLearningSession.cameraCalibrationAnchorFrame = newValue }
  }
  private(set) var cameraCalibrationReferencePosition: MachinePosition? {
    get { activeLearningSession.cameraCalibrationReferencePosition }
    set { activeLearningSession.cameraCalibrationReferencePosition = newValue }
  }
  private(set) var cameraCalibrationReferenceCapAnchor: ToolCapAnchorEstimate? {
    get { activeLearningSession.cameraCalibrationReferenceCapAnchor }
    set { activeLearningSession.cameraCalibrationReferenceCapAnchor = newValue }
  }
  private(set) var proposedMachineCameraRegistration: MachineCameraRegistration? {
    get { activeLearningSession.proposedMachineCameraRegistration }
    set { activeLearningSession.proposedMachineCameraRegistration = newValue }
  }
  private(set) var machineCameraRegistration: MachineCameraRegistration? {
    get { activeLearningSession.machineCameraRegistration }
    set { activeLearningSession.machineCameraRegistration = newValue }
  }
  private(set) var tipCameraRegistration: TipCameraRegistration? {
    get { activeLearningSession.tipCameraRegistration }
    set { activeLearningSession.tipCameraRegistration = newValue }
  }
  private(set) var proposedTipCameraRegistration: TipCameraRegistration? {
    get { activeLearningSession.proposedTipCameraRegistration }
    set { activeLearningSession.proposedTipCameraRegistration = newValue }
  }
  private(set) var sparseTipCalibrationCoordinator: SparseTipCalibrationCoordinator {
    get { activeLearningSession.sparseTipCalibrationCoordinator }
    set { activeLearningSession.sparseTipCalibrationCoordinator = newValue }
  }
  var frozenToolContactSelectionFrame: DisplayedFrame? {
    activeLearningSession.toolContactSelection.context?.frame
  }
  private var penCapAppearanceSelectionContext: PenCapAppearanceSelectionContext?
  var frozenPointSelectionFrame: DisplayedFrame? {
    penCapAppearanceSelectionContext?.frame ?? frozenToolContactSelectionFrame
  }
  private var pendingToolContactEvidence: [PendingToolContactEvidence] {
    activeLearningSession.toolContactSelection.context?.pendingEvidence
      ?? []
  }
  var toolContactPointSelectionRequest: ActionSurfacePointSelectionRequest? {
    activeLearningSession.toolContactSelection.context?.request
  }
  var pointSelectionRequest: ActionSurfacePointSelectionRequest? {
    penCapAppearanceSelectionContext?.request ?? toolContactPointSelectionRequest
  }
  var selectedToolContactPoints: [Point2<CameraPixelSpace>] {
    sparseTipCalibrationCoordinator.collectedClickPoints
  }
  private let machineGeometryIdentity: MachineGeometryIdentity
  private let toolAssemblyRevision: ToolAssemblyRevision
  private let penContactProfileRevision: PenContactProfileRevision
  private let cameraMountRevision: UUID
  private let cameraReframingRevision: UUID
  private(set) var blacklistedToolContactLocations: Set<BlacklistedToolContactLocation> {
    get { activeLearningSession.blacklistedToolContactLocations }
    set { activeLearningSession.blacklistedToolContactLocations = newValue }
  }
  private(set) var explicitRegistrationCapAnchorEvidence: [MachineCameraCorrespondenceProvenance] {
    get { activeLearningSession.explicitRegistrationCapAnchorEvidence }
    set { activeLearningSession.explicitRegistrationCapAnchorEvidence = newValue }
  }
  private(set) var currentCameraCalibrationPhase: CurrentCameraCalibrationPhase? {
    get { activeLearningSession.currentCameraCalibrationPhase }
    set { activeLearningSession.currentCameraCalibrationPhase = newValue }
  }
  private var currentCameraCalibrationFailure: CurrentCameraCalibrationFailure? {
    get { activeLearningSession.currentCameraCalibrationFailure }
    set { activeLearningSession.currentCameraCalibrationFailure = newValue }
  }
  private(set) var localPreLineBaseline: DisplayedFrame? {
    get { activeLearningSession.drawingTrial.localPreLineBaseline }
    set { activeLearningSession.drawingTrial.localPreLineBaseline = newValue }
  }
  private(set) var drawingTrialRevealPosition: MachinePosition? {
    get { activeLearningSession.drawingTrial.revealPosition }
    set { activeLearningSession.drawingTrial.revealPosition = newValue }
  }
  private(set) var drawingTrialTipRegistrationRevisionID: LearningArtifactRevisionID? {
    get { activeLearningSession.drawingTrial.tipRegistrationRevisionID }
    set { activeLearningSession.drawingTrial.tipRegistrationRevisionID = newValue }
  }
  private(set) var drawingTrialObservationRegion: PixelRect? {
    get { activeLearningSession.drawingTrial.observationRegion }
    set { activeLearningSession.drawingTrial.observationRegion = newValue }
  }
  private(set) var lastProtocolPoseSettlement: ProtocolPoseSettlement? {
    get { activeLearningSession.lastProtocolPoseSettlement }
    set { activeLearningSession.lastProtocolPoseSettlement = newValue }
  }
  private(set) var explorationError: String? {
    get { activeLearningSession.explorationError }
    set { activeLearningSession.explorationError = newValue }
  }
  private(set) var explorationPostLineFrame: DisplayedFrame? {
    get { activeLearningSession.drawingTrial.postLineFrame }
    set { activeLearningSession.drawingTrial.postLineFrame = newValue }
  }
  private(set) var drawingTrialLineStart: MachinePosition? {
    get { activeLearningSession.drawingTrial.lineStart }
    set { activeLearningSession.drawingTrial.lineStart = newValue }
  }
  private(set) var drawingTrialLineEnd: MachinePosition? {
    get { activeLearningSession.drawingTrial.lineEnd }
    set { activeLearningSession.drawingTrial.lineEnd = newValue }
  }
  private(set) var drawingTrialStrokeEvidence: DrawingStrokeEvidence? {
    get { activeLearningSession.drawingTrial.strokeEvidence }
    set { activeLearningSession.drawingTrial.strokeEvidence = newValue }
  }
  private(set) var lastInkObservation: IsolatedInkObservation? {
    get { activeLearningSession.drawingTrial.inkObservation }
    set { activeLearningSession.drawingTrial.inkObservation = newValue }
  }
  private(set) var explorationInkStatus: String {
    get { activeLearningSession.drawingTrial.inkStatus }
    set { activeLearningSession.drawingTrial.inkStatus = newValue }
  }
  private var activeExplorationOperation: ActiveExplorationOperation?
  private(set) var lastAnnouncementResultText = "No announcement has run."
  private(set) var lastTravelFeedSelection: TravelFeedSelection? {
    get { activeLearningSession.drawingTrial.lastTravelFeedSelection }
    set { activeLearningSession.drawingTrial.lastTravelFeedSelection = newValue }
  }
  private(set) var drawingTrialAssessment: DrawingTrialAssessment? {
    get { activeLearningSession.drawingTrial.assessment }
    set { activeLearningSession.drawingTrial.assessment = newValue }
  }
  private(set) var learningArtifactGraph: LearningDependencyGraph {
    get { activeLearningSession.learningArtifactGraph }
    set { activeLearningSession.learningArtifactGraph = newValue }
  }
  private(set) var penAttemptHistory: ExerciseAttemptHistory<PenInteractionAttemptEvidence> {
    get { activeLearningSession.penAttemptHistory }
    set { activeLearningSession.penAttemptHistory = newValue }
  }
  private(set) var currentPenActuationProfile: PenActuationProfile {
    get { activeLearningSession.penActuationProfile }
    set { activeLearningSession.penActuationProfile = newValue }
  }
  private var effectivePenActuationProfile: PenActuationProfile {
    activeLearningSession.penActuationDraft ?? currentPenActuationProfile
  }
  private(set) var boundaryAttemptHistories:
    [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<BoundarySideAttemptEvidence>]]
  {
    get { activeLearningSession.boundaryAttemptHistories }
    set { activeLearningSession.boundaryAttemptHistories = newValue }
  }
  private(set) var comparisonAttemptHistories:
    [AttemptCompatibility: ExerciseAttemptHistory<DrawingTrialAssessment>]
  {
    get { activeLearningSession.drawingTrial.comparisonAttemptHistories }
    set { activeLearningSession.drawingTrial.comparisonAttemptHistories = newValue }
  }
  var activeExerciseAttemptID: ExerciseAttemptID? {
    activeLearningSession.exerciseAttempt.id
  }
  var activeExerciseAttemptOwnerID: LearningPathItemID? {
    activeLearningSession.exerciseAttempt.ownerID
  }
  private(set) var restartableExerciseItemID: LearningPathItemID? {
    get { activeLearningSession.restartableExerciseItemID }
    set { activeLearningSession.restartableExerciseItemID = newValue }
  }
  private(set) var acceptedArtifactCheckpointStatus: AcceptedArtifactCheckpointStatus {
    get { activeLearningSession.acceptedArtifactCheckpointStatus }
    set { activeLearningSession.acceptedArtifactCheckpointStatus = newValue }
  }
  private(set) var quarantinedTipCalibrationCheckpoint: AcceptedTipCalibrationCheckpoint? {
    get { activeLearningSession.quarantinedTipCalibrationCheckpoint }
    set { activeLearningSession.quarantinedTipCalibrationCheckpoint = newValue }
  }
  private var acceptedLearningPathCheckpoint: AcceptedLearningPathCheckpoint? {
    get { activeLearningSession.acceptedLearningPathCheckpoint }
    set { activeLearningSession.acceptedLearningPathCheckpoint = newValue }
  }
  private var pendingMachineCameraCheckpoint: AcceptedMachineCameraCheckpoint? {
    get { activeLearningSession.pendingMachineCameraCheckpoint }
    set { activeLearningSession.pendingMachineCameraCheckpoint = newValue }
  }
  private var acceptedStageFourCheckpoint: AcceptedStageFourCheckpoint? {
    get { activeLearningSession.acceptedStageFourCheckpoint }
    set { activeLearningSession.acceptedStageFourCheckpoint = newValue }
  }
  private(set) var controllerPoseApplicability: ControllerPoseApplicability {
    get { activeLearningSession.controllerPoseApplicability }
    set { activeLearningSession.controllerPoseApplicability = newValue }
  }
  private(set) var learningAuthorityError: String? {
    get { activeLearningSession.learningAuthorityError }
    set { activeLearningSession.learningAuthorityError = newValue }
  }

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let persistPenCapAppearanceSelection:
    @Sendable (PenCapAppearanceSelection?) -> Void
  @ObservationIgnored private let announcementActions: AnnouncementActions?
  /// These ports are capabilities of the LIVE learning session only. The
  /// active accessors deliberately return nil for SIMULATED before any
  /// workflow can load, save, or clear physical durable authority.
  @ObservationIgnored private let liveAcceptedLearningPathCheckpointActions:
    AcceptedLearningPathCheckpointActions?
  @ObservationIgnored private let liveDrawingEvidenceActions: DrawingEvidenceActions?
  @ObservationIgnored private let livePaperCoverageActions: PaperCoverageActions?
  private var drawingEvidenceArchive = DrawingRunEvidenceArchive()
  private(set) var drawingEvidenceError: String?
  private var activeAcceptedLearningPathCheckpointActions:
    AcceptedLearningPathCheckpointActions?
  {
    frameMode == .live ? liveAcceptedLearningPathCheckpointActions : nil
  }
  @ObservationIgnored private let workflowTelemetryActions: WorkflowTelemetryActions?
  @ObservationIgnored private let simulatedLearningRuntime: SimulatedLearningRuntime
  @ObservationIgnored private var simulatedExecutionPacing: any SimulatedLearningExecutionPacing
  @ObservationIgnored private let serialDeviceDiscovery: @Sendable () -> [MachineLinkDescriptor]
  @ObservationIgnored private let persistSelectedSerialIdentifier: @Sendable (String) -> Void
  @ObservationIgnored private let persistOverlayPreference:
    @Sendable (Set<UserSceneOverlay>) -> Void
  @ObservationIgnored private let nowNanoseconds: @Sendable () -> UInt64
  @ObservationIgnored private var boundaryAtomicCommitFailurePoints:
    Set<BoundaryAtomicCommitFailurePoint>
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var visionUpdateTask: Task<Void, Never>?
  @ObservationIgnored private var penCapAcceptedClickContinuationTask: Task<Void, Never>?
  @ObservationIgnored private var penCapAcceptedClickContinuationIdentity:
    PenCapAcceptedClickContinuationIdentity?
  private var controllerSessionID: UUID {
    get { activeLearningSession.controllerSessionID }
    set { activeLearningSession.controllerSessionID = newValue }
  }
  private var explorationCoordinateRevision: UInt64 {
    get { activeLearningSession.explorationCoordinateRevision }
    set { activeLearningSession.explorationCoordinateRevision = newValue }
  }
  private var explorationPaperInstanceRevision: UUID {
    get { activeLearningSession.explorationPaperInstanceRevision }
    set { activeLearningSession.explorationPaperInstanceRevision = newValue }
  }
  private var explorationPaperContactPlaneRevision: UUID {
    get { activeLearningSession.explorationPaperContactPlaneRevision }
    set { activeLearningSession.explorationPaperContactPlaneRevision = newValue }
  }
  @ObservationIgnored private let persistPaperInstanceRevision:
    @Sendable (PaperInstanceRevision) -> Void
  @ObservationIgnored private let persistPaperContactPlaneRevision:
    @Sendable (PaperContactPlaneRevision) -> Void
  @ObservationIgnored private var boundaryMotionTask: Task<Void, Never>?
  @ObservationIgnored private var currentCameraCalibrationTask: Task<Void, Never>?
  @ObservationIgnored private var activeStoppableOperation: ActiveStoppableOperation?
  private var activeStopTarget: ContextualStopTarget? { activeStoppableOperation?.target }
  private var stopDispositionLatch: ContextualStopDispositionLatch? {
    activeStoppableOperation?.state.latch
  }
  private var jogCancelRequestInProgress: Bool {
    activeStoppableOperation?.state.cancellationRequestInProgress == true
  }
  @ObservationIgnored private var pendingBoundaryFinalPositions:
    [ExerciseAttemptID: MachinePosition] = [:]
  @ObservationIgnored private var pendingBoundaryOwnerIDs:
    [ExerciseAttemptID: BoundaryMotionOwnerID] = [:]
  @ObservationIgnored private var pendingBoundaryStopCapabilities:
    [ExerciseAttemptID: ContextualStopCapabilityID] = [:]
  @ObservationIgnored private var rememberedSerialDeviceIdentifier: String?
  @ObservationIgnored private var hasShutdown = false
  @ObservationIgnored private var lifetimeGeneration: UInt64 = 0
  @ObservationIgnored private var activeHardwareIntentCount = 0
  @ObservationIgnored private var intentDrainWaiters: [CheckedContinuation<Void, Never>] = []
  private var activeExerciseAttemptMode: ExerciseAttemptMode? {
    activeLearningSession.exerciseAttempt.mode
  }
  private var acceptedAttemptSequence: UInt64 {
    get { activeLearningSession.acceptedAttemptSequence }
    set { activeLearningSession.acceptedAttemptSequence = newValue }
  }
  @ObservationIgnored private var lastSimulatedProtocolCaptureNanoseconds: UInt64 = 0
  private var currentDrawingTrialGroup: AttemptGroupIdentity {
    get { activeLearningSession.drawingTrial.group }
    set { activeLearningSession.drawingTrial.group = newValue }
  }
  private var parkedAcceptedMachineArtifactCheckpoint: AcceptedMachineArtifactCheckpoint? {
    get { activeLearningSession.parkedAcceptedMachineArtifactCheckpoint }
    set { activeLearningSession.parkedAcceptedMachineArtifactCheckpoint = newValue }
  }

  init(
    machineActions: MachineActions? = nil,
    cameraActions: CameraActions? = nil,
    announcementActions: AnnouncementActions? = nil,
    acceptedLearningPathCheckpointActions: AcceptedLearningPathCheckpointActions? = nil,
    drawingEvidenceActions: DrawingEvidenceActions? = nil,
    paperCoverageActions: PaperCoverageActions? = nil,
    tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityState = .ephemeral(),
    persistPaperInstanceRevision: @escaping @Sendable (PaperInstanceRevision) -> Void = { _ in },
    persistPaperContactPlaneRevision: @escaping @Sendable (PaperContactPlaneRevision) -> Void = {
      _ in
    },
    workflowTelemetryActions: WorkflowTelemetryActions? = nil,
    simulatedLearningRuntime: SimulatedLearningRuntime = SimulatedLearningRuntime(),
    simulatedExecutionPacing: any SimulatedLearningExecutionPacing =
      SimulatedLearningInteractivePacing(),
    serialDevices: [MachineLinkDescriptor] = [],
    serialDeviceDiscovery: @escaping @Sendable () -> [MachineLinkDescriptor] = {
      SerialPortDiscovery.discover()
    },
    loadSelectedSerialIdentifier: @escaping @Sendable () -> String? = {
      UserDefaults.standard.string(forKey: "AdaptivePlotter.selectedSerialDeviceIdentifier")
    },
    persistSelectedSerialIdentifier: @escaping @Sendable (String) -> Void = { identifier in
      UserDefaults.standard.set(
        identifier, forKey: "AdaptivePlotter.selectedSerialDeviceIdentifier")
    },
    loadPenCapAppearanceSelection: @escaping @Sendable () -> PenCapAppearanceSelection? = {
      guard
        let data = UserDefaults.standard.data(
          forKey: "AdaptivePlotter.penCapAppearanceSelection")
      else { return nil }
      return try? JSONDecoder().decode(PenCapAppearanceSelection.self, from: data)
    },
    persistPenCapAppearanceSelection:
      @escaping @Sendable (PenCapAppearanceSelection?) -> Void = { selection in
        if let selection, let data = try? JSONEncoder().encode(selection) {
          UserDefaults.standard.set(data, forKey: "AdaptivePlotter.penCapAppearanceSelection")
        } else {
          UserDefaults.standard.removeObject(forKey: "AdaptivePlotter.penCapAppearanceSelection")
        }
      },
    loadOverlayPreference: @escaping @Sendable () -> Set<UserSceneOverlay>? = {
      guard
        let values = UserDefaults.standard.stringArray(
          forKey: "AdaptivePlotter.userSceneOverlays")
      else { return nil }
      return Set(values.compactMap(UserSceneOverlay.init(rawValue:)))
    },
    persistOverlayPreference: @escaping @Sendable (Set<UserSceneOverlay>) -> Void = { values in
      UserDefaults.standard.set(
        values.map(\.rawValue).sorted(),
        forKey: "AdaptivePlotter.userSceneOverlays"
      )
    },
    nowNanoseconds: @escaping @Sendable () -> UInt64 = {
      UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    },
    boundaryAtomicCommitFailurePoints: Set<BoundaryAtomicCommitFailurePoint> = []
  ) {
    overlayPreferenceState = .loaded(loadOverlayPreference())
    liveLearningSession = LearningSessionState(
      source: .live,
      paperInstanceRevision: tipCalibrationSemanticIdentities.paperInstance.rawValue,
      paperContactPlaneRevision: tipCalibrationSemanticIdentities.paperContactPlane.rawValue
    )
    simulatedLearningSession = LearningSessionState(
      source: .simulated,
      paperInstanceRevision: tipCalibrationSemanticIdentities.paperInstance.rawValue,
      paperContactPlaneRevision: tipCalibrationSemanticIdentities.paperContactPlane.rawValue
    )
    self.simulatedExecutionPacing = simulatedExecutionPacing
    self.machineActions = machineActions
    self.cameraActions = cameraActions
    if let loadedSelection = loadPenCapAppearanceSelection() {
      if let reason = loadedSelection.persistedLiveRejectionReason {
        livePenCapAppearanceSelection = nil
        persistedPenCapAppearanceLoadState = .refused(reason)
      } else {
        livePenCapAppearanceSelection = loadedSelection
        persistedPenCapAppearanceLoadState = .accepted
      }
    } else {
      livePenCapAppearanceSelection = nil
      persistedPenCapAppearanceLoadState = .absent
    }
    simulatedPenCapAppearanceSelection = nil
    self.persistPenCapAppearanceSelection = persistPenCapAppearanceSelection
    self.announcementActions = announcementActions
    liveAcceptedLearningPathCheckpointActions = acceptedLearningPathCheckpointActions
    liveDrawingEvidenceActions = drawingEvidenceActions
    livePaperCoverageActions = paperCoverageActions
    machineGeometryIdentity = tipCalibrationSemanticIdentities.machineGeometry
    toolAssemblyRevision = tipCalibrationSemanticIdentities.toolAssembly
    penContactProfileRevision = tipCalibrationSemanticIdentities.penContactProfile
    cameraMountRevision = tipCalibrationSemanticIdentities.cameraMountRevision
    cameraReframingRevision = tipCalibrationSemanticIdentities.cameraReframingRevision
    self.persistPaperInstanceRevision = persistPaperInstanceRevision
    self.persistPaperContactPlaneRevision = persistPaperContactPlaneRevision
    self.workflowTelemetryActions = workflowTelemetryActions
    self.simulatedLearningRuntime = simulatedLearningRuntime
    self.serialDevices = serialDevices
    self.serialDeviceDiscovery = serialDeviceDiscovery
    self.persistSelectedSerialIdentifier = persistSelectedSerialIdentifier
    self.persistOverlayPreference = persistOverlayPreference
    rememberedSerialDeviceIdentifier = loadSelectedSerialIdentifier()
    self.nowNanoseconds = nowNanoseconds
    self.boundaryAtomicCommitFailurePoints = boundaryAtomicCommitFailurePoints
    liveLearningSession.paperCoverageObservation = paperCoverageActions?.load()
    if let rememberedSerialDeviceIdentifier {
      selectedSerialDevice = serialDevices.first {
        $0.identifier == rememberedSerialDeviceIdentifier
      }
    }
    if let acceptedLearningPathCheckpointActions {
      switch acceptedLearningPathCheckpointActions.load() {
      case .absent:
        acceptedArtifactCheckpointStatus = .unavailable
      case .loaded(let checkpoint):
        if checkpoint.semanticIdentity == tipCalibrationSemanticIdentities.learningPathIdentity {
          acceptedLearningPathCheckpoint = checkpoint
          parkedAcceptedMachineArtifactCheckpoint = checkpoint.machineArtifacts
          pendingMachineCameraCheckpoint = checkpoint.machineCamera
          quarantinedTipCalibrationCheckpoint = checkpoint.tipCalibration
          acceptedStageFourCheckpoint = checkpoint.stageFour
          acceptedArtifactCheckpointStatus = checkpoint.machineArtifacts.map {
            .quarantined(sideCount: $0.boundarySideAggregates.count)
          } ?? .unavailable
          restoreAcceptedPenInteractionCheckpoint(checkpoint.penInteraction)
        } else {
          acceptedArtifactCheckpointStatus = .incompatible(
            "Saved machine, tool, paper-plane, or camera-mount identity changed."
          )
        }
      case .rejected(let reason):
        acceptedArtifactCheckpointStatus = .rejected(reason)
      }
    }
  }

  func replaceBoundaryAtomicCommitFailurePointsForTesting(
    _ points: Set<BoundaryAtomicCommitFailurePoint>
  ) {
    boundaryAtomicCommitFailurePoints = points
  }

  func replaceSimulatedExecutionPacingForTesting(
    _ pacing: any SimulatedLearningExecutionPacing
  ) {
    simulatedExecutionPacing = pacing
  }

  func replaceSimulatedTipCalibrationCheckpointForTesting(
    _ checkpoint: AcceptedTipCalibrationCheckpoint?
  ) {
    guard frameMode == .simulated else { return }
    quarantinedTipCalibrationCheckpoint = checkpoint
  }

  var actionSurfacePresentation: ActionSurfacePresentation {
    let surfaceFrame =
      frozenPointSelectionFrame
      ?? (activeLearningSession.drawingTrial.comparisonReviewIsPinned
        ? explorationPostLineFrame
        : nil)
      ?? (activeLearningSession.drawingStudio.reviewIsPinned
        ? activeLearningSession.drawingStudio.postFrame
        : nil)
      ?? displayedFrame
    let overlayComposition = OverlayPresentationComposer.compose(
      preference: overlayPreferenceState,
      channels: overlayResultChannels,
      displayedFrame: surfaceFrame,
      sceneState: visionAnalysisSnapshot,
      sceneIsAvailable: sceneOverlayIsAvailable,
      workflowVisionIsExclusive: exclusiveWorkflowVisionRequestCount > 0
    )
    let fittedRegion = surfaceFrame.flatMap(learnedBoundsPresentationRegion)
    let viewportContext = surfaceFrame.map {
      ActionSurfaceViewportContext(
        source: $0.source,
        cameraConfigurationID: $0.frame.cameraConfigurationID,
        fittedRegion: fittedRegion,
        preferredInitialZoom: 0,
        presentationRevisionToken: machineCameraRegistration.map {
          "machine-cap-\($0.correspondenceFrameIDs.map(\.rawValue).sorted().joined(separator: "-"))"
        } ?? "post-boundary-presentation"
      )
    }
    let tipPresentation: ActionSurfaceTipPresentation =
      if let toolContactPointSelectionRequest {
        .collectingClicks(
          prompt: toolContactPointSelectionRequest.prompt,
          clicks: sparseTipCalibrationCoordinator.collectedClickPoints
        )
      } else if let pointSelectionRequest {
        .awaitingClick(pointSelectionRequest.prompt)
      } else if tipCameraRegistration != nil {
        .calibrated(prediction: nil)
      } else {
        .notCalibrated
      }
    return ActionSurfacePresentation(
      displayedFrame: surfaceFrame,
      overlays: overlayComposition.overlays
        + (surfaceFrame.map(learnedDrawingOverlays) ?? [])
        + (surfaceFrame.map(drawingTrialPredictionOverlays) ?? []),
      simulatedAnnotations: simulatedAnnotations,
      simulatedViewportID: simulatedViewportID,
      simulatedAnnotationsAreVisible: simulatedAnnotationsAreVisible,
      viewportContext: viewportContext,
      analysisRegionIsLocked: surfaceFrame.map {
        videoAnalysisRegionLock?.matches($0) == true
      } ?? false,
      analyzedOverlayFrame: overlayComposition.analyzedFrame,
      pointSelectionRequest: pointSelectionRequest,
      tipPresentation: tipPresentation,
      completedComparisonReview: completedComparisonReviewPresentation,
      drawingStudioCanvas: drawingStudioIsPresented ? drawingStudioPresentation.canvas : nil
    )
  }

  var currentPaperRevisionContext: PaperRevisionContext {
    PaperRevisionContext(
      instance: PaperInstanceRevision(rawValue: explorationPaperInstanceRevision),
      contactPlane: PaperContactPlaneRevision(
        rawValue: explorationPaperContactPlaneRevision
      )
    )
  }

  private var currentPaperCoverageObservation: PaperCoverageObservation? {
    get { activeLearningSession.paperCoverageObservation }
    set { activeLearningSession.paperCoverageObservation = newValue }
  }

  var paperCoverageIsCurrent: Bool {
    guard let coverage = currentPaperCoverageObservation,
      coverage.paper == currentPaperRevisionContext,
      let frame = displayedFrame,
      coverage.source == frame.source,
      coverage.frame.cameraConfigurationID == frame.frame.cameraConfigurationID
    else { return false }
    return true
  }

  var interactiveLearningIsComplete: Bool {
    if drawingTrialAssessment == .predictionObserved { return true }
    guard let registration = tipCameraRegistration else { return false }
    return drawingEvidenceArchive.records.contains { record in
      record.role == .evaluationHoldout
        && record.evidenceDisposition == .attributable
        && drawingValidationRevision(
          record.tipCalibration.acceptedRevisionID,
          matches: registration
        )
        && record.paper.contactPlane == currentPaperRevisionContext.contactPlane
    }
  }

  private func drawingValidationRevision(
    _ evidenceRevision: LearningArtifactRevisionID,
    matches registration: TipCameraRegistration
  ) -> Bool {
    if evidenceRevision == registration.acceptedRevisionID { return true }
    guard case .checkpointRevalidated(let durableSourceRevision, _) = registration.derivation
    else { return false }
    return evidenceRevision == durableSourceRevision
  }

  var workbenchCapabilityPresentation: WorkbenchCapabilityPresentation {
    let learning: WorkbenchLearningCapabilityState
    if activeLearningSession.drawingReadinessAssessment?.state == .ready {
      learning = .adaptiveDrawingReady
    } else if interactiveLearningIsComplete {
      learning = .interactiveLearningComplete
    } else if tipCameraRegistration != nil {
      learning = .mapReady
    } else if quarantinedTipCalibrationCheckpoint != nil {
      learning = .savedMapNeedsRevalidation
    } else {
      learning = .learningNeeded
    }
    let paper: WorkbenchPaperSetupState =
      paperCoverageIsCurrent
      ? .current(
        detail: "Operator assertion: this sheet covers the outline; paper edges were not measured."
      )
      : .setupRequired(
        reason:
          "Place the current sheet over the outlined calibrated region and assert that it covers the outline."
      )
    return WorkbenchCapabilityPresentation(learning: learning, paper: paper)
  }

  func openDrawingStudio() {
    guard interactiveLearningIsComplete else { return }
    activeLearningSession.drawingTrial.comparisonReviewIsPinned = false
    activeLearningSession.drawingStudio.reviewIsPinned = false
    drawingStudioIsPresented = true
    rebuildDrawingStudioPlan()
  }

  func closeDrawingStudio() {
    guard !activeLearningSession.drawingStudio.runInProgress else { return }
    activeLearningSession.drawingStudio.reviewIsPinned = false
    drawingStudioIsPresented = false
  }

  var drawingStudioPanelChangeUnavailableReason: String? {
    activeLearningSession.drawingStudio.runInProgress
      ? "Drawing Studio cannot be hidden until the current run and evidence capture settle."
      : nil
  }

  var paperManagementUnavailableReason: String? {
    activeLearningSession.drawingStudio.runInProgress
      ? "Paper identity cannot change while a drawing run owns execution or evidence capture."
      : nil
  }

  func performCompletedComparisonReviewAction(_ action: CompletedComparisonReviewAction) {
    switch action {
    case .reviewComparison:
      reviewCompletedDrawingComparison()
    case .resumeLivePreview:
      resumeLivePreviewAfterDrawingComparison()
    case .openDrawingStudio:
      openDrawingStudio()
    }
  }

  var drawingStudioPresentation: DrawingStudioPresentation {
    let state = activeLearningSession.drawingStudio
    let editingIsEnabled = drawingStudioIsPresented && !state.runInProgress
    let placement = DrawingStudioPlacementPresentation(
      centerCameraPixel: drawingStudioCenterCameraPixel,
      uniformScale: state.uniformScale,
      allowedScale: drawingStudioAllowedScale,
      rotationDegrees: state.rotationDegrees,
      placementIsEnabled: editingIsEnabled && !state.terminalRequiresNewPlan
    )
    let runState: DrawingStudioRunState
    if let capabilityID = state.activeStopCapabilityID {
      runState = .running(
        capabilityID: capabilityID,
        detail: state.runDetail ?? "The accepted execution plan owns the plotter."
      )
    } else if state.runInProgress {
      runState = .processing(
        detail: state.runDetail ?? "The motion owner settled; evidence processing is in progress."
      )
    } else if let record = state.lastRunRecord {
      runState =
        state.reviewIsPinned
        ? .reviewing(
          runID: record.runID.description,
          detail: "Reviewing the exact post-run frame and retained observation."
        )
        : .reviewAvailable(
          runID: record.runID.description,
          detail: "The immutable run evidence is available for review."
        )
    } else if let reason = drawingStudioRunUnavailableReason {
      runState = .unavailable(reason: reason)
    } else {
      runState = .ready(
        detail: "The reviewed plan is inside the calibrated region on confirmed paper."
      )
    }
    return DrawingStudioPresentation(
      catalog: DrawingStudioCatalogItemPresentation.builtInCatalog,
      selectedCatalogItemID: state.selectedCatalogItemID,
      sourceParameters: [
        DrawingStudioParameterPresentation(
          id: DrawingStudioParameterID(rawValue: "evidence-role"),
          title: "Evidence role",
          detail:
            "Choose before execution; a holdout cannot become training evidence after inspection.",
          value: .choice(drawingEvidenceRoleLabel(state.evidenceRole)),
          control: .choices([
            "Ordinary drawing", "Training", "Reserved holdout", "Evaluation holdout",
          ])
        )
      ],
      canvas: DrawingStudioCanvasPresentation(
        placement: placement,
        targetPreview: drawingStudioTargetPreview
      ),
      editingIsEnabled: editingIsEnabled && !state.terminalRequiresNewPlan,
      runState: runState
    )
  }

  private var drawingStudioAllowedScale: ClosedRange<Double> {
    guard let region = currentDrawableMachineRegion else { return 0.02...1 }
    let entry = DrawingProgramCatalog.entry(
      for: activeLearningSession.drawingStudio.selectedCatalogItemID
    )
    let maximum = max(
      0.02,
      min(
        (region.effectiveBounds.maxX - region.effectiveBounds.minX) / entry.fieldExtent.width,
        (region.effectiveBounds.maxY - region.effectiveBounds.minY) / entry.fieldExtent.height
      ) * 0.9
    )
    return 0.02...maximum
  }

  private var drawingStudioCenterCameraPixel: Point2<CameraPixelSpace>? {
    guard let center = activeLearningSession.drawingStudio.machineCenter,
      let registration = tipCameraRegistration
    else { return nil }
    return try? registration.tipPixel(at: center)
  }

  private var drawingStudioTargetPreview: DrawingStudioTargetPreview? {
    let state = activeLearningSession.drawingStudio
    guard let frame = displayedFrame,
      let program = state.program,
      let registration = tipCameraRegistration
    else { return nil }
    let projected: [Polyline<CameraPixelSpace>]
    let planHash: String?
    let status: DrawingStudioTargetPreviewStatus
    if let plan = state.plan {
      do {
        projected = try plan.strokes.map { stroke in
          try Polyline(points: stroke.path.points.map { try registration.tipPixel(at: $0) })
        }
        planHash = plan.contentHash.description
        status = .ready
      } catch {
        projected = []
        planHash = nil
        status = .unavailable(reason: "The current tip map cannot project this plan: \(error)")
      }
    } else {
      projected = []
      planHash = nil
      status = .outsideDrawableRegion(
        reason: state.planningError ?? "Place the target inside the calibrated region."
      )
    }
    let points = projected.flatMap(\.points)
    let bounds: AxisAlignedBounds<CameraPixelSpace>? =
      if points.isEmpty {
        nil
      } else {
        try? AxisAlignedBounds(
          minX: points.map(\.x).min()!,
          minY: points.map(\.y).min()!,
          maxX: points.map(\.x).max()!,
          maxY: points.map(\.y).max()!
        )
      }
    return DrawingStudioTargetPreview(
      provenance: ExactFrameOverlayProvenance(frame),
      strokes: projected,
      bounds: bounds,
      programContentHash: program.contentHash.description,
      executionPlanContentHash: planHash,
      status: status
    )
  }

  private var drawingStudioRunUnavailableReason: String? {
    guard frameMode == .live else {
      return "SIMULATED previews placement but cannot supply physical drawing evidence."
    }
    guard interactiveLearningIsComplete else {
      return "Complete the attributable isolated-line validation first."
    }
    guard tipCameraRegistration != nil else { return "A current accepted tip map is required." }
    if let reason = controllerPoseRevalidationUnavailableReason { return reason }
    guard paperCoverageIsCurrent else {
      return
        "Assert that the current paper covers the outlined calibrated region; paper edges are not measured automatically."
    }
    guard activeLearningSession.drawingStudio.plan != nil else {
      return activeLearningSession.drawingStudio.planningError
        ?? "Place the drawing fully inside the calibrated region."
    }
    guard !activeLearningSession.drawingStudio.terminalRequiresNewPlan else {
      return "Review the terminal run, then start a new plan before drawing again."
    }
    if let hash = activeLearningSession.drawingStudio.plan?.contentHash,
      activeLearningSession.drawingStudio.redrawBlockedPlanHashes.contains(hash)
    {
      return "Move, resize, or rotate the target away from a plan that may already contain ink."
    }
    guard controllerSessionEstablished else { return "Connect the plotter first." }
    guard motionAuthorizationEnabled else { return "Enable Motion for this controller session." }
    guard controllerIsPenUpAndIdle else {
      return "A settled controller-confirmed Pen Up pose is required."
    }
    guard machineActions?.beginDrawingPlan != nil,
      cameraActions?.observePlannedDrawingInk != nil
    else {
      return "The drawing-plan runtime and planned-ink observer are unavailable."
    }
    return nil
  }

  func performDrawingStudioAction(_ action: DrawingStudioAction) async {
    switch action {
    case .selectCatalogItem(let id):
      guard drawingStudioDraftMutationIsAvailable else { return }
      activeLearningSession.drawingStudio.selectedCatalogItemID = id
      activeLearningSession.drawingStudio.placementID = UUID()
      rebuildDrawingStudioPlan()
    case .setParameter(let id, let value):
      guard drawingStudioDraftMutationIsAvailable else { return }
      guard id.rawValue == "evidence-role", case .choice(let label) = value else { return }
      activeLearningSession.drawingStudio.evidenceRole = drawingEvidenceRole(for: label)
    case .placeAtCameraPoint(let cameraPoint):
      guard drawingStudioDraftMutationIsAvailable else { return }
      guard let inverse = try? tipCameraRegistration?.cameraFromMachine.inverted(),
        let machinePoint = try? inverse.applying(to: cameraPoint)
      else { return }
      activeLearningSession.drawingStudio.machineCenter = machinePoint
      activeLearningSession.drawingStudio.placementID = UUID()
      rebuildDrawingStudioPlan()
    case .setUniformScale(let scale):
      guard drawingStudioDraftMutationIsAvailable else { return }
      activeLearningSession.drawingStudio.uniformScale = min(
        max(scale, drawingStudioAllowedScale.lowerBound),
        drawingStudioAllowedScale.upperBound
      )
      activeLearningSession.drawingStudio.placementID = UUID()
      rebuildDrawingStudioPlan()
    case .setRotationDegrees(let degrees):
      guard drawingStudioDraftMutationIsAvailable else { return }
      activeLearningSession.drawingStudio.rotationDegrees = degrees
      activeLearningSession.drawingStudio.placementID = UUID()
      rebuildDrawingStudioPlan()
    case .centerInDrawableRegion:
      guard drawingStudioDraftMutationIsAvailable else { return }
      guard let region = currentDrawableMachineRegion,
        let center = try? Point2<MachineSpace>(
          x: (region.effectiveBounds.minX + region.effectiveBounds.maxX) / 2,
          y: (region.effectiveBounds.minY + region.effectiveBounds.maxY) / 2
        )
      else { return }
      activeLearningSession.drawingStudio.machineCenter = center
      activeLearningSession.drawingStudio.placementID = UUID()
      rebuildDrawingStudioPlan()
    case .run:
      await runDrawingStudioPlan()
    case .stop(let capabilityID):
      await stopDrawingStudioPlan(capabilityID: capabilityID)
    case .reviewRun:
      activeLearningSession.drawingStudio.reviewIsPinned = true
    case .resumeLivePreview:
      activeLearningSession.drawingStudio.reviewIsPinned = false
    case .newRun:
      beginNewDrawingStudioPlan()
    }
  }

  private var drawingStudioDraftMutationIsAvailable: Bool {
    let state = activeLearningSession.drawingStudio
    return drawingStudioIsPresented && !state.runInProgress && !state.terminalRequiresNewPlan
  }

  private func beginNewDrawingStudioPlan() {
    guard !activeLearningSession.drawingStudio.runInProgress else { return }
    activeLearningSession.drawingStudio.lastRunRecord = nil
    activeLearningSession.drawingStudio.baselineFrame = nil
    activeLearningSession.drawingStudio.postFrame = nil
    activeLearningSession.drawingStudio.reviewIsPinned = false
    activeLearningSession.drawingStudio.terminalRequiresNewPlan = false
    activeLearningSession.drawingStudio.runDetail = nil
    activeLearningSession.drawingStudio.placementID = UUID()
    overlayResultChannels.clearWorkflow(source: frameMode, owner: .drawingStudio)
    rebuildDrawingStudioPlan()
  }

  private func rebuildDrawingStudioPlan() {
    guard let registration = tipCameraRegistration,
      let region = currentDrawableMachineRegion
    else {
      activeLearningSession.drawingStudio.program = nil
      activeLearningSession.drawingStudio.plan = nil
      activeLearningSession.drawingStudio.planningError = "A current accepted tip map is required."
      return
    }
    do {
      let entry = DrawingProgramCatalog.entry(
        for: activeLearningSession.drawingStudio.selectedCatalogItemID
      )
      let center: Point2<MachineSpace>
      if let existing = activeLearningSession.drawingStudio.machineCenter {
        center = existing
      } else {
        center = try Point2<MachineSpace>(
          x: (region.effectiveBounds.minX + region.effectiveBounds.maxX) / 2,
          y: (region.effectiveBounds.minY + region.effectiveBounds.maxY) / 2
        )
      }
      activeLearningSession.drawingStudio.machineCenter = center
      let program = try DrawingProgramCatalog.program(
        for: entry.id,
        style: StrokeStyle(
          nominalLineWidth: 0.4,
          penProfileID: PenProfileID(toolAssemblyRevision.rawValue)
        )
      )
      let placement = try DrawingPlacement(
        fieldAnchor: Point2(
          x: entry.fieldExtent.width / 2,
          y: entry.fieldExtent.height / 2
        ),
        machineAnchor: center,
        uniformScale: activeLearningSession.drawingStudio.uniformScale,
        rotationRadians: activeLearningSession.drawingStudio.rotationDegrees * .pi / 180
      )
      let plan = try DrawingPlanner.plan(
        program: program,
        placement: placement,
        drawableRegion: region,
        provenance: try drawingPlanningProvenance(for: registration)
      )
      activeLearningSession.drawingStudio.program = program
      activeLearningSession.drawingStudio.plan = plan
      activeLearningSession.drawingStudio.planningError = nil
    } catch {
      activeLearningSession.drawingStudio.program =
        activeLearningSession.drawingStudio.program
        ?? (try? DrawingProgramCatalog.program(
          for: activeLearningSession.drawingStudio.selectedCatalogItemID,
          style: StrokeStyle(
            nominalLineWidth: 0.4,
            penProfileID: PenProfileID(toolAssemblyRevision.rawValue)
          )
        ))
      activeLearningSession.drawingStudio.plan = nil
      activeLearningSession.drawingStudio.planningError = "Plan refused: \(error)"
    }
  }

  private func drawingPlanningProvenance(
    for registration: TipCameraRegistration
  ) throws -> DrawingPlanningProvenance {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let digest = try Digest(bytes: Array(SHA256.hash(data: encoder.encode(registration))))
    return DrawingPlanningProvenance(
      modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: digest,
      registrationRevisionID: DrawingRegistrationRevisionID(
        registration.acceptedRevisionID.rawValue
      ),
      registrationContentHash: digest
    )
  }

  private func drawingEvidenceRoleLabel(_ role: DrawingTrialEvidenceRole) -> String {
    switch role {
    case .ordinaryDrawing: "Ordinary drawing"
    case .training: "Training"
    case .reservedHoldout: "Reserved holdout"
    case .evaluationHoldout: "Evaluation holdout"
    }
  }

  private func drawingEvidenceRole(for label: String) -> DrawingTrialEvidenceRole {
    switch label {
    case "Training": .training
    case "Reserved holdout": .reservedHoldout
    case "Evaluation holdout": .evaluationHoldout
    default: .ordinaryDrawing
    }
  }

  private func runDrawingStudioPlan() async {
    guard drawingStudioRunUnavailableReason == nil,
      !activeLearningSession.drawingStudio.runInProgress,
      frameMode == .live,
      let machineActions,
      let beginDrawingPlan = machineActions.beginDrawingPlan,
      let observePlannedDrawingInk = cameraActions?.observePlannedDrawingInk,
      let program = activeLearningSession.drawingStudio.program,
      let plan = activeLearningSession.drawingStudio.plan,
      let registration = tipCameraRegistration
    else { return }

    let capabilityID = ContextualStopCapabilityID()
    let runID = RunID()
    let requestID = UUID()
    let placementID = activeLearningSession.drawingStudio.placementID
    let role = activeLearningSession.drawingStudio.evidenceRole
    let paper = currentPaperRevisionContext
    var terminalOutcome: DrawingPlanOutcome?
    var terminalRequestFrontier: DrawingRunRequestFrontier?
    activeLearningSession.drawingStudio.runInProgress = true
    activeLearningSession.drawingStudio.cancelRequested = false
    activeLearningSession.drawingStudio.runDetail = "Positioning for an exact pre-drawing frame."
    activeLearningSession.drawingStudio.lastRunRecord = nil
    activeLearningSession.drawingStudio.reviewIsPinned = false
    defer {
      activeLearningSession.drawingStudio.activeStopCapabilityID = nil
      activeLearningSession.drawingStudio.cancelRequested = false
      activeLearningSession.drawingStudio.runInProgress = false
    }

    do {
      guard let finalPoint = plan.strokes.last?.path.points.last else {
        throw LearningPathOperationError.requiredState("The drawing plan has no final point.")
      }
      var observationPosition = try currentMachinePosition()
      let preflightDelta = try observationPosition.point.vector(to: finalPoint)
      if preflightDelta.dx != 0 || preflightDelta.dy != 0 {
        let admission = await machineActions.beginRelativeJog(
          RelativeJogRequest(delta: preflightDelta, feedMMPerMinute: 500)
        )
        switch admission {
        case .admitted(let operation):
          activeLearningSession.drawingStudio.activeStopCapabilityID = capabilityID
          let outcome = await operation.outcome()
          activeLearningSession.drawingStudio.activeStopCapabilityID = nil
          switch outcome {
          case .acceptedThenCompleted(let final):
            observationPosition = final
          case .cancelled:
            activeLearningSession.drawingStudio.runDetail =
              "Drawing cancelled before any plan segment was admitted."
            return
          case .refused(let reason):
            activeLearningSession.drawingStudio.runDetail =
              "Observation-position travel was refused: \(reason)"
            return
          case .ambiguous(let reason):
            activeLearningSession.drawingStudio.runDetail =
              "Observation-position travel is ambiguous: \(reason)"
            return
          }
        case .rejected(let outcome):
          activeLearningSession.drawingStudio.runDetail =
            "Observation-position travel was rejected: \(outcome)"
          return
        }
      }
      guard !activeLearningSession.drawingStudio.cancelRequested else { return }
      let baseline = try await captureProtocolFrame(
        newerThan: displayedFrame?.frame.captureNanoseconds ?? 0
      )
      activeLearningSession.drawingStudio.baselineFrame = baseline
      activeLearningSession.drawingStudio.runDetail =
        "Executing \(plan.strokes.count) checkpointed stroke(s)."

      let request = try DrawingPlanRequest(
        operationID: DrawingPlanOperationID(rawValue: requestID),
        plan: plan,
        travelFeedMMPerMinute: 500,
        drawingFeedMMPerMinute: 100,
        penActuationProfile: currentPenActuationProfile
      )
      guard !activeLearningSession.drawingStudio.cancelRequested else { return }
      let admission = await beginDrawingPlan(request)
      let outcome: DrawingPlanOutcome
      let requestFrontier: DrawingRunRequestFrontier
      switch admission {
      case .admitted(let operation):
        requestFrontier = .admitted
        activeLearningSession.drawingStudio.activeStopCapabilityID = capabilityID
        outcome = await operation.outcome()
        activeLearningSession.drawingStudio.activeStopCapabilityID = nil
      case .rejected(let rejected):
        requestFrontier = .validated
        outcome = rejected
      }
      terminalOutcome = outcome
      terminalRequestFrontier = requestFrontier
      activeLearningSession.drawingStudio.terminalRequiresNewPlan = true
      if outcome.progress.commandedStrokeCount > 0 {
        activeLearningSession.drawingStudio.redrawBlockedPlanHashes.insert(plan.contentHash)
      }
      machineSnapshot = await machineActions.snapshot()

      guard case .completed(_, let finalPosition) = outcome else {
        let record = try makeDrawingStudioRunRecord(
          runID: runID,
          requestID: requestID,
          role: role,
          requestFrontier: requestFrontier,
          outcome: outcome,
          program: program,
          plan: plan,
          placementID: placementID,
          registration: registration,
          paper: paper,
          observation: drawingObservationNotAttempted(for: outcome)
        )
        await retainDrawingStudioRunRecord(record)
        activeLearningSession.drawingStudio.runDetail =
          "Drawing stopped without redraw: \(String(describing: outcome))"
        return
      }
      guard
        currentPaperRevisionContext == paper,
        MachinePositionAcceptancePolicy.accepts(
          finalPosition,
          target: MachinePosition(point: finalPoint)
        )
      else {
        throw LearningPathOperationError.requiredState(
          "Paper lineage changed or controller completion did not settle at the exact observation pose."
        )
      }

      activeLearningSession.drawingStudio.runDetail = "Capturing and comparing new ink."
      let post = try await captureProtocolFrame(
        newerThan: baseline.frame.captureNanoseconds
      )
      activeLearningSession.drawingStudio.postFrame = post
      let intended = try plan.strokes.map { stroke in
        try Polyline(points: stroke.path.points.map { try registration.tipPixel(at: $0) })
      }
      let region = plannedDrawingObservationRegion(
        intended,
        frameWidth: post.frame.width,
        frameHeight: post.frame.height
      )
      let frames = try DrawingObservationFramePair(
        source: post.source,
        baseline: ExactFrameProvenance(frame: baseline.frame),
        post: ExactFrameProvenance(frame: post.frame)
      )
      let observed = await observePlannedDrawingInk(
        PlannedDrawingObservationRequest(
          frames: frames,
          localPreDrawingBaseline: SamePoseFrameSample(
            displayedFrame: baseline,
            controllerPosition: observationPosition
          ),
          postDrawing: SamePoseFrameSample(
            displayedFrame: post,
            controllerPosition: finalPosition
          ),
          region: region,
          intendedCameraPolylines: intended,
          thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
          controllerPositionToleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
          alignmentSearchRadiusPixels: FixedCameraOpticalSettlingPolicy
            .alignmentSearchRadiusPixels,
          maximumAlignmentShiftPixels: FixedCameraOpticalSettlingPolicy
            .maximumAlignmentShiftPixels,
          maximumBackgroundMeanAbsoluteDifference: FixedCameraOpticalSettlingPolicy
            .maximumBackgroundMeanAbsoluteDifference,
          observerRevision: try AlgorithmRevisionEvidence(
            component: "planned-drawing-observer",
            revision: "bounded-nearest-polyline-v1"
          ),
          additionalAlgorithmRevisions: [
            try AlgorithmRevisionEvidence(
              component: "drawing-plan-runner",
              revision: "checkpointed-multistroke-v1"
            )
          ]
        )
      )
      let runObservation: DrawingRunObservationOutcome
      let evidenceDisposition: DrawingTrialEvidenceDisposition
      switch observed {
      case .observed(let observation):
        overlayResultChannels.publishWorkflow(
          OverlayChannelResult(displayedFrame: post, overlays: observation.overlays),
          source: frameMode,
          owner: .drawingStudio
        )
        runObservation = .observed(observation.evidence)
        evidenceDisposition = .attributable
      case .rejected(let rejection):
        runObservation = .rejected(rejection)
        evidenceDisposition = .visionUnclear
      }
      let record = try makeDrawingStudioRunRecord(
        runID: runID,
        requestID: requestID,
        role: role,
        requestFrontier: requestFrontier,
        outcome: outcome,
        program: program,
        plan: plan,
        placementID: placementID,
        registration: registration,
        paper: paper,
        observation: runObservation,
        evidenceDispositionOverride: evidenceDisposition
      )
      await retainDrawingStudioRunRecord(record)
      activeLearningSession.drawingStudio.reviewIsPinned = true
      activeLearningSession.drawingStudio.runDetail =
        evidenceDisposition == .attributable
        ? "Controller execution and planned-ink comparison are attributable."
        : "Controller execution completed; Vision evidence needs attention."
    } catch {
      let primaryError = "Drawing run failed: \(error)"
      if let outcome = terminalOutcome,
        let requestFrontier = terminalRequestFrontier,
        activeLearningSession.drawingStudio.lastRunRecord == nil
      {
        do {
          let record = try makeDrawingStudioRunRecord(
            runID: runID,
            requestID: requestID,
            role: role,
            requestFrontier: requestFrontier,
            outcome: outcome,
            program: program,
            plan: plan,
            placementID: placementID,
            registration: registration,
            paper: paper,
            observation: drawingObservationNotAttempted(for: outcome)
          )
          await retainDrawingStudioRunRecord(record)
        } catch {
          drawingEvidenceError = "\(primaryError) Terminal evidence also failed: \(error)"
        }
      }
      activeLearningSession.drawingStudio.runDetail = primaryError
      if drawingEvidenceError == nil { drawingEvidenceError = primaryError }
    }
  }

  private func stopDrawingStudioPlan(capabilityID: ContextualStopCapabilityID) async {
    guard activeLearningSession.drawingStudio.activeStopCapabilityID == capabilityID else { return }
    activeLearningSession.drawingStudio.cancelRequested = true
    _ = await machineActions?.requestJogCancel(.operatorStop)
  }

  private func plannedDrawingObservationRegion(
    _ intended: [Polyline<CameraPixelSpace>],
    frameWidth: Int,
    frameHeight: Int
  ) -> PixelRect {
    let points = intended.flatMap(\.points)
    let margin = 8
    let minX = max(0, Int(floor(points.map(\.x).min() ?? 0)) - margin)
    let minY = max(0, Int(floor(points.map(\.y).min() ?? 0)) - margin)
    let maxX = min(frameWidth - 1, Int(ceil(points.map(\.x).max() ?? 0)) + margin)
    let maxY = min(frameHeight - 1, Int(ceil(points.map(\.y).max() ?? 0)) + margin)
    return PixelRect(
      x: minX,
      y: minY,
      width: max(1, maxX - minX + 1),
      height: max(1, maxY - minY + 1)
    )
  }

  private func drawingObservationNotAttempted(
    for outcome: DrawingPlanOutcome
  ) -> DrawingRunObservationOutcome {
    switch outcome {
    case .refused:
      .notAttempted(.requestRefused)
    case .cancelled:
      .notAttempted(.executionCancelledBeforeObservation)
    case .ambiguous, .possibleInk:
      .notAttempted(.executionFailedBeforeObservation)
    case .completed:
      .notAttempted(.frameEvidenceUnavailable)
    }
  }

  private func makeDrawingStudioRunRecord(
    runID: RunID,
    requestID: UUID,
    role: DrawingTrialEvidenceRole,
    requestFrontier: DrawingRunRequestFrontier,
    outcome: DrawingPlanOutcome,
    program: DrawingProgram,
    plan: ExecutionPlanRevision,
    placementID: UUID,
    registration: TipCameraRegistration,
    paper: PaperRevisionContext,
    observation: DrawingRunObservationOutcome,
    evidenceDispositionOverride: DrawingTrialEvidenceDisposition? = nil
  ) throws -> DrawingRunEvidenceRecord {
    let progress = outcome.progress
    let executionDisposition: DrawingRunExecutionDisposition
    let evidenceDisposition: DrawingTrialEvidenceDisposition
    switch outcome {
    case .completed:
      executionDisposition = .completed
      evidenceDisposition = evidenceDispositionOverride ?? .visionUnclear
    case .refused(_, let reason):
      executionDisposition = .refused(reason: String(describing: reason))
      evidenceDisposition = .refused
    case .cancelled:
      executionDisposition = .cancelled(reason: "Operator Stop")
      evidenceDisposition = .cancelled
    case .ambiguous(_, let reason):
      executionDisposition = .ambiguous(reason: String(describing: reason))
      evidenceDisposition = .ambiguous
    case .possibleInk(_, let reason, _):
      executionDisposition = .ambiguous(reason: String(describing: reason))
      evidenceDisposition = .possibleInk
    }
    let verifiedCount: Int =
      evidenceDisposition == .attributable
      ? progress.controllerCompletedStrokeCount : 0
    let provenance = try drawingPlanningProvenance(for: registration)
    return try DrawingRunEvidenceRecord(
      runID: runID,
      requestID: requestID,
      role: role,
      evidenceDisposition: evidenceDisposition,
      requestFrontier: requestFrontier,
      executionFrontiers: DrawingRunExecutionFrontiers(
        plannedStrokeCount: UInt32(progress.plannedStrokeCount),
        commandedStrokeCount: UInt32(progress.commandedStrokeCount),
        controllerCompletedStrokeCount: UInt32(progress.controllerCompletedStrokeCount),
        inkVerifiedStrokeCount: UInt32(verifiedCount)
      ),
      executionDisposition: executionDisposition,
      program: DrawingProgramEvidenceReference(program: program),
      placement: DrawingPlacementEvidenceReference(
        placementID: placementID,
        placement: plan.placement
      ),
      plan: DrawingExecutionPlanEvidenceReference(plan: plan),
      planningProvenance: provenance,
      tipCalibration: DrawingTipCalibrationEvidenceReference(
        acceptedRevisionID: registration.acceptedRevisionID,
        registrationEvidenceSHA256: provenance.registrationContentHash.description,
        applicability: registration.applicability,
        estimatorRevision: registration.estimatorRevision
      ),
      paper: paper,
      observation: observation,
      recordedAt: RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
    )
  }

  private func retainDrawingStudioRunRecord(_ record: DrawingRunEvidenceRecord) async {
    activeLearningSession.drawingStudio.lastRunRecord = record
    guard frameMode == .live, let actions = liveDrawingEvidenceActions else { return }
    do {
      drawingEvidenceArchive = try await actions.append(record)
      drawingEvidenceError = nil
    } catch {
      drawingEvidenceError = "Drawing evidence could not be archived: \(error)"
    }
  }

  func confirmCurrentPaperCoversDrawableRegion() {
    guard !activeLearningSession.drawingStudio.runInProgress else {
      drawingEvidenceError =
        "Paper coverage cannot change while a drawing run owns execution or evidence capture."
      return
    }
    guard let frame = displayedFrame,
      let registration = tipCameraRegistration,
      let region = currentDrawableMachineRegion
    else {
      drawingEvidenceError =
        "A current tip map and displayed frame are required to record the operator's paper-coverage assertion."
      return
    }
    let bounds = region.effectiveBounds
    let machineCorners: [Point2<MachineSpace>] = [
      try? Point2(x: bounds.minX, y: bounds.minY),
      try? Point2(x: bounds.maxX, y: bounds.minY),
      try? Point2(x: bounds.maxX, y: bounds.maxY),
      try? Point2(x: bounds.minX, y: bounds.maxY),
    ].compactMap { $0 }
    do {
      let polygon = try machineCorners.map { try registration.tipPixel(at: $0) }
      let observation = try PaperCoverageObservation(
        paper: currentPaperRevisionContext,
        source: frame.source,
        frame: ExactFrameProvenance(frame: frame.frame),
        polygon: polygon,
        method: .operatorAccepted,
        observedAt: RuntimeTimestamp(
          monotonicNanoseconds: max(nowNanoseconds(), frame.frame.captureNanoseconds)
        ),
        algorithmRevision: "operator-confirmed-calibrated-region-coverage-v1"
      )
      currentPaperCoverageObservation = observation
      if frameMode == .live { try livePaperCoverageActions?.save(observation) }
      drawingEvidenceError = nil
    } catch {
      drawingEvidenceError = "Paper coverage could not be recorded: \(error)"
    }
  }

  var currentDrawableMachineRegion: DrawableMachineRegion? {
    guard let registration = tipCameraRegistration else { return nil }
    return try? DrawableMachineRegion(bounds: registration.applicabilityRectangle)
  }

  private func learnedDrawingOverlays(
    on displayedFrame: DisplayedFrame
  ) -> [CameraOverlayMeasurement] {
    guard let registration = tipCameraRegistration,
      displayedFrame.source == registration.applicability.opticalConfiguration.source,
      displayedFrame.frame.width == registration.applicability.opticalConfiguration.width,
      displayedFrame.frame.height == registration.applicability.opticalConfiguration.height,
      displayedFrame.frame.pixelFormat
        == registration.applicability.opticalConfiguration.pixelFormat,
      let region = currentDrawableMachineRegion
    else { return [] }

    let bounds = region.effectiveBounds
    let machineCorners: [Point2<MachineSpace>] = [
      try? Point2(x: bounds.minX, y: bounds.minY),
      try? Point2(x: bounds.maxX, y: bounds.minY),
      try? Point2(x: bounds.maxX, y: bounds.maxY),
      try? Point2(x: bounds.minX, y: bounds.maxY),
      try? Point2(x: bounds.minX, y: bounds.minY),
    ].compactMap { $0 }
    var overlays: [CameraOverlayMeasurement] = []
    if machineCorners.count == 5,
      let polyline = try? Polyline(
        points: machineCorners.map { try registration.tipPixel(at: $0) }
      )
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: displayedFrame.frame.id,
          cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
          geometry: .polyline(polyline),
          provenance: CameraMeasurementProvenance(
            kind: .calibratedDrawableRegion,
            source: .inferred,
            algorithmRevision: "accepted-tip-applicability-region-v1"
          )
        )
      )
    }
    if let position = try? currentMachinePosition(),
      let point = try? registration.tipPixel(at: position.point)
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: displayedFrame.frame.id,
          cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
          geometry: .point(point),
          provenance: CameraMeasurementProvenance(
            kind: .predictedContactPoint,
            source: .inferred,
            algorithmRevision: "accepted-tip-current-position-v1"
          )
        )
      )
    }
    if let coverage = currentPaperCoverageObservation,
      coverage.frame.frameID == displayedFrame.frame.id,
      coverage.frame.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID,
      let polygon = try? Polyline(points: coverage.polygon + [coverage.polygon[0]])
    {
      overlays.append(
        CameraOverlayMeasurement(
          frameID: displayedFrame.frame.id,
          cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
          geometry: .polyline(polygon),
          provenance: CameraMeasurementProvenance(
            kind: .paperCoverage,
            source: coverage.method == .visionMeasured ? .measured : .diagnostic,
            algorithmRevision: coverage.algorithmRevision
          )
        )
      )
    }
    return overlays
  }

  var completedComparisonReviewPresentation: CompletedComparisonReviewPresentation {
    guard !activeLearningSession.drawingStudio.runInProgress,
      completedDrawingComparisonReviewIsAvailable,
      let frame = explorationPostLineFrame
    else {
      return .unavailable
    }
    let provenance = ExactFrameOverlayProvenance(frame)
    return CompletedComparisonReviewPresentation(
      state: completedDrawingComparisonReviewIsPinned
        ? .reviewingExactFrame(provenance)
        : .available(provenance),
      drawingStudioIsAvailable: drawingTrialAssessment == .predictionObserved
    )
  }

  var completedDrawingComparisonReviewIsAvailable: Bool {
    drawingTrialAssessment != nil && explorationPostLineFrame != nil && lastInkObservation != nil
  }

  var completedDrawingComparisonReviewIsPinned: Bool {
    activeLearningSession.drawingTrial.comparisonReviewIsPinned
  }

  func reviewCompletedDrawingComparison() {
    guard completedDrawingComparisonReviewIsAvailable,
      !activeLearningSession.drawingStudio.runInProgress
    else { return }
    activeLearningSession.drawingStudio.reviewIsPinned = false
    drawingStudioIsPresented = false
    activeLearningSession.drawingTrial.comparisonReviewIsPinned = true
  }

  func resumeLivePreviewAfterDrawingComparison() {
    activeLearningSession.drawingTrial.comparisonReviewIsPinned = false
  }

  private func drawingTrialPredictionOverlays(
    on displayedFrame: DisplayedFrame
  ) -> [CameraOverlayMeasurement] {
    guard lastInkObservation == nil,
      let registration = tipCameraRegistration,
      displayedFrame.source == registration.applicability.opticalConfiguration.source,
      displayedFrame.frame.width == registration.applicability.opticalConfiguration.width,
      displayedFrame.frame.height == registration.applicability.opticalConfiguration.height,
      displayedFrame.frame.pixelFormat
        == registration.applicability.opticalConfiguration.pixelFormat,
      let currentRevision = learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id,
      currentRevision == registration.acceptedRevisionID,
      drawingTrialTipRegistrationRevisionID == currentRevision,
      let lineStart = drawingTrialLineStart,
      let lineEnd = drawingTrialLineEnd,
      let cameraStart = try? registration.tipPixel(at: lineStart.point),
      let cameraEnd = try? registration.tipPixel(at: lineEnd.point),
      let predictedLine = try? Polyline(points: [cameraStart, cameraEnd])
    else { return [] }
    return [
      CameraOverlayMeasurement(
        frameID: displayedFrame.frame.id,
        cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
        geometry: .polyline(predictedLine),
        provenance: CameraMeasurementProvenance(
          kind: .intendedPath,
          source: .planned,
          algorithmRevision: "tip-registration-isolated-line-preview-v1"
        )
      )
    ]
  }

  func overlayStatus(for overlay: UserSceneOverlay) -> OverlayLayerStatus {
    if frameMode == .live,
      overlayPreferenceState.enabled.contains(overlay),
      livePenCapAppearanceSelection == nil
    {
      return OverlayLayerStatus(
        state: .unavailable,
        message: persistedPenCapAppearanceLoadState.unavailableMessage,
        provenance: nil
      )
    }
    let surfaceFrame = frozenPointSelectionFrame ?? displayedFrame
    return OverlayPresentationComposer.compose(
      preference: overlayPreferenceState,
      channels: overlayResultChannels,
      displayedFrame: surfaceFrame,
      sceneState: visionAnalysisSnapshot,
      sceneIsAvailable: sceneOverlayIsAvailable,
      workflowVisionIsExclusive: exclusiveWorkflowVisionRequestCount > 0
    ).statuses[overlay]!
  }

  func overlayCardPresentation(for overlay: UserSceneOverlay) -> OverlayCardPresentation {
    OverlayCardPresentation(
      overlay: overlay,
      isOn: overlayPreferenceState.enabled.contains(overlay),
      status: overlayStatus(for: overlay),
      roiText: videoAnalysisRegionText,
      cadenceText: frameMode == .live
        ? "\(visionAnalysisCadence.rawValue) frames per second"
        : "Causal simulated frames",
      nowNanoseconds: nowNanoseconds()
    )
  }

  private var sceneOverlayIsAvailable: Bool {
    guard frameMode == .live, case .running = cameraSnapshot?.state else { return false }
    return true
  }

  private func learnedBoundsPresentationRegion(_ frame: DisplayedFrame) -> PixelRect? {
    guard let registration = machineCameraRegistration,
      let negativeX = boundarySideAggregates[.negativeX]?.estimateMM,
      let positiveX = boundarySideAggregates[.positiveX]?.estimateMM,
      let negativeY = boundarySideAggregates[.negativeY]?.estimateMM,
      let positiveY = boundarySideAggregates[.positiveY]?.estimateMM
    else { return nil }
    let corners = [
      try? Point2<MachineSpace>(x: negativeX, y: negativeY),
      try? Point2<MachineSpace>(x: negativeX, y: positiveY),
      try? Point2<MachineSpace>(x: positiveX, y: negativeY),
      try? Point2<MachineSpace>(x: positiveX, y: positiveY),
    ].compactMap { $0 }.compactMap { try? registration.fit.cameraPoint(from: $0) }
    guard corners.count == 4 else { return nil }
    let minX = Int(floor(corners.map(\.x).min()!))
    let minY = Int(floor(corners.map(\.y).min()!))
    let maxX = Int(ceil(corners.map(\.x).max()!))
    let maxY = Int(ceil(corners.map(\.y).max()!))
    return cameraFrameIntersection(
      PixelRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY)),
      frameWidth: frame.frame.width,
      frameHeight: frame.frame.height
    )
  }

  var cameraDevices: [CameraDevice] { cameraSnapshot?.devices ?? [] }
  var selectedCameraID: CameraDeviceID? { cameraSnapshot?.selectedDeviceID }
  var isShutdown: Bool { hasShutdown }

  var currentCameraCalibrationBusyReason: String? {
    currentCameraCalibrationPhase.map {
      "Automatic current-camera calibration is in progress (\($0.description)). Use Stop during an admitted move."
    }
  }

  var cameraIsLive: Bool {
    guard frameMode == .live, case .running = cameraSnapshot?.state,
      let latestLiveCameraFrame, case .live(let deviceID) = latestLiveCameraFrame.source,
      deviceID == selectedCameraID
    else { return false }
    if cameraSnapshot?.diagnostics.previewPublicationPaused == true { return true }
    let now = nowNanoseconds()
    guard now >= latestLiveCameraFrame.frame.captureNanoseconds else { return false }
    return now - latestLiveCameraFrame.frame.captureNanoseconds <= 1_000_000_000
  }

  var controllerIsConnected: Bool {
    guard passiveProbeResult?.blockers.isEmpty == true,
      let machine = machineSnapshot?.machine,
      machine.connection == .connected,
      machine.controllerState?.isRecognized == true,
      machine.stickyAmbiguity == nil
    else { return false }
    return true
  }

  /// A responsive operator session remains established while its one owner is
  /// moving or actuating. This is status truth, not motion admission.
  var controllerSessionEstablished: Bool {
    if frameMode == .simulated {
      return simulatedLearningSnapshot?.session == .connected
    }
    guard passiveProbeResult?.blockers.isEmpty == true,
      let machine = machineSnapshot?.machine,
      machine.controllerState?.isRecognized == true,
      machine.stickyAmbiguity == nil
    else { return false }
    switch machine.connection {
    case .connected, .moving, .actuatingPen:
      return true
    case .disconnected, .connecting, .probing, .blocked:
      return false
    }
  }

  /// Session authorization only. Transient operation ownership, Pen pose, and
  /// editable manual fields are presented separately as request availability.
  var motionAuthorizationEnabled: Bool {
    if frameMode == .simulated {
      return simulatedLearningSnapshot?.motionAuthorization == .enabled
    }
    return controllerSessionEstablished
      && machineSnapshot?.machine.motionGuardState == .active
  }

  var cameraStateText: String {
    guard frameMode == .live else { return "causal simulated frame" }
    guard let state = cameraSnapshot?.state else { return "not started" }
    return switch state {
    case .stopped: "stopped"
    case .discovering: "discovering"
    case .ready: "ready"
    case .starting: "starting"
    case .running: "running"
    case .interrupted(let reason): "interrupted: \(reason)"
    case .failed(let error): "failed: \(error.actionableDescription)"
    }
  }

  var frameAgeText: String {
    guard let frame = displayedFrame?.frame else { return "no frame" }
    let now = nowNanoseconds()
    guard now >= frame.captureNanoseconds else { return "clock mismatch" }
    return String(format: "%.2f s", Double(now - frame.captureNanoseconds) / 1_000_000_000)
  }

  var captureThroughputText: String {
    let diagnostics = cameraSnapshot?.diagnostics ?? .zero
    let held = diagnostics.previewPublicationPaused ? " · preview held for Vision" : ""
    return
      "received \(diagnostics.receivedFrameCount) · preview \(diagnostics.previewMaterializedFrameCount) · exact \(diagnostics.exactMaterializedFrameCount)\(held)"
  }

  var visionThroughputText: String {
    let snapshot = visionAnalysisSnapshot
    let cadence: String
    switch snapshot.state {
    case .stopped: cadence = "stopped"
    case .running(let value): cadence = "target \(value.rawValue) frames per second"
    }
    let duration =
      snapshot.latestResult.map {
        String(format: "%.1f ms", Double($0.analysisDurationNanoseconds) / 1_000_000)
      } ?? "no timing"
    return
      "\(cadence) · analyzed \(snapshot.analyzedFrameCount) · superseded \(snapshot.supersededFrameCount) · \(duration)"
  }

  var videoAnalysisIsActive: Bool {
    visionAnalysisSnapshot.activeFrameSequence != nil
  }

  var videoAnalysisRegionText: String {
    guard let lock = videoAnalysisRegionLock else {
      return "Full frame · unlocked/default analysis"
    }
    let region = lock.region
    return "x \(region.x), y \(region.y), \(region.width) × \(region.height) px · locked"
  }

  var currentOperationText: String {
    if frameMode == .simulated {
      guard let operation = simulatedLearningSnapshot?.currentOperation else {
        return "simulated idle"
      }
      return switch operation.kind {
      case .manualJog: "simulated manual jog"
      case .boundary: "simulated Boundary Discovery motion"
      case .drawing: "simulated drawing stroke"
      }
    }
    guard let operation = machineSnapshot?.currentOperation else { return "none" }
    return switch operation {
    case .idle: "idle"
    case .passiveProbe: "controller inspection"
    case .alarmClear: "clearing controller alarm"
    case .relativeJog: "relative jog"
    case .boundaryMotion: "Boundary Discovery motion"
    case .drawingStroke: "isolated drawing stroke"
    case .drawingPlan: "drawing execution plan"
    case .penActuation(let command): "pen \(command.rawValue)"
    }
  }

  var controllerStateText: String {
    if frameMode == .simulated {
      return simulatedLearningSnapshot?.currentOperation == nil
        ? "simulated Idle" : "simulated active"
    }
    return machineSnapshot?.machine.controllerState?.rawValue ?? "unknown"
  }

  var controllerConnectionText: String {
    if frameMode == .simulated {
      return controllerSessionEstablished ? "simulator connected" : "simulator disconnected"
    }
    guard selectedSerialDevice != nil else { return "not selected" }
    if controllerIsConnected { return "connected" }
    guard let machine = machineSnapshot?.machine else { return "not connected" }
    switch machine.connection {
    case .connected:
      return passiveProbeInProgress ? "connecting" : "not connected"
    case .disconnected:
      return "disconnected"
    case .connecting:
      return "connecting"
    case .probing:
      return "probing"
    case .moving:
      return "command in flight"
    case .actuatingPen:
      return "pen command in flight"
    case .blocked:
      return "blocked"
    }
  }

  /// grblHAL status proves that its USB-side controller is responsive. The
  /// BlackBox does not report whether motor supply current is present, so the
  /// UI must not turn a responsive serial link into a powered-motors claim.
  var motorPowerText: String {
    if frameMode == .simulated { return "not present — nonphysical simulator" }
    guard machineSnapshot?.machine.connection == .connected else { return "unverified" }
    return "not reported by controller"
  }

  var motionPermissionText: String {
    motionUnavailableReason == nil ? "request eligible" : "unavailable"
  }

  var motionGuardIsActive: Bool {
    motionAuthorizationEnabled
  }

  var motionGuardStateText: String {
    motionGuardIsActive ? "active" : "inactive"
  }

  var controllerSelectionUnavailableReason: String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if serialDevices.isEmpty { return "No serial controllers are available." }
    if let activeDiscoverySequenceID {
      return
        "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while its logical owner is active."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || motionAuthorizationActionInProgress
    {
      return "Wait for the current controller operation."
    }
    return nil
  }

  var motionGuardActivationUnavailableReason: String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if motionAuthorizationActionInProgress {
      return "A Motion authorization action is in progress."
    }
    if motionAuthorizationEnabled { return "Motion is already enabled." }
    if !controllerSessionEstablished {
      return frameMode == .simulated
        ? "Connect the learning simulator first."
        : "Connect the selected plotter first."
    }
    if frameMode == .simulated { return nil }
    guard let snapshot = machineSnapshot else {
      return MotionRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return MotionRefusal.operationInFlight.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return MotionRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return MotionRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return MotionRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    if machine.pins.hasRelevantLimitAsserted {
      return MotionRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    if machine.position == nil {
      return MotionRefusal.machinePositionUnknown.actionableDescription
    }
    return nil
  }

  var motionAuthorizationActionUnavailableReason: String? {
    guard motionAuthorizationEnabled else {
      return motionGuardActivationUnavailableReason
    }
    return controllerConnectionActionUnavailableReason
  }

  var controllerConnectionActionTitle: String {
    if frameMode == .simulated {
      return controllerSessionEstablished ? "Disconnect" : "Connect"
    }
    return controllerLinkIsOpen ? "Disconnect" : "Connect"
  }

  var controllerConnectionActionUnavailableReason: String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if controllerConnectionActionInProgress {
      return "The controller connection action is already in progress."
    }
    if let activeDiscoverySequenceID {
      return
        "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title) first."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress || motionAuthorizationActionInProgress
      || activeExplorationOperation != nil
    {
      return "Wait for the current operation."
    }
    if frameMode == .simulated {
      return simulatedLearningSnapshot?.currentOperation == nil
        ? nil : "Stop or finish the current simulated operation first."
    }
    if controllerLinkIsOpen { return nil }
    return passiveProbeUnavailableReason
  }

  var controllerAlarmEvidenceText: String? {
    guard frameMode == .live else { return nil }
    return machineSnapshot?.machine.blockers.compactMap { blocker in
      if case .controllerAlarm(let detail) = blocker { return detail }
      return nil
    }.first
  }

  var controllerAttentionText: String? {
    if let machineError { return machineError }
    if let blocker = machineSnapshot?.machine.blockers.first {
      return machineBlockerLabel(blocker)
    }
    guard let outcome = machineSnapshot?.machine.lastAlarmClearOutcome else { return nil }
    switch outcome {
    case .acknowledged:
      return nil
    case .refused, .controllerRejected, .unconfirmed:
      return outcome.actionableDescription
    }
  }

  var controllerLimitInputsText: String {
    guard frameMode == .live, let machine = machineSnapshot?.machine else {
      return "unknown — no LIVE controller sample"
    }
    switch machine.controllerAlarmClearReadiness {
    case .armed:
      return "clear — sampled Pn has no X/Y/Z"
    case .blockedByAxisLimit(let pins):
      return "asserted — Pn:\(pins)"
    case .limitStateUnknown:
      return "unknown — Connect to resample"
    case .unavailable:
      guard let status = machine.lastProbe?.latestStatusReport else {
        return "unknown — Connect to sample"
      }
      return status.controllerPins.hasAxisLimitAsserted
        ? "asserted — Pn:\(status.controllerPins.rawValue)"
        : "clear — sampled Pn has no X/Y/Z"
    }
  }

  var controllerAlarmUnlockReadinessText: String {
    guard frameMode == .live, let readiness = machineSnapshot?.machine.controllerAlarmClearReadiness
    else { return "not armed — no LIVE controller" }
    switch readiness {
    case .armed:
      return "armed — manual clear available"
    case .blockedByAxisLimit(let pins):
      return "blocked — Pn:\(pins) is physically asserted"
    case .limitStateUnknown:
      return "not armed — limit inputs unknown"
    case .unavailable:
      return "not armed — no current alarm"
    }
  }

  var controllerAlarmClearActionUnavailableReason: String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if frameMode == .simulated { return "SIMULATED owns no physical controller alarm." }
    if controllerAlarmClearInProgress { return "Clear Alarm is already in progress." }
    if controllerConnectionActionInProgress { return "Wait for the controller connection action." }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress || motionAuthorizationActionInProgress
      || machineSnapshot?.machine.operationInFlight == true
      || machineSnapshot?.currentOperation != .idle
      || activeExplorationOperation != nil || activeDiscoverySequenceID != nil
    {
      return "Wait for the current operation before clearing the controller alarm."
    }
    if let ambiguity = machineSnapshot?.machine.stickyAmbiguity {
      return ControllerAlarmClearRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    guard controllerAlarmEvidenceText != nil else {
      return ControllerAlarmClearRefusal.noCurrentAlarmEvidence.actionableDescription
    }
    guard let readiness = machineSnapshot?.machine.controllerAlarmClearReadiness else {
      return ControllerAlarmClearRefusal.currentLimitStateUnknown(
        "no current controller snapshot"
      ).actionableDescription
    }
    switch readiness {
    case .armed:
      return nil
    case .blockedByAxisLimit(let pins):
      return ControllerAlarmClearRefusal.axisLimitAsserted(pins).actionableDescription
    case .limitStateUnknown:
      return ControllerAlarmClearRefusal.currentLimitStateUnknown(
        "the latest alarm probe did not establish axis-limit inputs"
      ).actionableDescription
    case .unavailable:
      return ControllerAlarmClearRefusal.noCurrentAlarmEvidence.actionableDescription
    }
  }

  var frameModeSwitchUnavailableReason: String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if frameModeSwitchInProgress { return "A frame source switch is already in progress." }
    if activeExerciseAttemptOwnerID != nil {
      return "Finish or Cancel the active Learning Path attempt before changing frame source."
    }
    if activeDiscoverySequenceID != nil {
      return "Finish the active Human-Guided Discovery transaction first."
    }
    if activeExplorationOperation != nil {
      return "Wait for the current learning action before changing frame source."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress || machineSnapshot?.machine.operationInFlight == true
    {
      return "Wait for the current controller operation before changing frame source."
    }
    return nil
  }

  private(set) var observedDrawingTrialStep: ObservedDrawingTrialStep {
    get { activeLearningSession.drawingTrial.step }
    set { activeLearningSession.drawingTrial.step = newValue }
  }
  private(set) var selectedBoundaryDirection: BoundaryDirection {
    get { activeLearningSession.selectedBoundaryDirection }
    set { activeLearningSession.selectedBoundaryDirection = newValue }
  }
  private(set) var selectedLineDirection: BoundaryDirection {
    get { activeLearningSession.selectedLineDirection }
    set { activeLearningSession.selectedLineDirection = newValue }
  }

  var activeDiscoverySequenceID: DiscoverySequenceID? {
    discoveryTransactions.first { _, transaction in
      switch transaction.state {
      case .active, .cancelling: true
      case .notStarted, .succeeded, .failed, .cancelled: false
      }
    }?.key
  }

  var penInteractionCompleted: Bool {
    guard learningArtifactGraph.currentRevision(for: .penInteraction) != nil else { return false }
    return frameMode == .simulated
      ? simulatedLearningSnapshot?.penPose == .up
      : machineSnapshot?.machine.penState == .up
  }

  var relevantBoundaryObservationCount: Int {
    BoundaryDirection.allCases.filter {
      learningArtifactGraph.currentRevision(for: .boundarySideAggregate($0)) != nil
    }.count
  }

  var humanGuidedDiscoveryCurrentStep: HumanGuidedDiscoveryStep {
    switch currentLearningPathItemID {
    case .humanGuidedDiscovery(let step): step
    case .stage(.connect), .stage(.enableMotion), .stage(.humanGuidedDiscovery):
      .penInteraction
    case .stage(.observedDrawingTrials), .observedDrawingTrial:
      .calibratePenContactFromSparseMarks
    }
  }

  var currentLearningPathItemID: LearningPathItemID {
    LearningPathProjector().currentItemID(learningPathProjectionSnapshot(includeReset: false))
  }

  var learningPathItemPresentations: [LearningPathItemPresentation] {
    learningPathProjection(selectedItemID: currentLearningPathItemID).items
  }

  var resetAllLearningPlan: LearningVacatePlan? {
    makeLearningVacatePlan(
      scope: .all,
      anchor: .humanGuidedDiscovery(.penInteraction)
    )
  }

  func learningVacatePlan(from itemID: LearningPathItemID) -> LearningVacatePlan? {
    guard let anchor = itemID.learningRewindAnchor else { return nil }
    return makeLearningVacatePlan(scope: .from(anchor), anchor: anchor)
  }

  var learningVacateUnavailableReason: String? {
    if hasShutdown { return "The workspace is shutting down." }
    if activeExerciseAttemptID != nil {
      return "Cancel or finish the active exercise attempt before resetting learning."
    }
    if activeStopTarget != nil || activeExplorationOperation != nil {
      return "Stop or cancel the active learning operation and wait for settlement first."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress || machineSnapshot?.machine.operationInFlight == true
      || activeHardwareIntentCount > 0
    {
      return "Wait for the current controller or camera operation to settle first."
    }
    if let learningStickyAmbiguityReason {
      return
        "Resolve the sticky motion ambiguity before resetting learning: \(learningStickyAmbiguityReason)"
    }
    return nil
  }

  @discardableResult
  func performLearningVacate(_ plan: LearningVacatePlan) -> Bool {
    if let unavailableReason = learningVacateUnavailableReason {
      learningAuthorityError = unavailableReason
      return false
    }
    return performAvailableLearningVacate(plan)
  }

  private func performAvailableLearningVacate(_ plan: LearningVacatePlan) -> Bool {
    let freshPlan: LearningVacatePlan? =
      switch plan.scope {
      case .from:
        learningVacatePlan(from: plan.anchor)
      case .all:
        resetAllLearningPlan
      }
    guard freshPlan == plan else {
      learningAuthorityError =
        "Learning changed while the reset summary was open. Review the updated steps and try again."
      return false
    }
    guard persistLearningPathPrefixBeforeVacate(plan) else { return false }

    let rootKinds = Set(
      learningArtifactGraph.revisions.compactMap { revision -> LearningArtifactKind? in
        guard plan.expectedCurrentRevisionIDs.contains(revision.id), revision.state == .current
        else { return nil }
        return revision.kind
      }
    )
    var graph = learningArtifactGraph
    let invalidation = graph.invalidateCurrentRevisions(rootKinds: rootKinds)
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)

    switch plan.anchor {
    case .humanGuidedDiscovery(.penInteraction):
      clearPenLearningForRewind()
      clearBoundaryLearningForRewind()
      clearCalibrationLearningForRewind()
      clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      clearBoundaryLearningForRewind()
      clearCalibrationLearningForRewind()
      clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      clearCalibrationLearningForRewind(from: .calibrateCameraAndVisibleCap)
      clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      clearCalibrationLearningForRewind(from: .calibratePenContactFromSparseMarks)
      clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    case .observedDrawingTrial(let step):
      clearDrawingLearningForRewind(from: step)
    case .stage:
      learningAuthorityError = "The requested Learning Path row is not a rewind anchor."
      return false
    }

    activeLearningSession.exerciseAttempt.finish()
    restartableExerciseItemID = nil
    explorationError = nil
    learningAuthorityError = nil

    if plan.removesDurableMachineCheckpoint {
      parkedAcceptedMachineArtifactCheckpoint = nil
      pendingMachineCameraCheckpoint = nil
      acceptedArtifactCheckpointStatus = .cleared
    }
    if plan.removesDurableTipCheckpoint {
      quarantinedTipCalibrationCheckpoint = nil
    }
    return true
  }

  private func persistLearningPathPrefixBeforeVacate(_ plan: LearningVacatePlan) -> Bool {
    guard frameMode == .live, let actions = activeAcceptedLearningPathCheckpointActions else {
      return true
    }
    do {
      if plan.anchor == .humanGuidedDiscovery(.penInteraction) {
        try actions.clear()
        acceptedLearningPathCheckpoint = nil
        acceptedStageFourCheckpoint = nil
        return true
      }

      let order = LearningPathItemID.learningExerciseOrder
      let anchorIndex = order.firstIndex(of: plan.anchor)!
      let boundaryIndex = order.firstIndex(
        of: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      )!
      let cameraIndex = order.firstIndex(
        of: .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
      )!
      let tipIndex = order.firstIndex(
        of: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
      )!
      let checkpoint = try AcceptedLearningPathCheckpoint(
        semanticIdentity: currentLearningPathSemanticIdentity,
        penInteraction: currentAcceptedPenInteractionCheckpoint(),
        machineArtifacts: anchorIndex > boundaryIndex
          ? parkedAcceptedMachineArtifactCheckpoint : nil,
        machineCamera: anchorIndex > cameraIndex
          ? currentAcceptedMachineCameraCheckpoint() ?? pendingMachineCameraCheckpoint : nil,
        tipCalibration: anchorIndex > tipIndex
          ? acceptedLearningPathCheckpoint?.tipCalibration
            ?? quarantinedTipCalibrationCheckpoint : nil,
        stageFour: nil
      )
      try actions.save(checkpoint)
      acceptedLearningPathCheckpoint = checkpoint
      acceptedStageFourCheckpoint = nil
      return true
    } catch {
      learningAuthorityError =
        "The durable Learning Path checkpoint could not be updated; no reset was applied: \(error)"
      return false
    }
  }

  private func makeLearningVacatePlan(
    scope: LearningVacateScope,
    anchor: LearningPathItemID
  ) -> LearningVacatePlan? {
    guard let anchorIndex = LearningPathItemID.learningExerciseOrder.firstIndex(of: anchor)
    else { return nil }
    let currentRevisions = learningArtifactGraph.revisions.filter { $0.state == .current }
    let revisionIDs = Set(
      currentRevisions.compactMap { revision -> LearningArtifactRevisionID? in
        guard let item = learningPathItemID(for: revision.kind),
          let index = LearningPathItemID.learningExerciseOrder.firstIndex(of: item),
          index >= anchorIndex
        else { return nil }
        return revision.id
      })
    guard !revisionIDs.isEmpty || hasVacatablePayload(atOrAfter: anchorIndex) else { return nil }

    var endIndex = anchorIndex
    for revision in currentRevisions {
      guard let item = learningPathItemID(for: revision.kind),
        let index = LearningPathItemID.learningExerciseOrder.firstIndex(of: item)
      else { continue }
      endIndex = max(endIndex, index)
    }
    if let currentAnchor = currentLearningPathItemID.learningRewindAnchor,
      let currentIndex = LearningPathItemID.learningExerciseOrder.firstIndex(of: currentAnchor)
    {
      endIndex = max(endIndex, currentIndex)
    }

    let source: LearningVacateSource = frameMode == .live ? .live : .simulated
    let boundaryIndex = LearningPathItemID.learningExerciseOrder.firstIndex(
      of: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    )!
    let tipIndex = LearningPathItemID.learningExerciseOrder.firstIndex(
      of: .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    )!
    return LearningVacatePlan(
      scope: scope,
      source: source,
      anchor: anchor,
      affectedItems: Array(LearningPathItemID.learningExerciseOrder[anchorIndex...endIndex]),
      expectedCurrentRevisionIDs: revisionIDs,
      expectedAcceptedAttemptSequence: acceptedAttemptSequence,
      removesDurableMachineCheckpoint:
        source == .live && anchorIndex <= boundaryIndex
        && (parkedAcceptedMachineArtifactCheckpoint != nil
          || acceptedLearningPathCheckpoint?.machineArtifacts != nil),
      removesDurableTipCheckpoint:
        source == .live && anchorIndex <= tipIndex
        && (quarantinedTipCalibrationCheckpoint != nil
          || tipCameraRegistration != nil
          || acceptedLearningPathCheckpoint?.tipCalibration != nil),
      physicalInkMayRemain: drawingTrialStrokeEvidence != nil || lastInkObservation != nil
    )
  }

  private func learningPathItemID(for kind: LearningArtifactKind) -> LearningPathItemID? {
    switch kind {
    case .penInteraction:
      .humanGuidedDiscovery(.penInteraction)
    case .boundarySideAggregate, .estimatedMachineCenter, .centerArrival:
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    case .machineCameraRegistration:
      .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    case .toolContactObservation, .tipCameraRegistration:
      .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    case .linePlan, .localPreLineBaseline, .lineExecution, .postLineFrame,
      .inkObservation, .residual, .comparison:
      .observedDrawingTrial(.chooseIsolatedLinePlan)
    }
  }

  private func hasVacatablePayload(atOrAfter anchorIndex: Int) -> Bool {
    if let currentAnchor = currentLearningPathItemID.learningRewindAnchor,
      let currentIndex = LearningPathItemID.learningExerciseOrder.firstIndex(of: currentAnchor),
      currentIndex > anchorIndex
    {
      return true
    }
    func includes(_ item: LearningPathItemID) -> Bool {
      guard let index = LearningPathItemID.learningExerciseOrder.firstIndex(of: item) else {
        return false
      }
      return index >= anchorIndex
    }
    if includes(.humanGuidedDiscovery(.penInteraction)),
      !penAttemptHistory.records.isEmpty || discoveryTransactions[.penInteraction] != nil
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)),
      !boundaryAttemptHistories.isEmpty || !boundarySideAggregates.isEmpty
        || discoveryTransactions.keys.contains(where: { $0 != .penInteraction })
        || centerArrivalPosition != nil
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.calibrateCameraAndVisibleCap)),
      cameraCalibrationAnchorFrame != nil || proposedMachineCameraRegistration != nil
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.calibratePenContactFromSparseMarks)),
      tipCameraRegistration != nil || proposedTipCameraRegistration != nil
        || quarantinedTipCalibrationCheckpoint != nil
        || !sparseTipCalibrationCoordinator.acceptedObservations.isEmpty
    {
      return true
    }
    if includes(.observedDrawingTrial(.chooseIsolatedLinePlan)),
      drawingTrialLineStart != nil || localPreLineBaseline != nil
        || drawingTrialStrokeEvidence != nil
        || explorationPostLineFrame != nil || drawingTrialAssessment != nil
        || !comparisonAttemptHistories.isEmpty
    {
      return true
    }
    return false
  }

  var contextualStopPresentation: ContextualStopPresentation? {
    learningPathProjection(selectedItemID: currentLearningPathItemID).contextualStop
  }

  var manualMotionPresentation: ManualMotionPresentation {
    let stopAction: ContextualStopActionPresentation?
    if let target = activeStopTarget, isManualStopTarget(target), stopDispositionLatch == nil {
      let isDrawing: Bool
      if case .manualDrawingStroke = target {
        isDrawing = true
      } else {
        isDrawing = false
      }
      stopAction = ContextualStopActionPresentation(
        capabilityID: target.capabilityID,
        title: isDrawing ? "Stop Manual Drawing" : "Stop Manual Jog",
        detail: isDrawing
          ? "Stop only this manual drawing stroke; the controller waits for Idle and performs its one typed Pen Up attempt."
          : "Stop only this manual jog and wait for its original owner to settle."
      )
    } else {
      stopAction = nil
    }
    return ManualMotionPresentation(
      stopAction: stopAction,
      jogUnavailableReason: motionUnavailableReason
    )
  }

  private func isManualStopTarget(_ target: ContextualStopTarget) -> Bool {
    switch target {
    case .manualJog, .manualDrawingStroke: true
    default: false
    }
  }

  func stopManualMotion(capabilityID: ContextualStopCapabilityID) async {

    guard let target = activeStopTarget,
      target.capabilityID == capabilityID,
      isManualStopTarget(target)
    else { return }
    await stopCurrentOperation(capabilityID: capabilityID)
  }

  var motionRequestStatusPresentation: MotionRequestStatusPresentation {
    if frameMode == .simulated {
      if simulatedLearningSnapshot?.currentOperation != nil || jogRequestInProgress
        || penRequestInProgress || jogCancelRequestInProgress || activeStopTarget != nil
      {
        return .busy(currentOperationText)
      }
      if let reason = motionUnavailableReason { return .unavailable(reason) }
      return .ready
    }
    if let ambiguity = machineSnapshot?.machine.stickyAmbiguity {
      return .needsAttention(ambiguity.actionableDescription)
    }
    if let controllerAttentionText { return .needsAttention(controllerAttentionText) }
    if jogRequestInProgress || penRequestInProgress || jogCancelRequestInProgress
      || activeStopTarget != nil
    {
      return .busy(currentOperationText)
    }
    if let reason = motionUnavailableReason { return .unavailable(reason) }
    return .ready
  }

  func refreshVideoSources() async {
    if frameMode == .simulated {
      await refreshSimulatedContent()
    } else {
      await discoverCameras()
    }
  }

  func selectAndStartCamera(_ id: CameraDeviceID) async {
    await selectCamera(id)
    guard selectedCameraID == id, cameraError == nil else { return }
    await startCamera()
  }

  func setVisionAnalysisCadence(_ cadence: VisionAnalysisCadence) async {
    guard visionAnalysisCadence != cadence else { return }
    visionAnalysisCadence = cadence
    await reconcileAutomaticVisionAnalysis()
  }

  func setVideoAnalysisRegion(
    _ region: PixelRect?,
    for displayedFrame: DisplayedFrame
  ) async {
    guard
      region == nil
        || cameraFrameIntersection(
          region!,
          frameWidth: displayedFrame.frame.width,
          frameHeight: displayedFrame.frame.height
        ) == region
    else {
      cameraError = "The requested analysis region is outside the current camera frame."
      return
    }
    let fullFrame = PixelRect(
      x: 0,
      y: 0,
      width: displayedFrame.frame.width,
      height: displayedFrame.frame.height
    )
    let canonicalRegion = region == fullFrame ? nil : region
    videoAnalysisRegionLock = canonicalRegion.map {
      VideoAnalysisRegionLock(
        source: displayedFrame.source,
        cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
        region: $0
      )
    }
    await cameraActions?.setSceneAnalysisRegion(
      frameMode == .live ? videoAnalysisRegionLock?.region : nil
    )
    await reconcileAutomaticVisionAnalysis()
  }

  var currentExerciseActionStripPresentation: ExerciseActionStripPresentation? {
    learningPathProjection(selectedItemID: currentLearningPathItemID).currentActionStrip
  }

  func selectedOperatorActionPresentation(
    for itemID: LearningPathItemID
  ) -> OperatorActionPresentation {
    learningPathProjection(selectedItemID: itemID).selectedAction
  }

  func learningPathProjection(
    selectedItemID: LearningPathItemID
  ) -> LearningPathProjection {
    LearningPathProjector().project(
      learningPathProjectionSnapshot(includeReset: true),
      selectedItemID: selectedItemID
    )
  }

  private func learningPathProjectionSnapshot(
    includeReset: Bool
  ) -> LearningPathProjectionSnapshot {
    let currentPosition = try? currentMachinePosition()
    let centerTravelFeed: TravelFeedSelection? =
      if let center = estimatedMachineCenter,
        let currentPosition,
        let delta = try? Vector2<MachineSpace>(
          dx: center.point.x - currentPosition.point.x,
          dy: center.point.y - currentPosition.point.y
        )
      {
        travelFeedSelection(for: delta)
      } else { nil }
    let boundaryTravelFeeds = Dictionary(
      uniqueKeysWithValues: BoundaryDirection.allCases.map {
        ($0, boundaryTravelFeedSelection())
      }
    )
    let stopOwner: LearningPathProjectionSnapshot.StopOwner? = {
      guard let target = activeStopTarget else { return nil }
      switch target {
      case .pairedBoundary(let id, let transactionID, _, _, let direction):
        let sequence = sequenceID(for: direction)
        guard discoveryTransactions[sequence]?.id == transactionID,
          case .awaitContextualStop(direction) = discoveryTransactions[sequence]?.currentStep?
            .action
        else { return nil }
        return .pairedBoundary(id, direction)
      case .manualJog(let id, _): return .manualJog(id)
      case .manualDrawingStroke(let id, _): return .manualDrawing(id)
      case .exerciseMotion(let id, let owner, _, let action):
        return .exercise(id, action, boundaryOwner: owner.isBoundaryOwner)
      case .drawingTrial(let id, _): return .drawingTrial(id)
      case .sparseTipBatch(let id, _), .sparseTipBatchSegment(let id, _, _):
        return .sparseTipBatch(id)
      }
    }()
    let itemStartReasons = Dictionary(
      uniqueKeysWithValues: LearningPathItemID.learningExerciseOrder.compactMap {
        itemID -> (LearningPathItemID, String)? in
        let reason: String?
        switch itemID {
        case .humanGuidedDiscovery(.penInteraction):
          reason = discoveryStartUnavailableReason(for: .penInteraction)
        case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
          reason = discoveryStartUnavailableReason(for: sequenceID(for: selectedBoundaryDirection))
        case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
          .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
          reason =
            frameMode == .simulated || cameraIsLive
            ? nil : "A current LIVE camera frame is required."
        case .observedDrawingTrial(let step):
          reason = drawingTrialActionUnavailableReason(
            for: step == .chooseIsolatedLinePlan ? observedDrawingTrialStep : step
          )
        case .stage:
          reason = nil
        }
        return reason.map { (itemID, $0) }
      }
    )
    let resetFacts: LearningPathProjectionSnapshot.ResetFacts
    if includeReset {
      let plans = Dictionary(
        uniqueKeysWithValues: LearningPathItemID.learningExerciseOrder.compactMap { itemID in
          learningVacatePlan(from: itemID).map { (itemID, $0) }
        }
      )
      resetFacts = .init(
        plansByAnchor: plans,
        resetAllPlan: resetAllLearningPlan,
        unavailableReason: learningVacateUnavailableReason,
        authorityError: learningAuthorityError
      )
    } else {
      resetFacts = .init()
    }
    let savedCheckpointMatchesPaper =
      quarantinedTipCalibrationCheckpoint.map {
        $0.registration.applicability.paperContactPlane.rawValue
          == explorationPaperContactPlaneRevision
      } ?? false
    return LearningPathProjectionSnapshot(
      source: frameMode,
      learningEnabled: learningIsEnabled,
      penInteractionCompleted: penInteractionCompleted,
      penActuationProfile: effectivePenActuationProfile,
      selectedBoundaryDirection: selectedBoundaryDirection,
      controller: .init(
        sessionEstablished: controllerSessionEstablished,
        motionAuthorized: motionAuthorizationEnabled,
        connectionText: controllerConnectionText,
        cameraStateText: cameraStateText,
        motionGuardStateText: motionGuardStateText,
        connectionActionTitle: controllerConnectionActionTitle,
        workbenchStatusText: workbenchStatusText,
        machineError: controllerAttentionText,
        directMotionUnavailableReason: directCarriageMotionUnavailableReason
      ),
      boundary: .init(
        acceptedDirections: pairedBoundaryProgress.acceptedDirections,
        allowedDirections: pairedBoundaryProgress.allowedDirections,
        isComplete: pairedBoundaryProgress.isComplete,
        aggregates: boundarySideAggregates,
        attemptEvidence: boundaryAttemptEvidenceByAttemptID,
        estimatedCenter: estimatedMachineCenter,
        localFrame: learnedLocalCoordinateFrame,
        centerArrival: centerArrivalPosition,
        centerArrivalRetryRequired: centerArrivalRetryRequired,
        currentPosition: currentPosition,
        centerTravelFeed: centerTravelFeed,
        boundaryTravelFeeds: boundaryTravelFeeds,
        latestActivity: boundaryActivityRecords.last
      ),
      cameraCalibration: .init(
        accepted: machineCameraRegistration,
        proposed: proposedMachineCameraRegistration,
        acceptedIsCurrent: machineCameraRegistration != nil
          && learningArtifactGraph.currentRevision(for: .machineCameraRegistration) != nil,
        hasProposal: proposedMachineCameraRegistration != nil,
        phase: currentCameraCalibrationPhase,
        failureRecovery: currentCameraCalibrationFailure?.recovery
      ),
      sparseCalibration: .init(
        accepted: tipCameraRegistration,
        proposed: proposedTipCameraRegistration,
        acceptedIsCurrent:
          tipCameraRegistration.map {
            learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
              == $0.acceptedRevisionID
          } ?? false,
        phase: sparseTipCalibrationCoordinator.phase,
        acceptedObservationCount: sparseTipCalibrationCoordinator.acceptedObservations.count,
        collectedClickCount: sparseTipCalibrationCoordinator.collectedClickCount,
        blacklistedPositionCount: sparseTipCalibrationCoordinator.blacklistedPositions.count,
        savedCheckpointMatchesPaper: savedCheckpointMatchesPaper
      ),
      drawing: .init(
        currentStep: observedDrawingTrialStep,
        selectedDirection: selectedLineDirection,
        lineStart: drawingTrialLineStart,
        lineEnd: drawingTrialLineEnd,
        localBaselineFrameID: localPreLineBaseline?.frame.id.rawValue,
        strokeSettled: drawingTrialStrokeEvidence != nil,
        inkStatus: explorationInkStatus,
        assessment: drawingTrialAssessment,
        lastTravelFeed: lastTravelFeedSelection
      ),
      operations: .init(
        activeAttemptOwner: activeExerciseAttemptOwnerID,
        restartableItem: restartableExerciseItemID,
        stopOwner: stopOwner,
        stopDispositionLatched: stopDispositionLatch != nil,
        stickyAmbiguityReason: learningStickyAmbiguityReason,
        explorationFailure: explorationError.map(WorkflowFailure.failed),
        discoveryFailure: discoveryError.map(WorkflowFailure.failed),
        lastStopAudit: lastContextualStopAuditRecord,
        scopedVisionActive: scopedVisionAnalysisActive,
        visionAnalysisActive: visionAnalysisSnapshot.activeFrameSequence != nil,
        workflowVisionActive: exclusiveWorkflowVisionRequestCount > 0,
        visionState: visionAnalysisSnapshot.state
      ),
      discovery: discoveryTransactions.mapValues { transaction in
        LearningPathProjectionSnapshot.DiscoveryFacts(
          id: transaction.id,
          sequenceID: transaction.definition.id,
          title: transaction.definition.title,
          state: transaction.state,
          currentStep: transaction.currentStep,
          completedStepCount: transaction.completedStepCount,
          totalStepCount: transaction.definition.steps.count,
          evidenceSummaries: transaction.evidenceSummaries.map(\.summary)
        )
      },
      startUnavailableReasons: itemStartReasons,
      acceptedCheckpointStatus: acceptedArtifactCheckpointStatus,
      reset: resetFacts
    )
  }

  func selectBoundaryDirection(_ direction: BoundaryDirection) {
    guard !hasShutdown, activeDiscoverySequenceID == nil,
      pairedBoundaryProgress.allowedDirections.contains(direction)
    else { return }
    selectedBoundaryDirection = direction
  }

  func answerCurrentQuestion(_ choice: OperatorChoice) async {
    guard let sequenceID = activeDiscoverySequenceID else { return }
    await answerDiscoverySequence(choice, for: sequenceID)
  }

  func performExerciseAction(
    _ kind: ExerciseActionKind,
    for ownerID: LearningPathItemID
  ) async {
    guard learningIsEnabled else { return }
    if case .selectDirection(let purpose, let direction) = kind {
      guard !hasShutdown,
        let selection = selectedOperatorActionPresentation(for: ownerID).actionStrip?
          .directionSelection,
        selection.purpose == purpose,
        selection.options.contains(direction)
      else { return }
      switch purpose {
      case .boundary: selectBoundaryDirection(direction)
      }
      return
    }
    if case .setPenSetpoint(let command, let value) = kind {
      guard !hasShutdown,
        let adjustment = selectedOperatorActionPresentation(for: ownerID).actionStrip?
          .penSetpointAdjustment,
        adjustment.command == command,
        (adjustment.minimumValue...adjustment.maximumValue).contains(value)
      else { return }
      setPenActuationValue(value, for: command)
      return
    }
    guard !hasShutdown,
      let strip = selectedOperatorActionPresentation(for: ownerID).actionStrip,
      strip.ownerID == ownerID,
      let action = strip.actions.first(where: { $0.kind == kind }),
      action.isEnabled
    else { return }

    switch kind {
    case .start:
      await startExercise(ownerID, mode: .normal)
    case .choice(let choice):
      guard ownerID == activeExerciseAttemptOwnerID else { return }
      await answerCurrentQuestion(choice)
    case .setPenSetpoint:
      return
    case .cancel:
      await cancelExerciseAttempt(ownerID)
    case .stop(let capabilityID):
      guard ownerID == activeExerciseAttemptOwnerID else { return }
      await stopCurrentOperation(capabilityID: capabilityID)
    case .restart:
      guard restartableExerciseItemID == ownerID else { return }
      restartableExerciseItemID = nil
      await startExercise(ownerID, mode: .normal)
    case .redoThisStep:
      await startExercise(ownerID, mode: .replacement)
    case .recordAnotherAttempt:
      await startExercise(ownerID, mode: .additional)
    case .redoBoundary(let direction):
      guard ownerID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering) else {
        return
      }
      selectedBoundaryDirection = direction
      await beginPairedBoundarySide(direction, mode: .replacement)
    case .recordAnotherBoundaryAttempt(let direction):
      guard ownerID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering) else {
        return
      }
      selectedBoundaryDirection = direction
      await beginPairedBoundarySide(direction, mode: .additional)
    case .selectDirection:
      return
    case .moveToEstimatedCenter:
      await moveToEstimatedCenter()
    case .runCameraCalibrationAndBuildProposal:
      await runCameraCalibrationAndBuildProposal()
    case .acceptCameraCalibrationProposal:
      acceptCameraCalibrationProposal()
    case .rejectCameraCalibrationProposal:
      rejectCameraCalibrationProposal()
    case .drawFiveSparseTipCircles:
      await drawFiveSparseTipCircles()
    case .undoLastSparseTipClick:
      undoLastSparseTipClick()
    case .clearSparseTipClicks:
      clearSparseTipClicks()
    case .revalidateTipCalibrationCheckpoint:
      await revalidateTipCalibrationCheckpoint()
    case .acceptTipCalibrationProposal:
      _ = commitTipCalibration(actor: "operator-accepted-proposal")
    case .rejectTipCalibrationProposal:
      rejectTipCalibrationProposal()
    case .retryTipCalibrationCommit:
      _ = commitTipCalibration(actor: "operator-retry")
    case .paperReplaced:
      await recordPaperReplaced()
    }
  }

  func beginPenInteraction() async {
    await beginPenInteraction(mode: .normal)
  }

  private func beginPenInteraction(mode: ExerciseAttemptMode) async {
    guard discoveryStartUnavailableReason(for: .penInteraction) == nil else { return }
    cancelPenCapAcceptedClickContinuation()
    beginExerciseAttempt(
      ownerID: .humanGuidedDiscovery(.penInteraction),
      mode: mode
    )
    do {
      let boundary = displayedFrame?.frame.captureNanoseconds ?? 0
      var frame: DisplayedFrame?
      if frameMode == .live, livePenCapAppearanceSelection != nil, sceneAnalysisIsRequested {
        do {
          if let inspection = try await inspectWorkflowScene(
            newerThan: boundary,
            requestedFeatures: requestedSceneFeatures,
            analysisRegion: videoAnalysisRegionLock?.region
          ) {
            frame = inspection.displayedFrame
            displayedFrame = inspection.displayedFrame
            latestLiveCameraFrame = inspection.displayedFrame
            lastSceneMeasurement = inspection.measurement
            overlayResultChannels.publishScene(
              overlayChannelResult(
                displayedFrame: inspection.displayedFrame,
                measurement: inspection.measurement
              )
            )
          }
        } catch {
          visionError =
            "Frozen-frame overlay analysis failed — \(actionableDescription(error))"
        }
      }
      if frame == nil {
        frame = try await captureProtocolFrame(newerThan: boundary)
      }
      guard let frame else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
      let exact = try exactTipCalibrationFrame(frame)
      penCapAppearanceSelectionContext = PenCapAppearanceSelectionContext(
        frame: frame,
        request: ActionSurfacePointSelectionRequest(
          frame: exact,
          presentationTransformRevision: PresentationTransformRevision(),
          prompt: "Click the pen cap body—not the tip—on the current camera frame.",
          purpose: .penCapAppearance
        )
      )
      discoveryError = nil
    } catch {
      discoveryError =
        "Identify Pen Cap could not freeze an exact frame: \(actionableDescription(error))"
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = .humanGuidedDiscovery(.penInteraction)
    }
  }

  func beginPairedBoundarySide(_ direction: BoundaryDirection) async {
    await beginPairedBoundarySide(direction, mode: .normal)
  }

  private func beginPairedBoundarySide(
    _ direction: BoundaryDirection,
    mode: ExerciseAttemptMode
  ) async {
    let sequenceID = sequenceID(for: direction)
    let directionIsAdmissible =
      if mode == .replacement || mode == .additional {
        boundarySideAggregates[direction] != nil
      } else {
        pairedBoundaryProgress.allowedDirections.contains(direction)
      }
    guard directionIsAdmissible,
      discoveryStartUnavailableReason(for: sequenceID) == nil
    else { return }
    selectedBoundaryDirection = direction
    let jogDirection = jogDirection(from: direction)
    boundaryTeachingState = .awaitingOwnerAdmission(jogDirection)
    boundaryTeachingResultText =
      "\(jogDirection.shortLabel) selected. Start accepted; admitting one logical Boundary Discovery owner."
    beginExerciseAttempt(
      ownerID: .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      mode: mode
    )
    await startDiscoverySequence(sequenceID)
  }

  private func moveToEstimatedCenter() async {
    guard let center = estimatedMachineCenter else { return }
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .pairedBoundaryDiscoveryAndCentering
    )
    beginExerciseAttempt(ownerID: ownerID, mode: activeExerciseAttemptMode ?? .normal)
    do {
      let current = try currentMachinePosition()
      let destination = try MachinePosition(x: center.point.x, y: center.point.y)
      let delta = try Vector2<MachineSpace>(
        dx: destination.point.x - current.point.x,
        dy: destination.point.y - current.point.y
      )
      if delta.dx != 0 || delta.dy != 0 {
        let final = try await performSupervisedPenUpTravel(
          delta: delta,
          ownerID: ownerID,
          action: .moveToEstimatedCenter
        )
        _ = recordProtocolPoseSettlement(
          action: .moveToEstimatedCenter,
          target: destination,
          actual: final,
          toleranceMM: MachinePositionAcceptancePolicy.toleranceMM
        )
        guard MachinePositionAcceptancePolicy.accepts(final, target: destination) else {
          let residual = lastProtocolPoseSettlement?.residualMM ?? .infinity
          throw LearningPathOperationError.controllerFailed(
            String(
              format:
                "Center travel settled %.3f mm from the target, outside the %.3f mm tolerance. "
                + "The four accepted boundaries remain current; Retry Center Arrival "
                + "recomputes only the remaining delta.",
              residual,
              MachinePositionAcceptancePolicy.toleranceMM
            )
          )
        }
      }
      guard let attemptID = activeExerciseAttemptID,
        let centerRevision = learningArtifactGraph.currentRevision(for: .estimatedMachineCenter)?.id
      else {
        throw LearningPathOperationError.requiredState(
          "The accepted estimated-center artifact is unavailable."
        )
      }
      var graph = learningArtifactGraph
      let commit = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .centerArrival,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [centerRevision]
        )
      )
      learningArtifactGraph = graph
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
      centerArrivalPosition = destination
      centerArrivalRetryRequired = false
      explorationError = nil
      persistAcceptedMachineArtifacts()
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      let failure = workflowFailure(for: error)
      explorationError = failure.detail
      if activeExerciseAttemptOwnerID == ownerID {
        finishActiveExerciseAttempt(disposition: failure.attemptDisposition)
      }
      centerArrivalRetryRequired = true
      restartableExerciseItemID = nil
    }
  }

  private func captureProtocolFrame(newerThan boundary: UInt64) async throws -> DisplayedFrame {
    guard let cameraActions else { throw LearningPathOperationError.freshFrameUnavailable }
    if frameMode == .simulated {
      let scene = try await captureSimulatedProtocolScene(newerThan: boundary)
      guard
        scene.displayedFrame.frame.captureNanoseconds
          > lastSimulatedProtocolCaptureNanoseconds
      else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
      lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
      applySimulatedProtocolScene(scene)
      return scene.displayedFrame
    }
    guard let frame = try await cameraActions.captureFrame(boundary),
      frame.frame.captureNanoseconds > boundary
    else { throw LearningPathOperationError.freshFrameUnavailable }
    displayedFrame = frame
    latestLiveCameraFrame = frame
    return frame
  }

  private func captureSimulatedProtocolScene(
    newerThan captureNanoseconds: UInt64 = 0
  ) async throws -> SimulatedLearningSceneFrame {
    let acceptedPositions = Dictionary(
      uniqueKeysWithValues: boundarySideAggregates.compactMap {
        direction, aggregate -> (BoundaryDirection, SimulatedLearningMPos)? in
        guard let attemptID = aggregate.includedAttemptIDs.last,
          let evidence = boundaryAttemptEvidenceByAttemptID[attemptID],
          let position = try? SimulatedLearningMPos(
            xMM: evidence.finalPosition.point.x,
            yMM: evidence.finalPosition.point.y
          )
        else { return nil }
        return (direction, position)
      })
    let learnedCenter = estimatedMachineCenter.flatMap {
      try? SimulatedLearningMPos(xMM: $0.point.x, yMM: $0.point.y)
    }
    let scene = try await simulatedLearningRuntime.captureSceneFrame(
      annotationContext: SimulatedLearningAnnotationContext(
        acceptedBoundaryPositions: acceptedPositions,
        learnedCenter: learnedCenter
      ),
      newerThanCaptureNanoseconds: captureNanoseconds
    ).result.get()
    simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    return scene
  }

  private func applySimulatedProtocolScene(_ scene: SimulatedLearningSceneFrame) {
    displayedFrame = scene.displayedFrame
    simulatedAnnotations = scene.annotations
    simulatedViewportID = scene.viewportID
    let provenance = ExactFrameOverlayProvenance(scene.displayedFrame)
    let overlays = [
      CameraOverlayMeasurement(
        frameID: scene.displayedFrame.frame.id,
        cameraConfigurationID: scene.displayedFrame.frame.cameraConfigurationID,
        geometry: .point(scene.capAnchorPoint),
        provenance: CameraMeasurementProvenance(
          kind: .penCap,
          source: .simulated,
          algorithmRevision: "causal-learning-simulator-v1"
        )
      ),
      CameraOverlayMeasurement(
        frameID: scene.displayedFrame.frame.id,
        cameraConfigurationID: scene.displayedFrame.frame.cameraConfigurationID,
        geometry: .bounds(scene.armatureBounds),
        provenance: CameraMeasurementProvenance(
          kind: .armatureEstimate,
          source: .simulated,
          algorithmRevision: "causal-learning-simulator-v1"
        )
      ),
    ]
    let frameSequence = scene.displayedFrame.frame.sequence
    let statuses: [UserSceneOverlay: OverlayLayerStatus] = [
      .penCap: OverlayLayerStatus(
        state: .available,
        message: OverlayStatusGrammar.simulatedPenCapAvailable(frame: frameSequence),
        provenance: provenance
      ),
      .armatureEnvelope: OverlayLayerStatus(
        state: .available,
        message: OverlayStatusGrammar.simulatedArmatureAvailable(frame: frameSequence),
        provenance: provenance
      ),
    ]
    overlayResultChannels.publishSimulation(
      OverlayChannelResult(
        displayedFrame: scene.displayedFrame,
        overlays: overlays,
        statuses: statuses
      )
    )
    simulatorPenState = simulatedLearningSnapshot?.penPose == .down ? .down : .up
    simulatorLearningSummary =
      "causal scene · MPos X \(scene.controllerPosition.xMM) Y \(scene.controllerPosition.yMM) · persistent ink segments \(scene.inkSegmentCount)"
  }

  private func captureCameraCalibrationReference() async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    if activeExerciseAttemptID == nil {
      beginExerciseAttempt(ownerID: ownerID, mode: activeExerciseAttemptMode ?? .normal)
    }
    guard centerArrivalPosition != nil else { return }
    do {
      let targetMachinePosition = try currentMachinePosition()
      let frame = try await captureProtocolFrame(
        newerThan: cameraCalibrationAnchorFrame?.frame.captureNanoseconds ?? 0
      )
      let centroid: Point2<CameraPixelSpace>
      let bounds: AxisAlignedBounds<CameraPixelSpace>
      let confidence: Double
      var registrationFrame = frame
      if frameMode == .simulated {
        guard
          let point = overlayResultChannels.simulation?.overlays.compactMap({
            overlay -> Point2<CameraPixelSpace>? in
            guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
            else { return nil }
            return point
          }).first,
          let armatureBounds = overlayResultChannels.simulation?.overlays.compactMap({
            overlay
              -> AxisAlignedBounds<CameraPixelSpace>? in
            guard overlay.provenance.kind == .armatureEstimate,
              case .bounds(let bounds) = overlay.geometry
            else { return nil }
            return bounds
          }).first
        else {
          throw LearningPathOperationError.requiredState(
            "Cap-anchor and armature overlays are unavailable."
          )
        }
        bounds = armatureBounds
        centroid = try Point2(
          x: (armatureBounds.minX + armatureBounds.maxX) / 2,
          y: (armatureBounds.minY + armatureBounds.maxY) / 2
        )
        guard abs(point.x - centroid.x) <= 0.001,
          abs(point.y - armatureBounds.maxY) <= 0.001
        else {
          throw LearningPathOperationError.requiredState(
            "The causal simulator cap anchor does not match the armature bottom-center."
          )
        }
        confidence = 1
      } else {
        let stable = try await captureStableWorkflowCap(
          newerThan: frame.frame.captureNanoseconds - 1
        )
        let inspection = stable.inspection
        let cap = stable.cap
        centroid = cap.centroid
        bounds = try AxisAlignedBounds(
          minX: Double(cap.boundingBox.x),
          minY: Double(cap.boundingBox.y),
          maxX: Double(cap.boundingBox.x + cap.boundingBox.width),
          maxY: Double(cap.boundingBox.y + cap.boundingBox.height)
        )
        confidence = cap.confidence
        displayedFrame = inspection.displayedFrame
        registrationFrame = inspection.displayedFrame
        publishWorkflowInspection(inspection, owner: .cameraCalibration)
      }
      cameraCalibrationAnchorFrame = registrationFrame
      cameraCalibrationReferencePosition = targetMachinePosition
      cameraCalibrationReferenceCapAnchor = try ToolCapAnchorEstimate(
        componentCentroid: centroid,
        componentBounds: bounds,
        confidence: confidence,
        estimatorRevision: penCapAnchorEstimatorRevision,
        source: registrationFrame.source,
        frameID: registrationFrame.frame.id,
        cameraConfigurationID: registrationFrame.frame.cameraConfigurationID
      )
      proposedMachineCameraRegistration = nil
      explorationError = nil
    } catch {
      explorationError =
        "Camera-calibration reference capture failed: \(actionableDescription(error))"
    }
  }

  /// Runs Stage 3.3 as one operator action. Recovery after an interrupted
  /// calibration retains the exact center reference and resumes at proposal
  /// construction instead of demanding a duplicate capture.
  private func runCameraCalibrationAndBuildProposal() async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    if activeExerciseAttemptOwnerID == nil {
      await startExercise(ownerID, mode: activeExerciseAttemptMode ?? .normal)
    }
    guard activeExerciseAttemptOwnerID == ownerID else { return }
    if cameraCalibrationAnchorFrame == nil {
      await captureCameraCalibrationReference()
    }
    guard cameraCalibrationAnchorFrame != nil,
      cameraCalibrationReferencePosition != nil
    else { return }
    await buildCameraCalibrationProposal()
  }

  private var penCapAnchorEstimatorRevision: String {
    "selected-cap-\(penCapAppearanceSelection?.color.hexRGB ?? "UNLEARNED")-bottom-center-anchor-v3"
  }

  private func compatibleRegistrationCapAnchorEvidence(
    for frame: DisplayedFrame
  ) -> [MachineCameraCorrespondenceProvenance] {
    explicitRegistrationCapAnchorEvidence.filter {
      $0.source == frame.source
        && $0.cameraConfigurationID == frame.frame.cameraConfigurationID
        && $0.controllerSessionID == controllerSessionID
        && $0.coordinateRevision == explorationCoordinateRevision
        && $0.capAnchorEstimatorRevision == penCapAnchorEstimatorRevision
    }
  }

  @discardableResult
  private func stageMachineCameraRegistrationProposal(
    correspondenceOverride: [MachineCameraCorrespondenceProvenance]? = nil,
    applicabilityRectangleOverride: AxisAlignedBounds<MachineSpace>? = nil
  ) -> Bool {
    guard let frame = cameraCalibrationAnchorFrame,
      let capAnchor = cameraCalibrationReferenceCapAnchor,
      capAnchor.frameID == frame.frame.id
    else { return false }
    do {
      let exactSamples =
        correspondenceOverride ?? compatibleRegistrationCapAnchorEvidence(for: frame)
      guard exactSamples.count == 5 else {
        explorationError =
          "Machine-camera registration requires exactly five compatible cap samples: three fit samples and two independent holdouts; \(exactSamples.count) are available."
        return false
      }
      let fitSamples = Array(exactSamples.prefix(3))
      let holdoutSamples = Array(exactSamples.suffix(2))
      let fitCorrespondences = fitSamples.map {
        MachineCameraRegistrationCorrespondence(
          machine: $0.machinePoint,
          camera: $0.capAnchorPoint
        )
      }
      let candidateFit = try MachineCameraRegistrationFit.fit(
        correspondences: fitCorrespondences,
        weights: fitSamples.map { max(0.01, $0.capAnchorConfidence * $0.capAnchorConfidence) }
      )
      let holdoutResiduals = try holdoutSamples.map {
        try candidateFit.cameraPoint(from: $0.machinePoint).distance(to: $0.capAnchorPoint)
      }
      guard holdoutResiduals.allSatisfy({ $0 <= 8 }) else {
        throw LearningPathOperationError.requiredState(
          "Independent cap holdouts failed (\(holdoutResiduals.map { String(format: "%.3f px", $0) }.joined(separator: ", "))). No camera proposal was staged."
        )
      }
      let correspondences = exactSamples.map {
        MachineCameraRegistrationCorrespondence(
          machine: $0.machinePoint,
          camera: $0.capAnchorPoint
        )
      }
      let finalFit = try MachineCameraRegistrationFit.fit(
        correspondences: correspondences,
        weights: exactSamples.map { max(0.01, $0.capAnchorConfidence * $0.capAnchorConfidence) }
      )
      let applicabilityRectangle =
        try applicabilityRectangleOverride
        ?? AxisAlignedBounds<MachineSpace>(
          minX: exactSamples.map(\.machinePoint.x).min()!,
          minY: exactSamples.map(\.machinePoint.y).min()!,
          maxX: exactSamples.map(\.machinePoint.x).max()!,
          maxY: exactSamples.map(\.machinePoint.y).max()!
        )
      let registration = try MachineCameraRegistration(
        candidateFit: candidateFit,
        fit: finalFit,
        source: frame.source,
        opticalConfiguration: try exactTipCalibrationFrame(frame).opticalConfiguration,
        machineGeometry: machineGeometryIdentity,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        cameraConfigurationID: frame.frame.cameraConfigurationID,
        fitCorrespondenceProvenance: fitSamples,
        holdoutCorrespondenceProvenance: holdoutSamples,
        maximumHoldoutResidualPixels: 8,
        estimatorRevision:
          "five-cap-affine-three-fit-two-holdout-v2:cap-\(penCapAppearanceSelection?.color.hexRGB ?? "UNLEARNED")",
        uncertaintyPixels: max(finalFit.maximumErrorPixels, holdoutResiduals.max() ?? 0),
        applicabilityRectangle: applicabilityRectangle,
        applicabilityDerivation: .boundaryEnvelopeInsetAndSymmetricallyReduced(
          safetyMarginMM: CurrentCameraCalibrationPlan.safetyMarginMM,
          maximumHalfSpanMM: CurrentCameraCalibrationPlan.maximumUnprovenHalfSpanMM
        )
      )
      proposedMachineCameraRegistration = registration
      explorationError = nil
      return true
    } catch {
      proposedMachineCameraRegistration = nil
      explorationError = "Machine-camera registration failed: \(actionableDescription(error))"
      return false
    }
  }

  /// Makes the reviewed five-sample cap-map proposal authoritative atomically.
  private func acceptCameraCalibrationProposal() {
    guard let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
      let centerArrival = learningArtifactGraph.currentRevision(for: .centerArrival)?.id,
      let registration = proposedMachineCameraRegistration
    else { return }
    do {
      var graph = learningArtifactGraph
      let machineRegistrationCandidate = LearningArtifactRevision(
        kind: .machineCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: Set(
          registration.correspondenceProvenance.map(\.artifactRevisionID)
            + [centerArrival]
        )
      )
      let machineRegistration = try graph.commitReplacement(machineRegistrationCandidate)
      learningArtifactGraph = graph
      applyArtifactInvalidations(machineRegistration.invalidatedRevisionIDs)
      machineCameraRegistration = registration
      proposedMachineCameraRegistration = nil
      pendingMachineCameraCheckpoint = currentAcceptedMachineCameraCheckpoint()
      persistAcceptedLearningPathCheckpoint(clearTip: true, clearStageFour: true)
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
    } catch {
      explorationError =
        "Camera-calibration acceptance failed atomically: \(actionableDescription(error))"
    }
  }

  private func buildCameraCalibrationProposal() async {
    guard currentCameraCalibrationTask == nil, !hasShutdown else { return }
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.executeCurrentCameraCalibrationAndBuildProposal()
    }
    currentCameraCalibrationTask = task
    await task.value
    currentCameraCalibrationTask = nil
  }

  private func executeCurrentCameraCalibrationAndBuildProposal() async {
    guard currentCameraCalibrationPhase == nil, !hasShutdown, !Task.isCancelled,
      let frame = cameraCalibrationAnchorFrame,
      let targetPosition = cameraCalibrationReferencePosition
    else { return }

    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibrateCameraAndVisibleCap
    )
    let operationID = UUID()
    let attemptID = activeExerciseAttemptID
    currentCameraCalibrationFailure = nil
    await recordWorkflowTelemetry(
      WorkflowTelemetryEvent(
        operationID: operationID,
        operation: .currentCameraCalibration,
        phase: .intentAccepted,
        attemptID: attemptID,
        detail: "Stage 3.3 five-position cap calibration accepted by the workflow coordinator."
      )
    )
    await updateCurrentCameraCalibrationPhase(
      .preparing,
      operationID: operationID,
      attemptID: attemptID
    )
    explorationError = nil
    defer { currentCameraCalibrationPhase = nil }

    do {
      var stagedSamples: [MachineCameraCorrespondenceProvenance] = []
      var contextBaseline: ControllerContextBaseline?
      let current = try currentMachinePosition()
      guard protocolPositionsMatch(current, targetPosition) else {
        throw LearningPathOperationError.requiredState(
          "Return to the recorded calibration reference pose before calibrating the current camera."
        )
      }
      let plan = try CurrentCameraCalibrationPlan(
        targetPosition: targetPosition,
        boundarySideAggregates: boundarySideAggregates,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision
      )

      await updateCurrentCameraCalibrationPhase(
        .capturing(sample: 1, total: 5, role: "C (fit)"),
        operationID: operationID,
        attemptID: attemptID
      )
      let firstCapture = try await captureCurrentCameraCapAnchorEvidence(
        contextBaseline: contextBaseline,
        operationID: operationID
      )
      stagedSamples.append(firstCapture.evidence)
      contextBaseline = firstCapture.contextBaseline
      try requireCalibrationContinuation()

      for sampleIndex in 1..<plan.samplePositions.count {
        try requireCalibrationContinuation()
        let expected = plan.samplePositions[sampleIndex]
        await updateCurrentCameraCalibrationPhase(
          .moving(sample: sampleIndex + 1, total: 5),
          operationID: operationID,
          attemptID: attemptID
        )
        let final = try await performSupervisedPenUpTravel(
          delta: plan.motionDeltas[sampleIndex - 1],
          ownerID: ownerID,
          action: .cameraCalibrationSample(index: sampleIndex + 1, total: 5)
        )
        try requireCalibrationContinuation()
        guard
          recordProtocolPoseSettlement(
            action: .cameraCalibrationSample(index: sampleIndex + 1, total: 5),
            target: expected,
            actual: final
          )
        else {
          throw LearningPathOperationError.controllerFailed(
            "Calibration travel did not settle at exact sample \(sampleIndex + 1) of 5."
          )
        }
        await updateCurrentCameraCalibrationPhase(
          .capturing(sample: sampleIndex + 1, total: 5, role: nil),
          operationID: operationID,
          attemptID: attemptID
        )
        let capture = try await captureCurrentCameraCapAnchorEvidence(
          contextBaseline: contextBaseline,
          operationID: operationID
        )
        stagedSamples.append(capture.evidence)
        contextBaseline = capture.contextBaseline
        try requireCalibrationContinuation()
      }

      try requireCalibrationContinuation()
      await updateCurrentCameraCalibrationPhase(
        .returningToReference,
        operationID: operationID,
        attemptID: attemptID
      )
      let returned = try await performSupervisedPenUpTravel(
        delta: plan.motionDeltas[4],
        ownerID: ownerID,
        action: .returnFromCameraCalibration
      )
      try requireCalibrationContinuation()
      guard
        recordProtocolPoseSettlement(
          action: .returnFromCameraCalibration,
          target: targetPosition,
          actual: returned
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Calibration return did not settle at the recorded reference pose."
        )
      }
      try requireCalibrationContinuation()
      await updateCurrentCameraCalibrationPhase(
        .fittingAndTestingHoldouts,
        operationID: operationID,
        attemptID: attemptID
      )
      guard
        stageMachineCameraRegistrationProposal(
          correspondenceOverride: stagedSamples,
          applicabilityRectangleOverride: plan.applicabilityRectangle
        )
      else {
        throw LearningPathOperationError.requiredState(
          explorationError ?? "The current-camera registration fit was not accepted."
        )
      }
      explicitRegistrationCapAnchorEvidence.removeAll {
        $0.source == frame.source
          && $0.cameraConfigurationID == frame.frame.cameraConfigurationID
          && $0.controllerSessionID == controllerSessionID
          && $0.coordinateRevision == explorationCoordinateRevision
      }
      explicitRegistrationCapAnchorEvidence.append(contentsOf: stagedSamples)
      currentCameraCalibrationFailure = nil
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: operationID,
          operation: .currentCameraCalibration,
          phase: .completed,
          attemptID: attemptID,
          detail:
            "Five exact cap samples passed three-fit/two-holdout validation and staged one reviewable all-five proposal."
        )
      )
    } catch  where hasShutdown || Task.isCancelled {
      return
    } catch {
      proposedMachineCameraRegistration = nil
      let failure = currentCameraCalibrationFailure(for: error, targetPosition: targetPosition)
      currentCameraCalibrationFailure = failure
      explorationError =
        "Current-camera calibration failed [\(failure.code.rawValue)]: \(failure.detail)"
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: operationID,
          operation: .currentCameraCalibration,
          phase: .failed,
          attemptID: attemptID,
          detail: failure.detail,
          failureCode: failure.code,
          recovery: failure.recovery
        )
      )
    }
  }

  /// Captures one exact current-camera machine/cap-anchor correspondence. Motion,
  /// sequencing, and target return remain owned by the automatic calibration.
  private func captureCurrentCameraCapAnchorEvidence(
    contextBaseline: ControllerContextBaseline?,
    operationID: UUID,
    newerThanNanoseconds: UInt64? = nil
  ) async throws -> CalibrationCapAnchorCapture {
    try requireCalibrationContinuation()
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState(
        "No active machine-camera calibration attempt owns this sample."
      )
    }
    guard
      let centerArrivalRevisionID = learningArtifactGraph.currentRevision(
        for: .centerArrival
      )?.id
    else {
      throw LearningPathOperationError.requiredState(
        "The accepted center-arrival coordinate artifact is unavailable."
      )
    }
    let beforeCapture = try await freshCalibrationMachineObservation(
      contextBaseline: contextBaseline,
      operationID: operationID
    )
    try requireCalibrationContinuation()
    let boundary = max(
      displayedFrame?.frame.captureNanoseconds ?? 0,
      newerThanNanoseconds ?? 0
    )
    let frame = try await captureProtocolFrame(newerThan: boundary)
    try requireCalibrationContinuation()
    let centroid: Point2<CameraPixelSpace>
    let bounds: AxisAlignedBounds<CameraPixelSpace>
    let confidence: Double
    var evidenceFrame = frame
    if frameMode == .simulated {
      guard
        let point = overlayResultChannels.simulation?.overlays.compactMap({
          overlay -> Point2<CameraPixelSpace>? in
          guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
          else { return nil }
          return point
        }).first,
        let armatureBounds = overlayResultChannels.simulation?.overlays.compactMap({
          overlay -> AxisAlignedBounds<CameraPixelSpace>? in
          guard overlay.provenance.kind == .armatureEstimate,
            case .bounds(let bounds) = overlay.geometry
          else { return nil }
          return bounds
        }).first
      else {
        throw LearningPathOperationError.requiredState(
          "Cap-anchor and armature overlays are unavailable."
        )
      }
      centroid = try Point2(
        x: (armatureBounds.minX + armatureBounds.maxX) / 2,
        y: (armatureBounds.minY + armatureBounds.maxY) / 2
      )
      guard abs(point.x - centroid.x) <= 0.001,
        abs(point.y - armatureBounds.maxY) <= 0.001
      else {
        throw LearningPathOperationError.requiredState(
          "The causal simulator cap anchor does not match the armature bottom-center."
        )
      }
      bounds = armatureBounds
      confidence = 1
    } else {
      let stable = try await captureStableWorkflowCap(
        newerThan: frame.frame.captureNanoseconds
      )
      let inspection = stable.inspection
      let cap = stable.cap
      try requireCalibrationContinuation()
      centroid = cap.centroid
      bounds = try AxisAlignedBounds(
        minX: Double(cap.boundingBox.x),
        minY: Double(cap.boundingBox.y),
        maxX: Double(cap.boundingBox.x + cap.boundingBox.width),
        maxY: Double(cap.boundingBox.y + cap.boundingBox.height)
      )
      confidence = cap.confidence
      evidenceFrame = inspection.displayedFrame
      displayedFrame = inspection.displayedFrame
      publishWorkflowInspection(inspection, owner: .cameraCalibration)
    }
    let capAnchor = try ToolCapAnchorEstimate(
      componentCentroid: centroid,
      componentBounds: bounds,
      confidence: confidence,
      estimatorRevision: penCapAnchorEstimatorRevision,
      source: evidenceFrame.source,
      frameID: evidenceFrame.frame.id,
      cameraConfigurationID: evidenceFrame.frame.cameraConfigurationID
    )
    let afterCapture = try await freshCalibrationMachineObservation(
      contextBaseline: beforeCapture.contextBaseline,
      operationID: operationID
    )
    try requireCalibrationContinuation()
    guard protocolPositionsMatch(beforeCapture.position, afterCapture.position) else {
      throw LearningPathOperationError.controllerFailed(
        "Controller MPos changed while the camera sample was being captured; the sample was discarded."
      )
    }
    return CalibrationCapAnchorCapture(
      evidence: MachineCameraCorrespondenceProvenance(
        machinePoint: afterCapture.position.point,
        capAnchorPoint: capAnchor.point,
        source: evidenceFrame.source,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        frameID: evidenceFrame.frame.id,
        frameSHA256: evidenceFrame.frame.contentSHA256,
        captureNanoseconds: evidenceFrame.frame.captureNanoseconds,
        cameraConfigurationID: evidenceFrame.frame.cameraConfigurationID,
        attemptID: attemptID,
        capAnchorEstimatorRevision: capAnchor.estimatorRevision,
        algorithmRevision:
          "automatic-current-camera-cap-anchor-v4:cap-\(penCapAppearanceSelection?.color.hexRGB ?? "UNLEARNED")",
        capAnchorConfidence: capAnchor.confidence,
        artifactRevisionID: centerArrivalRevisionID
      ),
      contextBaseline: afterCapture.contextBaseline,
      displayedFrame: evidenceFrame,
      capAnchor: capAnchor
    )
  }

  private func requireCalibrationContinuation() throws {
    guard !hasShutdown, !Task.isCancelled else {
      throw LearningPathOperationError.requiredState(
        "Application shutdown cancelled automatic current-camera calibration."
      )
    }
  }

  private func freshCalibrationMachineObservation(
    contextBaseline: ControllerContextBaseline?,
    operationID: UUID
  ) async throws -> CalibrationMachineObservation {
    try requireCalibrationContinuation()
    if frameMode == .simulated {
      let snapshot = await simulatedLearningRuntime.snapshot()
      try requireCalibrationContinuation()
      guard snapshot.currentOperation == nil, snapshot.stickyAmbiguity == nil,
        snapshot.penPose == .up
      else {
        throw LearningPathOperationError.controllerFailed(
          "The simulated controller was not settled at an unambiguous Pen-Up position."
        )
      }
      simulatedLearningSnapshot = snapshot
      return CalibrationMachineObservation(
        position: try MachinePosition(x: snapshot.mpos.xMM, y: snapshot.mpos.yMM),
        contextBaseline: nil
      )
    }

    guard let machineActions else {
      throw LearningPathOperationError.requiredState(
        "A connected controller session is required for exact calibration evidence."
      )
    }
    let probe = try await machineActions.requestPassiveProbe()
    try requireCalibrationContinuation()
    let refreshedBaseline = try ControllerContextBaseline(probe: probe)
    if let contextBaseline {
      let comparison = contextBaseline.context.comparison(with: refreshedBaseline.context)
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: operationID,
          operation: .currentCameraCalibration,
          phase: .controllerContextCompared,
          attemptID: activeExerciseAttemptID,
          detail: comparison.actionableDescription,
          controllerContext: WorkflowControllerContextTelemetry(
            baselineProbeID: contextBaseline.probeID,
            refreshedProbeID: probe.probeID,
            comparison: comparison
          ),
          failureCode: comparison.isCompatible ? nil : .controllerContextChanged,
          recovery: comparison.isCompatible ? .none : .revalidateControllerContext
        )
      )
      guard comparison.isCompatible else {
        throw LearningPathOperationError.controllerContextChanged(comparison)
      }
    } else {
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: operationID,
          operation: .currentCameraCalibration,
          phase: .controllerContextEstablished,
          attemptID: activeExerciseAttemptID,
          detail:
            "The first fresh passive probe established this calibration operation's controller-context baseline.",
          controllerContext: WorkflowControllerContextTelemetry(
            baselineProbeID: nil,
            refreshedProbeID: probe.probeID,
            comparison: nil
          )
        )
      )
    }
    let snapshot = await machineActions.snapshot()
    try requireCalibrationContinuation()
    guard let snapshot, snapshot.currentOperation == .idle,
      snapshot.machine.connection == .connected,
      snapshot.machine.controllerState == .idle,
      snapshot.machine.stickyAmbiguity == nil,
      snapshot.machine.penState == .up,
      let position = snapshot.machine.position
    else {
      throw LearningPathOperationError.controllerFailed(
        "Fresh controller status did not prove an unambiguous Idle Pen-Up MPos."
      )
    }
    passiveProbeResult = probe
    machineSnapshot = snapshot
    return CalibrationMachineObservation(
      position: position,
      contextBaseline: refreshedBaseline
    )
  }

  private func rejectCameraCalibrationProposal() {
    currentCameraCalibrationFailure = nil
    cameraCalibrationAnchorFrame = nil
    cameraCalibrationReferencePosition = nil
    cameraCalibrationReferenceCapAnchor = nil
    proposedMachineCameraRegistration = nil
    machineCameraRegistration = nil
    explorationError =
      "Operator rejected the staged five-sample cap map. No machine-camera revision became authoritative."
  }

  func selectToolContactPoint(_ selection: ActionSurfacePointSelection) {
    if let context = penCapAppearanceSelectionContext,
      context.request.purpose == .penCapAppearance
    {
      do {
        guard context.request.matches(context.frame), selection.frame == context.request.frame
        else { throw PenCapAppearanceSamplingError.staleExactFrame }
        guard
          activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction),
          let attemptID = activeExerciseAttemptID,
          let attemptMode = activeExerciseAttemptMode
        else { throw PenCapAppearanceSamplingError.staleExactFrame }
        let learned = try PenCapAppearanceSampler.sample(
          frame: context.frame,
          selection: selection
        )
        let learnedFromLiveCamera: Bool
        switch learned.source {
        case .live:
          livePenCapAppearanceSelection = learned
          persistedPenCapAppearanceLoadState = .accepted
          persistPenCapAppearanceSelection(learned)
          learnedFromLiveCamera = true
        case .simulated:
          simulatedPenCapAppearanceSelection = learned
          learnedFromLiveCamera = false
        }
        penCapAppearanceSelectionContext = nil
        discoveryError = nil
        startPenCapAcceptedClickContinuation(
          attemptID: attemptID,
          attemptMode: attemptMode,
          source: learned.source == .simulated ? .simulated : .live,
          selection: learned,
          configuresLiveVision: learnedFromLiveCamera
        )
      } catch {
        discoveryError = "Identify Pen Cap rejected the click: \(actionableDescription(error))"
      }
      return
    }
    guard let request = toolContactPointSelectionRequest,
      let selectionFrame = frozenToolContactSelectionFrame,
      request.matches(selectionFrame),
      selection.frame == request.frame
    else { return }
    do {
      guard selection.point.x >= 0, selection.point.x < Double(request.frame.width),
        selection.point.y >= 0, selection.point.y < Double(request.frame.height)
      else {
        throw SparseTipCalibrationCoordinatorError.staleSelection
      }
      try sparseTipCalibrationCoordinator.select(selection)
    } catch {
      if explorationError == nil {
        explorationError =
          "Stage 3.4 click selection failed without motion or redraw: \(actionableDescription(error))"
      }
      return
    }
    guard
      sparseTipCalibrationCoordinator.collectedClickCount
        == SparseTipCalibrationCoordinator.orderedPositions.count
    else {
      explorationError = nil
      return
    }
    do {
      try acceptSparseTipBatchClicks()
      explorationError = nil
    } catch {
      if sparseTipCalibrationCoordinator.recoverFromFittingFailure() {
        explorationError =
          "Stage 3.4 model construction failed without motion or redraw: \(actionableDescription(error)). Use Undo Last Click or Clear Clicks on This Frame to correct the same frozen frame."
      } else {
        explorationError =
          "Stage 3.4 model construction failed without motion or redraw: \(actionableDescription(error)). The frozen-click state could not be restored; Cancel Attempt remains available and no redraw was sent."
      }
    }
  }

  private func startPenCapAcceptedClickContinuation(
    attemptID: ExerciseAttemptID,
    attemptMode: ExerciseAttemptMode,
    source: OperatorFrameMode,
    selection: PenCapAppearanceSelection,
    configuresLiveVision: Bool
  ) {
    cancelPenCapAcceptedClickContinuation()
    let identity = PenCapAcceptedClickContinuationIdentity(
      id: UUID(),
      attemptID: attemptID,
      attemptMode: attemptMode,
      source: source,
      selection: selection,
      lifetimeGeneration: lifetimeGeneration
    )
    penCapAcceptedClickContinuationIdentity = identity
    penCapAcceptedClickContinuationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      defer { finishPenCapAcceptedClickContinuation(identity) }

      // Give recovery actions one actor turn to cancel the accepted-click
      // transition before it can create the first discovery question.
      await Task.yield()
      guard penCapAcceptedClickContinuationIsCurrent(identity) else { return }

      if configuresLiveVision {
        await cameraActions?.setPenCapColor(selection.color)
        guard penCapAcceptedClickContinuationIsCurrent(identity) else { return }
        await reconcileAutomaticVisionAnalysis()
        guard penCapAcceptedClickContinuationIsCurrent(identity) else { return }
      }

      await startDiscoverySequence(.penInteraction)
      guard penCapAcceptedClickContinuationStillOwnsAttempt(identity) else { return }
    }
  }

  private func penCapAcceptedClickContinuationIsCurrent(
    _ identity: PenCapAcceptedClickContinuationIdentity
  ) -> Bool {
    guard penCapAcceptedClickContinuationStillOwnsAttempt(identity),
      activeDiscoverySequenceID == nil
    else { return false }
    return true
  }

  private func penCapAcceptedClickContinuationStillOwnsAttempt(
    _ identity: PenCapAcceptedClickContinuationIdentity
  ) -> Bool {
    guard !Task.isCancelled, canCommit(identity.lifetimeGeneration),
      penCapAcceptedClickContinuationIdentity == identity,
      activeExerciseAttemptID == identity.attemptID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction),
      activeExerciseAttemptMode == identity.attemptMode,
      frameMode == identity.source,
      penCapAppearanceSelection == identity.selection,
      penCapAppearanceSelectionContext == nil
    else { return false }
    return true
  }

  private func finishPenCapAcceptedClickContinuation(
    _ identity: PenCapAcceptedClickContinuationIdentity
  ) {
    guard penCapAcceptedClickContinuationIdentity == identity else { return }
    penCapAcceptedClickContinuationTask = nil
    penCapAcceptedClickContinuationIdentity = nil
  }

  @discardableResult
  private func cancelPenCapAcceptedClickContinuation() -> Task<Void, Never>? {
    let task = penCapAcceptedClickContinuationTask
    task?.cancel()
    penCapAcceptedClickContinuationTask = nil
    penCapAcceptedClickContinuationIdentity = nil
    return task
  }

  func awaitPenCapAcceptedClickTransition() async {
    let task = penCapAcceptedClickContinuationTask
    await task?.value
  }

  private func drawFiveSparseTipCircles() async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    if activeExerciseAttemptOwnerID == nil {
      await startExercise(ownerID, mode: .normal)
    }
    guard activeExerciseAttemptOwnerID == ownerID,
      let attemptID = activeExerciseAttemptID
    else { return }

    let target = ContextualStopTarget.sparseTipBatch(
      capabilityID: ContextualStopCapabilityID(),
      attemptID: attemptID
    )
    let task = Task { await executeFiveSparseTipCircles(ownerID: ownerID, attemptID: attemptID) }
    installStoppableOperation(target: target, owner: .batch(task))
    defer { clearStoppableOperation(matching: target) }
    await task.value
  }

  private func executeFiveSparseTipCircles(
    ownerID: LearningPathItemID,
    attemptID: ExerciseAttemptID
  ) async {
    guard activeExerciseAttemptOwnerID == ownerID,
      activeExerciseAttemptID == attemptID,
      let machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      let center = cameraCalibrationReferencePosition
    else { return }

    var completedLocations: [BlacklistedToolContactLocation] = []
    var activeLocation: BlacklistedToolContactLocation?
    do {
      try requireSparseTipBatchContinuation()
      let batchPlan = try SparseTipBatchMarkPlan(
        center: center,
        boundarySideAggregates: boundarySideAggregates
      )
      let physicalLocations = batchPlan.marks.map { mark in
        BlacklistedToolContactLocation(
          calibrationPosition: mark.position,
          machinePosition: mark.machinePosition,
          markRadiusMM: SparseTipCircularMarkPlan.radiusMM,
          paperInstance: PaperInstanceRevision(
            rawValue: explorationPaperInstanceRevision
          )
        )
      }
      guard
        physicalLocations.allSatisfy({
          !blacklistedToolContactLocations.contains($0)
        })
      else {
        throw LearningPathOperationError.requiredState(
          "Possible ink already blacklists one of the five Stage 3.4 circle locations on the current paper."
        )
      }
      try sparseTipCalibrationCoordinator.beginBatch()
      var drawnEvidence: [DrawnToolContactEvidence] = []
      var finalCirclePosition = try currentMachinePosition()
      var finalPenUpTimestamp = RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())

      for (markIndex, plannedMark) in batchPlan.marks.enumerated() {
        try requireSparseTipBatchContinuation()
        let position = plannedMark.position
        let physicalLocation = physicalLocations[markIndex]
        activeLocation = physicalLocation
        let current = try currentMachinePosition()
        let settled: MachinePosition
        if let delta = try Self.supervisedTravelDelta(
          from: current,
          to: plannedMark.machinePosition
        ) {
          settled = try await performSupervisedPenUpTravel(
            delta: delta,
            ownerID: ownerID,
            action: .sparseTipApproach(position)
          )
        } else {
          settled = current
        }
        try requireSparseTipBatchContinuation()
        guard
          recordProtocolPoseSettlement(
            action: .sparseTipApproach(position),
            target: plannedMark.machinePosition,
            actual: settled
          )
        else {
          throw LearningPathOperationError.controllerFailed(
            "Sparse mark approach did not settle within 0.05 mm."
          )
        }

        let operationUUID = UUID()
        let preCapture = try await captureCurrentCameraCapAnchorEvidence(
          contextBaseline: nil,
          operationID: operationUUID
        )
        try requireSparseTipBatchContinuation()
        let exactPreFrame = try exactTipCalibrationFrame(preCapture.displayedFrame)
        let capPredictionAtMark = try machineRegistration.fit.cameraPoint(
          from: settled.point
        )
        let controllerEvidence = try controllerContextEvidenceReference(
          preCapture.contextBaseline,
          operationID: operationUUID
        )
        let markStartDelta = try Vector2<MachineSpace>(
          dx: plannedMark.circle.startPosition.point.x - settled.point.x,
          dy: plannedMark.circle.startPosition.point.y - settled.point.y
        )
        let markStartSettled = try await performSupervisedPenUpTravel(
          delta: markStartDelta,
          ownerID: ownerID,
          action: .sparseTipCircleStart(position)
        )
        try requireSparseTipBatchContinuation()
        guard
          recordProtocolPoseSettlement(
            action: .sparseTipCircleStart(position),
            target: plannedMark.circle.startPosition,
            actual: markStartSettled
          )
        else {
          throw LearningPathOperationError.controllerFailed(
            "Sparse circle start did not settle within 0.05 mm."
          )
        }
        let mark = try await performCircularContactMark(
          plan: plannedMark.circle,
          at: physicalLocation,
          after: exactPreFrame.captureNanoseconds
        )
        try requireSparseTipBatchContinuation()
        completedLocations.append(physicalLocation)
        finalCirclePosition = mark.finalPosition
        finalPenUpTimestamp = mark.penUp.timestamp
        drawnEvidence.append(
          DrawnToolContactEvidence(
            attemptID: attemptID,
            operationID: ToolContactOperationID(rawValue: operationUUID),
            position: position,
            intendedMarkPosition: plannedMark.machinePosition,
            actualSettledPosition: settled,
            controllerContextEvidence: controllerEvidence,
            markGeometry: plannedMark.circle.geometry,
            penDown: mark.penDown,
            penUp: mark.penUp,
            preMarkFrame: exactPreFrame,
            preMarkCapEstimate: preCapture.capAnchor,
            capMapPredictionAtMark: capPredictionAtMark,
            maximumCapMapResidualPixels: 8
          )
        )
      }

      try requireSparseTipBatchContinuation()
      try sparseTipCalibrationCoordinator.beginReveal()
      let revealTarget = batchPlan.finalRevealPosition
      let revealSettled: MachinePosition
      if let revealDelta = try Self.supervisedTravelDelta(
        from: finalCirclePosition,
        to: revealTarget
      ) {
        revealSettled = try await performSupervisedPenUpTravel(
          delta: revealDelta,
          ownerID: ownerID,
          action: .sparseTipBatchReveal
        )
      } else {
        revealSettled = finalCirclePosition
      }
      try requireSparseTipBatchContinuation()
      guard
        recordProtocolPoseSettlement(
          action: .sparseTipBatchReveal,
          target: revealTarget,
          actual: revealSettled
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Sparse mark reveal did not settle within 0.05 mm."
        )
      }
      let revealSettledAt = RuntimeTimestamp(
        monotonicNanoseconds: frameMode == .simulated
          ? finalPenUpTimestamp.monotonicNanoseconds + 1
          : max(nowNanoseconds(), finalPenUpTimestamp.monotonicNanoseconds + 1)
      )
      let revealOperationID = UUID()
      let revealCapture = try await captureCurrentCameraCapAnchorEvidence(
        contextBaseline: nil,
        operationID: revealOperationID,
        newerThanNanoseconds: revealSettledAt.monotonicNanoseconds
      )
      try requireSparseTipBatchContinuation()
      let exactRevealFrame = try exactTipCalibrationFrame(revealCapture.displayedFrame)
      let revealPrediction = try machineRegistration.fit.cameraPoint(
        from: revealSettled.point
      )
      let controllerEvidence = try controllerContextEvidenceReference(
        revealCapture.contextBaseline,
        operationID: revealOperationID
      )
      let revealEvidence = try ToolContactRevealEvidence(
        intendedPosition: revealTarget,
        actualSettledPosition: revealSettled,
        settledAt: revealSettledAt,
        controllerContextEvidence: controllerEvidence,
        frame: exactRevealFrame,
        capEstimate: revealCapture.capAnchor,
        capMapPrediction: revealPrediction,
        maximumCapMapResidualPixels: 8
      )
      let pendingEvidence = drawnEvidence.map { drawn in
        PendingToolContactEvidence(
          attemptID: drawn.attemptID,
          operationID: drawn.operationID,
          position: drawn.position,
          intendedMarkPosition: drawn.intendedMarkPosition,
          actualSettledPosition: drawn.actualSettledPosition,
          controllerContextEvidence: drawn.controllerContextEvidence,
          markGeometry: drawn.markGeometry,
          penDown: drawn.penDown,
          penUp: drawn.penUp,
          preMarkFrame: drawn.preMarkFrame,
          preMarkCapEstimate: drawn.preMarkCapEstimate,
          revealEvidence: revealEvidence,
          capMapPredictionAtMark: drawn.capMapPredictionAtMark,
          maximumCapMapResidualPixels: drawn.maximumCapMapResidualPixels
        )
      }
      try sparseTipCalibrationCoordinator.awaitFrozenClicks(frame: exactRevealFrame)
      let selectionRequest = ActionSurfacePointSelectionRequest(
        frame: exactRevealFrame,
        presentationTransformRevision: PresentationTransformRevision(),
        prompt: "Click the five circle centers in any order"
      )
      activeLearningSession.toolContactSelection.stage(
        ToolContactSelectionContext(
          pendingEvidence: pendingEvidence,
          frame: revealCapture.displayedFrame,
          request: selectionRequest
        )
      )
      explorationError = nil
      _ = machineRegistrationRevision
    } catch {
      let failure = workflowFailure(for: error)
      var locationsToBlacklist = completedLocations
      if let activeLocation,
        blacklistedToolContactLocations.contains(activeLocation)
          || failure.kind == .ambiguous || failure.kind == .possibleInk
      {
        locationsToBlacklist.append(activeLocation)
      }
      if locationsToBlacklist.isEmpty {
        sparseTipCalibrationCoordinator.resetBeforeInkFailure()
      } else {
        for location in Set(locationsToBlacklist) {
          blacklistedToolContactLocations.insert(location)
          sparseTipCalibrationCoordinator.blacklistPossibleInk(
            at: location,
            reason: failure.detail
          )
        }
        restartableExerciseItemID = nil
      }
      activeLearningSession.toolContactSelection.clear()
      explorationError =
        "Sparse tip calibration stopped without automatic retry: \(failure.detail)"
    }
  }

  private func performCircularContactMark(
    plan: SparseTipCircularMarkPlan,
    at location: BlacklistedToolContactLocation,
    after captureNanoseconds: UInt64
  ) async throws -> (
    penDown: PenActuationEvidence,
    penUp: PenActuationEvidence,
    finalPosition: MachinePosition
  ) {
    let lower: PenOutcome
    if frameMode == .simulated {
      _ = try (await simulatedLearningRuntime.setPenPose(.down)).result.get()
      lower = .commandedAndSettled(command: .lower, commandedState: .down)
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    } else {
      guard let machineActions else {
        throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
      }
      lower = await machineActions.requestPenActuation(.lower, currentPenActuationProfile)
      machineSnapshot = await machineActions.snapshot()
    }
    guard case .commandedAndSettled(command: .lower, commandedState: .down) = lower else {
      switch lower {
      case .ambiguous:
        blacklistedToolContactLocations.insert(location)
        sparseTipCalibrationCoordinator.blacklistPossibleInk(
          at: location,
          reason: String(describing: lower)
        )
        throw LearningPathOperationError.possibleInk(String(describing: lower))
      case .refused:
        throw LearningPathOperationError.controllerRefused(String(describing: lower))
      case .commandedAndSettled:
        preconditionFailure("The successful Pen Down outcome was handled by the guard.")
      }
    }
    setSparseTipBatchPossibleInkLocation(location)
    try requireSparseTipBatchContinuation()

    let downTime = RuntimeTimestamp(
      monotonicNanoseconds: frameMode == .simulated
        ? captureNanoseconds + 1
        : max(nowNanoseconds(), captureNanoseconds + 1)
    )

    var finalPosition = plan.startPosition
    do {
      for (index, delta) in plan.pathDeltas.enumerated() {
        try requireSparseTipBatchContinuation()
        let expected = plan.pathPositions[index + 1]
        if frameMode == .simulated {
          let response = await simulatedLearningRuntime.beginDrawing(
            delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy)
          )
          let operation = try response.result.get()
          let target = ContextualStopTarget.sparseTipBatchSegment(
            capabilityID: try sparseTipBatchCapabilityID(),
            operationOwner: .simulated(operation.id),
            location: location
          )
          let task = Task { [simulatedLearningRuntime, simulatedExecutionPacing] in
            try? await simulatedLearningRuntime.executeNaturally(
              operation.id,
              pacing: simulatedExecutionPacing
            ).result.get()
          }
          installStoppableOperation(target: target, owner: .simulated(task))
          defer { clearStoppableOperation(matching: target) }
          try await cancelSparseTipSegmentIfRequested(target: target, owner: .simulated(task))
          let outcome = await task.value
          try requireSparseTipBatchContinuation()
          guard let outcome, outcome.disposition == .naturallyCompleted else {
            throw LearningPathOperationError.possibleInk(
              "The 2 mm calibration circle stopped after contact; possible ink exists."
            )
          }
          simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
          finalPosition = try MachinePosition(
            x: outcome.finalMPos.xMM,
            y: outcome.finalMPos.yMM
          )
        } else {
          guard let machineActions else {
            throw LearningPathOperationError.requiredState(
              "Machine composition is unavailable."
            )
          }
          let request = DrawingStrokeRequest(
            delta: delta,
            feedMMPerMinute: min(
              plan.geometry.maximumFeedMMPerMinute,
              machineSnapshot?.machine.controllerAxisFeedLimits?
                .applicableFeedCeiling(for: delta)
                ?? plan.geometry.maximumFeedMMPerMinute
            )
          )
          let operation: DrawingStrokeOperation
          switch await machineActions.beginDrawingStroke(request) {
          case .admitted(let admitted):
            operation = admitted
          case .rejected(let outcome):
            throw operationError(for: outcome, possibleInk: true)
          }
          let target = ContextualStopTarget.sparseTipBatchSegment(
            capabilityID: try sparseTipBatchCapabilityID(),
            operationOwner: .liveOperation(operation.id),
            location: location
          )
          let task = Task { await operation.outcome() }
          installStoppableOperation(target: target, owner: .drawing(task))
          defer { clearStoppableOperation(matching: target) }
          try await cancelSparseTipSegmentIfRequested(target: target, owner: .drawing(task))
          let outcome = await task.value
          machineSnapshot = await machineActions.snapshot()
          try requireSparseTipBatchContinuation()
          switch outcome {
          case .completed(let evidence):
            finalPosition = evidence.finalPosition
          case .cancelled(_, let penRaiseOutcome):
            throw LearningPathOperationError.possibleInk(
              "The calibration circle was stopped; Pen Up outcome: \(penRaiseOutcome)"
            )
          case .ambiguous(let ambiguity):
            throw LearningPathOperationError.possibleInk(
              ambiguity.actionableDescription
            )
          case .refused(let refusal):
            throw LearningPathOperationError.controllerRefused(String(describing: refusal))
          }
        }
        guard
          recordProtocolPoseSettlement(
            action: .sparseTipCircleChord(index: index + 1, total: plan.pathDeltas.count),
            target: expected,
            actual: finalPosition
          )
        else {
          throw LearningPathOperationError.controllerFailed(
            "A 2 mm calibration-circle chord did not settle within 0.05 mm."
          )
        }
      }
    } catch {
      blacklistedToolContactLocations.insert(location)
      sparseTipCalibrationCoordinator.blacklistPossibleInk(
        at: location,
        reason: actionableDescription(error)
      )
      await raisePenAfterKnownCircleFailureIfNeeded()
      throw error
    }

    let raise: PenOutcome
    if frameMode == .simulated {
      _ = try (await simulatedLearningRuntime.setPenPose(.up)).result.get()
      raise = .commandedAndSettled(command: .raise, commandedState: .up)
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    } else {
      guard let machineActions else {
        throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
      }
      raise = await machineActions.requestPenActuation(.raise, currentPenActuationProfile)
      machineSnapshot = await machineActions.snapshot()
    }
    guard case .commandedAndSettled(command: .raise, commandedState: .up) = raise else {
      blacklistedToolContactLocations.insert(location)
      sparseTipCalibrationCoordinator.blacklistPossibleInk(
        at: location,
        reason: String(describing: raise)
      )
      throw operationError(for: raise, possibleInk: true)
    }
    try requireSparseTipBatchContinuation()
    clearSparseTipBatchPossibleInkLocation(matching: location)
    let upTime = RuntimeTimestamp(
      monotonicNanoseconds: frameMode == .simulated
        ? downTime.monotonicNanoseconds + 1
        : max(nowNanoseconds(), downTime.monotonicNanoseconds + 1)
    )
    return (
      PenActuationEvidence(
        outcome: lower,
        profile: currentPenActuationProfile,
        timestamp: downTime
      ),
      PenActuationEvidence(
        outcome: raise,
        profile: currentPenActuationProfile,
        timestamp: upTime
      ),
      finalPosition
    )
  }

  private func raisePenAfterKnownCircleFailureIfNeeded() async {
    if frameMode == .simulated {
      let snapshot = await simulatedLearningRuntime.snapshot()
      if snapshot.penPose == .down {
        _ = await simulatedLearningRuntime.setPenPose(.up)
      }
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
      return
    }
    guard let machineActions,
      machineSnapshot?.machine.stickyAmbiguity == nil,
      machineSnapshot?.machine.penState == .down
    else { return }
    _ = await machineActions.requestPenActuation(.raise, currentPenActuationProfile)
    machineSnapshot = await machineActions.snapshot()
  }

  private func undoLastSparseTipClick() {
    do {
      discardStagedTipObservationArtifacts()
      try sparseTipCalibrationCoordinator.undoLastClick()
      explorationError = nil
    } catch {
      explorationError = actionableDescription(error)
    }
  }

  private func clearSparseTipClicks() {
    do {
      discardStagedTipObservationArtifacts()
      try sparseTipCalibrationCoordinator.clearClicks()
      explorationError = nil
    } catch {
      explorationError = actionableDescription(error)
    }
  }

  private func rejectTipCalibrationProposal() {
    clearSparseTipClicks()
    if explorationError == nil {
      explorationError =
        "The staged tip map was rejected. No tip-camera revision became authoritative; reselect the five points on the same frozen frame."
    }
  }

  private func discardStagedTipObservationArtifacts() {
    let rootKinds = Set(
      sparseTipCalibrationCoordinator.acceptedObservations.map {
        LearningArtifactKind.toolContactObservation($0.observation.id)
      }
    )
    if !rootKinds.isEmpty {
      var graph = learningArtifactGraph
      let invalidation = graph.invalidateCurrentRevisions(rootKinds: rootKinds)
      learningArtifactGraph = graph
      applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    }
    proposedTipCameraRegistration = nil
  }

  private func acceptSparseTipBatchClicks() throws {
    guard
      pendingToolContactEvidence.count == SparseTipCalibrationCoordinator.orderedPositions.count,
      sparseTipCalibrationCoordinator.collectedClickCount
        == SparseTipCalibrationCoordinator.orderedPositions.count,
      let request = toolContactPointSelectionRequest,
      let machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      let attemptID = activeExerciseAttemptID,
      let optical = pendingToolContactEvidence.first?.revealEvidence.frame.opticalConfiguration
    else { throw SparseTipCalibrationCoordinatorError.invalidTransition }

    let associations = try associateSparseTipClicks(
      using: machineRegistration.fit,
      knownMachinePositions: pendingToolContactEvidence.map {
        SparseTipKnownMachinePosition(
          calibrationPosition: $0.position,
          machinePosition: $0.intendedMarkPosition
        )
      },
      clicks: sparseTipCalibrationCoordinator.collectedClickPoints
    )
    let pendingByPosition = Dictionary(
      uniqueKeysWithValues: pendingToolContactEvidence.map { ($0.position, $0) }
    )
    let clickTimestamp = RuntimeTimestamp(
      monotonicNanoseconds: max(
        nowNanoseconds(),
        (pendingToolContactEvidence.first?.revealEvidence.frame.captureNanoseconds ?? 0) + 1
      )
    )
    let presentationRevision =
      sparseTipCalibrationCoordinator.selectedPresentationRevisionForCommit
      ?? request.presentationTransformRevision
    var graph = learningArtifactGraph
    var accepted: [AcceptedToolContactObservation] = []
    for association in associations {
      guard let pending = pendingByPosition[association.calibrationPosition] else {
        throw SparseTipCalibrationCoordinatorError.invalidTransition
      }
      let click = try ToolContactClickEvidence(
        point: association.clickedCameraPoint,
        pointingUncertaintyPixels: Vector2(dx: 1.5, dy: 1.5),
        timestamp: clickTimestamp,
        presentationTransformRevision: presentationRevision
      )
      let observation = try ToolContactObservation(
        attemptID: pending.attemptID,
        operationID: pending.operationID,
        calibrationPosition: pending.position,
        intendedMarkPosition: pending.intendedMarkPosition,
        actualSettledPosition: pending.actualSettledPosition,
        machineGeometry: machineGeometryIdentity,
        controllerSessionID: controllerSessionID,
        machineCoordinateFrame: MachineCoordinateFrameRevision(
          rawValue: explorationCoordinateRevision
        ),
        controllerContextEvidence: pending.controllerContextEvidence,
        markGeometry: pending.markGeometry,
        penDown: pending.penDown,
        penUp: pending.penUp,
        toolAssembly: toolAssemblyRevision,
        penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(
          rawValue: explorationPaperContactPlaneRevision
        ),
        preMarkFrame: pending.preMarkFrame,
        preMarkCapEstimate: pending.preMarkCapEstimate,
        revealEvidence: pending.revealEvidence,
        click: click,
        capMapPredictionAtMark: pending.capMapPredictionAtMark,
        maximumCapMapResidualPixels: pending.maximumCapMapResidualPixels,
        disposition: .accepted,
        consumedLearningArtifactRevisionIDs: [machineRegistrationRevision],
        algorithmRevisions: [
          try AlgorithmRevisionEvidence(
            component: "sparse-tip-workspace",
            revision: "five-circle-batch-unordered-global-association-v2"
          ),
          try AlgorithmRevisionEvidence(
            component: "pen-actuation",
            revision: currentPenActuationProfile.revision
          ),
        ]
      )
      let revision = LearningArtifactRevision(
        kind: .toolContactObservation(observation.id),
        attemptID: pending.attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [machineRegistrationRevision]
      )
      _ = try graph.commitReplacement(revision)
      accepted.append(
        try AcceptedToolContactObservation(
          artifactRevisionID: revision.id,
          observation: observation
        )
      )
    }

    var coordinator = sparseTipCalibrationCoordinator
    try coordinator.acceptAssociatedObservations(accepted)
    let selection = try coordinator.stageProposal(
      capCameraFromMachine: machineRegistration.fit.cameraFromMachine
    )
    let registrationRevisionID = LearningArtifactRevisionID()
    let proposal = try TipCameraRegistration(
      modelForm: selection.modelForm,
      cameraFromMachine: selection.finalCameraFromMachine,
      modelSelectionEvidence: selection.evidence,
      uncertainty: selection.uncertainty,
      applicabilityRectangle: machineRegistration.applicabilityRectangle,
      acceptedObservations: accepted,
      applicability: TipCalibrationApplicabilityContext(
        opticalConfiguration: optical,
        machineGeometry: machineGeometryIdentity,
        machineCoordinateFrame: MachineCoordinateFrameRevision(
          rawValue: explorationCoordinateRevision
        ),
        toolAssembly: toolAssemblyRevision,
        penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(
          rawValue: explorationPaperContactPlaneRevision
        )
      ),
      acceptedRevisionID: registrationRevisionID,
      machineCameraRegistrationRevisionID: machineRegistrationRevision,
      estimatorRevision: SparseTipCircularMarkPlan.registrationEstimatorRevision,
      acceptedAt: RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
    )
    _ = attemptID
    learningArtifactGraph = graph
    sparseTipCalibrationCoordinator = coordinator
    proposedTipCameraRegistration = proposal
  }

  @discardableResult
  private func commitTipCalibration(actor: String) -> Bool {
    guard let proposal = proposedTipCameraRegistration,
      let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID
        == .humanGuidedDiscovery(
          .calibratePenContactFromSparseMarks
        )
    else { return false }
    do {
      let candidate = LearningArtifactRevision(
        id: proposal.acceptedRevisionID,
        kind: .tipCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: proposal.consumedArtifactRevisionIDs
      )
      var graph = learningArtifactGraph
      let commit = try graph.commitReplacement(candidate)
      var coordinator = sparseTipCalibrationCoordinator
      try coordinator.beginCommit()
      try coordinator.markAccepted()
      let acceptedTimestamp = RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
      let acceptanceEvent = try TipCalibrationAcceptanceEvent(
        acceptedRevisionID: proposal.acceptedRevisionID,
        timestamp: acceptedTimestamp,
        actor: actor
      )
      let checkpoint = try AcceptedTipCalibrationCheckpoint(
        registration: proposal,
        acceptanceEvent: acceptanceEvent
      )
      learningArtifactGraph = graph
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
      tipCameraRegistration = proposal
      restoreInteractiveLearningCompletionFromEvidence()
      proposedTipCameraRegistration = nil
      sparseTipCalibrationCoordinator = coordinator
      activeLearningSession.toolContactSelection.clear()
      quarantinedTipCalibrationCheckpoint = nil
      persistAcceptedLearningPathCheckpoint(tipCalibration: checkpoint, clearStageFour: true)
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
      return true
    } catch {
      explorationError =
        "Tip-calibration commit failed atomically: \(actionableDescription(error))"
      return false
    }
  }

  private func revalidateTipCalibrationCheckpoint() async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(ownerID: ownerID, mode: .normal)
    }
    guard activeExerciseAttemptOwnerID == ownerID,
      let attemptID = activeExerciseAttemptID,
      var checkpoint = quarantinedTipCalibrationCheckpoint,
      var machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      checkpoint.registration.applicability.paperContactPlane.rawValue
        == explorationPaperContactPlaneRevision
    else { return }

    let operationID = UUID()
    do {
      let capture = try await captureCurrentCameraCapAnchorEvidence(
        contextBaseline: nil,
        operationID: operationID
      )
      let exactFrame = try exactTipCalibrationFrame(capture.displayedFrame)
      var effectiveCoordinateRevision = explorationCoordinateRevision
      var rebasedMachineCheckpoint: AcceptedMachineArtifactCheckpoint?
      var rebasedMachineCameraCheckpoint: AcceptedMachineCameraCheckpoint?
      let initialCapPrediction = try machineRegistration.fit.cameraPoint(
        from: capture.evidence.machinePoint
      )
      let initialCapResidual = initialCapPrediction.distance(to: capture.capAnchor.point)
      if case .requiresVisualRevalidation = controllerPoseApplicability,
        initialCapResidual > 8
      {
        guard let acceptedMachineCheckpoint = parkedAcceptedMachineArtifactCheckpoint else {
          throw LearningPathOperationError.requiredState(
            "The carriage moved relative to the saved cap map, but no accepted machine checkpoint is available to rebase."
          )
        }
        let formerMachinePoint = try machineRegistration.fit.machinePoint(
          from: capture.capAnchor.point
        )
        let delta = try formerMachinePoint.vector(to: capture.evidence.machinePoint)
        effectiveCoordinateRevision &+= 1
        let machineCheckpoint = try acceptedMachineCheckpoint
          .rebasedForKnownMachineCoordinateChange(
            to: effectiveCoordinateRevision,
            delta: delta
          )
        machineRegistration = try machineRegistration.rebasedForKnownMachineCoordinateChange(
          to: effectiveCoordinateRevision,
          delta: delta
        )
        let machineCameraCheckpoint = try AcceptedMachineCameraCheckpoint(
          revision: pendingMachineCameraCheckpoint?.revision
            ?? LearningArtifactRevision(
              id: machineRegistrationRevision,
              kind: .machineCameraRegistration,
              attemptID: attemptID,
              disposition: .succeeded,
              consumedRevisionIDs: machineRegistration.correspondenceRevisionIDs
            ),
          registration: machineRegistration
        )
        let rebasedTipRegistration = try checkpoint.registration
          .rebasedForKnownMachineCoordinateChange(
            to: MachineCoordinateFrameRevision(rawValue: effectiveCoordinateRevision),
            delta: delta
          )
        checkpoint = try AcceptedTipCalibrationCheckpoint(
          registration: rebasedTipRegistration,
          acceptanceEvent: checkpoint.acceptanceEvent
        )
        rebasedMachineCheckpoint = machineCheckpoint
        rebasedMachineCameraCheckpoint = machineCameraCheckpoint
      }
      let capPrediction = try machineRegistration.fit.cameraPoint(
        from: capture.evidence.machinePoint
      )
      let controllerEvidence = try controllerContextEvidenceReference(
        capture.contextBaseline,
        operationID: operationID
      )
      let currentApplicability = TipCalibrationApplicabilityContext(
        opticalConfiguration: exactFrame.opticalConfiguration,
        machineGeometry: machineGeometryIdentity,
        machineCoordinateFrame: MachineCoordinateFrameRevision(
          rawValue: effectiveCoordinateRevision
        ),
        toolAssembly: toolAssemblyRevision,
        penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(
          rawValue: explorationPaperContactPlaneRevision
        )
      )
      let evidenceTimestamp = RuntimeTimestamp(
        monotonicNanoseconds: max(
          nowNanoseconds(),
          exactFrame.captureNanoseconds + 1
        )
      )
      let evidence = try TipCalibrationRevalidationEvidence(
        currentApplicability: currentApplicability,
        currentMachineCameraRegistrationRevisionID: machineRegistrationRevision,
        controllerContextEvidence: controllerEvidence,
        frame: exactFrame,
        capEstimate: capture.capAnchor,
        capMapPrediction: capPrediction,
        maximumCapMapResidualPixels: 8,
        timestamp: evidenceTimestamp,
        algorithmRevision: "explicit-tip-checkpoint-revalidation-and-coordinate-rebase-v2"
      )
      guard case .restored = checkpoint.revalidate(with: evidence) else {
        throw LearningPathOperationError.requiredState(
          "The saved tip calibration remains quarantined because current semantic identity or fresh cap evidence did not match."
        )
      }

      var graph = learningArtifactGraph
      var rebuiltObservationRevisions: [ToolContactObservationID: LearningArtifactRevisionID] = [:]
      for observation in checkpoint.registration.observationEvidence {
        let revision = LearningArtifactRevision(
          kind: .toolContactObservation(observation.observationID),
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [machineRegistrationRevision]
        )
        _ = try graph.commitReplacement(revision)
        rebuiltObservationRevisions[observation.observationID] = revision.id
      }
      let acceptedRevisionID = LearningArtifactRevisionID()
      let acceptedAt = RuntimeTimestamp(
        monotonicNanoseconds: max(
          nowNanoseconds(),
          evidenceTimestamp.monotonicNanoseconds + 1
        )
      )
      let restoredRegistration = try checkpoint.registration.revalidatedFromCheckpoint(
        evidence: evidence,
        acceptedRevisionID: acceptedRevisionID,
        machineCameraRegistrationRevisionID: machineRegistrationRevision,
        observationArtifactRevisionIDs: rebuiltObservationRevisions,
        acceptedAt: acceptedAt
      )
      let tipRevision = LearningArtifactRevision(
        id: acceptedRevisionID,
        kind: .tipCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: restoredRegistration.consumedArtifactRevisionIDs
      )
      _ = try graph.commitReplacement(tipRevision)
      let acceptanceEvent = try TipCalibrationAcceptanceEvent(
        acceptedRevisionID: acceptedRevisionID,
        timestamp: acceptedAt,
        actor: "operator-checkpoint-revalidation"
      )
      let refreshedCheckpoint = try AcceptedTipCalibrationCheckpoint(
        registration: restoredRegistration,
        acceptanceEvent: acceptanceEvent
      )
      if let rebasedMachineCheckpoint, let rebasedMachineCameraCheckpoint {
        let histories = try rebasedMachineCheckpoint.restoredBoundaryHistories()
        parkedAcceptedMachineArtifactCheckpoint = rebasedMachineCheckpoint
        pendingMachineCameraCheckpoint = rebasedMachineCameraCheckpoint
        machineCameraRegistration = rebasedMachineCameraCheckpoint.registration
        boundaryAttemptHistories = histories
        boundaryAttemptEvidenceByAttemptID = Dictionary(
          uniqueKeysWithValues: rebasedMachineCheckpoint.acceptedBoundaryEvidence.map {
            ($0.attemptID, $0)
          }
        )
        boundarySideAggregates = Dictionary(
          uniqueKeysWithValues: rebasedMachineCheckpoint.boundarySideAggregates.map {
            ($0.direction, $0)
          }
        )
        estimatedMachineCenter = rebasedMachineCheckpoint.estimatedMachineCenter
        learnedLocalCoordinateFrame = rebasedMachineCheckpoint.learnedLocalCoordinateFrame
        centerArrivalPosition = rebasedMachineCheckpoint.centerArrivalPosition
        explorationCoordinateRevision = effectiveCoordinateRevision
        acceptedArtifactCheckpointStatus = .restored(
          sideCount: rebasedMachineCheckpoint.boundarySideAggregates.count,
          centerArrival: rebasedMachineCheckpoint.centerArrivalPosition != nil,
          reportedPositionDeltaMM: initialCapResidual
        )
      }
      learningArtifactGraph = graph
      tipCameraRegistration = restoredRegistration
      restoreInteractiveLearningCompletionFromEvidence()
      proposedTipCameraRegistration = nil
      quarantinedTipCalibrationCheckpoint = nil
      controllerPoseApplicability = .visuallyRevalidated(
        frameID: exactFrame.frameID,
        residualPixels: evidence.capMapResidualPixels
      )
      persistAcceptedLearningPathCheckpoint(tipCalibration: refreshedCheckpoint)
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
    } catch {
      finishActiveExerciseAttempt(disposition: .failed(actionableDescription(error)))
      explorationError =
        "Saved tip calibration was not restored: \(actionableDescription(error))"
    }
  }

  private func exactTipCalibrationFrame(_ displayed: DisplayedFrame) throws
    -> ExactTipCalibrationFrame
  {
    let configurationRevision = displayed.frame.cameraConfigurationID.rawValue
    let optical = try CameraOpticalConfigurationIdentity(
      source: displayed.source,
      sensorFormat: "runtime-\(displayed.frame.pixelFormat.rawValue)",
      width: displayed.frame.width,
      height: displayed.frame.height,
      pixelFormat: displayed.frame.pixelFormat,
      orientation: .up,
      mirrored: false,
      digitalZoomFactor: 1,
      lensIdentity: "runtime-unreported-lens",
      focusConfiguration: "runtime-unreported-focus",
      mountRevision: cameraMountRevision,
      reframingRevision: cameraReframingRevision
    )
    return try ExactTipCalibrationFrame(
      frameID: displayed.frame.id,
      frameSHA256: displayed.frame.contentSHA256,
      source: displayed.source,
      captureSessionID: CameraCaptureSessionID(rawValue: configurationRevision),
      opticalConfiguration: optical,
      cameraConfigurationID: displayed.frame.cameraConfigurationID,
      captureNanoseconds: displayed.frame.captureNanoseconds,
      width: displayed.frame.width,
      height: displayed.frame.height,
      pixelFormat: displayed.frame.pixelFormat
    )
  }

  private func controllerContextEvidenceReference(
    _ baseline: ControllerContextBaseline?,
    operationID: UUID
  ) throws -> ControllerContextEvidenceReference {
    let data: Data
    let probeID: UUID
    if let baseline {
      data = try JSONEncoder().encode(baseline)
      probeID = baseline.probeID
    } else {
      data = Data("simulated-sparse-tip-\(controllerSessionID.uuidString)".utf8)
      probeID = operationID
    }
    return try ControllerContextEvidenceReference(
      passiveProbeID: probeID,
      evidenceSHA256: RunLedger.sha256Hex(data),
      algorithmRevision: "sparse-tip-controller-context-v1"
    )
  }

  private func recordPaperReplaced() async {
    await recordPaperReplacement(contactPlaneChanged: false)
  }

  func recordNewPaperSheetOnCurrentPlane() async {
    await recordPaperReplacement(contactPlaneChanged: false)
  }

  /// Records a new sheet on a changed support/stock/contact plane. Ordinary
  /// sheet replacement uses `recordPaperReplaced()` and deliberately retains
  /// current tip calibration.
  func recordPaperContactPlaneChanged() async {
    await recordPaperReplacement(contactPlaneChanged: true)
  }

  private func recordPaperReplacement(contactPlaneChanged: Bool) async {
    guard !activeLearningSession.drawingStudio.runInProgress else {
      drawingEvidenceError =
        "Paper identity cannot change until the current drawing run and evidence capture settle."
      return
    }
    let replacementSnapshot: SimulatedLearningSnapshot?
    if frameMode == .simulated {
      do {
        replacementSnapshot = try await simulatedLearningRuntime.recordPaperReplaced().result.get()
      } catch {
        explorationError = "Paper replacement was refused: \(actionableDescription(error))"
        return
      }
    } else {
      replacementSnapshot = nil
    }

    if let owner = activeExerciseAttemptOwnerID,
      owner != .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    {
      finishActiveExerciseAttempt(disposition: .cancelled)
    }
    if contactPlaneChanged {
      var graph = learningArtifactGraph
      let invalidation = graph.invalidateCurrentRevisions(rootKinds: [.tipCameraRegistration])
      learningArtifactGraph = graph
      applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
      tipCameraRegistration = nil
      proposedTipCameraRegistration = nil
      explorationPaperContactPlaneRevision = UUID()
      if frameMode == .live {
        persistPaperContactPlaneRevision(
          PaperContactPlaneRevision(rawValue: explorationPaperContactPlaneRevision)
        )
      }
    }
    if let replacementSnapshot {
      simulatedLearningSnapshot = replacementSnapshot
      explorationPaperInstanceRevision = replacementSnapshot.toolPaperRevision
    } else {
      explorationPaperInstanceRevision = UUID()
      persistPaperInstanceRevision(
        PaperInstanceRevision(rawValue: explorationPaperInstanceRevision)
      )
    }
    sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
    currentPaperCoverageObservation = nil
    if frameMode == .live { livePaperCoverageActions?.clear() }
    clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    activeLearningSession.drawingStudio.baselineFrame = nil
    activeLearningSession.drawingStudio.postFrame = nil
    activeLearningSession.drawingStudio.lastRunRecord = nil
    activeLearningSession.drawingStudio.reviewIsPinned = false
    activeLearningSession.drawingStudio.terminalRequiresNewPlan = false
    activeLearningSession.drawingStudio.redrawBlockedPlanHashes = []
    activeLearningSession.drawingStudio.runDetail = nil
    overlayResultChannels.clearWorkflow(source: frameMode, owner: .drawingStudio)
    if contactPlaneChanged { rebuildDrawingStudioPlan() }
    persistAcceptedLearningPathCheckpoint(
      clearTip: contactPlaneChanged,
      clearStageFour: contactPlaneChanged
    )
    explorationError = nil
  }

  func runObservedDrawingTrial() async {
    guard tipCameraRegistration != nil, activeExplorationOperation == nil else { return }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .observedDrawingTrial(.chooseIsolatedLinePlan),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    explorationError = nil
    restartableExerciseItemID = nil

    while observedDrawingTrialStep != .compareIntendedAndObservedGeometry {
      let attemptedStep = observedDrawingTrialStep
      let payloadSnapshot = drawingTrialPayloadSnapshot()
      activeExplorationOperation = ActiveExplorationOperation(
        step: attemptedStep,
        strokeState: .notAdmitted
      )
      do {
        switch attemptedStep {
        case .chooseIsolatedLinePlan:
          try recordIsolatedLinePlan()
        case .captureLocalPreLineBaseline:
          try await captureLocalPreLineBaseline()
        case .moveToLineStart:
          try await moveToRecordedLineStart()
        case .drawIsolatedLine:
          try await drawIsolatedTrialLine()
        case .revealAndObserveNewInk:
          try await revealAndObserveTrialInk()
        case .compareIntendedAndObservedGeometry:
          break
        }
        try commitDrawingArtifact(for: attemptedStep)
        advanceDrawingTrialAfterSuccess(attemptedStep)
      } catch {
        let strokeState = activeExplorationOperation?.strokeState
        activeExplorationOperation = nil
        if attemptedStep == .drawIsolatedLine,
          drawingTrialStrokeEvidence != payloadSnapshot.strokeEvidence
            || strokeState != .notAdmitted
        {
          var commitFailure: String?
          if strokeState == .completedNaturally {
            do {
              try commitDrawingArtifact(for: .drawIsolatedLine)
            } catch {
              commitFailure = String(describing: error)
            }
          }
          advanceDrawingTrialAfterSuccess(.drawIsolatedLine)
          let base =
            "The stroke owner produced evidence, so physical ink may exist. Drawing will not be restarted; Continue Observation will return Pen Up and inspect the existing stroke."
          explorationError =
            commitFailure.map {
              "\(base) The line-execution artifact also needs attention: \($0)"
            } ?? "\(base) Post-stroke settlement needs attention: \(error)"
          finishActiveExerciseAttempt(
            disposition: .failed("Ink may exist; automatic redraw is prohibited.")
          )
          restartableExerciseItemID = nil
          return
        }
        if attemptedStep != .revealAndObserveNewInk {
          restoreDrawingTrialPayload(payloadSnapshot)
        }
        explorationError = "\(attemptedStep.title) failed: \(error)"
        finishActiveExerciseAttempt(disposition: workflowFailure(for: error).attemptDisposition)
        restartableExerciseItemID =
          attemptedStep == .revealAndObserveNewInk
          ? nil : .observedDrawingTrial(.chooseIsolatedLinePlan)
        return
      }
    }

    activeExplorationOperation = ActiveExplorationOperation(
      step: .compareIntendedAndObservedGeometry,
      strokeState: .notAdmitted
    )
    do {
      try commitComparisonAttemptAndArtifact(.predictionObserved)
      drawingTrialAssessment = .predictionObserved
      activeLearningSession.drawingTrial.comparisonReviewIsPinned = true
      await persistCompletedIsolatedLineEvidence()
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      explorationError = "Automatic comparison failed: \(error)"
      recordComparisonAttempt(
        assessment: nil,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = .observedDrawingTrial(.chooseIsolatedLinePlan)
    }
    activeExplorationOperation = nil
  }

  func discoveryStartUnavailableReason(for sequenceID: DiscoverySequenceID) -> String? {
    if let activeDiscoverySequenceID {
      return
        "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while its logical owner is active."
    }
    if sequenceID == .penInteraction {
      guard displayedFrame != nil else {
        return "A current exact camera or simulated frame is required to Identify Pen Cap."
      }
      return nil
    }
    if frameMode == .simulated {
      if !controllerSessionEstablished { return "Connect the learning simulator first." }
      if !motionAuthorizationEnabled { return "Enable simulated Motion first." }
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      switch sequenceID {
      case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
        return nil
      case .penInteraction:
        return nil
      }
    }
    if !motionGuardIsActive { return "Connect the plotter and Enable Motion first." }
    switch sequenceID {
    case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
      return directCarriageMotionUnavailableReason
    case .penInteraction:
      return penUnavailableReason(for: .lower)
    }
  }

  var workbenchStatusText: String {
    if let actionableError { return actionableError }
    if !controllerSessionEstablished {
      return frameMode == .simulated
        ? "Press Connect to start the nonphysical learning simulator session."
        : "Select the remembered controller and press Connect."
    }
    if !motionAuthorizationEnabled {
      return frameMode == .simulated
        ? "Simulator connected. Enable Motion before this action."
        : "Plotter connected. Enable Motion before this action."
    }
    return switch manualMotionPenState {
    case .up:
      "Motion enabled; manual controls will move with the commanded pen Up."
    case .down:
      "Motion enabled; manual controls will draw with the commanded pen Down."
    case .unknown:
      "Motion enabled; manual controls may move with possible ink because pen state is unknown."
    }
  }

  var manualMotionModeText: String {
    switch manualMotionPenState {
    case .up: "travel — commanded Pen Up"
    case .down: "drawing — commanded Pen Down"
    case .unknown: "manual move — possible ink; pen state unknown"
    }
  }

  var learningModeActionTitle: String {
    learningIsEnabled ? "Turn Learning Off" : "Turn Learning On"
  }

  var learningModeChangeUnavailableReason: String? {
    guard learningIsEnabled else { return nil }
    if currentCameraCalibrationPhase != nil {
      return "Stop or finish current-camera calibration before turning Learning off."
    }
    if activeExerciseAttemptOwnerID != nil || activeDiscoverySequenceID != nil
      || activeExplorationOperation != nil
    {
      return "Cancel or finish the active Learning attempt before turning Learning off."
    }
    if let target = activeStopTarget, !isManualStopTarget(target) {
      return "Stop or finish the active Learning motion before turning Learning off."
    }
    return nil
  }

  func toggleLearningMode() {
    guard learningModeChangeUnavailableReason == nil else { return }
    if learningIsEnabled {
      cancelPenCapAcceptedClickContinuation()
    }
    learningIsEnabled.toggle()
  }

  var machinePositionText: String {
    if frameMode == .simulated, let mpos = simulatedLearningSnapshot?.mpos {
      return String(format: "simulated X %.3f   Y %.3f", mpos.xMM, mpos.yMM)
    }
    guard let point = machineSnapshot?.machine.position?.point else { return "unknown" }
    return String(format: "X %.3f   Y %.3f", point.x, point.y)
  }

  var penStateText: String {
    if frameMode == .simulated, let pose = simulatedLearningSnapshot?.penPose {
      return "simulated \(pose.rawValue) — not a physical observation"
    }
    return switch machineSnapshot?.machine.penState ?? .unknown {
    case .unknown:
      "unknown — no physical pose assumed"
    case .up:
      "commanded up — not visually observed"
    case .down:
      "commanded down — not visually observed"
    }
  }

  var lastMotionOutcomeText: String {
    if frameMode == .simulated {
      return lastContextualStopAuditRecord?.outcome ?? "no simulated motion outcome"
    }
    if lastManualMotionWasDrawing,
      let outcome = machineSnapshot?.lastDrawingStrokeOutcome
    {
      return switch outcome {
      case .completed(let evidence):
        String(
          format: "drawing completed at X %.3f Y %.3f",
          evidence.finalPosition.point.x,
          evidence.finalPosition.point.y
        )
      case .cancelled(let evidence, let penRaiseOutcome):
        String(
          format: "drawing stopped at X %.3f Y %.3f; Pen Up: %@",
          evidence.finalPosition.point.x,
          evidence.finalPosition.point.y,
          String(describing: penRaiseOutcome)
        )
      case .refused(let refusal):
        "drawing refused: \(refusal.actionableDescription)"
      case .ambiguous(let ambiguity):
        "drawing ambiguous: \(ambiguity.actionableDescription)"
      }
    }
    guard let outcome = machineSnapshot?.lastMotionOutcome else { return "none" }
    switch outcome {
    case .refused(let reason):
      return "refused: \(reason.actionableDescription)"
    case .acceptedThenCompleted(let finalPosition):
      return String(
        format: lastManualMotionMayHaveProducedInk
          ? "completed at X %.3f Y %.3f; possible ink"
          : "completed at X %.3f Y %.3f",
        finalPosition.point.x,
        finalPosition.point.y
      )
    case .cancelled(let finalPosition):
      return String(
        format: lastManualMotionMayHaveProducedInk
          ? "cancelled at X %.3f Y %.3f; possible ink"
          : "cancelled at X %.3f Y %.3f",
        finalPosition.point.x,
        finalPosition.point.y
      )
    case .ambiguous(let ambiguity):
      return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  var lastPenOutcomeText: String {
    if frameMode == .simulated, let pose = simulatedLearningSnapshot?.penPose {
      return "simulated \(pose.rawValue); not physical evidence"
    }
    guard let outcome = machineSnapshot?.lastPenOutcome else { return "none" }
    switch outcome {
    case .refused(let reason):
      return "refused: \(reason.actionableDescription)"
    case .commandedAndSettled(let command, let commandedState):
      return "\(command.rawValue) acknowledged; commanded \(commandedState.rawValue)"
    case .ambiguous(let ambiguity):
      return "ambiguous: \(ambiguity.actionableDescription)"
    }
  }

  var actionableError: String? {
    if let cameraError { return cameraError }
    if let visionError { return visionError }
    if frameMode == .simulated { return discoveryError ?? explorationError }
    if let machineError { return machineError }
    if let blocker = machineSnapshot?.machine.blockers.first {
      return machineBlockerLabel(blocker)
    }
    if case .refused(let refusal) = machineSnapshot?.lastMotionOutcome {
      return refusal.actionableDescription
    }
    if case .ambiguous(let ambiguity) = machineSnapshot?.lastMotionOutcome {
      return ambiguity.actionableDescription
    }
    if case .refused(let refusal) = machineSnapshot?.lastPenOutcome {
      return refusal.actionableDescription
    }
    if case .ambiguous(let ambiguity) = machineSnapshot?.lastPenOutcome {
      return ambiguity.actionableDescription
    }
    return nil
  }

  var passiveProbeUnavailableReason: String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if passiveProbeInProgress { return "Controller connection inspection is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select one serial device first." }
    return nil
  }

  /// Presentation availability only. MachineController repeats every physical
  /// safety check when it receives the typed request.
  var motionUnavailableReason: String? {
    if frameMode == .simulated {
      if let reason = simulatedManualMotionUnavailableReason { return reason }
    } else if let reason = directManualMotionUnavailableReason {
      return reason
    }
    guard let xStep = inputNumber(xStepText), let yStep = inputNumber(yStepText),
      let feed = inputNumber(feedText)
    else { return "Enter numeric X step, Y step, and feed values." }
    guard xStep > 0, yStep > 0 else {
      return "X and Y step magnitudes must be greater than zero."
    }
    guard feed > 0 else { return "Feed must be greater than zero." }
    return nil
  }

  private var simulatedManualMotionUnavailableReason: String? {
    guard controllerSessionEstablished else { return "Connect the learning simulator first." }
    guard motionAuthorizationEnabled else { return "Enable simulated Motion first." }
    guard simulatedLearningSnapshot?.currentOperation == nil else {
      return "A simulated operation already owns motion."
    }
    return nil
  }

  private var manualMotionPenState: PenState {
    if frameMode == .simulated {
      guard let pose = simulatedLearningSnapshot?.penPose else { return .unknown }
      return switch pose {
      case .unknown: .unknown
      case .up: .up
      case .down: .down
      }
    }
    return machineSnapshot?.machine.penState ?? .unknown
  }

  private var ordinaryRelativeJogUnavailableReason: String? {
    if frameMode == .simulated {
      if let reason = simulatedManualMotionUnavailableReason { return reason }
      guard simulatedLearningSnapshot?.penPose == .up else {
        return "Set the simulated pen Up before carriage travel."
      }
      return nil
    }
    return directCarriageMotionUnavailableReason
  }

  private var learningStickyAmbiguityReason: String? {
    if frameMode == .simulated, let ambiguity = simulatedLearningSnapshot?.stickyAmbiguity {
      return
        "Sticky simulated ambiguity at \(String(describing: ambiguity.context)). Disconnect and reconnect before any machine-affecting action."
    }
    if let ambiguity = machineSnapshot?.machine.stickyAmbiguity {
      return
        "\(ambiguity.actionableDescription) Disconnect and reconnect before any machine-affecting action."
    }
    return nil
  }

  private var directManualMotionUnavailableReason: String? {
    directMotionUnavailableReason
  }

  private var directCarriageMotionUnavailableReason: String? {
    if let reason = directMotionUnavailableReason { return reason }
    guard let machine = machineSnapshot?.machine else {
      return MotionRefusal.notConnected.actionableDescription
    }
    if machine.penState != .up {
      return MotionRefusal.penNotUp(machine.penState).actionableDescription
    }
    return nil
  }

  private var directMotionUnavailableReason: String? {
    if jogRequestInProgress { return "A relative jog is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if frameMode == .simulated {
      return "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
    }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if let reason = controllerPoseRevalidationUnavailableReason { return reason }
    if selectedSerialDevice == nil { return "Select and connect one serial device." }
    guard let snapshot = machineSnapshot else {
      return MotionRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return MotionRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return MotionRefusal.operationInFlight.actionableDescription
    }
    if machine.connection != .connected {
      return MotionRefusal.notConnected.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return MotionRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return MotionRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return MotionRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    if machine.pins.hasRelevantLimitAsserted {
      return MotionRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    if machine.position == nil {
      return MotionRefusal.machinePositionUnknown.actionableDescription
    }
    if machine.motionGuardState != .active {
      return MotionRefusal.motionGuardInactive.actionableDescription
    }
    return nil
  }

  private var controllerPoseRevalidationUnavailableReason: String? {
    guard frameMode == .live else { return nil }
    if case .requiresVisualRevalidation = controllerPoseApplicability {
      return
        "Saved learning is loaded, but physical carriage pose is unproven after restart. Revalidate the saved tip calibration from a fresh cap frame before motion."
    }
    return nil
  }

  func penUnavailableReason(for command: PenCommand) -> String? {
    if penRequestInProgress { return "A pen command is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if frameMode == .simulated {
      if !controllerSessionEstablished { return "Connect the learning simulator first." }
      if !motionAuthorizationEnabled { return "Enable simulated Motion first." }
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      return nil
    }
    if machineActions == nil { return "Native machine composition is unavailable." }
    if selectedSerialDevice == nil { return "Select and connect one serial device." }
    guard let snapshot = machineSnapshot else {
      return PenRefusal.notConnected.actionableDescription
    }
    let machine = snapshot.machine
    if let ambiguity = machine.stickyAmbiguity {
      return PenRefusal.stickyAmbiguity(ambiguity).actionableDescription
    }
    if machine.operationInFlight || snapshot.currentOperation != .idle {
      return PenRefusal.operationInFlight.actionableDescription
    }
    if machine.connection != .connected {
      return PenRefusal.notConnected.actionableDescription
    }
    if machine.motionGuardState != .active {
      return PenRefusal.motionGuardInactive.actionableDescription
    }
    guard let controllerState = machine.controllerState, controllerState.isRecognized else {
      return PenRefusal.controllerStateUnknown.actionableDescription
    }
    if controllerState.isAlarm {
      return PenRefusal.controllerAlarm("controller is in Alarm").actionableDescription
    }
    if controllerState != .idle {
      return PenRefusal.controllerNotIdle(controllerState).actionableDescription
    }
    guard command == .lower else { return nil }
    if let reason = controllerPoseRevalidationUnavailableReason { return reason }
    if machine.pins.hasRelevantLimitAsserted {
      return PenRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    guard machine.position != nil else {
      return PenRefusal.machinePositionUnknown.actionableDescription
    }
    return nil
  }

  func setOverlay(_ overlay: UserSceneOverlay, enabled: Bool) {
    guard !hasShutdown else { return }
    overlayPreferenceState.applyOperatorSelection(overlay, enabled: enabled)
    persistOverlayPreference(overlayPreferenceState.enabled)
    Task { await reconcileAutomaticVisionAnalysis() }
  }

  private var sceneAnalysisIsRequested: Bool {
    !overlayPreferenceState.enabled.isEmpty
  }

  private var requestedSceneFeatures: SceneFeatureSet {
    SceneFeatureSet(preference: overlayPreferenceState)
  }

  private var automaticVisionAnalysisShouldRun: Bool {
    guard frameMode == .live, livePenCapAppearanceSelection != nil, sceneAnalysisIsRequested,
      case .running = cameraSnapshot?.state
    else { return false }
    return true
  }

  private func reconcileAutomaticVisionAnalysis() async {
    guard !hasShutdown, let cameraActions else { return }
    if automaticVisionAnalysisShouldRun {
      let generation = lifetimeGeneration
      await cameraActions.setSceneAnalysisRegion(videoAnalysisRegionLock?.region)
      let snapshot = await cameraActions.setAutomaticInspection(
        visionAnalysisCadence,
        requestedSceneFeatures
      )
      guard canCommit(generation), frameMode == .live else { return }
      visionAnalysisSnapshot = snapshot
      visionError = snapshot.lastError
      beginVisionUpdates(generation: generation)
      if let result = snapshot.latestResult { receiveVision(result) }
      return
    }

    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    let snapshot = await cameraActions.setAutomaticInspection(nil, [])
    visionAnalysisSnapshot = snapshot
    visionError = snapshot.lastError
    let cameraSnapshot = await cameraActions.snapshot()
    self.cameraSnapshot = cameraSnapshot
    if let latest = cameraSnapshot.latestFrame { displayedFrame = latest }
  }

  func refreshSerialDevices() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    let discovered = serialDeviceDiscovery()
    if let selectedSerialDevice,
      !discovered.contains(where: { $0.identifier == selectedSerialDevice.identifier })
    {
      await machineActions?.disconnect()
      guard canCommit(generation) else { return }
      await clearMachineAuthority(clearSelection: true)
    }
    guard canCommit(generation) else { return }
    serialDevices = discovered
    if selectedSerialDevice == nil, let rememberedSerialDeviceIdentifier {
      selectedSerialDevice = discovered.first {
        $0.identifier == rememberedSerialDeviceIdentifier
      }
    }
  }

  func performApplicationStartup(_ policy: AdaptivePlotterLaunchPolicy) async {
    await loadDrawingEvidenceArchive()
    await refreshSerialDevices()
    switch policy.startupRoute {
    case .preferredCamera:
      await startPreferredCameraAtStartup()
    case .simulated:
      await switchFrameMode(.simulated)
    }
  }

  private func loadDrawingEvidenceArchive() async {
    guard let liveDrawingEvidenceActions else { return }
    switch await liveDrawingEvidenceActions.load() {
    case .absent:
      drawingEvidenceArchive = DrawingRunEvidenceArchive()
      activeLearningSession.drawingStudio.redrawBlockedPlanHashes = []
      drawingEvidenceError = nil
    case .loaded(let archive):
      drawingEvidenceArchive = archive
      drawingEvidenceError = nil
      restoreDrawingRedrawBlocksFromEvidence()
      restoreInteractiveLearningCompletionFromEvidence()
    case .rejected(let rejection):
      drawingEvidenceError = "Saved drawing evidence was rejected: \(rejection)"
    }
  }

  private func restoreDrawingRedrawBlocksFromEvidence() {
    let paper = currentPaperRevisionContext
    activeLearningSession.drawingStudio.redrawBlockedPlanHashes = Set(
      drawingEvidenceArchive.records.lazy
        .filter {
          $0.paper == paper && $0.executionFrontiers.commandedStrokeCount > 0
        }
        .map(\.plan.contentHash)
    )
  }

  private func restoreInteractiveLearningCompletionFromEvidence() {
    guard frameMode == .live, interactiveLearningIsComplete else { return }
    drawingTrialAssessment = .predictionObserved
  }

  private func persistCompletedIsolatedLineEvidence() async {
    guard frameMode == .live, let actions = liveDrawingEvidenceActions,
      let attemptID = activeExerciseAttemptID,
      let registration = tipCameraRegistration,
      let lineStart = drawingTrialLineStart,
      let lineEnd = drawingTrialLineEnd,
      let observation = lastInkObservation,
      let region = currentDrawableMachineRegion
    else { return }
    do {
      let delta = try lineStart.point.vector(to: lineEnd.point)
      let length = delta.magnitude
      guard length > 0 else { return }
      let program = try DrawingProgramCatalog.program(
        for: .line,
        style: StrokeStyle(
          nominalLineWidth: 0.4,
          penProfileID: PenProfileID(toolAssemblyRevision.rawValue)
        )
      )
      let placement = try DrawingPlacement(
        fieldAnchor: Point2<FieldSpace>(x: 5, y: 50),
        machineAnchor: lineStart.point,
        uniformScale: length / 90,
        rotationRadians: atan2(delta.dy, delta.dx)
      )
      let provenance = try drawingPlanningProvenance(for: registration)
      let plan = try DrawingPlanner.plan(
        program: program,
        placement: placement,
        drawableRegion: region,
        provenance: provenance
      )
      let runObservation = try DrawingRunObservationOutcome(
        isolated: .observed(observation),
        sourceForRejection: observation.source,
        algorithmRevisionForRejection: observation.algorithmRevision
      )
      let registrationSHA = provenance.registrationContentHash.description
      let record = try DrawingRunEvidenceRecord(
        runID: RunID(attemptID.rawValue),
        requestID: attemptID.rawValue,
        role: .evaluationHoldout,
        evidenceDisposition: .attributable,
        requestFrontier: .admitted,
        executionFrontiers: DrawingRunExecutionFrontiers(
          plannedStrokeCount: 1,
          commandedStrokeCount: 1,
          controllerCompletedStrokeCount: 1,
          inkVerifiedStrokeCount: 1
        ),
        executionDisposition: .completed,
        program: DrawingProgramEvidenceReference(program: program),
        placement: DrawingPlacementEvidenceReference(
          placementID: attemptID.rawValue,
          placement: placement
        ),
        plan: DrawingExecutionPlanEvidenceReference(plan: plan),
        planningProvenance: provenance,
        tipCalibration: DrawingTipCalibrationEvidenceReference(
          acceptedRevisionID: registration.acceptedRevisionID,
          registrationEvidenceSHA256: registrationSHA,
          applicability: registration.applicability,
          estimatorRevision: registration.estimatorRevision
        ),
        paper: currentPaperRevisionContext,
        observation: runObservation,
        recordedAt: RuntimeTimestamp(
          monotonicNanoseconds: max(nowNanoseconds(), observation.postLine.captureNanoseconds)
        )
      )
      drawingEvidenceArchive = try await actions.append(record)
      let stageFourCheckpoint = AcceptedStageFourCheckpoint(
        recordID: record.recordID,
        tipCalibrationRevisionID: registration.acceptedRevisionID,
        paperContactPlane: currentPaperRevisionContext.contactPlane
      )
      acceptedStageFourCheckpoint = stageFourCheckpoint
      persistAcceptedLearningPathCheckpoint(stageFour: stageFourCheckpoint)
      drawingEvidenceError = nil
    } catch {
      drawingEvidenceError = "Completed comparison could not be archived: \(error)"
    }
  }

  func disconnectMachineSession() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard selectedSerialDevice != nil, !passiveProbeInProgress, !jogRequestInProgress,
      !penRequestInProgress
    else { return }
    await machineActions?.disconnect()
    guard canCommit(generation) else { return }
    await clearMachineAuthority(clearSelection: false)
  }

  func performControllerConnectionAction() async {
    guard controllerConnectionActionUnavailableReason == nil else { return }
    controllerConnectionActionInProgress = true
    defer { controllerConnectionActionInProgress = false }
    if frameMode == .simulated {
      let response =
        if controllerSessionEstablished {
          await simulatedLearningRuntime.disconnect()
        } else {
          await simulatedLearningRuntime.connect()
        }
      applySimulatedSnapshotResponse(
        response,
        action: controllerSessionEstablished ? "Disconnect simulator" : "Connect simulator"
      )
      return
    }
    if controllerLinkIsOpen {
      await disconnectMachineSession()
    } else {
      await connectSelectedController()
    }
  }

  /// Updates only the operator's pending device choice. A picker change is not
  /// a successful connection and cannot turn the status indicator green.
  func selectSerialDevice(_ descriptor: MachineLinkDescriptor) async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard activeDiscoverySequenceID == nil, activeExplorationOperation == nil else { return }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    guard serialDevices.contains(where: { $0.identifier == descriptor.identifier }) else { return }
    if selectedSerialDevice?.identifier != descriptor.identifier, machineSnapshot != nil {
      await machineActions?.disconnect()
      guard canCommit(generation) else { return }
      await clearMachineAuthority(clearSelection: false)
    }
    guard canCommit(generation) else { return }
    selectedSerialDevice = descriptor
    rememberedSerialDeviceIdentifier = descriptor.identifier
    persistSelectedSerialIdentifier(descriptor.identifier)
  }

  /// Test/support entrypoint for establishing the same selected-device session
  /// without asserting that its passive inspection succeeded.
  func establishMachineSession(_ descriptor: MachineLinkDescriptor) async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    await selectSerialDevice(descriptor)
    await openSelectedMachineSession()
  }

  func connectSelectedController() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard selectedSerialDevice != nil else { return }
    await openSelectedMachineSession()
    guard machineError == nil, machineSnapshot != nil else { return }
    await requestPassiveProbe()
  }

  private func openSelectedMachineSession() async {
    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let descriptor = selectedSerialDevice else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard !passiveProbeInProgress && !jogRequestInProgress && !penRequestInProgress else { return }
    guard let machineActions else {
      machineError = "Native machine composition is unavailable."
      return
    }
    machineError = nil
    do {
      let snapshot = try await machineActions.select(descriptor)
      guard canCommit(generation) else { return }
      machineSnapshot = snapshot
      passiveProbeResult = nil
      lastMotionGuardActivationText = "not activated"
    } catch {
      guard canCommit(generation) else { return }
      machineError = actionableDescription(error)
      machineSnapshot = nil
      passiveProbeResult = nil
    }
  }

  func requestPassiveProbe() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard passiveProbeUnavailableReason == nil, let machineActions else { return }
    passiveProbeInProgress = true
    machineError = nil
    passiveProbeResult = nil
    defer { passiveProbeInProgress = false }
    let operation = Task { try await machineActions.requestPassiveProbe() }
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    do {
      let result = try await operation.value
      let finalSnapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      passiveProbeResult = result
      machineSnapshot = finalSnapshot
      revalidateParkedAcceptedArtifactCheckpoint(
        with: result,
        currentPosition: finalSnapshot?.machine.position
      )
    } catch {
      let finalSnapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      machineError = actionableDescription(error)
      machineSnapshot = finalSnapshot
    }
  }

  /// Explicit operator-owned alarm unlock. `$X` acknowledgement is never
  /// treated as connection or motion authority; this action always follows it
  /// with a complete passive probe before publishing current controller facts.
  func clearControllerAlarm() async {
    guard controllerAlarmClearActionUnavailableReason == nil, let machineActions else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    controllerAlarmClearInProgress = true
    machineError = nil
    defer { controllerAlarmClearInProgress = false }

    let outcome = await machineActions.requestControllerAlarmClear()
    var snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
    guard outcome == .acknowledged else {
      machineError = outcome.actionableDescription
      return
    }

    passiveProbeInProgress = true
    passiveProbeResult = nil
    defer { passiveProbeInProgress = false }
    do {
      let probe = try await machineActions.requestPassiveProbe()
      snapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      passiveProbeResult = probe
      machineSnapshot = snapshot
      revalidateParkedAcceptedArtifactCheckpoint(
        with: probe,
        currentPosition: snapshot?.machine.position
      )
    } catch {
      snapshot = await machineActions.snapshot()
      guard canCommit(generation) else { return }
      machineError = actionableDescription(error)
      machineSnapshot = snapshot
    }
  }

  @discardableResult
  func requestPenActuation(_ command: PenCommand) async -> PenOutcome? {
    await requestPenActuation(command, profile: currentPenActuationProfile)
  }

  @discardableResult
  private func requestPenActuation(
    _ command: PenCommand,
    profile: PenActuationProfile
  ) async -> PenOutcome? {
    if frameMode == .simulated {
      guard penUnavailableReason(for: command) == nil else { return nil }
      penRequestInProgress = true
      defer { penRequestInProgress = false }
      let pose: SimulatedLearningPenPose = command.commandedState == .up ? .up : .down
      let response = await simulatedLearningRuntime.setPenPose(pose)
      applySimulatedSnapshotResponse(
        response,
        action: "Set simulated pen \(pose.rawValue)"
      )
      guard case .success = response.result else { return nil }
      let outcome = PenOutcome.commandedAndSettled(
        command: command,
        commandedState: command.commandedState
      )
      activeLearningSession.lastPenExecutionByCommand[command] = PenCommandExecutionEvidence(
        command: command,
        profile: profile,
        outcome: outcome,
        timestamp: RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
      )
      return outcome
    }
    guard let generation = beginHardwareIntent() else { return nil }
    defer { endHardwareIntent() }
    guard penUnavailableReason(for: command) == nil, let machineActions else { return nil }
    penRequestInProgress = true
    machineError = nil
    defer { penRequestInProgress = false }
    let operation = Task { await machineActions.requestPenActuation(command, profile) }
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    let outcome = await operation.value
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return nil }
    machineSnapshot = snapshot
    activeLearningSession.lastPenExecutionByCommand[command] = PenCommandExecutionEvidence(
      command: command,
      profile: profile,
      outcome: outcome,
      timestamp: RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
    )
    return outcome
  }

  private func setPenActuationValue(_ value: Int, for command: PenCommand) {
    let draft = effectivePenActuationProfile.replacingValue(
      for: command,
      with: value
    )
    activeLearningSession.penActuationDraft = draft
    pendingPenSetpointCommand = command
    guard penSetpointActuationTask == nil else { return }
    penSetpointActuationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while let nextCommand = pendingPenSetpointCommand {
        pendingPenSetpointCommand = nil
        let profile = effectivePenActuationProfile
        await requestPenActuation(nextCommand, profile: profile)
      }
      penSetpointActuationTask = nil
    }
  }

  private func awaitPendingPenSetpointActuation() async {
    while let task = penSetpointActuationTask {
      await task.value
    }
  }

  func startDiscoverySequence(_ sequenceID: DiscoverySequenceID) async {
    guard discoveryStartUnavailableReason(for: sequenceID) == nil else { return }
    if sequenceID == .penInteraction {
      guard penCapAppearanceSelection != nil,
        penCapAppearanceSelectionContext == nil,
        penInteractionSequenceUnavailableReason == nil
      else {
        discoveryError =
          penInteractionSequenceUnavailableReason
          ?? "Identify Pen Cap must be accepted before Pen Interaction questions begin."
        return
      }
    }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: learningPathItemID(for: sequenceID),
        mode: .normal
      )
    }
    selectedDiscoverySequenceID = sequenceID
    discoveryError = nil
    if sequenceID == .penInteraction {
      activeLearningSession.penActuationDraft = currentPenActuationProfile
      activeLearningSession.lastPenExecutionByCommand = [:]
      activeLearningSession.pendingPenUpPositions = []
      activeLearningSession.pendingPenUpSpindleValues = []
      activeLearningSession.pendingPenUpControllerOutcomes = []
      activeLearningSession.pendingPenUpTimestamps = []
      activeLearningSession.pendingPenDownPositions = []
      activeLearningSession.pendingPenDownSpindleValues = []
      activeLearningSession.pendingPenDownControllerOutcomes = []
      activeLearningSession.pendingPenDownTimestamps = []
    }
    var transaction = DiscoveryTransaction(sequenceID: sequenceID)
    do {
      try transaction.begin()
      discoveryTransactions[sequenceID] = transaction
      await advanceDiscoverySequence(sequenceID)
    } catch {
      discoveryError = "Human-Guided Discovery could not start: \(error)"
      recordDiscoveryAttempt(
        sequenceID: sequenceID,
        disposition: .failed(String(describing: error))
      )
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
    }
  }

  private func advanceDiscoverySequence(_ sequenceID: DiscoverySequenceID) async {
    while !hasShutdown, activeDiscoverySequenceID == sequenceID,
      let step = discoveryTransactions[sequenceID]?.currentStep
    {
      switch step.action {
      case .askQuestion:
        guard recordDiscovery(.questionPresented, for: sequenceID) else { return }

      case .awaitOperatorChoice:
        return

      case .awaitPhysicalPenConfirmation:
        return

      case .announce(let message):
        _ = await announceAdvisory(message)
        guard activeDiscoverySequenceID == sequenceID,
          discoveryTransactions[sequenceID]?.currentStep?.id == step.id
        else { return }
        guard recordDiscovery(.announcementCompleted, for: sequenceID) else { return }

      case .startBoundaryJog(let direction):
        guard boundaryMotionTask == nil else { return }
        let jogDirection = jogDirection(from: direction)
        boundaryMotionTask = Task { [weak self] in
          guard let self else { return }
          await self.executeBoundaryMotion(jogDirection)
          self.boundaryMotionTask = nil
        }
        return

      case .awaitContextualStop:
        return

      case .cancelBoundaryJogAndAwaitIdle:
        // `stopCurrentOperation()` owns the one cancel byte and then awaits the
        // original boundary-motion task. The motion owner records final MPos.
        return

      case .actuatePen(let command):
        let controllerSummary: String
        if frameMode == .simulated {
          let pose: SimulatedLearningPenPose = command.commandedState == .up ? .up : .down
          let response = await simulatedLearningRuntime.setPenPose(pose)
          switch response.result {
          case .success(let snapshot):
            simulatedLearningSnapshot = snapshot
            simulatorPenState = simulatorPenState(from: pose)
            controllerSummary = "Simulated pen \(pose.rawValue). \(response.evidenceNotice.label)"
          case .failure(let refusal):
            await failDiscovery(
              sequenceID, failure: .refused("Simulated pen action refused: \(refusal)."))
            return
          }
        } else {
          await requestPenActuation(command)
          guard case .commandedAndSettled = machineSnapshot?.lastPenOutcome else {
            let failure: WorkflowFailure =
              if case .ambiguous = machineSnapshot?.lastPenOutcome {
                .ambiguous(lastPenOutcomeText)
              } else {
                .refused(lastPenOutcomeText)
              }
            await failDiscovery(sequenceID, failure: failure)
            return
          }
          controllerSummary = lastPenOutcomeText
        }
        guard
          recordDiscovery(
            .penCommandSettled(command, controllerSummary: controllerSummary),
            for: sequenceID
          )
        else { return }
      case .commitBoundaryObservation(let direction):
        await commitBoundaryObservation(direction: direction, sequenceID: sequenceID)
        return
      }
    }
  }

  private func commitBoundaryObservation(
    direction: BoundaryDirection,
    sequenceID: DiscoverySequenceID
  ) async {
    guard let attemptID = activeExerciseAttemptID,
      let finalPosition = pendingBoundaryFinalPositions[attemptID],
      let ownerID = pendingBoundaryOwnerIDs[attemptID],
      let stopCapabilityID = pendingBoundaryStopCapabilities[attemptID]
    else {
      await failDiscovery(
        sequenceID,
        failure: .failed(
          "The Boundary commit is missing its attempt-bound Stop/Idle/final-MPos controller settlement."
        )
      )
      return
    }
    do {
      let aggregateRevision = LearningArtifactRevision(
        kind: .boundarySideAggregate(direction),
        attemptID: attemptID,
        disposition: .succeeded
      )
      let evidence = try BoundarySideAttemptEvidence(
        attemptID: attemptID,
        direction: direction,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        ownerID: ownerID,
        stopCapabilityID: stopCapabilityID.rawValue,
        stopIntent: .operatorStop,
        finalPosition: finalPosition,
        disposition: .succeeded
      )
      let compatibility = BoundaryNumericCompatibility(
        direction: direction,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        numericEstimatorRevision: "boundary-machine-coordinate-v1"
      ).attemptCompatibility
      var stagedHistories = boundaryAttemptHistories
      var directionHistories = stagedHistories[direction] ?? [:]
      var history =
        try directionHistories[compatibility]
        ?? ExerciseAttemptHistory(compatibility: compatibility)
      let acceptedSequence = acceptedAttemptSequence &+ 1
      let attempt = try ExerciseAttempt(
        id: attemptID,
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: acceptedSequence,
        value: evidence
      )
      if activeExerciseAttemptMode == .replacement {
        _ = try history.recordWholeIncludedSetReplacement(attempt)
      } else {
        try history.record(attempt)
      }
      directionHistories[compatibility] = history
      stagedHistories[direction] = directionHistories

      if boundaryAtomicCommitFailurePoints.contains(.aggregateConstruction) {
        throw LearningPathOperationError.requiredState(
          "Injected Boundary aggregate construction failure."
        )
      }
      let aggregate = try BoundarySideAggregate(
        direction: direction,
        revisionID: aggregateRevision.id,
        history: history
      )
      var stagedAggregates = boundarySideAggregates
      stagedAggregates[direction] = aggregate

      if boundaryAtomicCommitFailurePoints.contains(.artifactGraphCommit) {
        throw LearningPathOperationError.requiredState(
          "Injected Boundary artifact-graph commit failure."
        )
      }
      var stagedGraph = learningArtifactGraph
      let aggregateCommit = try stagedGraph.commitReplacement(aggregateRevision)
      let invalidatedRevisionIDs = aggregateCommit.invalidatedRevisionIDs

      var stagedProgress = PairedBoundaryProgress()
      var progressOrder = pairedBoundaryProgress.acceptedDirections
      if !progressOrder.contains(direction) { progressOrder.append(direction) }
      for acceptedDirection in progressOrder {
        guard let acceptedAggregate = stagedAggregates[acceptedDirection] else { continue }
        try stagedProgress.accept(
          acceptedDirection,
          revisionID: acceptedAggregate.revisionID
        )
      }

      var stagedTransaction = discoveryTransactions[sequenceID]!
      try stagedTransaction.record(
        .boundaryObservationCommitted(evidence, aggregate: aggregate)
      )
      guard stagedTransaction.state == .succeeded else {
        throw LearningPathOperationError.requiredState(
          "The typed Boundary transaction did not finish after its atomic commit event."
        )
      }

      // One nonthrowing authority swap. All potentially failing construction,
      // graph validation, center derivation, and local-frame derivation ran on
      // staged copies above.
      boundaryAttemptHistories = stagedHistories
      boundaryAttemptEvidenceByAttemptID[attemptID] = evidence
      boundarySideAggregates = stagedAggregates
      pairedBoundaryProgress = stagedProgress
      acceptedAttemptSequence = acceptedSequence
      discoveryTransactions[sequenceID] = stagedTransaction
      learningArtifactGraph = stagedGraph
      applyArtifactInvalidations(invalidatedRevisionIDs)
      if !stagedProgress.isComplete {
        centerArrivalPosition = nil
        centerArrivalRetryRequired = false
      }
      if let forcedNext = stagedProgress.allowedDirections.onlyElement {
        selectedBoundaryDirection = forcedNext
      } else if !stagedProgress.allowedDirections.contains(selectedBoundaryDirection),
        let first = stagedProgress.allowedDirections.first
      {
        selectedBoundaryDirection = first
      }
      discoveryError = nil
      restartableExerciseItemID = nil
      appendBoundaryActivity(
        actor: .workspace,
        direction: direction,
        phase: .commit,
        disposition: .succeeded,
        attemptID: attemptID,
        operationOwnerID: .liveBoundary(ownerID),
        stopCapabilityID: stopCapabilityID,
        finalPosition: finalPosition,
        affectedRevisionIDs: [aggregate.revisionID],
        detail: .message(
          "Typed direction + operator Stop + controller Idle/final MPos committed atomically as N=\(aggregate.validSampleCount). Camera and Vision were not consulted and could not veto the commit."
        )
      )
      persistAcceptedMachineArtifacts()
      finishActiveExerciseAttempt(disposition: .succeeded)
      if stagedProgress.isComplete {
        do {
          try deriveCenterAndLocalFrame(afterBoundaryAttempt: attemptID)
          persistAcceptedMachineArtifacts()
        } catch {
          discoveryError =
            "All four machine boundaries are accepted, but center/local derivation needs attention: \(actionableDescription(error)) No Boundary motion will repeat automatically."
          appendBoundaryActivity(
            actor: .workspace,
            direction: direction,
            phase: .recovery,
            disposition: .failed(actionableDescription(error)),
            attemptID: attemptID,
            operationOwnerID: .liveBoundary(ownerID),
            stopCapabilityID: stopCapabilityID,
            finalPosition: finalPosition,
            retainedRevisionIDs: [aggregate.revisionID],
            detail: .message(discoveryError!),
            recovery: .continueWithAcceptedFallback(direction),
            acceptedFallbackRemainsCurrent: true
          )
        }
      }
    } catch {
      await failDiscovery(
        sequenceID,
        failure: workflowFailure(for: error)
      )
    }
  }

  private func deriveCenterAndLocalFrame(
    afterBoundaryAttempt attemptID: ExerciseAttemptID
  ) throws {
    guard pairedBoundaryProgress.isComplete else { return }
    let aggregates = BoundaryDirection.allCases.compactMap { boundarySideAggregates[$0] }
    let center = try EstimatedMachineCenter.derive(from: aggregates)
    let localFrame = try LearnedLocalCoordinateFrame.derive(from: aggregates)
    let centerRevision = LearningArtifactRevision(
      kind: .estimatedMachineCenter,
      attemptID: attemptID,
      disposition: .succeeded,
      consumedRevisionIDs: center.consumedRevisionIDs
    )
    var stagedGraph = learningArtifactGraph
    let centerCommit: LearningArtifactCommit
    if let priorCenter = learningArtifactGraph.currentRevision(for: .estimatedMachineCenter),
      stagedGraph.revision(id: priorCenter.id)?.state == .invalidated
    {
      centerCommit = try stagedGraph.commitReplacement(
        centerRevision,
        supersedingInvalidatedRevision: priorCenter.id
      )
    } else {
      centerCommit = try stagedGraph.commitReplacement(centerRevision)
    }
    learningArtifactGraph = stagedGraph
    applyArtifactInvalidations(centerCommit.invalidatedRevisionIDs)
    estimatedMachineCenter = center
    learnedLocalCoordinateFrame = localFrame
    centerArrivalPosition = nil
    centerArrivalRetryRequired = false
  }

  private func recordDiscovery(_ event: DiscoveryEvent, for sequenceID: DiscoverySequenceID) -> Bool
  {
    guard var transaction = discoveryTransactions[sequenceID] else { return false }
    do {
      try transaction.record(event)
      discoveryTransactions[sequenceID] = transaction
      if transaction.state == .succeeded {
        commitSuccessfulDiscoveryAttempt(sequenceID)
      }
      return true
    } catch {
      transaction.fail("Unexpected discovery event: \(error)")
      discoveryTransactions[sequenceID] = transaction
      discoveryError = "Unexpected Human-Guided Discovery event: \(error)"
      return false
    }
  }

  private func failDiscovery(_ sequenceID: DiscoverySequenceID, failure: WorkflowFailure) async {
    let reason = failure.detail
    if var transaction = discoveryTransactions[sequenceID] {
      transaction.fail(reason)
      discoveryTransactions[sequenceID] = transaction
    }
    discoveryError = reason
    let disposition = failure.attemptDisposition
    let boundaryDirection = boundaryDirection(for: sequenceID)
    let boundaryAttemptID = activeExerciseAttemptID
    let acceptedFallback = boundaryDirection.flatMap { boundarySideAggregates[$0] }
    let isBoundaryRepeat =
      boundaryDirection != nil
      && (activeExerciseAttemptMode == .replacement || activeExerciseAttemptMode == .additional)
    recordDiscoveryAttempt(sequenceID: sequenceID, disposition: disposition)
    if let direction = boundaryDirection, let attemptID = boundaryAttemptID {
      appendBoundaryActivity(
        actor: .workspace,
        direction: direction,
        phase: .recovery,
        disposition: failure.boundaryDisposition,
        attemptID: attemptID,
        operationOwnerID: pendingBoundaryOwnerIDs[attemptID].map {
          .liveBoundary($0)
        },
        stopCapabilityID: pendingBoundaryStopCapabilities[attemptID],
        finalPosition: pendingBoundaryFinalPositions[attemptID],
        retainedRevisionIDs: acceptedFallback.map { [$0.revisionID] } ?? [],
        detail: .message(reason),
        recovery: acceptedFallback != nil
          ? .continueWithAcceptedFallback(direction)
          : .restartNormal(direction),
        acceptedFallbackRemainsCurrent: acceptedFallback != nil
      )
    }
    finishActiveExerciseAttempt(disposition: disposition)
    if isBoundaryRepeat, acceptedFallback != nil {
      // A failed typed Redo/Record Another never becomes generic Restart and
      // never replaces the already accepted runtime current path.
      restartableExerciseItemID = nil
    } else if machineSnapshot?.machine.stickyAmbiguity == nil {
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
    } else {
      restartableExerciseItemID = nil
    }
    boundaryTeachingState = .idle
    activeStoppableOperation = nil
    boundaryTeachingResultText = "Discovery stopped: \(reason)"
  }

  func stopCurrentOperation(capabilityID: ContextualStopCapabilityID) async {
    guard !jogCancelRequestInProgress,
      let operation = activeStoppableOperation,
      operation.target.capabilityID == capabilityID,
      latchContextualStopDisposition(
        for: operation.target,
        intent: .operatorStop,
        actor: "Operator",
        action: "Stop"
      )
    else { return }
    let target = operation.target
    switch target {
    case .pairedBoundary(_, let transactionID, let operationOwner, let attemptID, let direction):
      let sequenceID = sequenceID(for: direction)
      guard discoveryTransactions[sequenceID]?.id == transactionID,
        case .awaitContextualStop(direction) = discoveryTransactions[sequenceID]?.currentStep?
          .action
      else {
        await failDiscovery(
          sequenceID,
          failure: .failed(
            "The Stop capability no longer owns this Boundary Discovery transaction."))
        return
      }
      let recorded = recordDiscovery(.operatorStopRequested(direction), for: sequenceID)
      appendBoundaryActivity(
        actor: .operatorActor,
        direction: direction,
        phase: .stopLatched,
        disposition: .inProgress,
        attemptID: attemptID,
        operationOwnerID: operationOwner,
        stopCapabilityID: capabilityID,
        detail: .message(
          "Operator Stop latched before controller cancellation and any segment renewal.")
      )
      boundaryTeachingState = .cancelling(jogDirection(from: direction))
      boundaryTeachingResultText =
        "Stop requested. Waiting for the original motion owner to reach Idle."
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      if !recorded {
        if case .failed = discoveryTransactions[sequenceID]?.state {
          return
        }
        await failDiscovery(
          sequenceID,
          failure: .failed("The typed operator Stop event could not be recorded.")
        )
      }

    case .manualJog, .manualDrawingStroke:
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()

    case .exerciseMotion(_, _, let ownerID, _):
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      if ownerID != .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) {
        finishActiveExerciseAttempt(disposition: .cancelled)
        restartableExerciseItemID = ownerID
      }

    case .drawingTrial:
      let inkMayExist = operation.owner.drawingMayHaveInk
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      finishActiveExerciseAttempt(disposition: .cancelled)
      if inkMayExist {
        if observedDrawingTrialStep == .drawIsolatedLine {
          advanceDrawingTrialAfterSuccess(.drawIsolatedLine)
        }
        explorationError =
          "Drawing stopped after stroke admission; physical ink may exist. Draw is unavailable. Continue with return/observation."
        restartableExerciseItemID = nil
      } else {
        restartableExerciseItemID = .observedDrawingTrial(.chooseIsolatedLinePlan)
      }

    case .sparseTipBatch:
      if let location = operation.possibleInkLocation {
        blacklistedToolContactLocations.insert(location)
        sparseTipCalibrationCoordinator.blacklistPossibleInk(
          at: location,
          reason: "Operator stopped the five-circle batch after Pen Down."
        )
      }
      await cancelAndSettleStoppableOperation(operation, intent: .operatorStop)
      if sparseTipCalibrationCoordinator.blacklistedPositions.isEmpty {
        if activeExerciseAttemptOwnerID
          == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
        {
          finishActiveExerciseAttempt(disposition: .cancelled)
        }
        restartableExerciseItemID = .humanGuidedDiscovery(
          .calibratePenContactFromSparseMarks
        )
      } else {
        explorationError =
          "The five-circle calibration batch stopped after possible ink. Every affected paper location is blacklisted and will not be redrawn automatically."
        restartableExerciseItemID = nil
      }

    case .sparseTipBatchSegment(_, _, let location):
      blacklistedToolContactLocations.insert(location)
      sparseTipCalibrationCoordinator.blacklistPossibleInk(
        at: location,
        reason: "Operator stopped the 2 mm calibration circle after Pen Down."
      )
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      restartableExerciseItemID = nil
    }
  }

  private func requestSingleJogCancel(
    for target: ContextualStopTarget,
    intent: JogCancelIntent
  ) async {
    guard let operationOwner = target.operationOwner else { return }
    if case .simulated(let operationID) = operationOwner {
      guard beginCancellationRequest(for: target, intent: intent) else { return }
      defer { finishCancellationRequest(for: target) }
      let simulatedIntent: SimulatedLearningOperationIntent =
        switch intent {
        case .operatorStop: .stop
        case .cancelAttempt: .cancel
        case .shutdown: .shutdown
        }
      let response = await simulatedLearningRuntime.request(simulatedIntent, for: operationID)
      switch response.result {
      case .success(let outcome):
        simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
        updateContextualStopAudit(
          for: target,
          outcome:
            "\(outcome.disposition.rawValue); final simulated MPos X \(outcome.finalMPos.xMM) Y \(outcome.finalMPos.yMM); \(response.evidenceNotice.label)"
        )
      case .failure(let refusal):
        updateContextualStopAudit(
          for: target,
          outcome: "refused: \(refusal); \(response.evidenceNotice.label)"
        )
      }
      return
    }
    guard let machineActions else { return }
    let generation: UInt64?
    if intent == .shutdown {
      // Shutdown has already closed new hardware admission. This cancel is the
      // settlement of the exact owner admitted before that boundary, so it
      // must not attempt to reopen ordinary command admission.
      generation = nil
    } else {
      guard let admittedGeneration = beginHardwareIntent() else { return }
      generation = admittedGeneration
    }
    defer {
      if generation != nil { endHardwareIntent() }
    }
    guard beginCancellationRequest(for: target, intent: intent) else { return }
    defer { finishCancellationRequest(for: target) }
    let outcome = await machineActions.requestJogCancel(intent)
    updateContextualStopAudit(for: target, outcome: String(describing: outcome))
    let snapshot = await machineActions.snapshot()
    if let generation {
      guard canCommit(generation) else { return }
      machineSnapshot = snapshot
    }
  }

  private func latchContextualStopDisposition(
    for target: ContextualStopTarget,
    intent: JogCancelIntent,
    actor: String,
    action: String
  ) -> Bool {
    guard var operation = activeStoppableOperation,
      operation.target.capabilityID == target.capabilityID,
      case .available = operation.state
    else { return false }
    let latch = ContextualStopDispositionLatch(
      capabilityID: target.capabilityID,
      intent: intent,
      actor: actor
    )
    operation.state = .latched(latch, cancellationRequestInProgress: false)
    activeStoppableOperation = operation
    lastContextualStopAuditRecord = ContextualStopAuditRecord(
      capabilityID: target.capabilityID,
      actor: actor,
      action: action,
      disposition: intent,
      outcome: "requested; awaiting the original owner"
    )
    return true
  }

  private func installStoppableOperation(
    target: ContextualStopTarget,
    owner: StoppableOperationOwner
  ) {
    if var operation = activeStoppableOperation,
      case .sparseTipBatch = operation.target,
      operation.target.capabilityID == target.capabilityID
    {
      precondition(operation.segment == nil, "Only one sparse-tip batch segment may be active.")
      operation.segment = StoppableOperationSegment(target: target, owner: owner)
      activeStoppableOperation = operation
      return
    }
    precondition(activeStoppableOperation == nil, "Only one contextual Stop owner may exist.")
    activeStoppableOperation = ActiveStoppableOperation(target: target, owner: owner)
  }

  private func clearStoppableOperation(matching target: ContextualStopTarget) {
    guard var operation = activeStoppableOperation else { return }
    if operation.target == target {
      activeStoppableOperation = nil
      return
    }
    guard operation.segment?.target == target else { return }
    operation.segment = nil
    activeStoppableOperation = operation
  }

  private func sparseTipBatchCapabilityID() throws -> ContextualStopCapabilityID {
    guard let target = activeStopTarget,
      case .sparseTipBatch(let capabilityID, _) = target
    else {
      throw LearningPathOperationError.requiredState(
        "The five-circle calibration batch no longer owns its Stop capability."
      )
    }
    return capabilityID
  }

  private func supervisedTravelStopCapabilityID(
    ownerID: LearningPathItemID
  ) throws -> ContextualStopCapabilityID {
    if ownerID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
      return try sparseTipBatchCapabilityID()
    }
    return ContextualStopCapabilityID()
  }

  private func requireSparseTipBatchContinuation() throws {
    guard !Task.isCancelled,
      let operation = activeStoppableOperation,
      case .sparseTipBatch = operation.target,
      operation.state.latch == nil
    else {
      throw LearningPathOperationError.controllerCancelled(
        "The five-circle calibration batch was stopped; no later segment was admitted."
      )
    }
  }

  private func cancelSparseTipSegmentIfRequested(
    target: ContextualStopTarget,
    owner: StoppableOperationOwner
  ) async throws {
    guard let operation = activeStoppableOperation,
      case .sparseTipBatch = operation.target,
      operation.segment?.target == target,
      let latch = operation.state.latch
    else { return }
    await requestSingleJogCancel(for: target, intent: latch.intent)
    await owner.settle()
    throw LearningPathOperationError.controllerCancelled(
      "The five-circle calibration batch was stopped during segment admission."
    )
  }

  private func setSparseTipBatchPossibleInkLocation(
    _ location: BlacklistedToolContactLocation
  ) {
    guard var operation = activeStoppableOperation,
      case .sparseTipBatch = operation.target
    else { return }
    operation.possibleInkLocation = location
    activeStoppableOperation = operation
  }

  private func clearSparseTipBatchPossibleInkLocation(
    matching location: BlacklistedToolContactLocation
  ) {
    guard var operation = activeStoppableOperation,
      case .sparseTipBatch = operation.target,
      operation.possibleInkLocation == location
    else { return }
    operation.possibleInkLocation = nil
    activeStoppableOperation = operation
  }

  private func cancelAndSettleStoppableOperation(
    _ operation: ActiveStoppableOperation,
    intent: JogCancelIntent
  ) async {
    if case .sparseTipBatch = operation.target {
      operation.owner.cancelBatch()
      if let segment = operation.segment {
        await requestSingleJogCancel(for: segment.target, intent: intent)
        await segment.owner.settle()
      }
      await operation.owner.settle()
      return
    }
    await requestSingleJogCancel(for: operation.target, intent: intent)
    await operation.owner.settle()
  }

  private func beginCancellationRequest(
    for target: ContextualStopTarget,
    intent: JogCancelIntent
  ) -> Bool {
    guard var operation = activeStoppableOperation,
      operation.target.capabilityID == target.capabilityID,
      case .latched(let latch, false) = operation.state,
      latch.intent == intent
    else { return false }
    operation.state = .latched(latch, cancellationRequestInProgress: true)
    activeStoppableOperation = operation
    return true
  }

  private func finishCancellationRequest(for target: ContextualStopTarget) {
    guard var operation = activeStoppableOperation,
      operation.target.capabilityID == target.capabilityID,
      case .latched(let latch, true) = operation.state
    else { return }
    operation.state = .latched(latch, cancellationRequestInProgress: false)
    activeStoppableOperation = operation
  }

  private func updateContextualStopAudit(
    for target: ContextualStopTarget,
    outcome: String
  ) {
    guard let latch = stopDispositionLatch,
      latch.capabilityID == target.capabilityID
    else { return }
    let action =
      switch latch.intent {
      case .operatorStop: "Stop"
      case .cancelAttempt: "Cancel Attempt"
      case .shutdown: "Shutdown"
      }
    lastContextualStopAuditRecord = ContextualStopAuditRecord(
      capabilityID: target.capabilityID,
      actor: latch.actor,
      action: action,
      disposition: latch.intent,
      outcome: outcome
    )
  }

  func activateMotionGuard() async {
    if frameMode == .simulated {
      guard motionGuardActivationUnavailableReason == nil else { return }
      motionAuthorizationActionInProgress = true
      defer { motionAuthorizationActionInProgress = false }
      applySimulatedSnapshotResponse(
        await simulatedLearningRuntime.enableMotion(),
        action: "Enable simulated motion"
      )
      return
    }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard motionGuardActivationUnavailableReason == nil, let machineActions else { return }
    motionAuthorizationActionInProgress = true
    machineError = nil
    defer { motionAuthorizationActionInProgress = false }
    let outcome = await machineActions.activateMotionGuard()
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
    switch outcome {
    case .activated:
      lastMotionGuardActivationText = "activated for this controller session"
    case .refused(let refusal):
      lastMotionGuardActivationText = "refused: \(refusal.actionableDescription)"
      machineError = refusal.actionableDescription
    }
  }

  func performMotionAuthorizationAction() async {
    guard motionAuthorizationActionUnavailableReason == nil else { return }
    if motionAuthorizationEnabled {
      await deactivateMotionGuard()
    } else {
      await activateMotionGuard()
    }
  }

  private func deactivateMotionGuard() async {
    if frameMode == .simulated {
      guard motionAuthorizationActionUnavailableReason == nil else { return }
      motionAuthorizationActionInProgress = true
      defer { motionAuthorizationActionInProgress = false }
      applySimulatedSnapshotResponse(
        await simulatedLearningRuntime.disableMotion(),
        action: "Disable simulated motion"
      )
      return
    }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard motionAuthorizationActionUnavailableReason == nil, let machineActions else { return }
    motionAuthorizationActionInProgress = true
    machineError = nil
    defer { motionAuthorizationActionInProgress = false }
    await machineActions.deactivateMotionGuard()
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
    lastMotionGuardActivationText = "not activated"
  }

  func requestJog(_ direction: JogDirection) async {
    guard motionUnavailableReason == nil,
      let xStep = inputNumber(xStepText),
      let yStep = inputNumber(yStepText),
      let feed = inputNumber(feedText),
      xStep > 0,
      yStep > 0
    else { return }

    do {
      let delta: Vector2<MachineSpace>
      switch direction {
      case .xNegative: delta = try Vector2(dx: -xStep, dy: 0)
      case .xPositive: delta = try Vector2(dx: xStep, dy: 0)
      case .yNegative: delta = try Vector2(dx: 0, dy: -yStep)
      case .yPositive: delta = try Vector2(dx: 0, dy: yStep)
      }
      switch manualMotionPenState {
      case .up:
        let request = RelativeJogRequest(delta: delta, feedMMPerMinute: feed)
        await requestRelativeJog(request)
      case .down:
        let request = DrawingStrokeRequest(delta: delta, feedMMPerMinute: feed)
        await requestManualDrawingStroke(request)
      case .unknown:
        let request = RelativeJogRequest(
          delta: delta,
          feedMMPerMinute: feed,
          permitsUnknownPenStateAsPossibleInk: true
        )
        await requestRelativeJog(request)
      }
    } catch {
      machineError = actionableDescription(error)
    }
  }

  /// Routes an already typed relative-jog intent through the same presentation
  /// and runtime boundary as a button press. Callers cannot supply controller
  /// commands or bypass MachineController validation.
  @discardableResult
  func requestRelativeJog(_ request: RelativeJogRequest) async -> MotionOutcome? {
    if frameMode == .simulated {
      await requestSimulatedRelativeJog(request)
      return nil
    }
    guard let generation = beginHardwareIntent() else { return nil }
    defer { endHardwareIntent() }
    let requestUnavailableReason =
      request.permitsUnknownPenStateAsPossibleInk
      ? directManualMotionUnavailableReason
      : ordinaryRelativeJogUnavailableReason
    guard requestUnavailableReason == nil, !jogRequestInProgress,
      let machineActions
    else {
      return nil
    }

    jogRequestInProgress = true
    machineError = nil
    let fallbackOperationID = UUID()
    let motionIntent = WorkflowMotionIntent(
      deltaXMM: request.delta.dx,
      deltaYMM: request.delta.dy,
      feedMMPerMinute: request.feedMMPerMinute
    )
    let admittedOperation: RelativeJogOperation
    switch await machineActions.beginRelativeJog(request) {
    case .admitted(let operation):
      admittedOperation = operation
    case .rejected(let outcome):
      lastManualMotionWasDrawing = false
      lastManualMotionMayHaveProducedInk = request.permitsUnknownPenStateAsPossibleInk
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: fallbackOperationID,
          operation: .manualJog,
          phase: .failed,
          detail: "Manual jog admission was rejected: \(String(describing: outcome))",
          motionIntent: motionIntent,
          failureCode: .manualJogAdmissionRejected,
          recovery: .resolveNamedFailure
        )
      )
      jogRequestInProgress = false
      machineSnapshot = await machineActions.snapshot()
      return outcome
    }
    await recordWorkflowTelemetry(
      WorkflowTelemetryEvent(
        operationID: admittedOperation.id,
        operation: .manualJog,
        phase: .intentAccepted,
        detail: request.permitsUnknownPenStateAsPossibleInk
          ? "An operator-authored manual jog with unknown pen state was admitted as possible ink."
          : "An ordinary operator-authored manual jog was admitted.",
        motionIntent: motionIntent
      )
    )
    let stopTarget = ContextualStopTarget.manualJog(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(admittedOperation.id)
    )
    defer {
      jogRequestInProgress = false
      clearStoppableOperation(matching: stopTarget)
    }
    let operation = Task { await admittedOperation.outcome() }
    installStoppableOperation(target: stopTarget, owner: .motion(operation))
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    let outcome = await operation.value
    let finalSnapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return nil }
    machineSnapshot = finalSnapshot
    lastManualMotionWasDrawing = false
    lastManualMotionMayHaveProducedInk = request.permitsUnknownPenStateAsPossibleInk
    let telemetryTerminal:
      (
        phase: WorkflowTelemetryPhase, code: WorkflowTelemetryFailureCode?,
        recovery: WorkflowTelemetryRecovery
      ) =
        switch outcome {
        case .acceptedThenCompleted:
          (.completed, nil, .none)
        case .cancelled:
          (.cancelled, nil, .none)
        case .refused:
          (.failed, .manualJogRefused, .resolveNamedFailure)
        case .ambiguous:
          (.failed, .manualJogAmbiguous, .resolveNamedFailure)
        }
    await recordWorkflowTelemetry(
      WorkflowTelemetryEvent(
        operationID: admittedOperation.id,
        operation: .manualJog,
        phase: telemetryTerminal.phase,
        detail: "Manual jog settled as \(String(describing: outcome)).",
        motionIntent: motionIntent,
        failureCode: telemetryTerminal.code,
        recovery: telemetryTerminal.recovery
      )
    )
    return outcome
  }

  @discardableResult
  private func requestManualDrawingStroke(
    _ request: DrawingStrokeRequest
  ) async -> DrawingStrokeOutcome? {
    if frameMode == .simulated {
      await requestSimulatedManualMotion(
        delta: request.delta,
        draws: true
      )
      return nil
    }
    guard let generation = beginHardwareIntent() else { return nil }
    defer { endHardwareIntent() }
    guard motionUnavailableReason == nil, manualMotionPenState == .down,
      !jogRequestInProgress, let machineActions
    else { return nil }

    jogRequestInProgress = true
    machineError = nil
    let fallbackOperationID = UUID()
    let motionIntent = WorkflowMotionIntent(
      deltaXMM: request.delta.dx,
      deltaYMM: request.delta.dy,
      feedMMPerMinute: request.feedMMPerMinute
    )
    let admittedOperation: DrawingStrokeOperation
    switch await machineActions.beginDrawingStroke(request) {
    case .admitted(let operation):
      admittedOperation = operation
    case .rejected(let outcome):
      lastManualMotionWasDrawing = true
      lastManualMotionMayHaveProducedInk = true
      await recordWorkflowTelemetry(
        WorkflowTelemetryEvent(
          operationID: fallbackOperationID,
          operation: .manualDrawingStroke,
          phase: .failed,
          detail: "Manual drawing admission was rejected: \(String(describing: outcome))",
          motionIntent: motionIntent,
          failureCode: .manualDrawingAdmissionRejected,
          recovery: .resolveNamedFailure
        )
      )
      jogRequestInProgress = false
      machineSnapshot = await machineActions.snapshot()
      return outcome
    }
    await recordWorkflowTelemetry(
      WorkflowTelemetryEvent(
        operationID: admittedOperation.id,
        operation: .manualDrawingStroke,
        phase: .intentAccepted,
        detail: "An operator-authored Pen Down manual drawing stroke was admitted.",
        motionIntent: motionIntent
      )
    )
    let stopTarget = ContextualStopTarget.manualDrawingStroke(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(admittedOperation.id)
    )
    defer {
      jogRequestInProgress = false
      clearStoppableOperation(matching: stopTarget)
    }
    let operation = Task { await admittedOperation.outcome() }
    installStoppableOperation(target: stopTarget, owner: .drawing(operation))
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    let outcome = await operation.value
    let finalSnapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return nil }
    machineSnapshot = finalSnapshot
    lastManualMotionWasDrawing = true
    lastManualMotionMayHaveProducedInk = true
    let terminal:
      (
        phase: WorkflowTelemetryPhase, code: WorkflowTelemetryFailureCode?,
        recovery: WorkflowTelemetryRecovery
      ) =
        switch outcome {
        case .completed:
          (.completed, nil, .none)
        case .cancelled:
          (.cancelled, nil, .none)
        case .refused:
          (.failed, .manualDrawingRefused, .resolveNamedFailure)
        case .ambiguous:
          (.failed, .manualDrawingAmbiguous, .resolveNamedFailure)
        }
    await recordWorkflowTelemetry(
      WorkflowTelemetryEvent(
        operationID: admittedOperation.id,
        operation: .manualDrawingStroke,
        phase: terminal.phase,
        detail: "Manual drawing stroke settled as \(String(describing: outcome)).",
        motionIntent: motionIntent,
        failureCode: terminal.code,
        recovery: terminal.recovery
      )
    )
    return outcome
  }

  private func requestSimulatedRelativeJog(_ request: RelativeJogRequest) async {
    let requestUnavailableReason =
      request.permitsUnknownPenStateAsPossibleInk
      ? simulatedManualMotionUnavailableReason
      : ordinaryRelativeJogUnavailableReason
    guard requestUnavailableReason == nil, !jogRequestInProgress else { return }
    await requestSimulatedManualMotion(
      delta: request.delta,
      draws: false,
      permitsUnknownPenStateAsPossibleInk: request.permitsUnknownPenStateAsPossibleInk
    )
  }

  private func requestSimulatedManualMotion(
    delta: Vector2<MachineSpace>,
    draws: Bool,
    permitsUnknownPenStateAsPossibleInk: Bool = false
  ) async {
    guard motionUnavailableReason == nil, !jogRequestInProgress else { return }
    let vector: SimulatedLearningMotionVector
    do {
      vector = try SimulatedLearningMotionVector(
        dxMM: delta.dx,
        dyMM: delta.dy
      )
    } catch {
      simulatorLearningSummary = "Simulated manual motion is invalid: \(error)."
      return
    }
    let response =
      await
      (draws
      ? simulatedLearningRuntime.beginDrawing(delta: vector)
      : simulatedLearningRuntime.beginManualJog(
        delta: vector,
        permitsUnknownPenStateAsPossibleInk: permitsUnknownPenStateAsPossibleInk
      ))
    let operation: SimulatedLearningOperation
    switch response.result {
    case .success(let admitted):
      operation = admitted
    case .failure(let refusal):
      simulatorLearningSummary =
        "Simulated manual motion refused: \(refusal). \(response.evidenceNotice.label)"
      return
    }
    let capabilityID = ContextualStopCapabilityID()
    let owner = ContextualMotionOwnerID.simulated(operation.id)
    let target =
      draws
      ? ContextualStopTarget.manualDrawingStroke(
        capabilityID: capabilityID, operationOwner: owner)
      : ContextualStopTarget.manualJog(capabilityID: capabilityID, operationOwner: owner)
    jogRequestInProgress = true
    simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    simulatorLearningSummary =
      "Simulated manual \(draws ? "drawing" : "jog") active; use the bound Stop control. \(response.evidenceNotice.label)"
    let outcomeTask = Task<SimulatedLearningOperationOutcome?, Never> {
      [simulatedLearningRuntime, simulatedExecutionPacing] in
      let execution = await simulatedLearningRuntime.executeNaturally(
        operation.id,
        pacing: simulatedExecutionPacing
      )
      if case .success(let outcome) = execution.result {
        return outcome
      }
      return try? await simulatedLearningRuntime.waitForOutcome(of: operation.id).result.get()
    }
    installStoppableOperation(target: target, owner: .simulated(outcomeTask))
    defer {
      jogRequestInProgress = false
      clearStoppableOperation(matching: target)
    }
    _ = await outcomeTask.value
    simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
  }

  func discoverCameras() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard let cameraActions else {
      cameraError = "Native camera composition is unavailable."
      return
    }
    let snapshot = await cameraActions.discover()
    guard canCommit(generation) else { return }
    cameraSnapshot = snapshot
    updateCameraError()
  }

  func startPreferredCameraAtStartup() async {
    await discoverCameras()
    guard !hasShutdown, cameraError == nil else { return }
    let preferred =
      cameraDevices.first(where: {
        $0.name.localizedCaseInsensitiveContains("C920")
          || $0.name.localizedCaseInsensitiveContains("HD Pro Webcam")
      })
      ?? cameraDevices.onlyElement
    guard let preferred else { return }
    if selectedCameraID != preferred.id {
      await selectCamera(preferred.id)
    }
    guard !hasShutdown, cameraError == nil, selectedCameraID == preferred.id else { return }
    await startCamera()
  }

  func selectCamera(_ id: CameraDeviceID) async {
    guard currentCameraCalibrationBusyReason == nil else {
      cameraError = currentCameraCalibrationBusyReason
      return
    }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard let cameraActions, activeDiscoverySequenceID == nil,
      activeExplorationOperation == nil
    else {
      cameraError =
        "Finish the current discovery or learning action before changing camera configuration."
      return
    }
    clearAutomaticVisionPresentation()
    videoAnalysisRegionLock = nil
    invalidateCameraDependentLearningAuthority()
    cameraError = nil
    do {
      let snapshot = try await cameraActions.select(id)
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
      displayedFrame = nil
      latestLiveCameraFrame = nil
    } catch {
      let snapshot = await cameraActions.snapshot()
      guard canCommit(generation) else { return }
      cameraError = actionableDescription(error)
      cameraSnapshot = snapshot
    }
  }

  func startCamera() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard let cameraActions else { return }
    let priorCameraConfigurationID = displayedFrame?.frame.cameraConfigurationID
    if let livePenCapColor { await cameraActions.setPenCapColor(livePenCapColor) }
    let snapshot = await cameraActions.start()
    guard canCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    if let priorCameraConfigurationID,
      let currentCameraConfigurationID = displayedFrame?.frame.cameraConfigurationID,
      currentCameraConfigurationID != priorCameraConfigurationID
    {
      videoAnalysisRegionLock = nil
      await cameraActions.setSceneAnalysisRegion(nil)
      invalidateCameraDependentLearningAuthority()
    }
    updateCameraError()
    beginFrameUpdates(generation: generation)
    await reconcileAutomaticVisionAnalysis()
  }

  func stopCamera() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    guard let cameraActions else { return }
    let snapshot = await cameraActions.stop()
    guard canCommit(generation) else { return }
    cameraSnapshot = snapshot
    latestLiveCameraFrame = nil
    updateCameraError()
  }

  func restartCamera() async {

    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard activeDiscoverySequenceID == nil, activeExplorationOperation == nil else {
      cameraError = "Finish the current discovery or learning action before restarting the camera."
      return
    }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    videoAnalysisRegionLock = nil
    invalidateCameraDependentLearningAuthority()
    guard let cameraActions else { return }
    if let livePenCapColor { await cameraActions.setPenCapColor(livePenCapColor) }
    let snapshot = await cameraActions.restart()
    guard canCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    lastSceneMeasurement = nil
    updateCameraError()
    beginFrameUpdates(generation: generation)
    await reconcileAutomaticVisionAnalysis()
  }

  private func beginScopedVisionAnalysis() async -> ScopedVisionAnalysisLease? {
    guard !hasShutdown, frameMode == .live,
      case .running = cameraSnapshot?.state,
      automaticVisionAnalysisShouldRun,
      !scopedVisionAnalysisActive,
      let cameraActions
    else { return nil }
    let generation = lifetimeGeneration
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    await cameraActions.setSceneAnalysisRegion(videoAnalysisRegionLock?.region)
    let snapshot = await cameraActions.setAutomaticInspection(
      visionAnalysisCadence,
      requestedSceneFeatures
    )
    guard canCommit(generation), frameMode == .live else {
      _ = await cameraActions.setAutomaticInspection(nil, [])
      return nil
    }
    scopedVisionAnalysisActive = true
    visionError = snapshot.lastError
    visionAnalysisSnapshot = snapshot
    beginVisionUpdates(generation: generation)
    if let result = snapshot.latestResult { receiveVision(result) }
    return ScopedVisionAnalysisLease()
  }

  private func inspectWorkflowScene(
    newerThan boundary: UInt64,
    requestedFeatures: SceneFeatureSet = [.penCap],
    analysisRegion: PixelRect? = nil
  ) async throws -> LiveSceneInspection? {
    guard let cameraActions else { return nil }
    if frameMode == .live, livePenCapAppearanceSelection == nil,
      !requestedFeatures.intersection([.penCap, .armatureEnvelope]).isEmpty
    {
      throw LearningPathOperationError.requiredState(
        "Not learned — use Identify Pen Cap before LIVE exact-workflow Vision."
      )
    }
    exclusiveWorkflowVisionRequestCount += 1
    defer { exclusiveWorkflowVisionRequestCount -= 1 }
    return try await cameraActions.inspectWorkflowScene(
      boundary,
      requestedFeatures,
      analysisRegion
    )
  }

  func captureStableWorkflowCap(
    newerThan initialBoundary: UInt64
  ) async throws -> StableWorkflowCapInspection {
    var boundary = initialBoundary
    var samples: [StableWorkflowCapInspection] = []
    for _ in 0..<FixedCameraOpticalSettlingPolicy.requiredCentroidFrameCount {
      try Task.checkCancellation()
      guard
        let inspection = try await inspectWorkflowScene(
          newerThan: boundary,
          requestedFeatures: [.penCap],
          analysisRegion: nil
        ),
        inspection.displayedFrame.frame.captureNanoseconds > boundary
      else {
        throw LearningPathOperationError.freshFrameUnavailable
      }
      guard case .found(let cap, _) = inspection.measurement.penCap else {
        throw LearningPathOperationError.requiredState(
          "Pen-cap measurement refused: \(inspection.measurement.penCap.diagnosticReason)."
        )
      }
      samples.append(StableWorkflowCapInspection(inspection: inspection, cap: cap))
      boundary = inspection.displayedFrame.frame.captureNanoseconds
    }
    return try FixedCameraOpticalSettlingPolicy.newestStableCapSample(samples)
  }

  private func observeWorkflowInk(
    _ request: IsolatedInkObservationRequest
  ) async -> IsolatedInkObservationOutcome {
    guard let cameraActions else {
      preconditionFailure("Native camera composition is unavailable.")
    }
    exclusiveWorkflowVisionRequestCount += 1
    defer { exclusiveWorkflowVisionRequestCount -= 1 }
    return await cameraActions.observeIsolatedInk(request)
  }

  private func endScopedVisionAnalysis(_ lease: ScopedVisionAnalysisLease?) async {
    guard lease != nil, cameraActions != nil else { return }
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    scopedVisionAnalysisActive = false
    await reconcileAutomaticVisionAnalysis()
  }

  func switchFrameMode(_ mode: OperatorFrameMode) async {

    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard mode != frameMode || displayedFrame == nil else { return }
    if let reason = frameModeSwitchUnavailableReason {
      cameraError = reason
      return
    }
    cancelPenCapAcceptedClickContinuation()
    guard let cameraActions else { return }
    frameModeSwitchInProgress = true
    defer { frameModeSwitchInProgress = false }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    videoAnalysisRegionLock = nil
    await cameraActions.setSceneAnalysisRegion(nil)
    cameraError = nil
    switch mode {
    case .live:
      if let livePenCapColor { await cameraActions.setPenCapColor(livePenCapColor) }
      let snapshot = await cameraActions.start()
      guard canCommit(generation) else { return }
      frameMode = .live
      cameraSnapshot = snapshot
      displayedFrame = cameraSnapshot?.latestFrame
      latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
      updateCameraError()
      beginFrameUpdates(generation: generation)
      await reconcileAutomaticVisionAnalysis()
    case .simulated:
      let snapshot = await cameraActions.stop()
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
      latestLiveCameraFrame = nil
      simulatedLearningSession = LearningSessionState(
        source: .simulated,
        paperInstanceRevision: UUID(),
        paperContactPlaneRevision: simulatedLearningSession.explorationPaperContactPlaneRevision
      )
      frameMode = .simulated
      do {
        let scene = try await captureSimulatedProtocolScene()
        guard canCommit(generation) else { return }
        lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
        applySimulatedProtocolScene(scene)
        explorationPaperInstanceRevision = scene.toolPaperRevision
      } catch {
        guard canCommit(generation) else { return }
        displayedFrame = nil
        cameraError = actionableDescription(error)
      }
    }
  }

  private func refreshSimulatedContent() async {
    guard frameMode == .simulated else { return }
    do {
      let priorCameraConfigurationID = displayedFrame?.frame.cameraConfigurationID
      let scene = try await captureSimulatedProtocolScene()
      lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
      applySimulatedProtocolScene(scene)
      if let priorCameraConfigurationID,
        scene.displayedFrame.frame.cameraConfigurationID != priorCameraConfigurationID
      {
        invalidateCameraDependentLearningAuthority()
      }
    } catch {
      cameraError = actionableDescription(error)
    }
  }

  private func applySimulatedSnapshotResponse(
    _ response: SimulatedLearningResponse<SimulatedLearningSnapshot>,
    action: String
  ) {
    switch response.result {
    case .success(let snapshot):
      simulatedLearningSnapshot = snapshot
      simulatorPenState = simulatorPenState(from: snapshot.penPose)
      simulatorLearningSummary =
        "\(action) completed. \(response.evidenceNotice.label)"
    case .failure(let refusal):
      simulatorLearningSummary =
        "\(action) refused: \(refusal). \(response.evidenceNotice.label)"
    }
  }

  private func simulatorPenState(from pose: SimulatedLearningPenPose) -> PenState {
    switch pose {
    case .unknown: .unknown
    case .up: .up
    case .down: .down
    }
  }

  func stopObserving() {
    frameTask?.cancel()
    frameTask = nil
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
  }

  func shutdown() async {
    guard !hasShutdown else { return }
    hasShutdown = true
    lifetimeGeneration &+= 1
    let penCapContinuation = cancelPenCapAcceptedClickContinuation()
    stopObserving()
    let calibration = currentCameraCalibrationTask
    calibration?.cancel()
    await penCapContinuation?.value
    await announcementActions?.cancelForShutdown()
    await stopAndSettleActiveMotionForShutdown()
    await calibration?.value
    currentCameraCalibrationTask = nil
    await waitForHardwareIntentsToDrain()
    _ = await cameraActions?.stop()
    await machineActions?.disconnect()
    await clearCameraAuthority()
    await clearMachineAuthority(clearSelection: true)
  }

  private func beginFrameUpdates(generation: UInt64) {
    frameTask?.cancel()
    guard canCommit(generation), let cameraActions, frameMode == .live else { return }
    frameTask = Task { [weak self] in
      let stream = await cameraActions.frames()
      for await frame in stream {
        guard !Task.isCancelled, let self else { return }
        self.receive(frame, generation: generation)
      }
    }
  }

  private func receive(_ frame: DisplayedFrame, generation: UInt64? = nil) {
    guard !hasShutdown, frameMode == .live else { return }
    if let generation, !canCommit(generation) { return }
    guard case .live(let deviceID) = frame.source, deviceID == selectedCameraID else { return }
    latestLiveCameraFrame = frame
    if let lock = videoAnalysisRegionLock, !lock.matches(frame) {
      videoAnalysisRegionLock = nil
      Task {
        await cameraActions?.setSceneAnalysisRegion(nil)
        await reconcileAutomaticVisionAnalysis()
      }
    }

    guard case .stopped = visionAnalysisSnapshot.state else { return }
    displayedFrame = frame
  }

  private func beginVisionUpdates(generation: UInt64) {
    guard canCommit(generation), let cameraActions,
      case .running = visionAnalysisSnapshot.state
    else { return }
    visionUpdateTask?.cancel()
    visionUpdateTask = Task { [weak self] in
      let stream = await cameraActions.analysisUpdates()
      for await snapshot in stream {
        guard !Task.isCancelled, let self, self.canCommit(generation) else { return }
        let activityChanged =
          self.visionAnalysisSnapshot.activeFrameSequence != snapshot.activeFrameSequence
        let priorResultFrameID =
          self.visionAnalysisSnapshot.latestResult?.displayedFrame.frame.id
        let resultChanged =
          priorResultFrameID != snapshot.latestResult?.displayedFrame.frame.id
        self.visionAnalysisSnapshot = snapshot
        self.visionError = snapshot.lastError
        if activityChanged || resultChanged {
          let cameraSnapshot = await cameraActions.snapshot()
          guard !Task.isCancelled, self.canCommit(generation) else { return }
          self.cameraSnapshot = cameraSnapshot
        }
        if resultChanged, let result = snapshot.latestResult { self.receiveVision(result) }
      }
    }
  }

  private func defaultInkRegion(for frame: StampedFrame) -> PixelRect {
    let width = max(1, min(180, frame.width / 3))
    let height = max(1, min(120, frame.height / 3))
    return PixelRect(
      x: max(0, (frame.width - width) / 2),
      y: max(0, (frame.height - height) / 2),
      width: width,
      height: height
    )
  }

  private func acceptInkObservation(
    _ observation: IsolatedInkObservation,
    displayedFrame: DisplayedFrame
  ) {
    lastInkObservation = observation
    overlayResultChannels.publishWorkflow(
      OverlayChannelResult(displayedFrame: displayedFrame, overlays: observation.overlays),
      source: frameMode,
      owner: .observedDrawingTrial
    )
    explorationInkStatus =
      observation.residual == nil
      ? "new ink observed; absolute residual unavailable without a current-session projection"
      : "new ink observed with tip-model-projected residual"
  }

  private func answerDiscoverySequence(
    _ choice: OperatorChoice,
    for sequenceID: DiscoverySequenceID
  ) async {
    guard let transaction = discoveryTransactions[sequenceID],
      transaction.state == .active,
      let step = transaction.currentStep,
      let question = step.question,
      question.choices.contains(choice)
    else { return }

    guard question.advancingChoices.contains(choice) else {
      boundaryTeachingResultText = question.negativeAcknowledgement
      _ = await announceAdvisory(question.negativeAcknowledgement)
      if case .awaitPhysicalPenConfirmation(.down, _) = step.action {
        _ = await announceAdvisory("Raising the pen.")
        if frameMode == .simulated {
          simulatorPenState = .up
        } else {
          await requestPenActuation(.raise)
        }
        await failDiscovery(sequenceID, failure: .refused(question.negativeAcknowledgement))
      }
      return
    }

    switch step.action {
    case .awaitOperatorChoice:
      guard recordDiscovery(.operatorChoiceAccepted(choice), for: sequenceID) else { return }
    case .awaitPhysicalPenConfirmation(let state, _):
      await awaitPendingPenSetpointActuation()
      let command: PenCommand = state == .down ? .lower : .raise
      let setpoint = effectivePenActuationProfile.value(for: command)
      let execution = activeLearningSession.lastPenExecutionByCommand[command].flatMap {
        $0.profile.value(for: command) == setpoint ? $0 : nil
      }
      let position = try? currentMachinePosition()
      let timestamp =
        execution?.timestamp
        ?? RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
      if state == .down {
        activeLearningSession.pendingPenDownPositions.append(position)
        activeLearningSession.pendingPenDownSpindleValues.append(setpoint)
        activeLearningSession.pendingPenDownControllerOutcomes.append(execution?.outcome)
        activeLearningSession.pendingPenDownTimestamps.append(timestamp)
      } else {
        activeLearningSession.pendingPenUpPositions.append(position)
        activeLearningSession.pendingPenUpSpindleValues.append(setpoint)
        activeLearningSession.pendingPenUpControllerOutcomes.append(execution?.outcome)
        activeLearningSession.pendingPenUpTimestamps.append(timestamp)
      }
      guard
        recordDiscovery(
          .physicalPenConfirmed(
            state,
            response: choice,
            operatorSummary: position.map {
              String(
                format: "Operator chose Next at S%d and MPos X %.3f Y %.3f.",
                setpoint,
                $0.point.x,
                $0.point.y
              )
            } ?? "Operator chose Next at S\(setpoint); current MPos was unavailable."
          ),
          for: sequenceID
        )
      else { return }
      currentPenActuationProfile = effectivePenActuationProfile
      activeLearningSession.penActuationDraft = currentPenActuationProfile
    default:
      return
    }
    await advanceDiscoverySequence(sequenceID)
  }

  private func executeBoundaryMotion(_ direction: JogDirection) async {
    if frameMode == .simulated {
      await executeSimulatedBoundaryMotion(direction)
      return
    }
    guard let request = makeBoundaryMotionRequest(direction),
      let machineActions,
      let sequenceID = activeDiscoverySequenceID,
      let transactionID = discoveryTransactions[sequenceID]?.id,
      let attemptID = activeExerciseAttemptID
    else {
      boundaryTeachingState = .idle
      return
    }

    let discoveryDirection = boundaryDirection(from: direction)
    machineSnapshot = await machineActions.snapshot()
    // The controller owner renews only the same finite 50 mm segment. Camera and
    // Vision do not advise Boundary direction, distance, Stop, or acceptance.
    let admittedOperation: BoundaryMotionOperation
    switch await machineActions.beginBoundaryMotion(request, nil) {
    case .admitted(let operation):
      admittedOperation = operation
    case .rejected(let outcome):
      if case .needsAttention(_, let terminal) = outcome {
        await failDiscovery(sequenceID, failure: workflowFailure(for: terminal))
      } else {
        await failDiscovery(sequenceID, failure: .refused("Boundary owner admission was rejected."))
      }
      return
    }
    guard admittedOperation.ownerID == request.ownerID else {
      await failDiscovery(
        sequenceID,
        failure: .failed("Boundary owner admission returned a mismatched owner identity."))
      return
    }
    let stopTarget = ContextualStopTarget.pairedBoundary(
      capabilityID: ContextualStopCapabilityID(),
      transactionID: transactionID,
      operationOwner: .liveBoundary(request.ownerID),
      attemptID: attemptID,
      direction: discoveryDirection
    )
    guard let boundaryMotionTask else {
      await failDiscovery(
        sequenceID,
        failure: WorkflowFailure(
          kind: .failed,
          detail: "Boundary owner admission lost its coordinating task.",
          recovery: .resolveNamedFailure
        )
      )
      return
    }
    installStoppableOperation(target: stopTarget, owner: .boundary(boundaryMotionTask))
    defer { clearStoppableOperation(matching: stopTarget) }
    pendingBoundaryOwnerIDs[attemptID] = request.ownerID
    pendingBoundaryStopCapabilities[attemptID] = stopTarget.capabilityID
    appendBoundaryActivity(
      actor: .controller,
      direction: discoveryDirection,
      phase: .admission,
      disposition: .inProgress,
      attemptID: attemptID,
      operationOwnerID: .liveBoundary(request.ownerID),
      stopCapabilityID: stopTarget.capabilityID,
      detail: .message(
        "The logical Boundary owner was admitted under current direct controller facts.")
    )
    machineSnapshot = await machineActions.snapshot()
    boundaryTeachingState = .ownerActive(direction)
    boundaryTeachingResultText =
      "Boundary owner active toward \(direction.shortLabel). Stop is available during admission and motion."
    guard
      recordDiscovery(
        .boundaryJogStarted(
          discoveryDirection,
          controllerSummary:
            "Logical Boundary Discovery owner started; direct controller admission remains runtime-owned."
        ),
        for: sequenceID
      )
    else { return }
    await advanceDiscoverySequence(sequenceID)

    let outcome = await admittedOperation.outcome()
    machineSnapshot = await machineActions.snapshot()
    guard !hasShutdown else { return }

    switch outcome {
    case .settled(let settlement)
    where settlement.ownerID == request.ownerID
      && settlement.intent == .operatorStop
      && stopDispositionLatch?.capabilityID == stopTarget.capabilityID
      && stopDispositionLatch?.intent == .operatorStop:
      let finalPosition = settlement.finalPosition
      if boundaryAtomicCommitFailurePoints.contains(.settlement) {
        await failDiscovery(
          sequenceID,
          failure: .failed("Injected Boundary settlement failure after the owner returned.")
        )
        return
      }
      pendingBoundaryFinalPositions[attemptID] = finalPosition
      appendBoundaryActivity(
        actor: .controller,
        direction: discoveryDirection,
        phase: .settling,
        disposition: .succeeded,
        attemptID: attemptID,
        operationOwnerID: .liveBoundary(request.ownerID),
        stopCapabilityID: stopTarget.capabilityID,
        finalPosition: finalPosition,
        detail: .message("Operator Stop settled at Idle with final Controller MPos.")
      )
      boundaryTeachingResultText = String(
        format: "%@ observed at final X %.3f Y %.3f after Stop and Idle.",
        direction.shortLabel,
        finalPosition.point.x,
        finalPosition.point.y
      )
      guard
        recordDiscovery(
          .boundaryJogCancelled(
            boundaryDirection(from: direction),
            finalPosition: finalPosition,
            controllerSummary: boundaryTeachingResultText
          ),
          for: sequenceID
        )
      else { return }
      await advanceDiscoverySequence(sequenceID)

    case .settled(let settlement):
      if settlement.ownerID != request.ownerID
        || stopDispositionLatch?.capabilityID != stopTarget.capabilityID
        || stopDispositionLatch?.intent != settlement.intent
      {
        await failDiscovery(
          sequenceID,
          failure: .failed(
            "Boundary settlement owner/disposition did not match the first admitted operator action."
          )
        )
        return
      }
      if var transaction = discoveryTransactions[sequenceID] {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
      }
      boundaryTeachingResultText =
        settlement.intent == .shutdown
        ? "Boundary Discovery settled during shutdown; no boundary evidence was recorded."
        : "Boundary Discovery was cancelled; no boundary evidence was recorded."
      let acceptedFallback = boundarySideAggregates[discoveryDirection]
      let repeatAttempt =
        activeExerciseAttemptMode == .replacement
        || activeExerciseAttemptMode == .additional
      recordDiscoveryAttempt(sequenceID: sequenceID, disposition: .cancelled)
      appendBoundaryActivity(
        actor: .operatorActor,
        direction: discoveryDirection,
        phase: .recovery,
        disposition: .cancelled,
        attemptID: attemptID,
        operationOwnerID: .liveBoundary(request.ownerID),
        stopCapabilityID: stopTarget.capabilityID,
        finalPosition: settlement.finalPosition,
        retainedRevisionIDs: acceptedFallback.map { [$0.revisionID] } ?? [],
        detail: .message("The owner settled after Cancel; no Boundary sample was accepted."),
        recovery: acceptedFallback != nil
          ? .continueWithAcceptedFallback(discoveryDirection)
          : .restartNormal(discoveryDirection),
        acceptedFallbackRemainsCurrent: acceptedFallback != nil
      )
      finishActiveExerciseAttempt(disposition: .cancelled)
      if settlement.intent == .cancelAttempt {
        restartableExerciseItemID =
          repeatAttempt && acceptedFallback != nil
          ? nil : .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      }

    case .needsAttention(_, let terminal):
      await failDiscovery(sequenceID, failure: workflowFailure(for: terminal))
    }
    boundaryTeachingState = .idle
  }

  private func executeSimulatedBoundaryMotion(_ direction: JogDirection) async {
    guard let sequenceID = activeDiscoverySequenceID,
      let transactionID = discoveryTransactions[sequenceID]?.id,
      let attemptID = activeExerciseAttemptID
    else {
      boundaryTeachingState = .idle
      return
    }
    let discoveryDirection = boundaryDirection(from: direction)
    let response = await simulatedLearningRuntime.beginBoundary(
      direction: discoveryDirection,
      finiteSegmentLengthMM: MotionPriors.boundaryWireSegmentMM
    )
    let operation: SimulatedLearningOperation
    switch response.result {
    case .success(let admitted):
      operation = admitted
    case .failure(let refusal):
      await failDiscovery(
        sequenceID,
        failure: .refused("Simulated Boundary owner admission was refused: \(refusal).")
      )
      return
    }
    let stopTarget = ContextualStopTarget.pairedBoundary(
      capabilityID: ContextualStopCapabilityID(),
      transactionID: transactionID,
      operationOwner: .simulated(operation.id),
      attemptID: attemptID,
      direction: discoveryDirection
    )
    let outcomeTask = Task<SimulatedLearningOperationOutcome?, Never> {
      [simulatedLearningRuntime, simulatedExecutionPacing] in
      let execution = await simulatedLearningRuntime.executeBoundaryCooperatively(
        operation.id,
        pacing: simulatedExecutionPacing
      )
      if case .success(let outcome) = execution.result { return outcome }
      return try? await simulatedLearningRuntime.waitForOutcome(of: operation.id).result.get()
    }
    guard let boundaryMotionTask else {
      await failDiscovery(
        sequenceID,
        failure: .failed("Simulated Boundary owner lost its coordinating task.")
      )
      return
    }
    installStoppableOperation(target: stopTarget, owner: .boundary(boundaryMotionTask))
    defer { clearStoppableOperation(matching: stopTarget) }
    pendingBoundaryOwnerIDs[attemptID] = BoundaryMotionOwnerID()
    pendingBoundaryStopCapabilities[attemptID] = stopTarget.capabilityID
    boundaryTeachingState = .ownerActive(direction)
    boundaryTeachingResultText =
      "Simulated Boundary owner active toward \(direction.shortLabel). \(response.evidenceNotice.label)"
    guard
      recordDiscovery(
        .boundaryJogStarted(
          discoveryDirection,
          controllerSummary:
            "Simulated logical Boundary owner \(operation.id.sequence) started. \(response.evidenceNotice.label)"
        ),
        for: sequenceID
      )
    else { return }
    await advanceDiscoverySequence(sequenceID)

    guard let outcome = await outcomeTask.value else {
      await failDiscovery(
        sequenceID,
        failure: WorkflowFailure(
          kind: .failed,
          detail: "The simulated Boundary owner lost its outcome.",
          recovery: .resolveNamedFailure
        )
      )
      return
    }
    simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    guard !hasShutdown else { return }
    switch outcome.disposition {
    case .stopped
    where stopDispositionLatch?.capabilityID == stopTarget.capabilityID
      && stopDispositionLatch?.intent == .operatorStop:
      do {
        let finalPosition = try MachinePosition(
          x: outcome.finalMPos.xMM,
          y: outcome.finalMPos.yMM
        )
        if boundaryAtomicCommitFailurePoints.contains(.settlement) {
          await failDiscovery(
            sequenceID,
            failure: .failed("Injected simulated Boundary settlement failure.")
          )
          return
        }
        pendingBoundaryFinalPositions[attemptID] = finalPosition
        boundaryTeachingResultText =
          "Simulated Stop settled at X \(outcome.finalMPos.xMM) Y \(outcome.finalMPos.yMM). \(outcome.evidenceNotice.label)"
        guard
          recordDiscovery(
            .boundaryJogCancelled(
              discoveryDirection,
              finalPosition: finalPosition,
              controllerSummary: boundaryTeachingResultText
            ),
            for: sequenceID
          )
        else { return }
        await advanceDiscoverySequence(sequenceID)
      } catch {
        await failDiscovery(
          sequenceID, failure: .failed("Simulated final MPos was invalid: \(error)."))
      }

    case .cancelled:
      if var transaction = discoveryTransactions[sequenceID] {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
      }
      let acceptedFallback = boundarySideAggregates[discoveryDirection]
      let repeatAttempt =
        activeExerciseAttemptMode == .replacement
        || activeExerciseAttemptMode == .additional
      recordDiscoveryAttempt(sequenceID: sequenceID, disposition: .cancelled)
      finishActiveExerciseAttempt(disposition: .cancelled)
      restartableExerciseItemID =
        repeatAttempt && acceptedFallback != nil
        ? nil : .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      boundaryTeachingResultText =
        "Simulated Boundary attempt cancelled. \(outcome.evidenceNotice.label)"

    case .failed where simulatedLearningSnapshot?.stickyAmbiguity != nil:
      await failDiscovery(
        sequenceID,
        failure: .ambiguous(
          "The simulated Boundary owner lost attributable segment completion."
        )
      )

    case .stopped, .naturallyCompleted, .failed, .shutdown:
      await failDiscovery(
        sequenceID,
        failure: .failed(
          "Simulated Boundary settlement did not match the first admitted operator disposition."
        )
      )
    }
    boundaryTeachingState = .idle
  }

  private func makeBoundaryMotionRequest(_ direction: JogDirection) -> BoundaryMotionRequest? {
    guard boundaryTeachingState == .awaitingOwnerAdmission(direction),
      directCarriageMotionUnavailableReason == nil
    else {
      boundaryTeachingResultText =
        "Boundary motion cannot start: \(directCarriageMotionUnavailableReason ?? "current direct controller facts are unavailable")."
      return nil
    }
    do {
      let delta: Vector2<MachineSpace>
      switch direction {
      case .xNegative: delta = try Vector2(dx: -MotionPriors.boundaryWireSegmentMM, dy: 0)
      case .xPositive: delta = try Vector2(dx: MotionPriors.boundaryWireSegmentMM, dy: 0)
      case .yNegative: delta = try Vector2(dx: 0, dy: -MotionPriors.boundaryWireSegmentMM)
      case .yPositive: delta = try Vector2(dx: 0, dy: MotionPriors.boundaryWireSegmentMM)
      }
      let selection = boundaryTravelFeedSelection()
      lastTravelFeedSelection = selection
      return BoundaryMotionRequest(
        direction: boundaryDirection(from: direction),
        segment: RelativeJogRequest(
          delta: delta,
          feedMMPerMinute: selection.requestedFeedMMPerMinute
        ),
        renewalBounds: .fixed(MotionPriors.boundaryWireSegmentMM)
      )
    } catch {
      boundaryTeachingResultText = "Boundary motion request is invalid; no motion was sent."
      return nil
    }
  }

  private func startExercise(
    _ ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) async {
    guard activeExerciseAttemptOwnerID == nil else { return }
    restartableExerciseItemID = nil
    switch ownerID {
    case .humanGuidedDiscovery(.penInteraction):
      await beginPenInteraction(mode: mode)
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      await beginPairedBoundarySide(selectedBoundaryDirection, mode: mode)
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
    case .observedDrawingTrial(.chooseIsolatedLinePlan):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      await runObservedDrawingTrial()
    case .observedDrawingTrial:
      break
    case .stage:
      break
    }
  }

  private func cancelExerciseAttempt(_ ownerID: LearningPathItemID) async {
    guard activeExerciseAttemptOwnerID == ownerID else { return }
    let isPreSequencePenInteraction =
      ownerID == .humanGuidedDiscovery(.penInteraction)
      && activeDiscoverySequenceID == nil
      && (penCapAppearanceSelectionContext != nil
        || penCapAcceptedClickContinuationTask != nil)
    var penCapContinuation: Task<Void, Never>?
    if ownerID == .humanGuidedDiscovery(.penInteraction) {
      penCapContinuation = cancelPenCapAcceptedClickContinuation()
    }
    let boundaryRepeatWithFallback =
      ownerID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      && (activeExerciseAttemptMode == .replacement || activeExerciseAttemptMode == .additional)
      && boundarySideAggregates[selectedBoundaryDirection] != nil
    if let sequenceID = activeDiscoverySequenceID,
      var transaction = discoveryTransactions[sequenceID]
    {
      if let target = activeStopTarget,
        !latchContextualStopDisposition(
          for: target,
          intent: .cancelAttempt,
          actor: "Operator",
          action: "Cancel Attempt"
        )
      {
        return
      }
      transaction.cancel()
      discoveryTransactions[sequenceID] = transaction
      if let target = activeStopTarget {
        boundaryTeachingState = .cancelling(
          jogDirection(for: sequenceID) ?? jogDirection(from: selectedBoundaryDirection)
        )
        let owner = boundaryMotionTask
        await requestSingleJogCancel(for: target, intent: .cancelAttempt)
        await owner?.value
      }
      recordDiscoveryAttempt(sequenceID: sequenceID, disposition: .cancelled)
    } else if isPreSequencePenInteraction {
      recordDiscoveryAttempt(sequenceID: .penInteraction, disposition: .cancelled)
    } else if let target = activeStopTarget,
      !isManualStopTarget(target)
    {
      guard
        latchContextualStopDisposition(
          for: target,
          intent: .cancelAttempt,
          actor: "Operator",
          action: "Cancel Attempt"
        )
      else { return }
      if let operation = activeStoppableOperation {
        await cancelAndSettleStoppableOperation(operation, intent: .cancelAttempt)
      }
    }
    if ownerID == .observedDrawingTrial(.chooseIsolatedLinePlan),
      observedDrawingTrialStep == .compareIntendedAndObservedGeometry
    {
      recordComparisonAttempt(assessment: nil, disposition: .cancelled)
    }
    finishActiveExerciseAttempt(disposition: .cancelled)
    restartableExerciseItemID = boundaryRepeatWithFallback ? nil : ownerID
    await penCapContinuation?.value
  }

  private func beginExerciseAttempt(
    ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) {
    _ = activeLearningSession.exerciseAttempt.begin(ownerID: ownerID, mode: mode)
  }

  private func finishActiveExerciseAttempt(disposition: ExerciseAttemptDisposition) {
    if activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction) {
      cancelPenCapAcceptedClickContinuation()
      activeLearningSession.penActuationDraft = nil
      pendingPenSetpointCommand = nil
      penCapAppearanceSelectionContext = nil
    }
    if activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      let attemptID = activeExerciseAttemptID
    {
      pendingBoundaryFinalPositions.removeValue(forKey: attemptID)
      pendingBoundaryOwnerIDs.removeValue(forKey: attemptID)
      pendingBoundaryStopCapabilities.removeValue(forKey: attemptID)
    }
    if activeExerciseAttemptOwnerID
      == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    {
      activeLearningSession.toolContactSelection.clear()
    }
    activeLearningSession.exerciseAttempt.finish()
  }

  private var penInteractionSequenceUnavailableReason: String? {
    if frameMode == .simulated {
      if !controllerSessionEstablished { return "Connect the learning simulator first." }
      if !motionAuthorizationEnabled { return "Enable simulated Motion first." }
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      return nil
    }
    if !motionGuardIsActive { return "Connect the plotter and Enable Motion first." }
    return penUnavailableReason(for: .lower)
  }

  private func recordAttempt<Value: Hashable & Sendable>(
    _ attempt: ExerciseAttempt<Value>,
    in history: inout ExerciseAttemptHistory<Value>,
    replacingAttemptID: ExerciseAttemptID?
  ) throws {
    if activeExerciseAttemptMode == .replacement {
      guard let replacingAttemptID else {
        throw LearningPathOperationError.requiredState(
          "The accepted attempt selected for replacement is unavailable."
        )
      }
      try history.recordReplacement(attempt, replacing: replacingAttemptID)
    } else {
      try history.record(attempt)
    }
  }

  /// Stages replacement across compatibility-bound histories without pooling.
  /// An incompatible successful Redo supersedes the accepted source sample and
  /// records the new value in its own history; an unsuccessful Redo records only
  /// excluded provenance and leaves the old accepted sample included.
  private func recordAttempt<Value: Hashable & Sendable>(
    _ attempt: ExerciseAttempt<Value>,
    in histories: inout [AttemptCompatibility: ExerciseAttemptHistory<Value>],
    replacingAttemptID: ExerciseAttemptID?
  ) throws {
    var targetHistory =
      try histories[attempt.compatibility]
      ?? ExerciseAttemptHistory(compatibility: attempt.compatibility)
    guard activeExerciseAttemptMode == .replacement else {
      try targetHistory.record(attempt)
      histories[attempt.compatibility] = targetHistory
      return
    }
    guard let replacingAttemptID else {
      throw LearningPathOperationError.requiredState(
        "The accepted attempt selected for replacement is unavailable."
      )
    }

    if targetHistory.records.contains(where: { $0.attempt.id == replacingAttemptID }) {
      try targetHistory.recordReplacement(attempt, replacing: replacingAttemptID)
      histories[attempt.compatibility] = targetHistory
      return
    }

    guard
      let sourceCompatibility = histories.first(where: { _, history in
        history.records.contains(where: { $0.attempt.id == replacingAttemptID })
      })?.key
    else {
      throw ExerciseAttemptError.replacementTargetNotFound(replacingAttemptID)
    }
    try targetHistory.record(attempt)
    if attempt.disposition.contributesSuccessfulValue {
      var sourceHistory = histories[sourceCompatibility]!
      try sourceHistory.supersedeIncludedAttempt(replacingAttemptID, by: attempt.id)
      histories[sourceCompatibility] = sourceHistory
    }
    histories[attempt.compatibility] = targetHistory
  }

  private func commitSuccessfulDiscoveryAttempt(_ sequenceID: DiscoverySequenceID) {
    guard let attemptID = activeExerciseAttemptID else { return }
    do {
      switch sequenceID {
      case .penInteraction:
        let sequence = acceptedAttemptSequence &+ 1
        var history = penAttemptHistory
        let replacingAttemptID = learningArtifactGraph.currentRevision(for: .penInteraction)?
          .attemptID
        try recordAttempt(
          ExerciseAttempt(
            id: attemptID,
            disposition: .succeeded,
            compatibility: history.compatibility,
            acceptedSequence: sequence,
            value: PenInteractionAttemptEvidence(
              actuationProfile: currentPenActuationProfile,
              confirmedUpPositions: activeLearningSession.pendingPenUpPositions,
              confirmedUpSpindleValues: activeLearningSession.pendingPenUpSpindleValues,
              confirmedUpControllerOutcomes:
                activeLearningSession.pendingPenUpControllerOutcomes,
              confirmedUpTimestamps: activeLearningSession.pendingPenUpTimestamps,
              confirmedDownPositions: activeLearningSession.pendingPenDownPositions,
              confirmedDownSpindleValues: activeLearningSession.pendingPenDownSpindleValues,
              confirmedDownControllerOutcomes:
                activeLearningSession.pendingPenDownControllerOutcomes,
              confirmedDownTimestamps: activeLearningSession.pendingPenDownTimestamps
            )
          ),
          in: &history,
          replacingAttemptID: replacingAttemptID
        )
        var graph = learningArtifactGraph
        let commit = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .penInteraction,
            attemptID: attemptID,
            disposition: .succeeded
          )
        )
        penAttemptHistory = history
        acceptedAttemptSequence = sequence
        learningArtifactGraph = graph
        applyArtifactInvalidations(commit.invalidatedRevisionIDs)
        persistAcceptedLearningPathCheckpoint(clearTip: true, clearStageFour: true)

      case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
        // Boundary sequences commit their complete staged authority directly in
        // `commitBoundaryObservation`; reaching this callback would split the
        // transaction from its accepted aggregate.
        return
      }
      discoveryError = nil
      restartableExerciseItemID = nil
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      recordDiscoveryAttempt(
        sequenceID: sequenceID,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      discoveryError = "Accepted discovery artifact could not commit: \(error)"
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
    }
  }

  private func recordDiscoveryAttempt(
    sequenceID: DiscoverySequenceID,
    disposition: ExerciseAttemptDisposition
  ) {
    guard let attemptID = activeExerciseAttemptID else { return }
    do {
      if sequenceID == .penInteraction {
        let sequence = acceptedAttemptSequence &+ 1
        var history = penAttemptHistory
        let replacingAttemptID = learningArtifactGraph.currentRevision(for: .penInteraction)?
          .attemptID
        try recordAttempt(
          ExerciseAttempt(
            id: attemptID,
            disposition: disposition,
            compatibility: history.compatibility,
            acceptedSequence: sequence,
            value: nil
          ),
          in: &history,
          replacingAttemptID: replacingAttemptID
        )
        penAttemptHistory = history
        acceptedAttemptSequence = sequence
      } else if let direction = boundaryDirection(for: sequenceID) {
        let compatibility = boundaryCompatibility(direction)
        var histories = boundaryAttemptHistories[direction] ?? [:]
        var history =
          try histories[compatibility]
          ?? ExerciseAttemptHistory(compatibility: compatibility)
        let sequence = acceptedAttemptSequence &+ 1
        let attempt = try ExerciseAttempt<BoundarySideAttemptEvidence>(
          id: attemptID,
          disposition: disposition,
          compatibility: compatibility,
          acceptedSequence: sequence,
          value: nil
        )
        if activeExerciseAttemptMode == .replacement, !history.includedSuccessfulAttempts.isEmpty {
          _ = try history.recordWholeIncludedSetReplacement(attempt)
        } else {
          try history.record(attempt)
        }
        histories[compatibility] = history
        boundaryAttemptHistories[direction] = histories
        acceptedAttemptSequence = sequence
      }
    } catch {
      discoveryError = "Attempt provenance could not be recorded: \(error)"
    }
  }

  private func boundaryCompatibility(_ direction: BoundaryDirection) -> AttemptCompatibility {
    BoundaryNumericCompatibility(
      direction: direction,
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      numericEstimatorRevision: "boundary-machine-coordinate-v1"
    ).attemptCompatibility
  }

  func boundaryAggregate(
    for direction: BoundaryDirection,
    compatibility: AttemptCompatibility
  ) -> BoundarySideAggregate? {
    guard let history = boundaryAttemptHistories[direction]?[compatibility] else { return nil }
    guard let current = boundarySideAggregates[direction],
      current.numericCompatibility.attemptCompatibility == compatibility
    else { return nil }
    return try? BoundarySideAggregate(
      direction: direction,
      revisionID: current.revisionID,
      history: history
    )
  }

  var currentPenInteractionAggregate: LatestStateAggregate<PenInteractionAttemptEvidence>? {
    try? LatestStateAggregate(history: penAttemptHistory)
  }

  private func recordComparisonAttempt(
    assessment: DrawingTrialAssessment?,
    disposition: ExerciseAttemptDisposition
  ) {
    guard let attemptID = activeExerciseAttemptID else { return }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: explorationPostLineFrame?.frame.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: currentDrawingTrialGroup,
      algorithmRevision: "typed-trial-comparison-v1"
    )
    do {
      var histories = comparisonAttemptHistories
      let sequence = acceptedAttemptSequence &+ 1
      let replacingAttemptID = learningArtifactGraph.currentRevision(
        for: .comparison(currentDrawingTrialGroup)
      )?.attemptID
      try recordAttempt(
        ExerciseAttempt(
          id: attemptID,
          disposition: disposition,
          compatibility: compatibility,
          acceptedSequence: sequence,
          value: assessment
        ),
        in: &histories,
        replacingAttemptID: replacingAttemptID
      )
      comparisonAttemptHistories = histories
      acceptedAttemptSequence = sequence
    } catch {
      explorationError = "Comparison attempt provenance could not be recorded: \(error)"
    }
  }

  private func commitDrawingArtifact(for step: ObservedDrawingTrialStep) throws {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active typed exercise attempt.")
    }
    let group = currentDrawingTrialGroup
    var graph = learningArtifactGraph
    func required(_ kind: LearningArtifactKind) throws -> LearningArtifactRevisionID {
      guard let id = graph.currentRevision(for: kind)?.id else {
        throw LearningPathOperationError.requiredState("Required artifact \(kind) is unavailable.")
      }
      return id
    }
    let kind: LearningArtifactKind
    let dependencies: Set<LearningArtifactRevisionID>
    switch step {
    case .chooseIsolatedLinePlan:
      kind = .linePlan(group)
      dependencies = [try required(.tipCameraRegistration)]
    case .captureLocalPreLineBaseline:
      kind = .localPreLineBaseline(group)
      dependencies = [try required(.tipCameraRegistration)]
    case .moveToLineStart:
      return
    case .drawIsolatedLine:
      kind = .lineExecution(group)
      dependencies = [try required(.linePlan(group))]
    case .revealAndObserveNewInk:
      kind = .postLineFrame(group)
      dependencies = [
        try required(.lineExecution(group)),
        try required(.localPreLineBaseline(group)),
        try required(.tipCameraRegistration),
      ]
    case .compareIntendedAndObservedGeometry:
      kind = .comparison(group)
      dependencies = [
        try required(.inkObservation(group)), try required(.residual(group)),
      ]
    }
    let primary = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: kind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: dependencies
      )
    )
    var invalidated = primary.invalidatedRevisionIDs

    if step == .revealAndObserveNewInk {
      let baseline = try required(.localPreLineBaseline(group))
      let line = try required(.lineExecution(group))
      let post = try required(.postLineFrame(group))
      let tip = try required(.tipCameraRegistration)
      let ink = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .inkObservation(group),
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [baseline, line, post, tip]
        )
      )
      let residual = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .residual(group),
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [ink.currentRevision.id]
        )
      )
      invalidated.formUnion(ink.invalidatedRevisionIDs)
      invalidated.formUnion(residual.invalidatedRevisionIDs)
    }
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidated)
  }

  private func drawingTrialPayloadSnapshot() -> DrawingTrialState {
    activeLearningSession.drawingTrial
  }

  private func restoreDrawingTrialPayload(_ snapshot: DrawingTrialState) {
    activeLearningSession.drawingTrial = snapshot
  }

  private func advanceDrawingTrialAfterSuccess(_ step: ObservedDrawingTrialStep) {
    switch step {
    case .chooseIsolatedLinePlan: advanceDrawingTrial(to: .captureLocalPreLineBaseline)
    case .captureLocalPreLineBaseline: advanceDrawingTrial(to: .moveToLineStart)
    case .moveToLineStart: advanceDrawingTrial(to: .drawIsolatedLine)
    case .drawIsolatedLine: advanceDrawingTrial(to: .revealAndObserveNewInk)
    case .revealAndObserveNewInk:
      advanceDrawingTrial(to: .compareIntendedAndObservedGeometry)
    case .compareIntendedAndObservedGeometry:
      break
    }
  }

  private func commitComparisonAttemptAndArtifact(
    _ assessment: DrawingTrialAssessment
  ) throws {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active typed exercise attempt.")
    }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: explorationPostLineFrame?.frame.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: currentDrawingTrialGroup,
      algorithmRevision: "typed-trial-comparison-v1"
    )
    var histories = comparisonAttemptHistories
    let sequence = acceptedAttemptSequence &+ 1
    let comparisonKind = LearningArtifactKind.comparison(currentDrawingTrialGroup)
    let replacingAttemptID = learningArtifactGraph.currentRevision(for: comparisonKind)?.attemptID
    try recordAttempt(
      ExerciseAttempt(
        id: attemptID,
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: sequence,
        value: assessment
      ),
      in: &histories,
      replacingAttemptID: replacingAttemptID
    )

    var graph = learningArtifactGraph
    guard let ink = graph.currentRevision(for: .inkObservation(currentDrawingTrialGroup))?.id,
      let residual = graph.currentRevision(for: .residual(currentDrawingTrialGroup))?.id
    else {
      throw LearningPathOperationError.requiredState(
        "Observed ink and residual artifacts are required.")
    }
    let commit = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: comparisonKind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [ink, residual]
      )
    )
    comparisonAttemptHistories = histories
    acceptedAttemptSequence = sequence
    learningArtifactGraph = graph
    applyArtifactInvalidations(commit.invalidatedRevisionIDs)
  }

  private func applyArtifactInvalidations(_ revisionIDs: Set<LearningArtifactRevisionID>) {
    for revisionID in revisionIDs {
      guard let revision = learningArtifactGraph.revision(id: revisionID) else { continue }
      switch revision.kind {
      case .penInteraction, .boundarySideAggregate:
        break
      case .estimatedMachineCenter:
        estimatedMachineCenter = nil
        learnedLocalCoordinateFrame = nil
        centerArrivalPosition = nil
        centerArrivalRetryRequired = false
      case .centerArrival:
        centerArrivalPosition = nil
        centerArrivalRetryRequired = false
      case .machineCameraRegistration:
        machineCameraRegistration = nil
      case .toolContactObservation:
        break
      case .tipCameraRegistration:
        tipCameraRegistration = nil
        proposedTipCameraRegistration = nil
        drawingTrialTipRegistrationRevisionID = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .chooseIsolatedLinePlan)
      case .localPreLineBaseline:
        localPreLineBaseline = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .captureLocalPreLineBaseline)
      case .linePlan:
        drawingTrialLineStart = nil
        drawingTrialLineEnd = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .chooseIsolatedLinePlan)
      case .lineExecution:
        drawingTrialStrokeEvidence = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .drawIsolatedLine)
      case .postLineFrame:
        explorationPostLineFrame = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .revealAndObserveNewInk)
      case .inkObservation, .residual:
        lastInkObservation = nil
        drawingTrialAssessment = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .revealAndObserveNewInk)
      case .comparison:
        drawingTrialAssessment = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .compareIntendedAndObservedGeometry)
      }
    }
  }

  private func setObservedDrawingTrialStepEarlier(ifNeeded step: ObservedDrawingTrialStep) {
    if observedDrawingTrialStep.rawValue > step.rawValue {
      observedDrawingTrialStep = step
    }
  }

  private func boundaryTerminalDescription(_ terminal: BoundaryMotionTerminal) -> String {
    switch terminal {
    case .limitAsserted(let pins, _):
      "Controller limit asserted (\(pins)); no boundary evidence was recorded."
    case .alarm(let alarm): "Controller alarm: \(alarm); no boundary evidence was recorded."
    case .refusal(let refusal): refusal.actionableDescription
    case .disconnected: "Controller disconnected; no boundary evidence was recorded."
    case .fault(let ambiguity): ambiguity.actionableDescription
    }
  }

  private func boundaryActivityOperation(
    direction: BoundaryDirection
  ) -> BoundaryActivityOperation {
    let acceptedRevisionID = boundarySideAggregates[direction]?.revisionID
    switch activeExerciseAttemptMode {
    case .replacement:
      return acceptedRevisionID.map { .replacement(direction, acceptedRevisionID: $0) }
        ?? .normal(direction)
    case .additional:
      return acceptedRevisionID.map { .additional(direction, acceptedRevisionID: $0) }
        ?? .normal(direction)
    case .normal, nil:
      return .normal(direction)
    }
  }

  private func appendBoundaryActivity(
    actor: BoundaryActivityActor,
    direction: BoundaryDirection,
    phase: BoundaryActivityPhase,
    disposition: BoundaryActivityDisposition,
    attemptID: ExerciseAttemptID,
    operationOwnerID: ContextualMotionOwnerID? = nil,
    stopCapabilityID: ContextualStopCapabilityID? = nil,
    finalPosition: MachinePosition? = nil,
    frameID: FrameID? = nil,
    cameraConfigurationID: CameraConfigurationID? = nil,
    affectedRevisionIDs: Set<LearningArtifactRevisionID> = [],
    retainedRevisionIDs: Set<LearningArtifactRevisionID> = [],
    detail: BoundaryActivityDetail,
    recovery: BoundaryActivityRecovery = .none,
    acceptedFallbackRemainsCurrent: Bool = false
  ) {
    boundaryActivityRecords.append(
      BoundaryActivityRecord(
        id: UUID(),
        occurredNanoseconds: nowNanoseconds(),
        actor: actor,
        operation: boundaryActivityOperation(direction: direction),
        phase: phase,
        disposition: disposition,
        attemptID: attemptID,
        side: direction,
        operationOwnerID: operationOwnerID,
        stopCapabilityID: stopCapabilityID,
        finalPosition: finalPosition,
        frameID: frameID,
        cameraConfigurationID: cameraConfigurationID,
        affectedRevisionIDs: affectedRevisionIDs,
        retainedRevisionIDs: retainedRevisionIDs,
        detail: detail,
        recovery: recovery,
        acceptedFallbackRemainsCurrent: acceptedFallbackRemainsCurrent
      )
    )
  }

  private func learningPathItemID(for sequenceID: DiscoverySequenceID) -> LearningPathItemID {
    sequenceID == .penInteraction
      ? .humanGuidedDiscovery(.penInteraction)
      : .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
  }

  private func jogDirection(for sequenceID: DiscoverySequenceID) -> JogDirection? {
    switch sequenceID {
    case .boundaryNegativeX: .xNegative
    case .boundaryPositiveX: .xPositive
    case .boundaryNegativeY: .yNegative
    case .boundaryPositiveY: .yPositive
    case .penInteraction: nil
    }
  }

  private func jogDirection(from direction: BoundaryDirection) -> JogDirection {
    switch direction {
    case .negativeX: .xNegative
    case .positiveX: .xPositive
    case .negativeY: .yNegative
    case .positiveY: .yPositive
    }
  }

  private func boundaryDirection(from direction: JogDirection)
    -> BoundaryDirection
  {
    switch direction {
    case .xNegative: .negativeX
    case .xPositive: .positiveX
    case .yNegative: .negativeY
    case .yPositive: .positiveY
    }
  }

  private func receiveVision(_ result: PlotterSceneAnalysisResult) {
    guard frameMode == .live, case .running = visionAnalysisSnapshot.state else { return }
    if let lock = videoAnalysisRegionLock, !lock.matches(result.displayedFrame) {
      videoAnalysisRegionLock = nil
      Task {
        await cameraActions?.setSceneAnalysisRegion(nil)
        await reconcileAutomaticVisionAnalysis()
      }
    }
    displayedFrame = result.displayedFrame
    lastSceneMeasurement = result.measurement
    overlayResultChannels.publishScene(
      overlayChannelResult(
        displayedFrame: result.displayedFrame,
        measurement: result.measurement
      )
    )
  }

  private func publishWorkflowInspection(
    _ inspection: LiveSceneInspection,
    owner: WorkflowOverlayOwner
  ) {
    overlayResultChannels.publishWorkflow(
      overlayChannelResult(
        displayedFrame: inspection.displayedFrame,
        measurement: inspection.measurement
      ),
      source: frameMode,
      owner: owner
    )
  }

  private func overlayChannelResult(
    displayedFrame: DisplayedFrame,
    measurement: PlotterSceneMeasurement
  ) -> OverlayChannelResult {
    let provenance = ExactFrameOverlayProvenance(displayedFrame)
    let capStateAndMessage: (OverlayRunState, String) =
      switch measurement.penCap {
      case .notRequested:
        (.unavailable, "Pen-cap analysis was not requested.")
      case .found(let cap, _):
        (
          .available,
          OverlayStatusGrammar.found(
            pixelCount: cap.pixelCount,
            confidence: cap.confidence,
            frame: displayedFrame.frame.sequence
          )
        )
      case .notFound:
        (.unavailable, OverlayStatusGrammar.notFound)
      case .candidatesRejected(let diagnostics):
        (
          .unavailable,
          OverlayStatusGrammar.candidateRejected(
            count: diagnostics.componentCount,
            reason: measurement.penCap.diagnosticReason
          )
        )
      case .ambiguous(let counts, _):
        (.ambiguous, OverlayStatusGrammar.ambiguous(candidateSizes: counts))
      case .failed(let reason):
        (.failed, "Failed — \(reason)")
      }
    let capStatus = OverlayLayerStatus(
      state: capStateAndMessage.0,
      message: capStateAndMessage.1,
      provenance: provenance
    )
    let armatureStateAndMessage: (OverlayRunState, String) =
      switch measurement.armatureEnvelope {
      case .notRequested:
        (.unavailable, "Armature-envelope analysis was not requested.")
      case .available:
        (.available, OverlayStatusGrammar.armatureAvailable)
      case .unavailableBecausePenCap(let capResult):
        (
          .unavailable,
          OverlayStatusGrammar.armatureUnavailable(reason: capResult.diagnosticReason)
        )
      case .failed(let reason):
        (.failed, "Failed — \(reason)")
      }
    let armatureStatus = OverlayLayerStatus(
      state: armatureStateAndMessage.0,
      message: armatureStateAndMessage.1,
      provenance: provenance
    )
    return OverlayChannelResult(
      displayedFrame: displayedFrame,
      overlays: measurement.overlays,
      statuses: [.penCap: capStatus, .armatureEnvelope: armatureStatus]
    )
  }

  private func updateCameraError() {
    cameraError = cameraSnapshot?.error?.actionableDescription
  }

  private func validatedLiveCameraFrame(in snapshot: CameraCaptureSnapshot) -> DisplayedFrame? {
    guard let frame = snapshot.latestFrame,
      case .live(let deviceID) = frame.source,
      deviceID == snapshot.selectedDeviceID
    else { return nil }
    return frame
  }

  private func clearMachineAuthority(clearSelection: Bool) async {
    if clearSelection { selectedSerialDevice = nil }
    passiveProbeResult = nil
    machineSnapshot = nil
    machineError = nil
    controllerAlarmClearInProgress = false
    passiveProbeInProgress = false
    jogRequestInProgress = false
    penRequestInProgress = false
    motionAuthorizationActionInProgress = false
    lastMotionGuardActivationText = "not activated"
    currentCameraCalibrationFailure = nil
    boundaryTeachingState = .idle
    boundaryTeachingResultText = "Choose one side to begin."
    await clearDiscoveryAuthority()
    if let parkedAcceptedMachineArtifactCheckpoint {
      acceptedArtifactCheckpointStatus = .quarantined(
        sideCount: parkedAcceptedMachineArtifactCheckpoint.boundarySideAggregates.count
      )
    }
  }

  private func persistAcceptedMachineArtifacts() {
    guard frameMode == .live,
      activeAcceptedLearningPathCheckpointActions != nil,
      let passiveProbeResult,
      passiveProbeResult.blockers.isEmpty,
      let machinePosition = machineSnapshot?.machine.position,
      !boundarySideAggregates.isEmpty
    else { return }
    do {
      let context = try ControllerCheckpointContext(probe: passiveProbeResult)
      let aggregates = BoundaryDirection.allCases.compactMap { boundarySideAggregates[$0] }
      let acceptedEvidence = aggregates.flatMap { aggregate in
        aggregate.includedAttemptIDs.compactMap { boundaryAttemptEvidenceByAttemptID[$0] }
      }
      let allowedKinds: Set<LearningArtifactKind> = Set(
        BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
          + [.estimatedMachineCenter, .centerArrival]
      )
      let revisions = learningArtifactGraph.revisions.filter {
        $0.state == .current && allowedKinds.contains($0.kind)
      }
      let checkpoint = try AcceptedMachineArtifactCheckpoint(
        controllerContext: context,
        machinePositionAtSave: machinePosition,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        acceptedAttemptSequence: acceptedAttemptSequence,
        pairedBoundaryProgress: pairedBoundaryProgress,
        acceptedBoundaryEvidence: acceptedEvidence,
        boundarySideAggregates: aggregates,
        estimatedMachineCenter: estimatedMachineCenter,
        learnedLocalCoordinateFrame: learnedLocalCoordinateFrame,
        centerArrivalPosition: centerArrivalPosition,
        acceptedRevisions: revisions
      )
      parkedAcceptedMachineArtifactCheckpoint = checkpoint
      persistAcceptedLearningPathCheckpoint()
      acceptedArtifactCheckpointStatus = .saved(
        sideCount: aggregates.count,
        centerArrival: centerArrivalPosition != nil
      )
    } catch {
      acceptedArtifactCheckpointStatus = .rejected(
        "Saving accepted machine artifacts failed: \(error)"
      )
    }
  }

  private func restoreAcceptedPenInteractionCheckpoint(
    _ checkpoint: AcceptedPenInteractionCheckpoint?
  ) {
    guard let checkpoint else { return }
    do {
      var history = try ExerciseAttemptHistory<PenInteractionAttemptEvidence>(
        compatibility: penAttemptHistory.compatibility
      )
      try history.record(
        ExerciseAttempt(
          id: checkpoint.revision.attemptID,
          disposition: .succeeded,
          compatibility: history.compatibility,
          acceptedSequence: checkpoint.acceptedSequence,
          value: checkpoint.evidence
        )
      )
      var graph = learningArtifactGraph
      _ = try graph.commitReplacement(
        LearningArtifactRevision(
          id: checkpoint.revision.id,
          kind: .penInteraction,
          attemptID: checkpoint.revision.attemptID,
          disposition: .succeeded
        )
      )
      penAttemptHistory = history
      currentPenActuationProfile = checkpoint.evidence.actuationProfile
      acceptedAttemptSequence = max(acceptedAttemptSequence, checkpoint.acceptedSequence)
      learningArtifactGraph = graph
    } catch {
      learningAuthorityError = "Saved Pen Interaction could not be restored: \(error)"
    }
  }

  private func currentAcceptedPenInteractionCheckpoint()
    -> AcceptedPenInteractionCheckpoint?
  {
    guard let revision = learningArtifactGraph.currentRevision(for: .penInteraction),
      let attempt = penAttemptHistory.includedSuccessfulAttempts.max(by: {
        $0.acceptedSequence < $1.acceptedSequence
      }),
      let evidence = attempt.value
    else { return nil }
    return try? AcceptedPenInteractionCheckpoint(
      revision: revision,
      acceptedSequence: attempt.acceptedSequence,
      evidence: evidence
    )
  }

  private func currentAcceptedMachineCameraCheckpoint()
    -> AcceptedMachineCameraCheckpoint?
  {
    guard let registration = machineCameraRegistration,
      let revision = learningArtifactGraph.currentRevision(for: .machineCameraRegistration)
    else { return nil }
    return try? AcceptedMachineCameraCheckpoint(
      revision: revision,
      registration: registration
    )
  }

  private var currentLearningPathSemanticIdentity: LearningPathSemanticIdentity {
    LearningPathSemanticIdentity(
      machineGeometry: machineGeometryIdentity,
      toolAssembly: toolAssemblyRevision,
      penContactProfile: penContactProfileRevision,
      paperInstance: currentPaperRevisionContext.instance,
      paperContactPlane: currentPaperRevisionContext.contactPlane,
      cameraMountRevision: cameraMountRevision,
      cameraReframingRevision: cameraReframingRevision
    )
  }

  private func persistAcceptedLearningPathCheckpoint(
    tipCalibration: AcceptedTipCalibrationCheckpoint? = nil,
    stageFour: AcceptedStageFourCheckpoint? = nil,
    clearTip: Bool = false,
    clearStageFour: Bool = false
  ) {
    guard frameMode == .live, let actions = activeAcceptedLearningPathCheckpointActions else {
      return
    }
    do {
      let retainedTip = clearTip
        ? nil
        : tipCalibration ?? acceptedLearningPathCheckpoint?.tipCalibration
          ?? quarantinedTipCalibrationCheckpoint
      let retainedStage = clearStageFour
        ? nil
        : stageFour ?? acceptedLearningPathCheckpoint?.stageFour
          ?? acceptedStageFourCheckpoint
      let checkpoint = try AcceptedLearningPathCheckpoint(
        semanticIdentity: currentLearningPathSemanticIdentity,
        penInteraction: currentAcceptedPenInteractionCheckpoint(),
        machineArtifacts: parkedAcceptedMachineArtifactCheckpoint,
        machineCamera: currentAcceptedMachineCameraCheckpoint() ?? pendingMachineCameraCheckpoint,
        tipCalibration: retainedTip,
        stageFour: retainedStage
      )
      try actions.save(checkpoint)
      acceptedLearningPathCheckpoint = checkpoint
      pendingMachineCameraCheckpoint = checkpoint.machineCamera
      acceptedStageFourCheckpoint = checkpoint.stageFour
    } catch {
      learningAuthorityError = "Learning Path checkpoint could not be saved: \(error)"
    }
  }

  private func revalidateParkedAcceptedArtifactCheckpoint(
    with probe: PassiveProbeResult,
    currentPosition: MachinePosition?
  ) {
    guard frameMode == .live,
      boundarySideAggregates.isEmpty,
      let checkpoint = parkedAcceptedMachineArtifactCheckpoint,
      let currentPosition
    else { return }
    do {
      let context = try ControllerCheckpointContext(probe: probe)
      switch checkpoint.compatibility(with: context, currentPosition: currentPosition) {
      case .incompatible(let reason):
        acceptedArtifactCheckpointStatus = .incompatible(reason)
      case .compatible(let reportedPositionDeltaMM):
        let histories = try checkpoint.restoredBoundaryHistories()
        try checkpoint.validate()
        var graph = learningArtifactGraph
        let orderedKinds: [LearningArtifactKind] =
          BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
          + [.estimatedMachineCenter, .centerArrival]
        for kind in orderedKinds {
          guard let revision = checkpoint.acceptedRevisions.first(where: { $0.kind == kind })
          else { continue }
          _ = try graph.commitReplacement(
            LearningArtifactRevision(
              id: revision.id,
              kind: revision.kind,
              attemptID: revision.attemptID,
              disposition: revision.disposition,
              consumedRevisionIDs: revision.consumedRevisionIDs
            )
          )
        }
        if let machineCamera = pendingMachineCameraCheckpoint {
          let revision = machineCamera.revision
          _ = try graph.commitReplacement(
            LearningArtifactRevision(
              id: revision.id,
              kind: revision.kind,
              attemptID: revision.attemptID,
              disposition: revision.disposition,
              consumedRevisionIDs: revision.consumedRevisionIDs
            )
          )
          machineCameraRegistration = machineCamera.registration
        }
        boundaryAttemptHistories = histories
        boundaryAttemptEvidenceByAttemptID = Dictionary(
          uniqueKeysWithValues: checkpoint.acceptedBoundaryEvidence.map {
            ($0.attemptID, $0)
          }
        )
        boundarySideAggregates = Dictionary(
          uniqueKeysWithValues: checkpoint.boundarySideAggregates.map {
            ($0.direction, $0)
          }
        )
        pairedBoundaryProgress = checkpoint.pairedBoundaryProgress
        estimatedMachineCenter = checkpoint.estimatedMachineCenter
        learnedLocalCoordinateFrame = checkpoint.learnedLocalCoordinateFrame
        centerArrivalPosition = checkpoint.centerArrivalPosition
        centerArrivalRetryRequired = false
        learningArtifactGraph = graph
        controllerSessionID = checkpoint.controllerSessionID
        explorationCoordinateRevision = checkpoint.coordinateRevision
        acceptedAttemptSequence = max(acceptedAttemptSequence, checkpoint.acceptedAttemptSequence)
        controllerPoseApplicability = .requiresVisualRevalidation(
          reportedPositionDeltaMM: reportedPositionDeltaMM
        )
        acceptedArtifactCheckpointStatus = .restored(
          sideCount: checkpoint.boundarySideAggregates.count,
          centerArrival: checkpoint.centerArrivalPosition != nil,
          reportedPositionDeltaMM: reportedPositionDeltaMM
        )
      }
    } catch {
      acceptedArtifactCheckpointStatus = .rejected(
        "Fresh controller revalidation failed: \(error)"
      )
    }
  }

  private var controllerLinkIsOpen: Bool {
    guard let connection = machineSnapshot?.machine.connection else { return false }
    switch connection {
    case .connecting, .connected, .probing, .moving, .actuatingPen:
      return true
    case .disconnected, .blocked:
      return false
    }
  }

  private func invalidateCameraDependentLearningAuthority() {
    var graph = learningArtifactGraph
    let invalidation = graph.invalidateForCameraChange(
      rootKinds: [.machineCameraRegistration, .tipCameraRegistration]
    )
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    cameraCalibrationAnchorFrame = nil
    cameraCalibrationReferencePosition = nil
    cameraCalibrationReferenceCapAnchor = nil
    proposedMachineCameraRegistration = nil
    machineCameraRegistration = nil
    pendingMachineCameraCheckpoint = nil
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
    activeLearningSession.toolContactSelection.clear()
    quarantinedTipCalibrationCheckpoint = nil
    persistAcceptedLearningPathCheckpoint(clearTip: true, clearStageFour: true)
    clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    explorationError = nil
    overlayResultChannels.clearWorkflow(source: frameMode)
    // Pen current state, accepted boundary controller MPos revisions, estimated
    // center, and accepted center arrival belong to the unchanged controller
    // session/coordinate authority and deliberately survive camera replacement.
  }

  private func clearPenLearningForRewind() {
    cancelPenCapAcceptedClickContinuation()
    discoveryTransactions.removeValue(forKey: .penInteraction)
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: penAttemptHistory.compatibility
    )
    selectedDiscoverySequenceID = .penInteraction
  }

  private func clearBoundaryLearningForRewind() {
    selectedDiscoverySequenceID = sequenceID(for: selectedBoundaryDirection)
    discoveryTransactions = discoveryTransactions.filter { key, _ in
      key == .penInteraction
    }
    discoveryError = nil
    boundaryTeachingState = .idle
    boundaryTeachingResultText = "Choose one side to begin."
    pairedBoundaryProgress = PairedBoundaryProgress()
    boundaryAttemptEvidenceByAttemptID = [:]
    boundarySideAggregates = [:]
    boundaryAttemptHistories = [:]
    estimatedMachineCenter = nil
    learnedLocalCoordinateFrame = nil
    centerArrivalPosition = nil
    centerArrivalRetryRequired = false
    pendingBoundaryFinalPositions = [:]
    pendingBoundaryOwnerIDs = [:]
    pendingBoundaryStopCapabilities = [:]
  }

  private func clearCalibrationLearningForRewind() {
    clearCalibrationLearningForRewind(from: .calibrateCameraAndVisibleCap)
  }

  private func clearCalibrationLearningForRewind(from step: HumanGuidedDiscoveryStep) {
    if step.rawValue <= HumanGuidedDiscoveryStep.calibrateCameraAndVisibleCap.rawValue {
      currentCameraCalibrationFailure = nil
      cameraCalibrationAnchorFrame = nil
      cameraCalibrationReferencePosition = nil
      cameraCalibrationReferenceCapAnchor = nil
      proposedMachineCameraRegistration = nil
      machineCameraRegistration = nil
      explicitRegistrationCapAnchorEvidence = []
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.calibratePenContactFromSparseMarks.rawValue {
      tipCameraRegistration = nil
      proposedTipCameraRegistration = nil
      sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
      activeLearningSession.toolContactSelection.clear()
    }
    overlayResultChannels.clearWorkflow(source: frameMode, owner: .cameraCalibration)
    overlayResultChannels.clearWorkflow(source: frameMode, owner: .sparseTipCalibration)
  }

  private func freshSparseTipCalibrationCoordinatorForCurrentPaper()
    -> SparseTipCalibrationCoordinator
  {
    SparseTipCalibrationCoordinator(
      blacklistedLocations: blacklistedToolContactLocations.filter {
        $0.paperInstance.rawValue == explorationPaperInstanceRevision
      }
    )
  }

  private func clearDrawingLearningForRewind(from step: ObservedDrawingTrialStep) {
    if step.rawValue <= ObservedDrawingTrialStep.moveToLineStart.rawValue {
      lastProtocolPoseSettlement = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue {
      overlayResultChannels.clearWorkflow(source: frameMode, owner: .observedDrawingTrial)
    }
    activeLearningSession.drawingTrial.rewind(from: step, source: frameMode)
  }

  private func clearDiscoveryAuthority() async {
    let penCapContinuation = cancelPenCapAcceptedClickContinuation()
    await penCapContinuation?.value
    await cancelAndSettleDiscoveryMotionBeforeErasure()
    selectedDiscoverySequenceID = .penInteraction
    discoveryTransactions = [:]
    discoveryError = nil
    pairedBoundaryProgress = PairedBoundaryProgress()
    boundaryAttemptEvidenceByAttemptID = [:]
    boundarySideAggregates = [:]
    estimatedMachineCenter = nil
    learnedLocalCoordinateFrame = nil
    centerArrivalPosition = nil
    centerArrivalRetryRequired = false
    cameraCalibrationAnchorFrame = nil
    cameraCalibrationReferencePosition = nil
    cameraCalibrationReferenceCapAnchor = nil
    proposedMachineCameraRegistration = nil
    machineCameraRegistration = nil
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
    activeLearningSession.toolContactSelection.clear()
    explicitRegistrationCapAnchorEvidence = []
    pendingBoundaryFinalPositions = [:]
    pendingBoundaryOwnerIDs = [:]
    pendingBoundaryStopCapabilities = [:]
    lastProtocolPoseSettlement = nil
    activeLearningSession.drawingTrial = DrawingTrialState(source: frameMode)
    learningArtifactGraph = LearningDependencyGraph()
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: penAttemptHistory.compatibility
    )
    boundaryAttemptHistories = [:]
    activeLearningSession.exerciseAttempt.finish()
    restartableExerciseItemID = nil
  }

  private func cancelAndSettleDiscoveryMotionBeforeErasure() async {
    guard boundaryTeachingState != .idle || boundaryMotionTask != nil else { return }

    if let target = activeStopTarget {
      let admitted = latchContextualStopDisposition(
        for: target,
        intent: .cancelAttempt,
        actor: "Application",
        action: "Clear Discovery Authority"
      )
      if let sequenceID = activeDiscoverySequenceID,
        var transaction = discoveryTransactions[sequenceID],
        admitted
      {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
      }
      if admitted {
        await requestSingleJogCancel(for: target, intent: .cancelAttempt)
      }
    }
    let motionTask = boundaryMotionTask
    await motionTask?.value
    if let sequenceID = activeDiscoverySequenceID,
      var transaction = discoveryTransactions[sequenceID]
    {
      transaction.cancel()
      discoveryTransactions[sequenceID] = transaction
    }
  }

  /// Shutdown first closes the admission boundary, then settles the already
  /// latched motion owner. This bypasses normal intent admission without
  /// exposing a second cancellation route to the UI.
  private func stopAndSettleActiveMotionForShutdown() async {
    guard let operation = activeStoppableOperation else { return }
    let target = operation.target
    switch target {
    case .pairedBoundary(_, let transactionID, _, _, let direction):
      let sequenceID = sequenceID(for: direction)
      if discoveryTransactions[sequenceID]?.id == transactionID,
        var transaction = discoveryTransactions[sequenceID]
      {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
        boundaryTeachingState = .cancelling(jogDirection(from: direction))
        boundaryTeachingResultText =
          "Shutdown requested. Waiting for the original motion owner to reach Idle."
      }
    case .manualJog, .manualDrawingStroke, .exerciseMotion, .drawingTrial, .sparseTipBatch,
      .sparseTipBatchSegment:
      break
    }

    if case .sparseTipBatch = target,
      let location = operation.possibleInkLocation
    {
      blacklistedToolContactLocations.insert(location)
      sparseTipCalibrationCoordinator.blacklistPossibleInk(
        at: location,
        reason: "Shutdown stopped the five-circle batch after Pen Down."
      )
    }

    if stopDispositionLatch == nil,
      latchContextualStopDisposition(
        for: target,
        intent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
    {
      await cancelAndSettleStoppableOperation(operation, intent: .shutdown)
    } else {
      await operation.owner.settle()
    }
    clearStoppableOperation(matching: target)
    boundaryTeachingState = .idle
  }

  private func clearCameraAuthority() async {
    frameMode = .live
    cameraSnapshot = nil
    displayedFrame = nil
    latestLiveCameraFrame = nil
    await clearDiscoveryAuthority()
    cameraError = nil
    visionError = nil
    scopedVisionAnalysisActive = false
    visionAnalysisSnapshot = .stopped
    lastSceneMeasurement = nil
    simulatorPenState = .unknown
    simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
  }

  private func announceAdvisory(_ message: String) async -> SpeechAnnouncementOutcome {
    guard let announcementActions else {
      lastAnnouncementResultText = "Announcement unavailable; continuing with the visible action."
      return .failed("Native speech output is unavailable.")
    }
    let outcome = await announcementActions.announce(message)
    lastAnnouncementResultText =
      switch outcome {
      case .completed: "Announcement completed."
      case .failed(let reason): "Announcement failed: \(reason). Continuing."
      case .timedOut: "Announcement timed out. Continuing."
      case .cancelled: "Announcement cancelled during shutdown."
      }
    return outcome
  }

  private func positiveFallbackTravelFeed() -> Double {
    guard let feed = inputNumber(feedText), feed > 0 else { return 100 }
    return feed
  }

  private func boundaryTravelFeedSelection() -> TravelFeedSelection {
    TravelFeedSelection(
      requestedFeedMMPerMinute: MotionPriors.boundaryFeedMMPerMinute,
      source: .existingFallback
    )
  }

  private func travelFeedSelection(
    for delta: Vector2<MachineSpace>
  ) -> TravelFeedSelection {
    if let ceiling = machineSnapshot?.machine.controllerAxisFeedLimits?
      .applicableFeedCeiling(for: delta)
    {
      return TravelFeedSelection(
        requestedFeedMMPerMinute: ceiling,
        source: .controllerReportedCeiling
      )
    }
    return TravelFeedSelection(
      requestedFeedMMPerMinute: positiveFallbackTravelFeed(),
      source: .existingFallback
    )
  }

  private func sequenceID(for direction: BoundaryDirection) -> DiscoverySequenceID {
    switch direction {
    case .negativeX: .boundaryNegativeX
    case .positiveX: .boundaryPositiveX
    case .negativeY: .boundaryNegativeY
    case .positiveY: .boundaryPositiveY
    }
  }

  private func boundaryDirection(for sequenceID: DiscoverySequenceID) -> BoundaryDirection? {
    switch sequenceID {
    case .boundaryNegativeX: .negativeX
    case .boundaryPositiveX: .positiveX
    case .boundaryNegativeY: .negativeY
    case .boundaryPositiveY: .positiveY
    case .penInteraction: nil
    }
  }

  private func drawingTrialActionUnavailableReason(
    for step: ObservedDrawingTrialStep
  ) -> String? {
    if activeExplorationOperation != nil {
      return "The current learning action is still in progress."
    }
    if frameMode == .simulated {
      if cameraActions == nil { return "The simulator camera composition is unavailable." }
      if !controllerSessionEstablished { return "Connect the learning simulator first." }
      if !motionAuthorizationEnabled { return "Enable simulated Motion first." }
      if simulatedLearningSnapshot?.currentOperation != nil {
        return "Stop or finish the current simulated operation first."
      }
      return nil
    }
    guard controllerIsConnected else { return "Connect the selected controller first." }
    guard motionGuardIsActive else { return "Enable Motion first." }
    if step != .compareIntendedAndObservedGeometry,
      machineSnapshot?.machine.penState != .up
    {
      return "The current commanded pen state must be Up."
    }
    switch step {
    case .chooseIsolatedLinePlan, .captureLocalPreLineBaseline, .revealAndObserveNewInk:
      if !cameraIsLive { return "A current LIVE camera frame is required." }
    case .moveToLineStart, .drawIsolatedLine, .compareIntendedAndObservedGeometry:
      break
    }
    if step == .chooseIsolatedLinePlan || step == .moveToLineStart
      || step == .drawIsolatedLine,
      machineSnapshot?.machine.position == nil
    {
      return "A current controller MPos is required."
    }
    return nil
  }

  private func advanceDrawingTrial(to step: ObservedDrawingTrialStep) {
    observedDrawingTrialStep = step
  }

  private func recordIsolatedLinePlan() throws {
    guard let registration = tipCameraRegistration,
      learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
        == registration.acceptedRevisionID
    else {
      throw LearningPathOperationError.requiredState(
        "A current accepted TipCameraRegistration revision is required."
      )
    }
    let acceptedMarkGeometry = sparseTipCalibrationCoordinator.acceptedObservations.map {
      $0.observation.markGeometry
    }
    let restoredMarkGeometry: [ToolContactMarkGeometryEvidence]
    if acceptedMarkGeometry.isEmpty,
      registration.estimatorRevision == SparseTipCircularMarkPlan.registrationEstimatorRevision
    {
      restoredMarkGeometry = try registration.observationEvidence.map {
        try SparseTipCircularMarkPlan.restoredGeometry(
          for: $0.calibrationPosition,
          in: registration.applicabilityRectangle
        )
      }
    } else {
      restoredMarkGeometry = []
    }
    let existingMarks = acceptedMarkGeometry + restoredMarkGeometry
    let preferredDirections: [BoundaryDirection] = [
      .positiveX, .negativeX, .positiveY, .negativeY,
    ]
    guard
      let plan = preferredDirections.lazy.compactMap({ direction in
        try? ObservedDrawingTrialLinePlan(
          direction: direction,
          domain: registration.applicabilityRectangle,
          existingMarks: existingMarks
        )
      }).first
    else {
      throw ObservedDrawingTrialPlanningError.noClearFiveMillimeterLine
    }
    selectedLineDirection = plan.direction
    drawingTrialLineStart = plan.startPosition
    drawingTrialLineEnd = plan.endPosition
    drawingTrialTipRegistrationRevisionID = registration.acceptedRevisionID
  }

  private func captureLocalPreLineBaseline() async throws {
    guard let registration = tipCameraRegistration,
      let currentRevision = learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id,
      currentRevision == registration.acceptedRevisionID,
      drawingTrialTipRegistrationRevisionID == currentRevision,
      controllerIsPenUpAndIdle
    else {
      throw LearningPathOperationError.requiredState(
        "A current accepted tip-model revision and settled Pen-Up pose are required."
      )
    }
    let revealPosition = try currentMachinePosition()
    let frame = try await captureProtocolFrame(
      newerThan: displayedFrame?.frame.captureNanoseconds ?? 0
    )
    localPreLineBaseline = frame
    drawingTrialRevealPosition = revealPosition
  }

  private func moveToRecordedLineStart() async throws {
    guard let destination = drawingTrialLineStart else {
      throw LearningPathOperationError.requiredState("Typed line plan is unavailable.")
    }
    let current = try currentMachinePosition()
    let delta = try Vector2<MachineSpace>(
      dx: destination.point.x - current.point.x,
      dy: destination.point.y - current.point.y
    )
    if delta.dx != 0 || delta.dy != 0 {
      let final = try await performSupervisedPenUpTravel(
        delta: delta,
        ownerID: .observedDrawingTrial(.moveToLineStart),
        action: .moveToLineStart
      )
      guard
        recordProtocolPoseSettlement(
          action: .moveToLineStart,
          target: destination,
          actual: final
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Move to Line Start settled at an incompatible MPos."
        )
      }
    }
  }

  private func currentMachinePosition() throws -> MachinePosition {
    if frameMode == .simulated, let position = simulatedLearningSnapshot?.mpos {
      return try MachinePosition(x: position.xMM, y: position.yMM)
    }
    guard let position = machineSnapshot?.machine.position else {
      throw LearningPathOperationError.requiredState("Current controller MPos is unavailable.")
    }
    return position
  }

  private var controllerIsPenUpAndIdle: Bool {
    if frameMode == .simulated {
      guard let snapshot = simulatedLearningSnapshot else { return false }
      return snapshot.session == .connected
        && snapshot.penPose == .up
        && snapshot.currentOperation == nil
        && snapshot.stickyAmbiguity == nil
    }
    guard let snapshot = machineSnapshot else { return false }
    return snapshot.currentOperation == .idle
      && snapshot.machine.controllerState == .idle
      && snapshot.machine.penState == .up
      && !snapshot.machine.operationInFlight
      && snapshot.machine.stickyAmbiguity == nil
  }

  private func protocolSettlementIsCurrent(
    _ settlement: ProtocolPoseSettlement?,
    expectedTarget: MachinePosition?
  ) -> Bool {
    guard let settlement, let expectedTarget,
      settlement.controllerSessionID == controllerSessionID,
      settlement.coordinateRevision == explorationCoordinateRevision,
      settlement.toolPaperRevision == explorationPaperInstanceRevision,
      protocolPositionsMatch(settlement.target, expectedTarget),
      protocolPositionsMatch(settlement.actual, expectedTarget),
      controllerIsPenUpAndIdle,
      let current = try? currentMachinePosition(),
      protocolPositionsMatch(current, settlement.actual)
    else { return false }
    return true
  }

  private func protocolPositionsMatch(
    _ actual: MachinePosition,
    _ target: MachinePosition
  ) -> Bool {
    MachinePositionAcceptancePolicy.accepts(actual, target: target)
  }

  static func supervisedTravelDelta(
    from current: MachinePosition,
    to target: MachinePosition
  ) throws -> Vector2<MachineSpace>? {
    guard !MachinePositionAcceptancePolicy.accepts(current, target: target) else {
      return nil
    }
    return try Vector2(
      dx: target.point.x - current.point.x,
      dy: target.point.y - current.point.y
    )
  }

  private func recordProtocolPoseSettlement(
    action: LearningMotionAction,
    target: MachinePosition,
    actual: MachinePosition,
    toleranceMM: Double = MachinePositionAcceptancePolicy.toleranceMM
  ) -> Bool {
    let residual = actual.point.distance(to: target.point)
    lastProtocolPoseSettlement = ProtocolPoseSettlement(
      action: action,
      target: target,
      actual: actual,
      residualMM: residual,
      toleranceMM: toleranceMM,
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      toolPaperRevision: explorationPaperInstanceRevision
    )
    return residual <= toleranceMM
  }

  /// One explicit, finite, Pen-Up exercise travel. This shares the runtime's
  /// capability-bound cancel route but accepts no artifact unless the original
  /// owner naturally completes at its reported final MPos.
  private func performSupervisedPenUpTravel(
    delta: Vector2<MachineSpace>,
    ownerID: LearningPathItemID,
    action: LearningMotionAction
  ) async throws -> MachinePosition {
    let visionLease = await beginScopedVisionAnalysis()
    do {
      let finalPosition = try await executeSupervisedPenUpTravel(
        delta: delta,
        ownerID: ownerID,
        action: action
      )
      await endScopedVisionAnalysis(visionLease)
      return finalPosition
    } catch {
      await endScopedVisionAnalysis(visionLease)
      throw error
    }
  }

  private func executeSupervisedPenUpTravel(
    delta: Vector2<MachineSpace>,
    ownerID: LearningPathItemID,
    action: LearningMotionAction
  ) async throws -> MachinePosition {
    guard !hasShutdown, !Task.isCancelled else {
      throw LearningPathOperationError.requiredState(
        "Application shutdown closed admission for supervised Pen-Up travel."
      )
    }
    let selection = travelFeedSelection(for: delta)
    lastTravelFeedSelection = selection
    if frameMode == .simulated {
      let response = await simulatedLearningRuntime.beginManualJog(
        delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy)
      )
      let operation: SimulatedLearningOperation
      do {
        operation = try response.result.get()
      } catch {
        throw LearningPathOperationError.controllerFailed(
          "Simulated supervised Pen-Up travel was refused: \(String(describing: error))."
        )
      }
      let capabilityID = try supervisedTravelStopCapabilityID(ownerID: ownerID)
      let target = ContextualStopTarget.exerciseMotion(
        capabilityID: capabilityID,
        operationOwner: .simulated(operation.id),
        ownerID: ownerID,
        action: action
      )
      let owner = Task<SimulatedLearningOperationOutcome?, Never> {
        [simulatedLearningRuntime, simulatedExecutionPacing] in
        try? await simulatedLearningRuntime.executeNaturally(
          operation.id,
          pacing: simulatedExecutionPacing
        ).result.get()
      }
      installStoppableOperation(target: target, owner: .simulated(owner))
      defer { clearStoppableOperation(matching: target) }
      try await cancelSparseTipSegmentIfRequested(target: target, owner: .simulated(owner))
      if hasShutdown || Task.isCancelled {
        _ = latchContextualStopDisposition(
          for: target,
          intent: .shutdown,
          actor: "Application",
          action: "Shutdown"
        )
        await requestSingleJogCancel(for: target, intent: .shutdown)
        simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
        throw LearningPathOperationError.requiredState(
          "Application shutdown cancelled supervised Pen-Up travel before execution."
        )
      }
      let outcome = await owner.value
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
      guard let outcome, outcome.disposition == .naturallyCompleted else {
        throw LearningPathOperationError.controllerCancelled(
          "Simulated exercise travel did not complete naturally."
        )
      }
      return try MachinePosition(x: outcome.finalMPos.xMM, y: outcome.finalMPos.yMM)
    }

    guard let machineActions else {
      throw LearningPathOperationError.requiredState("Machine composition is unavailable.")
    }
    let request = RelativeJogRequest(
      delta: delta,
      feedMMPerMinute: selection.requestedFeedMMPerMinute
    )
    let operation: RelativeJogOperation
    switch await machineActions.beginRelativeJog(request) {
    case .admitted(let admitted):
      operation = admitted
    case .rejected(let outcome):
      throw operationError(for: outcome, action: action.title)
    }
    let capabilityID = try supervisedTravelStopCapabilityID(ownerID: ownerID)
    let target = ContextualStopTarget.exerciseMotion(
      capabilityID: capabilityID,
      operationOwner: .liveOperation(operation.id),
      ownerID: ownerID,
      action: action
    )
    let owner = Task { await operation.outcome() }
    installStoppableOperation(target: target, owner: .motion(owner))
    defer { clearStoppableOperation(matching: target) }
    try await cancelSparseTipSegmentIfRequested(target: target, owner: .motion(owner))
    if hasShutdown || Task.isCancelled {
      _ = latchContextualStopDisposition(
        for: target,
        intent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
      await requestSingleJogCancel(for: target, intent: .shutdown)
      _ = await owner.value
      machineSnapshot = await machineActions.snapshot()
      throw LearningPathOperationError.requiredState(
        "Application shutdown cancelled supervised Pen-Up travel during admission."
      )
    }
    let outcome = await owner.value
    machineSnapshot = await machineActions.snapshot()
    switch outcome {
    case .acceptedThenCompleted(let finalPosition):
      return finalPosition
    case .cancelled:
      throw LearningPathOperationError.controllerCancelled(
        "\(action.title) was stopped or cancelled; no arrival artifact was accepted."
      )
    case .ambiguous(let ambiguity):
      throw LearningPathOperationError.controllerAmbiguous(ambiguity.actionableDescription)
    case .refused(let refusal):
      throw LearningPathOperationError.controllerRefused(refusal.actionableDescription)
    }
  }

  private func drawIsolatedTrialLine() async throws {
    guard let start = drawingTrialLineStart else {
      throw LearningPathOperationError.requiredState(
        "Move to the recorded tip-model-domain line start before drawing."
      )
    }
    let current = try currentMachinePosition()
    guard
      recordProtocolPoseSettlement(
        action: .confirmIsolatedLineStart,
        target: start,
        actual: current
      )
    else {
      throw LearningPathOperationError.requiredState(
        "Move to the recorded tip-model-domain line start before drawing."
      )
    }
    guard let lineEnd = drawingTrialLineEnd else {
      throw LearningPathOperationError.requiredState(
        "The predicted isolated-line end is unavailable."
      )
    }
    let delta = try start.point.vector(to: lineEnd.point)
    if frameMode == .simulated {
      applySimulatedSnapshotResponse(
        await simulatedLearningRuntime.setPenPose(.down),
        action: "Lower simulated pen for isolated line"
      )
      let response = await simulatedLearningRuntime.beginDrawing(
        delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy)
      )
      let operation = try response.result.get()
      let target = ContextualStopTarget.drawingTrial(
        capabilityID: ContextualStopCapabilityID(),
        operationOwner: .simulated(operation.id)
      )
      let task = Task { [simulatedLearningRuntime, simulatedExecutionPacing] in
        try? await simulatedLearningRuntime.executeNaturally(
          operation.id,
          pacing: simulatedExecutionPacing
        ).result.get()
      }
      activeExplorationOperation?.strokeState = .possibleInk
      installStoppableOperation(target: target, owner: .simulated(task))
      defer { clearStoppableOperation(matching: target) }
      guard let outcome = await task.value else {
        throw LearningPathOperationError.possibleInk(
          "The simulated isolated-line owner lost its outcome."
        )
      }
      guard outcome.disposition == .naturallyCompleted else {
        throw LearningPathOperationError.possibleInk(
          "Simulated drawing did not complete naturally."
        )
      }
      activeExplorationOperation?.strokeState = .completedNaturally
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
      applySimulatedSnapshotResponse(
        await simulatedLearningRuntime.setPenPose(.up),
        action: "Raise simulated pen after isolated line"
      )
      return
    }
    guard let machineActions else {
      throw LearningPathOperationError.requiredState("Recorded line start is unavailable.")
    }
    _ = await announceAdvisory("Lowering the pen for the isolated line.")
    let lower = await machineActions.requestPenActuation(.lower, currentPenActuationProfile)
    machineSnapshot = await machineActions.snapshot()
    guard case .commandedAndSettled = lower else {
      activeExplorationOperation?.strokeState = .possibleInk
      throw operationError(for: lower, possibleInk: true)
    }

    let request = DrawingStrokeRequest(
      delta: delta,
      feedMMPerMinute: positiveFallbackTravelFeed()
    )
    _ = await announceAdvisory("Drawing one isolated line.")
    let admittedOperation: DrawingStrokeOperation
    switch await machineActions.beginDrawingStroke(request) {
    case .admitted(let operation):
      admittedOperation = operation
    case .rejected(let outcome):
      throw operationError(for: outcome, possibleInk: true)
    }
    let target = ContextualStopTarget.drawingTrial(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(admittedOperation.id)
    )
    let owner = Task { await admittedOperation.outcome() }
    activeExplorationOperation?.strokeState = .possibleInk
    installStoppableOperation(target: target, owner: .drawing(owner))
    defer { clearStoppableOperation(matching: target) }
    let outcome = await owner.value
    machineSnapshot = await machineActions.snapshot()
    switch outcome {
    case .completed(let evidence):
      drawingTrialStrokeEvidence = evidence
      activeExplorationOperation?.strokeState = .completedNaturally
      _ = await announceAdvisory("Raising the pen after the isolated line.")
      let raise = await machineActions.requestPenActuation(.raise, currentPenActuationProfile)
      machineSnapshot = await machineActions.snapshot()
      guard case .commandedAndSettled = raise else {
        throw operationError(for: raise, possibleInk: true)
      }
    case .cancelled(let evidence, let penRaiseOutcome):
      drawingTrialStrokeEvidence = evidence
      activeExplorationOperation?.strokeState = .possibleInk
      throw LearningPathOperationError.possibleInk(
        "Drawing stopped; controller Pen Up outcome: \(penRaiseOutcome)"
      )
    case .ambiguous(let ambiguity):
      throw LearningPathOperationError.possibleInk(ambiguity.actionableDescription)
    case .refused(let refusal):
      throw LearningPathOperationError.controllerRefused(String(describing: refusal))
    }
  }

  private func revealAndObserveTrialInk() async throws {
    guard cameraActions != nil,
      let baseline = localPreLineBaseline,
      let revealPosition = drawingTrialRevealPosition,
      let lineStart = drawingTrialLineStart,
      let lineEnd = drawingTrialLineEnd,
      let registration = tipCameraRegistration,
      let registrationRevisionID = drawingTrialTipRegistrationRevisionID,
      registration.acceptedRevisionID == registrationRevisionID,
      learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
        == registrationRevisionID
    else {
      throw LearningPathOperationError.requiredState(
        "The local baseline, reveal pose, line plan, and exact current tip-model revision are required."
      )
    }
    let current = try currentMachinePosition()
    if !protocolPositionsMatch(current, revealPosition) {
      let delta = try Vector2<MachineSpace>(
        dx: revealPosition.point.x - current.point.x,
        dy: revealPosition.point.y - current.point.y
      )
      let final = try await performSupervisedPenUpTravel(
        delta: delta,
        ownerID: .observedDrawingTrial(.revealAndObserveNewInk),
        action: .returnToLocalRevealPose
      )
      guard
        recordProtocolPoseSettlement(
          action: .returnToLocalRevealPose,
          target: revealPosition,
          actual: final
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Return to the local reveal pose settled at an incompatible MPos."
        )
      }
    }
    let boundary = max(
      baseline.frame.captureNanoseconds,
      drawingTrialStrokeEvidence?.finalSampleNanoseconds ?? 0
    )
    let post = try await captureProtocolFrame(newerThan: boundary)
    explorationPostLineFrame = post
    displayedFrame = post
    let cameraStart = try registration.tipPixel(at: lineStart.point)
    let cameraEnd = try registration.tipPixel(at: lineEnd.point)
    let projectedDelta = try cameraStart.vector(to: cameraEnd)
    let componentAndAlignmentMargin = 6
    let minX = Int(floor(min(cameraStart.x, cameraEnd.x))) - componentAndAlignmentMargin
    let minY = Int(floor(min(cameraStart.y, cameraEnd.y))) - componentAndAlignmentMargin
    let maxX = Int(ceil(max(cameraStart.x, cameraEnd.x))) + componentAndAlignmentMargin
    let maxY = Int(ceil(max(cameraStart.y, cameraEnd.y))) + componentAndAlignmentMargin
    let clippedX = max(0, min(post.frame.width - 1, minX))
    let clippedY = max(0, min(post.frame.height - 1, minY))
    let trialRegion = PixelRect(
      x: clippedX,
      y: clippedY,
      width: max(1, min(post.frame.width - clippedX, maxX - clippedX + 1)),
      height: max(1, min(post.frame.height - clippedY, maxY - clippedY + 1))
    )
    drawingTrialObservationRegion = trialRegion
    let outcome = await observeWorkflowInk(
      IsolatedInkObservationRequest(
        localPreLineBaseline: SamePoseFrameSample(
          displayedFrame: baseline,
          controllerPosition: revealPosition
        ),
        postLine: SamePoseFrameSample(
          displayedFrame: post,
          controllerPosition: revealPosition
        ),
        region: trialRegion,
        thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
        lineStartPoint: cameraStart,
        tipRegistrationRevisionID: registrationRevisionID,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        toolPaperRevision: explorationPaperInstanceRevision,
        controllerPositionToleranceMM: MachinePositionAcceptancePolicy.toleranceMM,
        alignmentSearchRadiusPixels:
          FixedCameraOpticalSettlingPolicy.alignmentSearchRadiusPixels,
        maximumAlignmentShiftPixels:
          FixedCameraOpticalSettlingPolicy.maximumAlignmentShiftPixels,
        maximumBackgroundMeanAbsoluteDifference:
          FixedCameraOpticalSettlingPolicy.maximumBackgroundMeanAbsoluteDifference,
        projectedActualStrokeDelta: projectedDelta,
        algorithmRevision: "tip-registration-local-line-v1"
      )
    )
    switch outcome {
    case .observed(let observation):
      acceptInkObservation(observation, displayedFrame: post)
    case .rejected(let rejection):
      lastInkObservation = nil
      explorationInkStatus = "ink or geometry unclear: \(rejection.reason); no redraw requested"
      overlayResultChannels.clearWorkflow(source: frameMode, owner: .observedDrawingTrial)
      throw LearningPathOperationError.inkRejected(String(describing: rejection.reason))
    }
  }

  private func clearAutomaticVisionPresentation() {
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    scopedVisionAnalysisActive = false
    visionAnalysisSnapshot = .stopped
    visionError = nil
    lastSceneMeasurement = nil
  }

  private func beginHardwareIntent() -> UInt64? {
    guard !hasShutdown else { return nil }
    activeHardwareIntentCount += 1
    return lifetimeGeneration
  }

  private func endHardwareIntent() {
    precondition(activeHardwareIntentCount > 0)
    activeHardwareIntentCount -= 1
    guard activeHardwareIntentCount == 0 else { return }
    let waiters = intentDrainWaiters
    intentDrainWaiters.removeAll(keepingCapacity: false)
    for waiter in waiters { waiter.resume() }
  }

  private func canCommit(_ generation: UInt64) -> Bool {
    !hasShutdown && lifetimeGeneration == generation
  }

  private func waitForHardwareIntentsToDrain() async {
    guard activeHardwareIntentCount > 0 else { return }
    await withCheckedContinuation { continuation in
      intentDrainWaiters.append(continuation)
    }
  }

  private func inputNumber(_ text: String) -> Double? {
    guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
      value.isFinite
    else { return nil }
    return value
  }

  private func actionableDescription(_ error: any Error) -> String {
    if let cameraError = error as? CameraCaptureError {
      return cameraError.actionableDescription
    }
    if let localized = error as? LocalizedError,
      let description = localized.errorDescription
    {
      return description
    }
    return String(describing: error)
  }

  private func workflowFailure(for error: any Error) -> WorkflowFailure {
    let detail = actionableDescription(error)
    guard let operationError = error as? LearningPathOperationError else {
      return WorkflowFailure(kind: .failed, detail: detail, recovery: .resolveNamedFailure)
    }
    switch operationError {
    case .controllerRefused:
      return WorkflowFailure(kind: .refused, detail: detail, recovery: .resolveNamedFailure)
    case .controllerCancelled:
      return WorkflowFailure(kind: .cancelled, detail: detail, recovery: .none)
    case .controllerAmbiguous:
      return WorkflowFailure(kind: .ambiguous, detail: detail, recovery: .resolveNamedFailure)
    case .possibleInk:
      return WorkflowFailure(kind: .possibleInk, detail: detail, recovery: .resolveNamedFailure)
    case .inkRejected:
      return WorkflowFailure(kind: .unclear, detail: detail, recovery: .resolveNamedFailure)
    case .freshFrameUnavailable, .controllerFailed, .controllerContextChanged, .requiredState:
      return WorkflowFailure(kind: .failed, detail: detail, recovery: .resolveNamedFailure)
    }
  }

  private func workflowFailure(for terminal: BoundaryMotionTerminal) -> WorkflowFailure {
    let detail = boundaryTerminalDescription(terminal)
    switch terminal {
    case .limitAsserted, .alarm, .refusal, .disconnected:
      return WorkflowFailure(kind: .refused, detail: detail, recovery: .resolveNamedFailure)
    case .fault:
      return WorkflowFailure(kind: .ambiguous, detail: detail, recovery: .resolveNamedFailure)
    }
  }

  private func operationError(
    for outcome: MotionOutcome,
    action: String
  ) -> LearningPathOperationError {
    switch outcome {
    case .refused(let refusal): .controllerRefused(refusal.actionableDescription)
    case .ambiguous(let ambiguity): .controllerAmbiguous(ambiguity.actionableDescription)
    case .cancelled:
      .controllerCancelled(
        "\(action) was stopped or cancelled before an arrival artifact could be accepted.")
    case .acceptedThenCompleted:
      .controllerFailed(
        "\(action) completed before its owner-bound admission handle was returned.")
    }
  }

  private func operationError(
    for outcome: DrawingStrokeOutcome,
    possibleInk: Bool
  ) -> LearningPathOperationError {
    switch outcome {
    case .refused(let refusal): .controllerRefused(String(describing: refusal))
    case .ambiguous(let ambiguity):
      possibleInk
        ? .possibleInk(ambiguity.actionableDescription)
        : .controllerAmbiguous(ambiguity.actionableDescription)
    case .cancelled(_, let penRaiseOutcome):
      possibleInk
        ? .possibleInk("Drawing was cancelled; Pen Up outcome: \(penRaiseOutcome)")
        : .controllerCancelled("Drawing was cancelled before contact authority existed.")
    case .completed:
      .controllerFailed("Drawing completed before its admitted owner handle was returned.")
    }
  }

  private func operationError(
    for outcome: PenOutcome,
    possibleInk: Bool
  ) -> LearningPathOperationError {
    switch outcome {
    case .refused(let refusal): .controllerRefused(String(describing: refusal))
    case .ambiguous(let ambiguity):
      possibleInk
        ? .possibleInk(ambiguity.actionableDescription)
        : .controllerAmbiguous(ambiguity.actionableDescription)
    case .commandedAndSettled:
      .controllerFailed("A settled Pen outcome reached a failure-only conversion path.")
    }
  }

  private func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async {
    await workflowTelemetryActions?.record(event)
  }

  private func updateCurrentCameraCalibrationPhase(
    _ phase: CurrentCameraCalibrationPhase,
    operationID: UUID,
    attemptID: ExerciseAttemptID?
  ) async {
    currentCameraCalibrationPhase = phase
    await recordWorkflowTelemetry(
      WorkflowTelemetryEvent(
        operationID: operationID,
        operation: .currentCameraCalibration,
        phase: .phaseChanged,
        attemptID: attemptID,
        detail: phase.description
      )
    )
  }

  private func currentCameraCalibrationFailure(
    for error: any Error,
    targetPosition: MachinePosition
  ) -> CurrentCameraCalibrationFailure {
    let detail = actionableDescription(error)
    if let operationError = error as? LearningPathOperationError {
      switch operationError {
      case .controllerContextChanged:
        return CurrentCameraCalibrationFailure(
          code: .controllerContextChanged,
          detail: detail,
          recovery: .revalidateControllerContext
        )
      case .freshFrameUnavailable:
        return CurrentCameraCalibrationFailure(
          code: .freshFrameUnavailable,
          detail: detail,
          recovery: calibrationPositionRecovery(targetPosition: targetPosition)
        )
      case .controllerRefused, .controllerCancelled, .controllerAmbiguous, .controllerFailed,
        .possibleInk:
        return CurrentCameraCalibrationFailure(
          code: .controllerOutcome,
          detail: detail,
          recovery: calibrationPositionRecovery(targetPosition: targetPosition)
        )
      case .inkRejected:
        return CurrentCameraCalibrationFailure(
          code: .inkRejected,
          detail: detail,
          recovery: .resolveNamedFailure
        )
      case .requiredState:
        return CurrentCameraCalibrationFailure(
          code: .requiredStateMissing,
          detail: detail,
          recovery: calibrationPositionRecovery(targetPosition: targetPosition)
        )
      }
    }
    return CurrentCameraCalibrationFailure(
      code: .unexpectedFailure,
      detail: detail,
      recovery: calibrationPositionRecovery(targetPosition: targetPosition)
    )
  }

  private func calibrationPositionRecovery(
    targetPosition: MachinePosition
  ) -> WorkflowTelemetryRecovery {
    guard let current = try? currentMachinePosition() else { return .resolveNamedFailure }
    return protocolPositionsMatch(current, targetPosition)
      ? .retryCalibration : .resolveNamedFailure
  }

}

extension Array {
  fileprivate var onlyElement: Element? { count == 1 ? self[0] : nil }
}

func machineBlockerLabel(_ blocker: MachineBlocker) -> String {
  switch blocker {
  case .noSerialDevice: "No serial device is selected."
  case .multipleSerialDevices(let devices): "Select one of \(devices.count) serial devices."
  case .transport(let reason): "Controller transport: \(reason)"
  case .timeout(let query): "Controller timed out during \(query.rawValue)."
  case .invalidReply(let query, let reason): "Invalid \(query.rawValue) reply: \(reason)"
  case .responseLimitExceeded(let query, let maximumBytes, let maximumChunks):
    "\(query.rawValue) exceeded \(maximumBytes) bytes or \(maximumChunks) chunks."
  case .controllerAlarm(let code): "Controller alarm: \(code)"
  case .controllerError(let code): "Controller error: \(code)"
  }
}
