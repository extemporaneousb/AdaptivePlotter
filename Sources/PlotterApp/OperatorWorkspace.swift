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
  static let maximumCentroidSpreadPixels: Double = 2
  static let maximumBackgroundMeanAbsoluteDifference: Double = 4
}

enum CanvasLayer: String, CaseIterable, Identifiable {
  case intendedPath = "Intended path"
  case modelPrediction = "Plotter estimate"
  case observedInk = "Observed ink"
  case residuals = "Residuals"
  case penCap = "Pen cap"
  case measuredFrameSides = "Measured frame sides"
  case drawingFrameEstimate = "Drawing frame estimate"
  case armatureEstimate = "Armature"

  var id: Self { self }

  var overlayKind: CameraOverlayKind {
    switch self {
    case .intendedPath: .intendedPath
    case .modelPrediction: .modelPrediction
    case .observedInk: .observedInk
    case .residuals: .residual
    case .penCap: .penCap
    case .measuredFrameSides: .measuredFrameSide
    case .drawingFrameEstimate: .drawingFrameEstimate
    case .armatureEstimate: .armatureEstimate
    }
  }

  var requiresSceneAnalysis: Bool {
    switch self {
    case .penCap, .measuredFrameSides, .drawingFrameEstimate, .armatureEstimate:
      true
    case .intendedPath, .modelPrediction, .observedInk, .residuals:
      false
    }
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

enum OperatorFrameMode: String, CaseIterable, Identifiable, Sendable {
  case live = "LIVE"
  case simulated = "SIMULATED"

  var id: Self { self }
}

enum AcceptedArtifactCheckpointStatus: Equatable, Sendable {
  case unavailable
  case cleared
  case quarantined(sideCount: Int)
  case saved(sideCount: Int, centerArrival: Bool)
  case restored(sideCount: Int, centerArrival: Bool, residualMM: Double)
  case incompatible(String)
  case rejected(String)

  var text: String {
    switch self {
    case .unavailable:
      "No durable accepted-artifact checkpoint is available."
    case .cleared:
      "The durable accepted-artifact checkpoint was explicitly cleared."
    case .quarantined(let sideCount):
      "A checkpoint containing \(sideCount) accepted Boundary side(s) is parked until a fresh passive controller probe matches."
    case .saved(let sideCount, let centerArrival):
      "Saved \(sideCount) accepted Boundary side(s)\(centerArrival ? " plus center arrival" : "") atomically."
    case .restored(let sideCount, let centerArrival, let residualMM):
      String(
        format:
          "Restored %d accepted Boundary side(s)%@ after controller-context revalidation (MPos residual %.3f mm).",
        sideCount,
        centerArrival ? " plus center arrival" : "",
        residualMM
      )
    case .incompatible(let reason):
      "The accepted-artifact checkpoint remains quarantined: \(reason) No workflow or command was replayed."
    case .rejected(let reason):
      "The accepted-artifact checkpoint was rejected: \(reason) No workflow or command was replayed."
    }
  }
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
  case exerciseMotion(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    ownerID: LearningPathItemID,
    action: String
  )
  case drawingTrial(
    capabilityID: ContextualStopCapabilityID, operationOwner: ContextualMotionOwnerID)
  case sparseTipMark(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    location: BlacklistedToolContactLocation
  )

  var capabilityID: ContextualStopCapabilityID {
    switch self {
    case .pairedBoundary(let capabilityID, _, _, _, _),
      .manualJog(let capabilityID, _),
      .exerciseMotion(let capabilityID, _, _, _),
      .drawingTrial(let capabilityID, _),
      .sparseTipMark(let capabilityID, _, _):
      capabilityID
    }
  }

  var operationOwner: ContextualMotionOwnerID {
    switch self {
    case .pairedBoundary(_, _, let owner, _, _),
      .manualJog(_, let owner),
      .exerciseMotion(_, let owner, _, _),
      .drawingTrial(_, let owner),
      .sparseTipMark(_, let owner, _):
      owner
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

  var actionLabel: String {
    switch self {
    case .normal(let direction): "Record \(direction.displayName) boundary stop"
    case .replacement(let direction, _): "Redo \(direction.displayName) Boundary"
    case .additional(let direction, _): "Record Another \(direction.displayName) Attempt"
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

  var presentationOutcome: OperationActivityOutcome {
    switch self {
    case .inProgress: .inProgress
    case .succeeded: .succeeded
    case .cancelled: .cancelled
    case .refused, .failed, .ambiguous: .needsAttention
    }
  }

  var outcomeLabel: String {
    switch self {
    case .inProgress: "In progress"
    case .succeeded: "Succeeded"
    case .refused: "Refused"
    case .failed: "Failed"
    case .cancelled: "Cancelled"
    case .ambiguous: "Ambiguous"
    }
  }
}

enum BoundaryActivityDetail: Hashable, Sendable {
  case message(String)
  case atomicCommitRejected(stage: String)

  var text: String {
    switch self {
    case .message(let text): text
    case .atomicCommitRejected(let stage):
      "The staged Boundary commit was rejected at \(stage); no accepted model value changed."
    }
  }
}

enum BoundaryActivityRecovery: Hashable, Sendable {
  case restartNormal(BoundaryDirection)
  case continueWithAcceptedFallback(BoundaryDirection)
  case resolveStickyAmbiguity(String)
  case none

  var text: String {
    switch self {
    case .restartNormal(let direction):
      "Restart the \(direction.displayName) Boundary attempt after resolving the named fact."
    case .continueWithAcceptedFallback(let direction):
      "Continue with the accepted boundaries, or explicitly retry \(direction.displayName)."
    case .resolveStickyAmbiguity(let reason):
      "Resolve sticky ambiguity before any new physical motion: \(reason)"
    case .none: ""
    }
  }
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
  case motion(Task<MotionOutcome, Never>)
  case drawing(Task<DrawingStrokeOutcome, Never>)
  case simulated(Task<SimulatedLearningOperationOutcome?, Never>)

  func settle() async {
    switch self {
    case .boundary(let task): await task.value
    case .motion(let task): _ = await task.value
    case .drawing(let task): _ = await task.value
    case .simulated(let task): _ = await task.value
    }
  }

  var drawingMayHaveInk: Bool {
    switch self {
    case .drawing, .simulated: true
    case .boundary, .motion: false
    }
  }
}

private struct ActiveStoppableOperation {
  let target: ContextualStopTarget
  let owner: StoppableOperationOwner
  var state: ContextualStopLifecycleState = .available
}

private struct BoundaryApproachAdvisory: Sendable {
  let observation: BoundaryApproachObservation?
  let advice: BoundaryApproachAdvice
}

enum BoundaryAtomicCommitFailurePoint: String, CaseIterable, Hashable, Sendable {
  case settlement
  case aggregateConstruction
  case artifactGraphCommit
}

enum DrawingTrialAssessment: String, CaseIterable, Identifiable, Hashable, Sendable {
  case observedGeometryAccepted
  case inkOrGeometryUnclear

  var id: Self { self }

  var title: String {
    switch self {
    case .observedGeometryAccepted: "Observed geometry accepted"
    case .inkOrGeometryUnclear: "Ink or geometry unclear"
    }
  }
}

private enum LearningPathOperationError: LocalizedError, Sendable {
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

  var recoveryDescription: String {
    switch recovery {
    case .none:
      "No recovery action is required."
    case .retryCalibration:
      "Resolve the named fact, then retry the bounded five-position calibration."
    case .revalidateControllerContext:
      "Do not continue calibration. Reconnect and revalidate the named controller context fields and accepted machine artifacts first."
    case .resolveNamedFailure:
      "Resolve the named controller, camera, or exact-frame failure before retrying this action."
    }
  }
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

struct LiveSceneInspection: Sendable {
  let displayedFrame: DisplayedFrame
  let measurement: PlotterSceneMeasurement
}

private struct ScopedVisionAnalysisLease: Sendable {}

struct ProtocolPoseSettlement: Hashable, Sendable {
  let action: String
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
  let paperContactPlane: PaperContactPlaneRevision
  let cameraMountRevision: UUID
  let cameraReframingRevision: UUID

  static func ephemeral() -> Self {
    Self(
      machineGeometry: MachineGeometryIdentity(),
      toolAssembly: ToolAssemblyRevision(),
      penContactProfile: PenContactProfileRevision(),
      paperContactPlane: PaperContactPlaneRevision(),
      cameraMountRevision: UUID(),
      cameraReframingRevision: UUID()
    )
  }
}

@MainActor
@Observable
final class OperatorWorkspace {
  private enum ExerciseAttemptMode: Sendable {
    case normal
    case replacement
    case additional
  }

  private struct DrawingTrialPayloadSnapshot {
    let step: ObservedDrawingTrialStep
    let localPreLineBaseline: DisplayedFrame?
    let revealPosition: MachinePosition?
    let tipRegistrationRevisionID: LearningArtifactRevisionID?
    let postLineFrame: DisplayedFrame?
    let lineStart: MachinePosition?
    let strokeEvidence: DrawingStrokeEvidence?
    let inkObservation: IsolatedInkObservation?
    let inkStatus: String
    let assessment: DrawingTrialAssessment?
    let episode: ExplorationEpisode?
    let completedEpisodes: [ExplorationEpisode]
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
    var cameraCalibrationProposalID: UUID?
    var machineCameraRegistration: MachineCameraRegistration?
    var tipCameraRegistration: TipCameraRegistration?
    var proposedTipCameraRegistration: TipCameraRegistration?
    var sparseTipCalibrationCoordinator = SparseTipCalibrationCoordinator()
    var frozenToolContactSelectionFrame: DisplayedFrame?
    var pendingToolContactEvidence: PendingToolContactEvidence?
    var toolContactPointSelectionRequest: ActionSurfacePointSelectionRequest?
    var selectedToolContactPoint: Point2<CameraPixelSpace>?
    var blacklistedToolContactLocations: Set<BlacklistedToolContactLocation> = []
    var explicitRegistrationCapAnchorEvidence: [MachineCameraCorrespondenceProvenance] = []
    var currentCameraCalibrationPhase: CurrentCameraCalibrationPhase?
    var currentCameraCalibrationFailure: CurrentCameraCalibrationFailure?
    var lastContextualStopAuditRecord: ContextualStopAuditRecord?
    var boundaryActivityRecords: [BoundaryActivityRecord] = []
    var localPreLineBaseline: DisplayedFrame?
    var drawingTrialRevealPosition: MachinePosition?
    var drawingTrialTipRegistrationRevisionID: LearningArtifactRevisionID?
    var drawingTrialObservationRegion: PixelRect?
    var lastProtocolPoseSettlement: ProtocolPoseSettlement?
    var explorationError: String?
    var currentExplorationEpisode: ExplorationEpisode?
    var completedExplorationEpisodes: [ExplorationEpisode] = []
    var explorationPostLineFrame: DisplayedFrame?
    var drawingTrialLineStart: MachinePosition?
    var drawingTrialStrokeEvidence: DrawingStrokeEvidence?
    var lastInkObservation: IsolatedInkObservation?
    var explorationInkStatus = "no isolated-line observation yet"
    var explorationExportPath: String?
    var lastTravelFeedSelection: TravelFeedSelection?
    var drawingTrialAssessment: DrawingTrialAssessment?
    var learningArtifactGraph = LearningDependencyGraph()
    var penAttemptHistory: ExerciseAttemptHistory<PenState>
    var boundaryAttemptHistories:
      [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<
        BoundarySideAttemptEvidence
      >]] = [:]
    var comparisonAttemptHistories:
      [AttemptCompatibility: ExerciseAttemptHistory<DrawingTrialAssessment>] = [:]
    var activeExerciseAttemptID: ExerciseAttemptID?
    var activeExerciseAttemptOwnerID: LearningPathItemID?
    var activeExerciseAttemptMode: ExerciseAttemptMode?
    var restartableExerciseItemID: LearningPathItemID?
    var acceptedArtifactCheckpointStatus: AcceptedArtifactCheckpointStatus = .unavailable
    var parkedAcceptedMachineArtifactCheckpoint: AcceptedMachineArtifactCheckpoint?
    var quarantinedTipCalibrationCheckpoint: AcceptedTipCalibrationCheckpoint?
    var learningAuthorityError: String?
    var observedDrawingTrialStep: ObservedDrawingTrialStep = .chooseIsolatedLinePlan
    var selectedBoundaryDirection: BoundaryDirection = .positiveX
    var selectedLineDirection: BoundaryDirection = .positiveX
    var acceptedAttemptSequence: UInt64 = 0
    var currentDrawingTrialGroup: AttemptGroupIdentity
    var learningEvidenceSessionID = LearningEvidenceSessionID()
    var controllerSessionID = UUID()
    var explorationCoordinateRevision: UInt64 = 0
    var explorationToolPaperRevision: UUID

    init(source: OperatorFrameMode, paperContactPlaneRevision: UUID) {
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
      currentDrawingTrialGroup = AttemptGroupIdentity(
        rawValue: simulated
          ? "simulated-\(UUID().uuidString.lowercased())"
          : UUID().uuidString.lowercased()
      )
      explorationToolPaperRevision = paperContactPlaneRevision
    }
  }

  private enum MotionPriors {
    static let stepMM = "1.0"
    static let feedMMPerMinute = "100"
    /// Finite GRBL wire segment used only for renewal under one logical owner.
    /// Reaching this distance is never a Boundary Discovery result.
    static let boundaryWireSegmentMM = 20.0
  }

  struct MachineActions: Sendable {
    let select: @Sendable (MachineLinkDescriptor) async throws -> RunInterpreterSnapshot
    let snapshot: @Sendable () async -> RunInterpreterSnapshot?
    let requestPassiveProbe: @Sendable () async throws -> PassiveProbeResult
    let activateMotionGuard: @Sendable () async -> MotionGuardActivationOutcome
    let deactivateMotionGuard: @Sendable () async -> Void
    let requestRelativeJog: @Sendable (RelativeJogRequest) async -> MotionOutcome
    let beginRelativeJog: @Sendable (RelativeJogRequest) async -> RelativeJogAdmission
    let requestDrawingStroke: @Sendable (DrawingStrokeRequest) async -> DrawingStrokeOutcome
    let beginDrawingStroke: @Sendable (DrawingStrokeRequest) async -> DrawingStrokeAdmission
    let requestPenActuation: @Sendable (PenCommand) async -> PenOutcome
    let requestBoundaryMotion: @Sendable (BoundaryMotionRequest) async -> BoundaryMotionOutcome
    let beginBoundaryMotion:
      @Sendable (BoundaryMotionRequest, BoundaryMotionRenewalPlanner?) async
        -> BoundaryMotionAdmission
    let requestJogCancel: @Sendable (JogCancelIntent) async -> JogCancelOutcome
    let disconnect: @Sendable () async -> Void
  }

  struct AnnouncementActions: Sendable {
    let announce: @Sendable (String) async -> SpeechAnnouncementOutcome
    let cancelForShutdown: @Sendable () async -> Void
  }

  struct WorkflowTelemetryActions: Sendable {
    let record: @Sendable (WorkflowTelemetryEvent) async -> Void
  }

  struct AcceptedArtifactCheckpointActions: Sendable {
    let load: @Sendable () -> AcceptedArtifactCheckpointLoadResult
    let save: @Sendable (AcceptedMachineArtifactCheckpoint) throws -> Void
    let clear: @Sendable () throws -> Void
  }

  struct AcceptedTipCalibrationCheckpointActions: Sendable {
    let load: @Sendable () -> AcceptedTipCalibrationCheckpointLoadResult
    let save: @Sendable (AcceptedTipCalibrationCheckpoint) throws -> Void
    let clear: @Sendable () throws -> Void
  }

  struct CameraActions: Sendable {
    let discover: @Sendable () async -> CameraCaptureSnapshot
    let select: @Sendable (CameraDeviceID) async throws -> CameraCaptureSnapshot
    let start: @Sendable () async -> CameraCaptureSnapshot
    let stop: @Sendable () async -> CameraCaptureSnapshot
    let restart: @Sendable () async -> CameraCaptureSnapshot
    let snapshot: @Sendable () async -> CameraCaptureSnapshot
    let frames: @Sendable () async -> AsyncStream<DisplayedFrame>
    let inspectScene: @Sendable (UInt64) async throws -> LiveSceneInspection?
    let captureFrame: @Sendable (UInt64) async throws -> DisplayedFrame?
    let setSceneAnalysisRegion: @Sendable (PixelRect?) async -> Void
    let setAutomaticInspection:
      @Sendable (VisionAnalysisCadence?) async
        -> PlotterSceneAnalysisSnapshot
    let analysisUpdates: @Sendable () async -> AsyncStream<PlotterSceneAnalysisSnapshot>
    let observeIsolatedInk:
      @Sendable (IsolatedInkObservationRequest) async
        -> IsolatedInkObservationOutcome
  }

  var visibleLayers = Set(CanvasLayer.allCases)
  private(set) var visionAnalysisCadence = VisionAnalysisCadence.twoFPS
  private(set) var videoAnalysisRegionLock: VideoAnalysisRegionLock?
  var frameMode: OperatorFrameMode = .live
  // String-backed numeric inputs preserve partially typed values and keep X/Y
  // independent. Runtime value constructors and MachineController own validity.
  var xStepText = MotionPriors.stepMM
  var yStepText = MotionPriors.stepMM
  var feedText = MotionPriors.feedMMPerMinute

  private(set) var serialDevices: [MachineLinkDescriptor] = []
  private(set) var selectedSerialDevice: MachineLinkDescriptor?
  private(set) var passiveProbeResult: PassiveProbeResult?
  private(set) var machineSnapshot: RunInterpreterSnapshot?
  private(set) var machineError: String?
  private(set) var controllerConnectionActionInProgress = false
  private(set) var passiveProbeInProgress = false
  private(set) var jogRequestInProgress = false
  private(set) var penRequestInProgress = false
  private(set) var frameModeSwitchInProgress = false
  private(set) var motionGuardActivationInProgress = false
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
  private(set) var cameraOverlays: [CameraOverlayMeasurement] = []
  private(set) var cameraError: String?
  private(set) var visionError: String?
  private(set) var scopedVisionAnalysisActive = false
  private(set) var visionAnalysisSnapshot: PlotterSceneAnalysisSnapshot = .stopped
  private(set) var lastSceneMeasurement: PlotterSceneMeasurement?
  private(set) var simulatorEvidenceLabel = SimulatedOverlaySceneContent.evidenceLabel
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
    [ExerciseAttemptID: BoundarySideAttemptEvidence] {
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
  private(set) var cameraCalibrationProposalID: UUID? {
    get { activeLearningSession.cameraCalibrationProposalID }
    set { activeLearningSession.cameraCalibrationProposalID = newValue }
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
  private(set) var frozenToolContactSelectionFrame: DisplayedFrame? {
    get { activeLearningSession.frozenToolContactSelectionFrame }
    set { activeLearningSession.frozenToolContactSelectionFrame = newValue }
  }
  private var pendingToolContactEvidence: PendingToolContactEvidence? {
    get { activeLearningSession.pendingToolContactEvidence }
    set { activeLearningSession.pendingToolContactEvidence = newValue }
  }
  private(set) var toolContactPointSelectionRequest: ActionSurfacePointSelectionRequest? {
    get { activeLearningSession.toolContactPointSelectionRequest }
    set { activeLearningSession.toolContactPointSelectionRequest = newValue }
  }
  private(set) var selectedToolContactPoint: Point2<CameraPixelSpace>? {
    get { activeLearningSession.selectedToolContactPoint }
    set { activeLearningSession.selectedToolContactPoint = newValue }
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
    get { activeLearningSession.localPreLineBaseline }
    set { activeLearningSession.localPreLineBaseline = newValue }
  }
  private(set) var drawingTrialRevealPosition: MachinePosition? {
    get { activeLearningSession.drawingTrialRevealPosition }
    set { activeLearningSession.drawingTrialRevealPosition = newValue }
  }
  private(set) var drawingTrialTipRegistrationRevisionID: LearningArtifactRevisionID? {
    get { activeLearningSession.drawingTrialTipRegistrationRevisionID }
    set { activeLearningSession.drawingTrialTipRegistrationRevisionID = newValue }
  }
  private(set) var drawingTrialObservationRegion: PixelRect? {
    get { activeLearningSession.drawingTrialObservationRegion }
    set { activeLearningSession.drawingTrialObservationRegion = newValue }
  }
  private(set) var lastProtocolPoseSettlement: ProtocolPoseSettlement? {
    get { activeLearningSession.lastProtocolPoseSettlement }
    set { activeLearningSession.lastProtocolPoseSettlement = newValue }
  }
  private(set) var explorationError: String? {
    get { activeLearningSession.explorationError }
    set { activeLearningSession.explorationError = newValue }
  }
  private(set) var currentExplorationEpisode: ExplorationEpisode? {
    get { activeLearningSession.currentExplorationEpisode }
    set { activeLearningSession.currentExplorationEpisode = newValue }
  }
  private(set) var completedExplorationEpisodes: [ExplorationEpisode] {
    get { activeLearningSession.completedExplorationEpisodes }
    set { activeLearningSession.completedExplorationEpisodes = newValue }
  }
  private(set) var explorationPostLineFrame: DisplayedFrame? {
    get { activeLearningSession.explorationPostLineFrame }
    set { activeLearningSession.explorationPostLineFrame = newValue }
  }
  private(set) var drawingTrialLineStart: MachinePosition? {
    get { activeLearningSession.drawingTrialLineStart }
    set { activeLearningSession.drawingTrialLineStart = newValue }
  }
  private(set) var drawingTrialStrokeEvidence: DrawingStrokeEvidence? {
    get { activeLearningSession.drawingTrialStrokeEvidence }
    set { activeLearningSession.drawingTrialStrokeEvidence = newValue }
  }
  private(set) var lastInkObservation: IsolatedInkObservation? {
    get { activeLearningSession.lastInkObservation }
    set { activeLearningSession.lastInkObservation = newValue }
  }
  private(set) var explorationInkStatus: String {
    get { activeLearningSession.explorationInkStatus }
    set { activeLearningSession.explorationInkStatus = newValue }
  }
  private(set) var explorationExportPath: String? {
    get { activeLearningSession.explorationExportPath }
    set { activeLearningSession.explorationExportPath = newValue }
  }
  private var activeExplorationOperation: ActiveExplorationOperation?
  private(set) var lastAnnouncementResultText = "No announcement has run."
  private(set) var lastTravelFeedSelection: TravelFeedSelection? {
    get { activeLearningSession.lastTravelFeedSelection }
    set { activeLearningSession.lastTravelFeedSelection = newValue }
  }
  private(set) var drawingTrialAssessment: DrawingTrialAssessment? {
    get { activeLearningSession.drawingTrialAssessment }
    set { activeLearningSession.drawingTrialAssessment = newValue }
  }
  private(set) var learningArtifactGraph: LearningDependencyGraph {
    get { activeLearningSession.learningArtifactGraph }
    set { activeLearningSession.learningArtifactGraph = newValue }
  }
  private(set) var penAttemptHistory: ExerciseAttemptHistory<PenState> {
    get { activeLearningSession.penAttemptHistory }
    set { activeLearningSession.penAttemptHistory = newValue }
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
    get { activeLearningSession.comparisonAttemptHistories }
    set { activeLearningSession.comparisonAttemptHistories = newValue }
  }
  private(set) var activeExerciseAttemptID: ExerciseAttemptID? {
    get { activeLearningSession.activeExerciseAttemptID }
    set { activeLearningSession.activeExerciseAttemptID = newValue }
  }
  private(set) var activeExerciseAttemptOwnerID: LearningPathItemID? {
    get { activeLearningSession.activeExerciseAttemptOwnerID }
    set { activeLearningSession.activeExerciseAttemptOwnerID = newValue }
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
  private(set) var learningAuthorityError: String? {
    get { activeLearningSession.learningAuthorityError }
    set { activeLearningSession.learningAuthorityError = newValue }
  }

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let announcementActions: AnnouncementActions?
  /// These ports are capabilities of the LIVE learning session only. The
  /// active accessors deliberately return nil for SIMULATED before any
  /// workflow can load, save, or clear physical durable authority.
  @ObservationIgnored private let liveAcceptedArtifactCheckpointActions:
    AcceptedArtifactCheckpointActions?
  @ObservationIgnored private let liveAcceptedTipCalibrationCheckpointActions:
    AcceptedTipCalibrationCheckpointActions?
  private var activeAcceptedArtifactCheckpointActions: AcceptedArtifactCheckpointActions? {
    frameMode == .live ? liveAcceptedArtifactCheckpointActions : nil
  }
  private var activeAcceptedTipCalibrationCheckpointActions:
    AcceptedTipCalibrationCheckpointActions?
  {
    frameMode == .live ? liveAcceptedTipCalibrationCheckpointActions : nil
  }
  @ObservationIgnored private let workflowTelemetryActions: WorkflowTelemetryActions?
  @ObservationIgnored private let simulatedLearningRuntime: SimulatedLearningRuntime
  @ObservationIgnored private var simulatedExecutionPacing: any SimulatedLearningExecutionPacing
  @ObservationIgnored private let serialDeviceDiscovery: @Sendable () -> [MachineLinkDescriptor]
  @ObservationIgnored private let persistSelectedSerialIdentifier: @Sendable (String) -> Void
  @ObservationIgnored private let nowNanoseconds: @Sendable () -> UInt64
  @ObservationIgnored private var boundaryAtomicCommitFailurePoints:
    Set<BoundaryAtomicCommitFailurePoint>
  @ObservationIgnored private var frameTask: Task<Void, Never>?
  @ObservationIgnored private var visionUpdateTask: Task<Void, Never>?
  private var learningEvidenceSessionID: LearningEvidenceSessionID {
    activeLearningSession.learningEvidenceSessionID
  }
  private var controllerSessionID: UUID {
    get { activeLearningSession.controllerSessionID }
    set { activeLearningSession.controllerSessionID = newValue }
  }
  private var explorationCoordinateRevision: UInt64 {
    get { activeLearningSession.explorationCoordinateRevision }
    set { activeLearningSession.explorationCoordinateRevision = newValue }
  }
  private var explorationToolPaperRevision: UUID {
    get { activeLearningSession.explorationToolPaperRevision }
    set { activeLearningSession.explorationToolPaperRevision = newValue }
  }
  @ObservationIgnored private let persistPaperContactPlaneRevision:
    @Sendable (PaperContactPlaneRevision) -> Void
  @ObservationIgnored private var boundaryMotionTask: Task<Void, Never>?
  @ObservationIgnored private var boundaryApproachVisionTasks:
    [ExerciseAttemptID: Task<Void, Never>] = [:]
  @ObservationIgnored private var boundaryApproachAdvisories:
    [ExerciseAttemptID: BoundaryApproachAdvisory] = [:]
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
    get { activeLearningSession.activeExerciseAttemptMode }
    set { activeLearningSession.activeExerciseAttemptMode = newValue }
  }
  private var acceptedAttemptSequence: UInt64 {
    get { activeLearningSession.acceptedAttemptSequence }
    set { activeLearningSession.acceptedAttemptSequence = newValue }
  }
  @ObservationIgnored private var lastSimulatedProtocolCaptureNanoseconds: UInt64 = 0
  private var currentDrawingTrialGroup: AttemptGroupIdentity {
    get { activeLearningSession.currentDrawingTrialGroup }
    set { activeLearningSession.currentDrawingTrialGroup = newValue }
  }
  private var parkedAcceptedMachineArtifactCheckpoint: AcceptedMachineArtifactCheckpoint? {
    get { activeLearningSession.parkedAcceptedMachineArtifactCheckpoint }
    set { activeLearningSession.parkedAcceptedMachineArtifactCheckpoint = newValue }
  }

  init(
    machineActions: MachineActions? = nil,
    cameraActions: CameraActions? = nil,
    announcementActions: AnnouncementActions? = nil,
    acceptedArtifactCheckpointActions: AcceptedArtifactCheckpointActions? = nil,
    acceptedTipCalibrationCheckpointActions: AcceptedTipCalibrationCheckpointActions? = nil,
    tipCalibrationSemanticIdentities: TipCalibrationSemanticIdentityState = .ephemeral(),
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
    nowNanoseconds: @escaping @Sendable () -> UInt64 = {
      UInt64(ProcessInfo.processInfo.systemUptime * 1_000_000_000)
    },
    boundaryAtomicCommitFailurePoints: Set<BoundaryAtomicCommitFailurePoint> = []
  ) {
    liveLearningSession = LearningSessionState(
      source: .live,
      paperContactPlaneRevision: tipCalibrationSemanticIdentities.paperContactPlane.rawValue
    )
    simulatedLearningSession = LearningSessionState(
      source: .simulated,
      paperContactPlaneRevision: UUID()
    )
    self.simulatedExecutionPacing = simulatedExecutionPacing
    self.machineActions = machineActions
    self.cameraActions = cameraActions
    self.announcementActions = announcementActions
    liveAcceptedArtifactCheckpointActions = acceptedArtifactCheckpointActions
    liveAcceptedTipCalibrationCheckpointActions = acceptedTipCalibrationCheckpointActions
    machineGeometryIdentity = tipCalibrationSemanticIdentities.machineGeometry
    toolAssemblyRevision = tipCalibrationSemanticIdentities.toolAssembly
    penContactProfileRevision = tipCalibrationSemanticIdentities.penContactProfile
    cameraMountRevision = tipCalibrationSemanticIdentities.cameraMountRevision
    cameraReframingRevision = tipCalibrationSemanticIdentities.cameraReframingRevision
    self.persistPaperContactPlaneRevision = persistPaperContactPlaneRevision
    self.workflowTelemetryActions = workflowTelemetryActions
    self.simulatedLearningRuntime = simulatedLearningRuntime
    self.serialDevices = serialDevices
    self.serialDeviceDiscovery = serialDeviceDiscovery
    self.persistSelectedSerialIdentifier = persistSelectedSerialIdentifier
    rememberedSerialDeviceIdentifier = loadSelectedSerialIdentifier()
    self.nowNanoseconds = nowNanoseconds
    self.boundaryAtomicCommitFailurePoints = boundaryAtomicCommitFailurePoints
    if let rememberedSerialDeviceIdentifier {
      selectedSerialDevice = serialDevices.first {
        $0.identifier == rememberedSerialDeviceIdentifier
      }
    }
    if let acceptedArtifactCheckpointActions {
      switch acceptedArtifactCheckpointActions.load() {
      case .absent:
        acceptedArtifactCheckpointStatus = .unavailable
      case .loaded(let checkpoint):
        parkedAcceptedMachineArtifactCheckpoint = checkpoint
        acceptedArtifactCheckpointStatus = .quarantined(
          sideCount: checkpoint.boundarySideAggregates.count
        )
      case .rejected(let reason):
        acceptedArtifactCheckpointStatus = .rejected(reason)
      }
    }
    if let acceptedTipCalibrationCheckpointActions,
      case .quarantined(let checkpoint) = acceptedTipCalibrationCheckpointActions.load()
    {
      // Durable tip evidence is intentionally quarantined. It cannot restore
      // graph or operational authority without an explicit current revalidation.
      quarantinedTipCalibrationCheckpoint = checkpoint
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
    let visibleKinds = Set(visibleLayers.map(\.overlayKind))
    let surfaceFrame = frozenToolContactSelectionFrame ?? displayedFrame
    let sparseMarkRegion = surfaceFrame.flatMap(sparseTipMarkPresentationRegion)
    let fittedRegion = sparseMarkRegion ?? surfaceFrame.flatMap(learnedBoundsPresentationRegion)
    let viewportContext = surfaceFrame.map {
      ActionSurfaceViewportContext(
        source: $0.source,
        cameraConfigurationID: $0.frame.cameraConfigurationID,
        fittedRegion: fittedRegion,
        preferredInitialZoom: sparseMarkRegion == nil ? 0 : 1,
        presentationRevisionToken: toolContactPointSelectionRequest.map {
          "sparse-tip-mark-focus-\($0.frame.frameID.rawValue)"
        } ?? machineCameraRegistration.map {
          "machine-cap-\($0.correspondenceFrameIDs.map(\.rawValue).sorted().joined(separator: "-"))"
        } ?? "post-boundary-presentation"
      )
    }
    let tipPresentation: ActionSurfaceTipPresentation =
      if selectedToolContactPoint != nil, let selectedToolContactPoint {
        .selected(
          click: selectedToolContactPoint,
          pointingUncertaintyPixels: try! Vector2(dx: 1.5, dy: 1.5),
          prediction: currentTipPredictionForPendingMark,
          residualPixels: currentTipPredictionForPendingMark.map {
            $0.distance(to: selectedToolContactPoint)
          }
        )
      } else if toolContactPointSelectionRequest != nil {
        .awaitingClick("Click the center of the new black circle")
      } else if tipCameraRegistration != nil {
        .calibrated(prediction: nil)
      } else {
        .notCalibrated
      }
    return ActionSurfacePresentation(
      displayedFrame: surfaceFrame,
      overlays: cameraOverlays.filter {
        visibleKinds.contains($0.provenance.kind)
          && !(toolContactPointSelectionRequest != nil && selectedToolContactPoint == nil
            && ($0.provenance.kind == .modelPrediction || $0.provenance.kind == .residual))
      },
      simulatedAnnotations: simulatedAnnotations,
      simulatedViewportID: simulatedViewportID,
      simulatedAnnotationsAreVisible: simulatedAnnotationsAreVisible,
      viewportContext: viewportContext,
      analysisRegionIsLocked: surfaceFrame.map {
        videoAnalysisRegionLock?.matches($0) == true
      } ?? false,
      pointSelectionRequest: toolContactPointSelectionRequest,
      tipPresentation: tipPresentation
    )
  }

  private var currentTipPredictionForPendingMark: Point2<CameraPixelSpace>? {
    guard let pendingToolContactEvidence else { return nil }
    let provisional = try? machineCameraRegistration.map { machineRegistration in
      try TipCalibrationModelSelection.provisionalConstantCandidate(
        acceptedObservations: sparseTipCalibrationCoordinator.acceptedObservations,
        capCameraFromMachine: machineRegistration.fit.cameraFromMachine
      )
    }
    let transform =
      proposedTipCameraRegistration?.cameraFromMachine
      ?? tipCameraRegistration?.cameraFromMachine
      ?? provisional
    return (try? transform?.applying(to: pendingToolContactEvidence.actualSettledPosition.point))
      ?? pendingToolContactEvidence.capMapPredictionAtMark
  }

  private func sparseTipMarkPresentationRegion(_ frame: DisplayedFrame) -> PixelRect? {
    guard toolContactPointSelectionRequest != nil,
      let center = pendingToolContactEvidence?.preMarkCapEstimate.point
    else { return nil }
    let width = max(96, frame.frame.width / 3)
    let height = max(96, frame.frame.height / 3)
    let x = min(
      max(0, Int(center.x.rounded()) - width / 2),
      max(0, frame.frame.width - width)
    )
    let y = min(
      max(0, Int(center.y.rounded()) - height / 2),
      max(0, frame.frame.height - height)
    )
    return cameraFrameIntersection(
      PixelRect(x: x, y: y, width: width, height: height),
      frameWidth: frame.frame.width,
      frameHeight: frame.frame.height
    )
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

  var sceneMeasurementText: String {
    guard let measurement = lastSceneMeasurement else { return "not measured" }
    let cap =
      measurement.cap.map {
        String(format: "cap %.0f px · %.2f", Double($0.pixelCount), $0.confidence)
      } ?? "cap not found"
    let top =
      measurement.topFrameSide.map {
        String(format: "top %.1f px · %.2f", $0.rmsResidualPixels, $0.confidence)
      } ?? "top not found"
    let right =
      measurement.rightFrameSide.map {
        String(format: "right %.1f px · %.2f", $0.rmsResidualPixels, $0.confidence)
      } ?? "right not found"
    let frame =
      measurement.drawingFrame.map {
        String(format: "frame inferred · %.2f", $0.confidence)
      } ?? "frame unavailable"
    let armature =
      measurement.armature.map {
        String(format: "armature inferred · %.2f", $0.confidence)
      } ?? "armature unavailable"
    return "\(cap) · \(top) · \(right) · \(frame) · \(armature)"
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
    guard let lock = videoAnalysisRegionLock else { return "Unlocked · current viewport" }
    let region = lock.region
    return "x \(region.x), y \(region.y), \(region.width) × \(region.height) px · locked"
  }

  func overlaySummary(for layer: CanvasLayer) -> String {
    let matching = cameraOverlays.filter { $0.provenance.kind == layer.overlayKind }
    guard !matching.isEmpty else { return "not present on current frame" }
    let sources = Set(matching.map(\.provenance.source.rawValue)).sorted().joined(separator: ", ")
    return "\(matching.count) · \(sources)"
  }

  var currentOperationText: String {
    if frameMode == .simulated {
      guard let operation = simulatedLearningSnapshot?.currentOperation else {
        return "simulated idle"
      }
      return switch operation.kind {
      case .manualJog: "simulated manual jog"
      case .boundary: "simulated Boundary Discovery motion"
      case .drawing: "simulated isolated drawing stroke"
      }
    }
    guard let operation = machineSnapshot?.currentOperation else { return "none" }
    return switch operation {
    case .idle: "idle"
    case .passiveProbe: "controller inspection"
    case .relativeJog: "relative jog"
    case .boundaryMotion: "Boundary Discovery motion"
    case .drawingStroke: "isolated drawing stroke"
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
      || motionGuardActivationInProgress
    {
      return "Wait for the current controller operation."
    }
    return nil
  }

  var motionGuardActivationUnavailableReason: String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if motionGuardActivationInProgress { return "Enable Motion is in progress." }
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
      || jogCancelRequestInProgress || motionGuardActivationInProgress
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
    get { activeLearningSession.observedDrawingTrialStep }
    set { activeLearningSession.observedDrawingTrialStep = newValue }
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
    if !penInteractionCompleted { return .penInteraction }
    if relevantBoundaryObservationCount < BoundaryDirection.allCases.count
      || centerArrivalPosition == nil
    {
      return .pairedBoundaryDiscoveryAndCentering
    }
    if machineCameraRegistration == nil { return .calibrateCameraAndVisibleCap }
    return .calibratePenContactFromSparseMarks
  }

  var currentLearningPathItemID: LearningPathItemID {
    if let activeExerciseAttemptOwnerID { return activeExerciseAttemptOwnerID }
    if let restartableExerciseItemID { return restartableExerciseItemID }
    if !controllerSessionEstablished { return .stage(.connect) }
    if !motionAuthorizationEnabled { return .stage(.enableMotion) }
    if !penInteractionCompleted { return .humanGuidedDiscovery(.penInteraction) }
    if relevantBoundaryObservationCount < BoundaryDirection.allCases.count
      || centerArrivalPosition == nil
    {
      return .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    }
    if tipCameraRegistration == nil {
      return .humanGuidedDiscovery(humanGuidedDiscoveryCurrentStep)
    }
    if drawingTrialAssessment == nil {
      return .observedDrawingTrial(observedDrawingTrialStep)
    }
    return .stage(.adaptiveDrawing)
  }

  var learningPathItemPresentations: [LearningPathItemPresentation] {
    LearningPathItemID.navigationOrder.map { itemID in
      LearningPathItemPresentation(
        id: itemID,
        status: learningPathStatus(for: itemID),
        summary: learningPathSummary(for: itemID),
        isRepeatable: itemIsRepeatable(itemID)
      )
    }
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

    if plan.removesDurableTipCheckpoint {
      do {
        try activeAcceptedTipCalibrationCheckpointActions?.clear()
      } catch {
        learningAuthorityError =
          "The durable accepted-tip checkpoint could not be cleared: \(error)"
        return false
      }
    }
    if plan.removesDurableMachineCheckpoint {
      do {
        try activeAcceptedArtifactCheckpointActions?.clear()
      } catch {
        learningAuthorityError =
          "The durable accepted-machine checkpoint could not be cleared: \(error)"
        return false
      }
    }

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

    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
    restartableExerciseItemID = nil
    explorationError = nil
    learningAuthorityError = nil

    if plan.removesDurableMachineCheckpoint {
      parkedAcceptedMachineArtifactCheckpoint = nil
      acceptedArtifactCheckpointStatus = .cleared
    }
    if plan.removesDurableTipCheckpoint {
      quarantinedTipCalibrationCheckpoint = nil
    }
    return true
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
    if currentLearningPathItemID == .stage(.adaptiveDrawing) {
      endIndex = LearningPathItemID.learningExerciseOrder.index(
        before:
          LearningPathItemID.learningExerciseOrder.endIndex)
    } else if let currentAnchor = currentLearningPathItemID.learningRewindAnchor,
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
        && activeAcceptedArtifactCheckpointActions != nil,
      removesDurableTipCheckpoint:
        source == .live && anchorIndex <= tipIndex
        && activeAcceptedTipCalibrationCheckpointActions != nil,
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
    case .linePlan:
      .observedDrawingTrial(.chooseIsolatedLinePlan)
    case .localPreLineBaseline:
      .observedDrawingTrial(.captureLocalPreLineBaseline)
    case .lineExecution:
      .observedDrawingTrial(.drawIsolatedLine)
    case .postLineFrame, .inkObservation, .residual:
      .observedDrawingTrial(.revealAndObserveNewInk)
    case .comparison:
      .observedDrawingTrial(.compareIntendedAndObservedGeometry)
    }
  }

  private func hasVacatablePayload(atOrAfter anchorIndex: Int) -> Bool {
    if currentLearningPathItemID == .stage(.adaptiveDrawing) {
      return true
    }
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
      cameraCalibrationAnchorFrame != nil || cameraCalibrationProposalID != nil
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
      currentExplorationEpisode != nil || drawingTrialLineStart != nil
        || localPreLineBaseline != nil || drawingTrialStrokeEvidence != nil
        || explorationPostLineFrame != nil || drawingTrialAssessment != nil
        || !comparisonAttemptHistories.isEmpty
    {
      return true
    }
    return false
  }

  var contextualStopPresentation: ContextualStopPresentation? {
    guard let activeStopTarget, stopDispositionLatch == nil else { return nil }
    if case .pairedBoundary(_, let transactionID, _, _, let direction) = activeStopTarget {
      let sequenceID = sequenceID(for: direction)
      guard discoveryTransactions[sequenceID]?.id == transactionID,
        case .awaitContextualStop(direction) = discoveryTransactions[sequenceID]?.currentStep?
          .action
      else { return nil }
    }
    let detail =
      switch activeStopTarget {
      case .pairedBoundary(_, _, _, _, let direction):
        "Stop \(direction.displayName) Boundary Discovery, wait for Idle, then commit its final controller position."
      case .manualJog:
        "Stop the active manual jog and wait for Idle."
      case .exerciseMotion(_, _, _, let action):
        "Stop \(action) and wait for the original owner to settle. No training artifact is accepted."
      case .drawingTrial:
        "Stop the drawing trial; the controller owns its single Pen Up cancellation."
      case .sparseTipMark:
        "Stop the active calibration circle. Possible ink will blacklist this physical location; it will not be redrawn automatically."
      }
    return ContextualStopPresentation(
      capabilityID: activeStopTarget.capabilityID,
      title: "Stop",
      detail: detail
    )
  }

  var manualMotionPresentation: ManualMotionPresentation {
    let stopAction: ContextualStopActionPresentation?
    if let target = activeStopTarget,
      case .manualJog = target,
      stopDispositionLatch == nil
    {
      stopAction = ContextualStopActionPresentation(
        capabilityID: target.capabilityID,
        title: "Stop Manual Jog",
        detail: "Stop only this manual jog and wait for its original owner to settle."
      )
    } else {
      stopAction = nil
    }
    return ManualMotionPresentation(
      stopAction: stopAction,
      jogUnavailableReason: motionUnavailableReason
    )
  }

  func stopManualJog(capabilityID: ContextualStopCapabilityID) async {

    guard let target = activeStopTarget,
      target.capabilityID == capabilityID,
      case .manualJog = target
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
    if let machineError { return .needsAttention(machineError) }
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
    videoAnalysisRegionLock = region.map {
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
    exerciseActionStrip(for: currentLearningPathItemID)
  }

  func selectedOperatorActionPresentation(
    for itemID: LearningPathItemID
  ) -> OperatorActionPresentation {
    switch itemID {
    case .stage(let stage):
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: stage.number,
        title: stage.title,
        status: learningPathStatus(for: itemID),
        instructions: [.text(learningPathSummary(for: itemID))],
        expectedObservation: stageExpectedObservation(stage),
        evidence: stageEvidence(stage),
        activity: operationActivityPresentation(for: itemID, transaction: nil),
        subsystemStatuses: subsystemStatusPresentations(for: itemID, transaction: nil),
        actionStrip: exerciseActionStrip(for: itemID)
      )

    case .humanGuidedDiscovery(let discoveryStep):
      let sequenceID = discoverySequenceID(for: discoveryStep)
      let transaction = sequenceID.flatMap { discoveryTransactions[$0] }
      let activeStep = transaction?.currentStep
      let feedSelection: TravelFeedSelection? =
        switch activeStep?.action {
        case .startBoundaryJog(let direction):
          travelFeedSelection(
            for: boundaryFeedVector(direction)
          )
        default: nil
        }
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: discoveryStep.stepNumber,
        title: discoveryStep.title,
        status: learningPathStatus(for: itemID),
        participant: activeStep?.participant.displayName,
        instructions: activeStep.map { discoveryInstructionFragments($0.action) }
          ?? discoveryReviewInstructions(discoveryStep),
        expectedObservation: activeStep.map {
          discoveryExpectationFragments($0.expectedEvent)
        } ?? discoveryReviewExpectation(discoveryStep),
        question: activeStep.flatMap { discoveryQuestionPresentation($0.action) },
        timeline: transaction.flatMap { transaction in
          guard transaction.state == .active,
            transaction.completedStepCount < transaction.definition.steps.count
          else { return nil }
          return ExerciseTimelinePresentation(
            position: transaction.completedStepCount + 1,
            total: transaction.definition.steps.count,
            currentLabel: transaction.currentStep?.id ?? discoveryStep.title
          )
        },
        evidence: discoveryEvidence(transaction) + protocolEvidence(for: discoveryStep),
        activity: operationActivityPresentation(for: itemID, transaction: transaction),
        subsystemStatuses: subsystemStatusPresentations(
          for: itemID,
          transaction: transaction
        ),
        actionStrip: exerciseActionStrip(for: itemID),
        requestedFeedMMPerMinute: feedSelection?.requestedFeedMMPerMinute,
        feedSource: feedSelection?.source
      )

    case .observedDrawingTrial(let trialStep):
      return OperatorActionPresentation(
        itemID: itemID,
        stepNumber: trialStep.stepNumber,
        title: trialStep.title,
        status: learningPathStatus(for: itemID),
        participant: drawingTrialParticipant(for: trialStep),
        instructions: drawingTrialInstructionFragments(for: trialStep),
        expectedObservation: drawingTrialExpectationFragments(for: trialStep),
        timeline: ExerciseTimelinePresentation(
          position: trialStep.rawValue,
          total: ObservedDrawingTrialStep.allCases.count,
          currentLabel: observedDrawingTrialStep.title
        ),
        evidence: drawingTrialEvidence(for: trialStep),
        activity: operationActivityPresentation(for: itemID, transaction: nil),
        subsystemStatuses: subsystemStatusPresentations(for: itemID, transaction: nil),
        actionStrip: exerciseActionStrip(for: itemID),
        requestedFeedMMPerMinute: lastTravelFeedSelection?.requestedFeedMMPerMinute,
        feedSource: lastTravelFeedSelection?.source
      )
    }
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
    if case .selectDirection(let purpose, let direction) = kind {
      guard !hasShutdown,
        let selection = exerciseActionStrip(for: ownerID)?.directionSelection,
        selection.purpose == purpose,
        selection.options.contains(direction)
      else { return }
      switch purpose {
      case .boundary: selectBoundaryDirection(direction)
      case .linePlan: selectedLineDirection = direction
      }
      return
    }
    guard !hasShutdown,
      let strip = exerciseActionStrip(for: ownerID),
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
      activeExerciseAttemptMode = .replacement
      await beginPairedBoundarySide(direction)
    case .recordAnotherBoundaryAttempt(let direction):
      guard ownerID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering) else {
        return
      }
      selectedBoundaryDirection = direction
      activeExerciseAttemptMode = .additional
      await beginPairedBoundarySide(direction)
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
    case .createNextSparseTipMark:
      await createNextSparseTipMark()
    case .reClickSparseTipFrame:
      reClickSparseTipFrame()
    case .acceptSparseTipMark:
      acceptSparseTipMark()
    case .revalidateTipCalibrationCheckpoint:
      await revalidateTipCalibrationCheckpoint()
    case .acceptTipCalibration:
      acceptTipCalibration()
    case .rejectTipCalibration:
      rejectTipCalibration()
    case .paperReplaced:
      await recordPaperReplaced()
    case .chooseIsolatedLinePlan(let direction):
      selectedLineDirection = direction
      await performCurrentLearningPathAction()
    case .captureLocalPreLineBaseline:
      await performCurrentLearningPathAction()
    case .moveToLineStart:
      await performCurrentLearningPathAction()
    case .drawIsolatedLine:
      await performCurrentLearningPathAction()
    case .revealAndObserveNewInk:
      await performCurrentLearningPathAction()
    case .recordDrawingTrialAssessment(let assessment):
      guard ownerID == .observedDrawingTrial(.compareIntendedAndObservedGeometry) else { return }
      await recordDrawingTrialAssessment(assessment)
    }
  }

  func beginPenInteraction() async {
    guard discoveryStartUnavailableReason(for: .penInteraction) == nil else { return }
    beginExerciseAttempt(
      ownerID: .humanGuidedDiscovery(.penInteraction),
      mode: activeExerciseAttemptMode ?? .normal
    )
    await startDiscoverySequence(.penInteraction)
  }

  func beginPairedBoundarySide(_ direction: BoundaryDirection) async {
    let sequenceID = sequenceID(for: direction)
    let directionIsAdmissible =
      if activeExerciseAttemptMode == .replacement
        || activeExerciseAttemptMode == .additional
      {
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
      mode: activeExerciseAttemptMode ?? .normal
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
          action: "Move to Estimated Center"
        )
        _ = recordProtocolPoseSettlement(
          action: "Move to Estimated Center",
          target: destination,
          actual: final,
          toleranceMM: ControllerPositionAcceptancePolicy.toleranceMM
        )
        guard ControllerPositionAcceptancePolicy.accepts(final, target: destination) else {
          let residual = lastProtocolPoseSettlement?.residualMM ?? .infinity
          throw LearningPathOperationError.controllerFailed(
            String(
              format:
                "Center travel settled %.3f mm from the target, outside the %.3f mm tolerance. "
                + "The four accepted boundaries remain current; Retry Center Arrival "
                + "recomputes only the remaining delta.",
              residual,
              ControllerPositionAcceptancePolicy.toleranceMM
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
    cameraOverlays = [
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
          let point = cameraOverlays.compactMap({ overlay -> Point2<CameraPixelSpace>? in
            guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
            else { return nil }
            return point
          }).first,
          let armatureBounds = cameraOverlays.compactMap({
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
        guard let cameraActions,
          let inspection = try await cameraActions.inspectScene(
            frame.frame.captureNanoseconds - 1
          ),
          let cap = inspection.measurement.cap
        else {
          throw LearningPathOperationError.requiredState("A measured tool component is required.")
        }
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
        cameraOverlays = inspection.measurement.overlays
      }
      cameraCalibrationAnchorFrame = registrationFrame
      cameraCalibrationReferencePosition = targetMachinePosition
      cameraCalibrationReferenceCapAnchor = try ToolCapAnchorEstimate(
        componentCentroid: centroid,
        componentBounds: bounds,
        confidence: confidence,
        estimatorRevision: "green-cap-bottom-center-anchor-v2",
        source: registrationFrame.source,
        frameID: registrationFrame.frame.id,
        cameraConfigurationID: registrationFrame.frame.cameraConfigurationID
      )
      proposedMachineCameraRegistration = nil
      cameraCalibrationProposalID = nil
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

  private func compatibleRegistrationCapAnchorEvidence(
    for frame: DisplayedFrame
  ) -> [MachineCameraCorrespondenceProvenance] {
    explicitRegistrationCapAnchorEvidence.filter {
      $0.source == frame.source
        && $0.cameraConfigurationID == frame.frame.cameraConfigurationID
        && $0.controllerSessionID == controllerSessionID
        && $0.coordinateRevision == explorationCoordinateRevision
        && $0.capAnchorEstimatorRevision == "green-cap-bottom-center-anchor-v2"
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
        estimatorRevision: "five-cap-affine-three-fit-two-holdout-v1",
        uncertaintyPixels: max(finalFit.maximumErrorPixels, holdoutResiduals.max() ?? 0),
        applicabilityRectangle: applicabilityRectangle,
        applicabilityDerivation: .boundaryEnvelopeInsetAndSymmetricallyReduced(
          safetyMarginMM: CurrentCameraCalibrationPlan.safetyMarginMM,
          maximumHalfSpanMM: CurrentCameraCalibrationPlan.maximumUnprovenHalfSpanMM
        )
      )
      proposedMachineCameraRegistration = registration
      cameraCalibrationProposalID = UUID()
      explorationError = nil
      return true
    } catch {
      proposedMachineCameraRegistration = nil
      cameraCalibrationProposalID = nil
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
      cameraCalibrationProposalID = nil
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
          action: "Current-Camera Calibration Sample \(sampleIndex + 1) of 5"
        )
        try requireCalibrationContinuation()
        guard
          recordProtocolPoseSettlement(
            action: "Current-Camera Calibration Sample \(sampleIndex + 1) of 5",
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
        action: "Return from Current-Camera Calibration"
      )
      try requireCalibrationContinuation()
      guard
        recordProtocolPoseSettlement(
          action: "Return from Current-Camera Calibration",
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
      cameraCalibrationProposalID = nil
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
        let point = cameraOverlays.compactMap({ overlay -> Point2<CameraPixelSpace>? in
          guard overlay.provenance.kind == .penCap, case .point(let point) = overlay.geometry
          else { return nil }
          return point
        }).first,
        let armatureBounds = cameraOverlays.compactMap({
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
      guard let cameraActions,
        let inspection = try await cameraActions.inspectScene(
          frame.frame.captureNanoseconds - 1
        ),
        let cap = inspection.measurement.cap
      else {
        throw LearningPathOperationError.requiredState("A measured tool component is required.")
      }
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
      cameraOverlays = inspection.measurement.overlays
    }
    let capAnchor = try ToolCapAnchorEstimate(
      componentCentroid: centroid,
      componentBounds: bounds,
      confidence: confidence,
      estimatorRevision: "green-cap-bottom-center-anchor-v2",
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
        algorithmRevision: "automatic-current-camera-cap-anchor-v3",
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
    cameraCalibrationProposalID = nil
    machineCameraRegistration = nil
    explorationError =
      "Operator rejected the staged five-sample cap map. No machine-camera revision became authoritative."
  }

  func selectToolContactPoint(_ selection: ActionSurfacePointSelection) {
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
      selectedToolContactPoint = selection.point
      explorationError = nil
    } catch {
      explorationError =
        "Sparse mark selection was rejected as stale: \(actionableDescription(error))"
    }
  }

  private func createNextSparseTipMark() async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .calibratePenContactFromSparseMarks
    )
    if activeExerciseAttemptOwnerID == nil {
      await startExercise(ownerID, mode: .normal)
    }
    guard activeExerciseAttemptOwnerID == ownerID,
      let attemptID = activeExerciseAttemptID,
      let machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      let center = cameraCalibrationReferencePosition
    else { return }

    var markCompleted = false
    var activeLocation: BlacklistedToolContactLocation?
    do {
      let position = try sparseTipCalibrationCoordinator.prepareNextMark()
      let plan = try CurrentCameraCalibrationPlan(
        targetPosition: center,
        boundarySideAggregates: boundarySideAggregates,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision
      )
      guard let sample = plan.samples.first(where: { $0.position == position }) else {
        throw LearningPathOperationError.requiredState(
          "Sparse calibration position is unavailable.")
      }
      let markPlan = try SparseTipCircularMarkPlan(
        center: sample.machinePosition,
        boundarySideAggregates: boundarySideAggregates
      )
      let physicalLocation = BlacklistedToolContactLocation(
        calibrationPosition: position,
        machinePosition: sample.machinePosition,
        markRadiusMM: SparseTipCircularMarkPlan.radiusMM,
        paperContactPlane: PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
      )
      activeLocation = physicalLocation
      guard !blacklistedToolContactLocations.contains(physicalLocation) else {
        throw LearningPathOperationError.requiredState(
          "Possible ink already blacklists this exact machine position on the current paper. Record paper replacement before restarting calibration."
        )
      }
      let current = try currentMachinePosition()
      let settled: MachinePosition
      if let delta = try Self.supervisedTravelDelta(
        from: current,
        to: sample.machinePosition
      ) {
        settled = try await performSupervisedPenUpTravel(
          delta: delta,
          ownerID: ownerID,
          action: "Sparse Tip Mark \(position.rawValue) Approach"
        )
      } else {
        settled = current
      }
      guard
        recordProtocolPoseSettlement(
          action: "Sparse Tip Mark \(position.rawValue) Approach",
          target: sample.machinePosition,
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
      let exactPreFrame = try exactTipCalibrationFrame(preCapture.displayedFrame)
      let capPredictionAtMark = try machineRegistration.fit.cameraPoint(
        from: settled.point
      )
      guard capPredictionAtMark.distance(to: preCapture.capAnchor.point) <= 8 else {
        throw LearningPathOperationError.requiredState(
          "The accepted cap map failed fresh pre-mark revalidation."
        )
      }
      let markStartDelta = try Vector2<MachineSpace>(
        dx: markPlan.startPosition.point.x - settled.point.x,
        dy: markPlan.startPosition.point.y - settled.point.y
      )
      let markStartSettled = try await performSupervisedPenUpTravel(
        delta: markStartDelta,
        ownerID: ownerID,
        action: "Sparse Tip Circle \(position.rawValue) Start"
      )
      guard
        recordProtocolPoseSettlement(
          action: "Sparse Tip Circle \(position.rawValue) Start",
          target: markPlan.startPosition,
          actual: markStartSettled
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Sparse circle start did not settle within 0.05 mm."
        )
      }
      try sparseTipCalibrationCoordinator.beganMark(at: position)
      let mark = try await performCircularContactMark(
        plan: markPlan,
        at: physicalLocation,
        after: exactPreFrame.captureNanoseconds
      )
      markCompleted = true

      let revealTarget = markPlan.revealPosition
      try sparseTipCalibrationCoordinator.beganReveal(from: position, to: revealTarget)
      let revealSettled: MachinePosition
      if let revealDelta = try Self.supervisedTravelDelta(
        from: mark.finalPosition,
        to: revealTarget
      ) {
        revealSettled = try await performSupervisedPenUpTravel(
          delta: revealDelta,
          ownerID: ownerID,
          action: "Reveal Sparse Tip Circle \(position.rawValue)"
        )
      } else {
        revealSettled = mark.finalPosition
      }
      guard
        recordProtocolPoseSettlement(
          action: "Reveal Sparse Tip Circle \(position.rawValue)",
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
          ? mark.penUp.timestamp.monotonicNanoseconds + 1
          : max(nowNanoseconds(), mark.penUp.timestamp.monotonicNanoseconds + 1)
      )
      let revealCapture = try await captureCurrentCameraCapAnchorEvidence(
        contextBaseline: preCapture.contextBaseline,
        operationID: operationUUID,
        newerThanNanoseconds: revealSettledAt.monotonicNanoseconds
      )
      let exactRevealFrame = try exactTipCalibrationFrame(revealCapture.displayedFrame)
      let revealPrediction = try machineRegistration.fit.cameraPoint(
        from: revealSettled.point
      )
      let controllerEvidence = try controllerContextEvidenceReference(
        revealCapture.contextBaseline,
        operationID: operationUUID
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
      pendingToolContactEvidence = PendingToolContactEvidence(
        attemptID: attemptID,
        operationID: ToolContactOperationID(rawValue: operationUUID),
        position: position,
        intendedMarkPosition: sample.machinePosition,
        actualSettledPosition: settled,
        controllerContextEvidence: controllerEvidence,
        markGeometry: markPlan.geometry,
        penDown: mark.penDown,
        penUp: mark.penUp,
        preMarkFrame: exactPreFrame,
        preMarkCapEstimate: preCapture.capAnchor,
        revealEvidence: revealEvidence,
        capMapPredictionAtMark: capPredictionAtMark,
        maximumCapMapResidualPixels: 8
      )
      try sparseTipCalibrationCoordinator.awaitFrozenClick(
        for: position,
        frame: exactRevealFrame
      )
      frozenToolContactSelectionFrame = revealCapture.displayedFrame
      selectedToolContactPoint = nil
      toolContactPointSelectionRequest = ActionSurfacePointSelectionRequest(
        frame: exactRevealFrame,
        presentationTransformRevision: PresentationTransformRevision(),
        prompt: "Click the center of the new black circle"
      )
      explorationError = nil
      _ = machineRegistrationRevision
    } catch {
      let failure = workflowFailure(for: error)
      if let activeLocation {
        if blacklistedToolContactLocations.contains(activeLocation) || markCompleted
          || failure.kind == .ambiguous || failure.kind == .possibleInk
        {
          blacklistedToolContactLocations.insert(activeLocation)
          sparseTipCalibrationCoordinator.blacklistPossibleInk(
            at: activeLocation,
            reason: failure.detail
          )
        } else {
          sparseTipCalibrationCoordinator.resetBeforeInkFailure()
        }
      }
      pendingToolContactEvidence = nil
      frozenToolContactSelectionFrame = nil
      toolContactPointSelectionRequest = nil
      selectedToolContactPoint = nil
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
      lower = await machineActions.requestPenActuation(.lower)
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

    let downTime = RuntimeTimestamp(
      monotonicNanoseconds: frameMode == .simulated
        ? captureNanoseconds + 1
        : max(nowNanoseconds(), captureNanoseconds + 1)
    )

    var finalPosition = plan.startPosition
    do {
      for (index, delta) in plan.pathDeltas.enumerated() {
        let expected = plan.pathPositions[index + 1]
        if frameMode == .simulated {
          let response = await simulatedLearningRuntime.beginDrawing(
            delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy)
          )
          let operation = try response.result.get()
          let target = ContextualStopTarget.sparseTipMark(
            capabilityID: ContextualStopCapabilityID(),
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
          let outcome = await task.value
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
          let target = ContextualStopTarget.sparseTipMark(
            capabilityID: ContextualStopCapabilityID(),
            operationOwner: .liveOperation(operation.id),
            location: location
          )
          let task = Task { await operation.outcome() }
          installStoppableOperation(target: target, owner: .drawing(task))
          defer { clearStoppableOperation(matching: target) }
          let outcome = await task.value
          machineSnapshot = await machineActions.snapshot()
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
            action: "Sparse Tip Circle chord \(index + 1)/\(plan.pathDeltas.count)",
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
      raise = await machineActions.requestPenActuation(.raise)
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
    let upTime = RuntimeTimestamp(
      monotonicNanoseconds: frameMode == .simulated
        ? downTime.monotonicNanoseconds + 1
        : max(nowNanoseconds(), downTime.monotonicNanoseconds + 1)
    )
    return (
      PenActuationEvidence(outcome: lower, timestamp: downTime),
      PenActuationEvidence(outcome: raise, timestamp: upTime),
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
    _ = await machineActions.requestPenActuation(.raise)
    machineSnapshot = await machineActions.snapshot()
  }

  private func reClickSparseTipFrame() {
    do {
      try sparseTipCalibrationCoordinator.reClickSameFrame()
      selectedToolContactPoint = nil
      explorationError = nil
    } catch {
      explorationError = actionableDescription(error)
    }
  }

  private func acceptSparseTipMark() {
    guard let pending = pendingToolContactEvidence,
      let point = selectedToolContactPoint,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      let request = toolContactPointSelectionRequest
    else { return }
    do {
      let click = try ToolContactClickEvidence(
        point: point,
        pointingUncertaintyPixels: Vector2(dx: 1.5, dy: 1.5),
        timestamp: RuntimeTimestamp(
          monotonicNanoseconds: max(
            nowNanoseconds(), pending.revealEvidence.frame.captureNanoseconds + 1)
        ),
        presentationTransformRevision:
          sparseTipCalibrationCoordinator.selectedPresentationRevisionForCommit
          ?? request.presentationTransformRevision
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
          rawValue: explorationToolPaperRevision
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
            revision: "circle-2mm-radius-16-chord-exact-center-click-v1"
          ),
          try AlgorithmRevisionEvidence(
            component: "pen-actuation",
            revision: PenActuationProfile.localPlotterRevision
          ),
        ]
      )
      let revision = LearningArtifactRevision(
        kind: .toolContactObservation(observation.id),
        attemptID: pending.attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [machineRegistrationRevision]
      )
      let accepted = try AcceptedToolContactObservation(
        artifactRevisionID: revision.id,
        observation: observation
      )
      var coordinator = sparseTipCalibrationCoordinator
      try coordinator.acceptObservation(accepted)
      var graph = learningArtifactGraph
      _ = try graph.commitReplacement(revision)
      if let checkpoint = quarantinedTipCalibrationCheckpoint,
        checkpoint.registration.applicability.paperContactPlane.rawValue
          != explorationToolPaperRevision
      {
        let restored = try revalidateTipCheckpointForChangedPaper(
          checkpoint,
          contactObservation: accepted,
          machineRegistrationRevision: machineRegistrationRevision,
          graph: &graph
        )
        coordinator.markCheckpointRevalidated()
        sparseTipCalibrationCoordinator = coordinator
        learningArtifactGraph = graph
        tipCameraRegistration = restored
        proposedTipCameraRegistration = nil
        quarantinedTipCalibrationCheckpoint = nil
        pendingToolContactEvidence = nil
        frozenToolContactSelectionFrame = nil
        toolContactPointSelectionRequest = nil
        selectedToolContactPoint = nil
        finishActiveExerciseAttempt(disposition: .succeeded)
        explorationError = nil
        return
      }
      sparseTipCalibrationCoordinator = coordinator
      learningArtifactGraph = graph
      pendingToolContactEvidence = nil
      frozenToolContactSelectionFrame = nil
      toolContactPointSelectionRequest = nil
      selectedToolContactPoint = nil
      if sparseTipCalibrationCoordinator.acceptedObservations.count
        == SparseTipCalibrationCoordinator.orderedPositions.count
      {
        try stageTipCalibrationProposal(
          machineRegistrationRevision: machineRegistrationRevision
        )
      }
      explorationError = nil
    } catch {
      explorationError = "Accept Mark failed atomically: \(actionableDescription(error))"
    }
  }

  private func revalidateTipCheckpointForChangedPaper(
    _ checkpoint: AcceptedTipCalibrationCheckpoint,
    contactObservation: AcceptedToolContactObservation,
    machineRegistrationRevision: LearningArtifactRevisionID,
    graph: inout LearningDependencyGraph
  ) throws -> TipCameraRegistration {
    let observation = contactObservation.observation
    let reveal = observation.revealEvidence
    let currentApplicability = TipCalibrationApplicabilityContext(
      opticalConfiguration: reveal.frame.opticalConfiguration,
      machineGeometry: machineGeometryIdentity,
      machineCoordinateFrame: MachineCoordinateFrameRevision(
        rawValue: explorationCoordinateRevision
      ),
      toolAssembly: toolAssemblyRevision,
      penContactProfile: penContactProfileRevision,
      paperContactPlane: PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
    )
    let revalidationTimestamp = RuntimeTimestamp(
      monotonicNanoseconds: max(
        nowNanoseconds(),
        observation.click.timestamp.monotonicNanoseconds + 1
      )
    )
    let evidence = try TipCalibrationRevalidationEvidence(
      currentApplicability: currentApplicability,
      currentMachineCameraRegistrationRevisionID: machineRegistrationRevision,
      controllerContextEvidence: reveal.controllerContextEvidence,
      frame: reveal.frame,
      capEstimate: reveal.capEstimate,
      capMapPrediction: reveal.capMapPrediction,
      maximumCapMapResidualPixels: reveal.maximumCapMapResidualPixels,
      contactPlaneRevalidation: TipContactPlaneRevalidationEvidence(
        acceptedObservation: contactObservation,
        maximumTipResidualPixels: 8
      ),
      timestamp: revalidationTimestamp,
      algorithmRevision: "explicit-tip-contact-plane-revalidation-v1"
    )
    guard case .restored = checkpoint.revalidate(with: evidence) else {
      throw LearningPathOperationError.requiredState(
        "The saved tip calibration remains quarantined because the new contact observation did not revalidate the replacement paper plane."
      )
    }

    guard let attemptID = activeExerciseAttemptID else {
      throw SparseTipCalibrationCoordinatorError.invalidTransition
    }
    var rebuiltObservationRevisions: [ToolContactObservationID: LearningArtifactRevisionID] = [:]
    for prior in checkpoint.registration.observationEvidence {
      let revision = LearningArtifactRevision(
        kind: .toolContactObservation(prior.observationID),
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [machineRegistrationRevision]
      )
      _ = try graph.commitReplacement(revision)
      rebuiltObservationRevisions[prior.observationID] = revision.id
    }
    let acceptedRevisionID = LearningArtifactRevisionID()
    let acceptedAt = RuntimeTimestamp(
      monotonicNanoseconds: max(
        nowNanoseconds(),
        revalidationTimestamp.monotonicNanoseconds + 1
      )
    )
    let restored = try checkpoint.registration.revalidatedFromCheckpoint(
      evidence: evidence,
      acceptedRevisionID: acceptedRevisionID,
      machineCameraRegistrationRevisionID: machineRegistrationRevision,
      observationArtifactRevisionIDs: rebuiltObservationRevisions,
      acceptedAt: acceptedAt
    )
    let revision = LearningArtifactRevision(
      id: acceptedRevisionID,
      kind: .tipCameraRegistration,
      attemptID: attemptID,
      disposition: .succeeded,
      consumedRevisionIDs: restored.consumedArtifactRevisionIDs
    )
    _ = try graph.commitReplacement(revision)
    let acceptance = try TipCalibrationAcceptanceEvent(
      acceptedRevisionID: acceptedRevisionID,
      timestamp: acceptedAt,
      actor: "operator-contact-plane-revalidation"
    )
    try activeAcceptedTipCalibrationCheckpointActions?.save(
      AcceptedTipCalibrationCheckpoint(
        registration: restored,
        acceptanceEvent: acceptance
      )
    )
    return restored
  }

  private func stageTipCalibrationProposal(
    machineRegistrationRevision: LearningArtifactRevisionID
  ) throws {
    guard let machineRegistration = machineCameraRegistration,
      let attemptID = activeExerciseAttemptID,
      let optical = sparseTipCalibrationCoordinator.acceptedObservations.first?
        .observation.postRevealSelectionFrame.opticalConfiguration
    else { throw SparseTipCalibrationCoordinatorError.invalidTransition }
    let selection = try sparseTipCalibrationCoordinator.stageProposal(
      capCameraFromMachine: machineRegistration.fit.cameraFromMachine,
      maximumHoldoutResidualPixels: 8
    )
    let registrationRevisionID = LearningArtifactRevisionID()
    proposedTipCameraRegistration = try TipCameraRegistration(
      modelForm: selection.modelForm,
      cameraFromMachine: selection.finalCameraFromMachine,
      modelSelectionEvidence: selection.evidence,
      uncertainty: selection.uncertainty,
      applicabilityRectangle: machineRegistration.applicabilityRectangle,
      acceptedObservations: sparseTipCalibrationCoordinator.acceptedObservations,
      maximumObservationResidualPixels: 8,
      applicability: TipCalibrationApplicabilityContext(
        opticalConfiguration: optical,
        machineGeometry: machineGeometryIdentity,
        machineCoordinateFrame: MachineCoordinateFrameRevision(
          rawValue: explorationCoordinateRevision
        ),
        toolAssembly: toolAssemblyRevision,
        penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(
          rawValue: explorationToolPaperRevision
        )
      ),
      acceptedRevisionID: registrationRevisionID,
      machineCameraRegistrationRevisionID: machineRegistrationRevision,
      estimatorRevision: SparseTipCircularMarkPlan.registrationEstimatorRevision,
      acceptedAt: RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
    )
    _ = attemptID
  }

  private func acceptTipCalibration() {
    guard let proposal = proposedTipCameraRegistration,
      let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID
        == .humanGuidedDiscovery(
          .calibratePenContactFromSparseMarks
        )
    else { return }
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
      try coordinator.markAccepted()
      let acceptedTimestamp = RuntimeTimestamp(monotonicNanoseconds: nowNanoseconds())
      let acceptanceEvent = try TipCalibrationAcceptanceEvent(
        acceptedRevisionID: proposal.acceptedRevisionID,
        timestamp: acceptedTimestamp,
        actor: "operator"
      )
      let checkpoint = try AcceptedTipCalibrationCheckpoint(
        registration: proposal,
        acceptanceEvent: acceptanceEvent
      )
      try activeAcceptedTipCalibrationCheckpointActions?.save(checkpoint)
      learningArtifactGraph = graph
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
      tipCameraRegistration = proposal
      proposedTipCameraRegistration = nil
      sparseTipCalibrationCoordinator = coordinator
      quarantinedTipCalibrationCheckpoint = nil
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
    } catch {
      explorationError =
        "Tip-calibration acceptance failed atomically: \(actionableDescription(error))"
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
      let checkpoint = quarantinedTipCalibrationCheckpoint,
      let machineRegistration = machineCameraRegistration,
      let machineRegistrationRevision = learningArtifactGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      checkpoint.registration.applicability.paperContactPlane.rawValue
        == explorationToolPaperRevision
    else { return }

    let operationID = UUID()
    do {
      let capture = try await captureCurrentCameraCapAnchorEvidence(
        contextBaseline: nil,
        operationID: operationID
      )
      let exactFrame = try exactTipCalibrationFrame(capture.displayedFrame)
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
          rawValue: explorationCoordinateRevision
        ),
        toolAssembly: toolAssemblyRevision,
        penContactProfile: penContactProfileRevision,
        paperContactPlane: PaperContactPlaneRevision(
          rawValue: explorationToolPaperRevision
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
        algorithmRevision: "explicit-tip-checkpoint-revalidation-v1"
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
      try activeAcceptedTipCalibrationCheckpointActions?.save(refreshedCheckpoint)

      learningArtifactGraph = graph
      tipCameraRegistration = restoredRegistration
      proposedTipCameraRegistration = nil
      quarantinedTipCalibrationCheckpoint = nil
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
    } catch {
      finishActiveExerciseAttempt(disposition: .failed(actionableDescription(error)))
      explorationError =
        "Saved tip calibration was not restored: \(actionableDescription(error))"
    }
  }

  private func rejectTipCalibration() {
    do {
      try sparseTipCalibrationCoordinator.markRejected(
        reason: "Operator rejected the staged tip model."
      )
      proposedTipCameraRegistration = nil
      finishActiveExerciseAttempt(disposition: .cancelled)
      explorationError =
        "Operator rejected the staged tip model. Five raw mark observations remain immutable; no redraw occurred. Replace the paper before starting a new physical calibration."
    } catch {
      explorationError = actionableDescription(error)
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
    var graph = learningArtifactGraph
    let invalidation = graph.invalidateCurrentRevisions(rootKinds: [.tipCameraRegistration])
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    if let replacementSnapshot {
      simulatedLearningSnapshot = replacementSnapshot
      explorationToolPaperRevision = replacementSnapshot.toolPaperRevision
    } else {
      explorationToolPaperRevision = UUID()
      persistPaperContactPlaneRevision(
        PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
      )
    }
    sparseTipCalibrationCoordinator = SparseTipCalibrationCoordinator(
      blacklistedLocations: blacklistedToolContactLocations.filter {
        $0.paperContactPlane.rawValue == explorationToolPaperRevision
      }
    )
    if quarantinedTipCalibrationCheckpoint == nil,
      let actions = activeAcceptedTipCalibrationCheckpointActions,
      case .quarantined(let checkpoint) = actions.load()
    {
      quarantinedTipCalibrationCheckpoint = checkpoint
    }
    clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    explorationError = nil
  }

  func performCurrentLearningPathAction() async {
    guard tipCameraRegistration != nil, activeExplorationOperation == nil else { return }
    let attemptedStep = observedDrawingTrialStep
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .observedDrawingTrial(attemptedStep),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    let payloadSnapshot = drawingTrialPayloadSnapshot()
    activeExplorationOperation = ActiveExplorationOperation(
      step: attemptedStep,
      strokeState: .notAdmitted
    )
    explorationError = nil
    defer { activeExplorationOperation = nil }
    do {
      switch observedDrawingTrialStep {
      case .chooseIsolatedLinePlan:
        try recordIsolatedLinePlan(selectedLineDirection)
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
      if attemptedStep != .compareIntendedAndObservedGeometry {
        try commitDrawingArtifact(for: attemptedStep)
        advanceDrawingTrialAfterSuccess(attemptedStep)
        finishActiveExerciseAttempt(disposition: .succeeded)
      }
    } catch {
      if attemptedStep == .drawIsolatedLine,
        (drawingTrialStrokeEvidence != payloadSnapshot.strokeEvidence
          || activeExplorationOperation?.strokeState != .notAdmitted)
      {
        var commitFailure: String?
        if activeExplorationOperation?.strokeState == .completedNaturally {
          do {
            try commitDrawingArtifact(for: .drawIsolatedLine)
          } catch {
            commitFailure = String(describing: error)
          }
        }
        advanceDrawingTrialAfterSuccess(.drawIsolatedLine)
        let base =
          "The stroke owner produced evidence, so physical ink may exist. Drawing will not be restarted; continue with return/observation."
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
      restoreDrawingTrialPayload(payloadSnapshot)
      explorationError = "\(attemptedStep.title) failed: \(error)"
      finishActiveExerciseAttempt(disposition: workflowFailure(for: error).attemptDisposition)
      restartableExerciseItemID = .observedDrawingTrial(attemptedStep)
    }
  }

  func recordDrawingTrialAssessment(_ assessment: DrawingTrialAssessment) async {
    guard observedDrawingTrialStep == .compareIntendedAndObservedGeometry
    else { return }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .observedDrawingTrial(.compareIntendedAndObservedGeometry),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    let payloadSnapshot = drawingTrialPayloadSnapshot()
    do {
      var episode = currentExplorationEpisode
      episode?.humanAssessment = ExplorationAssessment(
        summary: assessment.title,
        provenance: "typed local operator comparison"
      )
      episode?.termination = .completed
      try commitComparisonAttemptAndArtifact(assessment)
      drawingTrialAssessment = assessment
      currentExplorationEpisode = episode
      if let episode {
        completedExplorationEpisodes.removeAll { $0.id == episode.id }
        completedExplorationEpisodes.append(episode)
      }
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      restoreDrawingTrialPayload(payloadSnapshot)
      explorationError = "Comparison failed: \(error)"
      recordComparisonAttempt(
        assessment: nil,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = .observedDrawingTrial(.compareIntendedAndObservedGeometry)
    }
  }

  func discoveryStartUnavailableReason(for sequenceID: DiscoverySequenceID) -> String? {
    if let activeDiscoverySequenceID {
      return
        "Finish \(DiscoverySequenceCatalog.definition(for: activeDiscoverySequenceID).title); use Stop while its logical owner is active."
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
    let penIsUp =
      frameMode == .simulated
      ? simulatedLearningSnapshot?.penPose == .up
      : machineSnapshot?.machine.penState == .up
    if !penIsUp {
      return "Motion enabled. Raise the pen so the commanded state is Up before carriage travel."
    }
    return "Motion enabled; carriage motion is available."
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
    guard let outcome = machineSnapshot?.lastMotionOutcome else { return "none" }
    switch outcome {
    case .refused(let reason):
      return "refused: \(reason.actionableDescription)"
    case .acceptedThenCompleted(let finalPosition):
      return String(
        format: "completed at X %.3f Y %.3f",
        finalPosition.point.x,
        finalPosition.point.y
      )
    case .cancelled(let finalPosition):
      return String(
        format: "cancelled at X %.3f Y %.3f",
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
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if frameMode == .simulated {
      if let reason = simulatedManualMotionUnavailableReason { return reason }
    } else if let reason = directCarriageMotionUnavailableReason {
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
    guard simulatedLearningSnapshot?.penPose == .up else {
      return "Set the simulated pen Up before manual carriage motion."
    }
    return nil
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

  private var directCarriageMotionUnavailableReason: String? {
    if jogRequestInProgress { return "A relative jog is already in progress." }
    if frameModeSwitchInProgress { return "Wait for the frame source switch to finish." }
    if frameMode == .simulated {
      return "SIMULATED source cannot issue physical machine commands. Switch to LIVE first."
    }
    if machineActions == nil { return "Native machine composition is unavailable." }
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
    if machine.penState != .up {
      return MotionRefusal.penNotUp(machine.penState).actionableDescription
    }
    return nil
  }

  func penUnavailableReason(for command: PenCommand) -> String? {
    if let reason = currentCameraCalibrationBusyReason { return reason }
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
    if machine.pins.hasRelevantLimitAsserted {
      return PenRefusal.relevantLimitAsserted(machine.pins.rawValue).actionableDescription
    }
    guard machine.position != nil else {
      return PenRefusal.machinePositionUnknown.actionableDescription
    }
    return nil
  }

  func setLayer(_ layer: CanvasLayer, visible: Bool) {
    guard !hasShutdown else { return }
    if visible {
      visibleLayers.insert(layer)
    } else {
      visibleLayers.remove(layer)
    }
    Task { await reconcileAutomaticVisionAnalysis() }
  }

  private var sceneAnalysisIsRequested: Bool {
    visibleLayers.contains(where: \.requiresSceneAnalysis)
  }

  private var automaticVisionAnalysisShouldRun: Bool {
    guard frameMode == .live, sceneAnalysisIsRequested,
      case .running = cameraSnapshot?.state
    else { return false }
    return true
  }

  private func reconcileAutomaticVisionAnalysis() async {
    guard !hasShutdown, let cameraActions else { return }
    if automaticVisionAnalysisShouldRun {
      let generation = lifetimeGeneration
      await cameraActions.setSceneAnalysisRegion(videoAnalysisRegionLock?.region)
      let snapshot = await cameraActions.setAutomaticInspection(visionAnalysisCadence)
      guard canCommit(generation), frameMode == .live else { return }
      visionAnalysisSnapshot = snapshot
      visionError = snapshot.lastError
      beginVisionUpdates(generation: generation)
      if let result = snapshot.latestResult { receiveVision(result) }
      return
    }

    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    let snapshot = await cameraActions.setAutomaticInspection(nil)
    visionAnalysisSnapshot = snapshot
    visionError = snapshot.lastError
    let sceneKinds = Set(
      CanvasLayer.allCases.filter(\.requiresSceneAnalysis).map(\.overlayKind)
    )
    cameraOverlays.removeAll { sceneKinds.contains($0.provenance.kind) }
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

  func requestPenActuation(_ command: PenCommand) async {
    if frameMode == .simulated {
      guard penUnavailableReason(for: command) == nil else { return }
      penRequestInProgress = true
      defer { penRequestInProgress = false }
      let pose: SimulatedLearningPenPose = command.commandedState == .up ? .up : .down
      applySimulatedSnapshotResponse(
        await simulatedLearningRuntime.setPenPose(pose),
        action: "Set simulated pen \(pose.rawValue)"
      )
      return
    }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard penUnavailableReason(for: command) == nil, let machineActions else { return }
    penRequestInProgress = true
    machineError = nil
    defer { penRequestInProgress = false }
    let operation = Task { await machineActions.requestPenActuation(command) }
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    _ = await operation.value
    let snapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return }
    machineSnapshot = snapshot
  }

  func startDiscoverySequence(_ sequenceID: DiscoverySequenceID) async {
    guard discoveryStartUnavailableReason(for: sequenceID) == nil else { return }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: learningPathItemID(for: sequenceID),
        mode: .normal
      )
    }
    selectedDiscoverySequenceID = sequenceID
    discoveryError = nil
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

    case .manualJog:
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
        restartableExerciseItemID = .observedDrawingTrial(.drawIsolatedLine)
      }

    case .sparseTipMark(_, _, let location):
      blacklistedToolContactLocations.insert(location)
      sparseTipCalibrationCoordinator.blacklistPossibleInk(
        at: location,
        reason: "Operator stopped the 2 mm calibration circle after Pen Down."
      )
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await operation.owner.settle()
      explorationError =
        "Calibration circle stopped after contact. This paper location is blacklisted and will not be redrawn automatically."
      restartableExerciseItemID = nil
    }
  }

  private func requestSingleJogCancel(
    for target: ContextualStopTarget,
    intent: JogCancelIntent
  ) async {
    if case .simulated(let operationID) = target.operationOwner {
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
    precondition(activeStoppableOperation == nil, "Only one contextual Stop owner may exist.")
    activeStoppableOperation = ActiveStoppableOperation(target: target, owner: owner)
  }

  private func clearStoppableOperation(matching target: ContextualStopTarget) {
    guard activeStoppableOperation?.target == target else { return }
    activeStoppableOperation = nil
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
      motionGuardActivationInProgress = true
      defer { motionGuardActivationInProgress = false }
      applySimulatedSnapshotResponse(
        await simulatedLearningRuntime.enableMotion(),
        action: "Enable simulated motion"
      )
      return
    }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard motionGuardActivationUnavailableReason == nil, let machineActions else { return }
    motionGuardActivationInProgress = true
    machineError = nil
    defer { motionGuardActivationInProgress = false }
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
      let request = RelativeJogRequest(delta: delta, feedMMPerMinute: feed)
      await requestRelativeJog(request)
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
    guard motionUnavailableReason == nil, !jogRequestInProgress, let machineActions else {
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
        detail: "An ordinary operator-authored manual jog was admitted.",
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

  private func requestSimulatedRelativeJog(_ request: RelativeJogRequest) async {
    guard motionUnavailableReason == nil, !jogRequestInProgress else { return }
    let vector: SimulatedLearningMotionVector
    do {
      vector = try SimulatedLearningMotionVector(
        dxMM: request.delta.dx,
        dyMM: request.delta.dy
      )
    } catch {
      simulatorLearningSummary = "Simulated manual jog is invalid: \(error)."
      return
    }
    let response = await simulatedLearningRuntime.beginManualJog(delta: vector)
    let operation: SimulatedLearningOperation
    switch response.result {
    case .success(let admitted):
      operation = admitted
    case .failure(let refusal):
      simulatorLearningSummary =
        "Simulated manual jog refused: \(refusal). \(response.evidenceNotice.label)"
      return
    }
    let target = ContextualStopTarget.manualJog(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .simulated(operation.id)
    )
    jogRequestInProgress = true
    simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    simulatorLearningSummary =
      "Simulated manual jog active; use Stop Manual Jog. \(response.evidenceNotice.label)"
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
      cameraOverlays = []
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
    let snapshot = await cameraActions.restart()
    guard canCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    cameraOverlays = []
    lastSceneMeasurement = nil
    updateCameraError()
    beginFrameUpdates(generation: generation)
    await reconcileAutomaticVisionAnalysis()
  }

  private func beginScopedVisionAnalysis() async -> ScopedVisionAnalysisLease? {
    guard !hasShutdown, frameMode == .live,
      case .running = cameraSnapshot?.state,
      !scopedVisionAnalysisActive,
      let cameraActions
    else { return nil }
    let generation = lifetimeGeneration
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    await cameraActions.setSceneAnalysisRegion(videoAnalysisRegionLock?.region)
    let snapshot = await cameraActions.setAutomaticInspection(visionAnalysisCadence)
    guard canCommit(generation), frameMode == .live else {
      _ = await cameraActions.setAutomaticInspection(nil)
      return nil
    }
    scopedVisionAnalysisActive = true
    visionError = snapshot.lastError
    visionAnalysisSnapshot = snapshot
    beginVisionUpdates(generation: generation)
    if let result = snapshot.latestResult { receiveVision(result) }
    return ScopedVisionAnalysisLease()
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
    guard let cameraActions else { return }
    frameModeSwitchInProgress = true
    defer { frameModeSwitchInProgress = false }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    videoAnalysisRegionLock = nil
    await cameraActions.setSceneAnalysisRegion(nil)
    cameraOverlays = []
    cameraError = nil
    switch mode {
    case .live:
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
        paperContactPlaneRevision: UUID()
      )
      frameMode = .simulated
      do {
        let scene = try await captureSimulatedProtocolScene()
        guard canCommit(generation) else { return }
        lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
        applySimulatedProtocolScene(scene)
        explorationToolPaperRevision = scene.toolPaperRevision
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
    stopObserving()
    let calibration = currentCameraCalibrationTask
    calibration?.cancel()
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

  private func appendFrameEvidence(
    _ role: ExplorationFrameRole,
    frame: StampedFrame,
    algorithmRevision: String = "camera-selected-frame-v1"
  ) {
    guard var episode = currentExplorationEpisode else { return }
    episode.frames.removeAll { $0.role == role }
    episode.frames.append(
      ExplorationFrameEvidence(
        role: role,
        frameID: frame.id,
        contentSHA256: frame.contentSHA256,
        captureNanoseconds: frame.captureNanoseconds,
        cameraConfigurationID: frame.cameraConfigurationID,
        algorithmRevision: algorithmRevision
      ))
    currentExplorationEpisode = episode
  }

  private func recordStrokeEvidence(
    _ evidence: DrawingStrokeEvidence,
    outcome: ExplorationControllerOutcome,
    summary: String
  ) {
    guard var episode = currentExplorationEpisode else { return }
    episode.controllerEvidence = ExplorationControllerEvidence(
      startPosition: evidence.startPosition,
      finalPosition: evidence.finalPosition,
      startSampleNanoseconds: evidence.startSampleNanoseconds,
      settlementNanoseconds: evidence.finalSampleNanoseconds,
      outcome: outcome,
      summary: summary
    )
    currentExplorationEpisode = episode
  }

  private func acceptInkObservation(
    _ observation: IsolatedInkObservation
  ) {
    lastInkObservation = observation
    cameraOverlays = observation.overlays
    explorationInkStatus =
      observation.residual == nil
      ? "new ink observed; absolute residual unavailable without a current-session projection"
      : "new ink observed with tip-model-projected residual"
    if var episode = currentExplorationEpisode {
      episode.observedLineStartPoint = observation.lineStartPoint
      episode.observedLineObservation = observation
      episode.visionEstimate = ExplorationAssessment(
        summary: "\(observation.observedPixelCount) new line pixels",
        provenance: "\(observation.algorithmRevision) exact same-pose two-frame subtraction"
      )
      if let residual = observation.residual {
        episode.residual = ExplorationResidual(
          rmsPixels: residual.rootMeanSquareEndpointPixels,
          maximumPixels: residual.maximumEndpointPixels,
          crossTrackPixels: residual.rootMeanSquareCrossTrackPixels,
          summary: "camera-space tip-model-projected residual",
          provenance: observation.algorithmRevision
        )
      } else {
        episode.residual = ExplorationResidual(
          summary:
            "absolute camera-space residual unavailable; relative displacement/orientation only",
          provenance: observation.algorithmRevision
        )
      }
      currentExplorationEpisode = episode
    }
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
      guard
        recordDiscovery(
          .physicalPenConfirmed(
            state,
            response: choice,
            operatorSummary: "Operator selected \(choice.exactPhrase) for the current pen question."
          ),
          for: sequenceID
        )
      else { return }
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
    // Admit the motion owner and publish Stop without awaiting Camera/Vision.
    // Optional observations after a completed probe may increase only a later
    // bounded segment; absence or latency stays on the controller fallback.
    let approachPlanner = BoundaryApproachPlanner(seed: nil)
    let renewalPlanner = BoundaryMotionRenewalPlanner { @MainActor [weak self] progress in
      guard let self else { return nil }
      return await self.planBoundaryRenewal(
        after: progress,
        planner: approachPlanner,
        attemptID: attemptID
      )
    }
    let admittedOperation: BoundaryMotionOperation
    switch await machineActions.beginBoundaryMotion(request, renewalPlanner) {
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
        sequenceID, failure: .failed("Boundary owner admission returned a mismatched owner identity."))
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
    await cancelAndSettleBoundaryApproachVision(for: attemptID)
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
      let selection = travelFeedSelection(for: delta)
      lastTravelFeedSelection = selection
      return BoundaryMotionRequest(
        direction: boundaryDirection(from: direction),
        segment: RelativeJogRequest(
          delta: delta,
          feedMMPerMinute: selection.requestedFeedMMPerMinute
        ),
        renewalBounds: BoundaryMotionSegmentBounds(
          minimumMM: 2,
          fallbackMM: MotionPriors.boundaryWireSegmentMM,
          maximumMM: 50
        )
      )
    } catch {
      boundaryTeachingResultText = "Boundary motion request is invalid; no motion was sent."
      return nil
    }
  }

  private func captureBoundaryApproachObservation(
    at machinePosition: MachinePosition?
  ) async -> BoundaryApproachObservation? {
    guard let cameraActions, let machinePosition else { return nil }
    do {
      guard let inspection = try await cameraActions.inspectScene(nowNanoseconds()),
        let cap = inspection.measurement.cap,
        let drawingFrame = inspection.measurement.drawingFrame
      else { return nil }
      guard !Task.isCancelled else { return nil }
      let capAnchor = try Point2<CameraPixelSpace>(
        x: Double(cap.boundingBox.x) + (Double(cap.boundingBox.width) / 2),
        y: Double(cap.boundingBox.y + cap.boundingBox.height)
      )
      displayedFrame = inspection.displayedFrame
      latestLiveCameraFrame = inspection.displayedFrame
      cameraOverlays = inspection.measurement.overlays
      return BoundaryApproachObservation(
        source: inspection.displayedFrame.source,
        frameID: inspection.displayedFrame.frame.id,
        cameraConfigurationID: inspection.displayedFrame.frame.cameraConfigurationID,
        captureNanoseconds: inspection.displayedFrame.frame.captureNanoseconds,
        machinePosition: machinePosition,
        toolCapAnchor: capAnchor,
        toolConfidence: cap.confidence,
        drawingFrame: drawingFrame.geometry,
        drawingFrameConfidence: drawingFrame.confidence
      )
    } catch {
      return nil
    }
  }

  /// Ends the exact-frame advisory before the Boundary owner settles. A
  /// cancelled Task is still running until Camera/Vision unwinds its exclusive
  /// computation lease, so cancellation without settlement can leave obsolete
  /// inspection work consuming CPU after its owner is done.
  private func cancelAndSettleBoundaryApproachVision(
    for attemptID: ExerciseAttemptID
  ) async {
    let task = boundaryApproachVisionTasks.removeValue(forKey: attemptID)
    task?.cancel()
    await task?.value
    boundaryApproachAdvisories.removeValue(forKey: attemptID)
  }

  private func cancelAndSettleAllBoundaryApproachVision() async {
    let tasks = Array(boundaryApproachVisionTasks.values)
    boundaryApproachVisionTasks.removeAll()
    for task in tasks { task.cancel() }
    for task in tasks { await task.value }
    boundaryApproachAdvisories.removeAll()
  }

  private func planBoundaryRenewal(
    after progress: BoundaryMotionSegmentProgress,
    planner: BoundaryApproachPlanner,
    attemptID: ExerciseAttemptID
  ) async -> Double? {
    let advisory =
      boundaryApproachAdvisories[attemptID]
      ?? BoundaryApproachAdvisory(
        observation: nil,
        advice: BoundaryApproachAdvice(
          nextSegmentLengthMM: MotionPriors.boundaryWireSegmentMM,
          basis: .missingObservationFallback
        )
      )
    if boundaryApproachVisionTasks[attemptID] == nil,
      stopDispositionLatch == nil,
      activeExerciseAttemptID == attemptID
    {
      boundaryApproachVisionTasks[attemptID] = Task { [weak self] in
        guard let self else { return }
        let observation = await self.captureBoundaryApproachObservation(
          at: progress.finalPosition
        )
        let advice = await planner.advise(after: observation)
        guard !Task.isCancelled,
          self.activeExerciseAttemptID == attemptID,
          self.stopDispositionLatch == nil
        else {
          self.boundaryApproachVisionTasks[attemptID] = nil
          return
        }
        self.boundaryApproachAdvisories[attemptID] = BoundaryApproachAdvisory(
          observation: observation,
          advice: advice
        )
        self.boundaryApproachVisionTasks[attemptID] = nil
      }
    }
    let observation = advisory.observation
    let advice = advisory.advice
    let projection =
      advice.estimatedRemainingMM.map {
        String(format: ", estimated %.1f mm remaining", $0)
      } ?? ""
    appendBoundaryActivity(
      actor: .vision,
      direction: progress.direction,
      phase: .renewalPlanning,
      disposition: .succeeded,
      attemptID: attemptID,
      operationOwnerID: .liveBoundary(progress.ownerID),
      finalPosition: progress.finalPosition,
      frameID: observation?.frameID,
      cameraConfigurationID: observation?.cameraConfigurationID,
      detail: .message(
        "Segment \(progress.completedSegmentCount) completed at "
          + "\(String(format: "%.1f", progress.completedSegment.delta.magnitude)) mm; "
          + "next segment \(String(format: "%.1f", advice.nextSegmentLengthMM)) mm "
          + "from the latest completed advisory (\(advice.basis.rawValue)\(projection)). "
          + "Background analysis is paused while this owner is active; exact renewal "
          + "inspection continues off the motion-owner critical path."
      )
    )
    return advice.nextSegmentLengthMM
  }

  private func startExercise(
    _ ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) async {
    guard activeExerciseAttemptOwnerID == nil else { return }
    activeExerciseAttemptMode = mode
    restartableExerciseItemID = nil
    switch ownerID {
    case .humanGuidedDiscovery(.penInteraction):
      await beginPenInteraction()
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      await beginPairedBoundarySide(selectedBoundaryDirection)
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
    case .observedDrawingTrial(let step):
      observedDrawingTrialStep = step
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      if step != .compareIntendedAndObservedGeometry {
        await performCurrentLearningPathAction()
      }
    case .stage:
      activeExerciseAttemptMode = nil
    }
  }

  private func cancelExerciseAttempt(_ ownerID: LearningPathItemID) async {
    guard activeExerciseAttemptOwnerID == ownerID else { return }
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
      let owner = activeStoppableOperation?.owner
      await requestSingleJogCancel(for: target, intent: .cancelAttempt)
      await owner?.settle()
    }
    if ownerID == .observedDrawingTrial(.compareIntendedAndObservedGeometry) {
      recordComparisonAttempt(assessment: nil, disposition: .cancelled)
    }
    finishActiveExerciseAttempt(disposition: .cancelled)
    restartableExerciseItemID = boundaryRepeatWithFallback ? nil : ownerID
  }

  private func beginExerciseAttempt(
    ownerID: LearningPathItemID,
    mode: ExerciseAttemptMode
  ) {
    guard activeExerciseAttemptID == nil else { return }
    activeExerciseAttemptID = ExerciseAttemptID()
    activeExerciseAttemptOwnerID = ownerID
    activeExerciseAttemptMode = mode
  }

  private func finishActiveExerciseAttempt(disposition: ExerciseAttemptDisposition) {
    if activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      let attemptID = activeExerciseAttemptID
    {
      boundaryApproachVisionTasks.removeValue(forKey: attemptID)?.cancel()
      boundaryApproachAdvisories.removeValue(forKey: attemptID)
      pendingBoundaryFinalPositions.removeValue(forKey: attemptID)
      pendingBoundaryOwnerIDs.removeValue(forKey: attemptID)
      pendingBoundaryStopCapabilities.removeValue(forKey: attemptID)
    }
    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
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
            value: .up
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

  var currentPenStateAggregate: LatestStateAggregate<PenState>? {
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

  private func drawingTrialPayloadSnapshot() -> DrawingTrialPayloadSnapshot {
    DrawingTrialPayloadSnapshot(
      step: observedDrawingTrialStep,
      localPreLineBaseline: localPreLineBaseline,
      revealPosition: drawingTrialRevealPosition,
      tipRegistrationRevisionID: drawingTrialTipRegistrationRevisionID,
      postLineFrame: explorationPostLineFrame,
      lineStart: drawingTrialLineStart,
      strokeEvidence: drawingTrialStrokeEvidence,
      inkObservation: lastInkObservation,
      inkStatus: explorationInkStatus,
      assessment: drawingTrialAssessment,
      episode: currentExplorationEpisode,
      completedEpisodes: completedExplorationEpisodes
    )
  }

  private func restoreDrawingTrialPayload(_ snapshot: DrawingTrialPayloadSnapshot) {
    observedDrawingTrialStep = snapshot.step
    localPreLineBaseline = snapshot.localPreLineBaseline
    drawingTrialRevealPosition = snapshot.revealPosition
    drawingTrialTipRegistrationRevisionID = snapshot.tipRegistrationRevisionID
    explorationPostLineFrame = snapshot.postLineFrame
    drawingTrialLineStart = snapshot.lineStart
    drawingTrialStrokeEvidence = snapshot.strokeEvidence
    lastInkObservation = snapshot.inkObservation
    explorationInkStatus = snapshot.inkStatus
    drawingTrialAssessment = snapshot.assessment
    currentExplorationEpisode = snapshot.episode
    completedExplorationEpisodes = snapshot.completedEpisodes
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

  private func discoverySequenceID(
    for step: HumanGuidedDiscoveryStep
  ) -> DiscoverySequenceID? {
    switch step {
    case .penInteraction: .penInteraction
    case .pairedBoundaryDiscoveryAndCentering: sequenceID(for: selectedBoundaryDirection)
    case .calibrateCameraAndVisibleCap, .calibratePenContactFromSparseMarks:
      nil
    }
  }

  private func learningPathStatus(for itemID: LearningPathItemID) -> LearningPathStageStatus {
    if itemID == .stage(.adaptiveDrawing) { return .future }
    if itemIsComplete(itemID) { return .complete }
    let representsCurrentStage: Bool =
      if case .stage(let stage) = itemID {
        currentLearningPathItemID.stage == stage
      } else {
        false
      }
    if itemID == currentLearningPathItemID || representsCurrentStage {
      if itemID.stage == .humanGuidedDiscovery,
        discoveryError != nil || explorationError != nil
      {
        return .needsAttention
      }
      if itemID.stage == .observedDrawingTrials, explorationError != nil {
        return .needsAttention
      }
      if itemID == .stage(.connect), machineError != nil { return .needsAttention }
      return .current
    }
    return .next
  }

  private func itemIsComplete(_ itemID: LearningPathItemID) -> Bool {
    let discoveryComplete =
      penInteractionCompleted
      && centerArrivalPosition != nil
      && machineCameraRegistration != nil
      && tipCameraRegistration != nil
    return switch itemID {
    case .stage(.connect): controllerSessionEstablished
    case .stage(.enableMotion): controllerSessionEstablished && motionAuthorizationEnabled
    case .stage(.humanGuidedDiscovery): discoveryComplete
    case .stage(.observedDrawingTrials): drawingTrialAssessment != nil
    case .stage(.adaptiveDrawing): false
    case .humanGuidedDiscovery(.penInteraction): penInteractionCompleted
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      centerArrivalPosition != nil
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      machineCameraRegistration != nil
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      tipCameraRegistration != nil
    case .observedDrawingTrial(let step):
      drawingTrialAssessment != nil
        || (step.rawValue < observedDrawingTrialStep.rawValue
          && drawingArtifactRevision(for: step) != nil)
    }
  }

  private func itemIsRepeatable(_ itemID: LearningPathItemID) -> Bool {
    switch itemID {
    case .humanGuidedDiscovery(.penInteraction),
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      .observedDrawingTrial(.compareIntendedAndObservedGeometry):
      true
    default:
      false
    }
  }

  private func learningPathSummary(for itemID: LearningPathItemID) -> String {
    switch itemID {
    case .stage(.connect):
      controllerSessionEstablished
        ? (frameMode == .simulated
          ? "The nonphysical learning simulator session is connected."
          : "The selected controller is responsive.")
        : (frameMode == .simulated
          ? "Connect the nonphysical learning simulator."
          : "Select and connect one responsive controller.")
    case .stage(.enableMotion):
      motionAuthorizationEnabled
        ? "Motion is enabled for typed operations."
        : "Enable Motion for this controller session."
    case .stage(.humanGuidedDiscovery):
      "Observe Pen Interaction, four paired boundaries, center arrival, camera/cap calibration, and sparse-mark pen-contact calibration."
    case .humanGuidedDiscovery(.penInteraction):
      "Observe the physical pen UP, DOWN, then UP again."
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      "Observe both X sides and both Y sides in paired order, then move Pen Up to their estimated center."
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      "Capture five exact cap samples at normalized 10/50/90 cross positions, validate two independent holdouts, then explicitly accept or reject the all-five camera fit."
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      "Draw five centered 2 mm-radius circles with the full configured Pen Down, reveal each at safe X-max toward machine Y-zero, select its exact frozen-frame center, and accept only the smallest model that passes both holdouts."
    case .stage(.observedDrawingTrials):
      "Create one attributable line, observe actual ink, and compare geometry."
    case .observedDrawingTrial(let step): drawingTrialActionText(for: step)
    case .stage(.adaptiveDrawing):
      "Adaptive Drawing remains Future until multi-stroke checkpoint learning is implemented."
    }
  }

  private func exerciseActionStrip(
    for itemID: LearningPathItemID
  ) -> ExerciseActionStripPresentation? {
    if activeExerciseAttemptOwnerID == itemID {
      var actions: [ExerciseActionDescriptor] = []
      if let contextualStopPresentation,
        let target = activeStopTarget,
        !isManualStopTarget(target)
      {
        if stopDispositionLatch == nil {
          actions.append(
            ExerciseActionDescriptor(
              kind: .stop(contextualStopPresentation.capabilityID),
              title: target.operationOwner.isBoundaryOwner ? "Stop Boundary" : "Stop",
              role: .destructive
            )
          )
        }
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: actions,
          mustRemainVisible: true
        )
      }
      if itemID.stage == .humanGuidedDiscovery,
        let ambiguityReason = learningStickyAmbiguityReason
      {
        actions = [
          ExerciseActionDescriptor(
            kind: .start,
            title: "Machine action unavailable",
            unavailableReason: ambiguityReason
          )
        ]
      } else if case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) = itemID {
        if currentCameraCalibrationPhase != nil {
          actions = [
            ExerciseActionDescriptor(
              kind: .runCameraCalibrationAndBuildProposal,
              title: "Capturing Five Cap Samples…",
              unavailableReason: "Current-camera calibration is in progress."
            )
          ]
        } else if proposedMachineCameraRegistration == nil {
          actions = [
            ExerciseActionDescriptor(
              kind: .runCameraCalibrationAndBuildProposal,
              title: "Capture Five Cap Samples",
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: "Discard Cap Samples",
              role: .destructive
            ),
          ]
        } else {
          actions = [
            ExerciseActionDescriptor(
              kind: .acceptCameraCalibrationProposal,
              title: "Accept Camera and Visible-Cap Fit",
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectCameraCalibrationProposal,
              title: "Reject Camera Fit",
              role: .destructive
            ),
          ]
        }
      } else if case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) = itemID {
        switch sparseTipCalibrationCoordinator.phase {
        case .idle:
          actions = [
            ExerciseActionDescriptor(
              kind: .createNextSparseTipMark,
              title: "Create Next 2 mm Circle",
              role: .positive
            )
          ]
        case .preparingMark, .drawingMark, .revealing:
          actions = [
            ExerciseActionDescriptor(
              kind: .createNextSparseTipMark,
              title: "Creating and Revealing Mark…",
              unavailableReason: "The supervised 2 mm calibration-circle operation is in progress."
            )
          ]
        case .awaitingFrozenClick:
          actions = []
        case .reviewingClick:
          actions = [
            ExerciseActionDescriptor(
              kind: .reClickSparseTipFrame,
              title: "Re-click This Exact Frame"
            ),
            ExerciseActionDescriptor(
              kind: .acceptSparseTipMark,
              title: "Accept Mark Center",
              role: .positive
            ),
          ]
        case .fittingCandidates:
          actions = [
            ExerciseActionDescriptor(
              kind: .acceptTipCalibration,
              title: "Fitting Smallest Passing Model…",
              unavailableReason: "Candidate selection is in progress."
            )
          ]
        case .reviewingFinalProposal:
          actions = [
            ExerciseActionDescriptor(
              kind: .acceptTipCalibration,
              title: "Accept Tip Calibration",
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectTipCalibration,
              title: "Reject Tip Calibration",
              role: .destructive
            ),
          ]
        case .possibleInkBlacklisted(_, let reason), .holdoutFailed(let reason),
          .rejected(let reason):
          actions = [
            ExerciseActionDescriptor(
              kind: .rejectTipCalibration,
              title: "No Automatic Redraw",
              unavailableReason: reason
            ),
            ExerciseActionDescriptor(
              kind: .paperReplaced,
              title: "Record Paper Replacement",
              role: .positive
            ),
          ]
        case .accepted:
          actions = []
        }
      } else if case .observedDrawingTrial(.compareIntendedAndObservedGeometry) = itemID {
        actions.append(
          contentsOf: DrawingTrialAssessment.allCases.map { assessment in
            ExerciseActionDescriptor(
              kind: .recordDrawingTrialAssessment(assessment),
              title: assessment.title,
              role: assessment == .observedGeometryAccepted ? .positive : .standard
            )
          })
      } else if let sequenceID = activeDiscoverySequenceID,
        let choices = discoveryTransactions[sequenceID]?.currentStep?.question?.choices
      {
        actions.append(
          contentsOf: choices.map { choice in
            ExerciseActionDescriptor(
              kind: .choice(choice),
              title: choice.exactPhrase,
              role: choice == .yes ? .positive : .standard
            )
          })
      }
      if stopDispositionLatch == nil && currentCameraCalibrationPhase == nil {
        actions.append(
          ExerciseActionDescriptor(kind: .cancel, title: "Cancel Attempt", role: .destructive)
        )
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: actions,
        mustRemainVisible: activeStopTarget != nil
      )
    }

    if restartableExerciseItemID == itemID {
      guard machineSnapshot?.machine.stickyAmbiguity == nil else { return nil }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .restart,
            title: "Restart",
            role: .positive
          )
        ]
      )
    }

    if itemIsComplete(itemID), itemID.isExercise {
      let actions: [ExerciseActionDescriptor]
      if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering) {
        actions = pairedBoundaryProgress.acceptedDirections.flatMap { direction in
          [
            ExerciseActionDescriptor(
              kind: .redoBoundary(direction),
              title: "Redo \(direction.displayName) Boundary"
            ),
            ExerciseActionDescriptor(
              kind: .recordAnotherBoundaryAttempt(direction),
              title: "Record Another \(direction.displayName) Attempt"
            ),
          ]
        }
      } else {
        var repeatActions = [
          ExerciseActionDescriptor(kind: .redoThisStep, title: "Redo This Step")
        ]
        if itemIsRepeatable(itemID) {
          repeatActions.append(
            ExerciseActionDescriptor(
              kind: .recordAnotherAttempt,
              title: "Record Another Attempt"
            )
          )
        }
        actions = repeatActions
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: actions
      )
    }

    guard itemID == currentLearningPathItemID else { return nil }
    let reason: String?
    switch itemID {
    case .humanGuidedDiscovery(.penInteraction):
      reason = discoveryStartUnavailableReason(for: .penInteraction)
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      reason = discoveryStartUnavailableReason(for: sequenceID(for: selectedBoundaryDirection))
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      reason =
        frameMode == .simulated || cameraIsLive
        ? nil : "A current LIVE camera frame is required."
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      reason =
        frameMode == .simulated || cameraIsLive
        ? nil : "A current LIVE camera frame is required."
    case .observedDrawingTrial(let step):
      reason = drawingTrialActionUnavailableReason(for: step)
    case .stage:
      return nil
    }
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      pairedBoundaryProgress.isComplete,
      centerArrivalPosition == nil
    {
      if centerArrivalRetryRequired {
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .moveToEstimatedCenter,
              title: "Retry Center Arrival",
              role: .positive,
              unavailableReason: reason
            )
          ]
        )
      }
      let centerMoveUnavailableReason =
        estimatedMachineCenter == nil
        ? (discoveryError ?? "Accepted boundaries do not currently derive a valid center.")
        : reason
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .moveToEstimatedCenter,
            title: estimatedMachineCenter == nil
              ? "Center Derivation Needs Attention" : "Move to Estimated Center",
            role: .positive,
            unavailableReason: centerMoveUnavailableReason
          )
        ]
          + pairedBoundaryProgress.acceptedDirections.flatMap { direction in
            [
              ExerciseActionDescriptor(
                kind: .redoBoundary(direction),
                title: "Redo \(direction.displayName) Boundary"
              ),
              ExerciseActionDescriptor(
                kind: .recordAnotherBoundaryAttempt(direction),
                title: "Record Another \(direction.displayName) Attempt"
              ),
            ]
          }
      )
    }
    if case .observedDrawingTrial(let step) = itemID {
      let kind: ExerciseActionKind =
        switch step {
        case .chooseIsolatedLinePlan: .chooseIsolatedLinePlan(selectedLineDirection)
        case .captureLocalPreLineBaseline: .captureLocalPreLineBaseline
        case .moveToLineStart: .moveToLineStart
        case .drawIsolatedLine: .drawIsolatedLine
        case .revealAndObserveNewInk: .revealAndObserveNewInk
        case .compareIntendedAndObservedGeometry: .start
        }
      let direction =
        step == .chooseIsolatedLinePlan
        ? ExerciseDirectionSelectionPresentation(
          purpose: .linePlan,
          selected: selectedLineDirection
        ) : nil
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: kind,
            title: drawingTrialActionTitle(for: step),
            role: .positive,
            unavailableReason: reason
          )
        ],
        directionSelection: direction
      )
    }
    if itemID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) {
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .runCameraCalibrationAndBuildProposal,
            title: "Capture Five Cap Samples",
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks),
      let checkpoint = quarantinedTipCalibrationCheckpoint,
      checkpoint.registration.applicability.paperContactPlane.rawValue
        == explorationToolPaperRevision
    {
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .revalidateTipCalibrationCheckpoint,
            title: "Revalidate Saved Tip Calibration",
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibratePenContactFromSparseMarks) {
      switch sparseTipCalibrationCoordinator.phase {
      case .possibleInkBlacklisted, .holdoutFailed, .rejected:
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .paperReplaced,
              title: "Record Paper Replacement",
              role: .positive,
              unavailableReason: reason
            )
          ]
        )
      default:
        break
      }
    }
    let directionSelection =
      itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
      ? ExerciseDirectionSelectionPresentation(
        purpose: .boundary,
        options: pairedBoundaryProgress.allowedDirections,
        selected: selectedBoundaryDirection
      ) : nil
    return ExerciseActionStripPresentation(
      ownerID: itemID,
      actions: [
        ExerciseActionDescriptor(
          kind: .start,
          title: "Start",
          role: .positive,
          unavailableReason: reason
        )
      ],
      directionSelection: directionSelection
    )
  }

  private func isManualStopTarget(_ target: ContextualStopTarget) -> Bool {
    if case .manualJog = target { return true }
    return false
  }

  private func stageExpectedObservation(_ stage: LearningPathStage) -> [PresentationFragment] {
    switch stage {
    case .connect: [.text("A responsive selected controller session.")]
    case .enableMotion: [.text("The current session reports Motion Enabled.")]
    case .humanGuidedDiscovery: [.cue(.up), .text("boundary, cap-map, and tip-map evidence.")]
    case .observedDrawingTrials: [.text("Observed ink and a typed geometry comparison.")]
    case .adaptiveDrawing: [.text("Future multi-stroke observed adaptation.")]
    }
  }

  private func stageEvidence(_ stage: LearningPathStage) -> [ExerciseEvidencePresentation] {
    switch stage {
    case .connect:
      [
        ExerciseEvidencePresentation(
          label: "Controller", fragments: [.text(controllerConnectionText)]),
        ExerciseEvidencePresentation(
          label: "Accepted artifact checkpoint",
          fragments: [.text(acceptedArtifactCheckpointStatus.text)]
        ),
      ]
    case .enableMotion:
      [ExerciseEvidencePresentation(label: "Motion", fragments: [.text(motionGuardStateText)])]
    case .humanGuidedDiscovery:
      [
        ExerciseEvidencePresentation(
          label: "Boundary samples", fragments: [.text("N=\(relevantBoundaryObservationCount)")])
      ]
    case .observedDrawingTrials:
      [ExerciseEvidencePresentation(label: "Ink", fragments: [.text(explorationInkStatus)])]
    case .adaptiveDrawing:
      []
    }
  }

  private func discoveryReviewInstructions(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction:
      [.text("Confirm"), .cue(.up), .text("then"), .cue(.down), .text("then finish"), .cue(.up)]
    case .pairedBoundaryDiscoveryAndCentering:
      [.text("Choose a direction, observe the side, then press"), .cue(.stop)]
    case .calibrateCameraAndVisibleCap:
      [
        .text(
          "Capture five exact cap centers at C, X−, Y+, X+, and Y−; fit the first three, verify two holdouts, then explicitly accept or reject the all-five refit."
        )
      ]
    case .calibratePenContactFromSparseMarks:
      [
        .text(
          "Draw one centered 2 mm-radius circle at each cross position, reveal it Pen Up at safe X-max toward machine Y-zero, click its center on the frozen exact frame, and review the smallest passing model."
        )
      ]
    }
  }

  private func discoveryReviewExpectation(
    _ step: HumanGuidedDiscoveryStep
  ) -> [PresentationFragment] {
    switch step {
    case .penInteraction: [.text("Latest accepted physical pose is"), .cue(.up)]
    case .pairedBoundaryDiscoveryAndCentering:
      [.text("Four accepted sides and one explicit arrival at the estimated machine center.")]
    case .calibrateCameraAndVisibleCap:
      [
        .text(
          "Three fit samples, two independent holdouts, and one current all-five machine-camera revision."
        )
      ]
    case .calibratePenContactFromSparseMarks:
      [
        .text(
          "Five immutable click observations and one explicitly accepted tip-camera registration.")
      ]
    }
  }

  private func discoveryInstructionFragments(
    _ action: DiscoveryAction
  ) -> [PresentationFragment] {
    switch action {
    case .startBoundaryJog(let direction):
      [.text("Start motion toward"), .cue(.direction(direction))]
    case .awaitContextualStop(let direction):
      [.text("Observe"), .cue(.direction(direction)), .text("and press"), .cue(.stop)]
    case .awaitPhysicalPenConfirmation(let state, _):
      [.text("Confirm the pen is physically"), .cue(state == .up ? .up : .down)]
    case .actuatePen(let command):
      [.text("Command pen"), .cue(command.commandedState == .up ? .up : .down)]
    default: [.text(discoveryActionText(action))]
    }
  }

  private func discoveryExpectationFragments(
    _ expectation: DiscoveryEventExpectation
  ) -> [PresentationFragment] {
    switch expectation {
    case .operatorChoice:
      [.cue(.yes), .text("or"), .cue(.no), .text("is recorded for this question.")]
    case .operatorStopRequested: [.cue(.stop), .text("is latched before cancellation.")]
    case .physicalPenConfirmed(let state, _):
      [.text("The operator confirms"), .cue(state == .up ? .up : .down)]
    default: [.text(discoveryExpectationText(expectation))]
    }
  }

  private func discoveryQuestionPresentation(
    _ action: DiscoveryAction
  ) -> ExerciseQuestionPresentation? {
    switch action {
    case .awaitOperatorChoice(let question):
      ExerciseQuestionPresentation(
        prompt: [.text(question.prompt)],
        choices: question.choices
      )
    case .awaitPhysicalPenConfirmation(let state, let question):
      ExerciseQuestionPresentation(
        prompt: [
          .text(question.prompt),
          .text("Required physical pose:"),
          .cue(state == .up ? .up : .down),
        ],
        choices: question.choices
      )
    default:
      nil
    }
  }

  private func discoveryEvidence(
    _ transaction: DiscoveryTransaction?
  ) -> [ExerciseEvidencePresentation] {
    transaction?.evidenceSummaries.enumerated().map { index, evidence in
      ExerciseEvidencePresentation(
        label: "Evidence \(index + 1)",
        fragments: [.text(evidence.summary)]
      )
    } ?? []
  }

  private func protocolEvidence(
    for step: HumanGuidedDiscoveryStep
  ) -> [ExerciseEvidencePresentation] {
    switch step {
    case .penInteraction:
      return []
    case .pairedBoundaryDiscoveryAndCentering:
      var evidence: [ExerciseEvidencePresentation] = []
      if let localFrame = learnedLocalCoordinateFrame, let center = estimatedMachineCenter,
        let localCenter = try? localFrame.localPoint(fromRaw: center.point)
      {
        evidence.append(
          ExerciseEvidencePresentation(
            label: "Learned local coordinate frame (mm)",
            fragments: [
              .text(
                String(
                  format:
                    "origin at accepted X−/Y− · X 0 ... %.3f · Y 0 ... %.3f · center %.3f, %.4f",
                  localFrame.xSpanMM,
                  localFrame.ySpanMM,
                  localCenter.x,
                  localCenter.y
                )
              )
            ]
          )
        )
      } else {
        evidence.append(
          ExerciseEvidencePresentation(
            label: "Controller coordinate frame",
            fragments: [
              .text(
                "Raw Controller MPos is millimetre-valued relative to the controller's current origin; positive and negative signs are not paper-local coordinates. All four accepted side aggregates are required before a learned local frame exists."
              )
            ]
          )
        )
      }
      evidence.append(
        contentsOf: BoundaryDirection.allCases.compactMap { direction in
          guard let aggregate = boundarySideAggregates[direction],
            let attemptID = aggregate.includedAttemptIDs.last,
            let attemptEvidence = boundaryAttemptEvidenceByAttemptID[attemptID]
          else { return nil }
          return
            ExerciseEvidencePresentation(
              label: "Raw Controller MPos · \(direction.displayName)",
              fragments: [
                .text(
                  String(
                    format: "X %.3f Y %.3f · aggregate %.3f mm · N=%d · revision %@",
                    attemptEvidence.finalPosition.point.x,
                    attemptEvidence.finalPosition.point.y,
                    aggregate.estimateMM,
                    aggregate.validSampleCount,
                    aggregate.revisionID.rawValue.uuidString.lowercased()
                  ))
              ]
            )
        })
      if let center = estimatedMachineCenter {
        evidence.append(
          ExerciseEvidencePresentation(
            label: learnedLocalCoordinateFrame == nil
              ? "Estimated raw machine center" : "Raw Controller MPos center provenance",
            fragments: [
              .text(
                String(
                  format: "X %.3f Y %.3f · spans X %.3f mm Y %.3f mm · %@",
                  center.point.x,
                  center.point.y,
                  center.xSpanMM,
                  center.ySpanMM,
                  center.estimatorRevision
                ))
            ]
          ))
        let current = try? currentMachinePosition()
        evidence.append(
          ExerciseEvidencePresentation(
            label: "Center travel",
            fragments: [
              .text(
                current.map { position in
                  let delta = try? Vector2<MachineSpace>(
                    dx: center.point.x - position.point.x,
                    dy: center.point.y - position.point.y
                  )
                  let selection = delta.map { travelFeedSelection(for: $0) }
                  return String(
                    format: "current X %.3f Y %.3f · delta X %.3f Y %.3f · feed %@ · source %@",
                    position.point.x,
                    position.point.y,
                    center.point.x - position.point.x,
                    center.point.y - position.point.y,
                    selection.map {
                      String(format: "%.0f mm/min", $0.requestedFeedMMPerMinute)
                    } ?? "not selected",
                    selection.map {
                      switch $0.source {
                      case .controllerReportedCeiling: "Controller-reported ceiling"
                      case .existingFallback: "Existing fallback"
                      }
                    } ?? "unavailable"
                  )
                } ?? "current MPos unavailable")
            ]
          ))
      }
      return evidence
    case .calibrateCameraAndVisibleCap:
      let registration = proposedMachineCameraRegistration ?? machineCameraRegistration
      return [
        ExerciseEvidencePresentation(
          label: "Five-position cap calibration",
          fragments: [
            .text(
              registration.map {
                "\($0.fitCorrespondenceProvenance.count) fit samples · \($0.holdoutCorrespondenceProvenance.count) independent holdouts · \($0.correspondenceFrameIDs.count) exact frames"
              } ?? "not captured")
          ]
        ),
        ExerciseEvidencePresentation(
          label: proposedMachineCameraRegistration == nil
            ? "Accepted camera/cap fit" : "Staged camera/cap fit",
          fragments: [
            .text(
              registration.map {
                String(
                  format: "holdouts %.3f / %.3f px · limit %.3f px · all-five uncertainty %.3f px",
                  $0.holdoutResidualPixels[0],
                  $0.holdoutResidualPixels[1],
                  $0.maximumHoldoutResidualPixels,
                  $0.uncertaintyPixels
                )
              } ?? "not fitted")
          ]
        ),
      ]
    case .calibratePenContactFromSparseMarks:
      let proposal = proposedTipCameraRegistration ?? tipCameraRegistration
      return [
        ExerciseEvidencePresentation(
          label: "Sparse 2 mm-radius circles",
          fragments: [
            .text(
              "\(sparseTipCalibrationCoordinator.acceptedObservations.count)/5 accepted · \(sparseTipCalibrationCoordinator.blacklistedPositions.count) blacklisted · \(String(describing: sparseTipCalibrationCoordinator.phase))"
            )
          ]
        ),
        ExerciseEvidencePresentation(
          label: "Smallest passing model",
          fragments: [
            .text(
              proposal.map {
                let holdouts =
                  $0.modelForm == .constantCameraPixelCorrection
                  ? $0.modelSelectionEvidence.constantHoldouts
                  : $0.modelSelectionEvidence.affineHoldouts
                return
                  "\($0.modelForm.rawValue) · holdouts \(holdouts.map { String(format: "%.3f px", $0.residualPixels) }.joined(separator: ", ")) · uncertainty \(String(format: "%.3f px", $0.uncertainty.maximumResidualPixels))"
              } ?? "Tip not calibrated")
          ]
        ),
      ]
    }
  }

  private func operationActivityPresentation(
    for itemID: LearningPathItemID,
    transaction: DiscoveryTransaction?
  ) -> OperationActivityPresentation? {
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      centerArrivalRetryRequired,
      let explorationError
    {
      return OperationActivityPresentation(
        actor: "Controller",
        action: "Move to Estimated Center",
        outcome: .needsAttention,
        detail: [.text(explorationError)],
        acceptedResult: [.text("All four accepted Boundary aggregates remain current.")],
        recovery: [.text("Use Retry Center Arrival; it requests only the remaining delta.")]
      )
    }
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      let activity = boundaryActivityRecords.last
    {
      let retained = activity.retainedRevisionIDs
        .map { $0.rawValue.uuidString.lowercased() }
        .sorted()
        .joined(separator: ", ")
      return OperationActivityPresentation(
        actor: activity.actor.rawValue,
        action: activity.operation.actionLabel,
        phase: activity.phase.rawValue,
        outcomeLabel: activity.disposition.outcomeLabel,
        outcome: activity.disposition.presentationOutcome,
        detail: [.text(activity.detail.text)],
        acceptedResult: activity.acceptedFallbackRemainsCurrent
          ? [.text("The previously accepted aggregate remains current at revision \(retained).")]
          : [],
        recovery: activity.recovery.text.isEmpty ? [] : [.text(activity.recovery.text)]
      )
    }
    if itemID == .humanGuidedDiscovery(.calibrateCameraAndVisibleCap),
      let currentCameraCalibrationPhase
    {
      return OperationActivityPresentation(
        actor: activeStopTarget == nil ? "Camera and learning runtime" : "Plotter controller",
        action: "Build Camera Calibration Proposal",
        phase: currentCameraCalibrationPhase.description,
        outcome: .inProgress,
        detail: [
          .text(
            "The app owns three exact non-collinear fit samples, two independent holdouts, and the all-five accepted camera/cap fit."
          )
        ],
        recovery: activeStopTarget == nil
          ? [.text("No operator calibration move or hand-drawn triangle is required.")]
          : [.text("Stop remains bound to the currently admitted Pen-Up move.")]
      )
    }
    if itemID.stage == .humanGuidedDiscovery, let explorationError {
      return OperationActivityPresentation(
        actor: activeStopTarget == nil ? "Learning runtime" : "Plotter controller",
        action: currentLearningPathItemID.title,
        outcome: .needsAttention,
        detail: [.text(explorationError)],
        recovery: currentCameraCalibrationFailure.map {
          [.text($0.recoveryDescription)]
        } ?? [.text("Resolve the named controller, camera, or exact-frame fact, then retry.")]
      )
    }
    if itemID.stage == .humanGuidedDiscovery, let discoveryError {
      return OperationActivityPresentation(
        actor: transaction?.currentStep?.participant.displayName ?? "Learning runtime",
        action: transaction?.currentStep.map { discoveryActionText($0.action) }
          ?? "Human-Guided Discovery",
        outcome: .needsAttention,
        detail: [.text(discoveryError)],
        recovery: restartableExerciseItemID == itemID
          ? [.text("Review the recorded outcome, then use Restart to create a new attempt.")]
          : [.text("Resolve the named controller, camera, or observation fact before continuing.")]
      )
    }
    if itemID.stage == .observedDrawingTrials, let explorationError {
      let recovery: [PresentationFragment]
      if drawingTrialStrokeEvidence != nil,
        observedDrawingTrialStep == .revealAndObserveNewInk
      {
        recovery = [
          .text(
            "Ink may exist. Draw is unavailable; resolve Pen Up if needed, then return and observe the existing stroke."
          )
        ]
      } else if restartableExerciseItemID == itemID {
        recovery = [.text("Use Restart only after the failed attempt has settled.")]
      } else {
        recovery = [.text("Resolve the named subsystem fact before continuing.")]
      }
      return OperationActivityPresentation(
        actor: drawingTrialParticipant(for: observedDrawingTrialStep),
        action: drawingTrialActionText(for: observedDrawingTrialStep),
        outcome: .needsAttention,
        detail: [.text(explorationError)],
        recovery: recovery
      )
    }
    if itemID == .stage(.connect), let machineError {
      return OperationActivityPresentation(
        actor: "Controller session",
        action: controllerConnectionActionTitle,
        outcome: .needsAttention,
        detail: [.text(machineError)],
        recovery: [.text(workbenchStatusText)]
      )
    }
    if let transaction {
      switch transaction.state {
      case .active, .cancelling:
        if let step = transaction.currentStep {
          return OperationActivityPresentation(
            actor: step.participant.displayName,
            action: discoveryActionText(step.action),
            outcome: .inProgress,
            detail: lastContextualStopAuditRecord.map {
              [.text("\($0.actor) · \($0.action) · \($0.outcome)")]
            } ?? [],
            recovery: []
          )
        }
      case .succeeded:
        return OperationActivityPresentation(
          actor: "Learning runtime",
          action: transaction.definition.title,
          outcome: .succeeded,
          detail: transaction.evidenceSummaries.last.map { [.text($0.summary)] } ?? [],
          recovery: []
        )
      case .cancelled:
        return OperationActivityPresentation(
          actor: lastContextualStopAuditRecord?.actor ?? "Operator",
          action: lastContextualStopAuditRecord?.action ?? "Cancel Attempt",
          outcome: .cancelled,
          detail: lastContextualStopAuditRecord.map { [.text($0.outcome)] } ?? [],
          recovery: [.text("Use Restart to create a new attempt.")]
        )
      case .failed:
        break
      case .notStarted:
        break
      }
    }
    if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering),
      let audit = lastContextualStopAuditRecord
    {
      return OperationActivityPresentation(
        actor: audit.actor,
        action: audit.action,
        outcome: audit.disposition == .operatorStop ? .inProgress : .cancelled,
        detail: [.text(audit.outcome)],
        recovery: audit.disposition == .operatorStop
          ? [
            .text(
              "The original owner must settle at Idle/final MPos before the controller-side commit continues."
            )
          ]
          : [.text("Use Restart to create a new attempt.")]
      )
    }
    return nil
  }

  private func subsystemStatusPresentations(
    for itemID: LearningPathItemID,
    transaction: DiscoveryTransaction?
  ) -> [SubsystemStatusPresentation] {
    let motionGateReason: String? = {
      if !controllerSessionEstablished {
        return frameMode == .simulated
          ? "Connect the learning simulator first."
          : "Select and connect one responsive controller."
      }
      if !motionAuthorizationEnabled { return "Enable Motion for this controller session." }
      // Coordinator/operation ownership is reported in its own row instead of
      // being mislabeled as a Controller safety refusal.
      if currentCameraCalibrationPhase != nil || activeStopTarget != nil {
        return nil
      }
      return directCarriageMotionUnavailableReason
    }()
    let controllerState: String
    if !controllerSessionEstablished {
      controllerState = "Disconnected"
    } else if !motionAuthorizationEnabled {
      controllerState = "Motion disabled"
    } else if activeStopTarget != nil {
      controllerState = "Operation active"
    } else if currentCameraCalibrationPhase != nil {
      controllerState = "Ready / coordinator held"
    } else if motionGateReason != nil {
      controllerState = "Admission blocked"
    } else {
      controllerState = "Idle / admissible"
    }

    let motionOwnerDetail: String
    if let activeStopTarget {
      motionOwnerDetail =
        "An admitted operation owns motion under Stop capability \(activeStopTarget.capabilityID.rawValue.uuidString.lowercased())."
    } else {
      motionOwnerDetail = "No admitted operation currently owns controller motion."
    }

    let isBoundaryReview =
      itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    let visionDetail: String
    let visionState: String
    let visionBlocksMotion: Bool
    let visionRole: SubsystemAuthorityRole
    if let currentCameraCalibrationPhase {
      visionState = currentCameraCalibrationPhase.description
      visionBlocksMotion = true
      visionRole = .operationOwner
      visionDetail =
        "Current-camera calibration owns a multi-step optical-registration operation. New manual motion is blocked until it settles; any currently admitted move is also shown under Motion owner."
    } else if scopedVisionAnalysisActive {
      let analysisIsActive = visionAnalysisSnapshot.activeFrameSequence != nil
      visionState =
        analysisIsActive
        ? "Motion-scoped analysis · preview held"
        : "Motion-scoped analysis · live recovery"
      visionBlocksMotion = false
      visionRole = .advisoryEvidence
      visionDetail =
        analysisIsActive
        ? "One immutable frame is being analyzed off the main actor. Preview publication is held until it settles; raw camera delivery continues."
        : "The owned movement is still active between computations. When it settles, the selected overlay settings determine whether background analysis continues."
    } else if case .running(let cadence) = visionAnalysisSnapshot.state {
      visionState = "Overlay analysis · running"
      visionBlocksMotion = false
      visionRole = .advisoryEvidence
      visionDetail =
        "Selected scene overlays keep newest-only analysis running at up to \(cadence.rawValue) frames per second without changing preview appearance or automatic preview publication."
    } else {
      visionState = "Idle"
      visionBlocksMotion = false
      visionRole = .advisoryEvidence
      visionDetail = "No foreground Vision operation is active."
    }

    let boundaryAuthoritySuffix =
      isBoundaryReview
      ? " Stage 3.2 boundary acceptance never calls Camera or Vision."
      : ""
    let commitIsActive: Bool = {
      guard case .commitBoundaryObservation = transaction?.currentStep?.action else {
        return false
      }
      return true
    }()

    return [
      SubsystemStatusPresentation(
        id: "controller",
        subsystem: "Controller",
        state: controllerState,
        role: .motionGate,
        blocksNewMotion: motionGateReason != nil,
        detail: [
          .text(
            motionGateReason ?? "Controller facts currently admit a new direct carriage request.")
        ]
      ),
      SubsystemStatusPresentation(
        id: "motion-owner",
        subsystem: "Motion owner",
        state: activeStopTarget == nil ? "Unowned" : "Owned",
        role: .operationOwner,
        blocksNewMotion: activeStopTarget != nil,
        detail: [.text(motionOwnerDetail)]
      ),
      SubsystemStatusPresentation(
        id: "camera",
        subsystem: "Camera",
        state: cameraStateText,
        role: .advisoryEvidence,
        blocksNewMotion: false,
        detail: [
          .text(
            "Camera state does not accept or reject a machine boundary.\(boundaryAuthoritySuffix)"
          )
        ]
      ),
      SubsystemStatusPresentation(
        id: "vision",
        subsystem: "Vision / processing",
        state: visionState,
        role: visionRole,
        blocksNewMotion: visionBlocksMotion,
        detail: [.text(visionDetail + boundaryAuthoritySuffix)]
      ),
      SubsystemStatusPresentation(
        id: "learning-commit",
        subsystem: "Learning commit",
        state: commitIsActive ? "Committing controller settlement" : "Idle",
        role: .evidenceCommit,
        blocksNewMotion: false,
        detail: [
          .text(
            isBoundaryReview
              ? "Boundary commit consumes typed direction + operator Stop + controller Idle/final MPos only."
              : "Learning commits record evidence after the owning operation settles."
          )
        ]
      ),
    ]
  }

  private func drawingTrialInstructionFragments(
    for step: ObservedDrawingTrialStep
  ) -> [PresentationFragment] {
    [.text(drawingTrialActionText(for: step))]
  }

  private func drawingTrialExpectationFragments(
    for step: ObservedDrawingTrialStep
  ) -> [PresentationFragment] {
    [.text(drawingTrialExpectationText(for: step))]
  }

  private func drawingTrialEvidence(
    for step: ObservedDrawingTrialStep
  ) -> [ExerciseEvidencePresentation] {
    switch step {
    case .chooseIsolatedLinePlan:
      [
        ExerciseEvidencePresentation(
          label: "Line plan",
          fragments: [
            .text(
              drawingTrialLineStart.map {
                String(
                  format: "%@ from X %.3f Y %.3f", selectedLineDirection.displayName, $0.point.x,
                  $0.point.y)
              } ?? "not chosen")
          ])
      ]
    case .captureLocalPreLineBaseline:
      [
        ExerciseEvidencePresentation(
          label: "Local pre-line baseline",
          fragments: [.text(localPreLineBaseline?.frame.id.rawValue ?? "not captured")])
      ]
    case .moveToLineStart:
      [
        ExerciseEvidencePresentation(
          label: "Line start",
          fragments: [
            .text(
              drawingTrialLineStart.map { String(format: "X %.3f Y %.3f", $0.point.x, $0.point.y) }
                ?? "not reached")
          ])
      ]
    case .drawIsolatedLine:
      [
        ExerciseEvidencePresentation(
          label: "Controller",
          fragments: [.text(drawingTrialStrokeEvidence == nil ? "not settled" : "settled")])
      ]
    case .revealAndObserveNewInk:
      [ExerciseEvidencePresentation(label: "Ink", fragments: [.text(explorationInkStatus)])]
    case .compareIntendedAndObservedGeometry:
      [
        ExerciseEvidencePresentation(
          label: "Comparison", fragments: [.text(drawingTrialAssessment?.title ?? "not recorded")])
      ]
    }
  }

  private func drawingArtifactRevision(
    for step: ObservedDrawingTrialStep
  ) -> LearningArtifactRevision? {
    let kind: LearningArtifactKind =
      switch step {
      case .chooseIsolatedLinePlan: .linePlan(currentDrawingTrialGroup)
      case .captureLocalPreLineBaseline: .localPreLineBaseline(currentDrawingTrialGroup)
      case .moveToLineStart: .linePlan(currentDrawingTrialGroup)
      case .drawIsolatedLine: .lineExecution(currentDrawingTrialGroup)
      case .revealAndObserveNewInk: .postLineFrame(currentDrawingTrialGroup)
      case .compareIntendedAndObservedGeometry: .comparison(currentDrawingTrialGroup)
      }
    return learningArtifactGraph.currentRevision(for: kind)
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
    cameraOverlays = result.measurement.overlays
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
    passiveProbeInProgress = false
    jogRequestInProgress = false
    penRequestInProgress = false
    motionGuardActivationInProgress = false
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
      let acceptedArtifactCheckpointActions = activeAcceptedArtifactCheckpointActions,
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
      try acceptedArtifactCheckpointActions.save(checkpoint)
      parkedAcceptedMachineArtifactCheckpoint = checkpoint
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
      case .compatible(let residualMM):
        let histories = try checkpoint.restoredBoundaryHistories()
        let graph = try checkpoint.restoredLearningGraph()
        try checkpoint.validate()
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
        acceptedAttemptSequence = checkpoint.acceptedAttemptSequence
        acceptedArtifactCheckpointStatus = .restored(
          sideCount: checkpoint.boundarySideAggregates.count,
          centerArrival: checkpoint.centerArrivalPosition != nil,
          residualMM: residualMM
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
    cameraCalibrationProposalID = nil
    machineCameraRegistration = nil
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
    frozenToolContactSelectionFrame = nil
    pendingToolContactEvidence = nil
    toolContactPointSelectionRequest = nil
    selectedToolContactPoint = nil
    if let actions = activeAcceptedTipCalibrationCheckpointActions,
      case .quarantined(let checkpoint) = actions.load()
    {
      quarantinedTipCalibrationCheckpoint = checkpoint
    }
    clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    explorationError = nil
    cameraOverlays = []
    // Pen current state, accepted boundary controller MPos revisions, estimated
    // center, and accepted center arrival belong to the unchanged controller
    // session/coordinate authority and deliberately survive camera replacement.
  }

  private func clearPenLearningForRewind() {
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
      cameraCalibrationProposalID = nil
      machineCameraRegistration = nil
      explicitRegistrationCapAnchorEvidence = []
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.calibratePenContactFromSparseMarks.rawValue {
      tipCameraRegistration = nil
      proposedTipCameraRegistration = nil
      sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
      frozenToolContactSelectionFrame = nil
      pendingToolContactEvidence = nil
      toolContactPointSelectionRequest = nil
      selectedToolContactPoint = nil
    }
    cameraOverlays = []
  }

  private func freshSparseTipCalibrationCoordinatorForCurrentPaper()
    -> SparseTipCalibrationCoordinator
  {
    SparseTipCalibrationCoordinator(
      blacklistedLocations: blacklistedToolContactLocations.filter {
        $0.paperContactPlane.rawValue == explorationToolPaperRevision
      }
    )
  }

  private func clearDrawingLearningForRewind(from step: ObservedDrawingTrialStep) {
    if step == .chooseIsolatedLinePlan {
      currentExplorationEpisode = nil
      drawingTrialLineStart = nil
      currentDrawingTrialGroup = AttemptGroupIdentity(
        rawValue: frameMode == .simulated
          ? "simulated-\(UUID().uuidString.lowercased())"
          : UUID().uuidString.lowercased()
      )
    } else if var episode = currentExplorationEpisode {
      episode.termination = nil
      episode.humanAssessment = nil
      if step.rawValue <= ObservedDrawingTrialStep.captureLocalPreLineBaseline.rawValue {
        episode.frames.removeAll {
          $0.role == .localPreLineBaseline || $0.role == .postLine
        }
      } else if step.rawValue <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue {
        episode.frames.removeAll { $0.role == .postLine }
      }
      if step.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue {
        episode.executedAction = nil
        episode.controllerEvidence = nil
      }
      if step.rawValue <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue {
        episode.observedLineObservation = nil
        episode.visionEstimate = nil
        episode.residual = nil
        episode.reward = nil
      }
      currentExplorationEpisode = episode
    }

    if step.rawValue <= ObservedDrawingTrialStep.captureLocalPreLineBaseline.rawValue {
      localPreLineBaseline = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.moveToLineStart.rawValue {
      lastProtocolPoseSettlement = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue {
      drawingTrialStrokeEvidence = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue {
      explorationPostLineFrame = nil
      lastInkObservation = nil
      explorationInkStatus = "no isolated-line observation yet"
      cameraOverlays = []
    }
    drawingTrialAssessment = nil
    comparisonAttemptHistories = [:]
    explorationExportPath = nil
    lastTravelFeedSelection = nil
    observedDrawingTrialStep = step
  }

  private func clearDiscoveryAuthority() async {
    await cancelAndSettleDiscoveryMotionBeforeErasure()
    await cancelAndSettleAllBoundaryApproachVision()
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
    cameraCalibrationProposalID = nil
    machineCameraRegistration = nil
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
    frozenToolContactSelectionFrame = nil
    pendingToolContactEvidence = nil
    toolContactPointSelectionRequest = nil
    selectedToolContactPoint = nil
    explicitRegistrationCapAnchorEvidence = []
    pendingBoundaryFinalPositions = [:]
    pendingBoundaryOwnerIDs = [:]
    pendingBoundaryStopCapabilities = [:]
    observedDrawingTrialStep = .chooseIsolatedLinePlan
    drawingTrialAssessment = nil
    drawingTrialLineStart = nil
    drawingTrialStrokeEvidence = nil
    localPreLineBaseline = nil
    drawingTrialRevealPosition = nil
    drawingTrialTipRegistrationRevisionID = nil
    drawingTrialObservationRegion = nil
    lastProtocolPoseSettlement = nil
    explorationPostLineFrame = nil
    lastInkObservation = nil
    currentExplorationEpisode = nil
    learningArtifactGraph = LearningDependencyGraph()
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: penAttemptHistory.compatibility
    )
    boundaryAttemptHistories = [:]
    comparisonAttemptHistories = [:]
    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
    restartableExerciseItemID = nil
    currentDrawingTrialGroup = AttemptGroupIdentity(
      rawValue: UUID().uuidString.lowercased()
    )
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
    case .manualJog, .exerciseMotion, .drawingTrial, .sparseTipMark:
      break
    }

    if stopDispositionLatch == nil,
      latchContextualStopDisposition(
        for: target,
        intent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
    {
      await requestSingleJogCancel(for: target, intent: .shutdown)
    }
    await operation.owner.settle()
    clearStoppableOperation(matching: target)
    boundaryTeachingState = .idle
  }

  private func clearCameraAuthority() async {
    frameMode = .live
    cameraSnapshot = nil
    displayedFrame = nil
    latestLiveCameraFrame = nil
    cameraOverlays = []
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

  private func boundaryFeedVector(_ direction: BoundaryDirection) -> Vector2<MachineSpace> {
    switch direction {
    case .negativeX: try! Vector2(dx: -1, dy: 0)
    case .positiveX: try! Vector2(dx: 1, dy: 0)
    case .negativeY: try! Vector2(dx: 0, dy: -1)
    case .positiveY: try! Vector2(dx: 0, dy: 1)
    }
  }

  private func discoveryActionText(_ action: DiscoveryAction) -> String {
    switch action {
    case .askQuestion(let question): question.prompt
    case .awaitOperatorChoice(let question): "Choose \(question.choiceLabel) for this question."
    case .announce(let message): "Announce: \(message)"
    case .startBoundaryJog(let direction):
      "Start the logical \(direction.displayName) Boundary Discovery owner."
    case .awaitContextualStop: "Observe the boundary and use the contextual Stop."
    case .cancelBoundaryJogAndAwaitIdle: "Send one jog cancel and await the original motion owner."
    case .commitBoundaryObservation(let direction):
      "Commit \(direction.displayName) from typed direction + Stop + controller Idle/final MPos. Camera and Vision are not consulted."
    case .actuatePen(let command): "Command Pen \(command.commandedState.rawValue)."
    case .awaitPhysicalPenConfirmation(let state, _):
      "Confirm whether the pen is physically \(state.rawValue)."
    }
  }

  private func discoveryExpectationText(_ expectation: DiscoveryEventExpectation) -> String {
    switch expectation {
    case .questionPresented: "The contextual question is visible."
    case .operatorChoice: "One contextual YES or NO choice is recorded."
    case .announcementCompleted: "Speech output completes or reaches its advisory bound."
    case .boundaryJogStarted:
      "The logical boundary owner is active while direct controller admission remains runtime-owned."
    case .operatorStopRequested: "Stop is recorded before cancellation begins."
    case .boundaryJogCancelled: "The original motion owner reaches Idle with final MPos."
    case .boundaryObservationCommitted:
      "Controller settlement evidence and the current side aggregate commit together."
    case .penCommandSettled: "The typed pen command and dwell settle."
    case .physicalPenConfirmed: "The operator confirms the visible physical pen pose."
    }
  }

  private func drawingTrialParticipant(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan: "Operator"
    case .captureLocalPreLineBaseline, .revealAndObserveNewInk:
      "Camera and Vision"
    case .moveToLineStart, .drawIsolatedLine: "Plotter controller"
    case .compareIntendedAndObservedGeometry: "Operator"
    }
  }

  private func drawingTrialActionTitle(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan: "Choose Isolated Line Plan"
    case .captureLocalPreLineBaseline: "Capture Local Pre-Line Baseline"
    case .moveToLineStart: "Move to Line Start"
    case .drawIsolatedLine: "Draw Isolated Line"
    case .revealAndObserveNewInk: "Reveal and Observe New Ink"
    case .compareIntendedAndObservedGeometry: "Start"
    }
  }

  private func drawingTrialActionText(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan:
      "Choose a direction and project one local 5 mm path through the accepted tip model."
    case .captureLocalPreLineBaseline:
      "Capture one exact local baseline and record this Pen-Up reveal pose."
    case .moveToLineStart:
      "Move Pen Up to the recorded local line start."
    case .drawIsolatedLine:
      "Lower the pen, draw one 5 mm outward stroke, and raise."
    case .revealAndObserveNewInk:
      "Return Pen Up to the local reveal pose, settle, capture a newer frame, and extract new ink."
    case .compareIntendedAndObservedGeometry:
      "Record one typed comparison for this local trial; no redraw follows."
    }
  }

  private func drawingTrialExpectationText(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan:
      "One typed local line plan projected by an exact tip-model revision."
    case .captureLocalPreLineBaseline:
      "One exact pre-line frame and its Pen-Up reveal MPos."
    case .moveToLineStart: "Arrival at the local line start while Pen Up."
    case .drawIsolatedLine: "A closed controller stroke outcome; this is not yet ink proof."
    case .revealAndObserveNewInk:
      "Observed new line ink or a typed unclear/rejected observation, with no automatic redraw."
    case .compareIntendedAndObservedGeometry:
      "One typed operator assessment completes only this trial."
    }
  }

  private func drawingTrialActionUnavailableReason(
    for step: ObservedDrawingTrialStep
  ) -> String? {
    if activeExplorationOperation != nil { return "The current learning action is still in progress." }
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
    case .captureLocalPreLineBaseline, .revealAndObserveNewInk:
      if !cameraIsLive { return "A current LIVE camera frame is required." }
    case .chooseIsolatedLinePlan, .moveToLineStart, .drawIsolatedLine,
      .compareIntendedAndObservedGeometry:
      break
    }
    if step == .moveToLineStart || step == .drawIsolatedLine,
      machineSnapshot?.machine.position == nil
    {
      return "A current controller MPos is required."
    }
    return nil
  }

  private func advanceDrawingTrial(to step: ObservedDrawingTrialStep) {
    observedDrawingTrialStep = step
  }

  private func recordIsolatedLinePlan(_ direction: BoundaryDirection) throws {
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
    let plan = try ObservedDrawingTrialLinePlan(
      direction: direction,
      domain: registration.applicabilityRectangle,
      existingMarks: acceptedMarkGeometry + restoredMarkGeometry
    )
    drawingTrialLineStart = plan.startPosition
    drawingTrialTipRegistrationRevisionID = registration.acceptedRevisionID
    currentExplorationEpisode = ExplorationEpisode(
      sessionID: learningEvidenceSessionID,
      rung: .observedDrawingTrial,
      source: frameMode == .simulated ? .simulated : .live,
      split: .training,
      startedNanoseconds: nowNanoseconds()
    )
    currentExplorationEpisode?.lineStartPosition = drawingTrialLineStart
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
    appendFrameEvidence(.localPreLineBaseline, frame: frame.frame)
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
        action: "Move to Line Start"
      )
      guard
        recordProtocolPoseSettlement(
          action: "Move to Line Start",
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
      settlement.toolPaperRevision == explorationToolPaperRevision,
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
    ControllerPositionAcceptancePolicy.accepts(actual, target: target)
  }

  static func supervisedTravelDelta(
    from current: MachinePosition,
    to target: MachinePosition
  ) throws -> Vector2<MachineSpace>? {
    guard !ControllerPositionAcceptancePolicy.accepts(current, target: target) else {
      return nil
    }
    return try Vector2(
      dx: target.point.x - current.point.x,
      dy: target.point.y - current.point.y
    )
  }

  private func recordProtocolPoseSettlement(
    action: String,
    target: MachinePosition,
    actual: MachinePosition,
    toleranceMM: Double = ControllerPositionAcceptancePolicy.toleranceMM
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
      toolPaperRevision: explorationToolPaperRevision
    )
    return residual <= toleranceMM
  }

  /// One explicit, finite, Pen-Up exercise travel. This shares the runtime's
  /// capability-bound cancel route but accepts no artifact unless the original
  /// owner naturally completes at its reported final MPos.
  private func performSupervisedPenUpTravel(
    delta: Vector2<MachineSpace>,
    ownerID: LearningPathItemID,
    action: String
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
    action: String
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
      let target = ContextualStopTarget.exerciseMotion(
        capabilityID: ContextualStopCapabilityID(),
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
      throw operationError(for: outcome, action: action)
    }
    let target = ContextualStopTarget.exerciseMotion(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(operation.id),
      ownerID: ownerID,
      action: action
    )
    let owner = Task { await operation.outcome() }
    installStoppableOperation(target: target, owner: .motion(owner))
    defer { clearStoppableOperation(matching: target) }
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
        "\(action) was stopped or cancelled; no arrival artifact was accepted."
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
        action: "Confirm Isolated-Line Start",
        target: start,
        actual: current
      )
    else {
      throw LearningPathOperationError.requiredState(
        "Move to the recorded tip-model-domain line start before drawing."
      )
    }
    let delta: Vector2<MachineSpace> =
      switch selectedLineDirection {
      case .negativeX: try Vector2(dx: -5, dy: 0)
      case .positiveX: try Vector2(dx: 5, dy: 0)
      case .negativeY: try Vector2(dx: 0, dy: -5)
      case .positiveY: try Vector2(dx: 0, dy: 5)
      }
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
    let lower = await machineActions.requestPenActuation(.lower)
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
      recordStrokeEvidence(evidence, outcome: .completed, summary: "Idle with final MPos")
      _ = await announceAdvisory("Raising the pen after the isolated line.")
      let raise = await machineActions.requestPenActuation(.raise)
      machineSnapshot = await machineActions.snapshot()
      guard case .commandedAndSettled = raise else {
        throw operationError(for: raise, possibleInk: true)
      }
    case .cancelled(let evidence, let penRaiseOutcome):
      drawingTrialStrokeEvidence = evidence
      activeExplorationOperation?.strokeState = .possibleInk
      recordStrokeEvidence(evidence, outcome: .cancelled, summary: "Stop settled in place")
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
    guard let cameraActions,
      let baseline = localPreLineBaseline,
      let revealPosition = drawingTrialRevealPosition,
      let lineStart = drawingTrialLineStart,
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
        action: "Return to Local Reveal Pose"
      )
      guard
        recordProtocolPoseSettlement(
          action: "Return to Local Reveal Pose",
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
    appendFrameEvidence(.postLine, frame: post.frame)
    let lineDelta: Vector2<MachineSpace> =
      switch selectedLineDirection {
      case .negativeX: try Vector2(dx: -5, dy: 0)
      case .positiveX: try Vector2(dx: 5, dy: 0)
      case .negativeY: try Vector2(dx: 0, dy: -5)
      case .positiveY: try Vector2(dx: 0, dy: 5)
      }
    let lineEnd = try Point2<MachineSpace>(
      x: lineStart.point.x + lineDelta.dx,
      y: lineStart.point.y + lineDelta.dy
    )
    let cameraStart = try registration.tipPixel(at: lineStart.point)
    let cameraEnd = try registration.tipPixel(at: lineEnd)
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
    let outcome = await cameraActions.observeIsolatedInk(
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
        toolPaperRevision: explorationToolPaperRevision,
        controllerPositionToleranceMM: ControllerPositionAcceptancePolicy.toleranceMM,
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
      acceptInkObservation(observation)
    case .rejected(let rejection):
      lastInkObservation = nil
      explorationInkStatus = "ink or geometry unclear: \(rejection.reason); no redraw requested"
      cameraOverlays = []
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
    cameraOverlays = []
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
  case let .multipleSerialDevices(devices): "Select one of \(devices.count) serial devices."
  case let .transport(reason): "Controller transport: \(reason)"
  case let .timeout(query): "Controller timed out during \(query.rawValue)."
  case let .invalidReply(query, reason): "Invalid \(query.rawValue) reply: \(reason)"
  case let .responseLimitExceeded(query, maximumBytes, maximumChunks):
    "\(query.rawValue) exceeded \(maximumBytes) bytes or \(maximumChunks) chunks."
  case let .controllerAlarm(code): "Controller alarm: \(code)"
  case let .controllerError(code): "Controller error: \(code)"
  }
}
