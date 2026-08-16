import Foundation
import Observation
import PlotterModel
import PlotterRuntime

enum LearningSurfaceExposureRecoveryDisposition: Hashable, Sendable {
  case ready
  case diagnosticsRequired
  case paperReplacementRequired
}

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
    let maximumSpread = samples.enumerated().flatMap { leftIndex, left in
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
  case sparseTipMark(
    capabilityID: ContextualStopCapabilityID,
    operationOwner: ContextualMotionOwnerID,
    exposureID: LearningSurfaceExposureID
  )

  var capabilityID: ContextualStopCapabilityID {
    switch self {
    case .pairedBoundary(let capabilityID, _, _, _, _),
      .manualJog(let capabilityID, _),
      .manualDrawingStroke(let capabilityID, _),
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
      .manualDrawingStroke(_, let owner),
      .exerciseMotion(_, let owner, _, _),
      .drawingTrial(_, let owner),
      .sparseTipMark(_, let owner, _):
      owner
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
  case sparseTipReveal(ToolContactCalibrationPosition)
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
    case .sparseTipReveal(let position): "Reveal Sparse Tip Circle \(position.rawValue)"
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
  let boundaryIntent: BoundaryTerminationIntent?
  let mechanicalCancelIntent: JogCancelIntent
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
  case stopLatched = "Stop latched"
  case settling = "Controller settlement"
  case commit = "Atomic accepted commit"
  case recovery = "Recovery"
}

enum BoundaryActivityDisposition: Hashable, Sendable {
  case inProgress
  case succeeded
  case stopped
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
  let boundaryIntent: BoundaryTerminationIntent?
  let mechanicalCancelIntent: JogCancelIntent
  let actor: String
  let action: String
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

  private struct EstimatedCenterAuthority {
    let center: EstimatedMachineCenter
    let localFrame: LearnedLocalCoordinateFrame
  }

  private struct LocalPreLineContextAuthority {
    let baseline: DisplayedFrame
    let revealPosition: MachinePosition
    let tipRegistrationRevisionID: LearningArtifactRevisionID
  }

  private struct LineStartArrivalAuthority {
    let target: MachinePosition
    let settlement: ProtocolPoseSettlement
    let requiredTravel: Bool
  }

  private enum LineExecutionAuthority: Hashable, Sendable {
    case live(DrawingStrokeEvidence)
    case simulated(SimulatedLearningOperationOutcome)

    var finalSampleNanoseconds: UInt64? {
      guard case .live(let evidence) = self else { return nil }
      return evidence.finalSampleNanoseconds
    }
  }

  private struct PostLineObservationAuthority {
    let revealSettlement: ProtocolPoseSettlement
    let frame: DisplayedFrame
    let region: PixelRect
    let observation: IsolatedInkObservation
  }

  private struct DrawingTrialState {
    var step: ObservedDrawingTrialStep = .chooseIsolatedLinePlan
    var linePlan: ObservedDrawingTrialLinePlan?
    var localPreLineContext: LocalPreLineContextAuthority?
    var lineStartArrival: LineStartArrivalAuthority?
    var lineExecution: LineExecutionAuthority?
    var postLineObservation: PostLineObservationAuthority?
    var inkStatus = "no isolated-line observation yet"
    var lastTravelFeedSelection: TravelFeedSelection?
    var assessment: DrawingTrialAssessment?
    var currentEpisode: ExplorationEpisode?
    var completedEpisodes: [ExplorationEpisode] = []
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

    mutating func invalidatePayload(
      from invalidatedStep: ObservedDrawingTrialStep,
      source: OperatorFrameMode
    ) {
      if invalidatedStep == .chooseIsolatedLinePlan {
        currentEpisode = nil
        linePlan = nil
        group = Self.newGroup(for: source)
      } else if var episode = currentEpisode {
        episode.termination = nil
        episode.humanAssessment = nil
        if invalidatedStep.rawValue
          <= ObservedDrawingTrialStep.captureLocalPreLineBaseline.rawValue
        {
          episode.frames.removeAll {
            $0.role == .localPreLineBaseline || $0.role == .postLine
          }
        } else if invalidatedStep.rawValue
          <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue
        {
          episode.frames.removeAll { $0.role == .postLine }
        }
        if invalidatedStep.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue {
          episode.controllerEvidence = nil
        }
        if invalidatedStep.rawValue
          <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue
        {
          episode.observedLineObservation = nil
          episode.visionEstimate = nil
          episode.residual = nil
        }
        currentEpisode = episode
      }

      if invalidatedStep.rawValue
        <= ObservedDrawingTrialStep.captureLocalPreLineBaseline.rawValue
      {
        localPreLineContext = nil
      }
      if invalidatedStep.rawValue <= ObservedDrawingTrialStep.moveToLineStart.rawValue {
        lineStartArrival = nil
      }
      if invalidatedStep.rawValue <= ObservedDrawingTrialStep.drawIsolatedLine.rawValue {
        lineExecution = nil
      }
      if invalidatedStep.rawValue <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue {
        postLineObservation = nil
        inkStatus = "no isolated-line observation yet"
      }
      assessment = nil
      comparisonAttemptHistories = [:]
      lastTravelFeedSelection = nil
      step = invalidatedStep
    }
  }

  private struct ToolContactSelectionContext {
    let pendingEvidence: PendingToolContactEvidence
    let frame: DisplayedFrame
    let request: ActionSurfacePointSelectionRequest
  }

  private struct PenCapAppearanceSelectionContext {
    let frame: DisplayedFrame
    let request: ActionSurfacePointSelectionRequest
  }

  /// Attempt-local cap evidence. A click may configure the running LIVE Vision
  /// attempt, but it is not accepted Learning authority until the complete
  /// Pen Interaction transaction commits.
  private struct StagedPenCapAppearanceCandidate: Equatable, Sendable {
    let attemptID: ExerciseAttemptID
    let attemptMode: ExerciseAttemptMode
    let source: OperatorFrameMode
    let selection: PenCapAppearanceSelection
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
    case awaitingClick(ToolContactSelectionContext)
    case selected(ToolContactSelectionContext, Point2<CameraPixelSpace>)

    var context: ToolContactSelectionContext? {
      switch self {
      case .idle: nil
      case .awaitingClick(let context), .selected(let context, _): context
      }
    }

    var point: Point2<CameraPixelSpace>? {
      guard case .selected(_, let point) = self else { return nil }
      return point
    }

    mutating func stage(_ context: ToolContactSelectionContext) {
      self = .awaitingClick(context)
    }

    mutating func select(_ point: Point2<CameraPixelSpace>) -> Bool {
      guard let context else { return false }
      self = .selected(context, point)
      return true
    }

    mutating func clearPoint() -> Bool {
      guard case .selected(let context, _) = self else { return false }
      self = .awaitingClick(context)
      return true
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
    var estimatedCenterAuthority: EstimatedCenterAuthority?
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
    var surfaceExposureLedger = LearningSurfaceExposureLedger()
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
    var parkedAcceptedMachineArtifactCheckpoint: AcceptedMachineArtifactCheckpoint?
    var quarantinedTipCalibrationCheckpoint: AcceptedTipCalibrationCheckpoint?
    var learningAuthorityError: String?
    var selectedBoundaryDirection: BoundaryDirection = .positiveX
    var selectedLineDirection: BoundaryDirection = .positiveX
    var acceptedAttemptSequence: UInt64 = 0
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
      drawingTrial = DrawingTrialState(source: source)
      explorationToolPaperRevision = paperContactPlaneRevision
    }
  }

  private enum MotionPriors {
    static let stepMM = "50"
    static let feedMMPerMinute = "500"
    /// Finite GRBL boundary horizon. Reaching it is a needs-attention result,
    /// never Boundary evidence and never an automatic resend.
    static let boundaryWireSegmentMM = 20.0
  }

  struct MachineActions: Sendable {
    let select: @Sendable (MachineLinkDescriptor) async throws -> RunInterpreterSnapshot
    let snapshot: @Sendable () async -> RunInterpreterSnapshot?
    let requestPassiveProbe: @Sendable () async throws -> PassiveProbeResult
    let requestControllerAlarmClear: @Sendable () async -> ControllerAlarmClearOutcome
    let activateMotionGuard: @Sendable () async -> MotionGuardActivationOutcome
    let beginRelativeJog: @Sendable (RelativeJogRequest) async -> RelativeJogAdmission
    let beginDrawingStroke: @Sendable (DrawingStrokeRequest) async -> DrawingStrokeAdmission
    let requestPenActuation:
      @Sendable (PenCommand, PenActuationProfile) async -> PenOutcome
    let beginBoundaryMotion:
      @Sendable (BoundaryMotionRequest) async -> BoundaryMotionAdmission
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

  struct LearningAuthorityManifestActions: Sendable {
    let load: @Sendable () -> LearningAuthorityManifestLoadResult
    let commit:
      @Sendable (
        LearningAuthorityStoreRevision,
        LearningAuthorityManifestMutation
      ) throws -> LearningAuthorityManifestSnapshot
  }

  struct LiveLearningSurfaceExposureActions: Sendable {
    let load: @Sendable () -> LiveLearningSurfaceExposureLoadResult
    let save:
      @Sendable (
        LiveLearningSurfaceExposureStoreRevision,
        LearningSurfaceExposureLedger,
        PaperContactPlaneRevision
      ) throws -> LiveLearningSurfaceExposureSnapshot
    let recoverForPaperReplacement:
      @Sendable (
        LiveLearningSurfaceExposureStoreRevision,
        PaperContactPlaneRevision
      ) throws -> LiveLearningSurfaceExposureSnapshot
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
  }

  private(set) var livePenCapAppearanceSelection: PenCapAppearanceSelection?
  private(set) var simulatedPenCapAppearanceSelection: PenCapAppearanceSelection?
  private(set) var persistedPenCapAppearanceLoadState: PersistedPenCapAppearanceLoadState
  var penCapAppearanceSelection: PenCapAppearanceSelection? {
    frameMode == .live ? livePenCapAppearanceSelection : simulatedPenCapAppearanceSelection
  }
  private var livePenCapColor: PenCapColor? { livePenCapAppearanceSelection?.color }
  let videoPresentationPreferences: VideoPresentationPreferences
  var overlayPreferenceState: OverlayPreferenceState {
    videoPresentationPreferences.overlayPreferenceState
  }
  var visionAnalysisCadence: VisionAnalysisCadence {
    videoPresentationPreferences.cadence
  }
  var videoAnalysisRegionLock: VideoAnalysisRegionLock? {
    videoPresentationPreferences.lockedAnalysisRegion
  }
  var frameMode: OperatorFrameMode = .live
  // String-backed numeric inputs preserve partially typed values and keep X/Y
  // independent. Runtime value constructors and MachineController own validity.
  var xStepText = MotionPriors.stepMM
  var yStepText = MotionPriors.stepMM
  var feedText = MotionPriors.feedMMPerMinute
  private(set) var learningIsEnabled = true

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
    [ExerciseAttemptID: BoundarySideAttemptEvidence] {
    get { activeLearningSession.boundaryAttemptEvidenceByAttemptID }
    set { activeLearningSession.boundaryAttemptEvidenceByAttemptID = newValue }
  }
  private(set) var boundarySideAggregates: [BoundaryDirection: BoundarySideAggregate] {
    get { activeLearningSession.boundarySideAggregates }
    set { activeLearningSession.boundarySideAggregates = newValue }
  }
  var estimatedMachineCenter: EstimatedMachineCenter? {
    activeLearningSession.estimatedCenterAuthority?.center
  }
  var learnedLocalCoordinateFrame: LearnedLocalCoordinateFrame? {
    activeLearningSession.estimatedCenterAuthority?.localFrame
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
  private var pendingToolContactEvidence: PendingToolContactEvidence? {
    activeLearningSession.toolContactSelection.context?.pendingEvidence
  }
  var toolContactPointSelectionRequest: ActionSurfacePointSelectionRequest? {
    activeLearningSession.toolContactSelection.context?.request
  }
  var pointSelectionRequest: ActionSurfacePointSelectionRequest? {
    penCapAppearanceSelectionContext?.request ?? toolContactPointSelectionRequest
  }
  var selectedToolContactPoint: Point2<CameraPixelSpace>? {
    activeLearningSession.toolContactSelection.point
  }
  private let machineGeometryIdentity: MachineGeometryIdentity
  private let toolAssemblyRevision: ToolAssemblyRevision
  private let penContactProfileRevision: PenContactProfileRevision
  private let cameraMountRevision: UUID
  private let cameraReframingRevision: UUID
  private var surfaceExposureLedger: LearningSurfaceExposureLedger {
    get { activeLearningSession.surfaceExposureLedger }
    set { activeLearningSession.surfaceExposureLedger = newValue }
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
  var localPreLineBaseline: DisplayedFrame? {
    activeLearningSession.drawingTrial.localPreLineContext?.baseline
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
    get { activeLearningSession.drawingTrial.currentEpisode }
    set { activeLearningSession.drawingTrial.currentEpisode = newValue }
  }
  private(set) var completedExplorationEpisodes: [ExplorationEpisode] {
    get { activeLearningSession.drawingTrial.completedEpisodes }
    set { activeLearningSession.drawingTrial.completedEpisodes = newValue }
  }
  var explorationPostLineFrame: DisplayedFrame? {
    activeLearningSession.drawingTrial.postLineObservation?.frame
  }
  var drawingTrialLineStart: MachinePosition? {
    activeLearningSession.drawingTrial.linePlan?.startPosition
  }
  var currentDrawingTrialGroupHasExposure: Bool {
    drawingTrialGroupHasExposure(currentDrawingTrialGroup, in: activeLearningSession)
  }
  private func drawingTrialGroupHasExposure(
    _ group: AttemptGroupIdentity,
    in session: LearningSessionState
  ) -> Bool {
    session.surfaceExposureLedger.entries.contains { exposure in
      exposure.paperContactPlane.rawValue == session.explorationToolPaperRevision
        && exposure.owner == .drawingTrial(group)
    }
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
  private(set) var quarantinedTipCalibrationCheckpoint: AcceptedTipCalibrationCheckpoint? {
    get { activeLearningSession.quarantinedTipCalibrationCheckpoint }
    set { activeLearningSession.quarantinedTipCalibrationCheckpoint = newValue }
  }
  private(set) var learningAuthorityError: String? {
    get { activeLearningSession.learningAuthorityError }
    set { activeLearningSession.learningAuthorityError = newValue }
  }
  var learningAuthorityManifestError: String? {
    frameMode == .live ? liveLearningAuthorityManifestBlocker : nil
  }
  var learningSurfaceExposureError: String? {
    frameMode == .live
      ? (liveLearningSurfaceExposureBlocker ?? liveTipSurfaceExposureBindingBlocker)
      : nil
  }
  var learningSurfaceExposureLedger: LearningSurfaceExposureLedger {
    surfaceExposureLedger
  }
  var learningSurfaceExposureRecoveryDisposition:
    LearningSurfaceExposureRecoveryDisposition
  {
    guard frameMode == .live else { return .ready }
    if liveTipSurfaceExposureBindingBlocker != nil
      || unmatchedCurrentPaperSparseExposure() != nil
    {
      return .paperReplacementRequired
    }
    return liveLearningSurfaceStoreRecoveryDisposition
  }

  private var liveSparseContactUnavailableReason: String? {
    guard frameMode == .live else { return nil }
    if let blocker = liveLearningAuthorityManifestBlocker {
      return "LIVE contact is blocked by the Learning-authority manifest: \(blocker)"
    }
    guard learningSurfaceExposureRecoveryDisposition == .ready else {
      return "LIVE contact is blocked by the surface-exposure ledger: \(learningSurfaceExposureError ?? "current-paper safety history requires recovery")"
    }
    return nil
  }

  @ObservationIgnored private let machineActions: MachineActions?
  @ObservationIgnored private let cameraActions: CameraActions?
  @ObservationIgnored private let persistPenCapAppearanceSelection:
    @Sendable (PenCapAppearanceSelection?) -> Void
  @ObservationIgnored private let announcementActions: AnnouncementActions?
  /// These ports are capabilities of the LIVE learning session only. The
  /// active accessors deliberately return nil for SIMULATED before any
  /// workflow can load, save, or clear physical durable authority.
  @ObservationIgnored private let liveLearningAuthorityManifestActions:
    LearningAuthorityManifestActions?
  @ObservationIgnored private var liveLearningAuthorityManifestRevision:
    LearningAuthorityStoreRevision = .absent
  @ObservationIgnored private var liveLearningAuthorityManifest: LearningAuthorityManifest =
    try! LearningAuthorityManifest(generation: 0, machine: nil, tip: nil)
  private var liveLearningAuthorityManifestBlocker: String?
  @ObservationIgnored private let liveLearningSurfaceExposureActions:
    LiveLearningSurfaceExposureActions?
  private var liveLearningSurfaceExposureBlocker: String? =
    "LIVE surface-exposure persistence is unavailable."
  private var liveLearningSurfaceStoreRecoveryDisposition:
    LearningSurfaceExposureRecoveryDisposition = .diagnosticsRequired
  private var liveTipSurfaceExposureBindingBlocker: String?
  @ObservationIgnored private var liveLearningSurfaceExposureRevision:
    LiveLearningSurfaceExposureStoreRevision = .absent
  private var activeLearningAuthorityManifestActions: LearningAuthorityManifestActions? {
    frameMode == .live ? liveLearningAuthorityManifestActions : nil
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
  @ObservationIgnored private var stagedPenCapAppearanceCandidate:
    StagedPenCapAppearanceCandidate?
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
  @ObservationIgnored private var penUpFinalizerAttemptOutcomes:
    [LearningSurfaceExposureID: PenOutcome] = [:]
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
    learningAuthorityManifestActions: LearningAuthorityManifestActions? = nil,
    liveLearningSurfaceExposureActions: LiveLearningSurfaceExposureActions? = nil,
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
    loadPenCapAppearanceSelection: @escaping @Sendable () -> PenCapAppearanceSelection? = {
      guard let data = UserDefaults.standard.data(
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
    videoPresentationPreferences = VideoPresentationPreferences(
      cadence: .twoFPS,
      enabledOverlays: loadOverlayPreference() ?? Set(UserSceneOverlay.allCases)
    )
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
    liveLearningAuthorityManifestActions = learningAuthorityManifestActions
    self.liveLearningSurfaceExposureActions = liveLearningSurfaceExposureActions
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
    self.persistOverlayPreference = persistOverlayPreference
    rememberedSerialDeviceIdentifier = loadSelectedSerialIdentifier()
    self.nowNanoseconds = nowNanoseconds
    self.boundaryAtomicCommitFailurePoints = boundaryAtomicCommitFailurePoints
    if let rememberedSerialDeviceIdentifier {
      selectedSerialDevice = serialDevices.first {
        $0.identifier == rememberedSerialDeviceIdentifier
      }
    }
    if let learningAuthorityManifestActions {
      switch learningAuthorityManifestActions.load() {
      case .loaded(let snapshot):
        liveLearningAuthorityManifest = snapshot.manifest
        liveLearningAuthorityManifestRevision = snapshot.revision
        parkedAcceptedMachineArtifactCheckpoint = snapshot.manifest.machine
        quarantinedTipCalibrationCheckpoint = snapshot.manifest.tip
        liveLearningAuthorityManifestBlocker = nil
      case .rejected(let reason, let revision):
        liveLearningAuthorityManifestRevision = revision
        liveLearningAuthorityManifestBlocker = reason
      }
    } else {
      liveLearningAuthorityManifestBlocker =
        "LIVE accepted Learning-authority persistence is unavailable."
    }
    if let liveLearningSurfaceExposureActions {
      switch liveLearningSurfaceExposureActions.load() {
      case .absent:
        liveLearningSurfaceExposureRevision = .absent
        liveLearningSurfaceExposureBlocker = nil
        liveLearningSurfaceStoreRecoveryDisposition = .ready
      case .loaded(let snapshot):
        liveLearningSurfaceExposureRevision = snapshot.revision
        let ledger = snapshot.checkpoint.ledger
        liveLearningSession.surfaceExposureLedger = ledger
        let paper = PaperContactPlaneRevision(
          rawValue: liveLearningSession.explorationToolPaperRevision
        )
        if let unmatched = unmatchedCurrentPaperSparseExposure(
          ledger: ledger,
          checkpoint: liveLearningAuthorityManifest.tip
        ) {
          liveLearningSession.sparseTipCalibrationCoordinator.recordPossibleInk(
            unmatched,
            reason:
              "Durable possible-ink calibration exposure exists on this paper without a current accepted observation. Record paper replacement before calibration continues."
          )
        }
        if snapshot.checkpoint.currentPaperContactPlane == paper {
          liveLearningSurfaceExposureBlocker = nil
          liveLearningSurfaceStoreRecoveryDisposition = .ready
        } else {
          liveLearningSurfaceExposureBlocker =
            "Safety history is bound to a different current paper. Record Paper Replacement before LIVE contact."
          liveLearningSurfaceStoreRecoveryDisposition = .paperReplacementRequired
        }
      case .rejected(let reason, let revision):
        liveLearningSurfaceExposureRevision = revision
        liveLearningSurfaceExposureBlocker = reason
        liveLearningSurfaceStoreRecoveryDisposition = .paperReplacementRequired
      }
    }
    refreshLiveTipSurfaceExposureBindingBlocker()
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

  @discardableResult
  private func commitLearningAuthorityManifest(
    expectedRevision: LearningAuthorityStoreRevision? = nil,
    mutation: LearningAuthorityManifestMutation,
    permitsCorruptReplacement: Bool = false
  ) throws -> LearningAuthorityManifestSnapshot {
    guard frameMode == .live, let actions = activeLearningAuthorityManifestActions else {
      throw LearningPathOperationError.requiredState(
        "LIVE accepted Learning-authority persistence is unavailable."
      )
    }
    if let blocker = liveLearningAuthorityManifestBlocker,
      !(permitsCorruptReplacement && {
        if case .corrupt = liveLearningAuthorityManifestRevision { return true }
        return false
      }())
    {
      throw LearningPathOperationError.requiredState(blocker)
    }
    let revision = expectedRevision ?? liveLearningAuthorityManifestRevision
    let snapshot = try actions.commit(revision, mutation)
    liveLearningAuthorityManifest = snapshot.manifest
    liveLearningAuthorityManifestRevision = snapshot.revision
    liveLearningAuthorityManifestBlocker = nil
    refreshLiveTipSurfaceExposureBindingBlocker()
    return snapshot
  }

  private func refreshLiveTipSurfaceExposureBindingBlocker() {
    guard let checkpoint = liveLearningAuthorityManifest.tip else {
      liveTipSurfaceExposureBindingBlocker = nil
      return
    }
    guard checkpoint.isSurfaceExposureBound(to: liveLearningSession.surfaceExposureLedger) else {
      liveTipSurfaceExposureBindingBlocker =
        "The quarantined tip checkpoint is not cross-bound to its complete durable sparse-mark safety history. Record Paper Replacement before any further contact or Stage 4 drawing."
      return
    }
    liveTipSurfaceExposureBindingBlocker = nil
  }

  private func unmatchedCurrentPaperSparseExposure(
    ledger: LearningSurfaceExposureLedger? = nil,
    checkpoint: AcceptedTipCalibrationCheckpoint? = nil
  ) -> LearningSurfaceExposure? {
    let ledger = ledger ?? liveLearningSession.surfaceExposureLedger
    let checkpoint = checkpoint ?? liveLearningAuthorityManifest.tip
    let paper = PaperContactPlaneRevision(
      rawValue: liveLearningSession.explorationToolPaperRevision
    )
    let trusted = checkpoint.map { Set($0.surfaceExposures) } ?? []
    return ledger.exposures(on: paper).first { exposure in
      guard case .sparseTipMark = exposure.owner else { return false }
      return !trusted.contains(exposure)
        && !currentSparseAttemptRepresents(exposure)
    }
  }

  private func currentSparseAttemptRepresents(
    _ exposure: LearningSurfaceExposure
  ) -> Bool {
    guard case .sparseTipMark(let position) = exposure.owner,
      case .sparseCalibrationCircle(let center, let radiusMM) = exposure.geometry,
      exposure.paperContactPlane.rawValue == explorationToolPaperRevision,
      let finalization = exposure.penUpFinalization,
      finalization.reason == .circleCompleted,
      finalization.outcome
        == .commandedAndSettled(command: .raise, commandedState: .up)
    else { return false }

    func matches(
      position candidatePosition: ToolContactCalibrationPosition,
      geometry: ToolContactMarkGeometryEvidence,
      penUp: PenActuationEvidence,
      paper: PaperContactPlaneRevision
    ) -> Bool {
      candidatePosition == position
        && geometry.center == center
        && geometry.radiusMM == radiusMM
        && penUp.outcome == finalization.outcome
        && paper.rawValue == explorationToolPaperRevision
    }

    if let pending = pendingToolContactEvidence,
      matches(
        position: pending.position,
        geometry: pending.markGeometry,
        penUp: pending.penUp,
        paper: PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
      )
    {
      return true
    }
    return sparseTipCalibrationCoordinator.acceptedObservations.contains {
      matches(
        position: $0.observation.calibrationPosition,
        geometry: $0.observation.markGeometry,
        penUp: $0.observation.penUp,
        paper: $0.observation.paperContactPlane
      )
    }
  }

  private func persistTipCheckpointIfLive(
    _ checkpoint: AcceptedTipCalibrationCheckpoint
  ) throws {
    guard frameMode == .live else { return }
    _ = try commitLearningAuthorityManifest(
      mutation: LearningAuthorityManifestMutation(tip: .replace(checkpoint))
    )
  }

  var actionSurfacePresentation: ActionSurfacePresentation {
    let surfaceFrame = frozenPointSelectionFrame ?? displayedFrame
    let overlayComposition = OverlayPresentationComposer.compose(
      preference: overlayPreferenceState,
      channels: overlayResultChannels,
      displayedFrame: surfaceFrame,
      sceneState: visionAnalysisSnapshot,
      sceneIsAvailable: sceneOverlayIsAvailable,
      workflowVisionIsExclusive: exclusiveWorkflowVisionRequestCount > 0
    )
    let sparseMarkRegion = surfaceFrame.flatMap(sparseTipMarkPresentationRegion)
    let fittedRegion = sparseMarkRegion ?? surfaceFrame.flatMap(learnedBoundsPresentationRegion)
    let viewportContext = surfaceFrame.map {
      ActionSurfaceViewportContext(
        source: $0.source,
        cameraConfigurationID: $0.frame.cameraConfigurationID,
        fittedRegion: fittedRegion
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
      } else if pointSelectionRequest != nil {
        .awaitingClick
      } else if tipCameraRegistration != nil {
        .calibrated(prediction: nil)
      } else {
        .notCalibrated
      }
    return ActionSurfacePresentation(
      displayedFrame: surfaceFrame,
      overlays: overlayComposition.overlays,
      simulatedAnnotations: simulatedAnnotations,
      simulatedViewportID: simulatedViewportID,
      simulatedAnnotationsAreVisible: simulatedAnnotationsAreVisible,
      viewportContext: viewportContext,
      pointSelectionRequest: pointSelectionRequest,
      tipPresentation: tipPresentation
    )
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
      || jogCancelRequestInProgress || motionGuardActivationInProgress
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
    LearningPathProjector().currentItemID(
      learningPathProjectionSnapshot(includeInvalidation: false)
    )
  }

  var learningPathItemPresentations: [LearningPathItemPresentation] {
    learningPathProjection(selectedItemID: currentLearningPathItemID).items
  }

  var invalidateAllLearningPlan: LearningInvalidationPlan? {
    makeLearningInvalidationPlan(scope: .all)
  }

  func learningInvalidationPlan(
    for itemID: LearningPathItemID
  ) -> LearningInvalidationPlan? {
    let tree = LearningPathTree.curriculum
    if tree.isActionableLeaf(itemID) {
      return makeLearningInvalidationPlan(scope: .leaf(root: itemID))
    }
    guard !tree.children(of: itemID).isEmpty else { return nil }
    return makeLearningInvalidationPlan(scope: .subtree(root: itemID))
  }

  var learningInvalidationUnavailableReason: String? {
    if hasShutdown { return "The workspace is shutting down." }
    if activeExerciseAttemptID != nil {
      return "Stop, cancel, or finish the active exercise attempt before invalidating learning."
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
    return nil
  }

  private struct LearningInvalidationDraft {
    var session: LearningSessionState
    var pendingBoundaryFinalPositions: [ExerciseAttemptID: MachinePosition]
    var pendingBoundaryOwnerIDs: [ExerciseAttemptID: BoundaryMotionOwnerID]
    var pendingBoundaryStopCapabilities: [ExerciseAttemptID: ContextualStopCapabilityID]
    var clearsPenCapSelection = false
    var clearsDrawingWorkflowOverlay = false
  }

  private func learningAuthorityDraft(
    graph: LearningDependencyGraph,
    invalidatedRevisionIDs: Set<LearningArtifactRevisionID>,
    forcesFreshLinePlan: Bool = false
  ) -> LearningInvalidationDraft {
    var draft = LearningInvalidationDraft(
      session: activeLearningSession,
      pendingBoundaryFinalPositions: pendingBoundaryFinalPositions,
      pendingBoundaryOwnerIDs: pendingBoundaryOwnerIDs,
      pendingBoundaryStopCapabilities: pendingBoundaryStopCapabilities
    )
    draft.session.learningArtifactGraph = graph

    func setDrawingStepEarlier(_ step: ObservedDrawingTrialStep) {
      if draft.session.drawingTrial.step.rawValue > step.rawValue {
        draft.session.drawingTrial.step = step
      }
    }

    for revisionID in invalidatedRevisionIDs {
      guard let revision = graph.revision(id: revisionID) else { continue }
      switch revision.kind {
      case .penCapAppearance:
        draft.clearsPenCapSelection = true
      case .penInteraction:
        draft.session.penAttemptHistory = try! ExerciseAttemptHistory(
          compatibility: draft.session.penAttemptHistory.compatibility
        )
        draft.session.discoveryTransactions.removeValue(forKey: .penInteraction)
      case .boundarySideAggregate(let direction):
        if let aggregate = draft.session.boundarySideAggregates.removeValue(forKey: direction) {
          for attemptID in aggregate.includedAttemptIDs {
            draft.session.boundaryAttemptEvidenceByAttemptID.removeValue(forKey: attemptID)
            draft.pendingBoundaryFinalPositions.removeValue(forKey: attemptID)
            draft.pendingBoundaryOwnerIDs.removeValue(forKey: attemptID)
            draft.pendingBoundaryStopCapabilities.removeValue(forKey: attemptID)
          }
        }
        draft.session.boundaryAttemptHistories.removeValue(forKey: direction)
        draft.session.discoveryTransactions.removeValue(forKey: sequenceID(for: direction))
        var progress = PairedBoundaryProgress()
        for remainingDirection in draft.session.pairedBoundaryProgress.acceptedDirections {
          guard let aggregate = draft.session.boundarySideAggregates[remainingDirection] else {
            continue
          }
          try? progress.accept(remainingDirection, revisionID: aggregate.revisionID)
        }
        draft.session.pairedBoundaryProgress = progress
      case .estimatedMachineCenter:
        draft.session.estimatedCenterAuthority = nil
        draft.session.centerArrivalPosition = nil
        draft.session.centerArrivalRetryRequired = false
      case .centerArrival:
        draft.session.centerArrivalPosition = nil
        draft.session.centerArrivalRetryRequired = false
      case .machineCameraRegistration:
        draft.session.machineCameraRegistration = nil
        draft.session.proposedMachineCameraRegistration = nil
        draft.session.explicitRegistrationCapAnchorEvidence = []
      case .toolContactObservation:
        var coordinator = SparseTipCalibrationCoordinator()
        let paper = PaperContactPlaneRevision(
          rawValue: draft.session.explorationToolPaperRevision
        )
        if let unmatched = draft.session.surfaceExposureLedger.exposures(on: paper).first(
          where: { exposure in
            if case .sparseTipMark = exposure.owner { return true }
            return false
          })
        {
          coordinator.recordPossibleInk(
            unmatched,
            reason:
              "Possible-ink calibration exposure remains on this paper. Record paper replacement before calibration continues."
          )
        }
        draft.session.sparseTipCalibrationCoordinator = coordinator
        draft.session.toolContactSelection.clear()
      case .tipCameraRegistration:
        draft.session.tipCameraRegistration = nil
        draft.session.proposedTipCameraRegistration = nil
        setDrawingStepEarlier(.chooseIsolatedLinePlan)
      case .linePlan(let group):
        if group == draft.session.drawingTrial.group {
          draft.session.drawingTrial.linePlan = nil
          draft.session.drawingTrial.currentEpisode = nil
        }
        setDrawingStepEarlier(.chooseIsolatedLinePlan)
      case .localPreLineContext(let group):
        if group == draft.session.drawingTrial.group {
          draft.session.drawingTrial.localPreLineContext = nil
        }
        setDrawingStepEarlier(.captureLocalPreLineBaseline)
      case .lineStartArrival(let group):
        if group == draft.session.drawingTrial.group {
          draft.session.drawingTrial.lineStartArrival = nil
          draft.session.lastProtocolPoseSettlement = nil
        }
        setDrawingStepEarlier(.moveToLineStart)
      case .lineExecution(let group):
        if group == draft.session.drawingTrial.group {
          draft.session.drawingTrial.lineExecution = nil
        }
        setDrawingStepEarlier(.drawIsolatedLine)
      case .postLineObservation(let group):
        if group == draft.session.drawingTrial.group {
          draft.session.drawingTrial.postLineObservation = nil
          draft.session.drawingTrial.assessment = nil
          draft.clearsDrawingWorkflowOverlay = true
        }
        setDrawingStepEarlier(.revealAndObserveNewInk)
      case .comparison(let group):
        if group == draft.session.drawingTrial.group {
          draft.session.drawingTrial.assessment = nil
          draft.session.drawingTrial.comparisonAttemptHistories =
            draft.session.drawingTrial.comparisonAttemptHistories.filter {
              $0.key.group != group
            }
        }
        setDrawingStepEarlier(.compareIntendedAndObservedGeometry)
      }
    }
    if forcesFreshLinePlan {
      draft.session.drawingTrial.invalidatePayload(
        from: .chooseIsolatedLinePlan,
        source: frameMode
      )
      draft.session.restartableExerciseItemID = nil
    }
    return draft
  }

  private func installLearningAuthorityDraft(_ draft: LearningInvalidationDraft) {
    activeLearningSession = draft.session
    pendingBoundaryFinalPositions = draft.pendingBoundaryFinalPositions
    pendingBoundaryOwnerIDs = draft.pendingBoundaryOwnerIDs
    pendingBoundaryStopCapabilities = draft.pendingBoundaryStopCapabilities
    if draft.clearsPenCapSelection {
      if frameMode == .live {
        livePenCapAppearanceSelection = nil
        persistedPenCapAppearanceLoadState = .absent
        persistPenCapAppearanceSelection(nil)
      } else {
        simulatedPenCapAppearanceSelection = nil
      }
    }
    if draft.clearsDrawingWorkflowOverlay {
      overlayResultChannels.clearWorkflow(source: frameMode, owner: .observedDrawingTrial)
    }
  }

  @discardableResult
  func performLearningInvalidation(_ plan: LearningInvalidationPlan) -> Bool {
    if let unavailableReason = learningInvalidationUnavailableReason {
      learningAuthorityError = unavailableReason
      return false
    }
    let freshPlan = makeLearningInvalidationPlan(scope: plan.scope)
    guard freshPlan == plan else {
      learningAuthorityError =
        "Learning authority changed while the invalidation summary was open. Review it and try again."
      return false
    }
    if let invariantError = learningAuthorityInvariantError() {
      learningAuthorityError = "Learning authority is inconsistent: \(invariantError)"
      return false
    }

    let rootKinds = learningInvalidationRootKinds(for: plan.scope)
    let forcesFreshLinePlan = invalidationForcesFreshLinePlan(plan.scope)
    var preview = learningArtifactGraph
    let previewInvalidation = preview.invalidateCurrentRevisions(rootKinds: rootKinds)
    guard previewInvalidation.allInvalidatedRevisionIDs == plan.expectedCurrentRevisionIDs else {
      learningAuthorityError =
        "Learning authority changed while the invalidation roots were being resolved. Review it and try again."
      return false
    }

    // Build one pure graph+payload draft before touching durable state. Drafting
    // cannot persist preferences, clear overlays, or consume pending controller
    // audit maps.
    var graph = learningArtifactGraph
    let invalidation = graph.invalidateCurrentRevisions(rootKinds: rootKinds)
    var draft = learningAuthorityDraft(
      graph: graph,
      invalidatedRevisionIDs: invalidation.allInvalidatedRevisionIDs,
      forcesFreshLinePlan: forcesFreshLinePlan
    )
    draft.session.exerciseAttempt.finish()
    draft.session.restartableExerciseItemID = nil
    draft.session.explorationError = nil
    if plan.removesDurableMachineRegistration {
      draft.session.parkedAcceptedMachineArtifactCheckpoint = nil
    }
    if plan.removesDurableTipRegistration {
      draft.session.quarantinedTipCalibrationCheckpoint = nil
    }
    if let invariantError = learningAuthorityInvariantError(
      session: draft.session,
      penCapSelectionIsPresent:
        !draft.clearsPenCapSelection && penCapAppearanceSelection != nil
    ) {
      learningAuthorityError = "Learning invalidation was refused: \(invariantError)"
      return false
    }

    if plan.removesDurableMachineRegistration || plan.removesDurableTipRegistration {
      guard frameMode == .live,
        let expectedRevision = plan.expectedAuthorityManifestRevision
      else {
        learningAuthorityError =
          "The durable Learning-authority manifest is unavailable for this invalidation."
        return false
      }
      let mutation: LearningAuthorityManifestMutation
      if case .corrupt = expectedRevision {
        // A corrupt manifest has no trustworthy field boundary. Explicit
        // in-scope cleanup replaces the whole accepted-authority generation.
        mutation = LearningAuthorityManifestMutation(
          machine: .replace(nil),
          tip: .replace(nil)
        )
      } else {
        mutation = LearningAuthorityManifestMutation(
          machine: plan.removesDurableMachineRegistration ? .replace(nil) : .preserve,
          tip: plan.removesDurableTipRegistration ? .replace(nil) : .preserve
        )
      }
      do {
        _ = try commitLearningAuthorityManifest(
          expectedRevision: expectedRevision,
          mutation: mutation,
          permitsCorruptReplacement: true
        )
      } catch {
        learningAuthorityError =
          "Learning-authority manifest invalidation failed safely: \(error)"
        return false
      }
    }

    installLearningAuthorityDraft(draft)
    learningAuthorityError = nil
    return true
  }

  private func makeLearningInvalidationPlan(
    scope: LearningInvalidationScope
  ) -> LearningInvalidationPlan? {
    let tree = LearningPathTree.curriculum
    let directLeaves = directLearningInvalidationLeaves(for: scope)
    let forcesFreshLinePlan = invalidationForcesFreshLinePlan(scope)
    let rootKinds = learningInvalidationRootKinds(for: scope)
    var preview = learningArtifactGraph
    let invalidation = preview.invalidateCurrentRevisions(rootKinds: rootKinds)
    let invalidatedRevisionIDs = invalidation.allInvalidatedRevisionIDs

    var affected = Set(directLeaves)
    for revisionID in invalidatedRevisionIDs {
      guard let kind = learningArtifactGraph.revision(id: revisionID)?.kind,
        let itemID = learningPathItemID(for: kind)
      else { continue }
      affected.insert(itemID)
    }
    let rootKindsActuallyPresent = Set(invalidation.rootInvalidatedRevisionIDs.compactMap {
      learningArtifactGraph.revision(id: $0)?.kind
    })
    let scopeIncludesMachine = directLeaves.contains(
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    )
    let manifestIsCorrupt: Bool = {
      if case .corrupt = liveLearningAuthorityManifestRevision { return true }
      return false
    }()
    let hasDurableMachine = liveLearningAuthorityManifest.machine != nil
    let hasDurableTip = liveLearningAuthorityManifest.tip != nil
    let removesMachine = rootKindsActuallyPresent.contains { kind in
      switch kind {
      case .boundarySideAggregate, .estimatedMachineCenter, .centerArrival: true
      default: false
      }
    } || (frameMode == .live && scopeIncludesMachine && (hasDurableMachine || manifestIsCorrupt))
    let scopeIncludesTipLineage = directLeaves.contains { itemID in
      guard case .humanGuidedDiscovery = itemID else { return false }
      return true
    }
    let removesTip = invalidatedRevisionIDs.contains { revisionID in
      learningArtifactGraph.revision(id: revisionID)?.kind == .tipCameraRegistration
    } || (frameMode == .live && scopeIncludesTipLineage && (hasDurableTip || manifestIsCorrupt))
    let clearsCorruptManifest = frameMode == .live && manifestIsCorrupt
      && (scopeIncludesMachine || scopeIncludesTipLineage)
    let removesMachineManifestField = removesMachine || clearsCorruptManifest
    let removesTipManifestField = removesTip || clearsCorruptManifest
    if removesTip {
      affected.insert(.humanGuidedDiscovery(.calibratePenContactFromSparseMarks))
    }
    if removesMachineManifestField {
      affected.insert(.humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering))
    }
    if removesTipManifestField {
      affected.insert(.humanGuidedDiscovery(.calibratePenContactFromSparseMarks))
    }
    let finalOrderedAffected = tree.flattenedItems.filter(affected.contains)
    guard !invalidatedRevisionIDs.isEmpty || removesMachineManifestField
      || removesTipManifestField || forcesFreshLinePlan
    else { return nil }
    return LearningInvalidationPlan(
      scope: scope,
      source: frameMode == .live ? .live : .simulated,
      affectedItemIDs: finalOrderedAffected,
      expectedCurrentRevisionIDs: invalidatedRevisionIDs,
      expectedGraphRevision: learningArtifactGraph.revision,
      expectedAcceptedAttemptSequence: acceptedAttemptSequence,
      expectedAuthorityManifestRevision:
        removesMachineManifestField || removesTipManifestField
        ? liveLearningAuthorityManifestRevision : nil,
      removesDurableMachineRegistration:
        frameMode == .live && removesMachineManifestField
          && liveLearningAuthorityManifestActions != nil,
      removesDurableTipRegistration:
        frameMode == .live && removesTipManifestField
          && liveLearningAuthorityManifestActions != nil,
      physicalInkMayRemain:
        surfaceExposureLedger.exposures(
          on: PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
        ).contains { exposure in
          guard exposure.provenance == .livePossiblePhysicalInk else { return false }
          if scope == .all { return true }
          switch exposure.owner {
          case .sparseTipMark:
            return finalOrderedAffected.contains(
              .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
            )
          case .drawingTrial(let group):
            return (forcesFreshLinePlan && group == currentDrawingTrialGroup)
              || invalidatedRevisionIDs.contains { revisionID in
              guard let kind = learningArtifactGraph.revision(id: revisionID)?.kind else {
                return false
              }
              switch kind {
              case .linePlan(let artifactGroup), .localPreLineContext(let artifactGroup),
                .lineStartArrival(let artifactGroup), .lineExecution(let artifactGroup),
                .postLineObservation(let artifactGroup), .comparison(let artifactGroup):
                return group == artifactGroup
              default:
                return false
              }
            }
          }
        }
    )
  }

  private func directLearningInvalidationLeaves(
    for scope: LearningInvalidationScope
  ) -> [LearningPathItemID] {
    let tree = LearningPathTree.curriculum
    return switch scope {
    case .leaf(let root): [root]
    case .subtree(let root): tree.descendantLeaves(of: root)
    case .all: tree.flattenedItems.filter(tree.isActionableLeaf)
    }
  }

  private func invalidationForcesFreshLinePlan(
    _ scope: LearningInvalidationScope
  ) -> Bool {
    guard currentDrawingTrialGroupHasExposure else { return false }
    return directLearningInvalidationLeaves(for: scope).contains { itemID in
      guard case .observedDrawingTrial(let step) = itemID else { return false }
      return switch step {
      case .chooseIsolatedLinePlan, .captureLocalPreLineBaseline, .moveToLineStart,
        .drawIsolatedLine:
        true
      case .revealAndObserveNewInk, .compareIntendedAndObservedGeometry:
        false
      }
    }
  }

  private func learningInvalidationRootKinds(
    for scope: LearningInvalidationScope
  ) -> Set<LearningArtifactKind> {
    var kinds = Set(
      directLearningInvalidationLeaves(for: scope).flatMap(learningArtifactKindsOwned)
    )
    if invalidationForcesFreshLinePlan(scope) {
      kinds.formUnion(drawingArtifactKinds(for: currentDrawingTrialGroup))
    }
    return kinds
  }

  private func learningArtifactKindsOwned(
    by itemID: LearningPathItemID
  ) -> [LearningArtifactKind] {
    switch itemID {
    case .stage(.connect), .stage(.enableMotion), .stage(.humanGuidedDiscovery),
      .stage(.observedDrawingTrials):
      []
    case .humanGuidedDiscovery(.penInteraction):
      [.penCapAppearance, .penInteraction]
    case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
      BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
        + [.estimatedMachineCenter, .centerArrival]
    case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
      [.machineCameraRegistration]
    case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
      learningArtifactGraph.revisions.compactMap { revision -> LearningArtifactKind? in
        guard revision.state == .current else { return nil }
        switch revision.kind {
        case .toolContactObservation, .tipCameraRegistration: return revision.kind
        default: return nil
        }
      }
    case .observedDrawingTrial(.chooseIsolatedLinePlan):
      [.linePlan(currentDrawingTrialGroup)]
    case .observedDrawingTrial(.captureLocalPreLineBaseline):
      [.localPreLineContext(currentDrawingTrialGroup)]
    case .observedDrawingTrial(.moveToLineStart):
      [.lineStartArrival(currentDrawingTrialGroup)]
    case .observedDrawingTrial(.drawIsolatedLine):
      [.lineExecution(currentDrawingTrialGroup)]
    case .observedDrawingTrial(.revealAndObserveNewInk):
      [.postLineObservation(currentDrawingTrialGroup)]
    case .observedDrawingTrial(.compareIntendedAndObservedGeometry):
      [.comparison(currentDrawingTrialGroup)]
    }
  }

  /// Exhaustive current-subject/current-payload invariant. Candidate proposals,
  /// Preferences and histories are not authority; retained surface exposure is
  /// separate safety authority and is never cleared by graph invalidation.
  private func learningAuthorityInvariantError() -> String? {
    learningAuthorityInvariantError(
      session: activeLearningSession,
      penCapSelectionIsPresent: penCapAppearanceSelection != nil
    )
  }

  private func learningAuthorityInvariantError(
    session: LearningSessionState,
    penCapSelectionIsPresent: Bool
  ) -> String? {
    func hasCurrent(_ kind: LearningArtifactKind) -> Bool {
      session.learningArtifactGraph.currentRevision(for: kind) != nil
    }
    for revision in session.learningArtifactGraph.revisions where revision.state == .current {
      let hasPayload: Bool = switch revision.kind {
      case .penCapAppearance:
        penCapSelectionIsPresent
      case .penInteraction:
        !session.penAttemptHistory.includedSuccessfulAttempts.isEmpty
      case .boundarySideAggregate(let direction):
        session.boundarySideAggregates[direction]?.revisionID == revision.id
      case .estimatedMachineCenter:
        session.estimatedCenterAuthority != nil
      case .centerArrival:
        session.centerArrivalPosition != nil
      case .machineCameraRegistration:
        session.machineCameraRegistration != nil
      case .toolContactObservation(let observationID):
        session.sparseTipCalibrationCoordinator.acceptedObservations.contains {
          $0.observation.id == observationID && $0.artifactRevisionID == revision.id
        }
      case .tipCameraRegistration:
        session.tipCameraRegistration?.acceptedRevisionID == revision.id
      case .linePlan(let group):
        group == session.drawingTrial.group && session.drawingTrial.linePlan != nil
      case .localPreLineContext(let group):
        group == session.drawingTrial.group
          && session.drawingTrial.localPreLineContext != nil
      case .lineStartArrival(let group):
        group == session.drawingTrial.group
          && session.drawingTrial.lineStartArrival != nil
      case .lineExecution(let group):
        group == session.drawingTrial.group
          && session.drawingTrial.lineExecution != nil
      case .postLineObservation(let group):
        group == session.drawingTrial.group
          && session.drawingTrial.postLineObservation?.observation.residual != nil
      case .comparison(let group):
        group == session.drawingTrial.group && session.drawingTrial.assessment != nil
      }
      if !hasPayload { return "current revision \(revision.kind) has no exact payload" }
    }

    if !session.penAttemptHistory.includedSuccessfulAttempts.isEmpty, !hasCurrent(.penInteraction) {
      return "accepted pen-interaction payload has no current revision"
    }
    for (direction, aggregate) in session.boundarySideAggregates
    where session.learningArtifactGraph.currentRevision(for: .boundarySideAggregate(direction))?.id
      != aggregate.revisionID
    {
      return "accepted boundary payload \(direction) has no matching current revision"
    }
    if session.estimatedCenterAuthority != nil,
      !hasCurrent(.estimatedMachineCenter)
    {
      return "estimated-center payload has no current revision"
    }
    if session.centerArrivalPosition != nil, !hasCurrent(.centerArrival) {
      return "center-arrival payload has no current revision"
    }
    if session.machineCameraRegistration != nil, !hasCurrent(.machineCameraRegistration) {
      return "machine-camera payload has no current revision"
    }
    for accepted in session.sparseTipCalibrationCoordinator.acceptedObservations
    where session.learningArtifactGraph.currentRevision(
      for: .toolContactObservation(accepted.observation.id)
    )?.id != accepted.artifactRevisionID
    {
      return "accepted tool-contact payload has no matching current revision"
    }
    if session.tipCameraRegistration != nil, !hasCurrent(.tipCameraRegistration) {
      return "tip-camera payload has no current revision"
    }
    let group = session.drawingTrial.group
    let drawingPairs: [(Bool, LearningArtifactKind)] = [
      (session.drawingTrial.linePlan != nil, .linePlan(group)),
      (session.drawingTrial.localPreLineContext != nil, .localPreLineContext(group)),
      (session.drawingTrial.lineStartArrival != nil, .lineStartArrival(group)),
      (session.drawingTrial.lineExecution != nil, .lineExecution(group)),
      (session.drawingTrial.postLineObservation != nil, .postLineObservation(group)),
      (session.drawingTrial.assessment != nil, .comparison(group)),
    ]
    if let missing = drawingPairs.first(where: { $0.0 && !hasCurrent($0.1) })?.1 {
      return "authoritative drawing payload \(missing) has no current revision"
    }
    return nil
  }

  private func learningPathItemID(for kind: LearningArtifactKind) -> LearningPathItemID? {
    switch kind {
    case .penCapAppearance, .penInteraction:
      .humanGuidedDiscovery(.penInteraction)
    case .boundarySideAggregate, .estimatedMachineCenter, .centerArrival:
      .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
    case .machineCameraRegistration:
      .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    case .toolContactObservation, .tipCameraRegistration:
      .humanGuidedDiscovery(.calibratePenContactFromSparseMarks)
    case .linePlan:
      .observedDrawingTrial(.chooseIsolatedLinePlan)
    case .localPreLineContext:
      .observedDrawingTrial(.captureLocalPreLineBaseline)
    case .lineStartArrival:
      .observedDrawingTrial(.moveToLineStart)
    case .lineExecution:
      .observedDrawingTrial(.drawIsolatedLine)
    case .postLineObservation:
      .observedDrawingTrial(.revealAndObserveNewInk)
    case .comparison:
      .observedDrawingTrial(.compareIntendedAndObservedGeometry)
    }
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
    videoPresentationPreferences.selectCadence(cadence)
    await reconcileAutomaticVisionAnalysis()
  }

  func lockVideoAnalysisToCurrentView(
    for displayedFrame: DisplayedFrame
  ) async {
    guard let captured = videoPresentationPreferences.lockVisibleRect(for: displayedFrame) else {
      cameraError = "The current full-frame or stale view cannot be locked for analysis."
      return
    }
    await cameraActions?.setSceneAnalysisRegion(frameMode == .live ? captured : nil)
    cameraError = nil
    await reconcileAutomaticVisionAnalysis()
  }

  func unlockVideoAnalysisView(for displayedFrame: DisplayedFrame) async {
    guard videoAnalysisRegionLock?.matches(displayedFrame) == true else { return }
    videoPresentationPreferences.unlockAnalysisROI()
    await cameraActions?.setSceneAnalysisRegion(nil)
    await reconcileAutomaticVisionAnalysis()
  }

  var currentExerciseActionStripPresentation: ExerciseActionStripPresentation? {
    learningPathProjection(selectedItemID: currentLearningPathItemID).selectedAction.actionStrip
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
      learningPathProjectionSnapshot(includeInvalidation: true),
      selectedItemID: selectedItemID
    )
  }

  private func learningPathProjectionSnapshot(
    includeInvalidation: Bool
  ) -> LearningPathProjectionSnapshot {
    let completedDrawingSteps = Set(ObservedDrawingTrialStep.allCases.filter {
      learningArtifactGraph.currentRevision(for: drawingArtifactKind(for: $0)) != nil
    })
    let stopOwner: LearningPathProjectionSnapshot.StopOwner? = {
      guard let target = activeStopTarget else { return nil }
      switch target {
      case .pairedBoundary(let id, let transactionID, _, _, let direction):
        let sequence = sequenceID(for: direction)
        guard discoveryTransactions[sequence]?.id == transactionID,
          case .awaitContextualStop(direction) = discoveryTransactions[sequence]?.currentStep?.action
        else { return nil }
        return .pairedBoundary(id, direction)
      case .manualJog(let id, _): return .manualJog(id)
      case .manualDrawingStroke(let id, _): return .manualDrawing(id)
      case .exerciseMotion(let id, let owner, _, let action):
        return .exercise(id, action, boundaryOwner: owner.isBoundaryOwner)
      case .drawingTrial(let id, _): return .drawingTrial(id)
      case .sparseTipMark(let id, _, _): return .sparseTipMark(id)
      }
    }()
    let itemStartReasons = Dictionary(
      uniqueKeysWithValues: LearningPathTree.curriculum.flattenedItems.compactMap {
        itemID -> (LearningPathItemID, String)? in
        let reason: String?
        switch itemID {
        case .humanGuidedDiscovery(.penInteraction):
          reason = discoveryStartUnavailableReason(for: .penInteraction)
        case .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering):
          reason = discoveryStartUnavailableReason(for: sequenceID(for: selectedBoundaryDirection))
        case .humanGuidedDiscovery(.calibrateCameraAndVisibleCap):
          reason = frameMode == .simulated || cameraIsLive
            ? nil : "A current LIVE camera frame is required."
        case .humanGuidedDiscovery(.calibratePenContactFromSparseMarks):
          if let blocker = liveSparseContactUnavailableReason {
            reason = blocker
          } else {
            reason = frameMode == .simulated || cameraIsLive
              ? nil : "A current LIVE camera frame is required."
          }
        case .observedDrawingTrial(let step):
          reason = drawingTrialActionUnavailableReason(for: step)
        case .stage:
          reason = nil
        }
        return reason.map { (itemID, $0) }
      }
    )
    let invalidationFacts: LearningPathProjectionSnapshot.InvalidationFacts
    if includeInvalidation {
      let plans = Dictionary(
        uniqueKeysWithValues: LearningPathTree.curriculum.flattenedItems.compactMap { itemID in
          learningInvalidationPlan(for: itemID).map { (itemID, $0) }
        }
      )
      invalidationFacts = .init(
        plansByRoot: plans,
        invalidateAllPlan: invalidateAllLearningPlan,
        unavailableReason: learningInvalidationUnavailableReason
      )
    } else {
      invalidationFacts = .init()
    }
    let savedCheckpointMatchesPaper = quarantinedTipCalibrationCheckpoint.map {
      $0.registration.applicability.paperContactPlane.rawValue
        == explorationToolPaperRevision
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
        machineError: controllerAttentionText
      ),
      boundary: .init(
        acceptedDirections: pairedBoundaryProgress.acceptedDirections,
        allowedDirections: pairedBoundaryProgress.allowedDirections,
        isComplete: pairedBoundaryProgress.isComplete,
        estimatedCenter: estimatedMachineCenter,
        centerArrival: centerArrivalPosition,
        centerArrivalRetryRequired: centerArrivalRetryRequired
      ),
      cameraCalibration: .init(
        acceptedIsCurrent: machineCameraRegistration != nil
          && learningArtifactGraph.currentRevision(for: .machineCameraRegistration) != nil,
        hasProposal: proposedMachineCameraRegistration != nil,
        phase: currentCameraCalibrationPhase
      ),
      sparseCalibration: .init(
        acceptedIsCurrent:
          tipCameraRegistration.map {
            learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
              == $0.acceptedRevisionID
          } ?? false,
        phase: sparseTipCalibrationCoordinator.phase,
        savedCheckpointMatchesPaper: savedCheckpointMatchesPaper,
        requiresPaperReplacement:
          learningSurfaceExposureRecoveryDisposition == .paperReplacementRequired,
        paperReplacementUnavailableReason:
          frameMode == .live
            && learningSurfaceExposureRecoveryDisposition == .diagnosticsRequired
          ? (learningSurfaceExposureError
            ?? "LIVE safety-history persistence is unavailable.")
          : nil
      ),
      drawing: .init(
        currentStep: observedDrawingTrialStep,
        completedArtifactSteps: completedDrawingSteps,
        selectedDirection: selectedLineDirection,
        assessment: drawingTrialAssessment,
        currentGroupHasExposure: currentDrawingTrialGroupHasExposure
      ),
      operations: .init(
        activeAttemptOwner: activeExerciseAttemptOwnerID,
        restartableItem: restartableExerciseItemID,
        stopOwner: stopOwner,
        stopDispositionLatched: stopDispositionLatch != nil,
        stickyAmbiguityReason: learningStickyAmbiguityReason,
        explorationFailure: explorationError.map(WorkflowFailure.failed),
        discoveryFailure: discoveryError.map(WorkflowFailure.failed)
      ),
      discovery: discoveryTransactions.mapValues { transaction in
        LearningPathProjectionSnapshot.DiscoveryFacts(
          state: transaction.state,
          currentStep: transaction.currentStep
        )
      },
      startUnavailableReasons: itemStartReasons,
      invalidation: invalidationFacts
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
      case .linePlan: selectedLineDirection = direction
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
    case .stopAndAcceptBoundary(let capabilityID):
      guard ownerID == activeExerciseAttemptOwnerID else { return }
      await terminateBoundary(.stopAndAccept, capabilityID: capabilityID)
    case .stop(let capabilityID):
      guard ownerID == activeExerciseAttemptOwnerID else { return }
      await stopCurrentOperation(capabilityID: capabilityID)
    case .cancel(let capabilityID):
      guard ownerID == activeExerciseAttemptOwnerID else { return }
      await terminateBoundary(.cancelAttempt, capabilityID: capabilityID)
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
    await beginPenInteraction(mode: .normal)
  }

  private func beginPenInteraction(mode: ExerciseAttemptMode) async {
    guard discoveryStartUnavailableReason(for: .penInteraction) == nil else { return }
    cancelPenCapAcceptedClickContinuation()
    stagedPenCapAppearanceCandidate = nil
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
        visionError = nil
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
      discoveryError = "Identify Pen Cap could not freeze an exact frame: \(actionableDescription(error))"
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
      var draft = learningAuthorityDraft(
        graph: graph,
        invalidatedRevisionIDs: commit.invalidatedRevisionIDs
      )
      draft.session.centerArrivalPosition = destination
      draft.session.centerArrivalRetryRequired = false
      draft.session.explorationError = nil
      draft.session.exerciseAttempt.finish()
      let checkpoint = frameMode == .live
        ? try acceptedMachineCheckpoint(for: draft.session) : nil
      if let checkpoint {
        draft.session.parkedAcceptedMachineArtifactCheckpoint = checkpoint
        draft.session.quarantinedTipCalibrationCheckpoint = nil
      }
      if let invariantError = learningAuthorityInvariantError(
        session: draft.session,
        penCapSelectionIsPresent: penCapAppearanceSelection != nil
      ) {
        throw LearningPathOperationError.requiredState(invariantError)
      }
      if let checkpoint {
        _ = try commitLearningAuthorityManifest(
          mutation: LearningAuthorityManifestMutation(
            machine: .replace(checkpoint),
            tip: .replace(nil)
          )
        )
      }
      installLearningAuthorityDraft(draft)
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
    newerThan captureNanoseconds: UInt64 = 0,
    using session: LearningSessionState? = nil
  ) async throws -> SimulatedLearningSceneFrame {
    let authority = session ?? activeLearningSession
    let acceptedPositions = Dictionary(
      uniqueKeysWithValues: authority.boundarySideAggregates.compactMap {
        direction, aggregate -> (BoundaryDirection, SimulatedLearningMPos)? in
        guard let attemptID = aggregate.includedAttemptIDs.last,
          let evidence = authority.boundaryAttemptEvidenceByAttemptID[attemptID],
          let position = try? SimulatedLearningMPos(
            xMM: evidence.finalPosition.point.x,
            yMM: evidence.finalPosition.point.y
          )
        else { return nil }
        return (direction, position)
      })
    let learnedCenter = authority.estimatedCenterAuthority.flatMap {
      try? SimulatedLearningMPos(xMM: $0.center.point.x, yMM: $0.center.point.y)
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
      let penCapAppearance = learningArtifactGraph.currentRevision(for: .penCapAppearance)?.id,
      let registration = proposedMachineCameraRegistration
    else { return }
    do {
      var graph = learningArtifactGraph
      let machineRegistrationCandidate = LearningArtifactRevision(
        kind: .machineCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [centerArrival, penCapAppearance]
      )
      let machineRegistration = try graph.commitReplacement(machineRegistrationCandidate)
      var draft = learningAuthorityDraft(
        graph: graph,
        invalidatedRevisionIDs: machineRegistration.invalidatedRevisionIDs
      )
      draft.session.machineCameraRegistration = registration
      draft.session.proposedMachineCameraRegistration = nil
      draft.session.explicitRegistrationCapAnchorEvidence =
        registration.fitCorrespondenceProvenance
        + registration.holdoutCorrespondenceProvenance
      draft.session.exerciseAttempt.finish()
      draft.session.explorationError = nil
      let invalidatesCurrentTip = machineRegistration.invalidatedRevisionIDs.contains {
        graph.revision(id: $0)?.kind == .tipCameraRegistration
      }
      let clearsDurableTip = frameMode == .live
        && (activeExerciseAttemptMode == .replacement || invalidatesCurrentTip)
      if clearsDurableTip {
        draft.session.quarantinedTipCalibrationCheckpoint = nil
      }
      if let invariantError = learningAuthorityInvariantError(
        session: draft.session,
        penCapSelectionIsPresent: penCapAppearanceSelection != nil
      ) {
        throw LearningPathOperationError.requiredState(invariantError)
      }
      if clearsDurableTip {
        _ = try commitLearningAuthorityManifest(
          mutation: LearningAuthorityManifestMutation(tip: .replace(nil))
        )
      }
      installLearningAuthorityDraft(draft)
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
      cameraCalibrationAnchorFrame != nil,
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
    let acceptedFallbackRemainsCurrent = machineCameraRegistration != nil
      && learningArtifactGraph.currentRevision(for: .machineCameraRegistration) != nil
    currentCameraCalibrationFailure = nil
    cameraCalibrationAnchorFrame = nil
    cameraCalibrationReferencePosition = nil
    cameraCalibrationReferenceCapAnchor = nil
    proposedMachineCameraRegistration = nil
    finishActiveExerciseAttempt(disposition: .cancelled)
    explorationError = acceptedFallbackRemainsCurrent
      ? "Operator rejected the replacement cap map. The prior accepted machine-camera registration remains current."
      : "Operator rejected the staged five-sample cap map. No machine-camera revision became authoritative."
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
        let source: OperatorFrameMode = learned.source == .simulated ? .simulated : .live
        guard source == frameMode else {
          throw PenCapAppearanceSamplingError.staleExactFrame
        }
        stagedPenCapAppearanceCandidate = StagedPenCapAppearanceCandidate(
          attemptID: attemptID,
          attemptMode: attemptMode,
          source: source,
          selection: learned
        )
        penCapAppearanceSelectionContext = nil
        discoveryError = nil
        startPenCapAcceptedClickContinuation(
          attemptID: attemptID,
          attemptMode: attemptMode,
          source: source,
          selection: learned,
          configuresLiveVision: source == .live
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
      guard activeLearningSession.toolContactSelection.select(selection.point) else {
        throw SparseTipCalibrationCoordinatorError.staleSelection
      }
      explorationError = nil
    } catch {
      explorationError =
        "Sparse mark selection was rejected as stale: \(actionableDescription(error))"
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
      stagedPenCapAppearanceCandidate
        == StagedPenCapAppearanceCandidate(
          attemptID: identity.attemptID,
          attemptMode: identity.attemptMode,
          source: identity.source,
          selection: identity.selection
        ),
      penCapAppearanceSelectionContext == nil
    else { return false }
    return true
  }

  private var penCapAppearanceCandidateForActiveAttempt: PenCapAppearanceSelection? {
    guard let candidate = stagedPenCapAppearanceCandidate,
      candidate.attemptID == activeExerciseAttemptID,
      candidate.attemptMode == activeExerciseAttemptMode,
      candidate.source == frameMode,
      activeExerciseAttemptOwnerID == .humanGuidedDiscovery(.penInteraction)
    else { return nil }
    return candidate.selection
  }

  private func discardStagedPenCapAppearanceCandidate() async {
    guard let candidate = stagedPenCapAppearanceCandidate else { return }
    stagedPenCapAppearanceCandidate = nil
    guard candidate.source == .live else { return }
    if let accepted = livePenCapAppearanceSelection {
      await cameraActions?.setPenCapColor(accepted.color)
    }
    await reconcileAutomaticVisionAnalysis()
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

  private func createNextSparseTipMark() async {
    if let blocker = liveSparseContactUnavailableReason {
      explorationError = blocker
      return
    }
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

    var activeExposure: LearningSurfaceExposure?
    do {
      let position = try sparseTipCalibrationCoordinator.prepareNextMark(
        excluding: reservedSparseTipPositionsOnCurrentPaper
      )
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
      let current = try currentMachinePosition()
      let settled: MachinePosition
      if let delta = try Self.supervisedTravelDelta(
        from: current,
        to: sample.machinePosition
      ) {
        settled = try await performSupervisedPenUpTravel(
          delta: delta,
          ownerID: ownerID,
          action: .sparseTipApproach(position)
        )
      } else {
        settled = current
      }
      guard
        recordProtocolPoseSettlement(
          action: .sparseTipApproach(position),
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
        action: .sparseTipCircleStart(position)
      )
      guard
        recordProtocolPoseSettlement(
          action: .sparseTipCircleStart(position),
          target: markPlan.startPosition,
          actual: markStartSettled
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Sparse circle start did not settle within 0.05 mm."
        )
      }
      let exposure = try reserveLearningSurfaceExposure(
        owner: .sparseTipMark(position),
        geometry: .sparseCalibrationCircle(
          center: sample.machinePosition,
          radiusMM: SparseTipCircularMarkPlan.radiusMM
        )
      )
      activeExposure = exposure
      try sparseTipCalibrationCoordinator.beganMark(at: position)
      let mark = try await performCircularContactMark(
        plan: markPlan,
        exposure: exposure,
        after: exactPreFrame.captureNanoseconds
      )

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
          action: .sparseTipReveal(position)
        )
      } else {
        revealSettled = mark.finalPosition
      }
      guard
        recordProtocolPoseSettlement(
          action: .sparseTipReveal(position),
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
      let pendingEvidence = PendingToolContactEvidence(
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
      let selectionRequest = ActionSurfacePointSelectionRequest(
        frame: exactRevealFrame,
        presentationTransformRevision: PresentationTransformRevision(),
        prompt: "Click the center of the new black circle"
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
      if let activeExposure {
        sparseTipCalibrationCoordinator.recordPossibleInk(
          activeExposure,
          reason: failure.detail
        )
      } else {
        sparseTipCalibrationCoordinator.resetBeforeInkFailure()
      }
      activeLearningSession.toolContactSelection.clear()
      explorationError =
        "Sparse tip calibration stopped without automatic retry: \(failure.detail)"
    }
  }

  private func performCircularContactMark(
    plan: SparseTipCircularMarkPlan,
    exposure: LearningSurfaceExposure,
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
      case .ambiguous(let ambiguity):
        let recovery = await finalizePenUp(
          for: exposure.id,
          reason: .penLowerTerminal
        )
        throw LearningPathOperationError.possibleInk(
          "Pen Down was ambiguous: \(ambiguity.actionableDescription) Pen-Up recovery: \(recovery.outcome). \(recovery.audit)"
        )
      case .refused(let refusal):
        _ = await finalizePenUp(for: exposure.id, reason: .penLowerTerminal)
        throw LearningPathOperationError.controllerRefused(refusal.actionableDescription)
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
    var penUpAlreadyAttempted = false
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
            exposureID: exposure.id
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
            let recovery = await finalizePenUp(
              for: exposure.id,
              reason: .drawingStrokeAdmissionRejected
            )
            penUpAlreadyAttempted = true
            throw LearningPathOperationError.possibleInk(
              "A calibration-circle stroke was not admitted after Pen Down: \(outcome). Pen-Up recovery: \(recovery.outcome). \(recovery.audit)"
            )
          }
          let target = ContextualStopTarget.sparseTipMark(
            capabilityID: ContextualStopCapabilityID(),
            operationOwner: .liveOperation(operation.id),
            exposureID: exposure.id
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
            _ = await finalizePenUp(
              for: exposure.id,
              reason: .drawingStrokeCancelled,
              suppliedOutcome: penRaiseOutcome
            )
            penUpAlreadyAttempted = true
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
      if !penUpAlreadyAttempted {
        _ = await finalizePenUp(
          for: exposure.id,
          reason: .circleDrawingFailed
        )
      }
      throw error
    }

    let finalization = await finalizePenUp(
      for: exposure.id,
      reason: .circleCompleted
    )
    guard finalization.persistence.isDurable else {
      throw LearningPathOperationError.requiredState(
        "The circle completed, but its Pen-Up recovery audit is not durable: \(finalization.audit)"
      )
    }
    let raise = finalization.outcome
    guard case .commandedAndSettled(command: .raise, commandedState: .up) = raise else {
      throw operationError(for: raise, possibleInk: true)
    }
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

  private func reClickSparseTipFrame() {
    do {
      try sparseTipCalibrationCoordinator.reClickSameFrame()
      guard activeLearningSession.toolContactSelection.clearPoint() else {
        throw SparseTipCalibrationCoordinatorError.staleSelection
      }
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
        activeLearningSession.toolContactSelection.clear()
        finishActiveExerciseAttempt(disposition: .succeeded)
        explorationError = nil
        return
      }
      sparseTipCalibrationCoordinator = coordinator
      learningArtifactGraph = graph
      activeLearningSession.toolContactSelection.clear()
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
    let acceptedRevisionID = LearningArtifactRevisionID()
    let acceptedAt = RuntimeTimestamp(
      monotonicNanoseconds: max(
        nowNanoseconds(),
        revalidationTimestamp.monotonicNanoseconds + 1
      )
    )
    let restored = try checkpoint.registration.revalidatedSummaryFromCheckpoint(
      evidence: evidence,
      acceptedRevisionID: acceptedRevisionID,
      machineCameraRegistrationRevisionID: machineRegistrationRevision,
      acceptedAt: acceptedAt
    )
    let revision = LearningArtifactRevision(
      id: acceptedRevisionID,
      kind: .tipCameraRegistration,
      attemptID: attemptID,
      disposition: .succeeded,
      consumedRevisionIDs: [
        machineRegistrationRevision,
        contactObservation.artifactRevisionID,
      ]
    )
    _ = try graph.commitReplacement(revision)
    let acceptance = try TipCalibrationAcceptanceEvent(
      acceptedRevisionID: acceptedRevisionID,
      timestamp: acceptedAt,
      actor: "operator-contact-plane-revalidation"
    )
    try persistTipCheckpointIfLive(
      AcceptedTipCalibrationCheckpoint(
        registration: restored,
        acceptanceEvent: acceptance,
        surfaceExposures: try surfaceExposuresForChangedPaperTipRevalidation(
          checkpoint,
          contactObservation: observation
        )
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
        acceptanceEvent: acceptanceEvent,
        surfaceExposures: try currentPaperSparseSurfaceExposures(
          requiredPositions: Set(ToolContactCalibrationPosition.allCases)
        )
      )
      try persistTipCheckpointIfLive(checkpoint)
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
    if let blocker = liveSparseContactUnavailableReason {
      explorationError = blocker
      return
    }
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
      let acceptedRevisionID = LearningArtifactRevisionID()
      let acceptedAt = RuntimeTimestamp(
        monotonicNanoseconds: max(
          nowNanoseconds(),
          evidenceTimestamp.monotonicNanoseconds + 1
        )
      )
      let restoredRegistration = try checkpoint.registration.revalidatedSummaryFromCheckpoint(
        evidence: evidence,
        acceptedRevisionID: acceptedRevisionID,
        machineCameraRegistrationRevisionID: machineRegistrationRevision,
        acceptedAt: acceptedAt
      )
      let tipRevision = LearningArtifactRevision(
        id: acceptedRevisionID,
        kind: .tipCameraRegistration,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [machineRegistrationRevision]
      )
      _ = try graph.commitReplacement(tipRevision)
      let acceptanceEvent = try TipCalibrationAcceptanceEvent(
        acceptedRevisionID: acceptedRevisionID,
        timestamp: acceptedAt,
        actor: "operator-checkpoint-revalidation"
      )
      let refreshedCheckpoint = try AcceptedTipCalibrationCheckpoint(
        registration: restoredRegistration,
        acceptanceEvent: acceptanceEvent,
        surfaceExposures: checkpoint.surfaceExposures
      )
      try persistTipCheckpointIfLive(refreshedCheckpoint)

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

  private func currentPaperSparseSurfaceExposures(
    requiredPositions: Set<ToolContactCalibrationPosition>
  ) throws -> [LearningSurfaceExposure] {
    let paper = PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
    let exposures = surfaceExposureLedger.exposures(on: paper).filter { exposure in
      guard case .sparseTipMark(let position) = exposure.owner else { return false }
      return requiredPositions.contains(position)
    }
    let positionValues: [ToolContactCalibrationPosition] = exposures.compactMap {
      exposure in
      guard case .sparseTipMark(let position) = exposure.owner else { return nil }
      return position
    }
    let positions = Set(positionValues)
    guard positions == requiredPositions,
      exposures.count == requiredPositions.count,
      exposures.allSatisfy({ exposure in
        if case .commandedAndSettled(command: .raise, commandedState: .up) =
          exposure.penUpFinalization?.outcome
        {
          return true
        }
        return false
      })
    else {
      throw LearningPathOperationError.requiredState(
        "Accepted tip authority requires one durably finalized surface reservation for every consumed sparse mark."
      )
    }
    return exposures.sorted { lhs, rhs in
      func index(_ exposure: LearningSurfaceExposure) -> Int {
        guard case .sparseTipMark(let position) = exposure.owner else { return .max }
        return SparseTipCalibrationCoordinator.orderedPositions.firstIndex(of: position) ?? .max
      }
      return index(lhs) < index(rhs)
    }
  }

  private func surfaceExposuresForChangedPaperTipRevalidation(
    _ checkpoint: AcceptedTipCalibrationCheckpoint,
    contactObservation: ToolContactObservation
  ) throws -> [LearningSurfaceExposure] {
    let currentPaper = PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
    guard let current = surfaceExposureLedger.exposures(on: currentPaper).first(where: {
      exposure in
      guard exposure.owner == .sparseTipMark(contactObservation.calibrationPosition),
        case .sparseCalibrationCircle(let center, let radiusMM) = exposure.geometry,
        case .commandedAndSettled(command: .raise, commandedState: .up) =
          exposure.penUpFinalization?.outcome
      else { return false }
      return center == contactObservation.markGeometry.center
        && radiusMM == contactObservation.markGeometry.radiusMM
    }) else {
      throw LearningPathOperationError.requiredState(
        "The new-paper contact observation has no matching durably finalized surface reservation."
      )
    }
    if checkpoint.surfaceExposures.contains(where: { $0.id == current.id }) {
      return checkpoint.surfaceExposures
    }
    return checkpoint.surfaceExposures + [current]
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
    let liveReplacementPaper: PaperContactPlaneRevision?
    if frameMode == .simulated {
      do {
        replacementSnapshot = try await simulatedLearningRuntime.recordPaperReplaced().result.get()
      } catch {
        explorationError = "Paper replacement was refused: \(actionableDescription(error))"
        return
      }
      liveReplacementPaper = nil
    } else {
      let intentionalAcceptedSparseReplacement =
        learningSurfaceExposureRecoveryDisposition == .ready
        && tipCameraRegistration != nil
        && !reservedSparseTipPositionsOnCurrentPaper.isEmpty
      guard learningSurfaceExposureRecoveryDisposition == .paperReplacementRequired
        || intentionalAcceptedSparseReplacement
      else {
        explorationError =
          "Paper Replacement is not the recovery for the current safety-store failure. Resolve the Diagnostics blocker without changing paper authority."
        return
      }
      replacementSnapshot = nil
      let replacement = PaperContactPlaneRevision()
      guard let actions = liveLearningSurfaceExposureActions else {
        explorationError =
          "Paper replacement could not be recorded because LIVE safety-history persistence is unavailable."
        return
      }
      var durableTipWasCleared = false
      do {
        if liveLearningAuthorityManifest.tip != nil {
          _ = try commitLearningAuthorityManifest(
            mutation: LearningAuthorityManifestMutation(tip: .replace(nil))
          )
          quarantinedTipCalibrationCheckpoint = nil
          durableTipWasCleared = true
        }
        let persisted: LiveLearningSurfaceExposureSnapshot
        switch actions.load() {
        case .rejected(_, let revision):
          guard revision == liveLearningSurfaceExposureRevision else {
            throw LearningSurfaceExposureLedgerError.staleStoreRevision(
              expected: liveLearningSurfaceExposureRevision,
              actual: revision
            )
          }
          persisted = try actions.recoverForPaperReplacement(revision, replacement)
        case .absent:
          guard liveLearningSurfaceExposureRevision == .absent else {
            throw LearningSurfaceExposureLedgerError.staleStoreRevision(
              expected: liveLearningSurfaceExposureRevision,
              actual: .absent
            )
          }
          persisted = try actions.save(.absent, surfaceExposureLedger, replacement)
        case .loaded(let snapshot):
          guard snapshot.revision == liveLearningSurfaceExposureRevision else {
            throw LearningSurfaceExposureLedgerError.staleStoreRevision(
              expected: liveLearningSurfaceExposureRevision,
              actual: snapshot.revision
            )
          }
          persisted = try actions.save(
            liveLearningSurfaceExposureRevision,
            surfaceExposureLedger,
            replacement
          )
        }
        surfaceExposureLedger = persisted.checkpoint.ledger
        liveLearningSurfaceExposureRevision = persisted.revision
        liveLearningSurfaceExposureBlocker = nil
        liveLearningSurfaceStoreRecoveryDisposition = .ready
        liveReplacementPaper = replacement
      } catch {
        if durableTipWasCleared {
          var graph = learningArtifactGraph
          let invalidation = graph.invalidateCurrentRevisions(
            rootKinds: [.tipCameraRegistration]
          )
          learningArtifactGraph = graph
          applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
          tipCameraRegistration = nil
          proposedTipCameraRegistration = nil
          applyDrawingTrialAuthorityInvalidation(
            from: .chooseIsolatedLinePlan
          )
        }
        liveLearningSurfaceExposureBlocker = String(describing: error)
        if let ledgerError = error as? LearningSurfaceExposureLedgerError,
          case .staleStoreRevision = ledgerError
        {
          liveLearningSurfaceStoreRecoveryDisposition = .paperReplacementRequired
        } else {
          liveLearningSurfaceStoreRecoveryDisposition = .diagnosticsRequired
        }
        explorationError =
          "Paper replacement did not change safety authority: \(actionableDescription(error))"
        return
      }
    }

    if let owner = activeExerciseAttemptOwnerID,
      owner != .humanGuidedDiscovery(.calibrateCameraAndVisibleCap)
    {
      finishActiveExerciseAttempt(disposition: .cancelled)
    }
    var graph = learningArtifactGraph
    let currentContactKinds = Set<LearningArtifactKind>(graph.revisions.compactMap { revision in
      guard revision.state == .current,
        case .toolContactObservation = revision.kind
      else { return nil }
      return revision.kind
    })
    let invalidation = graph.invalidateCurrentRevisions(
      rootKinds: currentContactKinds.union(Set([LearningArtifactKind.tipCameraRegistration]))
    )
    learningArtifactGraph = graph
    applyArtifactInvalidations(invalidation.allInvalidatedRevisionIDs)
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    if let replacementSnapshot {
      simulatedLearningSnapshot = replacementSnapshot
      explorationToolPaperRevision = replacementSnapshot.toolPaperRevision
    } else if let liveReplacementPaper {
      explorationToolPaperRevision = liveReplacementPaper.rawValue
      persistPaperContactPlaneRevision(
        liveReplacementPaper
      )
    }
    refreshLiveTipSurfaceExposureBindingBlocker()
    sparseTipCalibrationCoordinator = SparseTipCalibrationCoordinator()
    if quarantinedTipCalibrationCheckpoint == nil, frameMode == .live {
      quarantinedTipCalibrationCheckpoint = liveLearningAuthorityManifest.tip
    }
    applyDrawingTrialAuthorityInvalidation(from: .chooseIsolatedLinePlan)
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
        (activeLearningSession.drawingTrial.lineExecution != payloadSnapshot.lineExecution
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
        let settlement =
          "\(base) Post-stroke settlement needs attention: \(error)"
        explorationError =
          commitFailure.map {
            "\(settlement) The line-execution artifact also needs attention: \($0)"
          } ?? settlement
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

  var currentOperatorNoticeMessage: String? {
    if let cameraError { return cameraError }
    if let visionError { return visionError }
    if let discoveryError { return discoveryError }
    if let explorationError { return explorationError }
    if let learningAuthorityError { return learningAuthorityError }
    if let learningAuthorityManifestError { return learningAuthorityManifestError }
    if let learningSurfaceExposureError { return learningSurfaceExposureError }
    if let learningStickyAmbiguityReason { return learningStickyAmbiguityReason }
    if let machineError { return machineError }
    if let blocker = machineSnapshot?.machine.blockers.first {
      return machineBlockerLabel(blocker)
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
    videoPresentationPreferences.setOverlay(overlay, enabled: enabled)
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
    guard frameMode == .live else { return }
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
    await refreshSerialDevices()
    switch policy.startupRoute {
    case .preferredCamera:
      await startPreferredCameraAtStartup()
    case .simulated:
      await switchFrameMode(.simulated)
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
      guard penCapAppearanceCandidateForActiveAttempt != nil,
        penCapAppearanceSelectionContext == nil,
        penInteractionSequenceUnavailableReason == nil
      else {
        discoveryError = penInteractionSequenceUnavailableReason
          ?? "Identify Pen Cap must be staged for this Pen Interaction attempt before questions begin."
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
        guard await recordDiscovery(.questionPresented, for: sequenceID) else { return }

      case .awaitOperatorChoice:
        return

      case .awaitPhysicalPenConfirmation:
        return

      case .announce(let message):
        _ = await announceAdvisory(message)
        guard activeDiscoverySequenceID == sequenceID,
          discoveryTransactions[sequenceID]?.currentStep?.id == step.id
        else { return }
        guard await recordDiscovery(.announcementCompleted, for: sequenceID) else { return }

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
          await recordDiscovery(
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
      let stopCapabilityID = pendingBoundaryStopCapabilities[attemptID],
      stopDispositionLatch?.capabilityID == stopCapabilityID,
      stopDispositionLatch?.boundaryIntent == .stopAndAccept
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
        stopIntent: .stopAndAccept,
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

      var allInvalidatedRevisionIDs = invalidatedRevisionIDs
      var stagedCenterAuthority: EstimatedCenterAuthority?
      if stagedProgress.isComplete {
        let aggregates = BoundaryDirection.allCases.compactMap { stagedAggregates[$0] }
        let center = try EstimatedMachineCenter.derive(from: aggregates)
        let localFrame = try LearnedLocalCoordinateFrame.derive(from: aggregates)
        let centerRevision = LearningArtifactRevision(
          kind: .estimatedMachineCenter,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: center.consumedRevisionIDs
        )
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
        allInvalidatedRevisionIDs.formUnion(centerCommit.invalidatedRevisionIDs)
        stagedCenterAuthority = EstimatedCenterAuthority(center: center, localFrame: localFrame)
      }

      var draft = learningAuthorityDraft(
        graph: stagedGraph,
        invalidatedRevisionIDs: allInvalidatedRevisionIDs
      )
      draft.session.boundaryAttemptHistories = stagedHistories
      draft.session.boundaryAttemptEvidenceByAttemptID[attemptID] = evidence
      draft.session.boundarySideAggregates = stagedAggregates
      draft.session.pairedBoundaryProgress = stagedProgress
      draft.session.acceptedAttemptSequence = acceptedSequence
      draft.session.discoveryTransactions[sequenceID] = stagedTransaction
      if let stagedCenterAuthority {
        draft.session.estimatedCenterAuthority = stagedCenterAuthority
      }
      draft.session.centerArrivalPosition = nil
      draft.session.centerArrivalRetryRequired = false
      if let forcedNext = stagedProgress.allowedDirections.onlyElement {
        draft.session.selectedBoundaryDirection = forcedNext
      } else if !stagedProgress.allowedDirections.contains(
        draft.session.selectedBoundaryDirection
      ), let first = stagedProgress.allowedDirections.first {
        draft.session.selectedBoundaryDirection = first
      }
      draft.session.discoveryError = nil
      draft.session.restartableExerciseItemID = nil
      draft.session.exerciseAttempt.finish()
      draft.pendingBoundaryFinalPositions.removeValue(forKey: attemptID)
      draft.pendingBoundaryOwnerIDs.removeValue(forKey: attemptID)
      draft.pendingBoundaryStopCapabilities.removeValue(forKey: attemptID)

      let checkpoint = frameMode == .live
        ? try acceptedMachineCheckpoint(for: draft.session) : nil
      if let checkpoint {
        draft.session.parkedAcceptedMachineArtifactCheckpoint = checkpoint
        draft.session.quarantinedTipCalibrationCheckpoint = nil
      }
      if let invariantError = learningAuthorityInvariantError(
        session: draft.session,
        penCapSelectionIsPresent: penCapAppearanceSelection != nil
      ) {
        throw LearningPathOperationError.requiredState(invariantError)
      }
      if let checkpoint {
        _ = try commitLearningAuthorityManifest(
          mutation: LearningAuthorityManifestMutation(
            machine: .replace(checkpoint),
            tip: .replace(nil)
          )
        )
      }
      installLearningAuthorityDraft(draft)
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
    } catch {
      await failDiscovery(
        sequenceID,
        failure: workflowFailure(for: error)
      )
    }
  }

  private func recordDiscovery(
    _ event: DiscoveryEvent,
    for sequenceID: DiscoverySequenceID
  ) async -> Bool
  {
    guard var transaction = discoveryTransactions[sequenceID] else { return false }
    do {
      try transaction.record(event)
      discoveryTransactions[sequenceID] = transaction
      if transaction.state == .succeeded {
        return await commitSuccessfulDiscoveryAttempt(sequenceID)
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
    if sequenceID == .penInteraction {
      await discardStagedPenCapAppearanceCandidate()
    }
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
    if case .pairedBoundary = activeStoppableOperation?.target {
      await terminateBoundary(.stop, capabilityID: capabilityID)
    } else {
      await terminateCurrentOperation(
        boundaryIntent: nil,
        action: "Stop",
        capabilityID: capabilityID
      )
    }
  }

  private func terminateBoundary(
    _ intent: BoundaryTerminationIntent,
    capabilityID: ContextualStopCapabilityID
  ) async {
    guard case .pairedBoundary = activeStoppableOperation?.target else { return }
    await terminateCurrentOperation(
      boundaryIntent: intent,
      action: boundaryTerminationAction(intent),
      capabilityID: capabilityID
    )
  }

  private func terminateCurrentOperation(
    boundaryIntent: BoundaryTerminationIntent?,
    action: String,
    capabilityID: ContextualStopCapabilityID
  ) async {
    guard !jogCancelRequestInProgress,
      let operation = activeStoppableOperation,
      operation.target.capabilityID == capabilityID,
      latchContextualStopDisposition(
        for: operation.target,
        boundaryIntent: boundaryIntent,
        mechanicalCancelIntent: .operatorInterruption,
        actor: "Operator",
        action: action
      )
    else { return }
    let target = operation.target
    switch target {
    case .pairedBoundary(_, let transactionID, let operationOwner, let attemptID, let direction):
      guard let boundaryIntent else { return }
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
      let recorded: Bool
      if boundaryIntent == .stopAndAccept {
        recorded = await recordDiscovery(.stopAndAcceptRequested(direction), for: sequenceID)
      } else {
        recorded = true
      }
      appendBoundaryActivity(
        actor: .operatorActor,
        direction: direction,
        phase: .stopLatched,
        disposition: .inProgress,
        attemptID: attemptID,
        operationOwnerID: operationOwner,
        stopCapabilityID: capabilityID,
        detail: .message(
          "Operator \(action) latched before controller cancellation.")
      )
      boundaryTeachingState = .cancelling(jogDirection(from: direction))
      boundaryTeachingResultText =
        "\(action) requested. Waiting for the original motion owner to reach Idle."
      await requestSingleJogCancel(for: target, mechanicalIntent: .operatorInterruption)
      await operation.owner.settle()
      if !recorded {
        if case .failed = discoveryTransactions[sequenceID]?.state {
          return
        }
        await failDiscovery(
          sequenceID,
          failure: .failed("The typed Stop & Accept event could not be recorded.")
        )
      }

    case .manualJog, .manualDrawingStroke:
      await requestSingleJogCancel(for: target, mechanicalIntent: .operatorInterruption)
      await operation.owner.settle()

    case .exerciseMotion(_, _, let ownerID, _):
      await requestSingleJogCancel(for: target, mechanicalIntent: .operatorInterruption)
      await operation.owner.settle()
      if ownerID != .humanGuidedDiscovery(.calibrateCameraAndVisibleCap) {
        finishActiveExerciseAttempt(disposition: .cancelled)
        restartableExerciseItemID = ownerID
      }

    case .drawingTrial:
      let inkMayExist = operation.owner.drawingMayHaveInk
      await requestSingleJogCancel(for: target, mechanicalIntent: .operatorInterruption)
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

    case .sparseTipMark(_, _, let exposureID):
      if let exposure = surfaceExposure(id: exposureID) {
        sparseTipCalibrationCoordinator.recordPossibleInk(
          exposure,
          reason: "Operator stopped the 2 mm calibration circle after Pen Down."
        )
      }
      await requestSingleJogCancel(for: target, mechanicalIntent: .operatorInterruption)
      await operation.owner.settle()
      explorationError =
        "Calibration circle stopped after contact. Its possible-ink exposure is retained and will not be redrawn automatically."
      restartableExerciseItemID = nil
    }
  }

  private func boundaryTerminationAction(_ intent: BoundaryTerminationIntent) -> String {
    switch intent {
    case .stopAndAccept: "Stop & Accept"
    case .stop: "Stop"
    case .cancelAttempt: "Cancel"
    }
  }

  private func requestSingleJogCancel(
    for target: ContextualStopTarget,
    mechanicalIntent: JogCancelIntent
  ) async {
    if case .simulated(let operationID) = target.operationOwner {
      guard beginCancellationRequest(for: target, mechanicalIntent: mechanicalIntent) else {
        return
      }
      defer { finishCancellationRequest(for: target) }
      let simulatedIntent: SimulatedLearningOperationIntent =
        switch mechanicalIntent {
        case .operatorInterruption: .stop
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
    if mechanicalIntent == .shutdown {
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
    guard beginCancellationRequest(for: target, mechanicalIntent: mechanicalIntent) else { return }
    defer { finishCancellationRequest(for: target) }
    let outcome = await machineActions.requestJogCancel(mechanicalIntent)
    updateContextualStopAudit(for: target, outcome: String(describing: outcome))
    let snapshot = await machineActions.snapshot()
    if let generation {
      guard canCommit(generation) else { return }
      machineSnapshot = snapshot
    }
  }

  private func latchContextualStopDisposition(
    for target: ContextualStopTarget,
    boundaryIntent: BoundaryTerminationIntent?,
    mechanicalCancelIntent: JogCancelIntent,
    actor: String,
    action: String
  ) -> Bool {
    guard var operation = activeStoppableOperation,
      operation.target.capabilityID == target.capabilityID,
      case .available = operation.state
    else { return false }
    let latch = ContextualStopDispositionLatch(
      capabilityID: target.capabilityID,
      boundaryIntent: boundaryIntent,
      mechanicalCancelIntent: mechanicalCancelIntent,
      actor: actor,
      action: action
    )
    operation.state = .latched(latch, cancellationRequestInProgress: false)
    activeStoppableOperation = operation
    lastContextualStopAuditRecord = ContextualStopAuditRecord(
      capabilityID: target.capabilityID,
      actor: actor,
      action: action,
      boundaryIntent: boundaryIntent,
      mechanicalCancelIntent: mechanicalCancelIntent,
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
    mechanicalIntent: JogCancelIntent
  ) -> Bool {
    guard var operation = activeStoppableOperation,
      operation.target.capabilityID == target.capabilityID,
      case .latched(let latch, false) = operation.state,
      latch.mechanicalCancelIntent == mechanicalIntent
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
    lastContextualStopAuditRecord = ContextualStopAuditRecord(
      capabilityID: target.capabilityID,
      actor: latch.actor,
      action: latch.action,
      boundaryIntent: latch.boundaryIntent,
      mechanicalCancelIntent: latch.mechanicalCancelIntent,
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
    let requestUnavailableReason = request.permitsUnknownPenStateAsPossibleInk
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
    let requestUnavailableReason = request.permitsUnknownPenStateAsPossibleInk
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
    let response = await (
      draws
        ? simulatedLearningRuntime.beginDrawing(delta: vector)
        : simulatedLearningRuntime.beginManualJog(
          delta: vector,
          permitsUnknownPenStateAsPossibleInk: permitsUnknownPenStateAsPossibleInk
        )
    )
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
    let priorSelectedCameraID = selectedCameraID
    cameraError = nil
    do {
      let snapshot = try await cameraActions.select(id)
      guard canCommit(generation) else { return }
      let identityChanged = priorSelectedCameraID != nil && priorSelectedCameraID != id
      frameTask?.cancel()
      frameTask = nil
      clearAutomaticVisionPresentation()
      cameraSnapshot = snapshot
      displayedFrame = nil
      latestLiveCameraFrame = nil
      if identityChanged {
        videoPresentationPreferences.unlockAnalysisROI()
        await cameraActions.setSceneAnalysisRegion(nil)
        invalidateCameraDependentLearningAuthority()
      }
      updateCameraError()
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
      videoPresentationPreferences.unlockAnalysisROI()
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
    guard let cameraActions else { return }
    let priorIdentity = displayedFrame.map(VideoViewportIdentity.init)
    if let livePenCapColor { await cameraActions.setPenCapColor(livePenCapColor) }
    let snapshot = await cameraActions.restart()
    guard canCommit(generation) else { return }
    guard case .running = snapshot.state, snapshot.error == nil else {
      cameraError = snapshot.error?.actionableDescription
        ?? "Camera restart did not return a running camera session."
      return
    }
    frameTask?.cancel()
    frameTask = nil
    clearAutomaticVisionPresentation()
    frameMode = .live
    cameraSnapshot = snapshot
    displayedFrame = cameraSnapshot?.latestFrame
    latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
    let nextIdentity = displayedFrame.map(VideoViewportIdentity.init)
    if let priorIdentity, let nextIdentity, priorIdentity != nextIdentity {
      videoPresentationPreferences.unlockAnalysisROI()
      await cameraActions.setSceneAnalysisRegion(nil)
    }
    // A successful restart always creates a new evidence session and requires
    // camera-dependent Learning revalidation. View geometry resets only when
    // the actual source/configuration identity changed.
    invalidateCameraDependentLearningAuthority()
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
    guard let cameraActions else { return }
    frameModeSwitchInProgress = true
    defer { frameModeSwitchInProgress = false }
    switch mode {
    case .live:
      if let livePenCapColor { await cameraActions.setPenCapColor(livePenCapColor) }
      let snapshot = await cameraActions.start()
      guard canCommit(generation) else { return }
      guard case .running = snapshot.state, snapshot.error == nil else {
        cameraError = snapshot.error?.actionableDescription
          ?? "The LIVE camera did not enter a running state."
        return
      }
      cancelPenCapAcceptedClickContinuation()
      frameTask?.cancel()
      frameTask = nil
      clearAutomaticVisionPresentation()
      frameMode = .live
      cameraSnapshot = snapshot
      displayedFrame = cameraSnapshot?.latestFrame
      latestLiveCameraFrame = validatedLiveCameraFrame(in: snapshot)
      videoPresentationPreferences.unlockAnalysisROI()
      await cameraActions.setSceneAnalysisRegion(nil)
      updateCameraError()
      beginFrameUpdates(generation: generation)
      await reconcileAutomaticVisionAnalysis()
    case .simulated:
      let scene: SimulatedLearningSceneFrame
      do {
        scene = try await captureSimulatedProtocolScene(using: simulatedLearningSession)
      } catch {
        guard canCommit(generation) else { return }
        cameraError = actionableDescription(error)
        return
      }
      let snapshot = await cameraActions.stop()
      guard canCommit(generation) else { return }
      guard case .stopped = snapshot.state, snapshot.error == nil else {
        cameraError = snapshot.error?.actionableDescription
          ?? "The LIVE camera did not stop for the simulated source transition."
        return
      }
      cancelPenCapAcceptedClickContinuation()
      frameTask?.cancel()
      frameTask = nil
      clearAutomaticVisionPresentation()
      cameraSnapshot = snapshot
      latestLiveCameraFrame = nil
      frameMode = .simulated
      lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
      applySimulatedProtocolScene(scene)
      explorationToolPaperRevision = scene.toolPaperRevision
      videoPresentationPreferences.unlockAnalysisROI()
      await cameraActions.setSceneAnalysisRegion(nil)
      cameraError = nil
    }
  }

  private func refreshSimulatedContent() async {
    guard frameMode == .simulated else { return }
    do {
      let priorCameraConfigurationID = displayedFrame?.frame.cameraConfigurationID
      let scene = try await captureSimulatedProtocolScene()
      lastSimulatedProtocolCaptureNanoseconds = scene.displayedFrame.frame.captureNanoseconds
      applySimulatedProtocolScene(scene)
      cameraError = nil
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
      videoPresentationPreferences.unlockAnalysisROI()
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
    _ observation: IsolatedInkObservation,
    displayedFrame: DisplayedFrame
  ) {
    overlayResultChannels.publishWorkflow(
      OverlayChannelResult(displayedFrame: displayedFrame, overlays: observation.overlays),
      source: frameMode,
      owner: .observedDrawingTrial
    )
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
      guard await recordDiscovery(.operatorChoiceAccepted(choice), for: sequenceID) else { return }
    case .awaitPhysicalPenConfirmation(let state, _):
      await awaitPendingPenSetpointActuation()
      let command: PenCommand = state == .down ? .lower : .raise
      let setpoint = effectivePenActuationProfile.value(for: command)
      let execution = activeLearningSession.lastPenExecutionByCommand[command].flatMap {
        $0.profile.value(for: command) == setpoint ? $0 : nil
      }
      let position = try? currentMachinePosition()
      let timestamp = execution?.timestamp
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
        await recordDiscovery(
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
    // The controller owner runs one finite 20 mm segment with no automatic
    // renewal. Camera and Vision do not advise direction, distance, Stop, or acceptance.
    let admittedOperation: BoundaryMotionOperation
    switch await machineActions.beginBoundaryMotion(request) {
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
      await recordDiscovery(
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
      && settlement.mechanicalCancelIntent == .operatorInterruption
      && stopDispositionLatch?.capabilityID == stopTarget.capabilityID
      && stopDispositionLatch?.boundaryIntent == .stopAndAccept:
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
        await recordDiscovery(
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
        || settlement.mechanicalCancelIntent != .operatorInterruption
        || stopDispositionLatch?.mechanicalCancelIntent != settlement.mechanicalCancelIntent
      {
        await failDiscovery(
          sequenceID,
          failure: .failed(
            "Boundary settlement owner/disposition did not match the first admitted operator action."
          )
        )
        return
      }
      guard let boundaryIntent = stopDispositionLatch?.boundaryIntent else {
        await failDiscovery(
          sequenceID,
          failure: .failed(
            "Boundary settlement had no first-winner Boundary termination intent."
          )
        )
        return
      }
      if var transaction = discoveryTransactions[sequenceID] {
        transaction.cancel()
        discoveryTransactions[sequenceID] = transaction
      }
      boundaryTeachingResultText = switch boundaryIntent {
      case .stop:
        "Boundary Discovery stopped at final MPos; no boundary evidence was accepted."
      case .cancelAttempt:
        "Boundary Discovery was cancelled; no boundary evidence was accepted."
      case .stopAndAccept:
        "Boundary Stop & Accept settlement was inconsistent; no boundary evidence was accepted."
      }
      let acceptedFallback = boundarySideAggregates[discoveryDirection]
      let attemptDisposition: ExerciseAttemptDisposition =
        boundaryIntent == .stop ? .stopped : .cancelled
      recordDiscoveryAttempt(sequenceID: sequenceID, disposition: attemptDisposition)
      appendBoundaryActivity(
        actor: .operatorActor,
        direction: discoveryDirection,
        phase: .recovery,
        disposition: boundaryIntent == .stop ? .stopped : .cancelled,
        attemptID: attemptID,
        operationOwnerID: .liveBoundary(request.ownerID),
        stopCapabilityID: stopTarget.capabilityID,
        finalPosition: settlement.finalPosition,
        retainedRevisionIDs: acceptedFallback.map { [$0.revisionID] } ?? [],
        detail: .message(
          "The owner settled after \(boundaryTerminationAction(boundaryIntent)); no Boundary sample was accepted."
        ),
        recovery: acceptedFallback != nil
          ? .continueWithAcceptedFallback(discoveryDirection)
          : .restartNormal(discoveryDirection),
        acceptedFallbackRemainsCurrent: acceptedFallback != nil
      )
      finishActiveExerciseAttempt(disposition: attemptDisposition)
      restartableExerciseItemID = boundaryIntent == .stop
        ? .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
        : nil

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
      let execution = await simulatedLearningRuntime.executeBoundarySegment(
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
      await recordDiscovery(
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
    case .stopped:
      guard stopDispositionLatch?.capabilityID == stopTarget.capabilityID,
        stopDispositionLatch?.mechanicalCancelIntent == .operatorInterruption,
        let boundaryIntent = stopDispositionLatch?.boundaryIntent
      else {
        await failDiscovery(
          sequenceID,
          failure: .failed(
            "Simulated Boundary settlement had no attributable first-winner termination intent."
          )
        )
        return
      }
      switch boundaryIntent {
      case .stopAndAccept:
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
            "Simulated Stop & Accept settled at X \(outcome.finalMPos.xMM) Y \(outcome.finalMPos.yMM). \(outcome.evidenceNotice.label)"
          guard
            await recordDiscovery(
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

      case .stop, .cancelAttempt:
        if var transaction = discoveryTransactions[sequenceID] {
          transaction.cancel()
          discoveryTransactions[sequenceID] = transaction
        }
        let acceptedFallback = boundarySideAggregates[discoveryDirection]
        let attemptDisposition: ExerciseAttemptDisposition =
          boundaryIntent == .stop ? .stopped : .cancelled
        recordDiscoveryAttempt(sequenceID: sequenceID, disposition: attemptDisposition)
        appendBoundaryActivity(
          actor: .operatorActor,
          direction: discoveryDirection,
          phase: .recovery,
          disposition: boundaryIntent == .stop ? .stopped : .cancelled,
          attemptID: attemptID,
          operationOwnerID: .simulated(operation.id),
          stopCapabilityID: stopTarget.capabilityID,
          retainedRevisionIDs: acceptedFallback.map { [$0.revisionID] } ?? [],
          detail: .message(
            "Simulated Boundary \(boundaryIntent == .stop ? "stopped" : "cancelled"); no sample was accepted."
          ),
          recovery: acceptedFallback != nil
            ? .continueWithAcceptedFallback(discoveryDirection)
            : .restartNormal(discoveryDirection),
          acceptedFallbackRemainsCurrent: acceptedFallback != nil
        )
        finishActiveExerciseAttempt(disposition: attemptDisposition)
        restartableExerciseItemID = boundaryIntent == .stop
          ? .humanGuidedDiscovery(.pairedBoundaryDiscoveryAndCentering)
          : nil
        boundaryTeachingResultText =
          "Simulated Boundary \(boundaryIntent == .stop ? "stopped" : "cancelled"); no sample accepted. \(outcome.evidenceNotice.label)"
      }

    case .failed where simulatedLearningSnapshot?.stickyAmbiguity != nil:
      await failDiscovery(
        sequenceID,
        failure: .ambiguous(
          "The simulated Boundary owner lost attributable segment completion."
        )
      )

    case .cancelled, .naturallyCompleted, .failed, .shutdown:
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
        )
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
    case .observedDrawingTrial(let step):
      observedDrawingTrialStep = step
      beginExerciseAttempt(ownerID: ownerID, mode: mode)
      if step != .compareIntendedAndObservedGeometry {
        await performCurrentLearningPathAction()
      }
    case .stage:
      break
    }
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
      stagedPenCapAppearanceCandidate = nil
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

  private func commitSuccessfulDiscoveryAttempt(_ sequenceID: DiscoverySequenceID) async -> Bool {
    guard let attemptID = activeExerciseAttemptID else { return false }
    do {
      switch sequenceID {
      case .penInteraction:
        guard let candidate = stagedPenCapAppearanceCandidate,
          candidate.attemptID == attemptID,
          candidate.attemptMode == activeExerciseAttemptMode,
          candidate.source == frameMode,
          let completedTransaction = discoveryTransactions[.penInteraction],
          completedTransaction.state == .succeeded
        else {
          throw LearningPathOperationError.requiredState(
            "The Pen Interaction attempt lost its exact staged cap appearance."
          )
        }
        let acceptedProfile = effectivePenActuationProfile
        let sequence = acceptedAttemptSequence &+ 1
        var history = penAttemptHistory
        let replacedPenRevision = learningArtifactGraph.currentRevision(for: .penInteraction)
        try recordAttempt(
          ExerciseAttempt(
            id: attemptID,
            disposition: .succeeded,
            compatibility: history.compatibility,
            acceptedSequence: sequence,
            value: PenInteractionAttemptEvidence(
              actuationProfile: acceptedProfile,
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
          replacingAttemptID: replacedPenRevision?.attemptID
        )

        var graph = learningArtifactGraph
        let appearanceCommit = try graph.commitReplacement(
          LearningArtifactRevision(
            kind: .penCapAppearance,
            attemptID: attemptID,
            disposition: .succeeded
          )
        )
        let penCandidate = LearningArtifactRevision(
          kind: .penInteraction,
          attemptID: attemptID,
          disposition: .succeeded,
          consumedRevisionIDs: [appearanceCommit.currentRevision.id]
        )
        let penCommit: LearningArtifactCommit
        if let replacedPenRevision,
          graph.revision(id: replacedPenRevision.id)?.state == .invalidated
        {
          penCommit = try graph.commitReplacement(
            penCandidate,
            supersedingInvalidatedRevision: replacedPenRevision.id
          )
        } else {
          penCommit = try graph.commitReplacement(penCandidate)
        }
        let invalidatedRevisionIDs = appearanceCommit.invalidatedRevisionIDs
          .union(penCommit.invalidatedRevisionIDs)
        var draft = learningAuthorityDraft(
          graph: graph,
          invalidatedRevisionIDs: invalidatedRevisionIDs
        )
        draft.session.penAttemptHistory = history
        draft.session.discoveryTransactions[.penInteraction] = completedTransaction
        draft.session.penActuationProfile = acceptedProfile
        draft.session.penActuationDraft = nil
        draft.session.acceptedAttemptSequence = sequence
        draft.session.discoveryError = nil
        draft.session.restartableExerciseItemID = nil
        draft.session.exerciseAttempt.finish()
        let invalidatesTip = invalidatedRevisionIDs.contains { revisionID in
          graph.revision(id: revisionID)?.kind == .tipCameraRegistration
        }
        let clearsDurableTip = frameMode == .live
          && (activeExerciseAttemptMode == .replacement
            || invalidatesTip
            || liveLearningAuthorityManifest.tip != nil)
        if clearsDurableTip {
          draft.session.quarantinedTipCalibrationCheckpoint = nil
        }
        if let invariantError = learningAuthorityInvariantError(
          session: draft.session,
          penCapSelectionIsPresent: true
        ) {
          throw LearningPathOperationError.requiredState(invariantError)
        }

        // The durable authority compare-and-swap is the commit point. Until it
        // succeeds, the accepted cap, graph, preference, and prior tip fallback
        // all remain untouched.
        if clearsDurableTip {
          _ = try commitLearningAuthorityManifest(
            mutation: LearningAuthorityManifestMutation(tip: .replace(nil))
          )
        }

        switch candidate.source {
        case .live:
          livePenCapAppearanceSelection = candidate.selection
          persistedPenCapAppearanceLoadState = .accepted
          persistPenCapAppearanceSelection(candidate.selection)
        case .simulated:
          simulatedPenCapAppearanceSelection = candidate.selection
        }
        installLearningAuthorityDraft(draft)
        stagedPenCapAppearanceCandidate = nil
        if candidate.source == .live {
          await reconcileAutomaticVisionAnalysis()
        }
        return true

      case .boundaryNegativeX, .boundaryPositiveX, .boundaryNegativeY, .boundaryPositiveY:
        // Boundary sequences commit their complete staged authority directly in
        // `commitBoundaryObservation`; reaching this callback would split the
        // transaction from its accepted aggregate.
        return true
      }
    } catch {
      await discardStagedPenCapAppearanceCandidate()
      recordDiscoveryAttempt(
        sequenceID: sequenceID,
        disposition: .failed("Atomic accepted-artifact commit failed: \(error)")
      )
      discoveryError = "Accepted discovery artifact could not commit: \(error)"
      restartableExerciseItemID = learningPathItemID(for: sequenceID)
      finishActiveExerciseAttempt(disposition: .failed(String(describing: error)))
      return false
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
      guard activeLearningSession.drawingTrial.linePlan != nil else {
        throw LearningPathOperationError.requiredState("Line-plan payload is unavailable.")
      }
      kind = .linePlan(group)
      dependencies = [try required(.tipCameraRegistration)]
    case .captureLocalPreLineBaseline:
      guard activeLearningSession.drawingTrial.localPreLineContext != nil else {
        throw LearningPathOperationError.requiredState("Local pre-line context is unavailable.")
      }
      kind = .localPreLineContext(group)
      dependencies = [
        try required(.linePlan(group)), try required(.tipCameraRegistration),
      ]
    case .moveToLineStart:
      guard activeLearningSession.drawingTrial.lineStartArrival != nil else {
        throw LearningPathOperationError.requiredState("Line-start arrival is unavailable.")
      }
      kind = .lineStartArrival(group)
      dependencies = [
        try required(.linePlan(group)), try required(.localPreLineContext(group)),
      ]
    case .drawIsolatedLine:
      guard activeLearningSession.drawingTrial.lineExecution != nil else {
        throw LearningPathOperationError.requiredState("Line-execution payload is unavailable.")
      }
      kind = .lineExecution(group)
      dependencies = [
        try required(.linePlan(group)), try required(.localPreLineContext(group)),
        try required(.lineStartArrival(group)),
      ]
    case .revealAndObserveNewInk:
      guard activeLearningSession.drawingTrial.postLineObservation?.observation.residual != nil
      else {
        throw LearningPathOperationError.requiredState(
          "Post-line observation and residual payload are unavailable."
        )
      }
      kind = .postLineObservation(group)
      dependencies = [
        try required(.lineExecution(group)),
        try required(.localPreLineContext(group)),
        try required(.tipCameraRegistration),
      ]
    case .compareIntendedAndObservedGeometry:
      kind = .comparison(group)
      dependencies = [try required(.postLineObservation(group))]
    }
    let primary = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: kind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: dependencies
      )
    )
    learningArtifactGraph = graph
    applyArtifactInvalidations(primary.invalidatedRevisionIDs)
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
    guard let observation = graph.currentRevision(
      for: .postLineObservation(currentDrawingTrialGroup)
    )?.id,
      activeLearningSession.drawingTrial.postLineObservation?.observation.residual != nil
    else {
      throw LearningPathOperationError.requiredState(
        "The atomic post-line observation and residual are required.")
    }
    let commit = try graph.commitReplacement(
      LearningArtifactRevision(
        kind: comparisonKind,
        attemptID: attemptID,
        disposition: .succeeded,
        consumedRevisionIDs: [observation]
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
      case .penCapAppearance:
        if frameMode == .live {
          livePenCapAppearanceSelection = nil
          persistedPenCapAppearanceLoadState = .absent
          persistPenCapAppearanceSelection(nil)
        } else {
          simulatedPenCapAppearanceSelection = nil
        }
      case .penInteraction:
        penAttemptHistory = try! ExerciseAttemptHistory(
          compatibility: penAttemptHistory.compatibility
        )
        discoveryTransactions.removeValue(forKey: .penInteraction)
      case .boundarySideAggregate(let direction):
        if let aggregate = boundarySideAggregates.removeValue(forKey: direction) {
          for attemptID in aggregate.includedAttemptIDs {
            boundaryAttemptEvidenceByAttemptID.removeValue(forKey: attemptID)
            pendingBoundaryFinalPositions.removeValue(forKey: attemptID)
            pendingBoundaryOwnerIDs.removeValue(forKey: attemptID)
            pendingBoundaryStopCapabilities.removeValue(forKey: attemptID)
          }
        }
        boundaryAttemptHistories.removeValue(forKey: direction)
        discoveryTransactions.removeValue(forKey: sequenceID(for: direction))
        var progress = PairedBoundaryProgress()
        for remainingDirection in pairedBoundaryProgress.acceptedDirections {
          guard let aggregate = boundarySideAggregates[remainingDirection] else { continue }
          try? progress.accept(remainingDirection, revisionID: aggregate.revisionID)
        }
        pairedBoundaryProgress = progress
      case .estimatedMachineCenter:
        activeLearningSession.estimatedCenterAuthority = nil
        centerArrivalPosition = nil
        centerArrivalRetryRequired = false
      case .centerArrival:
        centerArrivalPosition = nil
        centerArrivalRetryRequired = false
      case .machineCameraRegistration:
        machineCameraRegistration = nil
        proposedMachineCameraRegistration = nil
        explicitRegistrationCapAnchorEvidence = []
      case .toolContactObservation:
        sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
        activeLearningSession.toolContactSelection.clear()
      case .tipCameraRegistration:
        tipCameraRegistration = nil
        proposedTipCameraRegistration = nil
        setObservedDrawingTrialStepEarlier(ifNeeded: .chooseIsolatedLinePlan)
      case .localPreLineContext(let group):
        if group == currentDrawingTrialGroup {
          activeLearningSession.drawingTrial.localPreLineContext = nil
        }
        setObservedDrawingTrialStepEarlier(ifNeeded: .captureLocalPreLineBaseline)
      case .lineStartArrival(let group):
        if group == currentDrawingTrialGroup {
          activeLearningSession.drawingTrial.lineStartArrival = nil
          lastProtocolPoseSettlement = nil
        }
        setObservedDrawingTrialStepEarlier(ifNeeded: .moveToLineStart)
      case .linePlan(let group):
        if group == currentDrawingTrialGroup {
          activeLearningSession.drawingTrial.linePlan = nil
          activeLearningSession.drawingTrial.currentEpisode = nil
        }
        setObservedDrawingTrialStepEarlier(ifNeeded: .chooseIsolatedLinePlan)
      case .lineExecution(let group):
        if group == currentDrawingTrialGroup {
          activeLearningSession.drawingTrial.lineExecution = nil
        }
        setObservedDrawingTrialStepEarlier(ifNeeded: .drawIsolatedLine)
      case .postLineObservation(let group):
        if group == currentDrawingTrialGroup {
          activeLearningSession.drawingTrial.postLineObservation = nil
          drawingTrialAssessment = nil
          overlayResultChannels.clearWorkflow(source: frameMode, owner: .observedDrawingTrial)
        }
        setObservedDrawingTrialStepEarlier(ifNeeded: .revealAndObserveNewInk)
      case .comparison(let group):
        if group == currentDrawingTrialGroup {
          drawingTrialAssessment = nil
          comparisonAttemptHistories = comparisonAttemptHistories.filter {
            $0.key.group != group
          }
        }
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


  private func drawingArtifactKind(
    for step: ObservedDrawingTrialStep
  ) -> LearningArtifactKind {
    switch step {
    case .chooseIsolatedLinePlan: .linePlan(currentDrawingTrialGroup)
    case .captureLocalPreLineBaseline: .localPreLineContext(currentDrawingTrialGroup)
    case .moveToLineStart: .lineStartArrival(currentDrawingTrialGroup)
    case .drawIsolatedLine: .lineExecution(currentDrawingTrialGroup)
    case .revealAndObserveNewInk: .postLineObservation(currentDrawingTrialGroup)
    case .compareIntendedAndObservedGeometry: .comparison(currentDrawingTrialGroup)
    }
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
      videoPresentationPreferences.unlockAnalysisROI()
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
    motionGuardActivationInProgress = false
    lastMotionGuardActivationText = "not activated"
    currentCameraCalibrationFailure = nil
    boundaryTeachingState = .idle
    boundaryTeachingResultText = "Choose one side to begin."
    await clearDiscoveryAuthority()
  }

  private func acceptedMachineCheckpoint(
    for session: LearningSessionState
  ) throws -> AcceptedMachineArtifactCheckpoint {
    guard let passiveProbeResult,
      passiveProbeResult.blockers.isEmpty,
      let machinePosition = machineSnapshot?.machine.position,
      !session.boundarySideAggregates.isEmpty
    else {
      throw LearningPathOperationError.requiredState(
        "Fresh controller context, MPos, and accepted Boundary data are required for the durable machine manifest."
      )
    }
    let context = try ControllerCheckpointContext(probe: passiveProbeResult)
    let aggregates = BoundaryDirection.allCases.compactMap {
      session.boundarySideAggregates[$0]
    }
    let acceptedEvidence = aggregates.flatMap { aggregate in
      aggregate.includedAttemptIDs.compactMap {
        session.boundaryAttemptEvidenceByAttemptID[$0]
      }
    }
    let allowedKinds: Set<LearningArtifactKind> = Set(
      BoundaryDirection.allCases.map(LearningArtifactKind.boundarySideAggregate)
        + [.estimatedMachineCenter, .centerArrival]
    )
    let revisions = session.learningArtifactGraph.revisions.filter {
      $0.state == .current && allowedKinds.contains($0.kind)
    }
    return try AcceptedMachineArtifactCheckpoint(
      controllerContext: context,
      machinePositionAtSave: machinePosition,
      controllerSessionID: session.controllerSessionID,
      coordinateRevision: session.explorationCoordinateRevision,
      acceptedAttemptSequence: session.acceptedAttemptSequence,
      pairedBoundaryProgress: session.pairedBoundaryProgress,
      acceptedBoundaryEvidence: acceptedEvidence,
      boundarySideAggregates: aggregates,
      estimatedMachineCenter: session.estimatedCenterAuthority?.center,
      learnedLocalCoordinateFrame: session.estimatedCenterAuthority?.localFrame,
      centerArrivalPosition: session.centerArrivalPosition,
      acceptedRevisions: revisions
    )
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
        learningAuthorityError =
          "Stored machine authority is incompatible with the current controller: \(reason)"
      case .compatible:
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
        if let center = checkpoint.estimatedMachineCenter,
          let localFrame = checkpoint.learnedLocalCoordinateFrame
        {
          activeLearningSession.estimatedCenterAuthority = EstimatedCenterAuthority(
            center: center,
            localFrame: localFrame
          )
        } else {
          activeLearningSession.estimatedCenterAuthority = nil
        }
        centerArrivalPosition = checkpoint.centerArrivalPosition
        centerArrivalRetryRequired = false
        learningArtifactGraph = graph
        controllerSessionID = checkpoint.controllerSessionID
        explorationCoordinateRevision = checkpoint.coordinateRevision
        acceptedAttemptSequence = checkpoint.acceptedAttemptSequence
        learningAuthorityError = nil
      }
    } catch {
      learningAuthorityError = "Fresh controller revalidation failed: \(error)"
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
    tipCameraRegistration = nil
    proposedTipCameraRegistration = nil
    sparseTipCalibrationCoordinator = freshSparseTipCalibrationCoordinatorForCurrentPaper()
    activeLearningSession.toolContactSelection.clear()
    if frameMode == .live {
      quarantinedTipCalibrationCheckpoint = liveLearningAuthorityManifest.tip
    }
    applyDrawingTrialAuthorityInvalidation(from: .chooseIsolatedLinePlan)
    explorationError = nil
    overlayResultChannels.clearWorkflow(source: frameMode)
    // Pen current state, accepted boundary controller MPos revisions, estimated
    // center, and accepted center arrival belong to the unchanged controller
    // session/coordinate authority and deliberately survive camera replacement.
  }

  private func freshSparseTipCalibrationCoordinatorForCurrentPaper()
    -> SparseTipCalibrationCoordinator
  {
    var coordinator = SparseTipCalibrationCoordinator()
    let trustedCheckpoint = frameMode == .live
      ? liveLearningAuthorityManifest.tip : quarantinedTipCalibrationCheckpoint
    let trustedExposures = trustedCheckpoint.map { checkpoint in
      checkpoint.isSurfaceExposureBound(to: surfaceExposureLedger)
        ? Set(checkpoint.surfaceExposures) : []
    } ?? []
    if let unmatched = surfaceExposureLedger.exposures(
      on: PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
    ).first(where: { exposure in
      guard case .sparseTipMark = exposure.owner else { return false }
      return !trustedExposures.contains(exposure)
    }) {
      coordinator.recordPossibleInk(
        unmatched,
        reason:
          "Possible-ink calibration exposure remains on this paper. Record paper replacement before calibration continues."
      )
    }
    return coordinator
  }

  private func applyDrawingTrialAuthorityInvalidation(
    from step: ObservedDrawingTrialStep
  ) {
    if step.rawValue <= ObservedDrawingTrialStep.moveToLineStart.rawValue {
      lastProtocolPoseSettlement = nil
    }
    if step.rawValue <= ObservedDrawingTrialStep.revealAndObserveNewInk.rawValue {
      overlayResultChannels.clearWorkflow(source: frameMode, owner: .observedDrawingTrial)
    }
    activeLearningSession.drawingTrial.invalidatePayload(from: step, source: frameMode)
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
    activeLearningSession.estimatedCenterAuthority = nil
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
        boundaryIntent: .cancelAttempt,
        mechanicalCancelIntent: .operatorInterruption,
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
        await requestSingleJogCancel(for: target, mechanicalIntent: .operatorInterruption)
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
    case .manualJog, .manualDrawingStroke, .exerciseMotion, .drawingTrial, .sparseTipMark:
      break
    }

    if stopDispositionLatch == nil,
      latchContextualStopDisposition(
        for: target,
        boundaryIntent: nil,
        mechanicalCancelIntent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
    {
      await requestSingleJogCancel(for: target, mechanicalIntent: .shutdown)
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

  private func drawingTrialActionUnavailableReason(
    for step: ObservedDrawingTrialStep
  ) -> String? {
    if activeExplorationOperation != nil { return "The current learning action is still in progress." }
    if step == .drawIsolatedLine, currentDrawingTrialGroupHasExposure {
      return
        "This line group already has admitted stroke exposure and cannot be redrawn. Invalidate Choose an Isolated Line Plan and select a new clear line."
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
    if step == .drawIsolatedLine, let blocker = liveLearningSurfaceExposureBlocker {
      return "LIVE drawing is blocked by the surface-exposure ledger: \(blocker)"
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
    guard !currentDrawingTrialGroupHasExposure else {
      throw LearningPathOperationError.requiredState(
        "Confirm invalidation of the exposed line group before choosing a fresh plan."
      )
    }
    let paper = PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
    let plan = try ObservedDrawingTrialLinePlan(
      direction: direction,
      domain: registration.applicabilityRectangle,
      surfaceExposureLedger: surfaceExposureLedger,
      paperContactPlane: paper
    )
    activeLearningSession.drawingTrial.linePlan = plan
    currentExplorationEpisode = ExplorationEpisode(
      sessionID: learningEvidenceSessionID,
      source: frameMode == .simulated ? .simulated : .live,
      startedNanoseconds: nowNanoseconds()
    )
    currentExplorationEpisode?.lineStartPosition = drawingTrialLineStart
  }

  private func drawingArtifactKinds(
    for group: AttemptGroupIdentity
  ) -> [LearningArtifactKind] {
    [
      .linePlan(group),
      .localPreLineContext(group),
      .lineStartArrival(group),
      .lineExecution(group),
      .postLineObservation(group),
      .comparison(group),
    ]
  }

  private func reserveLearningSurfaceExposure(
    owner: LearningSurfaceExposureOwner,
    geometry: LearningSurfaceExposureGeometry
  ) throws -> LearningSurfaceExposure {
    if frameMode == .live,
      learningSurfaceExposureRecoveryDisposition != .ready
    {
      let blocker = learningSurfaceExposureError
        ?? "Current-paper surface exposure requires explicit Paper Replacement."
      throw LearningPathOperationError.requiredState(
        "LIVE drawing is blocked because its durable surface-exposure ledger is unavailable: \(blocker)"
      )
    }
    let exposure = try LearningSurfaceExposure(
      provenance: frameMode == .live
        ? .livePossiblePhysicalInk : .simulatedNonphysical,
      paperContactPlane: PaperContactPlaneRevision(rawValue: explorationToolPaperRevision),
      owner: owner,
      geometry: geometry,
      reservedNanoseconds: nowNanoseconds()
    )
    var updated = surfaceExposureLedger
    try updated.reserve(exposure)
    if frameMode == .live {
      guard let actions = liveLearningSurfaceExposureActions else {
        throw LearningPathOperationError.requiredState(
          "LIVE drawing is blocked because surface-exposure persistence is unavailable."
        )
      }
      do {
        let snapshot = try actions.save(
          liveLearningSurfaceExposureRevision,
          updated,
          PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
        )
        liveLearningSurfaceExposureRevision = snapshot.revision
      } catch {
        liveLearningSurfaceExposureBlocker = String(describing: error)
        liveLearningSurfaceStoreRecoveryDisposition = .diagnosticsRequired
        throw LearningPathOperationError.requiredState(
          "No Pen Down was sent because the surface-exposure reservation could not be persisted: \(error)"
        )
      }
    }
    surfaceExposureLedger = updated
    if case .drawingTrial = owner {
      activeExplorationOperation?.strokeState = .possibleInk
    }
    return exposure
  }

  private func recordPenUpFinalization(
    for exposureID: LearningSurfaceExposureID,
    reason: LearningSurfacePenUpFinalizationReason,
    outcome: PenOutcome
  ) throws {
    var updated = surfaceExposureLedger
    try updated.recordPenUpFinalization(
      for: exposureID,
      finalization: LearningSurfacePenUpFinalization(
        reason: reason,
        outcome: outcome,
        attemptedNanoseconds: nowNanoseconds()
      )
    )
    if frameMode == .live {
      guard let actions = liveLearningSurfaceExposureActions else {
        throw LearningPathOperationError.requiredState(
          "The Pen-Up finalizer ran, but its durable audit port is unavailable."
        )
      }
      do {
        let snapshot = try actions.save(
          liveLearningSurfaceExposureRevision,
          updated,
          PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
        )
        liveLearningSurfaceExposureRevision = snapshot.revision
      } catch {
        liveLearningSurfaceExposureBlocker = String(describing: error)
        liveLearningSurfaceStoreRecoveryDisposition = .diagnosticsRequired
        throw LearningPathOperationError.requiredState(
          "The Pen-Up finalizer ran, but its outcome could not be persisted: \(error)"
        )
      }
    }
    surfaceExposureLedger = updated
  }

  private func surfaceExposure(
    id: LearningSurfaceExposureID
  ) -> LearningSurfaceExposure? {
    surfaceExposureLedger.entries.first { $0.id == id }
  }

  private enum PenUpFinalizationPersistenceDisposition: Hashable, Sendable {
    case durable
    case alreadyDurable
    case failed(String)

    var isDurable: Bool {
      switch self {
      case .durable, .alreadyDurable: true
      case .failed: false
      }
    }
  }

  private struct PenUpFinalizationResult: Hashable, Sendable {
    let outcome: PenOutcome
    let persistence: PenUpFinalizationPersistenceDisposition

    var audit: String {
      switch persistence {
      case .durable: "Pen-Up finalization outcome was durably recorded."
      case .alreadyDurable: "The existing Pen-Up finalization audit was retained."
      case .failed(let reason): "Pen-Up finalization audit failed: \(reason)"
      }
    }
  }

  private func finalizePenUp(
    for exposureID: LearningSurfaceExposureID,
    reason: LearningSurfacePenUpFinalizationReason,
    suppliedOutcome: PenOutcome? = nil
  ) async -> PenUpFinalizationResult {
    if let existing = surfaceExposure(id: exposureID)?.penUpFinalization {
      return PenUpFinalizationResult(
        outcome: existing.outcome,
        persistence: .alreadyDurable
      )
    }
    let outcome: PenOutcome
    if let attempted = penUpFinalizerAttemptOutcomes[exposureID] {
      outcome = attempted
    } else if let suppliedOutcome {
      outcome = suppliedOutcome
    } else if frameMode == .simulated {
      do {
        _ = try (await simulatedLearningRuntime.setPenPose(.up)).result.get()
        simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
        outcome = .commandedAndSettled(command: .raise, commandedState: .up)
      } catch {
        outcome = .ambiguous(.transport(String(describing: error)))
      }
    } else if let machineActions {
      outcome = await machineActions.requestPenActuation(.raise, currentPenActuationProfile)
      machineSnapshot = await machineActions.snapshot()
    } else {
      outcome = .refused(.notConnected)
    }
    penUpFinalizerAttemptOutcomes[exposureID] = outcome
    do {
      try recordPenUpFinalization(for: exposureID, reason: reason, outcome: outcome)
      return PenUpFinalizationResult(outcome: outcome, persistence: .durable)
    } catch {
      return PenUpFinalizationResult(
        outcome: outcome,
        persistence: .failed(String(describing: error))
      )
    }
  }

  private var reservedSparseTipPositionsOnCurrentPaper:
    Set<ToolContactCalibrationPosition>
  {
    Set(
      surfaceExposureLedger.exposures(
        on: PaperContactPlaneRevision(rawValue: explorationToolPaperRevision)
      ).compactMap { exposure in
        guard case .sparseTipMark(let position) = exposure.owner else { return nil }
        return position
      }
    )
  }

  private func captureLocalPreLineBaseline() async throws {
    guard let registration = tipCameraRegistration,
      let currentRevision = learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id,
      currentRevision == registration.acceptedRevisionID,
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
    activeLearningSession.drawingTrial.localPreLineContext = LocalPreLineContextAuthority(
      baseline: frame,
      revealPosition: revealPosition,
      tipRegistrationRevisionID: currentRevision
    )
    appendFrameEvidence(.localPreLineBaseline, frame: frame.frame)
  }

  private func moveToRecordedLineStart() async throws {
    guard let plan = activeLearningSession.drawingTrial.linePlan,
      activeLearningSession.drawingTrial.localPreLineContext != nil
    else {
      throw LearningPathOperationError.requiredState("Typed line plan is unavailable.")
    }
    let destination = plan.startPosition
    let current = try currentMachinePosition()
    let delta = try Vector2<MachineSpace>(
      dx: destination.point.x - current.point.x,
      dy: destination.point.y - current.point.y
    )
    let requiredTravel = delta.dx != 0 || delta.dy != 0
    let final: MachinePosition
    if requiredTravel {
      final = try await performSupervisedPenUpTravel(
        delta: delta,
        ownerID: .observedDrawingTrial(.moveToLineStart),
        action: .moveToLineStart
      )
    } else {
      final = current
    }
    guard
      recordProtocolPoseSettlement(
        action: .moveToLineStart,
        target: destination,
        actual: final
      ), let settlement = lastProtocolPoseSettlement,
      settlement.action == .moveToLineStart
    else {
      throw LearningPathOperationError.controllerFailed(
        "Move to Line Start settled at an incompatible MPos."
      )
    }
    activeLearningSession.drawingTrial.lineStartArrival = LineStartArrivalAuthority(
      target: destination,
      settlement: settlement,
      requiredTravel: requiredTravel
    )
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
    action: LearningMotionAction,
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
          boundaryIntent: nil,
          mechanicalCancelIntent: .shutdown,
          actor: "Application",
          action: "Shutdown"
        )
        await requestSingleJogCancel(for: target, mechanicalIntent: .shutdown)
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
        boundaryIntent: nil,
        mechanicalCancelIntent: .shutdown,
        actor: "Application",
        action: "Shutdown"
      )
      await requestSingleJogCancel(for: target, mechanicalIntent: .shutdown)
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
    guard let plan = activeLearningSession.drawingTrial.linePlan,
      activeLearningSession.drawingTrial.localPreLineContext != nil,
      activeLearningSession.drawingTrial.lineStartArrival != nil
    else {
      throw LearningPathOperationError.requiredState(
        "Move to the recorded tip-model-domain line start before drawing."
      )
    }
    let start = plan.startPosition
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
    let delta = plan.delta
    let exposure = try reserveLearningSurfaceExposure(
      owner: .drawingTrial(currentDrawingTrialGroup),
      geometry: .isolatedLine(
        startPosition: plan.startPosition,
        endPosition: plan.endPosition
      )
    )
    if frameMode == .simulated {
      applySimulatedSnapshotResponse(
        await simulatedLearningRuntime.setPenPose(.down),
        action: "Lower simulated pen for isolated line"
      )
      let response = await simulatedLearningRuntime.beginDrawing(
        delta: try SimulatedLearningMotionVector(dxMM: delta.dx, dyMM: delta.dy)
      )
      let operation: SimulatedLearningOperation
      do {
        operation = try response.result.get()
      } catch {
        _ = await finalizePenUp(
          for: exposure.id,
          reason: .drawingStrokeAdmissionRejected
        )
        throw error
      }
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
        _ = await finalizePenUp(
          for: exposure.id,
          reason: .drawingStrokeAmbiguous
        )
        throw LearningPathOperationError.possibleInk(
          "The simulated isolated-line owner lost its outcome."
        )
      }
      guard outcome.disposition == .naturallyCompleted else {
        _ = await finalizePenUp(
          for: exposure.id,
          reason: .drawingStrokeCancelled
        )
        throw LearningPathOperationError.possibleInk(
          "Simulated drawing did not complete naturally."
        )
      }
      activeExplorationOperation?.strokeState = .completedNaturally
      simulatedLearningSnapshot = await simulatedLearningRuntime.snapshot()
      let finalization = await finalizePenUp(
        for: exposure.id,
        reason: .drawingStrokeCompleted
      )
      guard finalization.persistence.isDurable else {
        throw LearningPathOperationError.requiredState(
          "The simulated line completed, but its Pen-Up audit is not durable: \(finalization.audit)"
        )
      }
      guard case .commandedAndSettled(command: .raise, commandedState: .up) =
        finalization.outcome
      else {
        throw operationError(for: finalization.outcome, possibleInk: true)
      }
      activeLearningSession.drawingTrial.lineExecution = .simulated(outcome)
      return
    }
    guard let machineActions else {
      throw LearningPathOperationError.requiredState("Recorded line start is unavailable.")
    }
    _ = await announceAdvisory("Lowering the pen for the isolated line.")
    let lower = await machineActions.requestPenActuation(.lower, currentPenActuationProfile)
    machineSnapshot = await machineActions.snapshot()
    guard case .commandedAndSettled(command: .lower, commandedState: .down) = lower else {
      switch lower {
      case .ambiguous(let ambiguity):
        let recovery = await finalizePenUp(
          for: exposure.id,
          reason: .penLowerTerminal
        )
        throw LearningPathOperationError.possibleInk(
          "Pen Down was ambiguous: \(ambiguity.actionableDescription) Pen-Up recovery: \(recovery.outcome). \(recovery.audit)"
        )
      case .refused(let refusal):
        _ = await finalizePenUp(for: exposure.id, reason: .penLowerTerminal)
        throw LearningPathOperationError.controllerRefused(refusal.actionableDescription)
      case .commandedAndSettled:
        preconditionFailure("The settled Pen Down outcome was handled by the guard.")
      }
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
      let recovery = await finalizePenUp(
        for: exposure.id,
        reason: .drawingStrokeAdmissionRejected
      )
      throw LearningPathOperationError.possibleInk(
        "The isolated-line stroke was not admitted after Pen Down: \(outcome). Pen-Up recovery: \(recovery.outcome). \(recovery.audit)"
      )
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
      activeExplorationOperation?.strokeState = .completedNaturally
      recordStrokeEvidence(evidence, outcome: .completed, summary: "Idle with final MPos")
      _ = await announceAdvisory("Raising the pen after the isolated line.")
      let finalization = await finalizePenUp(
        for: exposure.id,
        reason: .drawingStrokeCompleted
      )
      guard finalization.persistence.isDurable else {
        throw LearningPathOperationError.requiredState(
          "The line completed, but its Pen-Up audit is not durable: \(finalization.audit)"
        )
      }
      let raise = finalization.outcome
      guard case .commandedAndSettled(command: .raise, commandedState: .up) = raise else {
        throw operationError(for: raise, possibleInk: true)
      }
      activeLearningSession.drawingTrial.lineExecution = .live(evidence)
    case .cancelled(let evidence, let penRaiseOutcome):
      _ = await finalizePenUp(
        for: exposure.id,
        reason: .drawingStrokeCancelled,
        suppliedOutcome: penRaiseOutcome
      )
      activeExplorationOperation?.strokeState = .possibleInk
      recordStrokeEvidence(evidence, outcome: .cancelled, summary: "Stop settled in place")
      throw LearningPathOperationError.possibleInk(
        "Drawing stopped; controller Pen Up outcome: \(penRaiseOutcome)"
      )
    case .ambiguous(let ambiguity):
      _ = await finalizePenUp(
        for: exposure.id,
        reason: .drawingStrokeAmbiguous
      )
      throw LearningPathOperationError.possibleInk(ambiguity.actionableDescription)
    case .refused(let refusal):
      _ = await finalizePenUp(
        for: exposure.id,
        reason: .drawingStrokeRefused
      )
      throw LearningPathOperationError.controllerRefused(String(describing: refusal))
    }
  }

  private func revealAndObserveTrialInk() async throws {
    guard cameraActions != nil,
      let context = activeLearningSession.drawingTrial.localPreLineContext,
      let plan = activeLearningSession.drawingTrial.linePlan,
      let lineExecution = activeLearningSession.drawingTrial.lineExecution,
      let registration = tipCameraRegistration,
      registration.acceptedRevisionID == context.tipRegistrationRevisionID,
      learningArtifactGraph.currentRevision(for: .tipCameraRegistration)?.id
        == context.tipRegistrationRevisionID
    else {
      throw LearningPathOperationError.requiredState(
        "The local baseline, reveal pose, line plan, and exact current tip-model revision are required."
      )
    }
    let baseline = context.baseline
    let revealPosition = context.revealPosition
    let lineStart = plan.startPosition
    let registrationRevisionID = context.tipRegistrationRevisionID
    let current = try currentMachinePosition()
    let finalRevealPosition: MachinePosition
    if !protocolPositionsMatch(current, revealPosition) {
      let delta = try Vector2<MachineSpace>(
        dx: revealPosition.point.x - current.point.x,
        dy: revealPosition.point.y - current.point.y
      )
      finalRevealPosition = try await performSupervisedPenUpTravel(
        delta: delta,
        ownerID: .observedDrawingTrial(.revealAndObserveNewInk),
        action: .returnToLocalRevealPose
      )
      guard
        recordProtocolPoseSettlement(
          action: .returnToLocalRevealPose,
          target: revealPosition,
          actual: finalRevealPosition
        )
      else {
        throw LearningPathOperationError.controllerFailed(
          "Return to the local reveal pose settled at an incompatible MPos."
        )
      }
    } else {
      finalRevealPosition = current
      guard recordProtocolPoseSettlement(
        action: .returnToLocalRevealPose,
        target: revealPosition,
        actual: current
      ) else {
        throw LearningPathOperationError.controllerFailed(
          "The local reveal pose did not satisfy the accepted position tolerance."
        )
      }
    }
    guard let revealSettlement = lastProtocolPoseSettlement,
      revealSettlement.action == .returnToLocalRevealPose,
      protocolPositionsMatch(finalRevealPosition, revealPosition)
    else {
      throw LearningPathOperationError.controllerFailed(
        "Return-to-reveal settlement evidence is unavailable."
      )
    }
    let boundary = max(
      baseline.frame.captureNanoseconds,
      lineExecution.finalSampleNanoseconds ?? 0
    )
    let post = try await captureProtocolFrame(newerThan: boundary)
    displayedFrame = post
    appendFrameEvidence(.postLine, frame: post.frame)
    let lineEnd = plan.endPosition.point
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
      guard observation.residual != nil else {
        throw LearningPathOperationError.inkRejected(
          "Post-line observation did not contain the required tip-projected residual."
        )
      }
      activeLearningSession.drawingTrial.postLineObservation = PostLineObservationAuthority(
        revealSettlement: revealSettlement,
        frame: post,
        region: trialRegion,
        observation: observation
      )
      acceptInkObservation(observation, displayedFrame: post)
    case .rejected(let rejection):
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
