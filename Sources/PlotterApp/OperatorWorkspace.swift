import Foundation
import Observation
import PlotterModel
import PlotterRuntime

enum ClearPoseAcceptancePolicy {
  static func admits(
    pendingLabel: ArmatureVisibilityLabel?,
    observation: ArmaturePoseObservation?
  ) -> Bool {
    pendingLabel == .clear && observation?.humanLabel == .clear
  }

  static func labelTitle(
    _ label: ArmatureVisibilityLabel,
    pendingLabel: ArmatureVisibilityLabel?,
    observation: ArmaturePoseObservation?
  ) -> String {
    guard pendingLabel == label, observation?.humanLabel == label,
      let estimate = observation?.overlapEstimate.visibility.rawValue.capitalized
    else { return label.rawValue.capitalized }
    return "\(label.rawValue.capitalized) (recorded; Vision: \(estimate))"
  }
}

enum FixedCameraOpticalSettlingPolicy {
  // The C920 mount can wobble by more than one integer pixel after carriage
  // travel. Keep the search finite and accept at most two pixels of global
  // translation; controller pose tolerance remains independently authoritative.
  static let alignmentSearchRadiusPixels = 3
  static let maximumAlignmentShiftPixels = 2
  static let maximumCentroidSpreadPixels: Double = 2
  static let maximumBackgroundMeanAbsoluteDifference: Double = 4
}

enum VisibilityTargetSearchCirclePolicy {
  /// Initial camera-pixel bound while the cap-to-tip translation is unknown.
  /// Half the shorter frame dimension preserves the same finite acquisition
  /// geometry at simulator and live-camera resolutions and covers the observed
  /// C920 cap-to-tip displacement without falling back to the full frame.
  static let acquisitionRadiusShortSideFraction: Double = 0.5
  static let algorithmRevision = "visibility-target-cap-tip-search-circle-v2"

  static func acquisitionRadius(frameWidth: Int, frameHeight: Int) -> Double {
    Double(min(frameWidth, frameHeight)) * acquisitionRadiusShortSideFraction
  }

  static func proposal(
    capAnchor: Point2<CameraPixelSpace>,
    anchorFrame: DisplayedFrame
  ) -> VisibilityTargetSearchCircle? {
    try? VisibilityTargetSearchCircle(
      center: capAnchor,
      radiusPixels: acquisitionRadius(
        frameWidth: anchorFrame.frame.width,
        frameHeight: anchorFrame.frame.height
      ),
      anchor: anchorFrame,
      algorithmRevision: algorithmRevision
    )
  }
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
  case visibilityTarget(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    ownerID: LearningPathItemID
  )
  case drawingTrial(
    capabilityID: ContextualStopCapabilityID, operationOwner: ContextualMotionOwnerID)

  var capabilityID: ContextualStopCapabilityID {
    switch self {
    case .pairedBoundary(let capabilityID, _, _, _, _),
      .manualJog(let capabilityID, _),
      .exerciseMotion(let capabilityID, _, _, _),
      .visibilityTarget(let capabilityID, _, _),
      .drawingTrial(let capabilityID, _):
      capabilityID
    }
  }

  var operationOwner: ContextualMotionOwnerID {
    switch self {
    case .pairedBoundary(_, _, let owner, _, _),
      .manualJog(_, let owner),
      .exerciseMotion(_, let owner, _, _),
      .drawingTrial(_, let owner):
      owner
    case .visibilityTarget(_, let operationOwner, _):
      operationOwner
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
  case controllerOutcome(String)
  case controllerContextChanged(ControllerCheckpointContextComparison)
  case inkRejected(String)
  case requiredState(String)

  var errorDescription: String? {
    switch self {
    case .freshFrameUnavailable:
      "A strictly newer exact camera frame was unavailable."
    case .controllerOutcome(let detail), .inkRejected(let detail), .requiredState(let detail):
      detail
    case .controllerContextChanged(let comparison):
      "Controller context changed during calibration: \(comparison.actionableDescription) The sample was discarded without motion retry."
    }
  }
}

private struct CurrentCameraCalibrationFailure: Hashable, Sendable {
  let code: String
  let detail: String
  let recovery: WorkflowTelemetryRecovery

  var recoveryDescription: String {
    switch recovery {
    case .none:
      "No recovery action is required."
    case .retryCalibration:
      "The controller is still at the registered target pose. Resolve the named fact, then retry Bounded Calibration and Build Proposal."
    case .returnToRegisteredTargetPose:
      "The controller is not at the registered target pose. Use Return to Captured Target Pose before retrying calibration."
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
}

struct LiveSceneInspection: Sendable {
  let displayedFrame: DisplayedFrame
  let measurement: PlotterSceneMeasurement
}

struct ProtocolPoseSettlement: Hashable, Sendable {
  let action: String
  let target: MachinePosition
  let actual: MachinePosition
  let residualMM: Double
  let toleranceMM: Double
  let controllerSessionID: UUID
  let coordinateRevision: UInt64
  let toolPaperRevision: UUID
  let targetAreaIdentity: UUID
}

enum VisibilityTargetExecutionDisposition: Hashable, Sendable {
  case completed
  case stopped
  case cancelled
  case shutdown
  case failed(String)
  case finalPositionMismatch
}

struct VisibilityTargetExecutionAttemptEvidence: Hashable, Sendable {
  let attemptID: ExerciseAttemptID
  let planRevision: String
  let disposition: VisibilityTargetExecutionDisposition
  let sceneDisposition: VisibilityTargetSceneDisposition
  let completedTraversalStepCount: Int
  let lastCompletedTraversalStep: VisibilityTargetTraversalStep?
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
    let targetAnchoredBaseline: DisplayedFrame?
    let postLineFrame: DisplayedFrame?
    let lineStart: MachinePosition?
    let strokeEvidence: DrawingStrokeEvidence?
    let inkObservation: IsolatedInkObservation?
    let inkStatus: String
    let assessment: DrawingTrialAssessment?
    let episode: ExplorationEpisode?
    let completedEpisodes: [ExplorationEpisode]
  }

  private struct VisibilityRegistrationPayloadSnapshot {
    let targetPoseRegistrationFrame: DisplayedFrame?
    let registeredTargetMachinePosition: MachinePosition?
    let targetCapAnchorEstimate: ToolCapAnchorEstimate?
    let targetSearchCircle: VisibilityTargetSearchCircle?
    let targetCapAnchorAndSearchCircleAccepted: Bool
    let preTargetClearViewBaseline: DisplayedFrame?
    let visibilityTargetSceneDisposition: VisibilityTargetSceneDisposition
    let visibilityTargetObservation: VisibilityTargetObservation?
    let penTipOffsetRegistration: PenTipOffsetRegistration?
    let executedVisibilityTargetPlanRevision: String?
    let visibilityTargetExecutionAttemptEvidence: VisibilityTargetExecutionAttemptEvidence?
    let visibilityRegistrationAccepted: Bool
    let machineCameraRegistration: MachineCameraRegistration?
    let clearViewPoseAccepted: Bool
    let registeredTargetReturnSettlement: ProtocolPoseSettlement?
    let acceptedClearReturnSettlement: ProtocolPoseSettlement?
    let pendingClearViewLabel: ArmatureVisibilityLabel?
    let armatureGuidanceState: ArmatureGuidanceState?
    let lastArmatureObservation: ArmaturePoseObservation?
    let targetAreaIdentity: UUID
    let targetAreaRelocationRequired: Bool
    let targetAreaRelocationCompleted: Bool
    let retiredTargetAreaDispositions: [UUID: VisibilityTargetSceneDisposition]
    let learningArtifactGraph: LearningDependencyGraph
    let observedDrawingTrialStep: ObservedDrawingTrialStep
  }

  private struct VisibilityObservationAuthorityContext: Sendable {
    let operationID: VisibilityObservationOperationID
    let generation: UInt64
    let attemptID: ExerciseAttemptID
    let baselineFrameID: FrameID
    let baselineSHA256: String
    let source: FrameSourceIdentity
    let cameraConfigurationID: CameraConfigurationID
    let controllerSessionID: UUID
    let coordinateRevision: UInt64
    let toolPaperRevision: UUID
    let targetAreaIdentity: UUID
    let clearPosition: MachinePosition
    let searchCircle: VisibilityTargetSearchCircle
    let targetPlanRevision: String
  }

  /// Live accepted learning authority is parked while the deterministic
  /// simulator runs. Simulated artifacts can drive the same presentation but
  /// are discarded when LIVE resumes and can never become physical evidence.
  private struct LearningAuthoritySnapshot {
    let boundaryTeachingState: BoundaryTeachingState
    let boundaryTeachingResultText: String
    let selectedDiscoverySequenceID: DiscoverySequenceID
    let discoveryTransactions: [DiscoverySequenceID: DiscoveryTransaction]
    let discoveryError: String?
    let pairedBoundaryProgress: PairedBoundaryProgress
    let boundaryAttemptEvidenceByAttemptID: [ExerciseAttemptID: BoundarySideAttemptEvidence]
    let boundarySideAggregates: [BoundaryDirection: BoundarySideAggregate]
    let estimatedMachineCenter: EstimatedMachineCenter?
    let learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame?
    let centerArrivalPosition: MachinePosition?
    let centerArrivalRetryRequired: Bool
    let targetPoseRegistrationFrame: DisplayedFrame?
    let registeredTargetMachinePosition: MachinePosition?
    let targetCapAnchorEstimate: ToolCapAnchorEstimate?
    let targetSearchCircle: VisibilityTargetSearchCircle?
    let targetCapAnchorAndSearchCircleAccepted: Bool
    let preTargetClearViewBaseline: DisplayedFrame?
    let visibilityTargetSceneDisposition: VisibilityTargetSceneDisposition
    let visibilityTargetObservation: VisibilityTargetObservation?
    let penTipOffsetRegistration: PenTipOffsetRegistration?
    let executedVisibilityTargetPlanRevision: String?
    let visibilityTargetExecutionAttemptEvidence: VisibilityTargetExecutionAttemptEvidence?
    let visibilityObservationAttemptHistories:
      [AttemptCompatibility: ExerciseAttemptHistory<VisibilityTargetObservation>]
    let acceptedVisibilityObservationAttemptID: ExerciseAttemptID?
    let visibilityRegistrationAccepted: Bool
    let machineCameraRegistration: MachineCameraRegistration?
    let targetAreaIdentity: UUID
    let targetAreaRelocationRequired: Bool
    let targetAreaRelocationCompleted: Bool
    let retiredTargetAreaDispositions: [UUID: VisibilityTargetSceneDisposition]
    let explorationError: String?
    let currentExplorationEpisode: ExplorationEpisode?
    let completedExplorationEpisodes: [ExplorationEpisode]
    let armatureGuidanceState: ArmatureGuidanceState?
    let lastArmatureObservation: ArmaturePoseObservation?
    let targetAnchoredTrialBaseline: DisplayedFrame?
    let drawingTrialObservationRegion: PixelRect?
    let lastProtocolPoseSettlement: ProtocolPoseSettlement?
    let explorationPostLineFrame: DisplayedFrame?
    let drawingTrialLineStart: MachinePosition?
    let drawingTrialStrokeEvidence: DrawingStrokeEvidence?
    let lastInkObservation: IsolatedInkObservation?
    let explorationInkStatus: String
    let explorationExportPath: String?
    let lastTravelFeedSelection: TravelFeedSelection?
    let drawingTrialAssessment: DrawingTrialAssessment?
    let clearViewPoseAccepted: Bool
    let registeredTargetReturnSettlement: ProtocolPoseSettlement?
    let acceptedClearReturnSettlement: ProtocolPoseSettlement?
    let learningArtifactGraph: LearningDependencyGraph
    let penAttemptHistory: ExerciseAttemptHistory<PenState>
    let boundaryAttemptHistories:
      [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<
        BoundarySideAttemptEvidence
      >]]
    let clearViewAttemptHistories:
      [AttemptCompatibility: ExerciseAttemptHistory<ArmatureVisibilityLabel>]
    let comparisonAttemptHistories:
      [AttemptCompatibility: ExerciseAttemptHistory<DrawingTrialAssessment>]
    let restartableExerciseItemID: LearningPathItemID?
    let observedDrawingTrialStep: ObservedDrawingTrialStep
    let pendingClearViewLabel: ArmatureVisibilityLabel?
    let selectedBoundaryDirection: BoundaryDirection
    let selectedClearViewDirection: BoundaryDirection
    let selectedLineDirection: BoundaryDirection
    let acceptedAttemptSequence: UInt64
    let currentDrawingTrialGroup: AttemptGroupIdentity
    let explorationCoordinateRevision: UInt64
    let explorationToolPaperRevision: UUID
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
    let beginVisibilityTarget:
      @Sendable (VisibilityTargetOperationRequest) async
        -> VisibilityTargetAdmission
    let requestVisibilityTargetIntent:
      @Sendable (VisibilityTargetOperationIntent, UUID) async
        -> VisibilityTargetIntentOutcome
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
    let captureSnapshot: @Sendable () async throws -> String
    let setAutomaticInspection:
      @Sendable (VisionAnalysisCadence?) async
        -> PlotterSceneAnalysisSnapshot
    let analysisUpdates: @Sendable () async -> AsyncStream<PlotterSceneAnalysisSnapshot>
    let observeIsolatedInk:
      @Sendable (IsolatedInkObservationRequest) async
        -> IsolatedInkObservationOutcome
    let observeVisibilityTarget:
      @Sendable (
        VisibilityTargetObservationRequest,
        @escaping @Sendable (VisibilityTargetObservationProgress) -> Void
      ) async
        -> VisibilityTargetObservationOutcome
  }

  var visibleLayers = Set(CanvasLayer.allCases)
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
  private(set) var jogCancelRequestInProgress = false
  private(set) var frameModeSwitchInProgress = false
  private(set) var motionGuardActivationInProgress = false
  private(set) var lastMotionGuardActivationText = "not activated"
  private(set) var lastContextualStopAuditRecord: ContextualStopAuditRecord?
  private(set) var boundaryActivityRecords: [BoundaryActivityRecord] = []

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
  private(set) var sceneInspectionInProgress = false
  private(set) var analysisFrameHeld = false
  private(set) var scopedVisionAnalysisActive = false
  private(set) var visionAnalysisSnapshot: PlotterSceneAnalysisSnapshot = .stopped
  private(set) var lastSceneMeasurement: PlotterSceneMeasurement?
  private(set) var lastCameraSnapshotPath: String?
  private(set) var simulatorEvidenceLabel = SimulatedOverlaySceneContent.evidenceLabel
  private(set) var simulatorPenState: PenState = .unknown
  private(set) var simulatorLearningSummary = "Switch to SIMULATED to inspect model behavior."
  private(set) var simulatedLearningSnapshot: SimulatedLearningSnapshot?
  private(set) var simulatedAnnotations: [SimulatedLearningAnnotation] = []
  private(set) var simulatedViewportID: SimulatedCameraViewportID?
  var simulatedAnnotationsAreVisible = true
  private(set) var boundaryTeachingState: BoundaryTeachingState = .idle
  private(set) var boundaryTeachingResultText = "Choose one side to begin."
  var selectedDiscoverySequenceID: DiscoverySequenceID = .penInteraction
  private(set) var discoveryTransactions: [DiscoverySequenceID: DiscoveryTransaction] = [:]
  private(set) var discoveryError: String?
  private(set) var pairedBoundaryProgress = PairedBoundaryProgress()
  private(set) var boundaryAttemptEvidenceByAttemptID:
    [ExerciseAttemptID: BoundarySideAttemptEvidence] = [:]
  private(set) var boundarySideAggregates: [BoundaryDirection: BoundarySideAggregate] = [:]
  private(set) var estimatedMachineCenter: EstimatedMachineCenter?
  private(set) var learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame?
  private(set) var centerArrivalPosition: MachinePosition?
  private(set) var centerArrivalRetryRequired = false
  private(set) var targetPoseRegistrationFrame: DisplayedFrame?
  private(set) var registeredTargetMachinePosition: MachinePosition?
  private(set) var targetCapAnchorEstimate: ToolCapAnchorEstimate?
  private(set) var proposedMachineCameraRegistration: MachineCameraRegistration?
  private(set) var proposedTargetSearchCircle: VisibilityTargetSearchCircle?
  private(set) var targetGeometryProposalID: UUID?
  private(set) var targetSearchCircle: VisibilityTargetSearchCircle?
  private(set) var targetCapAnchorAndSearchCircleAccepted = false
  private(set) var preTargetClearViewBaseline: DisplayedFrame?
  private(set) var blankTargetBaselineCandidate: DisplayedFrame?
  private(set) var visibilityTargetSceneDisposition: VisibilityTargetSceneDisposition = .pristine
  private(set) var visibilityTargetObservation: VisibilityTargetObservation?
  private(set) var penTipOffsetRegistration: PenTipOffsetRegistration?
  private(set) var executedVisibilityTargetPlanRevision: String?
  private(set) var visibilityTargetExecutionAttemptEvidence:
    VisibilityTargetExecutionAttemptEvidence?
  private(set) var visibilityObservationOperation: VisibilityObservationOperationPresentation?
  private(set) var visibilityObservationAttemptHistories:
    [AttemptCompatibility: ExerciseAttemptHistory<VisibilityTargetObservation>] = [:]
  private(set) var acceptedVisibilityObservationAttemptID: ExerciseAttemptID?
  private(set) var visibilityRegistrationAccepted = false
  private(set) var machineCameraRegistration: MachineCameraRegistration?
  private(set) var explicitRegistrationCapAnchorEvidence: [MachineCameraCorrespondenceProvenance] = []
  private(set) var currentCameraCalibrationPhase: String?
  private var currentCameraCalibrationFailure: CurrentCameraCalibrationFailure?
  private(set) var targetAreaIdentity = UUID()
  private(set) var targetAreaRelocationRequired = false
  private(set) var targetAreaRelocationCompleted = false
  private(set) var retiredTargetAreaDispositions: [UUID: VisibilityTargetSceneDisposition] = [:]
  private(set) var targetAnchoredTrialBaseline: DisplayedFrame?
  private(set) var drawingTrialObservationRegion: PixelRect?
  private(set) var lastProtocolPoseSettlement: ProtocolPoseSettlement?
  private(set) var explorationError: String?
  private(set) var currentExplorationEpisode: ExplorationEpisode?
  private(set) var completedExplorationEpisodes: [ExplorationEpisode] = []
  private(set) var armatureGuidanceState: ArmatureGuidanceState?
  private(set) var lastArmatureObservation: ArmaturePoseObservation?
  private(set) var explorationPostLineFrame: DisplayedFrame?
  private(set) var drawingTrialLineStart: MachinePosition?
  private(set) var drawingTrialStrokeEvidence: DrawingStrokeEvidence?
  private(set) var lastInkObservation: IsolatedInkObservation?
  private(set) var explorationInkStatus = "no isolated-line observation yet"
  private(set) var explorationExportPath: String?
  private(set) var explorationOperationInProgress = false
  private(set) var lastAnnouncementResultText = "No announcement has run."
  private(set) var lastTravelFeedSelection: TravelFeedSelection?
  private(set) var drawingTrialAssessment: DrawingTrialAssessment?
  private(set) var clearViewPoseAccepted = false
  private(set) var registeredTargetReturnSettlement: ProtocolPoseSettlement?
  private(set) var acceptedClearReturnSettlement: ProtocolPoseSettlement?
  private(set) var learningArtifactGraph = LearningDependencyGraph()
  private(set) var penAttemptHistory: ExerciseAttemptHistory<PenState>
  private(set) var boundaryAttemptHistories:
    [BoundaryDirection: [AttemptCompatibility: ExerciseAttemptHistory<BoundarySideAttemptEvidence>]] =
      [:]
  private(set) var clearViewAttemptHistories:
    [AttemptCompatibility: ExerciseAttemptHistory<ArmatureVisibilityLabel>] = [:]
  private(set) var comparisonAttemptHistories:
    [AttemptCompatibility: ExerciseAttemptHistory<DrawingTrialAssessment>] = [:]
  private(set) var activeExerciseAttemptID: ExerciseAttemptID?
  private(set) var activeExerciseAttemptOwnerID: LearningPathItemID?
  private(set) var restartableExerciseItemID: LearningPathItemID?
  private(set) var acceptedArtifactCheckpointStatus: AcceptedArtifactCheckpointStatus = .unavailable
  private(set) var learningAuthorityError: String?

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let announcementActions: AnnouncementActions?
  @ObservationIgnored private let acceptedArtifactCheckpointActions:
    AcceptedArtifactCheckpointActions?
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
  @ObservationIgnored private let learningEvidenceSessionID = LearningEvidenceSessionID()
  @ObservationIgnored private var controllerSessionID = UUID()
  @ObservationIgnored private var explorationCoordinateRevision: UInt64 = 0
  @ObservationIgnored private var explorationToolPaperRevision = UUID()
  @ObservationIgnored private var boundaryMotionTask: Task<Void, Never>?
  @ObservationIgnored private var boundaryApproachVisionTasks:
    [ExerciseAttemptID: Task<Void, Never>] = [:]
  @ObservationIgnored private var boundaryApproachAdvisories:
    [ExerciseAttemptID: BoundaryApproachAdvisory] = [:]
  @ObservationIgnored private var manualJogTask: Task<MotionOutcome, Never>?
  @ObservationIgnored private var exerciseMotionTask: Task<MotionOutcome, Never>?
  @ObservationIgnored private var currentCameraCalibrationTask: Task<Void, Never>?
  @ObservationIgnored private var simulatedVisibilityTargetFinalMPosOffsetForTesting:
    Vector2<MachineSpace>?
  @ObservationIgnored private var visibilityTargetTask:
    Task<VisibilityTargetOperationOutcome, Never>?
  @ObservationIgnored private var visibilityObservationTask: Task<Void, Never>?
  @ObservationIgnored private var visibilityObservationGeneration: UInt64 = 0
  @ObservationIgnored private var drawingTrialTask: Task<DrawingStrokeOutcome, Never>?
  @ObservationIgnored private var drawingTrialStrokeCompletedNaturally = false
  @ObservationIgnored private var simulatedOperationTask:
    Task<SimulatedLearningOperationOutcome?, Never>?
  @ObservationIgnored private var activeStopTarget: ContextualStopTarget?
  @ObservationIgnored private var stopDispositionLatch: ContextualStopDispositionLatch?
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
  @ObservationIgnored private var activeExerciseAttemptMode: ExerciseAttemptMode?
  @ObservationIgnored private var visibilityRepeatSnapshot: VisibilityRegistrationPayloadSnapshot?
  @ObservationIgnored private var visibilityDraftArtifactGraph: LearningDependencyGraph?
  @ObservationIgnored private var visibilityDraftClearViewAttemptHistories:
    [AttemptCompatibility: ExerciseAttemptHistory<ArmatureVisibilityLabel>]?
  @ObservationIgnored private var visibilityDraftAcceptedAttemptSequence: UInt64?
  @ObservationIgnored private var parkedLiveLearningAuthority: LearningAuthoritySnapshot?
  @ObservationIgnored private var acceptedAttemptSequence: UInt64 = 0
  @ObservationIgnored private var lastSimulatedProtocolCaptureNanoseconds: UInt64 = 0
  @ObservationIgnored private var currentDrawingTrialGroup = AttemptGroupIdentity(
    rawValue: UUID().uuidString.lowercased()
  )
  @ObservationIgnored private var parkedAcceptedMachineArtifactCheckpoint:
    AcceptedMachineArtifactCheckpoint?

  init(
    machineActions: MachineActions? = nil,
    cameraActions: CameraActions? = nil,
    announcementActions: AnnouncementActions? = nil,
    acceptedArtifactCheckpointActions: AcceptedArtifactCheckpointActions? = nil,
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
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: AttemptCompatibility(
        cameraConfigurationID: nil,
        coordinateSpace: .currentState,
        units: .state,
        group: AttemptGroupIdentity(rawValue: "pen-interaction"),
        algorithmRevision: "typed-operator-pen-observation-v1"
      )
    )
    self.simulatedExecutionPacing = simulatedExecutionPacing
    self.machineActions = machineActions
    self.cameraActions = cameraActions
    self.announcementActions = announcementActions
    self.acceptedArtifactCheckpointActions = acceptedArtifactCheckpointActions
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

  func replaceSimulatedVisibilityTargetFinalMPosOffsetForTesting(
    _ offset: Vector2<MachineSpace>?
  ) {
    simulatedVisibilityTargetFinalMPosOffsetForTesting = offset
  }

  var actionSurfacePresentation: ActionSurfacePresentation {
    let visibleKinds = Set(visibleLayers.map(\.overlayKind))
    let focus = displayedFrame.flatMap { frame -> ActionSurfaceFocus? in
      guard let searchCircle = proposedTargetSearchCircle ?? targetSearchCircle else {
        return nil
      }
      guard searchCircle.source == frame.source,
        searchCircle.anchorFrame.cameraConfigurationID
          == frame.frame.cameraConfigurationID
      else { return nil }
      let authorityToken =
        targetGeometryProposalID.map {
          "proposal-\($0.uuidString.lowercased())"
        } ?? learningArtifactGraph.currentRevision(for: .targetROIRegistration)?.id.rawValue
        .uuidString.lowercased() ?? "unaccepted"
      return ActionSurfaceFocus(
        frameID: frame.frame.id,
        cameraConfigurationID: frame.frame.cameraConfigurationID,
        searchCircle: searchCircle,
        region: searchCircle.boundingROI,
        label: "CAP ANCHOR FRAME \(searchCircle.anchorFrame.frameID.rawValue)",
        viewportContext: ActionSurfaceViewportContext(
          source: frame.source,
          cameraConfigurationID: frame.frame.cameraConfigurationID,
          targetAreaIdentity: targetAreaIdentity,
          searchAuthorityToken: authorityToken,
          region: searchCircle.boundingROI
        )
      )
    }
    return ActionSurfacePresentation(
      displayedFrame: displayedFrame,
      overlays: cameraOverlays.filter { visibleKinds.contains($0.provenance.kind) },
      simulatedAnnotations: simulatedAnnotations,
      simulatedViewportID: simulatedViewportID,
      simulatedAnnotationsAreVisible: simulatedAnnotationsAreVisible,
      focus: focus
    )
  }

  var cameraDevices: [CameraDevice] { cameraSnapshot?.devices ?? [] }
  var selectedCameraID: CameraDeviceID? { cameraSnapshot?.selectedDeviceID }
  var isShutdown: Bool { hasShutdown }

  var foregroundVisionOperationUnavailableReason: String? {
    visibilityObservationOperation.map {
      "Cancel Vision or wait for its exact circular target observation to settle. \($0.busyDetail)"
    }
  }

  var currentCameraCalibrationBusyReason: String? {
    currentCameraCalibrationPhase.map {
      "Automatic current-camera calibration is in progress (\($0)). Use Stop during an admitted move."
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
    case .running(let value): cadence = "target \(value.rawValue) Hz"
    }
    let duration =
      snapshot.latestResult.map {
        String(format: "%.1f ms", Double($0.analysisDurationNanoseconds) / 1_000_000)
      } ?? "no timing"
    return
      "\(cadence) · analyzed \(snapshot.analyzedFrameCount) · superseded \(snapshot.supersededFrameCount) · \(duration)"
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
      case .visibilityTarget: "simulated visibility-target drawing"
      }
    }
    guard let operation = machineSnapshot?.currentOperation else { return "none" }
    return switch operation {
    case .idle: "idle"
    case .passiveProbe: "controller inspection"
    case .relativeJog: "relative jog"
    case .boundaryMotion: "Boundary Discovery motion"
    case .drawingStroke: "isolated drawing stroke"
    case .visibilityTarget: "visibility-target drawing"
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
      || explorationOperationInProgress
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
    if let reason = currentCameraCalibrationBusyReason { return reason }
    if frameModeSwitchInProgress { return "A frame source switch is already in progress." }
    if activeExerciseAttemptOwnerID != nil {
      return "Finish or Cancel the active Learning Path attempt before changing frame source."
    }
    if activeDiscoverySequenceID != nil {
      return "Finish the active Human-Guided Discovery transaction first."
    }
    if explorationOperationInProgress {
      return "Wait for the current learning action before changing frame source."
    }
    if passiveProbeInProgress || jogRequestInProgress || penRequestInProgress
      || jogCancelRequestInProgress || machineSnapshot?.machine.operationInFlight == true
    {
      return "Wait for the current controller operation before changing frame source."
    }
    return nil
  }

  private(set) var observedDrawingTrialStep: ObservedDrawingTrialStep = .chooseIsolatedLinePlan
  private(set) var pendingClearViewLabel: ArmatureVisibilityLabel?
  private(set) var selectedBoundaryDirection: BoundaryDirection = .positiveX
  private(set) var selectedClearViewDirection: BoundaryDirection = .positiveX
  private(set) var selectedLineDirection: BoundaryDirection = .positiveX

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
    if !targetCapAnchorAndSearchCircleAccepted { return .registerTargetPoseAndCameraGeometry }
    if !clearViewPoseAccepted { return .discoverAndAcceptClearView }
    if preTargetClearViewBaseline == nil { return .confirmBlankTargetBaseline }
    if visibilityTargetSceneDisposition == .pristine {
      if !registeredTargetReturnIsCurrent { return .returnToRegisteredTargetPose }
      return .drawVisibilityTarget
    }
    if visibilityTargetObservation == nil
      || visibilityTargetSceneDisposition != .targetObserved
      || !acceptedClearReturnIsCurrent
    {
      return .returnAndObserveExistingTarget
    }
    return .acceptVisibilityRegistration
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
    if !visibilityRegistrationAccepted {
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
    if activeStopTarget != nil || explorationOperationInProgress
      || visibilityObservationOperation != nil
    {
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

    if plan.removesDurableCheckpoint {
      do {
        try acceptedArtifactCheckpointActions?.clear()
      } catch {
        learningAuthorityError =
          "The durable accepted-artifact checkpoint could not be cleared: \(error)"
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
      clearVisibilityLearningForRewind()
      clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      clearBoundaryLearningForRewind()
      clearVisibilityLearningForRewind()
      clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    case .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry):
      clearVisibilityLearningForRewind(from: .registerTargetPoseAndCameraGeometry)
      clearDrawingLearningForRewind(from: .chooseIsolatedLinePlan)
    case .humanGuidedDiscovery(let step):
      clearVisibilityLearningForRewind(from: step)
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
    visibilityRepeatSnapshot = nil
    visibilityDraftArtifactGraph = nil
    visibilityDraftClearViewAttemptHistories = nil
    visibilityDraftAcceptedAttemptSequence = nil
    explorationError = nil
    learningAuthorityError = nil

    if plan.removesDurableCheckpoint {
      parkedAcceptedMachineArtifactCheckpoint = nil
      acceptedArtifactCheckpointStatus = .cleared
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
    return LearningVacatePlan(
      scope: scope,
      source: source,
      anchor: anchor,
      affectedItems: Array(LearningPathItemID.learningExerciseOrder[anchorIndex...endIndex]),
      expectedCurrentRevisionIDs: revisionIDs,
      expectedAcceptedAttemptSequence: acceptedAttemptSequence,
      removesDurableCheckpoint:
        source == .live && anchorIndex <= boundaryIndex
        && acceptedArtifactCheckpointActions != nil,
      physicalInkMayRemain:
        visibilityTargetSceneDisposition != .pristine || drawingTrialStrokeEvidence != nil
        || lastInkObservation != nil
    )
  }

  private func learningPathItemID(for kind: LearningArtifactKind) -> LearningPathItemID? {
    switch kind {
    case .penInteraction:
      .humanGuidedDiscovery(.penInteraction)
    case .boundarySideAggregate, .estimatedMachineCenter, .centerArrival:
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    case .targetPoseRegistration, .machineCameraRegistration, .targetROIRegistration:
      .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)
    case .clearPose:
      .humanGuidedDiscovery(.discoverAndAcceptClearView)
    case .preTargetClearViewBaseline:
      .humanGuidedDiscovery(.confirmBlankTargetBaseline)
    case .visibilityTargetExecution:
      .humanGuidedDiscovery(.drawVisibilityTarget)
    case .visibilityTargetObservation:
      .humanGuidedDiscovery(.returnAndObserveExistingTarget)
    case .penTipOffsetRegistration, .visibilityRegistration:
      .humanGuidedDiscovery(.acceptVisibilityRegistration)
    case .linePlan:
      .observedDrawingTrial(.chooseIsolatedLinePlan)
    case .targetAnchoredTrialBaseline:
      .observedDrawingTrial(.captureTargetAnchoredBaseline)
    case .lineExecution:
      .observedDrawingTrial(.drawIsolatedLine)
    case .postLineFrame, .inkObservation, .residual:
      .observedDrawingTrial(.returnToClearPoseAndObserveNewInk)
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
    if includes(.humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)),
      targetPoseRegistrationFrame != nil || targetGeometryProposalID != nil
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.discoverAndAcceptClearView)),
      clearViewPoseAccepted || !clearViewAttemptHistories.isEmpty
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.confirmBlankTargetBaseline)),
      preTargetClearViewBaseline != nil || blankTargetBaselineCandidate != nil
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.returnToRegisteredTargetPose)),
      registeredTargetReturnSettlement != nil
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.drawVisibilityTarget)),
      visibilityTargetSceneDisposition != .pristine
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.returnAndObserveExistingTarget)),
      visibilityTargetObservation != nil || !visibilityObservationAttemptHistories.isEmpty
    {
      return true
    }
    if includes(.humanGuidedDiscovery(.acceptVisibilityRegistration)),
      visibilityRegistrationAccepted
    {
      return true
    }
    if includes(.observedDrawingTrial(.chooseIsolatedLinePlan)),
      currentExplorationEpisode != nil || drawingTrialLineStart != nil
        || targetAnchoredTrialBaseline != nil || drawingTrialStrokeEvidence != nil
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
      case .visibilityTarget:
        "Stop the compound visibility-target owner. Ink may already exist and the target will never be redrawn automatically."
      case .drawingTrial:
        "Stop the drawing trial; the controller owns its single Pen Up cancellation."
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
    guard visibilityObservationOperation == nil else { return }
    guard let target = activeStopTarget,
      target.capabilityID == capabilityID,
      case .manualJog = target
    else { return }
    await stopCurrentOperation(capabilityID: capabilityID)
  }

  var motionRequestStatusPresentation: MotionRequestStatusPresentation {
    if let operation = visibilityObservationOperation {
      return .busy(operation.busyDetail)
    }
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

  var cameraUtilityPresentation: CameraUtilityPresentation {
    let simulated = frameMode == .simulated
    let switchReason = frameModeSwitchUnavailableReason
    let foregroundReason = foregroundVisionOperationUnavailableReason
    let calibrationReason = currentCameraCalibrationBusyReason
    let liveOnly = "This action requires a LIVE camera source."
    let actions = CameraUtilityActionKind.allCases.map { kind in
      let title: String
      let systemImage: String
      let unavailableReason: String?
      switch kind {
      case .refresh:
        title = "Refresh Source"
        systemImage = "arrow.clockwise"
        unavailableReason = switchReason
      case .start:
        title = "Start Source"
        systemImage = "play.fill"
        unavailableReason = switchReason
      case .stop:
        title = "Stop Source"
        systemImage = "stop.fill"
        unavailableReason = switchReason
      case .restart:
        title = "Restart Source"
        systemImage = "arrow.counterclockwise"
        unavailableReason = switchReason
      case .analyzeOrResume:
        title = analysisFrameHeld ? "Resume Preview" : "Analyze Current Frame"
        systemImage = analysisFrameHeld ? "play.rectangle" : "viewfinder"
        unavailableReason =
          calibrationReason ?? foregroundReason
          ?? (simulated ? liveOnly : !displayedFrameAvailable ? "No current frame." : nil)
      case .saveSnapshot:
        title = "Save Snapshot"
        systemImage = "camera"
        unavailableReason =
          calibrationReason ?? foregroundReason
          ?? (simulated ? liveOnly : !displayedFrameAvailable ? "No current frame." : nil)
      }
      return CameraUtilityActionPresentation(
        kind: kind,
        title: title,
        systemImage: systemImage,
        unavailableReason: unavailableReason
      )
    }
    return CameraUtilityPresentation(mode: frameMode, actions: actions)
  }

  func performCameraUtilityAction(_ kind: CameraUtilityActionKind) async {
    guard cameraUtilityPresentation.actions.first(where: { $0.kind == kind })?.isEnabled == true
    else { return }
    if frameMode == .simulated {
      switch kind {
      case .refresh, .start, .restart:
        await refreshSimulatedContent()
      case .stop:
        displayedFrame = nil
        cameraOverlays = []
        simulatorLearningSummary =
          "Simulated source stopped. \(SimulatedLearningEvidenceNotice.evidenceLabel)"
      case .analyzeOrResume, .saveSnapshot:
        return
      }
      return
    }
    switch kind {
    case .refresh: await discoverCameras()
    case .start: await startCamera()
    case .stop: await stopCamera()
    case .restart: await restartCamera()
    case .analyzeOrResume:
      if analysisFrameHeld { await resumeLivePreview() } else { await inspectLatestScene() }
    case .saveSnapshot: await captureCameraSnapshot()
    }
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
    guard visibilityObservationOperation == nil, !hasShutdown, activeDiscoverySequenceID == nil,
      pairedBoundaryProgress.allowedDirections.contains(direction)
    else { return }
    selectedBoundaryDirection = direction
  }

  func performExerciseAction(
    _ kind: ExerciseActionKind,
    for ownerID: LearningPathItemID
  ) async {
    if let operation = visibilityObservationOperation {
      guard
        case .cancelVisibilityObservation(let capabilityID) = kind,
        capabilityID == operation.cancelCapabilityID
      else { return }
      await cancelVisibilityObservation(capabilityID: capabilityID)
      return
    }
    if case .selectDirection(let purpose, let direction) = kind {
      guard !hasShutdown,
        let selection = exerciseActionStrip(for: ownerID)?.directionSelection,
        selection.purpose == purpose,
        selection.options.contains(direction)
      else { return }
      switch purpose {
      case .boundary: selectBoundaryDirection(direction)
      case .clearViewSearch: selectedClearViewDirection = direction
      case .linePlan: selectedLineDirection = direction
      case .targetAreaRelocation: selectedClearViewDirection = direction
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
    case .cancelVisibilityObservation:
      return
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
    case .captureTargetPoseAndBuildGeometryProposal:
      await captureTargetPoseAndBuildGeometryProposal()
    case .acceptTargetGeometryProposal:
      acceptTargetGeometryProposal()
    case .rejectTargetGeometryProposal:
      rejectTargetGeometryProposal()
    case .moveForClearView(let move):
      await moveForClearView(move)
    case .moveToNewTargetArea(let move):
      await moveToNewTargetArea(move)
    case .recordClearViewLabel(let label):
      guard ownerID == .humanGuidedDiscovery(.discoverAndAcceptClearView) else {
        return
      }
      await recordClearViewLabel(label)
    case .acceptClearPose:
      guard ownerID == .humanGuidedDiscovery(.discoverAndAcceptClearView) else {
        return
      }
      await acceptClearPose()
    case .captureBlankTargetBaselineCandidate:
      await captureBlankTargetBaselineCandidate()
    case .confirmBlankTargetBaseline:
      confirmBlankTargetBaseline()
    case .rejectBlankTargetBaseline:
      rejectBlankTargetBaseline()
    case .returnToRegisteredTargetPose:
      await returnToRegisteredTargetPoseAction()
    case .drawVisibilityTarget:
      await drawVisibilityTargetAction()
    case .returnToAcceptedClearPose:
      await returnToAcceptedClearPoseAction()
    case .observeExistingVisibilityTarget:
      await observeExistingVisibilityTarget()
    case .acceptVisibilityRegistration:
      acceptVisibilityRegistration()
    case .rejectVisibilityRegistration:
      rejectVisibilityRegistration()
    case .registerNewTargetArea:
      registerNewTargetArea()
    case .paperReplaced:
      await recordPaperReplaced()
    case .chooseIsolatedLinePlan(let direction):
      selectedLineDirection = direction
      await performCurrentLearningPathAction()
    case .captureTargetAnchoredBaseline:
      await performCurrentLearningPathAction()
    case .moveToLineStart:
      await performCurrentLearningPathAction()
    case .drawIsolatedLine:
      await performCurrentLearningPathAction()
    case .returnToClearPoseAndObserveNewInk:
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
          throw LearningPathOperationError.controllerOutcome(
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
      var graph = visibilityDraftArtifactGraph ?? learningArtifactGraph
      let commit = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .centerArrival,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [centerRevision]
        )
      )
      learningArtifactGraph = graph
      visibilityDraftArtifactGraph = nil
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
      centerArrivalPosition = destination
      centerArrivalRetryRequired = false
      explorationError = nil
      persistAcceptedMachineArtifacts()
      finishActiveExerciseAttempt(disposition: .succeeded)
    } catch {
      explorationError = actionableDescription(error)
      if activeExerciseAttemptOwnerID == ownerID {
        finishActiveExerciseAttempt(disposition: attemptDisposition(for: explorationError ?? ""))
      }
      centerArrivalRetryRequired = true
      restartableExerciseItemID = nil
    }
  }

  private func captureProtocolFrame(newerThan boundary: UInt64) async throws -> DisplayedFrame {
    guard let cameraActions else { throw LearningPathOperationError.freshFrameUnavailable }
    if frameMode == .simulated {
      let scene = try await captureSimulatedProtocolScene()
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

  private func captureSimulatedProtocolScene() async throws -> SimulatedLearningSceneFrame {
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
        learnedCenter: learnedCenter,
        targetSearchCircle: targetSearchCircle
      )
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

  private func captureTargetPoseRegistration() async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    if activeExerciseAttemptID == nil {
      beginExerciseAttempt(ownerID: ownerID, mode: activeExerciseAttemptMode ?? .normal)
    }
    guard centerArrivalPosition != nil,
      !targetAreaRelocationRequired || targetAreaRelocationCompleted
    else {
      explorationError = "Move to a new target area first."
      return
    }
    do {
      let targetMachinePosition = try currentMachinePosition()
      let frame = try await captureProtocolFrame(
        newerThan: targetPoseRegistrationFrame?.frame.captureNanoseconds ?? 0
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
      targetPoseRegistrationFrame = registrationFrame
      registeredTargetMachinePosition = targetMachinePosition
      targetCapAnchorEstimate = try ToolCapAnchorEstimate(
        componentCentroid: centroid,
        componentBounds: bounds,
        confidence: confidence,
        estimatorRevision: "green-cap-bottom-center-anchor-v2",
        source: registrationFrame.source,
        frameID: registrationFrame.frame.id,
        cameraConfigurationID: registrationFrame.frame.cameraConfigurationID
      )
      proposedMachineCameraRegistration = nil
      proposedTargetSearchCircle = nil
      targetGeometryProposalID = nil
      targetCapAnchorAndSearchCircleAccepted = false
      explorationError = nil
    } catch {
      explorationError = "Target-pose registration failed: \(actionableDescription(error))"
    }
  }

  /// Runs Stage 3.3 as one operator action. Recovery after an interrupted
  /// calibration retains the exact registered target and resumes at proposal
  /// construction instead of demanding a duplicate capture.
  private func captureTargetPoseAndBuildGeometryProposal() async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    if activeExerciseAttemptOwnerID == nil {
      await startExercise(ownerID, mode: activeExerciseAttemptMode ?? .normal)
    }
    guard activeExerciseAttemptOwnerID == ownerID else { return }
    if targetPoseRegistrationFrame == nil {
      await captureTargetPoseRegistration()
    }
    guard targetPoseRegistrationFrame != nil,
      registeredTargetMachinePosition != nil
    else { return }
    await buildTargetGeometryProposal()
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
  private func stageTargetGeometryProposal(
    correspondenceOverride: [MachineCameraCorrespondenceProvenance]? = nil
  ) -> Bool {
    guard let frame = targetPoseRegistrationFrame,
      let capAnchor = targetCapAnchorEstimate,
      capAnchor.frameID == frame.frame.id
    else { return false }
    do {
      guard let targetMachinePosition = registeredTargetMachinePosition else {
        throw LearningPathOperationError.requiredState("Registered target MPos is unavailable.")
      }
      let exactSamples =
        correspondenceOverride ?? compatibleRegistrationCapAnchorEvidence(for: frame)
      guard exactSamples.count >= 3 else {
        explorationError =
          "Machine-camera registration needs automatic current-camera calibration: \(exactSamples.count) compatible exact cap-anchor samples are available; three non-collinear samples are required. Accepted machine-space Boundary aggregates and center remain current."
        return false
      }
      let correspondences = exactSamples.map {
        MachineCameraRegistrationCorrespondence(
          machine: $0.machinePoint,
          camera: $0.capAnchorPoint
        )
      }
      let fit = try MachineCameraRegistrationFit.fit(correspondences: correspondences)
      let provenance = exactSamples
      let registration = try MachineCameraRegistration(
        fit: fit,
        source: frame.source,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision,
        cameraConfigurationID: frame.frame.cameraConfigurationID,
        correspondenceProvenance: provenance,
        validationTargetFrameID: frame.frame.id,
        validationMachinePoint: targetMachinePosition.point,
        validationCapAnchorPoint: capAnchor.point,
        maximumValidationResidualPixels: 8,
        estimatorRevision: "boundary-affine-cap-anchor-with-target-validation-v2",
        uncertaintyPixels: max(fit.maximumErrorPixels, 0)
      )
      // The fit is validated against this cap landmark, but its residual must
      // not move the acquisition anchor. The exact target-pose cap measurement
      // owns the circle centre; the later ink observation learns cap -> tip.
      guard let searchCircle = VisibilityTargetSearchCirclePolicy.proposal(
        capAnchor: capAnchor.point,
        anchorFrame: frame
      ) else {
        throw LearningPathOperationError.requiredState(
          "Cap-anchored visibility-target search circle is unavailable."
        )
      }
      proposedMachineCameraRegistration = registration
      proposedTargetSearchCircle = searchCircle
      targetGeometryProposalID = UUID()
      targetCapAnchorAndSearchCircleAccepted = false
      explorationError = nil
      return true
    } catch {
      proposedMachineCameraRegistration = nil
      proposedTargetSearchCircle = nil
      targetGeometryProposalID = nil
      explorationError = "Machine-camera registration failed: \(actionableDescription(error))"
      return false
    }
  }

  /// Makes the reviewed proposal authoritative in one graph transaction. No
  /// target pose, fit, or search-circle revision becomes current before this decision.
  private func acceptTargetGeometryProposal() {
    let sourceGraph = visibilityDraftArtifactGraph ?? learningArtifactGraph
    guard let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry),
      let centerArrival = sourceGraph.currentRevision(for: .centerArrival)?.id,
      let registration = proposedMachineCameraRegistration,
      let searchCircle = proposedTargetSearchCircle
    else { return }
    do {
      var graph = sourceGraph
      let targetPose = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .targetPoseRegistration,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [centerArrival]
        )
      )
      let machineRegistrationCandidate = LearningArtifactRevision(
        kind: .machineCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: Set(
          registration.correspondenceProvenance.map(\.artifactRevisionID)
            + [targetPose.currentRevision.id]
        )
      )
      let priorMachineRegistrationID = visibilityRepeatSnapshot?.learningArtifactGraph
        .currentRevision(for: .machineCameraRegistration)?.id
      let machineRegistration =
        if activeExerciseAttemptMode == .replacement,
          let priorMachineRegistrationID,
          graph.revision(id: priorMachineRegistrationID)?.state == .invalidated
        {
          try graph.commitReplacement(
            machineRegistrationCandidate,
            supersedingInvalidatedRevision: priorMachineRegistrationID
          )
        } else {
          try graph.commitReplacement(machineRegistrationCandidate)
        }
      let targetROICandidate = LearningArtifactRevision(
        kind: .targetROIRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [
          targetPose.currentRevision.id,
          machineRegistration.currentRevision.id,
        ]
      )
      let priorTargetROIID = visibilityRepeatSnapshot?.learningArtifactGraph
        .currentRevision(for: .targetROIRegistration)?.id
      let targetROI =
        if activeExerciseAttemptMode == .replacement,
          let priorTargetROIID,
          graph.revision(id: priorTargetROIID)?.state == .invalidated
        {
          try graph.commitReplacement(
            targetROICandidate,
            supersedingInvalidatedRevision: priorTargetROIID
          )
        } else {
          try graph.commitReplacement(targetROICandidate)
        }
      learningArtifactGraph = graph
      visibilityDraftArtifactGraph = nil
      applyArtifactInvalidations(
        targetPose.invalidatedRevisionIDs
          .union(machineRegistration.invalidatedRevisionIDs)
          .union(targetROI.invalidatedRevisionIDs)
      )
      machineCameraRegistration = registration
      targetSearchCircle = searchCircle
      proposedMachineCameraRegistration = nil
      proposedTargetSearchCircle = nil
      targetGeometryProposalID = nil
      targetCapAnchorAndSearchCircleAccepted = true
      visibilityRegistrationAccepted = false
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
    } catch {
      explorationError =
        "Target-geometry acceptance failed atomically: \(actionableDescription(error))"
    }
  }

  private func buildTargetGeometryProposal() async {
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
      let frame = targetPoseRegistrationFrame,
      let targetPosition = registeredTargetMachinePosition
    else { return }

    if compatibleRegistrationCapAnchorEvidence(for: frame).count >= 3,
      stageTargetGeometryProposal()
    {
      return
    }

    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
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
        detail: "Stage 3.3 bounded three-sample calibration accepted by the workflow coordinator."
      )
    )
    await updateCurrentCameraCalibrationPhase(
      "Preparing bounded calibration",
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
          "Return to the registered target pose before calibrating the current camera."
        )
      }
      let plan = try CurrentCameraCalibrationPlan(
        targetPosition: targetPosition,
        boundarySideAggregates: boundarySideAggregates,
        controllerSessionID: controllerSessionID,
        coordinateRevision: explorationCoordinateRevision
      )

      await updateCurrentCameraCalibrationPhase(
        "Capturing exact sample 1 of 3 at the target pose",
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
          "Moving Pen Up to exact sample \(sampleIndex + 1) of 3",
          operationID: operationID,
          attemptID: attemptID
        )
        let final = try await performSupervisedPenUpTravel(
          delta: plan.motionDeltas[sampleIndex - 1],
          ownerID: ownerID,
          action: "Current-Camera Calibration Sample \(sampleIndex + 1) of 3"
        )
        try requireCalibrationContinuation()
        guard
          recordProtocolPoseSettlement(
            action: "Current-Camera Calibration Sample \(sampleIndex + 1) of 3",
            target: expected,
            actual: final
          )
        else {
          throw LearningPathOperationError.controllerOutcome(
            "Calibration travel did not settle at exact sample \(sampleIndex + 1) of 3."
          )
        }
        await updateCurrentCameraCalibrationPhase(
          "Capturing exact sample \(sampleIndex + 1) of 3",
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
        "Returning Pen Up to the registered target pose",
        operationID: operationID,
        attemptID: attemptID
      )
      let returned = try await performSupervisedPenUpTravel(
        delta: plan.motionDeltas[2],
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
        throw LearningPathOperationError.controllerOutcome(
          "Calibration return did not settle at the registered target pose."
        )
      }
      try requireCalibrationContinuation()
      await updateCurrentCameraCalibrationPhase(
        "Fitting a reviewable registration and search-circle proposal",
        operationID: operationID,
        attemptID: attemptID
      )
      guard stageTargetGeometryProposal(correspondenceOverride: stagedSamples) else {
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
          detail: "Three exact samples were staged and a reviewable geometry proposal was built."
        )
      )
    } catch  where hasShutdown || Task.isCancelled {
      return
    } catch {
      proposedMachineCameraRegistration = nil
      proposedTargetSearchCircle = nil
      targetGeometryProposalID = nil
      targetCapAnchorAndSearchCircleAccepted = false
      let failure = currentCameraCalibrationFailure(for: error, targetPosition: targetPosition)
      currentCameraCalibrationFailure = failure
      explorationError =
        "Current-camera calibration failed [\(failure.code)]: \(failure.detail)"
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
    operationID: UUID
  ) async throws -> CalibrationCapAnchorCapture
  {
    try requireCalibrationContinuation()
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState(
        "No active target-registration attempt owns this calibration sample."
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
    let boundary = displayedFrame?.frame.captureNanoseconds ?? 0
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
      throw LearningPathOperationError.controllerOutcome(
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
      contextBaseline: afterCapture.contextBaseline
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
        throw LearningPathOperationError.controllerOutcome(
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
          failureCode: comparison.isCompatible ? nil : "controller_context_changed",
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
          detail: "The first fresh passive probe established this calibration operation's controller-context baseline.",
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
      throw LearningPathOperationError.controllerOutcome(
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

  private func rejectTargetGeometryProposal() {
    currentCameraCalibrationFailure = nil
    targetPoseRegistrationFrame = nil
    registeredTargetMachinePosition = nil
    targetCapAnchorEstimate = nil
    proposedMachineCameraRegistration = nil
    proposedTargetSearchCircle = nil
    targetGeometryProposalID = nil
    targetCapAnchorAndSearchCircleAccepted = false
    targetSearchCircle = nil
    machineCameraRegistration = nil
    explorationError =
      "Operator rejected the staged target geometry. No target-pose, camera-fit, or search-circle revision became authoritative; capture a new exact target frame."
  }

  private func moveForClearView(_ move: ClearViewSearchMove) async {
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .discoverAndAcceptClearView
    )
    guard targetCapAnchorAndSearchCircleAccepted else { return }
    if activeExerciseAttemptID == nil {
      beginExerciseAttempt(ownerID: ownerID, mode: activeExerciseAttemptMode ?? .normal)
    }
    do {
      _ = try await performSupervisedPenUpTravel(
        delta: move.delta,
        ownerID: ownerID,
        action: "Clear-View Search \(move.direction.displayName) \(move.distance.displayName)"
      )
      pendingClearViewLabel = nil
      _ = try await captureProtocolFrame(newerThan: displayedFrame?.frame.captureNanoseconds ?? 0)
      explorationError = nil
    } catch {
      explorationError = "Clear-view search move failed: \(actionableDescription(error))"
      if activeExerciseAttemptOwnerID == ownerID {
        finishActiveExerciseAttempt(disposition: attemptDisposition(for: explorationError ?? ""))
      }
      restartableExerciseItemID = ownerID
    }
  }

  private func moveToNewTargetArea(_ move: ClearViewSearchMove) async {
    guard targetAreaRelocationRequired else { return }
    let ownerID = LearningPathItemID.humanGuidedDiscovery(
      .registerTargetPoseAndCameraGeometry
    )
    if activeExerciseAttemptID == nil {
      beginExerciseAttempt(ownerID: ownerID, mode: activeExerciseAttemptMode ?? .normal)
    }
    do {
      _ = try await performSupervisedPenUpTravel(
        delta: move.delta,
        ownerID: ownerID,
        action: "Move New Target Area \(move.direction.displayName) \(move.distance.displayName)"
      )
      targetAreaRelocationCompleted = true
      explorationError = nil
    } catch {
      explorationError = "New target-area relocation failed: \(actionableDescription(error))"
      restartableExerciseItemID = ownerID
    }
  }

  func answerCurrentQuestion(_ choice: OperatorChoice) async {
    guard visibilityObservationOperation == nil else { return }
    guard let sequenceID = activeDiscoverySequenceID else { return }
    await answerDiscoverySequence(choice, for: sequenceID)
  }

  func recordClearViewLabel(_ label: ArmatureVisibilityLabel) async {
    guard visibilityObservationOperation == nil else { return }
    guard humanGuidedDiscoveryCurrentStep == .discoverAndAcceptClearView else {
      return
    }
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .humanGuidedDiscovery(.discoverAndAcceptClearView),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    explorationError = nil
    do {
      let frame: DisplayedFrame
      let position: MachinePosition
      let armatureBounds: AxisAlignedBounds<CameraPixelSpace>?
      if frameMode == .simulated {
        guard let displayedFrame else { throw LearningPathOperationError.freshFrameUnavailable }
        frame = displayedFrame
        if let simulated = simulatedLearningSnapshot?.mpos {
          position = try MachinePosition(x: simulated.xMM, y: simulated.yMM)
        } else {
          position = try MachinePosition(x: 0, y: 0)
        }
        armatureBounds =
          cameraOverlays.compactMap { overlay in
            guard overlay.provenance.kind == .armatureEstimate,
              case .bounds(let bounds) = overlay.geometry
            else { return nil }
            return bounds
          }.first
      } else {
        guard let cameraActions, let currentPosition = machineSnapshot?.machine.position else {
          throw LearningPathOperationError.freshFrameUnavailable
        }
        guard
          let inspection = try await cameraActions.inspectScene(
            displayedFrame?.frame.captureNanoseconds ?? 0
          )
        else { throw LearningPathOperationError.freshFrameUnavailable }
        frame = inspection.displayedFrame
        position = currentPosition
        armatureBounds = inspection.measurement.armature?.bounds
        displayedFrame = inspection.displayedFrame
        cameraOverlays = inspection.measurement.overlays
      }
      let context = armatureContext(
        frame: frame.frame,
        region: targetSearchCircle?.boundingROI ?? defaultInkRegion(for: frame.frame)
      )
      var guidance = armatureGuidanceState ?? ArmatureGuidanceState(context: context)
      guidance.updateContext(context)
      let observation = try guidance.record(
        frame: frame.frame,
        controllerPosition: position,
        armatureBounds: armatureBounds,
        humanLabel: label,
        outcome: .stopped
      )
      armatureGuidanceState = guidance
      lastArmatureObservation = observation
      pendingClearViewLabel = label
    } catch {
      explorationError = "Clear-View observation failed: \(error)"
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
    }
  }

  func acceptClearPose() async {
    guard visibilityObservationOperation == nil,
      let observation = lastArmatureObservation,
      ClearPoseAcceptancePolicy.admits(
        pendingLabel: pendingClearViewLabel,
        observation: observation
      ),
      var guidance = armatureGuidanceState
    else { return }
    do {
      try guidance.acceptClearPose(
        observationID: observation.id,
        returnFeedMMPerMinute: positiveFallbackTravelFeed()
      )
      try commitClearViewAttemptAndArtifact(guidance: guidance)
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
    } catch {
      explorationError = "Clear-View acceptance failed: \(error)"
      recordClearViewAttempt(
        label: nil,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      restartableExerciseItemID = .humanGuidedDiscovery(.discoverAndAcceptClearView)
    }
  }

  private func captureBlankTargetBaselineCandidate() async {
    guard visibilityTargetSceneDisposition == .pristine,
      clearViewPoseAccepted,
      let clearPosition = armatureGuidanceState?.acceptedClearPose?.position,
      (try? currentMachinePosition()).map({ protocolPositionsMatch($0, clearPosition) }) == true
    else { return }
    do {
      let frame = try await captureProtocolFrame(
        newerThan: displayedFrame?.frame.captureNanoseconds ?? 0
      )
      blankTargetBaselineCandidate = frame
      explorationError = nil
    } catch {
      explorationError = "Pre-target baseline failed: \(actionableDescription(error))"
    }
  }

  private func confirmBlankTargetBaseline() {
    guard visibilityTargetSceneDisposition == .pristine,
      let candidate = blankTargetBaselineCandidate,
      let attemptID = activeExerciseAttemptID,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.confirmBlankTargetBaseline),
      let clearPose = learningArtifactGraph.currentRevision(for: .clearPose)?.id,
      let targetROI = learningArtifactGraph.currentRevision(for: .targetROIRegistration)?.id
    else { return }
    do {
      var graph = learningArtifactGraph
      let commit = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .preTargetClearViewBaseline,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [clearPose, targetROI]
        )
      )
      learningArtifactGraph = graph
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
      preTargetClearViewBaseline = candidate
      blankTargetBaselineCandidate = nil
      registeredTargetReturnSettlement = nil
      finishActiveExerciseAttempt(disposition: .succeeded)
      explorationError = nil
    } catch {
      explorationError = "Blank-baseline acceptance failed: \(actionableDescription(error))"
    }
  }

  private func rejectBlankTargetBaseline() {
    blankTargetBaselineCandidate = nil
    visibilityTargetSceneDisposition = .targetUnusable
    explorationError =
      "The exact frame was marked Not Blank. No baseline revision was accepted; register a new target area or paper revision."
  }

  private func returnToRegisteredTargetPoseAction() async {
    guard let destination = registeredTargetMachinePosition else { return }
    await performNamedTravel(
      to: destination,
      action: "Return to Registered Target Pose"
    )
  }

  private func returnToAcceptedClearPoseAction() async {
    guard let destination = armatureGuidanceState?.acceptedClearPose?.position else { return }
    await performNamedTravel(
      to: destination,
      action: "Return to Accepted Clear Pose"
    )
  }

  private func performNamedTravel(to destination: MachinePosition, action: String) async {
    let ownerID =
      activeExerciseAttemptOwnerID
      ?? .humanGuidedDiscovery(.returnToRegisteredTargetPose)
    do {
      let current = try currentMachinePosition()
      let delta = try Vector2<MachineSpace>(
        dx: destination.point.x - current.point.x,
        dy: destination.point.y - current.point.y
      )
      let final: MachinePosition
      if delta.dx != 0 || delta.dy != 0 {
        final = try await performSupervisedPenUpTravel(
          delta: delta,
          ownerID: ownerID,
          action: action
        )
      } else {
        final = current
      }
      guard
        recordProtocolPoseSettlement(
          action: action,
          target: destination,
          actual: final
        )
      else {
        throw LearningPathOperationError.controllerOutcome(
          "\(action) settled at an incompatible final MPos."
        )
      }
      if ownerID == .humanGuidedDiscovery(.returnToRegisteredTargetPose) {
        registeredTargetReturnSettlement = lastProtocolPoseSettlement
        finishActiveExerciseAttempt(disposition: .succeeded)
      } else if ownerID == .humanGuidedDiscovery(.returnAndObserveExistingTarget) {
        acceptedClearReturnSettlement = lastProtocolPoseSettlement
        if visibilityTargetObservation != nil,
          visibilityTargetSceneDisposition == .targetObserved
        {
          finishActiveExerciseAttempt(disposition: .succeeded)
        }
      }
      explorationError = nil
    } catch {
      explorationError = "\(action) failed: \(actionableDescription(error))"
      restartableExerciseItemID = ownerID
    }
  }

  private func drawVisibilityTargetAction() async {
    guard preTargetClearViewBaseline != nil,
      let targetCenter = registeredTargetMachinePosition,
      (try? currentMachinePosition()).map({ protocolPositionsMatch($0, targetCenter) }) == true,
      visibilityTargetSceneDisposition == .pristine
    else { return }
    let ownerID = LearningPathItemID.humanGuidedDiscovery(.drawVisibilityTarget)
    let plan = VisibilityTargetPlanV2()
    if frameMode == .simulated {
      let operation: SimulatedLearningOperation
      do {
        operation = try await simulatedLearningRuntime.beginVisibilityTarget(plan: plan).result
          .get()
      } catch {
        explorationError = "Simulated visibility-target admission was refused: \(error)."
        return
      }
      executedVisibilityTargetPlanRevision = plan.algorithmRevision
      let target = ContextualStopTarget.visibilityTarget(
        capabilityID: ContextualStopCapabilityID(),
        operationOwner: .simulated(operation.id),
        ownerID: ownerID
      )
      let task = Task { @MainActor [simulatedLearningRuntime, simulatedExecutionPacing] in
        let outcome = try? await simulatedLearningRuntime.executeNaturally(
          operation.id,
          pacing: simulatedExecutionPacing
        ).result.get()
        if let outcome {
          self.applySimulatedVisibilityTargetOutcome(
            outcome,
            registeredCenter: targetCenter,
            plan: plan
          )
        }
        return outcome
      }
      simulatedOperationTask = task
      activeStopTarget = target
      stopDispositionLatch = nil
      let outcome = await task.value
      simulatedOperationTask = nil
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
      if activeStopTarget == target { activeStopTarget = nil }
      guard outcome != nil else {
        explorationError = "The simulated visibility-target owner lost its typed outcome."
        return
      }
      return
    }

    guard let machineActions else { return }
    let request = VisibilityTargetOperationRequest(
      plan: plan,
      approachFeedMMPerMinute: positiveFallbackTravelFeed(),
      drawingFeedMMPerMinute: positiveFallbackTravelFeed()
    )
    let operation: VisibilityTargetOperation
    switch await machineActions.beginVisibilityTarget(request) {
    case .admitted(let admitted):
      operation = admitted
      executedVisibilityTargetPlanRevision = plan.algorithmRevision
    case .rejected(let outcome):
      applyVisibilityTargetOutcome(outcome, registeredCenter: targetCenter, plan: plan)
      return
    }
    let target = ContextualStopTarget.visibilityTarget(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(operation.id),
      ownerID: ownerID
    )
    let task = Task { @MainActor in
      let outcome = await operation.outcome()
      self.applyVisibilityTargetOutcome(
        outcome,
        registeredCenter: targetCenter,
        plan: plan
      )
      return outcome
    }
    visibilityTargetTask = task
    activeStopTarget = target
    stopDispositionLatch = nil
    _ = await task.value
    visibilityTargetTask = nil
    if activeStopTarget == target { activeStopTarget = nil }
    machineSnapshot = await machineActions.snapshot()
  }

  private func applySimulatedVisibilityTargetOutcome(
    _ outcome: SimulatedLearningOperationOutcome,
    registeredCenter: MachinePosition,
    plan: VisibilityTargetPlanV2
  ) {
    let scene = outcome.visibilityTargetSceneDisposition ?? .pristine
    visibilityTargetSceneDisposition = scene
    switch outcome.disposition {
    case .naturallyCompleted:
      let reportedFinalMPos: SimulatedLearningMPos
      if let offset = simulatedVisibilityTargetFinalMPosOffsetForTesting,
        let shifted = try? SimulatedLearningMPos(
          xMM: outcome.finalMPos.xMM + offset.dx,
          yMM: outcome.finalMPos.yMM + offset.dy
        )
      {
        reportedFinalMPos = shifted
      } else {
        reportedFinalMPos = outcome.finalMPos
      }
      guard
        let final = try? MachinePosition(
          x: reportedFinalMPos.xMM,
          y: reportedFinalMPos.yMM
        ),
        let expected = try? MachinePosition(
          x: registeredCenter.point.x + plan.approachDelta.dx,
          y: registeredCenter.point.y + plan.approachDelta.dy
        ),
        recordProtocolPoseSettlement(
          action: "Draw Visibility Target",
          target: expected,
          actual: final
        )
      else {
        if visibilityTargetSceneDisposition == .pristine {
          visibilityTargetSceneDisposition = .inkPossible
        }
        let mismatch =
          "Visibility target final MPos did not match the registered target plan. Existing ink may be present; no redraw is available."
        commitVisibilityTargetExecutionArtifact(
          planRevision: outcome.visibilityTargetProgress?.planRevision ?? plan.algorithmRevision,
          executionDisposition: .finalPositionMismatch,
          progress: outcome.visibilityTargetProgress,
          attemptDisposition: .failed(mismatch),
          retainedError: mismatch
        )
        return
      }
      commitVisibilityTargetExecutionArtifact(
        planRevision: outcome.visibilityTargetProgress?.planRevision ?? plan.algorithmRevision,
        executionDisposition: .completed,
        progress: outcome.visibilityTargetProgress
      )
    case .stopped:
      let message =
        "Visibility target settled as \(scene.rawValue). Observe Existing Target if ink is possible; never redraw in this target area."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: outcome.visibilityTargetProgress?.planRevision ?? plan.algorithmRevision,
          executionDisposition: .stopped,
          progress: outcome.visibilityTargetProgress,
          attemptDisposition: .cancelled,
          retainedError: message
        )
      } else {
        explorationError = message
      }
    case .cancelled:
      let message =
        "Visibility target settled as \(scene.rawValue). Observe Existing Target if ink is possible; never redraw in this target area."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: outcome.visibilityTargetProgress?.planRevision ?? plan.algorithmRevision,
          executionDisposition: .cancelled,
          progress: outcome.visibilityTargetProgress,
          attemptDisposition: .cancelled,
          retainedError: message
        )
      } else {
        explorationError = message
      }
    case .shutdown:
      let message =
        "Visibility target settled as \(scene.rawValue). Observe Existing Target if ink is possible; never redraw in this target area."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: outcome.visibilityTargetProgress?.planRevision ?? plan.algorithmRevision,
          executionDisposition: .shutdown,
          progress: outcome.visibilityTargetProgress,
          attemptDisposition: .cancelled,
          retainedError: message
        )
      } else {
        explorationError = message
      }
    case .failed:
      let message =
        "Visibility target failed at \(String(describing: outcome.visibilityTargetFailurePhase)); scene is \(scene.rawValue). Observe existing ink or choose an explicit recovery."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: outcome.visibilityTargetProgress?.planRevision ?? plan.algorithmRevision,
          executionDisposition: .failed(String(describing: outcome.visibilityTargetFailurePhase)),
          progress: outcome.visibilityTargetProgress,
          attemptDisposition: .failed(message),
          retainedError: message
        )
      } else {
        explorationError = message
      }
    }
  }

  private func applyVisibilityTargetOutcome(
    _ outcome: VisibilityTargetOperationOutcome,
    registeredCenter: MachinePosition,
    plan: VisibilityTargetPlanV2
  ) {
    switch outcome {
    case .completed(let final, let scene, let progress):
      visibilityTargetSceneDisposition = scene
      guard
        let expected = try? MachinePosition(
          x: registeredCenter.point.x + plan.approachDelta.dx,
          y: registeredCenter.point.y + plan.approachDelta.dy
        ),
        recordProtocolPoseSettlement(
          action: "Draw Visibility Target",
          target: expected,
          actual: final
        )
      else {
        if visibilityTargetSceneDisposition == .pristine {
          visibilityTargetSceneDisposition = .inkPossible
        }
        let mismatch =
          "Visibility target final MPos did not match the registered target plan. Existing ink may be present; no redraw is available."
        commitVisibilityTargetExecutionArtifact(
          planRevision: progress.planRevision,
          executionDisposition: .finalPositionMismatch,
          progress: progress,
          attemptDisposition: .failed(mismatch),
          retainedError: mismatch
        )
        return
      }
      commitVisibilityTargetExecutionArtifact(
        planRevision: progress.planRevision,
        executionDisposition: .completed,
        progress: progress
      )
    case .stopped(let scene, _, let progress):
      visibilityTargetSceneDisposition = scene
      executedVisibilityTargetPlanRevision = progress.planRevision
      let message =
        "Visibility target settled as \(scene.rawValue). Observe Existing Target if ink is possible; never redraw in this target area."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: progress.planRevision,
          executionDisposition: .stopped,
          progress: progress,
          attemptDisposition: .cancelled,
          retainedError: message
        )
      } else {
        explorationError = message
      }
    case .cancelled(let scene, _, let progress):
      visibilityTargetSceneDisposition = scene
      executedVisibilityTargetPlanRevision = progress.planRevision
      let message =
        "Visibility target settled as \(scene.rawValue). Observe Existing Target if ink is possible; never redraw in this target area."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: progress.planRevision,
          executionDisposition: .cancelled,
          progress: progress,
          attemptDisposition: .cancelled,
          retainedError: message
        )
      } else {
        explorationError = message
      }
    case .shutdown(let scene, _, let progress):
      visibilityTargetSceneDisposition = scene
      executedVisibilityTargetPlanRevision = progress.planRevision
      let message =
        "Visibility target settled as \(scene.rawValue). Observe Existing Target if ink is possible; never redraw in this target area."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: progress.planRevision,
          executionDisposition: .shutdown,
          progress: progress,
          attemptDisposition: .cancelled,
          retainedError: message
        )
      } else {
        explorationError = message
      }
    case .needsAttention(let phase, let scene, let failure, let progress):
      visibilityTargetSceneDisposition = scene
      executedVisibilityTargetPlanRevision = progress.planRevision
      let message =
        "Visibility target needs attention at \(phase): \(failure). Scene is \(scene.rawValue); ambiguous work is never resumed or redrawn."
      if scene != .pristine {
        commitVisibilityTargetExecutionArtifact(
          planRevision: progress.planRevision,
          executionDisposition: .failed("\(phase): \(failure)"),
          progress: progress,
          attemptDisposition: .failed(message),
          retainedError: message
        )
      } else {
        explorationError = message
      }
    }
  }

  private func commitVisibilityTargetExecutionArtifact(
    planRevision: String,
    executionDisposition: VisibilityTargetExecutionDisposition,
    progress: VisibilityTargetOperationProgress?,
    attemptDisposition: ExerciseAttemptDisposition = .succeeded,
    retainedError: String? = nil
  ) {
    do {
      let sourceGraph = visibilityDraftArtifactGraph ?? learningArtifactGraph
      guard let attemptID = activeExerciseAttemptID,
        let baseline = sourceGraph.currentRevision(
          for: .preTargetClearViewBaseline
        )?.id,
        let targetPose = sourceGraph.currentRevision(for: .targetPoseRegistration)?.id,
        let machineRegistration = sourceGraph.currentRevision(for: .machineCameraRegistration)?.id,
        let targetROI = sourceGraph.currentRevision(for: .targetROIRegistration)?.id
      else {
        throw LearningPathOperationError.requiredState(
          "Accepted target pose and pre-target baseline are unavailable."
        )
      }
      var graph = sourceGraph
      let commit = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .visibilityTargetExecution,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [baseline, targetPose, machineRegistration, targetROI]
        )
      )
      if visibilityDraftArtifactGraph != nil {
        visibilityDraftArtifactGraph = graph
      } else {
        learningArtifactGraph = graph
        applyArtifactInvalidations(commit.invalidatedRevisionIDs)
      }
      visibilityTargetSceneDisposition = .inkPossible
      executedVisibilityTargetPlanRevision = planRevision
      visibilityTargetExecutionAttemptEvidence = VisibilityTargetExecutionAttemptEvidence(
        attemptID: attemptID,
        planRevision: planRevision,
        disposition: executionDisposition,
        sceneDisposition: visibilityTargetSceneDisposition,
        completedTraversalStepCount: progress?.completedTraversalStepCount ?? 0,
        lastCompletedTraversalStep: progress?.lastCompletedTraversalStep
      )
      finishActiveExerciseAttempt(disposition: attemptDisposition)
      explorationError = retainedError
    } catch {
      explorationError = "Visibility-target artifact commit failed: \(actionableDescription(error))"
    }
  }

  private func observeExistingVisibilityTarget() async {
    guard
      visibilityObservationOperation == nil,
      visibilityTargetSceneDisposition == .inkPossible
        || visibilityTargetSceneDisposition == .targetObserved,
      let baseline = preTargetClearViewBaseline,
      let clearPosition = armatureGuidanceState?.acceptedClearPose?.position,
      let searchCircle = targetSearchCircle,
      let targetPlanRevision = executedVisibilityTargetPlanRevision,
      let attemptID = activeExerciseAttemptID,
      acceptedClearReturnIsCurrent,
      let cameraActions
    else { return }

    visibilityObservationGeneration &+= 1
    let operationID = VisibilityObservationOperationID()
    let capabilityID = VisibilityObservationCancelCapabilityID()
    let context = VisibilityObservationAuthorityContext(
      operationID: operationID,
      generation: visibilityObservationGeneration,
      attemptID: attemptID,
      baselineFrameID: baseline.frame.id,
      baselineSHA256: baseline.frame.contentSHA256,
      source: baseline.source,
      cameraConfigurationID: baseline.frame.cameraConfigurationID,
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      toolPaperRevision: explorationToolPaperRevision,
      targetAreaIdentity: targetAreaIdentity,
      clearPosition: clearPosition,
      searchCircle: searchCircle,
      targetPlanRevision: targetPlanRevision
    )
    visibilityObservationOperation = VisibilityObservationOperationPresentation(
      id: operationID,
      cancelCapabilityID: capabilityID,
      phase: .preparing,
      searchCircle: searchCircle,
      targetPlanRevision: targetPlanRevision
    )
    explorationError = nil

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.runVisibilityObservation(
        context: context,
        baseline: baseline,
        cameraActions: cameraActions
      )
    }
    visibilityObservationTask = task
    await task.value
  }

  private func runVisibilityObservation(
    context: VisibilityObservationAuthorityContext,
    baseline: DisplayedFrame,
    cameraActions: CameraActions
  ) async {
    await executeVisibilityObservation(
      context: context,
      baseline: baseline,
      cameraActions: cameraActions
    )
    settleVisibilityObservationOwner(context.operationID)
  }

  private func executeVisibilityObservation(
    context: VisibilityObservationAuthorityContext,
    baseline: DisplayedFrame,
    cameraActions: CameraActions
  ) async {
    do {
      try Task.checkCancellation()
      guard visibilityObservationContextIsCurrent(context) else { return }
      updateVisibilityObservationPhase(.acquiringFirstFrame, operationID: context.operationID)
      let first = try await captureProtocolFrame(newerThan: baseline.frame.captureNanoseconds)
      try Task.checkCancellation()
      guard visibilityObservationContextIsCurrent(context) else { return }
      updateVisibilityObservationPhase(.acquiringSecondFrame, operationID: context.operationID)
      let second = try await captureProtocolFrame(newerThan: first.frame.captureNanoseconds)
      try Task.checkCancellation()
      guard visibilityObservationContextIsCurrent(context) else { return }
      let expectedDiameter = expectedVisibilityTargetDiameterPixels()
      updateVisibilityObservationPhase(.analyzingFirstFrame, operationID: context.operationID)
      let outcome = await cameraActions.observeVisibilityTarget(
        VisibilityTargetObservationRequest(
          baseline: SamePoseFrameSample(
            displayedFrame: baseline,
            controllerPosition: context.clearPosition
          ),
          targetSamples: [
            SamePoseFrameSample(displayedFrame: first, controllerPosition: context.clearPosition),
            SamePoseFrameSample(displayedFrame: second, controllerPosition: context.clearPosition),
          ],
          targetSearchCircle: context.searchCircle,
          thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
          controllerSessionID: controllerSessionID,
          coordinateRevision: explorationCoordinateRevision,
          toolPaperRevision: explorationToolPaperRevision,
          controllerPositionToleranceMM: ControllerPositionAcceptancePolicy.toleranceMM,
          expectedDiameterPixels: expectedDiameter,
          minimumTargetPixels: 8,
          maximumCentroidSpreadPixels:
            FixedCameraOpticalSettlingPolicy.maximumCentroidSpreadPixels,
          maximumAreaRatio: 1.25,
          maximumBackgroundMeanAbsoluteDifference:
            FixedCameraOpticalSettlingPolicy.maximumBackgroundMeanAbsoluteDifference,
          alignmentSearchRadiusPixels:
            FixedCameraOpticalSettlingPolicy.alignmentSearchRadiusPixels,
          maximumAlignmentShiftPixels:
            FixedCameraOpticalSettlingPolicy.maximumAlignmentShiftPixels,
          algorithmRevision: "visibility-target-two-frame-cap-tip-circle-v7",
          targetPlanRevision: context.targetPlanRevision
        ),
        { [weak self] progress in
          Task { @MainActor [weak self] in
            self?.updateVisibilityObservationPhase(
              progress.sampleIndex == 1 ? .analyzingFirstFrame : .analyzingSecondFrame,
              operationID: context.operationID
            )
          }
        }
      )
      try Task.checkCancellation()
      guard visibilityObservationContextIsCurrent(context) else { return }
      switch outcome {
      case .observed(let observation):
        updateVisibilityObservationPhase(.committing, operationID: context.operationID)
        guard observation.targetPlanRevision == context.targetPlanRevision,
          visibilityObservationContextIsCurrent(context)
        else { return }
        try commitVisibilityTargetObservationArtifact()
        visibilityTargetObservation = observation
        visibilityTargetSceneDisposition = .targetObserved
        displayedFrame = second
        cameraOverlays = observation.overlays
        finishActiveExerciseAttempt(disposition: .succeeded)
        explorationError = nil
      case .rejected(let rejection):
        if case .observationAlreadyInProgress = rejection {
          explorationError =
            "Vision refused a duplicate target observation. The existing target and ROI remain current."
          return
        }
        visibilityTargetObservation = nil
        penTipOffsetRegistration = nil
        visibilityTargetSceneDisposition = .targetUnusable
        explorationError =
          "Visibility target unusable: \(rejection). Register New Target Area or record Paper Replaced; no redraw is available."
      case .cancelled:
        explorationError =
          "Vision observation cancelled. Existing target ink, baseline, accepted search circle, and active attempt remain current; Observe Existing Target when ready."
      }
    } catch is CancellationError {
      explorationError =
        "Vision observation cancelled. Existing target ink, baseline, accepted search circle, and active attempt remain current; Observe Existing Target when ready."
    } catch {
      guard visibilityObservationContextIsCurrent(context) else { return }
      explorationError = "Visibility target observation failed: \(actionableDescription(error))"
    }
  }

  private func updateVisibilityObservationPhase(
    _ phase: VisibilityObservationPhase,
    operationID: VisibilityObservationOperationID
  ) {
    guard let operation = visibilityObservationOperation,
      operation.id == operationID,
      operation.phase != .cancelling
    else { return }
    visibilityObservationOperation = VisibilityObservationOperationPresentation(
      id: operation.id,
      cancelCapabilityID: operation.cancelCapabilityID,
      phase: phase,
      searchCircle: operation.searchCircle,
      targetPlanRevision: operation.targetPlanRevision
    )
  }

  private func visibilityObservationContextIsCurrent(
    _ context: VisibilityObservationAuthorityContext
  ) -> Bool {
    guard !hasShutdown,
      visibilityObservationGeneration == context.generation,
      visibilityObservationOperation?.id == context.operationID,
      activeExerciseAttemptID == context.attemptID,
      preTargetClearViewBaseline?.frame.id == context.baselineFrameID,
      preTargetClearViewBaseline?.frame.contentSHA256 == context.baselineSHA256,
      preTargetClearViewBaseline?.source == context.source,
      preTargetClearViewBaseline?.frame.cameraConfigurationID == context.cameraConfigurationID,
      controllerSessionID == context.controllerSessionID,
      explorationCoordinateRevision == context.coordinateRevision,
      explorationToolPaperRevision == context.toolPaperRevision,
      targetAreaIdentity == context.targetAreaIdentity,
      targetSearchCircle == context.searchCircle,
      executedVisibilityTargetPlanRevision == context.targetPlanRevision,
      visibilityTargetSceneDisposition == .inkPossible
        || visibilityTargetSceneDisposition == .targetObserved,
      acceptedClearReturnIsCurrent,
      acceptedClearReturnSettlement.map({ protocolPositionsMatch($0.target, context.clearPosition) }
      )
        == true
    else { return false }
    return true
  }

  private func settleVisibilityObservationOwner(
    _ operationID: VisibilityObservationOperationID
  ) {
    guard visibilityObservationOperation?.id == operationID else { return }
    visibilityObservationTask = nil
    visibilityObservationOperation = nil
  }

  private func cancelVisibilityObservation(
    capabilityID: VisibilityObservationCancelCapabilityID
  ) async {
    guard let operation = visibilityObservationOperation,
      operation.cancelCapabilityID == capabilityID
    else { return }
    await cancelAndSettleVisibilityObservation()
    explorationError =
      "Vision observation cancelled. Existing target ink, baseline, accepted search circle, and active attempt remain current; Observe Existing Target when ready."
  }

  private func cancelAndSettleVisibilityObservation() async {
    guard let operation = visibilityObservationOperation else { return }
    visibilityObservationGeneration &+= 1
    visibilityObservationOperation = VisibilityObservationOperationPresentation(
      id: operation.id,
      cancelCapabilityID: operation.cancelCapabilityID,
      phase: .cancelling,
      searchCircle: operation.searchCircle,
      targetPlanRevision: operation.targetPlanRevision
    )
    let owner = visibilityObservationTask
    owner?.cancel()
    await owner?.value
    if visibilityObservationOperation?.id == operation.id {
      settleVisibilityObservationOwner(operation.id)
    }
  }

  private func commitVisibilityTargetObservationArtifact() throws {
    let sourceGraph = visibilityDraftArtifactGraph ?? learningArtifactGraph
    guard let attemptID = activeExerciseAttemptID,
      let execution = sourceGraph.currentRevision(
        for: .visibilityTargetExecution
      )?.id,
      let baseline = sourceGraph.currentRevision(
        for: .preTargetClearViewBaseline
      )?.id,
      let targetROI = sourceGraph.currentRevision(for: .targetROIRegistration)?.id
    else {
      throw LearningPathOperationError.requiredState(
        "Accepted target execution and same-pose baseline are unavailable."
      )
    }
    var graph = sourceGraph
    let commit = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: .visibilityTargetObservation,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [execution, baseline, targetROI]
      )
    )
    if visibilityDraftArtifactGraph != nil {
      visibilityDraftArtifactGraph = graph
    } else {
      learningArtifactGraph = graph
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
    }
  }

  private func expectedVisibilityTargetDiameterPixels() -> ClosedRange<Double> {
    guard let fit = machineCameraRegistration?.fit,
      let center = registeredTargetMachinePosition,
      let projected = try? VisibilityTargetPlanV2().relativeVertices.map({ vertex in
        try fit.cameraPoint(
          from: Point2<MachineSpace>(
            x: center.point.x + vertex.x,
            y: center.point.y + vertex.y
          ))
      })
    else { return 8...32 }
    let expected = max(
      projected.map(\.x).max()! - projected.map(\.x).min()!,
      projected.map(\.y).max()! - projected.map(\.y).min()!
    )
    return max(1, expected * 0.6)...max(2, expected * 1.6)
  }

  private func acceptVisibilityRegistration() {
    let sourceGraph = visibilityDraftArtifactGraph ?? learningArtifactGraph
    guard let observation = visibilityTargetObservation,
      observation.validSampleCount == 2,
      visibilityTargetSceneDisposition == .targetObserved,
      acceptedClearReturnIsCurrent,
      let machineRegistration = machineCameraRegistration,
      let capAnchor = targetCapAnchorEstimate,
      let capAnchorFrame = targetPoseRegistrationFrame,
      machineRegistration.source == capAnchorFrame.source,
      machineRegistration.cameraConfigurationID
        == capAnchorFrame.frame.cameraConfigurationID,
      let attemptID = activeExerciseAttemptID,
      let observationRevision = sourceGraph.currentRevision(
        for: .visibilityTargetObservation
      )?.id,
      let machineRegistrationRevision = sourceGraph.currentRevision(
        for: .machineCameraRegistration
      )?.id,
      let targetROIRevision = sourceGraph.currentRevision(
        for: .targetROIRegistration
      )?.id,
      let targetPoseRevision = sourceGraph.currentRevision(
        for: .targetPoseRegistration
      )?.id
    else { return }
    do {
      let tipOffset = try PenTipOffsetRegistration(
        capAnchor: capAnchor,
        anchorFrame: capAnchorFrame,
        observation: observation,
        estimatorRevision: "cap-anchor-to-visibility-centroid-v1"
      )
      let compatibility = AttemptCompatibility(
        cameraConfigurationID: observation.samples.first?.frame.cameraConfigurationID,
        coordinateSpace: .cameraPixels,
        units: .pixels,
        group: AttemptGroupIdentity(
          rawValue: "visibility-target-\(targetAreaIdentity.uuidString.lowercased())"
        ),
        algorithmRevision: observation.algorithmRevision
      )
      let sequence =
        max(
          acceptedAttemptSequence,
          visibilityDraftAcceptedAttemptSequence ?? acceptedAttemptSequence
        ) &+ 1
      var histories = visibilityObservationAttemptHistories
      try recordAttempt(
        ExerciseAttempt(
          id: attemptID,
          disposition: .succeeded,
          compatibility: compatibility,
          acceptedSequence: sequence,
          value: observation
        ),
        in: &histories,
        replacingAttemptID: activeExerciseAttemptMode == .replacement
          ? acceptedVisibilityObservationAttemptID : nil
      )
      var graph = sourceGraph
      let tipOffsetCandidate = LearningArtifactRevision(
        kind: .penTipOffsetRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [observationRevision, targetPoseRevision]
      )
      let priorTipOffsetID = visibilityRepeatSnapshot?.learningArtifactGraph
        .currentRevision(for: .penTipOffsetRegistration)?.id
      let tipOffsetCommit =
        if activeExerciseAttemptMode != .normal,
          let priorTipOffsetID,
          graph.revision(id: priorTipOffsetID)?.state == .invalidated
        {
          try graph.commitReplacement(
            tipOffsetCandidate,
            supersedingInvalidatedRevision: priorTipOffsetID
          )
        } else {
          try graph.commitReplacement(tipOffsetCandidate)
        }
      let candidate = LearningArtifactRevision(
        kind: .visibilityRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [
          observationRevision,
          machineRegistrationRevision,
          targetROIRevision,
          tipOffsetCommit.currentRevision.id,
        ]
      )
      let commit: LearningArtifactCommit
      if activeExerciseAttemptMode != .normal,
        let acceptedRegistrationID = visibilityRepeatSnapshot?.learningArtifactGraph
          .currentRevision(for: .visibilityRegistration)?.id
      {
        commit = try graph.commitReplacement(
          candidate,
          supersedingInvalidatedRevision: acceptedRegistrationID
        )
      } else {
        commit = try graph.commitReplacement(candidate)
      }
      learningArtifactGraph = graph
      visibilityDraftArtifactGraph = nil
      if let draftHistories = visibilityDraftClearViewAttemptHistories {
        clearViewAttemptHistories = draftHistories
      }
      if let draftSequence = visibilityDraftAcceptedAttemptSequence {
        acceptedAttemptSequence = max(acceptedAttemptSequence, draftSequence)
      }
      visibilityDraftClearViewAttemptHistories = nil
      visibilityDraftAcceptedAttemptSequence = nil
      applyArtifactInvalidations(
        tipOffsetCommit.invalidatedRevisionIDs.union(commit.invalidatedRevisionIDs)
      )
      visibilityTargetObservation = observation
      penTipOffsetRegistration = tipOffset
      visibilityRegistrationAccepted = true
      visibilityObservationAttemptHistories = histories
      acceptedVisibilityObservationAttemptID = attemptID
      acceptedAttemptSequence = sequence
      finishActiveExerciseAttempt(disposition: .succeeded)
      observedDrawingTrialStep = .chooseIsolatedLinePlan
      explorationError = nil
    } catch {
      explorationError = "Visibility registration failed: \(actionableDescription(error))"
    }
  }

  private func rejectVisibilityRegistration() {
    guard
      activeExerciseAttemptOwnerID
        == .humanGuidedDiscovery(.acceptVisibilityRegistration)
    else { return }
    finishActiveExerciseAttempt(disposition: .cancelled)
    restartableExerciseItemID = .humanGuidedDiscovery(.acceptVisibilityRegistration)
    explorationError =
      "Operator rejected the visibility-registration decision. The exact two-frame observation and existing physical target remain attributable; no redraw or evidence mutation occurred."
  }

  private func registerNewTargetArea() {
    if let owner = activeExerciseAttemptOwnerID,
      owner != .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)
    {
      finishActiveExerciseAttempt(disposition: .cancelled)
    }
    retiredTargetAreaDispositions[targetAreaIdentity] = visibilityTargetSceneDisposition
    invalidateCurrentVisibilityArtifactAuthority()
    targetAreaIdentity = UUID()
    targetAreaRelocationRequired = true
    targetAreaRelocationCompleted = false
    resetCurrentTargetAreaEvidence()
    explorationError = "Move to a new target area first."
  }

  private func visibilityRegistrationPayloadSnapshot() -> VisibilityRegistrationPayloadSnapshot {
    VisibilityRegistrationPayloadSnapshot(
      targetPoseRegistrationFrame: targetPoseRegistrationFrame,
      registeredTargetMachinePosition: registeredTargetMachinePosition,
      targetCapAnchorEstimate: targetCapAnchorEstimate,
      targetSearchCircle: targetSearchCircle,
      targetCapAnchorAndSearchCircleAccepted: targetCapAnchorAndSearchCircleAccepted,
      preTargetClearViewBaseline: preTargetClearViewBaseline,
      visibilityTargetSceneDisposition: visibilityTargetSceneDisposition,
      visibilityTargetObservation: visibilityTargetObservation,
      penTipOffsetRegistration: penTipOffsetRegistration,
      executedVisibilityTargetPlanRevision: executedVisibilityTargetPlanRevision,
      visibilityTargetExecutionAttemptEvidence: visibilityTargetExecutionAttemptEvidence,
      visibilityRegistrationAccepted: visibilityRegistrationAccepted,
      machineCameraRegistration: machineCameraRegistration,
      clearViewPoseAccepted: clearViewPoseAccepted,
      registeredTargetReturnSettlement: registeredTargetReturnSettlement,
      acceptedClearReturnSettlement: acceptedClearReturnSettlement,
      pendingClearViewLabel: pendingClearViewLabel,
      armatureGuidanceState: armatureGuidanceState,
      lastArmatureObservation: lastArmatureObservation,
      targetAreaIdentity: targetAreaIdentity,
      targetAreaRelocationRequired: targetAreaRelocationRequired,
      targetAreaRelocationCompleted: targetAreaRelocationCompleted,
      retiredTargetAreaDispositions: retiredTargetAreaDispositions,
      learningArtifactGraph: learningArtifactGraph,
      observedDrawingTrialStep: observedDrawingTrialStep
    )
  }

  private func restoreVisibilityRegistrationPayload(
    _ snapshot: VisibilityRegistrationPayloadSnapshot
  ) {
    targetPoseRegistrationFrame = snapshot.targetPoseRegistrationFrame
    registeredTargetMachinePosition = snapshot.registeredTargetMachinePosition
    targetCapAnchorEstimate = snapshot.targetCapAnchorEstimate
    targetSearchCircle = snapshot.targetSearchCircle
    targetCapAnchorAndSearchCircleAccepted = snapshot.targetCapAnchorAndSearchCircleAccepted
    preTargetClearViewBaseline = snapshot.preTargetClearViewBaseline
    visibilityTargetSceneDisposition = snapshot.visibilityTargetSceneDisposition
    visibilityTargetObservation = snapshot.visibilityTargetObservation
    penTipOffsetRegistration = snapshot.penTipOffsetRegistration
    executedVisibilityTargetPlanRevision = snapshot.executedVisibilityTargetPlanRevision
    visibilityTargetExecutionAttemptEvidence = snapshot.visibilityTargetExecutionAttemptEvidence
    visibilityRegistrationAccepted = snapshot.visibilityRegistrationAccepted
    machineCameraRegistration = snapshot.machineCameraRegistration
    clearViewPoseAccepted = snapshot.clearViewPoseAccepted
    registeredTargetReturnSettlement = snapshot.registeredTargetReturnSettlement
    acceptedClearReturnSettlement = snapshot.acceptedClearReturnSettlement
    pendingClearViewLabel = snapshot.pendingClearViewLabel
    armatureGuidanceState = snapshot.armatureGuidanceState
    lastArmatureObservation = snapshot.lastArmatureObservation
    targetAreaIdentity = snapshot.targetAreaIdentity
    targetAreaRelocationRequired = snapshot.targetAreaRelocationRequired
    targetAreaRelocationCompleted = snapshot.targetAreaRelocationCompleted
    retiredTargetAreaDispositions = snapshot.retiredTargetAreaDispositions
    learningArtifactGraph = snapshot.learningArtifactGraph
    observedDrawingTrialStep = snapshot.observedDrawingTrialStep
  }

  private func resetCurrentTargetAreaEvidence() {
    currentCameraCalibrationFailure = nil
    targetPoseRegistrationFrame = nil
    registeredTargetMachinePosition = nil
    targetCapAnchorEstimate = nil
    proposedMachineCameraRegistration = nil
    proposedTargetSearchCircle = nil
    targetGeometryProposalID = nil
    targetSearchCircle = nil
    targetCapAnchorAndSearchCircleAccepted = false
    preTargetClearViewBaseline = nil
    blankTargetBaselineCandidate = nil
    visibilityTargetObservation = nil
    penTipOffsetRegistration = nil
    executedVisibilityTargetPlanRevision = nil
    visibilityTargetExecutionAttemptEvidence = nil
    visibilityRegistrationAccepted = false
    machineCameraRegistration = nil
    visibilityTargetSceneDisposition = .pristine
    clearViewPoseAccepted = false
    pendingClearViewLabel = nil
    armatureGuidanceState = nil
    lastArmatureObservation = nil
    registeredTargetReturnSettlement = nil
    acceptedClearReturnSettlement = nil
  }

  private func invalidateCurrentVisibilityArtifactAuthority() {
    var graph = visibilityDraftArtifactGraph ?? learningArtifactGraph
    let invalidation = graph.invalidateCurrentRevisions(rootKinds: [
      .targetPoseRegistration,
      .machineCameraRegistration,
      .targetROIRegistration,
      .clearPose,
      .preTargetClearViewBaseline,
      .visibilityTargetExecution,
      .visibilityTargetObservation,
      .visibilityRegistration,
    ])
    if visibilityDraftArtifactGraph != nil {
      visibilityDraftArtifactGraph = graph
    } else {
      learningArtifactGraph = graph
      applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    }
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
      owner != .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)
    {
      finishActiveExerciseAttempt(disposition: .cancelled)
    }
    retiredTargetAreaDispositions[targetAreaIdentity] = visibilityTargetSceneDisposition
    invalidateCurrentVisibilityArtifactAuthority()
    targetAreaIdentity = UUID()
    targetAreaRelocationRequired = false
    targetAreaRelocationCompleted = false
    if let replacementSnapshot {
      simulatedLearningSnapshot = replacementSnapshot
      explorationToolPaperRevision = replacementSnapshot.toolPaperRevision
    } else {
      explorationToolPaperRevision = UUID()
    }
    resetCurrentTargetAreaEvidence()
    explorationError = nil
  }

  func performCurrentLearningPathAction() async {
    guard visibilityObservationOperation == nil, clearViewPoseAccepted,
      !explorationOperationInProgress
    else { return }
    let attemptedStep = observedDrawingTrialStep
    if activeExerciseAttemptOwnerID == nil {
      beginExerciseAttempt(
        ownerID: .observedDrawingTrial(attemptedStep),
        mode: activeExerciseAttemptMode ?? .normal
      )
    }
    let payloadSnapshot = drawingTrialPayloadSnapshot()
    if attemptedStep == .drawIsolatedLine {
      drawingTrialStrokeCompletedNaturally = false
    }
    explorationOperationInProgress = true
    explorationError = nil
    defer { explorationOperationInProgress = false }
    do {
      switch observedDrawingTrialStep {
      case .chooseIsolatedLinePlan:
        try recordIsolatedLinePlan(selectedLineDirection)
      case .captureTargetAnchoredBaseline:
        try await captureTargetAnchoredTrialBaseline()
      case .moveToLineStart:
        try await moveToRecordedLineStart()
      case .drawIsolatedLine:
        try await drawIsolatedTrialLine()
      case .returnToClearPoseAndObserveNewInk:
        try await returnToClearPoseAndObserveTrialInk()
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
        drawingTrialStrokeEvidence != payloadSnapshot.strokeEvidence
      {
        var commitFailure: String?
        if drawingTrialStrokeCompletedNaturally {
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
      let disposition = attemptDisposition(for: String(describing: error))
      finishActiveExerciseAttempt(disposition: disposition)
      restartableExerciseItemID = .observedDrawingTrial(attemptedStep)
    }
  }

  func recordDrawingTrialAssessment(_ assessment: DrawingTrialAssessment) async {
    guard visibilityObservationOperation == nil,
      observedDrawingTrialStep == .compareIntendedAndObservedGeometry
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
      if let episode { completedExplorationEpisodes.append(episode) }
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
    if let operation = visibilityObservationOperation {
      return
        "Vision owns the foreground operation. \(operation.busyDetail) Only Cancel Vision is available."
    }
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
    if let reason = foregroundVisionOperationUnavailableReason { return reason }
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
    guard visibilityObservationOperation == nil, !hasShutdown else { return }
    if visible {
      visibleLayers.insert(layer)
    } else {
      visibleLayers.remove(layer)
    }
  }

  func refreshSerialDevices() async {
    guard visibilityObservationOperation == nil else { return }
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
    guard visibilityObservationOperation == nil else { return }
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
    guard visibilityObservationOperation == nil else { return }
    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard activeDiscoverySequenceID == nil, !explorationOperationInProgress else { return }
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
    guard visibilityObservationOperation == nil else { return }
    guard currentCameraCalibrationBusyReason == nil else { return }
    await selectSerialDevice(descriptor)
    await openSelectedMachineSession()
  }

  func connectSelectedController() async {
    guard visibilityObservationOperation == nil else { return }
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
    guard visibilityObservationOperation == nil else { return }
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
            await failDiscovery(sequenceID, reason: "Simulated pen action refused: \(refusal).")
            return
          }
        } else {
          await requestPenActuation(command)
          guard case .commandedAndSettled = machineSnapshot?.lastPenOutcome else {
            await failDiscovery(sequenceID, reason: lastPenOutcomeText)
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
        reason:
          "The Boundary commit is missing its attempt-bound Stop/Idle/final-MPos controller settlement."
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
        reason: "Atomic Boundary observation commit failed: \(error)"
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

  private func failDiscovery(_ sequenceID: DiscoverySequenceID, reason: String) async {
    if var transaction = discoveryTransactions[sequenceID] {
      transaction.fail(reason)
      discoveryTransactions[sequenceID] = transaction
    }
    discoveryError = reason
    let disposition = attemptDisposition(for: reason)
    let boundaryDirection = boundaryDirection(for: sequenceID)
    let boundaryAttemptID = activeExerciseAttemptID
    let acceptedFallback = boundaryDirection.flatMap { boundarySideAggregates[$0] }
    let isBoundaryRepeat =
      boundaryDirection != nil
      && (activeExerciseAttemptMode == .replacement || activeExerciseAttemptMode == .additional)
    recordDiscoveryAttempt(sequenceID: sequenceID, disposition: disposition)
    if let direction = boundaryDirection, let attemptID = boundaryAttemptID {
      let activityDisposition: BoundaryActivityDisposition =
        if reason.localizedCaseInsensitiveContains("ambiguous")
          || reason.localizedCaseInsensitiveContains("unknown after write")
        {
          .ambiguous(reason)
        } else {
          .failed(reason)
        }
      appendBoundaryActivity(
        actor: .workspace,
        direction: direction,
        phase: .recovery,
        disposition: activityDisposition,
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
    activeStopTarget = nil
    stopDispositionLatch = nil
    boundaryTeachingResultText = "Discovery stopped: \(reason)"
  }

  func stopCurrentOperation(capabilityID: ContextualStopCapabilityID) async {
    guard visibilityObservationOperation == nil, !jogCancelRequestInProgress,
      let target = activeStopTarget,
      target.capabilityID == capabilityID,
      latchContextualStopDisposition(
        for: target,
        intent: .operatorStop,
        actor: "Operator",
        action: "Stop"
      )
    else { return }
    switch target {
    case .pairedBoundary(_, let transactionID, let operationOwner, let attemptID, let direction):
      let sequenceID = sequenceID(for: direction)
      guard discoveryTransactions[sequenceID]?.id == transactionID,
        case .awaitContextualStop(direction) = discoveryTransactions[sequenceID]?.currentStep?
          .action
      else {
        await failDiscovery(
          sequenceID,
          reason: "The Stop capability no longer owns this Boundary Discovery transaction.")
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
      let owner = boundaryMotionTask
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      await owner?.value
      if !recorded {
        if case .failed = discoveryTransactions[sequenceID]?.state {
          return
        }
        await failDiscovery(
          sequenceID,
          reason: "The typed operator Stop event could not be recorded."
        )
      }

    case .manualJog:
      let owner = manualJogTask
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      _ = await owner?.value

    case .exerciseMotion(_, _, let ownerID, _):
      let owner = exerciseMotionTask
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      _ = await owner?.value
      if ownerID != .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry) {
        finishActiveExerciseAttempt(disposition: .cancelled)
        restartableExerciseItemID = ownerID
      }

    case .visibilityTarget(_, let operationOwner, let ownerID):
      await requestVisibilityTargetIntent(.operatorStop, operationOwner: operationOwner)
      await waitForVisibilityTargetOwner(operationOwner)
      finishActiveExerciseAttempt(disposition: .cancelled)
      if visibilityTargetSceneDisposition == .pristine {
        restartableExerciseItemID = ownerID
      }

    case .drawingTrial:
      let liveOwner = drawingTrialTask
      let simulatedOwner = simulatedOperationTask
      let inkMayExist = liveOwner != nil || simulatedOwner != nil
      await requestSingleJogCancel(for: target, intent: .operatorStop)
      _ = await liveOwner?.value
      _ = await simulatedOwner?.value
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
    }
  }

  private func requestVisibilityTargetIntent(
    _ intent: JogCancelIntent,
    operationOwner: ContextualMotionOwnerID
  ) async {
    switch operationOwner {
    case .liveOperation(let operationID):
      let runtimeIntent: VisibilityTargetOperationIntent =
        switch intent {
        case .operatorStop: .stop
        case .cancelAttempt: .cancel
        case .shutdown: .shutdown
        }
      if let machineActions {
        _ = await machineActions.requestVisibilityTargetIntent(runtimeIntent, operationID)
      }
    case .simulated(let operationID):
      let runtimeIntent: SimulatedLearningOperationIntent =
        switch intent {
        case .operatorStop: .stop
        case .cancelAttempt: .cancel
        case .shutdown: .shutdown
        }
      _ = await simulatedLearningRuntime.request(runtimeIntent, for: operationID)
    case .liveBoundary:
      break
    }
  }

  private func waitForVisibilityTargetOwner(
    _ operationOwner: ContextualMotionOwnerID
  ) async {
    switch operationOwner {
    case .liveOperation:
      _ = await visibilityTargetTask?.value
    case .simulated:
      _ = await simulatedOperationTask?.value
    case .liveBoundary:
      break
    }
  }

  private func requestSingleJogCancel(
    for target: ContextualStopTarget,
    intent: JogCancelIntent
  ) async {
    if case .simulated(let operationID) = target.operationOwner {
      guard !jogCancelRequestInProgress,
        activeStopTarget?.capabilityID == target.capabilityID,
        stopDispositionLatch?.capabilityID == target.capabilityID,
        stopDispositionLatch?.intent == intent
      else { return }
      jogCancelRequestInProgress = true
      defer { jogCancelRequestInProgress = false }
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
    guard !jogCancelRequestInProgress,
      activeStopTarget?.capabilityID == target.capabilityID,
      stopDispositionLatch?.capabilityID == target.capabilityID,
      stopDispositionLatch?.intent == intent
    else { return }
    jogCancelRequestInProgress = true
    defer { jogCancelRequestInProgress = false }
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
    guard activeStopTarget?.capabilityID == target.capabilityID,
      stopDispositionLatch == nil
    else { return false }
    stopDispositionLatch = ContextualStopDispositionLatch(
      capabilityID: target.capabilityID,
      intent: intent,
      actor: actor
    )
    lastContextualStopAuditRecord = ContextualStopAuditRecord(
      capabilityID: target.capabilityID,
      actor: actor,
      action: action,
      disposition: intent,
      outcome: "requested; awaiting the original owner"
    )
    return true
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
          failureCode: "manual_jog_admission_rejected",
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
      manualJogTask = nil
      if activeStopTarget == stopTarget {
        activeStopTarget = nil
        stopDispositionLatch = nil
      }
    }
    let operation = Task { await admittedOperation.outcome() }
    manualJogTask = operation
    activeStopTarget = stopTarget
    stopDispositionLatch = nil
    await Task.yield()
    let interimSnapshot = await machineActions.snapshot()
    if canCommit(generation) { machineSnapshot = interimSnapshot }
    let outcome = await operation.value
    let finalSnapshot = await machineActions.snapshot()
    guard canCommit(generation) else { return nil }
    machineSnapshot = finalSnapshot
    let telemetryTerminal: (
      phase: WorkflowTelemetryPhase, code: String?, recovery: WorkflowTelemetryRecovery
    ) = switch outcome {
    case .acceptedThenCompleted:
      (.completed, nil, .none)
    case .cancelled:
      (.cancelled, nil, .none)
    case .refused:
      (.failed, "manual_jog_refused", .resolveNamedFailure)
    case .ambiguous:
      (.failed, "manual_jog_ambiguous", .resolveNamedFailure)
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
    activeStopTarget = target
    stopDispositionLatch = nil
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
    simulatedOperationTask = outcomeTask
    _ = await outcomeTask.value
    simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
    simulatedOperationTask = nil
    jogRequestInProgress = false
    if activeStopTarget == target { activeStopTarget = nil }
    if stopDispositionLatch?.capabilityID == target.capabilityID {
      stopDispositionLatch = nil
    }
  }

  func discoverCameras() async {
    guard visibilityObservationOperation == nil else { return }
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
    guard visibilityObservationOperation == nil else {
      cameraError = foregroundVisionOperationUnavailableReason
      return
    }
    guard currentCameraCalibrationBusyReason == nil else {
      cameraError = currentCameraCalibrationBusyReason
      return
    }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard let cameraActions, activeDiscoverySequenceID == nil,
      !explorationOperationInProgress
    else {
      cameraError =
        "Finish the current discovery or learning action before changing camera configuration."
      return
    }
    clearAutomaticVisionPresentation()
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
    guard visibilityObservationOperation == nil else { return }
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
      invalidateCameraDependentLearningAuthority()
    }
    updateCameraError()
    beginFrameUpdates(generation: generation)
  }

  func stopCamera() async {
    guard visibilityObservationOperation == nil else { return }
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
    guard visibilityObservationOperation == nil else { return }
    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard activeDiscoverySequenceID == nil, !explorationOperationInProgress else {
      cameraError = "Finish the current discovery or learning action before restarting the camera."
      return
    }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    invalidateCameraDependentLearningAuthority()
    guard let cameraActions else { return }
    let snapshot = await cameraActions.restart()
    guard canCommit(generation) else { return }
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    cameraOverlays = []
    analysisFrameHeld = false
    lastSceneMeasurement = nil
    updateCameraError()
    beginFrameUpdates(generation: generation)
  }

  func inspectLatestScene() async {
    guard visibilityObservationOperation == nil else { return }
    guard currentCameraCalibrationBusyReason == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard frameMode == .live, !scopedVisionAnalysisActive,
      !sceneInspectionInProgress, let cameraActions
    else { return }
    sceneInspectionInProgress = true
    cameraError = nil
    defer { sceneInspectionInProgress = false }
    do {
      guard let inspection = try await cameraActions.inspectScene(0) else {
        guard canCommit(generation) else { return }
        cameraError = "No newer camera frame is available for analysis."
        return
      }
      guard canCommit(generation) else { return }
      analysisFrameHeld = true
      displayedFrame = inspection.displayedFrame
      lastSceneMeasurement = inspection.measurement
      cameraOverlays = inspection.measurement.overlays
    } catch {
      guard canCommit(generation) else { return }
      cameraError = actionableDescription(error)
    }
  }

  func resumeLivePreview() async {
    guard visibilityObservationOperation == nil else { return }
    guard currentCameraCalibrationBusyReason == nil else { return }
    guard frameMode == .live, let cameraActions else { return }
    analysisFrameHeld = false
    lastSceneMeasurement = nil
    cameraOverlays = []
    let snapshot = await cameraActions.snapshot()
    cameraSnapshot = snapshot
    if let latest = snapshot.latestFrame { displayedFrame = latest }
  }

  private func beginScopedVisionAnalysis() async -> Bool {
    guard !hasShutdown, frameMode == .live,
      case .running = cameraSnapshot?.state,
      visibilityObservationOperation == nil,
      !scopedVisionAnalysisActive,
      let cameraActions
    else { return false }
    let generation = lifetimeGeneration
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    let snapshot = await cameraActions.setAutomaticInspection(.twoFPS)
    guard canCommit(generation), frameMode == .live else {
      _ = await cameraActions.setAutomaticInspection(nil)
      return false
    }
    scopedVisionAnalysisActive = true
    visionError = snapshot.lastError
    analysisFrameHeld = false
    visionAnalysisSnapshot = snapshot
    beginVisionUpdates(generation: generation)
    if let result = snapshot.latestResult { receiveVision(result) }
    return true
  }

  private func endScopedVisionAnalysis(_ scopeWasStarted: Bool) async {
    guard scopeWasStarted, let cameraActions else { return }
    visionUpdateTask?.cancel()
    visionUpdateTask = nil
    let generation = lifetimeGeneration
    let snapshot = await cameraActions.setAutomaticInspection(nil)
    guard canCommit(generation) else { return }
    scopedVisionAnalysisActive = false
    visionError = snapshot.lastError
    analysisFrameHeld = false
    visionAnalysisSnapshot = snapshot
    lastSceneMeasurement = nil
    cameraOverlays = []
    let latestCameraSnapshot = await cameraActions.snapshot()
    guard canCommit(generation), frameMode == .live else { return }
    cameraSnapshot = latestCameraSnapshot
    if let latest = latestCameraSnapshot.latestFrame { displayedFrame = latest }
  }

  func captureCameraSnapshot() async {
    guard visibilityObservationOperation == nil else { return }
    guard let generation = beginHardwareIntent() else { return }
    defer { endHardwareIntent() }
    guard frameMode == .live, let cameraActions else { return }
    cameraError = nil
    do {
      let path = try await cameraActions.captureSnapshot()
      guard canCommit(generation) else { return }
      lastCameraSnapshotPath = path
    } catch {
      guard canCommit(generation) else { return }
      cameraError = actionableDescription(error)
    }
  }

  func switchFrameMode(_ mode: OperatorFrameMode) async {
    guard visibilityObservationOperation == nil else { return }
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
    cameraOverlays = []
    cameraError = nil
    switch mode {
    case .live:
      let snapshot = await cameraActions.start()
      guard canCommit(generation) else { return }
      frameMode = .live
      if let parkedLiveLearningAuthority {
        restoreLearningAuthority(parkedLiveLearningAuthority)
        self.parkedLiveLearningAuthority = nil
      }
      cameraSnapshot = snapshot
      displayedFrame = cameraSnapshot?.latestFrame
      latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
      updateCameraError()
      beginFrameUpdates(generation: generation)
    case .simulated:
      let snapshot = await cameraActions.stop()
      guard canCommit(generation) else { return }
      cameraSnapshot = snapshot
      latestLiveCameraFrame = nil
      parkedLiveLearningAuthority = captureLearningAuthority()
      resetLearningAuthorityForSimulation()
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
    await cancelAndSettleVisibilityObservation()
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
    guard visibilityObservationOperation == nil else { return }
    guard !analysisFrameHeld, !scopedVisionAnalysisActive else { return }
    displayedFrame = frame
  }

  private func beginVisionUpdates(generation: UInt64) {
    guard canCommit(generation), let cameraActions, scopedVisionAnalysisActive else { return }
    visionUpdateTask = Task { [weak self] in
      let stream = await cameraActions.analysisUpdates()
      for await snapshot in stream {
        guard !Task.isCancelled, let self,
          self.canCommit(generation), self.scopedVisionAnalysisActive
        else { return }
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
          guard !Task.isCancelled, self.canCommit(generation), self.scopedVisionAnalysisActive
          else { return }
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

  private func armatureContext(
    frame: StampedFrame,
    region: PixelRect
  ) -> ArmatureGuidanceContext {
    ArmatureGuidanceContext(
      controllerSessionID: controllerSessionID,
      coordinateRevision: explorationCoordinateRevision,
      cameraConfigurationID: frame.cameraConfigurationID,
      observationRegion: region,
      toolPaperRevision: explorationToolPaperRevision
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
      : "new ink observed with target-anchored projected residual"
    if var episode = currentExplorationEpisode {
      episode.targetContactPoint = observation.lineStartPoint
      episode.visionEstimate = ExplorationAssessment(
        summary: "\(observation.observedPixelCount) new line pixels",
        provenance: "\(observation.algorithmRevision) exact same-pose two-frame subtraction"
      )
      if let residual = observation.residual {
        episode.residual = ExplorationResidual(
          rmsPixels: residual.rootMeanSquareEndpointPixels,
          maximumPixels: residual.maximumEndpointPixels,
          crossTrackPixels: residual.rootMeanSquareCrossTrackPixels,
          summary: "camera-space target-anchored residual",
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
        await failDiscovery(sequenceID, reason: question.negativeAcknowledgement)
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
        await failDiscovery(sequenceID, reason: boundaryTerminalDescription(terminal))
      } else {
        await failDiscovery(sequenceID, reason: "Boundary owner admission was rejected.")
      }
      return
    }
    guard admittedOperation.ownerID == request.ownerID else {
      await failDiscovery(
        sequenceID, reason: "Boundary owner admission returned a mismatched owner identity.")
      return
    }
    let stopTarget = ContextualStopTarget.pairedBoundary(
      capabilityID: ContextualStopCapabilityID(),
      transactionID: transactionID,
      operationOwner: .liveBoundary(request.ownerID),
      attemptID: attemptID,
      direction: discoveryDirection
    )
    activeStopTarget = stopTarget
    stopDispositionLatch = nil
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
          reason: "Injected Boundary settlement failure after the owner returned."
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
          reason:
            "Boundary settlement owner/disposition did not match the first admitted operator action."
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
      await failDiscovery(sequenceID, reason: boundaryTerminalDescription(terminal))
    }
    boundaryTeachingState = .idle
    if activeStopTarget == stopTarget { activeStopTarget = nil }
    if stopDispositionLatch?.capabilityID == stopTarget.capabilityID {
      stopDispositionLatch = nil
    }
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
        reason: "Simulated Boundary owner admission was refused: \(refusal)."
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
    activeStopTarget = stopTarget
    stopDispositionLatch = nil
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

    let outcomeTask = Task<SimulatedLearningOperationOutcome?, Never> {
      [simulatedLearningRuntime, simulatedExecutionPacing] in
      let execution = await simulatedLearningRuntime.executeBoundaryCooperatively(
        operation.id,
        pacing: simulatedExecutionPacing
      )
      if case .success(let outcome) = execution.result {
        return outcome
      }
      // Stop is intentionally usable immediately after admission. It can win
      // before this cooperative executor task is scheduled, in which case the
      // runtime has already stored the terminal outcome and rejects a second
      // execution start. Await the original owner identity instead of turning
      // that valid race into a failed Boundary attempt.
      return try? await simulatedLearningRuntime.waitForOutcome(
        of: operation.id
      ).result.get()
    }
    simulatedOperationTask = outcomeTask
    guard let outcome = await outcomeTask.value else {
      await failDiscovery(sequenceID, reason: "The simulated Boundary owner lost its outcome.")
      return
    }
    simulatedOperationTask = nil
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
            reason: "Injected simulated Boundary settlement failure."
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
        await failDiscovery(sequenceID, reason: "Simulated final MPos was invalid: \(error).")
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

    case .stopped, .naturallyCompleted, .failed, .shutdown:
      await failDiscovery(
        sequenceID,
        reason:
          "Simulated Boundary settlement did not match the first admitted operator disposition."
      )
    }
    boundaryTeachingState = .idle
    if activeStopTarget == stopTarget { activeStopTarget = nil }
    if stopDispositionLatch?.capabilityID == stopTarget.capabilityID {
      stopDispositionLatch = nil
    }
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
    guard visibilityObservationOperation == nil, activeExerciseAttemptOwnerID == nil else { return }
    activeExerciseAttemptMode = mode
    restartableExerciseItemID = nil
    switch ownerID {
    case .humanGuidedDiscovery(.penInteraction):
      await beginPenInteraction()
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      await beginPairedBoundarySide(selectedBoundaryDirection)
    case .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry):
      if mode == .replacement, targetCapAnchorAndSearchCircleAccepted {
        guard visibilityTargetSceneDisposition == .pristine else {
          activeExerciseAttemptMode = nil
          explorationError =
            "This target area may contain ink. Register New Target Area or record Paper Replaced; earlier Stage 3 rows cannot re-authorize a draw here."
          return
        }
        visibilityRepeatSnapshot = visibilityRegistrationPayloadSnapshot()
        visibilityDraftArtifactGraph = learningArtifactGraph
        visibilityDraftClearViewAttemptHistories = clearViewAttemptHistories
        visibilityDraftAcceptedAttemptSequence = acceptedAttemptSequence
        resetCurrentTargetAreaEvidence()
      }
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      pendingClearViewLabel = nil
    case .humanGuidedDiscovery(.discoverAndAcceptClearView),
      .humanGuidedDiscovery(.confirmBlankTargetBaseline),
      .humanGuidedDiscovery(.returnToRegisteredTargetPose),
      .humanGuidedDiscovery(.drawVisibilityTarget),
      .humanGuidedDiscovery(.returnAndObserveExistingTarget),
      .humanGuidedDiscovery(.acceptVisibilityRegistration):
      if mode == .replacement,
        visibilityTargetSceneDisposition != .pristine,
        ownerID == .humanGuidedDiscovery(.discoverAndAcceptClearView)
          || ownerID == .humanGuidedDiscovery(.confirmBlankTargetBaseline)
          || ownerID == .humanGuidedDiscovery(.returnToRegisteredTargetPose)
      {
        activeExerciseAttemptMode = nil
        explorationError =
          "This target area may contain ink. Register New Target Area or record Paper Replaced; earlier Stage 3 rows cannot re-authorize a draw here."
        return
      }
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      if ownerID == .humanGuidedDiscovery(.discoverAndAcceptClearView) {
        pendingClearViewLabel = nil
      }
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
      var owner: Task<Void, Never>?
      switch target {
      case .exerciseMotion:
        owner = exerciseMotionTask.map { task in
          Task<Void, Never> { _ = await task.value }
        }
      case .visibilityTarget(_, let operationOwner, _):
        await requestVisibilityTargetIntent(
          .cancelAttempt,
          operationOwner: operationOwner
        )
        switch operationOwner {
        case .liveOperation:
          owner = visibilityTargetTask.map { task in
            Task<Void, Never> { _ = await task.value }
          }
        case .simulated:
          owner = simulatedOperationTask.map { task in
            Task<Void, Never> { _ = await task.value }
          }
        case .liveBoundary:
          owner = nil
        }
      case .drawingTrial:
        if frameMode == .simulated {
          owner = simulatedOperationTask.map { task in
            Task<Void, Never> { _ = await task.value }
          }
        } else {
          owner = drawingTrialTask.map { task in
            Task<Void, Never> { _ = await task.value }
          }
        }
      case .pairedBoundary, .manualJog:
        owner = nil
      }
      if case .visibilityTarget = target {
        // The runtime compound owner owns its first-intent latch and compatible
        // mechanical cancel. Do not send the generic jog-cancel route as well.
      } else {
        await requestSingleJogCancel(for: target, intent: .cancelAttempt)
      }
      await owner?.value
    }
    if ownerID == .humanGuidedDiscovery(.discoverAndAcceptClearView) {
      recordClearViewAttempt(label: nil, disposition: .cancelled)
    } else if ownerID == .observedDrawingTrial(.compareIntendedAndObservedGeometry) {
      recordComparisonAttempt(assessment: nil, disposition: .cancelled)
    }
    if ownerID == .humanGuidedDiscovery(.returnAndObserveExistingTarget),
      visibilityTargetSceneDisposition == .inkPossible,
      activeExerciseAttemptMode == .normal
    {
      finishActiveExerciseAttempt(disposition: .cancelled)
      beginExerciseAttempt(ownerID: ownerID, mode: .normal)
      pendingClearViewLabel = nil
      return
    }
    pendingClearViewLabel = nil
    finishActiveExerciseAttempt(disposition: .cancelled)
    let recoveryOnlyTarget =
      ownerID.stage == .humanGuidedDiscovery
      && visibilityTargetSceneDisposition == .targetUnusable
    restartableExerciseItemID = boundaryRepeatWithFallback || recoveryOnlyTarget ? nil : ownerID
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
    if activeExerciseAttemptOwnerID
      == .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry)
    {
      if disposition != .succeeded, let snapshot = visibilityRepeatSnapshot {
        let attemptedAreaIdentity = targetAreaIdentity
        let attemptedSceneDisposition = visibilityTargetSceneDisposition
        recordUnsuccessfulVisibilityRepeat(
          disposition: disposition,
          acceptedSnapshot: snapshot,
          attemptedTargetAreaIdentity: attemptedAreaIdentity
        )
        restoreVisibilityRegistrationPayload(snapshot)
        if attemptedAreaIdentity != snapshot.targetAreaIdentity,
          attemptedSceneDisposition != .pristine
        {
          retiredTargetAreaDispositions[attemptedAreaIdentity] = attemptedSceneDisposition
        }
      }
      visibilityRepeatSnapshot = nil
      visibilityDraftArtifactGraph = nil
      visibilityDraftClearViewAttemptHistories = nil
      visibilityDraftAcceptedAttemptSequence = nil
    }
    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
  }

  private func recordUnsuccessfulVisibilityRepeat(
    disposition: ExerciseAttemptDisposition,
    acceptedSnapshot: VisibilityRegistrationPayloadSnapshot,
    attemptedTargetAreaIdentity: UUID
  ) {
    guard let attemptID = activeExerciseAttemptID,
      let acceptedObservation = acceptedSnapshot.visibilityTargetObservation
    else { return }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: acceptedObservation.baseline.cameraConfigurationID,
      coordinateSpace: .cameraPixels,
      units: .pixels,
      group: AttemptGroupIdentity(
        rawValue: "visibility-target-\(attemptedTargetAreaIdentity.uuidString.lowercased())"
      ),
      algorithmRevision: acceptedObservation.algorithmRevision
    )
    do {
      var histories = visibilityObservationAttemptHistories
      let sequence = acceptedAttemptSequence &+ 1
      try recordAttempt(
        ExerciseAttempt(
          id: attemptID,
          disposition: disposition,
          compatibility: compatibility,
          acceptedSequence: sequence,
          value: nil
        ),
        in: &histories,
        replacingAttemptID: activeExerciseAttemptMode == .replacement
          ? acceptedVisibilityObservationAttemptID : nil
      )
      visibilityObservationAttemptHistories = histories
      acceptedAttemptSequence = sequence
    } catch {
      explorationError = "Visibility repeat provenance could not be recorded: \(error)"
    }
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

  private func recordClearViewAttempt(
    label: ArmatureVisibilityLabel?,
    disposition: ExerciseAttemptDisposition
  ) {
    guard let attemptID = activeExerciseAttemptID else { return }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: lastArmatureObservation?.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: AttemptGroupIdentity(rawValue: "clear-view"),
      algorithmRevision: "armature-guidance-v1"
    )
    do {
      var histories = clearViewAttemptHistories
      let sequence = acceptedAttemptSequence &+ 1
      let replacingAttemptID = learningArtifactGraph.currentRevision(for: .clearPose)?.attemptID
      try recordAttempt(
        ExerciseAttempt(
          id: attemptID,
          disposition: disposition,
          compatibility: compatibility,
          acceptedSequence: sequence,
          value: label
        ),
        in: &histories,
        replacingAttemptID: replacingAttemptID
      )
      clearViewAttemptHistories = histories
      acceptedAttemptSequence = sequence
    } catch {
      explorationError = "Clear-View attempt provenance could not be recorded: \(error)"
    }
  }

  private func commitClearViewAttemptAndArtifact(
    guidance: ArmatureGuidanceState
  ) throws {
    guard let attemptID = activeExerciseAttemptID else {
      throw LearningPathOperationError.requiredState("No active typed exercise attempt.")
    }
    let compatibility = AttemptCompatibility(
      cameraConfigurationID: lastArmatureObservation?.cameraConfigurationID,
      coordinateSpace: .categorical,
      units: .categorical,
      group: AttemptGroupIdentity(rawValue: "clear-view"),
      algorithmRevision: "armature-guidance-v1"
    )
    var histories = visibilityDraftClearViewAttemptHistories ?? clearViewAttemptHistories
    let sequence = (visibilityDraftAcceptedAttemptSequence ?? acceptedAttemptSequence) &+ 1
    let sourceGraph = visibilityDraftArtifactGraph ?? learningArtifactGraph
    let replacingAttemptID =
      activeExerciseAttemptMode == .replacement
      ? visibilityRepeatSnapshot?.learningArtifactGraph.currentRevision(for: .clearPose)?.attemptID
      : sourceGraph.currentRevision(for: .clearPose)?.attemptID
    try recordAttempt(
      ExerciseAttempt(
        id: attemptID,
        disposition: .succeeded,
        compatibility: compatibility,
        acceptedSequence: sequence,
        value: .clear
      ),
      in: &histories,
      replacingAttemptID: replacingAttemptID
    )
    var graph = sourceGraph
    guard let targetROI = graph.currentRevision(for: .targetROIRegistration)?.id else {
      throw LearningPathOperationError.requiredState(
        "Accepted target search-circle registration is required before accepting Clear."
      )
    }
    let commit = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: .clearPose,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [targetROI]
      )
    )

    if visibilityDraftArtifactGraph != nil {
      visibilityDraftArtifactGraph = graph
      visibilityDraftClearViewAttemptHistories = histories
      visibilityDraftAcceptedAttemptSequence = sequence
    } else {
      clearViewAttemptHistories = histories
      acceptedAttemptSequence = sequence
      learningArtifactGraph = graph
      applyArtifactInvalidations(commit.invalidatedRevisionIDs)
    }
    armatureGuidanceState = guidance
    clearViewPoseAccepted = true
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
      dependencies = [
        try required(.visibilityRegistration),
        try required(.machineCameraRegistration),
      ]
    case .captureTargetAnchoredBaseline:
      kind = .targetAnchoredTrialBaseline(group)
      dependencies = [try required(.visibilityRegistration), try required(.clearPose)]
    case .moveToLineStart:
      return
    case .drawIsolatedLine:
      kind = .lineExecution(group)
      dependencies = [try required(.linePlan(group))]
    case .returnToClearPoseAndObserveNewInk:
      kind = .postLineFrame(group)
      dependencies = [
        try required(.lineExecution(group)),
        try required(.targetAnchoredTrialBaseline(group)),
        try required(.clearPose),
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

    if step == .returnToClearPoseAndObserveNewInk {
      let baseline = try required(.targetAnchoredTrialBaseline(group))
      let line = try required(.lineExecution(group))
      let post = try required(.postLineFrame(group))
      let ink = try graph.commitReplacement(
        LearningArtifactRevision(
          kind: .inkObservation(group),
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [baseline, line, post]
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
      targetAnchoredBaseline: targetAnchoredTrialBaseline,
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
    targetAnchoredTrialBaseline = snapshot.targetAnchoredBaseline
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
    case .chooseIsolatedLinePlan: advanceDrawingTrial(to: .captureTargetAnchoredBaseline)
    case .captureTargetAnchoredBaseline: advanceDrawingTrial(to: .moveToLineStart)
    case .moveToLineStart: advanceDrawingTrial(to: .drawIsolatedLine)
    case .drawIsolatedLine: advanceDrawingTrial(to: .returnToClearPoseAndObserveNewInk)
    case .returnToClearPoseAndObserveNewInk:
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
      case .targetPoseRegistration:
        targetPoseRegistrationFrame = nil
        registeredTargetMachinePosition = nil
        targetCapAnchorEstimate = nil
      case .targetROIRegistration:
        targetSearchCircle = nil
        targetCapAnchorAndSearchCircleAccepted = false
      case .clearPose:
        clearViewPoseAccepted = false
      case .preTargetClearViewBaseline:
        preTargetClearViewBaseline = nil
        registeredTargetReturnSettlement = nil
      case .visibilityTargetExecution:
        visibilityTargetObservation = nil
        penTipOffsetRegistration = nil
        visibilityRegistrationAccepted = false
      case .visibilityTargetObservation:
        visibilityTargetObservation = nil
        penTipOffsetRegistration = nil
        visibilityRegistrationAccepted = false
      case .penTipOffsetRegistration:
        penTipOffsetRegistration = nil
        visibilityRegistrationAccepted = false
      case .visibilityRegistration:
        visibilityRegistrationAccepted = false
      case .machineCameraRegistration:
        machineCameraRegistration = nil
      case .targetAnchoredTrialBaseline:
        targetAnchoredTrialBaseline = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .captureTargetAnchoredBaseline)
      case .linePlan:
        drawingTrialLineStart = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .chooseIsolatedLinePlan)
      case .lineExecution:
        drawingTrialStrokeEvidence = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .drawIsolatedLine)
      case .postLineFrame:
        explorationPostLineFrame = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .returnToClearPoseAndObserveNewInk)
      case .inkObservation, .residual:
        lastInkObservation = nil
        drawingTrialAssessment = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .returnToClearPoseAndObserveNewInk)
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

  private func attemptDisposition(for reason: String) -> ExerciseAttemptDisposition {
    let lowered = reason.lowercased()
    if lowered.contains("unclear") { return .unclear(reason) }
    if lowered.contains("ambiguous") || lowered.contains("unknown post-write") {
      return .ambiguous(reason)
    }
    if lowered.contains("refus") || lowered.contains("alarm") || lowered.contains("limit")
      || lowered.contains("disconnect")
    {
      return .refused(reason)
    }
    return .failed(reason)
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
    case .registerTargetPoseAndCameraGeometry, .discoverAndAcceptClearView,
      .confirmBlankTargetBaseline, .returnToRegisteredTargetPose, .drawVisibilityTarget,
      .returnAndObserveExistingTarget, .acceptVisibilityRegistration:
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
      && centerArrivalPosition != nil && visibilityRegistrationAccepted
    return switch itemID {
    case .stage(.connect): controllerSessionEstablished
    case .stage(.enableMotion): controllerSessionEstablished && motionAuthorizationEnabled
    case .stage(.humanGuidedDiscovery): discoveryComplete
    case .stage(.observedDrawingTrials): drawingTrialAssessment != nil
    case .stage(.adaptiveDrawing): false
    case .humanGuidedDiscovery(.penInteraction): penInteractionCompleted
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      centerArrivalPosition != nil
    case .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry):
      targetCapAnchorAndSearchCircleAccepted
    case .humanGuidedDiscovery(.discoverAndAcceptClearView): clearViewPoseAccepted
    case .humanGuidedDiscovery(.confirmBlankTargetBaseline):
      preTargetClearViewBaseline != nil
    case .humanGuidedDiscovery(.returnToRegisteredTargetPose):
      visibilityTargetSceneDisposition == .pristine
        ? registeredTargetReturnIsCurrent
        : registeredTargetReturnSettlement != nil
    case .humanGuidedDiscovery(.drawVisibilityTarget):
      visibilityTargetSceneDisposition != .pristine
    case .humanGuidedDiscovery(.returnAndObserveExistingTarget):
      visibilityTargetObservation != nil
        && visibilityTargetSceneDisposition == .targetObserved
        && (visibilityRegistrationAccepted
          ? acceptedClearReturnSettlement != nil : acceptedClearReturnIsCurrent)
    case .humanGuidedDiscovery(.acceptVisibilityRegistration):
      visibilityRegistrationAccepted
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
      .humanGuidedDiscovery(.returnAndObserveExistingTarget),
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
      "Observe Pen Interaction, four paired boundaries, center arrival, and visibility-target registration."
    case .humanGuidedDiscovery(.penInteraction):
      "Observe the physical pen UP, DOWN, then UP again."
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      "Observe both X sides and both Y sides in paired order, then move Pen Up to their estimated center."
    case .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry):
      "Capture the exact target pose, build a current-camera cap fit and search-circle proposal, inspect it at adjustable presentation zoom, then explicitly accept or reject it."
    case .humanGuidedDiscovery(.discoverAndAcceptClearView):
      "Move Pen Up in bounded increments, label exact Clear/Partial/Blocked frames, then explicitly accept one agreed Clear pose."
    case .humanGuidedDiscovery(.confirmBlankTargetBaseline):
      "Capture one exact frame at the accepted Clear pose and explicitly confirm that the circular target search region is blank."
    case .humanGuidedDiscovery(.returnToRegisteredTargetPose):
      "Return Pen Up to the registered target MPos and retain the exact Idle settlement."
    case .humanGuidedDiscovery(.drawVisibilityTarget):
      "Execute the immutable V2 double-trace visibility target once. Possible ink advances to observation; it is never redrawn automatically."
    case .humanGuidedDiscovery(.returnAndObserveExistingTarget):
      "Return Pen Up to accepted Clear, then run one foreground two-frame observation of the existing target in the accepted search circle."
    case .humanGuidedDiscovery(.acceptVisibilityRegistration):
      "Review the exact frames, geometry, uncertainty, and provenance, then explicitly accept the visibility registration."
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
    if let operation = visibilityObservationOperation {
      let ownerID = LearningPathItemID.humanGuidedDiscovery(
        .returnAndObserveExistingTarget
      )
      guard itemID == ownerID else { return nil }
      return ExerciseActionStripPresentation(
        ownerID: ownerID,
        actions: [
          ExerciseActionDescriptor(
            kind: .cancelVisibilityObservation(operation.cancelCapabilityID),
            title: "Cancel Vision",
            role: .destructive
          )
        ],
        mustRemainVisible: true
      )
    }
    if activeExerciseAttemptOwnerID == itemID {
      var actions: [ExerciseActionDescriptor] = []
      var directionSelection: ExerciseDirectionSelectionPresentation?
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
            kind: .drawVisibilityTarget,
            title: "Machine action unavailable",
            unavailableReason: ambiguityReason
          )
        ]
      } else if case .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry) = itemID {
        let currentPosition = try? currentMachinePosition()
        if visibilityTargetSceneDisposition == .targetUnusable {
          actions = [
            ExerciseActionDescriptor(
              kind: .registerNewTargetArea, title: "Register New Target Area"),
            ExerciseActionDescriptor(kind: .paperReplaced, title: "Paper Replaced"),
          ]
        } else if targetAreaRelocationRequired && !targetAreaRelocationCompleted {
          directionSelection = ExerciseDirectionSelectionPresentation(
            purpose: .targetAreaRelocation,
            selected: selectedClearViewDirection
          )
          actions = ClearViewSearchDistance.allCases.map { distance in
            let move = ClearViewSearchMove(
              direction: selectedClearViewDirection, distance: distance)
            return ExerciseActionDescriptor(
              kind: .moveToNewTargetArea(move),
              title: "Move New Target Area \(move.direction.displayName) \(distance.displayName)"
            )
          }
        } else if targetPoseRegistrationFrame == nil {
          actions = [
            ExerciseActionDescriptor(
              kind: .captureTargetPoseAndBuildGeometryProposal,
              title: "Capture Target Pose and Build Geometry Proposal",
              role: .positive
            )
          ]
        } else if proposedTargetSearchCircle == nil {
          let isAtTarget = currentPosition.map { current in
            registeredTargetMachinePosition.map { protocolPositionsMatch(current, $0) } ?? false
          }
          if currentCameraCalibrationPhase != nil {
            actions = [
              ExerciseActionDescriptor(
                kind: .captureTargetPoseAndBuildGeometryProposal,
                title: "Building Geometry Proposal…",
                unavailableReason: "Current-camera calibration is in progress."
              )
            ]
          } else if isAtTarget == false {
            actions = [
              ExerciseActionDescriptor(
                kind: .returnToRegisteredTargetPose,
                title: "Return to Captured Target Pose"
              )
            ]
          } else {
            let compatibleCount =
              targetPoseRegistrationFrame.map {
                compatibleRegistrationCapAnchorEvidence(for: $0).count
              } ?? 0
            actions = [
              ExerciseActionDescriptor(
                kind: .captureTargetPoseAndBuildGeometryProposal,
                title: compatibleCount >= 3
                  ? "Build Geometry Proposal from Existing Samples"
                  : "Retry Bounded Calibration and Build Proposal",
                role: .positive,
                unavailableReason: currentCameraCalibrationFailure?.recovery
                  == .revalidateControllerContext
                  ? currentCameraCalibrationFailure?.recoveryDescription
                  : (isAtTarget == nil ? "Current Controller MPos is unavailable." : nil)
              ),
              ExerciseActionDescriptor(
                kind: .rejectTargetGeometryProposal,
                title: "Reject Captured Target",
                role: .destructive
              ),
            ]
          }
        } else {
          actions = [
            ExerciseActionDescriptor(
              kind: .acceptTargetGeometryProposal,
              title: "Accept Target Pose, Cap Fit, and Search Circle",
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectTargetGeometryProposal,
              title: "Reject Geometry Proposal",
              role: .destructive
            ),
          ]
        }
      } else if case .humanGuidedDiscovery(.discoverAndAcceptClearView) = itemID {
        directionSelection = ExerciseDirectionSelectionPresentation(
          purpose: .clearViewSearch, selected: selectedClearViewDirection)
        actions = ClearViewSearchDistance.allCases.map { distance in
          let move = ClearViewSearchMove(
            direction: selectedClearViewDirection, distance: distance)
          return ExerciseActionDescriptor(
            kind: .moveForClearView(move),
            title: "Move for Clear View \(move.direction.displayName) \(distance.displayName)"
          )
        }
        actions.append(
          contentsOf: ArmatureVisibilityLabel.allCases.map { label in
            return ExerciseActionDescriptor(
              kind: .recordClearViewLabel(label),
              title: ClearPoseAcceptancePolicy.labelTitle(
                label,
                pendingLabel: pendingClearViewLabel,
                observation: lastArmatureObservation
              )
            )
          })
        actions.append(
          ExerciseActionDescriptor(
            kind: .acceptClearPose,
            title: "Accept Clear Pose",
            role: .positive,
            unavailableReason: ClearPoseAcceptancePolicy.admits(
              pendingLabel: pendingClearViewLabel,
              observation: lastArmatureObservation
            )
              ? nil : "Record a Clear exact-frame observation first."
          )
        )
      } else if case .humanGuidedDiscovery(.confirmBlankTargetBaseline) = itemID {
        if visibilityTargetSceneDisposition == .targetUnusable {
          actions = [
            ExerciseActionDescriptor(
              kind: .registerNewTargetArea, title: "Register New Target Area"),
            ExerciseActionDescriptor(kind: .paperReplaced, title: "Paper Replaced"),
          ]
        } else if blankTargetBaselineCandidate == nil {
          actions = [
            ExerciseActionDescriptor(
              kind: .captureBlankTargetBaselineCandidate,
              title: "Capture Blank-Baseline Candidate"
            )
          ]
        } else {
          actions = [
            ExerciseActionDescriptor(
              kind: .confirmBlankTargetBaseline,
              title: "Confirm Search Circle Is Blank",
              role: .positive
            ),
            ExerciseActionDescriptor(
              kind: .rejectBlankTargetBaseline,
              title: "Not Blank",
              role: .destructive
            ),
          ]
        }
      } else if case .humanGuidedDiscovery(.returnToRegisteredTargetPose) = itemID {
        actions = [
          ExerciseActionDescriptor(
            kind: .returnToRegisteredTargetPose,
            title: "Return Pen Up to Registered Target Pose",
            role: .positive
          )
        ]
      } else if case .humanGuidedDiscovery(.drawVisibilityTarget) = itemID {
        actions = [
          ExerciseActionDescriptor(
            kind: .drawVisibilityTarget,
            title: "Draw Visibility Target Once",
            role: .positive,
            unavailableReason: registeredTargetReturnIsCurrent
              ? nil
              : "Return Pen Up to the registered target and retain its current Idle settlement."
          )
        ]
      } else if case .humanGuidedDiscovery(.returnAndObserveExistingTarget) = itemID {
        if visibilityTargetSceneDisposition == .targetUnusable {
          actions = [
            ExerciseActionDescriptor(
              kind: .registerNewTargetArea, title: "Register New Target Area"),
            ExerciseActionDescriptor(kind: .paperReplaced, title: "Paper Replaced"),
          ]
        } else {
          actions = [
            acceptedClearReturnIsCurrent
              ? ExerciseActionDescriptor(
                kind: .observeExistingVisibilityTarget,
                title: "Observe Existing Target",
                role: .positive
              )
              : ExerciseActionDescriptor(
                kind: .returnToAcceptedClearPose,
                title: "Return Pen Up to Accepted Clear Pose"
              )
          ]
        }
      } else if case .humanGuidedDiscovery(.acceptVisibilityRegistration) = itemID {
        actions = [
          ExerciseActionDescriptor(
            kind: .acceptVisibilityRegistration,
            title: "Accept Visibility Registration",
            role: .positive,
            unavailableReason: acceptedClearReturnIsCurrent
              ? nil : "Return Pen Up to the accepted Clear pose before accepting registration."
          ),
          ExerciseActionDescriptor(
            kind: .rejectVisibilityRegistration,
            title: "Reject Registration Evidence",
            role: .destructive
          ),
        ]
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
        directionSelection: directionSelection,
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
      let usedTargetRecoveryRows: Set<LearningPathItemID> = [
        .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry),
        .humanGuidedDiscovery(.discoverAndAcceptClearView),
        .humanGuidedDiscovery(.confirmBlankTargetBaseline),
        .humanGuidedDiscovery(.returnToRegisteredTargetPose),
      ]
      if visibilityTargetSceneDisposition != .pristine,
        usedTargetRecoveryRows.contains(itemID)
      {
        actions = [
          ExerciseActionDescriptor(
            kind: .registerNewTargetArea, title: "Register New Target Area"),
          ExerciseActionDescriptor(kind: .paperReplaced, title: "Paper Replaced"),
        ]
      } else if itemID == .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering) {
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
      } else if itemID == .humanGuidedDiscovery(.drawVisibilityTarget)
        || itemID == .humanGuidedDiscovery(.acceptVisibilityRegistration)
      {
        return nil
      } else if itemID == .humanGuidedDiscovery(.returnAndObserveExistingTarget) {
        actions = [
          ExerciseActionDescriptor(
            kind: .recordAnotherAttempt,
            title: "Record Another Observation"
          )
        ]
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
    case .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry):
      reason =
        frameMode == .simulated || cameraIsLive
        ? nil : "A current LIVE camera frame is required."
    case .humanGuidedDiscovery(.discoverAndAcceptClearView),
      .humanGuidedDiscovery(.confirmBlankTargetBaseline),
      .humanGuidedDiscovery(.returnAndObserveExistingTarget):
      reason =
        frameMode == .simulated || cameraIsLive
        ? nil : "A current LIVE camera frame is required."
    case .humanGuidedDiscovery(.returnToRegisteredTargetPose),
      .humanGuidedDiscovery(.drawVisibilityTarget),
      .humanGuidedDiscovery(.acceptVisibilityRegistration):
      reason = nil
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
        case .captureTargetAnchoredBaseline: .captureTargetAnchoredBaseline
        case .moveToLineStart: .moveToLineStart
        case .drawIsolatedLine: .drawIsolatedLine
        case .returnToClearPoseAndObserveNewInk: .returnToClearPoseAndObserveNewInk
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
    if itemID == .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry) {
      if visibilityTargetSceneDisposition == .targetUnusable {
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: [
            ExerciseActionDescriptor(
              kind: .registerNewTargetArea,
              title: "Register New Target Area"
            ),
            ExerciseActionDescriptor(kind: .paperReplaced, title: "Paper Replaced"),
          ]
        )
      }
      if targetAreaRelocationRequired && !targetAreaRelocationCompleted {
        let directionSelection = ExerciseDirectionSelectionPresentation(
          purpose: .targetAreaRelocation,
          selected: selectedClearViewDirection
        )
        let actions = ClearViewSearchDistance.allCases.map { distance in
          let move = ClearViewSearchMove(
            direction: selectedClearViewDirection,
            distance: distance
          )
          return ExerciseActionDescriptor(
            kind: .moveToNewTargetArea(move),
            title: "Move New Target Area \(move.direction.displayName) \(distance.displayName)"
          )
        }
        return ExerciseActionStripPresentation(
          ownerID: itemID,
          actions: actions,
          directionSelection: directionSelection
        )
      }
      return ExerciseActionStripPresentation(
        ownerID: itemID,
        actions: [
          ExerciseActionDescriptor(
            kind: .captureTargetPoseAndBuildGeometryProposal,
            title: "Capture Target Pose and Build Geometry Proposal",
            role: .positive,
            unavailableReason: reason
          )
        ]
      )
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
    case .humanGuidedDiscovery: [.cue(.up), .text("boundary evidence, and a Clear view.")]
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
    case .registerTargetPoseAndCameraGeometry:
      [
        .text(
          "Capture one exact target frame, build a cap-fit/search-circle proposal, inspect the outlined circle with presentation zoom, then explicitly accept or reject it."
        )
      ]
    case .discoverAndAcceptClearView:
      [
        .text(
          "Move Pen Up in bounded increments, label each exact frame, and accept only an agreed Clear pose."
        )
      ]
    case .confirmBlankTargetBaseline:
      [.text("Capture at accepted Clear and answer whether the exact circular target search region is blank.")]
    case .returnToRegisteredTargetPose:
      [.text("Return Pen Up to the accepted target MPos and wait for exact Idle settlement.")]
    case .drawVisibilityTarget:
      [.text("Execute the immutable visibility target once. Never redraw after ink may exist.")]
    case .returnAndObserveExistingTarget:
      [
        .text(
          "Return Pen Up to Clear, then observe the existing target from two strictly newer frames."
        )
      ]
    case .acceptVisibilityRegistration:
      [
        .text(
          "Review exact frames, geometry, uncertainty, plan, and provenance; then accept or reject."
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
    case .registerTargetPoseAndCameraGeometry:
      [.text("Current target-pose, machine-camera, and target-search revisions.")]
    case .discoverAndAcceptClearView:
      [.text("One accepted Clear pose with exact frame, MPos, label, and search-circle context.")]
    case .confirmBlankTargetBaseline:
      [.text("One explicitly confirmed blank exact-frame baseline.")]
    case .returnToRegisteredTargetPose:
      [.text("Pen Up, Idle, and exact final MPos at the registered target.")]
    case .drawVisibilityTarget:
      [.text("One attributable execution or retained possible-ink outcome; no redraw.")]
    case .returnAndObserveExistingTarget:
      [.text("Pen Up at Clear and one two-frame current observation of existing ink.")]
    case .acceptVisibilityRegistration:
      [.text("One current accepted visibility-registration revision.")]
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
    case .registerTargetPoseAndCameraGeometry:
      let searchCircle = proposedTargetSearchCircle ?? targetSearchCircle
      let registration = proposedMachineCameraRegistration ?? machineCameraRegistration
      return [
        ExerciseEvidencePresentation(
          label: "Exact target-pose capture",
          fragments: [
            .text(
              targetPoseRegistrationFrame.map {
                let mpos =
                  registeredTargetMachinePosition.map {
                    String(format: " · MPos X %.3f Y %.3f", $0.point.x, $0.point.y)
                  } ?? ""
                return
                  "frame \($0.frame.id.rawValue) · SHA \($0.frame.contentSHA256) · config \($0.frame.cameraConfigurationID.rawValue.uuidString.lowercased())\(mpos)"
              } ?? "not captured")
          ]
        ),
        ExerciseEvidencePresentation(
          label: targetGeometryProposalID == nil
            ? "Accepted cap anchor, fit, and search circle"
            : "Staged cap anchor, fit, and search-circle proposal",
          fragments: [
            .text(
              targetCapAnchorEstimate.map {
                String(
                  format:
                    "cap anchor %.1f, %.1f · %@ · fit residual %@ · %@",
                  $0.point.x,
                  $0.point.y,
                  searchCircle.map(String.init(describing:)) ?? "search circle not available",
                  registration.map { String(format: "%.3f px", $0.validationResidualPixels) }
                    ?? "not fitted",
                  targetCapAnchorAndSearchCircleAccepted ? "accepted" : "not authoritative"
                )
              } ?? "not measured")
          ]
        ),
      ]
    case .discoverAndAcceptClearView:
      return [
        ExerciseEvidencePresentation(
          label: "Target search-circle input",
          fragments: [
            .text(
              targetSearchCircle.map {
                "\($0) · revision \(learningArtifactGraph.currentRevision(for: .targetROIRegistration)?.id.rawValue.uuidString.lowercased() ?? "not current")"
              } ?? "not accepted")
          ]
        ),
        ExerciseEvidencePresentation(
          label: "Clear-pose decision",
          fragments: [
            .text(
              armatureGuidanceState?.acceptedClearPose.map {
                String(
                  format: "X %.3f Y %.3f · observation %@ · accepted", $0.position.point.x,
                  $0.position.point.y, $0.sourceObservationID.rawValue.uuidString.lowercased())
              } ?? lastArmatureObservation.map {
                String(
                  format: "candidate X %.3f Y %.3f · label %@ · frame %@ · agreed %@",
                  $0.controllerPosition.point.x, $0.controllerPosition.point.y,
                  $0.humanLabel.rawValue, $0.frameID.rawValue,
                  $0.estimateAgreedWithHuman ? "yes" : "no")
              } ?? "no labelled observation")
          ]
        ),
      ]
    case .confirmBlankTargetBaseline:
      return [
        ExerciseEvidencePresentation(
          label: "Blank-baseline candidate",
          fragments: [
            .text(
              blankTargetBaselineCandidate.map {
                "frame \($0.frame.id.rawValue) · SHA \($0.frame.contentSHA256) · awaiting explicit Blank / Not Blank decision"
              } ?? "no candidate")
          ]
        ),
        ExerciseEvidencePresentation(
          label: "Accepted blank baseline",
          fragments: [
            .text(
              preTargetClearViewBaseline.map {
                "frame \($0.frame.id.rawValue) · SHA \($0.frame.contentSHA256) · revision \(learningArtifactGraph.currentRevision(for: .preTargetClearViewBaseline)?.id.rawValue.uuidString.lowercased() ?? "not current")"
              } ?? "not accepted")
          ]
        ),
      ]
    case .returnToRegisteredTargetPose:
      return [
        ExerciseEvidencePresentation(
          label: "Registered-target settlement",
          fragments: [
            .text(
              registeredTargetReturnSettlement.map {
                String(
                  format:
                    "target X %.3f Y %.3f · final X %.3f Y %.3f · residual %.3f / %.3f mm · %@",
                  $0.target.point.x, $0.target.point.y, $0.actual.point.x, $0.actual.point.y,
                  $0.residualMM, $0.toleranceMM,
                  registeredTargetReturnIsCurrent ? "current Pen Up + Idle" : "historical only")
              } ?? "not settled")
          ]
        )
      ]
    case .drawVisibilityTarget:
      return [
        ExerciseEvidencePresentation(
          label: "Accepted drawing inputs",
          fragments: [
            .text(
              "baseline \(preTargetClearViewBaseline?.frame.id.rawValue ?? "not accepted") · search \(targetSearchCircle.map(String.init(describing:)) ?? "not accepted")"
            )
          ]
        ),
        ExerciseEvidencePresentation(
          label: "One-shot target execution",
          fragments: [
            .text(
              visibilityTargetExecutionAttemptEvidence.map {
                "scene \($0.sceneDisposition.rawValue) · operation \(String(describing: $0.disposition)) · plan \($0.planRevision) · completed steps \($0.completedTraversalStepCount)/\(VisibilityTargetPlanV2().drawingStepCount) · revision \(learningArtifactGraph.currentRevision(for: .visibilityTargetExecution)?.id.rawValue.uuidString.lowercased() ?? "not current") · redraw unavailable after possible ink"
              }
                ?? "scene \(visibilityTargetSceneDisposition.rawValue) · plan not executed · no execution-attempt evidence"
            )
          ]
        ),
      ]
    case .returnAndObserveExistingTarget:
      var evidence = [
        ExerciseEvidencePresentation(
          label: "Accepted-Clear return settlement",
          fragments: [
            .text(
              acceptedClearReturnSettlement.map {
                String(
                  format:
                    "target X %.3f Y %.3f · final X %.3f Y %.3f · residual %.3f / %.3f mm · %@",
                  $0.target.point.x, $0.target.point.y, $0.actual.point.x, $0.actual.point.y,
                  $0.residualMM, $0.toleranceMM,
                  acceptedClearReturnIsCurrent ? "current Pen Up + Idle" : "historical only")
              } ?? "not settled")
          ]
        )
      ]
      if let observation = visibilityTargetObservation {
        evidence.append(
          ExerciseEvidencePresentation(
            label: "Existing-target observation",
            fragments: [
              .text(
                "frames \(observation.includedFrameIDs.map(\.rawValue).joined(separator: ", ")) · N=\(observation.validSampleCount) · centroid \(observation.centroid.x), \(observation.centroid.y) · uncertainty X \(observation.centroidUncertainty.dx) Y \(observation.centroidUncertainty.dy) · revision \(learningArtifactGraph.currentRevision(for: .visibilityTargetObservation)?.id.rawValue.uuidString.lowercased() ?? "not current")"
              )
            ]
          ))
      }
      return evidence
    case .acceptVisibilityRegistration:
      var evidence: [ExerciseEvidencePresentation] = []
      let tipOffsetCandidate = penTipOffsetRegistration ?? visibilityTargetObservation.flatMap {
        observation in
        guard let capAnchor = targetCapAnchorEstimate,
          let anchorFrame = targetPoseRegistrationFrame
        else { return nil }
        return try? PenTipOffsetRegistration(
          capAnchor: capAnchor,
          anchorFrame: anchorFrame,
          observation: observation,
          estimatorRevision: "cap-anchor-to-visibility-centroid-v1"
        )
      }
      if let observation = visibilityTargetObservation {
        evidence.append(
          ExerciseEvidencePresentation(
            label: "Registration candidate",
            fragments: [
              .text(
                "frames \(observation.includedFrameIDs.map(\.rawValue).joined(separator: ", ")) · plan \(observation.targetPlanRevision) · execution \(visibilityTargetExecutionAttemptEvidence.map { String(describing: $0.disposition) } ?? "unavailable") · \(observation.estimatorRevision) · area ratio \(observation.areaRatio)"
              )
            ]
          ))
      }
      if let acceptedVisibilityObservationAttemptID,
        let history = visibilityObservationAttemptHistories.values.first(where: { history in
          history.records.contains { $0.attempt.id == acceptedVisibilityObservationAttemptID }
        }),
        let aggregate = try? VisibilityTargetAttemptAggregate(history: history)
      {
        evidence.append(
          ExerciseEvidencePresentation(
            label: "Target attempt aggregate",
            fragments: [
              .text(
                "attempt N=\(aggregate.validAttemptCount) · frames=\(aggregate.includedObservations.flatMap(\.includedFrameIDs).count) · estimator \(aggregate.estimator.name) \(aggregate.estimator.revision) · included \(aggregate.includedAttemptIDs.map { $0.rawValue.uuidString.lowercased() }.joined(separator: ", ")) · uncertainty \(String(describing: aggregate.uncertainty))"
              )
            ]
          ))
      }
      evidence.append(
        ExerciseEvidencePresentation(
          label: "Cap-to-tip registration",
          fragments: [
            .text(
              tipOffsetCandidate.map {
                String(
                  format:
                    "cap %.1f, %.1f · observed tip %.1f, %.1f · offset X %+.1f Y %+.1f px · anchor frame %@ · %@",
                  $0.capAnchor.x,
                  $0.capAnchor.y,
                  $0.observedTip.x,
                  $0.observedTip.y,
                  $0.capToTipOffset.dx,
                  $0.capToTipOffset.dy,
                  $0.capAnchorFrame.frameID.rawValue,
                  $0.estimatorRevision
                )
              } ?? "not available"
            )
          ]
        ))
      evidence.append(
        ExerciseEvidencePresentation(
          label: "Visibility-registration authority",
          fragments: [
            .text(
              "\(visibilityRegistrationAccepted ? "accepted" : "not accepted") · revision \(learningArtifactGraph.currentRevision(for: .visibilityRegistration)?.id.rawValue.uuidString.lowercased() ?? "not current")"
            )
          ]
        ))
      return evidence
    }
  }

  private func operationActivityPresentation(
    for itemID: LearningPathItemID,
    transaction: DiscoveryTransaction?
  ) -> OperationActivityPresentation? {
    if itemID == .humanGuidedDiscovery(.returnAndObserveExistingTarget),
      let operation = visibilityObservationOperation
    {
      return OperationActivityPresentation(
        actor: "Camera and Vision",
        action: "Observe Existing Target",
        phase: operation.phase.rawValue,
        outcome: .inProgress,
        detail: [
          .text(
            "Vision is masked to the cap-anchored circle with radius \(Int(operation.searchCircle.radiusPixels.rounded())) px (bounded by \(operation.searchCircle.boundingROI.width)x\(operation.searchCircle.boundingROI.height) px). Plan \(operation.targetPlanRevision)."
          )
        ],
        recovery: [.text("Cancel Vision remains available; no other operation is admitted.")]
      )
    }
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
    if itemID == .humanGuidedDiscovery(.registerTargetPoseAndCameraGeometry),
      let currentCameraCalibrationPhase
    {
      return OperationActivityPresentation(
        actor: activeStopTarget == nil ? "Camera and learning runtime" : "Plotter controller",
        action: "Build Target Geometry Proposal",
        phase: currentCameraCalibrationPhase,
        outcome: .inProgress,
        detail: [
          .text(
            "The app owns three exact non-collinear cap-anchor samples and returns to the registered target pose. The later visibility target is still a separate machine-drawn action."
          )
        ],
        recovery: activeStopTarget == nil
          ? [.text("No operator calibration move or hand-drawn triangle is required.")]
          : [.text("Stop remains bound to the currently admitted Pen-Up move.")]
      )
    }
    if itemID.stage == .humanGuidedDiscovery, let explorationError {
      return OperationActivityPresentation(
        actor: visibilityActivityActor,
        action: visibilityActivityAction,
        outcome: .needsAttention,
        detail: [.text(explorationError)],
        recovery: visibilityActivityRecovery
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
        observedDrawingTrialStep == .returnToClearPoseAndObserveNewInk
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
      if visibilityObservationOperation != nil || currentCameraCalibrationPhase != nil
        || activeStopTarget != nil
      {
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
    } else if visibilityObservationOperation != nil || currentCameraCalibrationPhase != nil {
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
    if let operation = visibilityObservationOperation {
      visionState = operation.phase.rawValue
      visionBlocksMotion = true
      visionRole = .operationOwner
      visionDetail =
        "Foreground circular target observation owns a still-scene evidence transaction. It blocks new motion until it settles or Cancel Vision is used."
    } else if let currentCameraCalibrationPhase {
      visionState = currentCameraCalibrationPhase
      visionBlocksMotion = true
      visionRole = .operationOwner
      visionDetail =
        "Current-camera calibration owns a multi-step optical-registration operation. New manual motion is blocked until it settles; any currently admitted move is also shown under Motion owner."
    } else if sceneInspectionInProgress {
      visionState = "Inspecting one frame"
      visionBlocksMotion = false
      visionRole = .advisoryEvidence
      visionDetail = "One camera frame is being processed for overlays and diagnostics."
    } else if scopedVisionAnalysisActive {
      let analysisIsActive = visionAnalysisSnapshot.activeFrameSequence != nil
      visionState = analysisIsActive
        ? "Motion-scoped analysis · preview held"
        : "Motion-scoped analysis · live recovery"
      visionBlocksMotion = false
      visionRole = .advisoryEvidence
      visionDetail = analysisIsActive
        ? "One immutable frame is being analyzed off the main actor. Preview publication is held until it settles; raw camera delivery continues."
        : "The owned movement is still active between computations. Analysis stops when that owner settles."
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

  private var visibilityActivityActor: String {
    if activeStopTarget != nil { return "Plotter controller" }
    if visibilityTargetSceneDisposition == .targetUnusable { return "Camera and Vision" }
    return "Learning runtime"
  }

  private var visibilityActivityAction: String {
    if currentCameraCalibrationFailure != nil {
      return "Build Target Geometry Proposal"
    }
    if targetAreaRelocationRequired && !targetAreaRelocationCompleted {
      return "Move to New Target Area"
    }
    if visibilityTargetSceneDisposition == .inkPossible {
      return "Observe Existing Target"
    }
    if visibilityTargetSceneDisposition == .targetUnusable {
      return "Recover Visibility Target"
    }
    return currentLearningPathItemID.title
  }

  private var visibilityActivityRecovery: [PresentationFragment] {
    if let currentCameraCalibrationFailure {
      return [.text(currentCameraCalibrationFailure.recoveryDescription)]
    }
    if targetAreaRelocationRequired && !targetAreaRelocationCompleted {
      return [.text("Choose a signed axis direction and one 50 or 10 mm Pen-Up move.")]
    }
    switch visibilityTargetSceneDisposition {
    case .inkPossible:
      return [
        .text(
          "Return to the accepted Clear pose and Observe Existing Target; never redraw this target area.")
      ]
    case .targetUnusable:
      return [.text("Register New Target Area and relocate, or record Paper Replaced.")]
    case .pristine, .targetObserved:
      return [
        .text(
          "Resolve the named controller, camera, or exact-frame fact, then retry that explicit action."
        )
      ]
    }
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
    case .captureTargetAnchoredBaseline:
      [
        ExerciseEvidencePresentation(
          label: "Target baseline",
          fragments: [.text(targetAnchoredTrialBaseline?.frame.id.rawValue ?? "not captured")])
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
    case .returnToClearPoseAndObserveNewInk:
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
      case .captureTargetAnchoredBaseline: .targetAnchoredTrialBaseline(currentDrawingTrialGroup)
      case .moveToLineStart: .linePlan(currentDrawingTrialGroup)
      case .drawIsolatedLine: .lineExecution(currentDrawingTrialGroup)
      case .returnToClearPoseAndObserveNewInk: .postLineFrame(currentDrawingTrialGroup)
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
    guard frameMode == .live, scopedVisionAnalysisActive,
      visibilityObservationOperation == nil
    else { return }
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
    jogCancelRequestInProgress = false
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
      let acceptedArtifactCheckpointActions,
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
    let priorScene = visibilityTargetSceneDisposition
    let priorTargetPose = targetPoseRegistrationFrame
    let priorTargetMachinePosition = registeredTargetMachinePosition
    let priorContact = targetCapAnchorEstimate
    let priorBaseline = preTargetClearViewBaseline
    let priorObservation = visibilityTargetObservation
    var graph = learningArtifactGraph
    let roots: Set<LearningArtifactKind> = [
      .machineCameraRegistration,
      .targetPoseRegistration,
      .targetROIRegistration,
    ]
    let invalidation = graph.invalidateForCameraChange(rootKinds: roots)
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    targetPoseRegistrationFrame = priorScene == .pristine ? nil : priorTargetPose
    registeredTargetMachinePosition =
      priorScene == .pristine
      ? nil : priorTargetMachinePosition
    targetCapAnchorEstimate = priorScene == .pristine ? nil : priorContact
    proposedMachineCameraRegistration = nil
    proposedTargetSearchCircle = nil
    targetGeometryProposalID = nil
    targetSearchCircle = nil
    targetCapAnchorAndSearchCircleAccepted = false
    preTargetClearViewBaseline = priorScene == .pristine ? nil : priorBaseline
    blankTargetBaselineCandidate = nil
    visibilityTargetSceneDisposition = priorScene == .pristine ? .pristine : .targetUnusable
    visibilityTargetObservation = priorScene == .pristine ? nil : priorObservation
    visibilityRegistrationAccepted = false
    machineCameraRegistration = nil
    targetAreaRelocationRequired = false
    targetAreaRelocationCompleted = false
    if priorScene != .pristine {
      retiredTargetAreaDispositions[targetAreaIdentity] = .targetUnusable
    }
    clearViewPoseAccepted = false
    pendingClearViewLabel = nil
    armatureGuidanceState = nil
    lastArmatureObservation = nil
    registeredTargetReturnSettlement = nil
    acceptedClearReturnSettlement = nil
    targetAnchoredTrialBaseline = nil
    drawingTrialObservationRegion = nil
    explorationPostLineFrame = nil
    drawingTrialLineStart = nil
    drawingTrialStrokeEvidence = nil
    lastInkObservation = nil
    drawingTrialAssessment = nil
    observedDrawingTrialStep = .chooseIsolatedLinePlan
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

  private func clearVisibilityLearningForRewind() {
    clearVisibilityLearningForRewind(from: .registerTargetPoseAndCameraGeometry)
  }

  private func clearVisibilityLearningForRewind(from step: HumanGuidedDiscoveryStep) {
    let physicalTargetMayRemain = visibilityTargetSceneDisposition != .pristine
    if step.rawValue <= HumanGuidedDiscoveryStep.registerTargetPoseAndCameraGeometry.rawValue {
      currentCameraCalibrationFailure = nil
      targetPoseRegistrationFrame = nil
      registeredTargetMachinePosition = nil
      targetCapAnchorEstimate = nil
      proposedMachineCameraRegistration = nil
      proposedTargetSearchCircle = nil
      targetGeometryProposalID = nil
      targetSearchCircle = nil
      targetCapAnchorAndSearchCircleAccepted = false
      machineCameraRegistration = nil
      targetAreaRelocationRequired = false
      targetAreaRelocationCompleted = false
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.discoverAndAcceptClearView.rawValue {
      clearViewPoseAccepted = false
      clearViewAttemptHistories = [:]
      pendingClearViewLabel = nil
      armatureGuidanceState = nil
      lastArmatureObservation = nil
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.confirmBlankTargetBaseline.rawValue {
      preTargetClearViewBaseline = nil
      blankTargetBaselineCandidate = nil
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.returnToRegisteredTargetPose.rawValue {
      registeredTargetReturnSettlement = nil
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.drawVisibilityTarget.rawValue {
      executedVisibilityTargetPlanRevision = nil
      visibilityTargetExecutionAttemptEvidence = nil
      acceptedClearReturnSettlement = nil
      visibilityTargetSceneDisposition = physicalTargetMayRemain ? .targetUnusable : .pristine
    }
    if step.rawValue <= HumanGuidedDiscoveryStep.returnAndObserveExistingTarget.rawValue {
      visibilityTargetObservation = nil
      penTipOffsetRegistration = nil
      visibilityObservationAttemptHistories = [:]
      acceptedVisibilityObservationAttemptID = nil
      acceptedClearReturnSettlement = nil
      if step.rawValue > HumanGuidedDiscoveryStep.drawVisibilityTarget.rawValue,
        physicalTargetMayRemain
      {
        visibilityTargetSceneDisposition = .inkPossible
      }
      cameraOverlays = []
    }
    visibilityRegistrationAccepted = false
  }

  private func clearDrawingLearningForRewind(from step: ObservedDrawingTrialStep) {
    if let episodeID = currentExplorationEpisode?.id {
      completedExplorationEpisodes.removeAll { $0.id == episodeID }
    }

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
      if step.rawValue <= ObservedDrawingTrialStep.captureTargetAnchoredBaseline.rawValue {
        episode.frames.removeAll {
          $0.role == .targetAnchoredTrialBaseline || $0.role == .postLine
        }
      } else if step.rawValue <= ObservedDrawingTrialStep.returnToClearPoseAndObserveNewInk.rawValue
      {
        episode.frames.removeAll { $0.role == .postLine }
      }
      if step.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue {
        episode.executedAction = nil
        episode.controllerEvidence = nil
      }
      if step.rawValue <= ObservedDrawingTrialStep.returnToClearPoseAndObserveNewInk.rawValue {
        episode.visionEstimate = nil
        episode.residual = nil
        episode.reward = nil
      }
      currentExplorationEpisode = episode
    }

    if step.rawValue <= ObservedDrawingTrialStep.captureTargetAnchoredBaseline.rawValue {
      targetAnchoredTrialBaseline = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.moveToLineStart.rawValue {
      lastProtocolPoseSettlement = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue {
      drawingTrialStrokeEvidence = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.returnToClearPoseAndObserveNewInk.rawValue {
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
    await cancelAndSettleVisibilityObservation()
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
    targetPoseRegistrationFrame = nil
    registeredTargetMachinePosition = nil
    targetCapAnchorEstimate = nil
    proposedMachineCameraRegistration = nil
    proposedTargetSearchCircle = nil
    targetGeometryProposalID = nil
    targetSearchCircle = nil
    targetCapAnchorAndSearchCircleAccepted = false
    preTargetClearViewBaseline = nil
    blankTargetBaselineCandidate = nil
    visibilityTargetSceneDisposition = .pristine
    visibilityTargetObservation = nil
    penTipOffsetRegistration = nil
    executedVisibilityTargetPlanRevision = nil
    visibilityTargetExecutionAttemptEvidence = nil
    visibilityObservationAttemptHistories = [:]
    acceptedVisibilityObservationAttemptID = nil
    visibilityRegistrationAccepted = false
    machineCameraRegistration = nil
    targetAreaIdentity = UUID()
    targetAreaRelocationRequired = false
    targetAreaRelocationCompleted = false
    retiredTargetAreaDispositions = [:]
    pendingBoundaryFinalPositions = [:]
    pendingBoundaryOwnerIDs = [:]
    pendingBoundaryStopCapabilities = [:]
    clearViewPoseAccepted = false
    pendingClearViewLabel = nil
    armatureGuidanceState = nil
    lastArmatureObservation = nil
    registeredTargetReturnSettlement = nil
    acceptedClearReturnSettlement = nil
    observedDrawingTrialStep = .chooseIsolatedLinePlan
    drawingTrialAssessment = nil
    drawingTrialLineStart = nil
    drawingTrialStrokeEvidence = nil
    targetAnchoredTrialBaseline = nil
    drawingTrialObservationRegion = nil
    explorationPostLineFrame = nil
    lastInkObservation = nil
    currentExplorationEpisode = nil
    learningArtifactGraph = LearningDependencyGraph()
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: penAttemptHistory.compatibility
    )
    boundaryAttemptHistories = [:]
    clearViewAttemptHistories = [:]
    comparisonAttemptHistories = [:]
    visibilityRepeatSnapshot = nil
    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
    restartableExerciseItemID = nil
    currentDrawingTrialGroup = AttemptGroupIdentity(
      rawValue: UUID().uuidString.lowercased()
    )
  }

  private func captureLearningAuthority() -> LearningAuthoritySnapshot {
    LearningAuthoritySnapshot(
      boundaryTeachingState: boundaryTeachingState,
      boundaryTeachingResultText: boundaryTeachingResultText,
      selectedDiscoverySequenceID: selectedDiscoverySequenceID,
      discoveryTransactions: discoveryTransactions,
      discoveryError: discoveryError,
      pairedBoundaryProgress: pairedBoundaryProgress,
      boundaryAttemptEvidenceByAttemptID: boundaryAttemptEvidenceByAttemptID,
      boundarySideAggregates: boundarySideAggregates,
      estimatedMachineCenter: estimatedMachineCenter,
      learnedLocalCoordinateFrame: learnedLocalCoordinateFrame,
      centerArrivalPosition: centerArrivalPosition,
      centerArrivalRetryRequired: centerArrivalRetryRequired,
      targetPoseRegistrationFrame: targetPoseRegistrationFrame,
      registeredTargetMachinePosition: registeredTargetMachinePosition,
      targetCapAnchorEstimate: targetCapAnchorEstimate,
      targetSearchCircle: targetSearchCircle,
      targetCapAnchorAndSearchCircleAccepted: targetCapAnchorAndSearchCircleAccepted,
      preTargetClearViewBaseline: preTargetClearViewBaseline,
      visibilityTargetSceneDisposition: visibilityTargetSceneDisposition,
      visibilityTargetObservation: visibilityTargetObservation,
      penTipOffsetRegistration: penTipOffsetRegistration,
      executedVisibilityTargetPlanRevision: executedVisibilityTargetPlanRevision,
      visibilityTargetExecutionAttemptEvidence: visibilityTargetExecutionAttemptEvidence,
      visibilityObservationAttemptHistories: visibilityObservationAttemptHistories,
      acceptedVisibilityObservationAttemptID: acceptedVisibilityObservationAttemptID,
      visibilityRegistrationAccepted: visibilityRegistrationAccepted,
      machineCameraRegistration: machineCameraRegistration,
      targetAreaIdentity: targetAreaIdentity,
      targetAreaRelocationRequired: targetAreaRelocationRequired,
      targetAreaRelocationCompleted: targetAreaRelocationCompleted,
      retiredTargetAreaDispositions: retiredTargetAreaDispositions,
      explorationError: explorationError,
      currentExplorationEpisode: currentExplorationEpisode,
      completedExplorationEpisodes: completedExplorationEpisodes,
      armatureGuidanceState: armatureGuidanceState,
      lastArmatureObservation: lastArmatureObservation,
      targetAnchoredTrialBaseline: targetAnchoredTrialBaseline,
      drawingTrialObservationRegion: drawingTrialObservationRegion,
      lastProtocolPoseSettlement: lastProtocolPoseSettlement,
      explorationPostLineFrame: explorationPostLineFrame,
      drawingTrialLineStart: drawingTrialLineStart,
      drawingTrialStrokeEvidence: drawingTrialStrokeEvidence,
      lastInkObservation: lastInkObservation,
      explorationInkStatus: explorationInkStatus,
      explorationExportPath: explorationExportPath,
      lastTravelFeedSelection: lastTravelFeedSelection,
      drawingTrialAssessment: drawingTrialAssessment,
      clearViewPoseAccepted: clearViewPoseAccepted,
      registeredTargetReturnSettlement: registeredTargetReturnSettlement,
      acceptedClearReturnSettlement: acceptedClearReturnSettlement,
      learningArtifactGraph: learningArtifactGraph,
      penAttemptHistory: penAttemptHistory,
      boundaryAttemptHistories: boundaryAttemptHistories,
      clearViewAttemptHistories: clearViewAttemptHistories,
      comparisonAttemptHistories: comparisonAttemptHistories,
      restartableExerciseItemID: restartableExerciseItemID,
      observedDrawingTrialStep: observedDrawingTrialStep,
      pendingClearViewLabel: pendingClearViewLabel,
      selectedBoundaryDirection: selectedBoundaryDirection,
      selectedClearViewDirection: selectedClearViewDirection,
      selectedLineDirection: selectedLineDirection,
      acceptedAttemptSequence: acceptedAttemptSequence,
      currentDrawingTrialGroup: currentDrawingTrialGroup,
      explorationCoordinateRevision: explorationCoordinateRevision,
      explorationToolPaperRevision: explorationToolPaperRevision
    )
  }

  private func resetLearningAuthorityForSimulation() {
    boundaryTeachingState = .idle
    boundaryTeachingResultText = "Choose one side to begin."
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
    targetPoseRegistrationFrame = nil
    registeredTargetMachinePosition = nil
    targetCapAnchorEstimate = nil
    proposedMachineCameraRegistration = nil
    proposedTargetSearchCircle = nil
    targetGeometryProposalID = nil
    targetSearchCircle = nil
    targetCapAnchorAndSearchCircleAccepted = false
    preTargetClearViewBaseline = nil
    blankTargetBaselineCandidate = nil
    visibilityTargetSceneDisposition = .pristine
    visibilityTargetObservation = nil
    penTipOffsetRegistration = nil
    executedVisibilityTargetPlanRevision = nil
    visibilityTargetExecutionAttemptEvidence = nil
    visibilityObservationAttemptHistories = [:]
    acceptedVisibilityObservationAttemptID = nil
    visibilityRegistrationAccepted = false
    machineCameraRegistration = nil
    targetAreaIdentity = UUID()
    targetAreaRelocationRequired = false
    targetAreaRelocationCompleted = false
    retiredTargetAreaDispositions = [:]
    explorationError = nil
    currentExplorationEpisode = nil
    completedExplorationEpisodes = []
    armatureGuidanceState = nil
    lastArmatureObservation = nil
    targetAnchoredTrialBaseline = nil
    drawingTrialObservationRegion = nil
    lastProtocolPoseSettlement = nil
    explorationPostLineFrame = nil
    drawingTrialLineStart = nil
    drawingTrialStrokeEvidence = nil
    lastInkObservation = nil
    explorationInkStatus = "no isolated-line observation yet"
    explorationExportPath = nil
    lastTravelFeedSelection = nil
    drawingTrialAssessment = nil
    clearViewPoseAccepted = false
    registeredTargetReturnSettlement = nil
    acceptedClearReturnSettlement = nil
    learningArtifactGraph = LearningDependencyGraph()
    penAttemptHistory = try! ExerciseAttemptHistory(
      compatibility: AttemptCompatibility(
        cameraConfigurationID: nil,
        coordinateSpace: .currentState,
        units: .state,
        group: AttemptGroupIdentity(rawValue: "simulated-pen-interaction"),
        algorithmRevision: "simulated-typed-operator-pen-observation-v1"
      )
    )
    boundaryAttemptHistories = [:]
    clearViewAttemptHistories = [:]
    comparisonAttemptHistories = [:]
    activeExerciseAttemptID = nil
    activeExerciseAttemptOwnerID = nil
    activeExerciseAttemptMode = nil
    restartableExerciseItemID = nil
    observedDrawingTrialStep = .chooseIsolatedLinePlan
    pendingClearViewLabel = nil
    selectedBoundaryDirection = .positiveX
    selectedClearViewDirection = .positiveX
    selectedLineDirection = .positiveX
    acceptedAttemptSequence = 0
    currentDrawingTrialGroup = AttemptGroupIdentity(
      rawValue: "simulated-\(UUID().uuidString.lowercased())"
    )
    explorationCoordinateRevision = 0
    explorationToolPaperRevision = UUID()
  }

  private func restoreLearningAuthority(_ snapshot: LearningAuthoritySnapshot) {
    boundaryTeachingState = snapshot.boundaryTeachingState
    boundaryTeachingResultText = snapshot.boundaryTeachingResultText
    selectedDiscoverySequenceID = snapshot.selectedDiscoverySequenceID
    discoveryTransactions = snapshot.discoveryTransactions
    discoveryError = snapshot.discoveryError
    pairedBoundaryProgress = snapshot.pairedBoundaryProgress
    boundaryAttemptEvidenceByAttemptID = snapshot.boundaryAttemptEvidenceByAttemptID
    boundarySideAggregates = snapshot.boundarySideAggregates
    estimatedMachineCenter = snapshot.estimatedMachineCenter
    learnedLocalCoordinateFrame = snapshot.learnedLocalCoordinateFrame
    centerArrivalPosition = snapshot.centerArrivalPosition
    centerArrivalRetryRequired = snapshot.centerArrivalRetryRequired
    targetPoseRegistrationFrame = snapshot.targetPoseRegistrationFrame
    registeredTargetMachinePosition = snapshot.registeredTargetMachinePosition
    targetCapAnchorEstimate = snapshot.targetCapAnchorEstimate
    targetSearchCircle = snapshot.targetSearchCircle
    targetCapAnchorAndSearchCircleAccepted = snapshot.targetCapAnchorAndSearchCircleAccepted
    preTargetClearViewBaseline = snapshot.preTargetClearViewBaseline
    visibilityTargetSceneDisposition = snapshot.visibilityTargetSceneDisposition
    visibilityTargetObservation = snapshot.visibilityTargetObservation
    penTipOffsetRegistration = snapshot.penTipOffsetRegistration
    executedVisibilityTargetPlanRevision = snapshot.executedVisibilityTargetPlanRevision
    visibilityTargetExecutionAttemptEvidence = snapshot.visibilityTargetExecutionAttemptEvidence
    visibilityObservationAttemptHistories = snapshot.visibilityObservationAttemptHistories
    acceptedVisibilityObservationAttemptID = snapshot.acceptedVisibilityObservationAttemptID
    visibilityRegistrationAccepted = snapshot.visibilityRegistrationAccepted
    machineCameraRegistration = snapshot.machineCameraRegistration
    targetAreaIdentity = snapshot.targetAreaIdentity
    targetAreaRelocationRequired = snapshot.targetAreaRelocationRequired
    targetAreaRelocationCompleted = snapshot.targetAreaRelocationCompleted
    retiredTargetAreaDispositions = snapshot.retiredTargetAreaDispositions
    explorationError = snapshot.explorationError
    currentExplorationEpisode = snapshot.currentExplorationEpisode
    completedExplorationEpisodes = snapshot.completedExplorationEpisodes
    armatureGuidanceState = snapshot.armatureGuidanceState
    lastArmatureObservation = snapshot.lastArmatureObservation
    targetAnchoredTrialBaseline = snapshot.targetAnchoredTrialBaseline
    drawingTrialObservationRegion = snapshot.drawingTrialObservationRegion
    lastProtocolPoseSettlement = snapshot.lastProtocolPoseSettlement
    explorationPostLineFrame = snapshot.explorationPostLineFrame
    drawingTrialLineStart = snapshot.drawingTrialLineStart
    drawingTrialStrokeEvidence = snapshot.drawingTrialStrokeEvidence
    lastInkObservation = snapshot.lastInkObservation
    explorationInkStatus = snapshot.explorationInkStatus
    explorationExportPath = snapshot.explorationExportPath
    lastTravelFeedSelection = snapshot.lastTravelFeedSelection
    drawingTrialAssessment = snapshot.drawingTrialAssessment
    clearViewPoseAccepted = snapshot.clearViewPoseAccepted
    registeredTargetReturnSettlement = snapshot.registeredTargetReturnSettlement
    acceptedClearReturnSettlement = snapshot.acceptedClearReturnSettlement
    learningArtifactGraph = snapshot.learningArtifactGraph
    penAttemptHistory = snapshot.penAttemptHistory
    boundaryAttemptHistories = snapshot.boundaryAttemptHistories
    clearViewAttemptHistories = snapshot.clearViewAttemptHistories
    comparisonAttemptHistories = snapshot.comparisonAttemptHistories
    restartableExerciseItemID = snapshot.restartableExerciseItemID
    observedDrawingTrialStep = snapshot.observedDrawingTrialStep
    pendingClearViewLabel = snapshot.pendingClearViewLabel
    selectedBoundaryDirection = snapshot.selectedBoundaryDirection
    selectedClearViewDirection = snapshot.selectedClearViewDirection
    selectedLineDirection = snapshot.selectedLineDirection
    acceptedAttemptSequence = snapshot.acceptedAttemptSequence
    currentDrawingTrialGroup = snapshot.currentDrawingTrialGroup
    explorationCoordinateRevision = snapshot.explorationCoordinateRevision
    explorationToolPaperRevision = snapshot.explorationToolPaperRevision
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
    guard let target = activeStopTarget else { return }

    let owner: Task<Void, Never>?
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
      owner = boundaryMotionTask
    case .manualJog:
      owner = manualJogTask.map { task in Task { _ = await task.value } }
    case .exerciseMotion:
      owner = exerciseMotionTask.map { task in Task { _ = await task.value } }
    case .visibilityTarget(_, let operationOwner, _):
      await requestVisibilityTargetIntent(.shutdown, operationOwner: operationOwner)
      owner =
        switch operationOwner {
        case .liveOperation:
          visibilityTargetTask.map { task in Task { _ = await task.value } }
        case .simulated:
          simulatedOperationTask.map { task in Task { _ = await task.value } }
        case .liveBoundary:
          nil
        }
    case .drawingTrial:
      owner =
        frameMode == .simulated
        ? simulatedOperationTask.map { task in Task { _ = await task.value } }
        : drawingTrialTask.map { task in Task { _ = await task.value } }
    }

    if case .visibilityTarget = target {
      // Compound visibility target already latched its shutdown intent above.
    } else if stopDispositionLatch == nil,
      latchContextualStopDisposition(
        for: target,
        intent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
    {
      await requestSingleJogCancel(for: target, intent: .shutdown)
    }
    await owner?.value
    if activeStopTarget == target { activeStopTarget = nil }
    if stopDispositionLatch?.capabilityID == target.capabilityID { stopDispositionLatch = nil }
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
    analysisFrameHeld = false
    scopedVisionAnalysisActive = false
    visionAnalysisSnapshot = .stopped
    lastSceneMeasurement = nil
    lastCameraSnapshotPath = nil
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
    case .captureTargetAnchoredBaseline, .returnToClearPoseAndObserveNewInk:
      "Camera and Vision"
    case .moveToLineStart, .drawIsolatedLine: "Plotter controller"
    case .compareIntendedAndObservedGeometry: "Operator"
    }
  }

  private func drawingTrialActionTitle(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan: "Choose Isolated Line Plan"
    case .captureTargetAnchoredBaseline: "Capture Target-Anchored Baseline"
    case .moveToLineStart: "Move to Line Start"
    case .drawIsolatedLine: "Draw Isolated Line"
    case .returnToClearPoseAndObserveNewInk: "Return to Clear Pose and Observe New Ink"
    case .compareIntendedAndObservedGeometry: "Start"
    }
  }

  private func drawingTrialActionText(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan:
      "Choose an outward direction from the accepted visibility target and record its perimeter start."
    case .captureTargetAnchoredBaseline:
      "At the accepted Clear pose, capture one exact target-present baseline."
    case .moveToLineStart:
      "Move Pen Up to the recorded target-perimeter line start."
    case .drawIsolatedLine:
      "Lower the pen, draw one 5 mm outward stroke, and raise."
    case .returnToClearPoseAndObserveNewInk:
      "Return clear, settle, capture a strictly newer frame, and extract new ink."
    case .compareIntendedAndObservedGeometry:
      "Record one typed comparison for this local trial; no redraw follows."
    }
  }

  private func drawingTrialExpectationText(for step: ObservedDrawingTrialStep) -> String {
    switch step {
    case .chooseIsolatedLinePlan: "One typed target-anchored line plan."
    case .captureTargetAnchoredBaseline:
      "One exact target-present frame at the accepted Clear pose."
    case .moveToLineStart: "Arrival at the target-perimeter start while Pen Up."
    case .drawIsolatedLine: "A closed controller stroke outcome; this is not yet ink proof."
    case .returnToClearPoseAndObserveNewInk:
      "Observed new line ink or a typed unclear/rejected observation, with no automatic redraw."
    case .compareIntendedAndObservedGeometry:
      "One typed operator assessment completes only this trial."
    }
  }

  private func drawingTrialActionUnavailableReason(
    for step: ObservedDrawingTrialStep
  ) -> String? {
    if explorationOperationInProgress { return "The current learning action is still in progress." }
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
    case .captureTargetAnchoredBaseline, .returnToClearPoseAndObserveNewInk:
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
    guard let center = registeredTargetMachinePosition else {
      throw LearningPathOperationError.requiredState("Accepted target center is unavailable.")
    }
    let perimeter = 2.0
    let offset: Vector2<MachineSpace> =
      switch direction {
      case .negativeX: try Vector2(dx: -perimeter, dy: 0)
      case .positiveX: try Vector2(dx: perimeter, dy: 0)
      case .negativeY: try Vector2(dx: 0, dy: -perimeter)
      case .positiveY: try Vector2(dx: 0, dy: perimeter)
      }
    drawingTrialLineStart = try MachinePosition(
      x: center.point.x + offset.dx,
      y: center.point.y + offset.dy
    )
    currentExplorationEpisode = ExplorationEpisode(
      sessionID: learningEvidenceSessionID,
      rung: .observedDrawingTrial,
      source: frameMode == .simulated ? .simulated : .live,
      split: .training,
      startedNanoseconds: nowNanoseconds()
    )
    currentExplorationEpisode?.lineStartPosition = drawingTrialLineStart
  }

  private func captureTargetAnchoredTrialBaseline() async throws {
    guard let clear = armatureGuidanceState?.acceptedClearPose?.position,
      protocolPositionsMatch(try currentMachinePosition(), clear),
      visibilityRegistrationAccepted
    else {
      throw LearningPathOperationError.requiredState(
        "Accepted visibility target and exact Clear pose are required."
      )
    }
    let frame = try await captureProtocolFrame(
      newerThan: displayedFrame?.frame.captureNanoseconds ?? 0
    )
    targetAnchoredTrialBaseline = frame
    appendFrameEvidence(.targetAnchoredTrialBaseline, frame: frame.frame)
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
        throw LearningPathOperationError.controllerOutcome(
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
      settlement.targetAreaIdentity == targetAreaIdentity,
      protocolPositionsMatch(settlement.target, expectedTarget),
      protocolPositionsMatch(settlement.actual, expectedTarget),
      controllerIsPenUpAndIdle,
      let current = try? currentMachinePosition(),
      protocolPositionsMatch(current, settlement.actual)
    else { return false }
    return true
  }

  private var registeredTargetReturnIsCurrent: Bool {
    protocolSettlementIsCurrent(
      registeredTargetReturnSettlement,
      expectedTarget: registeredTargetMachinePosition
    )
  }

  private var acceptedClearReturnIsCurrent: Bool {
    protocolSettlementIsCurrent(
      acceptedClearReturnSettlement,
      expectedTarget: armatureGuidanceState?.acceptedClearPose?.position
    )
  }

  private func protocolPositionsMatch(
    _ actual: MachinePosition,
    _ target: MachinePosition
  ) -> Bool {
    ControllerPositionAcceptancePolicy.accepts(actual, target: target)
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
      toolPaperRevision: explorationToolPaperRevision,
      targetAreaIdentity: targetAreaIdentity
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
    let visionScopeWasStarted = await beginScopedVisionAnalysis()
    do {
      let finalPosition = try await executeSupervisedPenUpTravel(
        delta: delta,
        ownerID: ownerID,
        action: action
      )
      await endScopedVisionAnalysis(visionScopeWasStarted)
      return finalPosition
    } catch {
      await endScopedVisionAnalysis(visionScopeWasStarted)
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
        throw LearningPathOperationError.controllerOutcome(
          "Simulated supervised Pen-Up travel was refused: \(String(describing: error))."
        )
      }
      let target = ContextualStopTarget.exerciseMotion(
        capabilityID: ContextualStopCapabilityID(),
        operationOwner: .simulated(operation.id),
        ownerID: ownerID,
        action: action
      )
      activeStopTarget = target
      stopDispositionLatch = nil
      if hasShutdown || Task.isCancelled {
        _ = latchContextualStopDisposition(
          for: target,
          intent: .shutdown,
          actor: "Application",
          action: "Shutdown"
        )
        await requestSingleJogCancel(for: target, intent: .shutdown)
        if activeStopTarget == target { activeStopTarget = nil }
        if stopDispositionLatch?.capabilityID == target.capabilityID {
          stopDispositionLatch = nil
        }
        simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
        throw LearningPathOperationError.requiredState(
          "Application shutdown cancelled supervised Pen-Up travel before execution."
        )
      }
      let owner = Task { [simulatedLearningRuntime, simulatedExecutionPacing] in
        try? await simulatedLearningRuntime.executeNaturally(
          operation.id,
          pacing: simulatedExecutionPacing
        ).result.get()
      }
      exerciseMotionTask = Task {
        _ = await owner.value
        return .ambiguous(.transport("simulated exercise travel task adapter"))
      }
      let outcome = await owner.value
      exerciseMotionTask = nil
      if activeStopTarget == target { activeStopTarget = nil }
      if stopDispositionLatch?.capabilityID == target.capabilityID { stopDispositionLatch = nil }
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
      guard let outcome, outcome.disposition == .naturallyCompleted else {
        throw LearningPathOperationError.controllerOutcome(
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
      throw LearningPathOperationError.controllerOutcome(
        motionOutcomeDescription(outcome, action: action)
      )
    }
    let target = ContextualStopTarget.exerciseMotion(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(operation.id),
      ownerID: ownerID,
      action: action
    )
    let owner = Task { await operation.outcome() }
    exerciseMotionTask = owner
    activeStopTarget = target
    stopDispositionLatch = nil
    if hasShutdown || Task.isCancelled {
      _ = latchContextualStopDisposition(
        for: target,
        intent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
      await requestSingleJogCancel(for: target, intent: .shutdown)
      _ = await owner.value
      exerciseMotionTask = nil
      if activeStopTarget == target { activeStopTarget = nil }
      if stopDispositionLatch?.capabilityID == target.capabilityID { stopDispositionLatch = nil }
      machineSnapshot = await machineActions.snapshot()
      throw LearningPathOperationError.requiredState(
        "Application shutdown cancelled supervised Pen-Up travel during admission."
      )
    }
    let outcome = await owner.value
    exerciseMotionTask = nil
    if activeStopTarget == target { activeStopTarget = nil }
    if stopDispositionLatch?.capabilityID == target.capabilityID { stopDispositionLatch = nil }
    machineSnapshot = await machineActions.snapshot()
    switch outcome {
    case .acceptedThenCompleted(let finalPosition):
      return finalPosition
    case .cancelled:
      throw LearningPathOperationError.controllerOutcome(
        "\(action) was stopped or cancelled; no arrival artifact was accepted."
      )
    case .ambiguous(let ambiguity):
      throw LearningPathOperationError.controllerOutcome(ambiguity.actionableDescription)
    case .refused(let refusal):
      throw LearningPathOperationError.controllerOutcome(refusal.actionableDescription)
    }
  }

  private func drawIsolatedTrialLine() async throws {
    guard let start = drawingTrialLineStart else {
      throw LearningPathOperationError.requiredState(
        "Move to the recorded target-perimeter line start before drawing."
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
        "Move to the recorded target-perimeter line start before drawing."
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
      simulatedOperationTask = task
      activeStopTarget = target
      stopDispositionLatch = nil
      guard let outcome = await task.value else {
        throw LearningPathOperationError.controllerOutcome(
          "The simulated isolated-line owner lost its outcome."
        )
      }
      simulatedOperationTask = nil
      if activeStopTarget == target { activeStopTarget = nil }
      guard outcome.disposition == .naturallyCompleted else {
        throw LearningPathOperationError.controllerOutcome(
          "Simulated drawing did not complete naturally."
        )
      }
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
      throw LearningPathOperationError.controllerOutcome(String(describing: lower))
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
      throw LearningPathOperationError.controllerOutcome(String(describing: outcome))
    }
    let target = ContextualStopTarget.drawingTrial(
      capabilityID: ContextualStopCapabilityID(),
      operationOwner: .liveOperation(admittedOperation.id)
    )
    let owner = Task { await admittedOperation.outcome() }
    drawingTrialTask = owner
    activeStopTarget = target
    stopDispositionLatch = nil
    let outcome = await owner.value
    drawingTrialTask = nil
    if activeStopTarget == target { activeStopTarget = nil }
    if stopDispositionLatch?.capabilityID == target.capabilityID { stopDispositionLatch = nil }
    machineSnapshot = await machineActions.snapshot()
    switch outcome {
    case .completed(let evidence):
      drawingTrialStrokeEvidence = evidence
      drawingTrialStrokeCompletedNaturally = true
      recordStrokeEvidence(evidence, outcome: .completed, summary: "Idle with final MPos")
      _ = await announceAdvisory("Raising the pen after the isolated line.")
      let raise = await machineActions.requestPenActuation(.raise)
      machineSnapshot = await machineActions.snapshot()
      guard case .commandedAndSettled = raise else {
        throw LearningPathOperationError.controllerOutcome(String(describing: raise))
      }
    case .cancelled(let evidence, let penRaiseOutcome):
      drawingTrialStrokeEvidence = evidence
      drawingTrialStrokeCompletedNaturally = false
      recordStrokeEvidence(evidence, outcome: .cancelled, summary: "Stop settled in place")
      throw LearningPathOperationError.controllerOutcome(
        "Drawing stopped; controller Pen Up outcome: \(penRaiseOutcome)"
      )
    case .ambiguous(let ambiguity):
      throw LearningPathOperationError.controllerOutcome(ambiguity.actionableDescription)
    case .refused(let refusal):
      throw LearningPathOperationError.controllerOutcome(String(describing: refusal))
    }
  }

  private func returnToClearPoseAndObserveTrialInk() async throws {
    guard let cameraActions,
      let anchored = targetAnchoredTrialBaseline,
      let clearPosition = armatureGuidanceState?.acceptedClearPose?.position,
      let lineStart = drawingTrialLineStart,
      let registration = machineCameraRegistration,
      let tipOffset = penTipOffsetRegistration,
      registration.source == tipOffset.source,
      registration.cameraConfigurationID == tipOffset.cameraConfigurationID,
      let targetObservation = visibilityTargetObservation
    else {
      throw LearningPathOperationError.requiredState(
        "Target baseline, Clear pose, line plan, cap registration, and cap-to-tip offset are required."
      )
    }
    let current = try currentMachinePosition()
    if !protocolPositionsMatch(current, clearPosition) {
      let delta = try Vector2<MachineSpace>(
        dx: clearPosition.point.x - current.point.x,
        dy: clearPosition.point.y - current.point.y
      )
      let final = try await performSupervisedPenUpTravel(
        delta: delta,
        ownerID: .observedDrawingTrial(.returnToClearPoseAndObserveNewInk),
        action: "Return to Clear Pose and Observe New Ink"
      )
      guard
        recordProtocolPoseSettlement(
          action: "Return to Clear Pose and Observe New Ink",
          target: clearPosition,
          actual: final
        )
      else {
        throw LearningPathOperationError.controllerOutcome(
          "Return to Clear settled at an incompatible MPos."
        )
      }
    }
    let boundary = max(
      anchored.frame.captureNanoseconds,
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
    let cameraStart = try tipOffset.tipPoint(
      from: registration.fit.cameraPoint(from: lineStart.point)
    )
    let cameraEnd = try tipOffset.tipPoint(
      from: registration.fit.cameraPoint(from: lineEnd)
    )
    let projectedDelta = try cameraStart.vector(to: cameraEnd)
    let componentAndAlignmentMargin = 4
    let observedTargetMinX = targetObservation.samples.map(\.bounds.minX).min()!
    let observedTargetMinY = targetObservation.samples.map(\.bounds.minY).min()!
    let observedTargetMaxX = targetObservation.samples.map(\.bounds.maxX).max()!
    let observedTargetMaxY = targetObservation.samples.map(\.bounds.maxY).max()!
    let minX = min(
      Int(floor(observedTargetMinX)) - componentAndAlignmentMargin,
      Int(floor(min(cameraStart.x, cameraEnd.x))) - componentAndAlignmentMargin)
    let minY = min(
      Int(floor(observedTargetMinY)) - componentAndAlignmentMargin,
      Int(floor(min(cameraStart.y, cameraEnd.y))) - componentAndAlignmentMargin)
    let maxX = max(
      Int(ceil(observedTargetMaxX)) + componentAndAlignmentMargin,
      Int(ceil(max(cameraStart.x, cameraEnd.x))) + componentAndAlignmentMargin
    )
    let maxY = max(
      Int(ceil(observedTargetMaxY)) + componentAndAlignmentMargin,
      Int(ceil(max(cameraStart.y, cameraEnd.y))) + componentAndAlignmentMargin
    )
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
        targetPresentBaseline: SamePoseFrameSample(
          displayedFrame: anchored,
          controllerPosition: clearPosition
        ),
        postLine: SamePoseFrameSample(
          displayedFrame: post,
          controllerPosition: clearPosition
        ),
        region: trialRegion,
        thresholds: InkPixelThresholds(minimumLuminanceDecrease: 20),
        lineStartPoint: cameraStart,
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
        algorithmRevision: "cap-tip-corrected-isolated-ink-v4"
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
    analysisFrameHeld = false
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

  private func motionOutcomeDescription(_ outcome: MotionOutcome, action: String) -> String {
    switch outcome {
    case .refused(let refusal):
      refusal.actionableDescription
    case .ambiguous(let ambiguity):
      ambiguity.actionableDescription
    case .cancelled:
      "\(action) was stopped or cancelled before an arrival artifact could be accepted."
    case .acceptedThenCompleted:
      "\(action) completed before its owner-bound admission handle was returned."
    }
  }

  private func recordWorkflowTelemetry(_ event: WorkflowTelemetryEvent) async {
    await workflowTelemetryActions?.record(event)
  }

  private func updateCurrentCameraCalibrationPhase(
    _ phase: String,
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
        detail: phase
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
          code: "controller_context_changed",
          detail: detail,
          recovery: .revalidateControllerContext
        )
      case .freshFrameUnavailable:
        return CurrentCameraCalibrationFailure(
          code: "fresh_frame_unavailable",
          detail: detail,
          recovery: calibrationPositionRecovery(targetPosition: targetPosition)
        )
      case .controllerOutcome:
        return CurrentCameraCalibrationFailure(
          code: "controller_outcome",
          detail: detail,
          recovery: calibrationPositionRecovery(targetPosition: targetPosition)
        )
      case .inkRejected:
        return CurrentCameraCalibrationFailure(
          code: "ink_rejected",
          detail: detail,
          recovery: .resolveNamedFailure
        )
      case .requiredState:
        return CurrentCameraCalibrationFailure(
          code: "required_state_missing",
          detail: detail,
          recovery: calibrationPositionRecovery(targetPosition: targetPosition)
        )
      }
    }
    return CurrentCameraCalibrationFailure(
      code: "unexpected_failure",
      detail: detail,
      recovery: calibrationPositionRecovery(targetPosition: targetPosition)
    )
  }

  private func calibrationPositionRecovery(
    targetPosition: MachinePosition
  ) -> WorkflowTelemetryRecovery {
    guard let current = try? currentMachinePosition() else { return .resolveNamedFailure }
    return protocolPositionsMatch(current, targetPosition)
      ? .retryCalibration : .returnToRegisteredTargetPose
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
